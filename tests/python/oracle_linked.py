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
    _isolate_locale_data(localedata)
    return linked


def _isolate_locale_data(localedata):
    """Make every locale's data what a fresh process would load.

    Babel's LocaleDataDict resolves aliases by writing the resolved values
    back into the dicts it reads, and a locale's data shares nested dicts
    with its parent's cached data: reading one locale can change what a
    later child locale loads. Babel4Pascal gives the fresh-process result
    for every locale, so here each locale is built from untouched copies
    of its parents' data, and callers get their own copy."""
    import copy
    import pickle
    import threading
    from babel.core import get_global

    pristine = {}
    served = {}
    lock = threading.RLock()

    def parent_of(name):
        parent = get_global('parent_exceptions').get(name)
        if not parent:
            if localedata._is_non_likely_script(name):
                parent = 'root'
            else:
                parts = name.split('_')
                parent = 'root' if len(parts) == 1 else '_'.join(parts[:-1])
        return parent

    def build(name):
        if name in pristine:
            return pristine[name]
        with open(localedata.resolve_locale_filename(name), 'rb') as f:
            own = pickle.load(f)
        if name == 'root':
            data = own
        else:
            data = copy.deepcopy(build(parent_of(name)))
            localedata.merge(data, own)
        pristine[name] = data
        return data

    def load(name, merge_inherited=True):
        name = os.path.basename(name)
        with lock:
            if not merge_inherited:
                with open(localedata.resolve_locale_filename(name), 'rb') as f:
                    return pickle.load(f)
            if name not in served:
                served[name] = copy.deepcopy(build(name))
            return served[name]

    localedata.load = load
