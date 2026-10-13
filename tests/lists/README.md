# babel.lists tests

`reference.jsonl` holds the expected results of 4 000 calls of
`FormatList` (one JSON object per line: `op`, `args`, and `expect` or
`error`), a stratified sample of 61 440 cases. `babel.lists` matched Python Babel
2.18.0 on all of them (commit 5656de7) and then departed from it to
follow CLDR as ICU applies it: each part of a style is resolved through
CLDR's aliases (Babel raised KeyError on partial styles and repeated the
last item without a '2' pattern), and ICU's contextual conjunctions
(Spanish 'e' and 'u', Hebrew 'ו-'). The results are also compared with
ICU4C (tests/icu/README.md). `test_lists` runs them:

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
