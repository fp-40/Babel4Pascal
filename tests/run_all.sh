#!/bin/sh
# Runs every check of Babel4Pascal. Exit status 0 only when all pass.
#
# 1. Generator unit tests (tests/python/test_cldrgen.py).
# 2. The Pascal library's loaded data against the importer's
#    (tests/data/dumpdata + tests/python/compare_dump.py): every generated
#    locale merged along its parent chain with root's aliases resolved,
#    and the global data.
# 3. babel.core, babel.plural and babel.decimal against their reference
#    cases (tests/core/reference.jsonl + tests/core/test_core), and
#    DefaultLocale under several environments
#    (tests/core/default_locale.json, tests/python/check_default_locale.py
#    + tests/core/print_default).
# 4. babel.numbers against its reference cases (tests/numbers/reference.jsonl,
#    tests/numbers/README.md), and, when node is installed, against ICU
#    (tests/js/README.md): differences other than the known data
#    differences between CLDR 47 and 48 fail the run. Round trips
#    (tests/numbers/test_roundtrip): ParseDecimal(FormatDecimal(x)) = x in
#    every locale and numbering system.
# 5. babel.tz against Python's zoneinfo on the system's tz database: every
#    zone, offsets and DST at UTC instants and local times
#    (tests/python/gen_tz_vectors.py + tests/tz/test_tz).
# 6. babel.dates against its reference cases (tests/dates/reference.jsonl,
#    tests/dates/README.md), and, when gcc and the ICU development headers
#    are installed, against ICU4C (tests/icu/README.md): differences other
#    than the known data differences between CLDR 47 and 48 fail the run.
# 7. babel.lists and babel.units against their reference cases
#    (tests/lists/reference.jsonl, tests/units/reference.jsonl), and
#    against ICU4C as in 6.
# 8. babel.languages and babel.support (TFormat) against their reference
#    cases (tests/languages/reference.jsonl, tests/format/reference.jsonl).
#
# The CLDR release (.cache/cldr) is downloaded once when absent. Python 3
# runs the generator and the checkers; Python Babel is not used.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT=$ROOT/build
mkdir -p "$OUT/units" "$OUT/bin"
python3 -I tools/gencldr.py fetch > /dev/null   # the CLDR release, downloaded once

echo "== generator tests"
python3 -I tests/python/test_cldrgen.py

# Run from /tmp: Python must not import modules from this checkout's cwd.
check() { # name, command...: run, show the last lines, fail on failure
  name=$1; shift
  if (cd /tmp && "$@") > "$OUT/$name.log" 2>&1; then tail -n 3 "$OUT/$name.log"
  else tail -n 20 "$OUT/$name.log"; echo "FAILED: $name (see $OUT/$name.log)"; exit 1; fi
}

echo "== Pascal loaded data vs the importer's"
# Regenerate, so the units match the generator and the CLDR release.
python3 -I tools/gencldr.py generate
fpc -Mobjfpc -Sh -O2 -FU"$OUT/units" -FE"$OUT/bin" -Fusrc -Fusrc/data \
  tests/data/dumpdata.pas > "$OUT/dumpdata.build.log" 2>&1 \
  || { tail -n 5 "$OUT/dumpdata.build.log"; exit 1; }
"$OUT/bin/dumpdata" > "$OUT/dump-locales.txt"
"$OUT/bin/dumpdata" --global > "$OUT/dump-global.txt"
check locales sh -c "python3 -I '$ROOT/tests/python/compare_dump.py' < '$OUT/dump-locales.txt'"
check global sh -c "python3 -I '$ROOT/tests/python/compare_dump.py' --global < '$OUT/dump-global.txt'"
echo "== babel.core, babel.plural, babel.decimal vs their reference cases"
mkdir -p "$OUT/vectors"
for prog in core/test_core core/print_default numbers/test_numbers numbers/test_roundtrip tz/test_tz dates/test_dates \
    lists/test_lists units/test_units languages/test_languages format/test_format; do
  fpc -Mobjfpc -Sh -O2 -FU"$OUT/units" -FE"$OUT/bin" -Fusrc -Fusrc/data -Futests/support \
    "tests/$prog.pas" > "$OUT/build.log" 2>&1 \
    || { tail -n 5 "$OUT/build.log"; exit 1; }
done
check core "$OUT/bin/test_core" "$ROOT/tests/core/reference.jsonl"
check default_locale python3 -I "$ROOT/tests/python/check_default_locale.py" "$OUT/bin/print_default"
echo "== babel.numbers vs its reference cases, round trips"
check numbers "$OUT/bin/test_numbers" "$ROOT/tests/numbers/reference.jsonl"
check roundtrip "$OUT/bin/test_roundtrip"
if command -v node > /dev/null; then
  echo "== babel.numbers vs ICU"
  node tests/js/icu_numbers.mjs "$OUT/vectors/icu.jsonl" > /dev/null
  "$OUT/bin/test_numbers" "$OUT/vectors/icu.jsonl" --update "$OUT/vectors/icu-ours.jsonl" > /dev/null
  check icu python3 -I "$ROOT/tests/js/check_icu.py" "$OUT/vectors/icu.jsonl" "$OUT/vectors/icu-ours.jsonl"
fi
echo "== babel.tz vs Python zoneinfo (system tz database)"
check tz_vectors python3 -I "$ROOT/tests/python/gen_tz_vectors.py" "$OUT/vectors/tz.jsonl"
check tz "$OUT/bin/test_tz" "$OUT/vectors/tz.jsonl"
echo "== babel.dates vs its reference cases"
check dates "$OUT/bin/test_dates" "$ROOT/tests/dates/reference.jsonl"
if command -v gcc > /dev/null && gcc -O2 tests/icu/icu_dates.c -o "$OUT/bin/icu_dates" \
     -licui18n -licuuc > "$OUT/icu_dates.build.log" 2>&1; then
  echo "== babel.dates vs ICU4C"
  "$OUT/bin/icu_dates" > "$OUT/vectors/icu_dates.jsonl" 2> /dev/null
  "$OUT/bin/test_dates" "$OUT/vectors/icu_dates.jsonl" --update "$OUT/vectors/icu_dates-ours.jsonl" > /dev/null
  check icu_dates python3 -I "$ROOT/tests/icu/check_icu.py" "$OUT/vectors/icu_dates.jsonl" \
    "$OUT/vectors/icu_dates-ours.jsonl"
else
  echo "(babel.dates vs ICU4C skipped: no gcc or ICU headers; see $OUT/icu_dates.build.log)"
fi
echo "== babel.lists and babel.units vs their reference cases"
check lists "$OUT/bin/test_lists" "$ROOT/tests/lists/reference.jsonl"
check units "$OUT/bin/test_units" "$ROOT/tests/units/reference.jsonl"
if command -v gcc > /dev/null && gcc -O2 tests/icu/icu_lists_units.c -o "$OUT/bin/icu_lists_units" \
     -licui18n -licuuc > "$OUT/icu_lists_units.build.log" 2>&1; then
  echo "== babel.lists and babel.units vs ICU4C"
  "$OUT/bin/icu_lists_units" > "$OUT/vectors/icu_lists_units.jsonl" 2> /dev/null
  grep '"icu_list"' "$OUT/vectors/icu_lists_units.jsonl" > "$OUT/vectors/icu_lists.jsonl"
  grep '"icu_unit' "$OUT/vectors/icu_lists_units.jsonl" > "$OUT/vectors/icu_units.jsonl"
  "$OUT/bin/test_lists" "$OUT/vectors/icu_lists.jsonl" --update "$OUT/vectors/icu_lists-ours.jsonl" > /dev/null
  "$OUT/bin/test_units" "$OUT/vectors/icu_units.jsonl" --update "$OUT/vectors/icu_units-ours.jsonl" > /dev/null
  check icu_lists python3 -I "$ROOT/tests/icu/check_icu.py" "$OUT/vectors/icu_lists.jsonl" \
    "$OUT/vectors/icu_lists-ours.jsonl"
  check icu_units python3 -I "$ROOT/tests/icu/check_icu.py" "$OUT/vectors/icu_units.jsonl" \
    "$OUT/vectors/icu_units-ours.jsonl"
else
  echo "(babel.lists and babel.units vs ICU4C skipped: no gcc or ICU headers)"
fi
echo "== babel.languages and babel.support vs their reference cases"
check languages "$OUT/bin/test_languages" "$ROOT/tests/languages/reference.jsonl"
check format "$OUT/bin/test_format" "$ROOT/tests/format/reference.jsonl"
echo "== all passed"
