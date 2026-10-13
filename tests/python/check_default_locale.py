#!/usr/bin/env python3
"""Run tests/core/print_default with different locale environment variables
and compare its output with the oracle's default_locale and Locale.default
under the same variables.

Usage: check_default_locale.py PATH/TO/print_default
Exit status 1 when any case differs.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import oracle  # noqa: E402

oracle.ensure()
from babel import Locale, core  # noqa: E402

VARS = ('LANGUAGE', 'LC_ALL', 'LC_CTYPE', 'LANG', 'LC_TIME', 'LC_MESSAGES')
CASES = [
    ({}, ''), ({'LANG': 'fr_FR.UTF-8'}, ''), ({'LANG': 'C'}, ''), ({'LANG': 'POSIX'}, ''),
    ({'LANG': 'C.UTF-8'}, ''), ({'LANGUAGE': 'de:en', 'LANG': 'fr_FR'}, ''),
    ({'LANGUAGE': ':de', 'LANG': 'fr_FR'}, ''), ({'LC_ALL': 'es_PE.UTF-8', 'LANG': 'fr'}, ''),
    ({'LANG': 'en'}, ''), ({'LANG': 'no'}, ''), ({'LANG': 'bad_locale_X'}, ''),
    ({'LANG': 'bad_locale_X', 'LC_CTYPE': 'pt_BR'}, ''), ({'LC_TIME': 'ja_JP', 'LANG': 'en'}, 'LC_TIME'),
    ({'LC_TIME': '', 'LANG': 'sv_SE'}, 'LC_TIME'), ({'LANG': 'de_DE@euro'}, ''),
    ({'LANG': 'xx_YY'}, ''), ({'LANG': 'zh_TW.Big5'}, ''), ({'LANG': 'sr_RS@latin'}, ''),
]


def oracle_result(env, category):
    saved = {v: os.environ.pop(v, None) for v in VARS}
    os.environ.update(env)
    try:
        d = core.default_locale(category or None) or ''
        try:
            loc = str(Locale.default(category or None))
        except core.UnknownLocaleError:
            loc = 'UnknownLocaleError'
        except TypeError:
            loc = 'TypeError'
        except ValueError:
            loc = 'ValueError'
        return [d, loc]
    finally:
        for v in VARS:
            os.environ.pop(v, None)
            if saved[v] is not None:
                os.environ[v] = saved[v]


def main(argv):
    prog = argv[1]
    bad = 0
    for env, category in CASES:
        want = oracle_result(env, category)
        clean = {k: v for k, v in os.environ.items() if k not in VARS}
        clean.update(env)
        got = subprocess.run([prog] + ([category] if category else []), env=clean,
                             capture_output=True, text=True, check=True).stdout.splitlines()
        if got != want:
            bad += 1
            print(f'{env} {category!r}: ours {got} babel {want}')
    print(f'{len(CASES)} environments compared, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
