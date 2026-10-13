# babel.dates tests

`reference.jsonl` holds the expected results of 8 462 calls of
`babel.dates` (one JSON object per line: `op`, `args`, and `expect` or
`error`). `test_dates` runs them:

```sh
build/bin/test_dates tests/dates/reference.jsonl
```

The file started as a sample of the cases on which `babel.dates` matched
Python Babel 2.18.0 exactly (commit d1e1263, 352 627 cases). Since then
`babel.dates` departs from Babel on purpose where Babel is wrong or does
not follow CLDR, so the file, not Babel, is the reference. After a
deliberate change, update it from the library's own results and review
the diff:

```sh
build/bin/test_dates tests/dates/reference.jsonl --update /tmp/new.jsonl
mv /tmp/new.jsonl tests/dates/reference.jsonl
git diff tests/dates/reference.jsonl
```

`tests/python/gen_dates_vectors.py` still generates the full set of cases
from Babel, useful to see every difference from Babel at once.
