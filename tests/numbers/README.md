# babel.numbers tests

`reference.jsonl` holds the expected results of 6 434 calls of
`babel.numbers` (one JSON object per line: `op`, `args`, and `expect` or
`error`). `test_numbers` runs them:

```sh
build/bin/test_numbers tests/numbers/reference.jsonl
```

The results are also compared with ICU (tests/js/README.md). After a
deliberate change, update the file from the library's own results and
review the diff:

```sh
build/bin/test_numbers tests/numbers/reference.jsonl --update /tmp/new.jsonl
mv /tmp/new.jsonl tests/numbers/reference.jsonl
git diff tests/numbers/reference.jsonl
```
