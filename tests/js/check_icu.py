"""Compare babel.numbers' results with ICU's for the cases of
tests/js/icu_numbers.mjs, allowing the differences listed (by operation
and locale) in tests/js/icu_known_differences.json.

Usage: check_icu.py ICU.jsonl OURS.jsonl
  ICU.jsonl   written by tests/js/icu_numbers.mjs
  OURS.jsonl  the same cases with babel.numbers' results
              (test_numbers ICU.jsonl --update OURS.jsonl)
Exit status 1 when a difference is not listed.
"""

import collections
import json
import os
import sys


def result(o):
    return o["expect"] if "expect" in o else "error " + o["error"]


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "icu_known_differences.json"), encoding="utf-8") as f:
        known = json.load(f)
    icu = [json.loads(line) for line in open(argv[1], encoding="utf-8")]
    ours = [json.loads(line) for line in open(argv[2], encoding="utf-8")]
    assert len(icu) == len(ours)
    allowed = collections.Counter()
    unexpected = []
    for i, o in zip(icu, ours):
        if result(i) == result(o):
            continue
        args = i["args"]
        locale = args[2] if i["op"] == "icu_currency" else args[1]
        key = f"{i['op']} {locale}"
        if key in known:
            allowed[key] += 1
        else:
            unexpected.append((i, o))
    for i, o in unexpected[:30]:
        print(
            f"{i['op']} {json.dumps(i['args'], ensure_ascii=False)}: ICU {result(i)!r} ours {result(o)!r}"
        )
    print(
        f"{len(icu)} cases: {len(icu) - sum(allowed.values()) - len(unexpected)} equal, "
        f"{sum(allowed.values())} known data differences, {len(unexpected)} unexpected"
    )
    return 1 if unexpected else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
