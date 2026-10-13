#!/bin/sh
# Runs every check of Babel4Pascal. Exit status 0 only when all pass.
#
# 1. Generator unit tests (tests/python/test_cldrgen.py).
# 2. The importer against the data files of the oracle, Python Babel 2.18.0
#    (tools/check_import.py): every locale of the release.
# 3. The Pascal library's loaded data against the oracle's
#    (tests/data/dumpdata + tests/python/compare_dump.py): every generated
#    locale, and the global data.
#
# The CLDR release (.cache/cldr) and the oracle's wheel (.cache/oracle)
# are downloaded once when absent.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT=$ROOT/build
mkdir -p "$OUT/units" "$OUT/bin"
COMMON=$(python3 -I tools/gencldr.py fetch)

echo "== generator tests"
python3 -I tests/python/test_cldrgen.py

echo "== importer vs Babel's data files"
# Run from /tmp: Python must not import modules from this checkout's cwd.
check() { # name, command...: run, show the last lines, fail on failure
  name=$1; shift
  if (cd /tmp && "$@") > "$OUT/$name.log" 2>&1; then tail -n 3 "$OUT/$name.log"
  else tail -n 20 "$OUT/$name.log"; echo "FAILED: $name (see $OUT/$name.log)"; exit 1; fi
}
check import python3 -I "$ROOT/tools/check_import.py" "$COMMON"

echo "== Pascal loaded data vs Babel"
# Regenerate, so the units match the generator and the CLDR release.
python3 -I tools/gencldr.py generate
fpc -Mobjfpc -Sh -O2 -FU"$OUT/units" -FE"$OUT/bin" -Fusrc -Fusrc/data \
  tests/data/dumpdata.pas > "$OUT/dumpdata.build.log" 2>&1 \
  || { tail -n 5 "$OUT/dumpdata.build.log"; exit 1; }
"$OUT/bin/dumpdata" > "$OUT/dump-locales.txt"
"$OUT/bin/dumpdata" --global > "$OUT/dump-global.txt"
check locales sh -c "python3 -I '$ROOT/tests/python/compare_dump.py' < '$OUT/dump-locales.txt'"
check global sh -c "python3 -I '$ROOT/tests/python/compare_dump.py' --global < '$OUT/dump-global.txt'"
echo "== all passed"
