# babel.support tests (TFormat)

`reference.jsonl` holds 3 000 calls of the `TFormat` methods (date,
datetime, time, timedelta, number, decimal, compact decimal, currency,
compact currency, percent, scientific) in 20 locales, 4 time zones and
the 'latn' and 'default' numbering systems: a stratified sample of 7 280
cases compared with Python Babel 2.18.0's `Format`.

`TFormat` only binds the arguments of the functions of `babel.dates` and
`babel.numbers`; its results differ from Babel's `Format` where those
modules depart from Babel on purpose (tests/dates/README.md,
tests/numbers/README.md), and in one more place: the numbering system is
also given to the dates (Babel's dates have none), so 'default' writes
dates and times in the locale's digits. With 'latn' (the default) the
dates are as in babel.dates.

```sh
build/bin/test_format tests/format/reference.jsonl
```

After a deliberate change, update the file with `--update` and review the
diff, as for the other modules.
