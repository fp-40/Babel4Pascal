"""Compare the output of tests/data/dumpdata (the locale data as the Pascal
library loads it: encoded, merged along the parent chain, aliases
resolved) with the same data built here from the generator's export of
the imported data (`gencldr dump`, before encoding): each locale's own
data merged over its parent's (CLDR's parent chain, as parent_of below
computes it from the global data), dictionaries merged key by key, and
the aliases of root (months, days, quarters, eras, currency formats)
resolved against the locale's merged data. The global data is compared
as the export has it.

This checks the generator's encoding and the library's decoding,
inheritance and alias resolution, independently of the Pascal code that
does them.

Usage:
  gencldr dump --global --out global.txt
  gencldr dump --out locales.txt
  dumpdata | tests/python/compare_dump.py global.txt locales.txt
  dumpdata --global | tests/python/compare_dump.py --global global.txt
Exit status 1 when any entry differs.
"""

import copy
import json
import sys


class Alias:
    """An alias of the export ({"alias": [key, ...]}): the path of keys of
    the value it stands for."""

    __slots__ = ("keys",)

    def __init__(self, keys):
        self.keys = keys


def from_export(value):
    """A value of the export as Python values: {"m": [[key, value], ...]}
    is a dict (in insertion order), {"alias": [...]} an Alias, an array a
    list."""
    if isinstance(value, dict):
        if "m" in value:
            return {k: from_export(v) for k, v in value["m"]}
        return Alias(value["alias"])
    if isinstance(value, list):
        return [from_export(v) for v in value]
    return value


def read_export(path):
    """{name: value} from the lines "name<TAB>json" of an export file."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            name, _, js = line.rstrip("\n").partition("\t")
            out[name] = from_export(json.loads(js))
    return out


def script_of(name):
    """The script subtag of a 'lang_Script' identifier, else None."""
    parts = name.split("_")
    if len(parts) == 2 and len(parts[1]) == 4 and parts[1].isalpha():
        return parts[1].title()
    return None


def parent_of(name, global_data):
    """The locale whose data `name` inherits: an explicit CLDR
    parentLocale (parent_exceptions); root for a 'lang_Script' locale
    whose script is not the language's likely script; else the
    identifier without its last subtag; root for a language alone."""
    parent = global_data["parent_exceptions"].get(name)
    if parent:
        return parent
    script = script_of(name)
    if script:
        lang = name.split("_")[0]
        likely = global_data["likely_subtags"].get(lang)
        if likely and script_of("_".join(likely.split("_")[:2])) != script:
            return "root"
    parts = name.split("_")
    return "root" if len(parts) == 1 else "_".join(parts[:-1])


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
        return {"m": [[k, dump_value(v, top)] for k, v in value.items()]}
    if isinstance(value, (list, tuple)):
        return [dump_value(v, top) for v in value]
    return value


def first_difference(a, b, path=()):
    if isinstance(a, dict) and isinstance(b, dict):
        ka, kb = [k for k, _ in a["m"]], [k for k, _ in b["m"]]
        if ka != kb:
            extra = [k for k in ka if k not in kb][:5]
            missing = [k for k in kb if k not in ka][:5]
            return (
                path,
                f"keys differ: extra {extra} missing {missing} (or order)",
                None,
            )
        for (k, x), (_, y) in zip(a["m"], b["m"]):
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
    is_global = "--global" in argv
    files = [a for a in argv[1:] if a != "--global"]
    if len(files) != (1 if is_global else 2):
        print(__doc__, file=sys.stderr)
        return 2
    global_data = read_export(files[0])
    own = {} if is_global else read_export(files[1])
    built = {}

    def build(name):
        if name not in built:
            if name == "root":
                data = own[name]
            else:
                data = copy.deepcopy(build(parent_of(name, global_data)))
                merge(data, own[name])
            built[name] = data
        return built[name]

    count = bad = 0
    for line in sys.stdin:
        name, _, js = line.rstrip("\n").partition("\t")
        got = json.loads(js)
        count += 1
        try:
            if is_global:
                want = dump_value(global_data[name], global_data)
            else:
                data = copy.deepcopy(build(name))
                want = dump_value(data, data)
        except KeyError as e:
            bad += 1
            print(f"{name}: key {e} absent (from the export, or the target of an alias)")
            continue
        d = first_difference(got, want)
        if d:
            bad += 1
            print(f"{name}: at {d[0]}: ours {d[1]!r:.150} export {d[2]!r:.150}")
    print(f"{count} compared, {bad} differ")
    return 1 if bad or not count else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
