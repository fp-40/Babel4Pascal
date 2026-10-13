#!/usr/bin/env python3
"""Compare the output of tests/data/dumpdata (the locale data as the Pascal
library loads it: encoded, merged along the parent chain, aliases
resolved) with the same data built here from tools/cldrgen/importer.py:
each locale's own data merged over its parent's (CLDR's parent chain,
cldrgen.locales.parent_of), dictionaries merged key by key, and the
aliases of root (months, days, quarters, eras, currency formats) resolved
against the locale's merged data. The global data is compared with
importer.parse_global as it is.

This checks the generator's encoding and the library's decoding,
inheritance and alias resolution, independently of the Pascal code.

Usage: dumpdata | tests/python/compare_dump.py
       dumpdata --global | tests/python/compare_dump.py --global
Exit status 1 when any locale differs.
"""
import copy
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from cldrgen import importer, locales  # noqa: E402
from cldrgen.model import Alias  # noqa: E402


def merge(dict1, dict2):
    """dict2 merged into dict1, key by key: a nested dictionary is merged
    into the inherited one; an alias with local additions becomes the pair
    (alias, additions), resolved later."""
    for key, val2 in dict2.items():
        if val2 is None:
            continue
        val1 = dict1.get(key)
        if isinstance(val2, dict):
            if val1 is None:
                val1 = {}
            if isinstance(val1, Alias):
                val1 = (val1, val2)
            elif isinstance(val1, tuple):
                alias, others = val1
                others = copy.copy(others)
                merge(others, val2)
                val1 = (alias, others)
            else:
                val1 = copy.copy(val1)
                merge(val1, val2)
        else:
            val1 = val2
        dict1[key] = val1


def lookup(top, keys):
    value = top
    for k in keys:
        value = resolve_alias(value, top)[k]
    return value


def resolve_alias(value, top):
    """The value an alias, or an (alias, additions) pair, stands for."""
    if isinstance(value, Alias):
        return resolve_alias(lookup(top, value.keys), top)
    if isinstance(value, tuple) and len(value) == 2 and isinstance(value[0], Alias):
        base = copy.deepcopy(resolve_alias(value[0], top))
        merge(base, value[1])
        return base
    return value


def dump_value(value, top):
    """A value in the dump's representation ({'m': [[key, value], ...]} for
    a dictionary, lists for sequences), aliases resolved."""
    value = resolve_alias(value, top)
    if isinstance(value, dict):
        return {'m': [[k, dump_value(v, top)] for k, v in value.items()]}
    if isinstance(value, (list, tuple)):
        return [dump_value(v, top) for v in value]
    return value


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
    srcdir = subprocess.run([sys.executable, '-I', os.path.join(ROOT, 'tools', 'gencldr.py'), 'fetch'],
                            check=True, capture_output=True, text=True).stdout.strip()
    global_data = importer.parse_global(srcdir)
    is_global = '--global' in argv
    imp = importer.LocaleImporter(srcdir)
    built = {}

    def build(name):
        if name not in built:
            own = imp.import_locale(name)
            if name == 'root':
                data = own
            else:
                data = copy.deepcopy(build(locales.parent_of(name, global_data)))
                merge(data, own)
            built[name] = data
        return built[name]

    count = bad = 0
    for line in sys.stdin:
        name, _, js = line.rstrip('\n').partition('\t')
        got = json.loads(js)
        if is_global:
            want = dump_value(global_data[name], global_data)
        else:
            data = copy.deepcopy(build(name))
            want = dump_value(data, data)
        count += 1
        d = first_difference(got, want)
        if d:
            bad += 1
            print(f'{name}: at {d[0]}: ours {d[1]!r:.150} importer {d[2]!r:.150}')
    print(f'{count} compared, {bad} differ')
    return 1 if bad or not count else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
