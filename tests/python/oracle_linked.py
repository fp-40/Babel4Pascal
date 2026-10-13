"""The oracle (Python Babel 2.18.0, tools/oracle.py) limited to the locales
that the Pascal test programs link (the data units in src/data), so that
Locale.parse chooses among the same locales on both sides.

    import oracle_linked
    LINKED = oracle_linked.setup()     # the set of linked identifiers
    from babel import ...
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import oracle  # noqa: E402


def linked_locales():
    names = set()
    for path in glob.glob(os.path.join(ROOT, 'src', 'data', 'babel.cldr_*.pas')):
        with open(path, encoding='utf-8') as f:
            m = re.search(r"RegisterLocaleData\('([^']+)'", f.read())
        if m:
            names.add(m.group(1))
    if not names:
        raise SystemExit('no data units in src/data (tools/gencldr.py generate)')
    return names


def setup():
    oracle.ensure()
    from babel import localedata
    linked = linked_locales()
    identifiers = sorted(linked - {'root'})

    def exists(name):
        if not name or not isinstance(name, str):
            return False
        return name in linked or bool(localedata.normalize_locale(name))

    localedata.locale_identifiers = lambda: identifiers
    localedata.exists = exists
    return linked
