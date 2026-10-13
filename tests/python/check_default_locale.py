#!/usr/bin/env python3
"""Run tests/core/print_default under the locale environment variables of
each case of tests/core/default_locale.json and compare its output
(DefaultLocale and TLocale.Default for the category) with the expected
lines.

The expected results are Python Babel 2.18.0's default_locale and
Locale.default under the same variables, recorded once.

Usage: check_default_locale.py PATH/TO/print_default
Exit status 1 when any case differs.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VARS = ('LANGUAGE', 'LC_ALL', 'LC_CTYPE', 'LANG', 'LC_TIME', 'LC_MESSAGES')


def main(argv):
    prog = argv[1]
    with open(os.path.join(ROOT, 'tests', 'core', 'default_locale.json'), encoding='utf-8') as f:
        cases = json.load(f)
    bad = 0
    for case in cases:
        env, category = case['env'], case['category']
        clean = {k: v for k, v in os.environ.items() if k not in VARS}
        clean.update(env)
        got = subprocess.run([prog] + ([category] if category else []), env=clean,
                             capture_output=True, text=True, check=True).stdout.splitlines()
        if got != case['expect']:
            bad += 1
            print(f'{env} {category!r}: got {got} want {case["expect"]}')
    print(f'{len(cases)} environments compared, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
