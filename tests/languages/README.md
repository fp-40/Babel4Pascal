# babel.languages tests

`reference.jsonl` holds the 1 320 cases of
`tests/python/gen_languages_vectors.py` (`GetOfficialLanguages` with
every combination of options and `GetTerritoryLanguageInfo`, for every
territory of CLDR's territoryInfo and a few unknown codes) with the
results of Python Babel 2.18.0, which `babel.languages` matches exactly.
ICU4C has no public API for this data, so there is no ICU comparison.

```sh
build/bin/test_languages tests/languages/reference.jsonl
```
