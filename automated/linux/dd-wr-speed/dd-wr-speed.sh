#!/bin/sh -e

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOG_FILE="${OUTPUT}/output.txt"
export RESULT_FILE
create_out_dir "${OUTPUT}"

ITERATION="5"

usage() {
    echo "Usage: $0 [-p <partition>] [-t <type>] [-i <iteration>] [-s <true>]" 1>&2
    exit 1
}

while getopts "p:t:i:s:" o; do
  case "$o" in
    # The current working directory will be used by default.
    # Use '-p' specify partition that used for dd test.
    p) PARTITION="${OPTARG}" ;;
    # CAUTION: if FS_TYPE not equal to the existing fs type of the partition
    # specified with '-p', the partition will be formatted.
    t) FS_TYPE="${OPTARG}" ;;
    # You may need to run dd test 4-5 times for an accurate evaluation.
    i) ITERATION="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    *) usage ;;
  esac
done

install() {
    dist_name
    case "${dist}" in
      debian|ubuntu|elxr) install_deps "e2fsprogs dosfstools" "${SKIP_INSTALL}";;
      unknown) warn_msg "Unsupported distro: package install skipped" ;;
    esac
}

prepare_partition() {
    if [ -n "${PARTITION}" ]; then
        device_attribute="$(blkid | grep "${PARTITION}")"
        [ -z "${device_attribute}" ] && {
            echo "y" | mkfs -t vfat -F 32 "${PARTITION}"
            device_attribute="$(blkid | grep "${PARTITION}")"
        }

        fs_type=$(echo "${device_attribute}" \
            | grep "TYPE=" \
            | awk '{print $4}' \
            | awk -F '"' '{print $2}')

        # If PARTITION specified, its FS_TYPE needs to be specified explicitly.
        [ -z "${FS_TYPE}" ] && \
            error_msg "Please specify ${PARTITION} filesystem with -t"
        umount "${PARTITION}" &>/dev/null
        format_partitions "${PARTITION}" "${FS_TYPE}"

        # Mount the partition and enter its mount point.
        mount_point="$(df |grep "${PARTITION}" | awk '{print $NF}')"
        if [ -z "${mount_point}" ]; then
            mount_point="/mnt"
            mount "${PARTITION}" "${mount_point}"
            info_msg "${PARTITION} mounted to ${mount_point}"
        fi
        cd "${mount_point}"
    fi
}

dd_write() {
    echo
    echo "--- dd write speed test ---"
    rm -f dd-write-output.txt
    for i in $(seq "${ITERATION}"); do
        echo "Running iteration ${i}..."
        rm -f dd.img
        echo 3 > /proc/sys/vm/drop_caches
        dd if=/dev/zero of=dd.img bs=1048576 count=1024 conv=fsync 2>&1 \
            | tee  -a "${OUTPUT}"/dd-write-output.txt
    done
}

dd_read() {
    echo
    echo "--- dd read speed test ---"
    rm -f dd-read-output.txt
    for i in $(seq "${ITERATION}"); do
        echo "Running iteration ${i}..."
        echo 3 > /proc/sys/vm/drop_caches
        dd if=dd.img of=/dev/null bs=1048576 count=1024 2>&1 \
            | tee -a "${OUTPUT}"/dd-read-output.txt
    done
    rm -f dd.img
}

parse_output() {
    test_case_id="$1"
    if ! [ -f "${OUTPUT}/${test_case_id}-output.txt" ]; then
        warn_msg "${test_case_id} output file is missing"
        return 1
    fi

    itr=1
    while read -r line; do
        if echo "${line}" | grep -q -E "(M|G)B/s"; then
            measurement="$(echo "${line}" | awk '{print $(NF-1)}')"
            units="$(echo "${line}" | awk '{print substr($NF,1,2)}')"
            result=$(convert_to_mb "${measurement}" "${units}")

            add_metric "${test_case_id}-itr${itr}" "pass" "${result}" "MB/s"
            itr=$(( itr + 1 ))
        fi
    done < "${OUTPUT}/${test_case_id}-output.txt"

    # For mutiple times dd test, calculate the mean, min and max values.
    # Save them to result.txt.
    if [ "${ITERATION}" -gt 1 ]; then
        eval "$(grep "${test_case_id}" "${OUTPUT}"/result.txt \
            | awk '{
                       if(min=="") {min=max=$3};
                       if($3>max) {max=$3};
                       if($3< min) {min=$3};
                       total+=$3; count+=1;
                   }
               END {
                       print "mean="total/count, "min="min, "max="max;
                   }')"

        # shellcheck disable=SC2154
        add_metric "${test_case_id}-mean"  "pass" "${mean}" "MB/s"
        # shellcheck disable=SC2154
        add_metric "${test_case_id}-min" "pass" "${min}" "MB/s"
        # shellcheck disable=SC2154
        add_metric "${test_case_id}-max" "pass" "${max}" "MB/s"
    fi
}

install

# Test run.
echo && {
    ! check_root && error_msg "This script must be run as root"
    prepare_partition
    info_msg "dd test directory: $(pwd)"
    dd_write 
    parse_output "dd-write"
    dd_read
    parse_output "dd-read"
} | tee ${LOG_FILE}
