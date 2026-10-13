# babel.units tests

`reference.jsonl` holds the expected results of 8 000 calls of
`GetUnitName`, `FormatUnit`, `FormatUnitText`, `FormatCompoundUnit` and
`FormatCompoundUnitText` (one JSON object per line: `op`, `args`, and
`expect` or `error`), a stratified sample of the 292 732 cases of
`tests/python/gen_units_vectors.py`. `babel.units` matched Python Babel
2.18.0 on all of them except where `babel.numbers` departs from Babel on
purpose (minimum grouping digits, the locale's minus sign, native digits
for the 'default' numbering system): 4 958 cases, each with a negative
value, a value of four or more integer digits, or the 'default' numbering
system. Then `babel.units` departed from Babel to follow CLDR as ICU
applies it: the plural form of the number as
shown, the 'other' pattern for a missing plural form, and the short data
for what the long and narrow lengths lack. The results are also compared
with ICU4C (tests/icu/README.md). `test_units` runs them:

```sh
build/bin/test_units tests/units/reference.jsonl
```

After a deliberate change, update the file from the library's results
and review the diff:

```sh
build/bin/test_units tests/units/reference.jsonl --update /tmp/new.jsonl
mv /tmp/new.jsonl tests/units/reference.jsonl
git diff tests/units/reference.jsonl
```
