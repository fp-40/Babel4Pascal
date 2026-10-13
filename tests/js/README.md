# Comparison with ICU

`icu_numbers.mjs` writes test vectors from Node's `Intl.NumberFormat`,
that is from ICU, the reference implementation of CLDR: decimal,
percent, currency (standard, accounting, name) and compact formats of 20
numbers in 50 locales, with the locale's default numbering system and
half-even rounding. `test_numbers` runs the same cases through
`babel.numbers` (`--update` writes its results) and `check_icu.py`
compares the two.

Node's ICU (78.2) carries CLDR 48; Babel4Pascal uses CLDR 47. Where the
data of the two versions differ, the results differ too: those cases are
listed by operation and locale, with the reason, in
`icu_known_differences.json`. Any other difference fails the check.

```sh
node tests/js/icu_numbers.mjs build/icu.jsonl
build/bin/test_numbers build/icu.jsonl --update build/icu-ours.jsonl
python3 tests/js/check_icu.py build/icu.jsonl build/icu-ours.jsonl
```

`tests/run_all.sh` runs it when node is installed.
