#!/usr/bin/env python3
"""Compare the output of tests/data/dumpdata (the locale data as the Pascal
library loads it) with Python Babel's data for the same locales: what
babel.localedata.load returns, read through LocaleDataDict (aliases
resolved), as in a fresh process.

The reference is the oracle, Babel 2.18.0 with CLDR 47 (tools/oracle.py
downloads it into .cache/oracle).

Babel reads each locale's data from the importer
(oracle.correct_babel_data), which corrects errors of Babel's import, so
the comparison checks the encoding, merge and alias resolution of the
Pascal library against Babel's on the same data.

Usage: dumpdata | tests/python/compare_dump.py
       dumpdata --global | tests/python/compare_dump.py --global
Exit status 1 when any locale differs.
"""
import copy
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), 'tools'))
import oracle  # noqa: E402
from cldrgen.importer import EXTRA_LOCALE_KEYS  # noqa: E402

def ref_value(v):
    """Babel's value in the dump's representation."""
    from babel.dates import DateTimePattern
    from babel.localedata import LocaleDataDict
    from babel.numbers import NumberPattern
    from babel.plural import PluralRule
    if isinstance(v, (dict, LocaleDataDict)):
        return {'m': [[k, ref_value(v[k])] for k in v]}
    if isinstance(v, (list, tuple)):
        return [ref_value(x) for x in v]
    if isinstance(v, (NumberPattern, DateTimePattern)):
        return v.pattern
    if isinstance(v, PluralRule):
        return ('plural', sorted(v.rules.items()))
    return v


def ours_value(v, key=None):
    from babel.plural import PluralRule
    if isinstance(v, dict):
        return {'m': [[k, ours_value(x, k)] for k, x in v['m']]}
    if key in ('plural_form', 'ordinal_form'):
        return ('plural', sorted(PluralRule([tuple(p) for p in v]).rules.items()))
    if isinstance(v, list):
        return [ours_value(x) for x in v]
    return v


def first_difference(a, b, path=()):
    if isinstance(a, dict) and isinstance(b, dict):
        ka, kb = [k for k, _ in a['m']], [k for k, _ in b['m']]
        if ka != kb:
            extra = [k for k in ka if k not in kb][:5]
            missing = [k for k in kb if k not in ka][:5]
            return path, f'keys differ: extra {extra} missing {missing} (or order)', None
        for (k, x), (_, y) in zip(a['m'], b['m']):
            d = first_difference(x, y, path + (k,))
            if d:
                return d
        return None
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_difference(x, y, path + (i,))
            if d:
                return d
        return None
    if isinstance(a, float) or isinstance(b, float):
        return None if float(a) == float(b) else (path, a, b)
    return None if a == b and type(a) is type(b) else (path, a, b)


def main(argv):
    oracle.ensure()
    from babel import localedata
    from babel.core import get_global
    is_global = '--global' in argv
    if not is_global:
        oracle.correct_babel_data()
    count = bad = 0
    for line in sys.stdin:
        name, _, js = line.rstrip('\n').partition('\t')
        got = ours_value(json.loads(js))
        if not is_global:
            # keys babel.numbers uses that Babel does not import
            got = {'m': [kv for kv in got['m'] if kv[0] not in EXTRA_LOCALE_KEYS]}
        if is_global:
            want = ref_value(get_global(name))
        else:
            # A deep copy, so that resolving aliases does not change the
            # cached dicts that later loads copy (Babel resolves in place).
            want = ref_value(localedata.LocaleDataDict(copy.deepcopy(localedata.load(name))))
        count += 1
        d = first_difference(got, want)
        if d:
            bad += 1
            print(f'{name}: at {d[0]}: ours {d[1]!r:.150} babel {d[2]!r:.150}')
    print(f'{count} compared, {bad} differ')
    return 1 if bad or not count else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
