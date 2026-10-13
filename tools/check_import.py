#!/usr/bin/env python3
"""Compare the data that tools/cldrgen/importer.py reads from a CLDR XML
release with the global.dat and locale-data/*.dat files of an installed
Python Babel built from the same release (Babel 2.17.0: CLDR 46).

A development check, not part of the build: it needs Babel installed. It
prints the locales whose data differ and exits with status 1 if any does.

Usage: tools/check_import.py CLDR_COMMON_DIR [LOCALE ...]
  CLDR_COMMON_DIR  the common/ directory of the extracted cldr-common zip
                   (tools/gencldr.py fetch prints it)
  LOCALE           only these locales (default: every locale of Babel)
"""
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cldrgen import importer  # noqa: E402
from cldrgen.model import Alias  # noqa: E402


def babel_norm(o):
    """Babel's pickled values in the importer's representation."""
    from babel.dates import DateTimePattern
    from babel.localedata import Alias as BabelAlias
    from babel.numbers import NumberPattern
    from babel.plural import PluralRule
    if isinstance(o, dict):
        return {k: babel_norm(v) for k, v in o.items() if k != '_version'}
    if isinstance(o, (list, tuple)):
        return [babel_norm(x) for x in o]
    if isinstance(o, BabelAlias):
        return ('alias', list(o.keys))
    if isinstance(o, PluralRule):
        return ('plural', sorted(o.rules.items()))
    if isinstance(o, (NumberPattern, DateTimePattern)):
        return o.pattern
    return o


def ours_norm(o, key=None):
    from babel.plural import PluralRule
    if isinstance(o, dict):
        return {k: ours_norm(v, k) for k, v in o.items()}
    if key in ('plural_form', 'ordinal_form'):
        return ('plural', sorted(PluralRule(o).rules.items()))
    if isinstance(o, list):
        return [ours_norm(x) for x in o]
    if isinstance(o, Alias):
        return ('alias', list(o.keys))
    return o


def first_difference(a, b, path=()):
    """Path and values of the first difference, comparing key order too."""
    if isinstance(a, dict) and isinstance(b, dict):
        if list(a) != list(b):
            return path, f'keys {list(a)[:6]}...', f'keys {list(b)[:6]}...'
        for k in a:
            d = first_difference(a[k], b[k], path + (k,))
            if d:
                return d
        return None
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_difference(x, y, path + (i,))
            if d:
                return d
        return None
    return None if a == b and type(a) is type(b) else (path, a, b)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    import babel
    babel_dir = os.path.dirname(babel.__file__)
    srcdir = argv[1]
    bad = 0

    g_ours = ours_norm(importer.parse_global(srcdir))
    with open(os.path.join(babel_dir, 'global.dat'), 'rb') as f:
        g_babel = babel_norm(pickle.load(f))
    d = first_difference(g_ours, g_babel)
    if d:
        bad += 1
        print('global:', d)

    imp = importer.LocaleImporter(srcdir)
    names = argv[2:] or sorted(os.path.splitext(n)[0]
                               for n in os.listdir(os.path.join(babel_dir, 'locale-data'))
                               if n.endswith('.dat'))
    for name in names:
        with open(os.path.join(babel_dir, 'locale-data', name + '.dat'), 'rb') as f:
            want = babel_norm(pickle.load(f))
        got = ours_norm(imp.import_locale(name))
        d = first_difference(got, want)
        if d:
            bad += 1
            print(f'{name}: at {d[0]}: ours {d[1]!r:.120} babel {d[2]!r:.120}')
    print(f'{len(names)} locales and global data compared, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
