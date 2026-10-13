# babel.support tests (TFormat)

`reference.jsonl` holds 3 000 calls of the `TFormat` methods (date,
datetime, time, timedelta, number, decimal, compact decimal, currency,
compact currency, percent, scientific) in 20 locales, 4 time zones and
the 'latn' and 'default' numbering systems.

`TFormat` binds the arguments of the functions of `babel.dates` and
`babel.numbers`, so its results are theirs (tests/dates/README.md,
tests/numbers/README.md). The numbering system also applies to the
dates: 'default' writes dates and times in the locale's digits.

```sh
build/bin/test_format tests/format/reference.jsonl
```

After a deliberate change, update the file with `--update` and review the
diff, as for the other modules.
