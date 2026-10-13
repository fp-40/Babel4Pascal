#!/usr/bin/env python3
"""Compare babel.dates' results with ICU4C's for the cases of
tests/icu/icu_dates.c, allowing the differences listed in
tests/icu/known_differences.json (by operation, field and locale).

Usage: check_icu.py ICU.jsonl OURS.jsonl
  ICU.jsonl   written by icu_dates (tests/icu/icu_dates.c)
  OURS.jsonl  the same cases with babel.dates' results
              (test_dates ICU.jsonl --update OURS.jsonl)
Exit status 1 when a difference is not listed, or a listed one no
longer occurs (the list must stay current).
"""
import collections
import json
import os
import sys


def result(o):
    return o['expect'] if 'expect' in o else 'error ' + o['error']


def key(case):
    """'operation field locale': the pattern, the style or the skeleton,
    or the unit and width of a relative time."""
    op, a = case['op'], case['args']
    if op == 'icu_pattern':
        field, locale = a[2], a[3]
    elif op == 'icu_style':
        field, locale = a[2] + '/' + a[3], a[4]
    elif op == 'icu_skeleton':
        field, locale = a[0], a[3]
    else:
        field, locale = a[1] + '/' + a[2], a[3]
    return f'{op} {field} {locale}'


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'known_differences.json'), encoding='utf-8') as f:
        known = {k: v for k, v in json.load(f).items() if k != 'comment'}
    icu = [json.loads(line) for line in open(argv[1], encoding='utf-8')]
    ours = [json.loads(line) for line in open(argv[2], encoding='utf-8')]
    if len(icu) != len(ours):
        print(f'{argv[1]} has {len(icu)} cases, {argv[2]} {len(ours)}')
        return 1
    allowed = collections.Counter()
    unexpected = []
    for i, o in zip(icu, ours):
        if result(i) == result(o):
            continue
        k = key(i)
        if k in known:
            allowed[k] += 1
        else:
            unexpected.append((i, o))
    for i, o in unexpected[:30]:
        print(f"{i['op']} {json.dumps(i['args'], ensure_ascii=False)}: "
              f"ICU {result(i)!r} ours {result(o)!r}")
    stale = sorted(set(known) - set(allowed))
    for k in stale:
        print(f'listed but not found: {k}')
    print(f'{len(icu)} cases: {len(icu) - sum(allowed.values()) - len(unexpected)} equal, '
          f'{sum(allowed.values())} known data differences, {len(unexpected)} unexpected')
    return 1 if unexpected or stale else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
