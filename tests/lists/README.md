# babel.lists tests

`reference.jsonl` holds the expected results of 4 000 calls of
`FormatList` (one JSON object per line: `op`, `args`, and `expect` or
`error`): every style in every locale, lists of zero to five items.
Each part of a style is resolved through CLDR's root aliases, and the
conjunctions change as in ICU (Spanish 'e' and 'u', Hebrew 'ו-'). The
results are also compared with ICU4C (tests/icu/README.md). `test_lists`
runs them:

```sh
build/bin/test_lists tests/lists/reference.jsonl
```

After a deliberate change, update the file from the library's results
and review the diff:

```sh
build/bin/test_lists tests/lists/reference.jsonl --update /tmp/new.jsonl
mv /tmp/new.jsonl tests/lists/reference.jsonl
git diff tests/lists/reference.jsonl
```
