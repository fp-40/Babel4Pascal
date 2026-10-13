#!/usr/bin/env python3
"""Generate the CLDR data units of Babel4Pascal (src/data/*.pas) from the
CLDR XML release.

  tools/gencldr.py fetch
      Download cldr-common-<version>.zip from unicode.org into
      .cache/cldr/ (checking its SHA-512) and extract it there. Prints the
      path of its common/ directory.

  tools/gencldr.py generate [--locales modern|all|ID,ID,...] [--out DIR]
      Fetch if needed, then write one unit per locale, babel.cldr_global
      and babel.cldr_all into DIR (default src/data, emptied first).
      modern (the default): the locales whose coverage level in
      common/properties/coverageLevels.txt is "modern", or that inherit
      from such a locale. all: every locale of the release. A list:
      those locales. The locales they inherit from (up to root) are
      always added.

Only the Python standard library is needed.
"""

import argparse
import hashlib
import os
import shutil
import sys
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cldrgen import encode, importer, locales, pascal

# The CLDR release the library uses.
CLDR_VERSION = "47.0"
CLDR_URL = "https://unicode.org/Public/cldr/47/cldr-common-47.zip"
CLDR_SHA512 = (
    "3b1eb2a046dae23cf16f611f452833e2a95affb1aa2ae3fa599753d229d15257"
    "7114c2ff44ca98a7f369fa41dc6f45b0d7a6647653ca79694aacfd3f3be59801"
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache", "cldr")


def fetch():
    """The common/ directory of the extracted release (downloaded once)."""
    dest = os.path.join(CACHE, f"cldr-common-{CLDR_VERSION}")
    common = os.path.join(dest, "common")
    if os.path.isdir(os.path.join(common, "main")):
        return common
    os.makedirs(CACHE, exist_ok=True)
    zip_path = os.path.join(CACHE, f"cldr-common-{CLDR_VERSION}.zip")
    if not os.path.exists(zip_path):
        print(f"downloading {CLDR_URL}", file=sys.stderr)
        urllib.request.urlretrieve(CLDR_URL, zip_path + ".part")
        os.replace(zip_path + ".part", zip_path)
    h = hashlib.sha512()
    with open(zip_path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    if h.hexdigest() != CLDR_SHA512:
        raise SystemExit(f"{zip_path}: SHA-512 mismatch; delete it and run again")
    tmp = dest + ".part"
    shutil.rmtree(tmp, ignore_errors=True)
    with zipfile.ZipFile(zip_path) as z:
        for member in z.namelist():
            # Extract only below the destination (no absolute or .. paths).
            target = os.path.realpath(os.path.join(tmp, member))
            if not target.startswith(os.path.realpath(tmp) + os.sep):
                raise SystemExit(f"{zip_path}: unsafe member {member!r}")
        z.extractall(tmp)
    os.replace(tmp, dest)
    return common


def generate(selection, outdir):
    srcdir = fetch()
    global_data = importer.parse_global(srcdir)
    imp = importer.LocaleImporter(srcdir)
    all_names = imp.locale_names()
    if selection == "modern":
        wanted = locales.modern_locales(all_names, srcdir, global_data)
    elif selection == "all":
        wanted = all_names
    else:
        wanted = [s.strip() for s in selection.split(",") if s.strip()]
        unknown = sorted(set(wanted) - set(all_names))
        if unknown:
            raise SystemExit(f"unknown locales: {', '.join(unknown)}")
    names = locales.with_ancestors(wanted, global_data)

    files = {pascal.file_name(pascal.unit_name(n)) for n in names}
    if len(files) != len(names):
        raise SystemExit("two locales map to the same unit file name")

    if os.path.isdir(outdir):
        for f in os.listdir(outdir):
            if f.startswith("babel.cldr_") and f.endswith(".pas"):
                os.remove(os.path.join(outdir, f))
    os.makedirs(outdir, exist_ok=True)

    total = 0
    blob = encode.encode(global_data)
    total += len(blob)
    pascal.write_global_unit(outdir, CLDR_VERSION, blob)
    units = []
    for name in names:
        blob = encode.encode(imp.import_locale(name))
        total += len(blob)
        units.append(
            pascal.write_locale_unit(
                outdir, CLDR_VERSION, name, locales.parent_of(name, global_data), blob
            )
        )
    pascal.write_all_unit(outdir, CLDR_VERSION, units)
    print(
        f"{len(names)} locales ({len(wanted)} selected), {total} bytes of data, in {outdir}"
    )


def main(argv):
    ap = argparse.ArgumentParser(
        description="Generate the CLDR data units of Babel4Pascal."
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("fetch")
    g = sub.add_parser("generate")
    g.add_argument("--locales", default="modern")
    g.add_argument("--out", default=os.path.join(ROOT, "src", "data"))
    args = ap.parse_args(argv[1:])
    if args.cmd == "fetch":
        print(fetch())
    else:
        generate(args.locales, args.out)


if __name__ == "__main__":
    main(sys.argv)
