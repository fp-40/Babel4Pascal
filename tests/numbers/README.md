# babel.numbers tests

`reference.jsonl` holds the expected results of 6 448 calls of
`babel.numbers` (one JSON object per line: `op`, `args`, and `expect` or
`error`). `test_numbers` runs them:

```sh
build/bin/test_numbers tests/numbers/reference.jsonl
```

The file started as a sample of the cases on which `babel.numbers`
matched Python Babel 2.18.0 exactly (commit 0535909). Since then
`babel.numbers` departs from Babel on purpose (exact decimal arithmetic,
CLDR's localized signs and digits, plural from the displayed number, ...),
so the file, not Babel, is the reference. After a deliberate change,
update it from the library's own results and review the diff:

```sh
build/bin/test_numbers tests/numbers/reference.jsonl --update /tmp/new.jsonl
mv /tmp/new.jsonl tests/numbers/reference.jsonl
git diff tests/numbers/reference.jsonl
```

`tests/python/gen_numbers_vectors.py` still generates the full set of
cases from Babel (about 263 000), useful to see every difference from
Babel at once.
