# Comparison of babel.dates with ICU4C

`icu_dates.c` writes test vectors from ICU4C, the reference
implementation of CLDR, through its C API (`udat`, `udatpg`,
`ureldatefmt`), one JSON object per line:

- `icu_pattern`: 30 patterns (every zone field, day periods, weeks,
  weekdays, quarters, eras...) at 5 instants in 13 zones;
- `icu_style`: the full, long, medium and short date, time and date-time
  formats;
- `icu_skeleton`: 19 skeletons through ICU's pattern generator;
- `icu_relative`: relative times ('in 3 hours', 'hace 3 min') for 7
  units, 3 widths and 5 values;

in 36 locales, with the Gregorian calendar and the locale's default
numbering system (90 720 cases). `test_dates` runs the same cases through
`babel.dates` (with `NumberingSystem` 'default'; `--update` writes its
results) and `check_icu.py` compares the two.

```sh
gcc -O2 tests/icu/icu_dates.c -o build/bin/icu_dates -licui18n -licuuc
build/bin/icu_dates > build/vectors/icu_dates.jsonl
build/bin/test_dates build/vectors/icu_dates.jsonl --update build/vectors/icu_dates-ours.jsonl
python3 tests/icu/check_icu.py build/vectors/icu_dates.jsonl build/vectors/icu_dates-ours.jsonl
```

`tests/run_all.sh` runs it when gcc and the ICU development headers are
installed (Debian/Ubuntu: `libicu-dev`).

## Known differences

The system's ICU (78.2) carries CLDR 48; Babel4Pascal uses CLDR 47. Where
the data of the two versions differ, the results differ too. Those cases
are listed, with the reason, in `known_differences.json`, by operation,
field and locale. Any other difference fails the check, and so does a
listed difference that no longer occurs.

Each listed difference was confirmed to come from the data: built from
CLDR 48's XML (the importer and the generator run on
`cldr-common-48.zip` into another directory, and `test_dates` compiled
against those units), `babel.dates` gives ICU's result in every listed
case except one: ICU 78 joins zh_Hant's short date and time with a thin
space, which neither CLDR 47 ('{1} {0}') nor CLDR 48.0's XML ('{1}{0}')
has.

A different ICU version gives other differences; the list is for ICU
78.2.
