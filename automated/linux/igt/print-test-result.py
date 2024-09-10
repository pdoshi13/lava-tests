#!/usr/bin/python3
import argparse
import sys
import json


def print_result(results):
    for test, content in results["tests"].items():
        print("<LAVA_SIGNAL_STARTTC %s>" % test)
        print(
            "************************************************************************************************************************************"
        )
        print("%-15s %s" % ("Test:", test))
        print("%-15s %s" % ("Result:", content["result"]))
        # Test result generated by igt_runner doesn't have the following values
        try:
            print("%-15s %s" % ("Command:", content["command"]))
            print("%-15s %s" % ("Environment:", content["environment"]))
            print("%-15s %s" % ("Returncode:", content["returncode"]))
        except KeyError:
            pass
        print(
            "%-15s %s" % ("Stdout:", content["out"].replace("\n", "\n                "))
        )
        print(
            "%-15s %s" % ("Stderr:", content["err"].replace("\n", "\n                "))
        )
        print(
            "%-15s %s"
            % ("dmesg:", content["dmesg"].replace("\n", "\n                "))
        )
        print(
            "<LAVA_SIGNAL_TESTCASE TEST_CASE_ID=%s RESULT=%s>"
            % (test, content["result"])
        )
        print("<LAVA_SIGNAL_ENDTC %s>" % test)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-f",
        "--json-file",
        nargs="?",
        default=sys.stdin,
        type=argparse.FileType("r", encoding="UTF-8"),
        help="Test result file in json format",
    )

    args = parser.parse_args()
    with args.json_file as data:
        results = json.load(data)

    print_result(results)
