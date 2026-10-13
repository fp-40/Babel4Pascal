# babel.lists tests

`reference.jsonl` holds the expected results of 4 000 calls of
`FormatList` (one JSON object per line: `op`, `args`, and `expect` or
`error`), a stratified sample of the 61 440 cases of
`tests/python/gen_lists_vectors.py` on which `babel.lists` matched Python
Babel 2.18.0 exactly. `test_lists` runs them:

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
