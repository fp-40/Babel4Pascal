# babel.units tests

`reference.jsonl` holds the expected results of 8 000 calls of
`GetUnitName`, `FormatUnit`, `FormatUnitText`, `FormatCompoundUnit` and
`FormatCompoundUnitText` (one JSON object per line: `op`, `args`, and
`expect` or `error`). As in ICU, the plural form is that of the number
as shown, a missing plural form uses the 'other' pattern, and the long
and narrow lengths take from the short one what they lack (CLDR's root
aliases). The results are also compared with ICU4C
(tests/icu/README.md). `test_units` runs them:

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
