#!/usr/bin/env python3
"""Compare the results of babel.dates, babel.lists or babel.units with
ICU4C's for the cases of tests/icu/icu_dates.c or
tests/icu/icu_lists_units.c, allowing the differences listed in
tests/icu/known_differences.json (by operation, field and locale).

Usage: check_icu.py ICU.jsonl OURS.jsonl
  ICU.jsonl   written by icu_dates or icu_lists_units
  OURS.jsonl  the same cases with the library's results
              (test_dates ICU.jsonl --update OURS.jsonl, or test_lists,
              test_units)
Exit status 1 when a difference is not listed, or a listed one of the
operations in ICU.jsonl no longer occurs (the list must stay current).
"""
import collections
import json
import os
import sys


def result(o):
    return o['expect'] if 'expect' in o else 'error ' + o['error']


def key(case):
    """'operation field locale': the pattern, the style or the skeleton,
    the unit and width of a relative time, the list style, or the unit
    and length."""
    op, a = case['op'], case['args']
    if op == 'icu_list':
        field, locale = a[1], a[2]
    elif op == 'icu_unit':
        field, locale = a[1] + '/' + a[2], a[3]
    elif op == 'icu_unit_per':
        field, locale = a[1] + '-per-' + a[2] + '/' + a[3], a[4]
    elif op == 'icu_pattern':
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
    ops = {case['op'] for case in icu}
    stale = sorted(k for k in set(known) - set(allowed) if k.split(' ', 1)[0] in ops)
    for k in stale:
        print(f'listed but not found: {k}')
    print(f'{len(icu)} cases: {len(icu) - sum(allowed.values()) - len(unexpected)} equal, '
          f'{sum(allowed.values())} known data differences, {len(unexpected)} unexpected')
    return 1 if unexpected or stale else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
