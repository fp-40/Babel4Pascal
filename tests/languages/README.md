# babel.languages tests

`reference.jsonl` holds 1 320 cases (`GetOfficialLanguages` with
every combination of options and `GetTerritoryLanguageInfo`, for every
territory of CLDR's territoryInfo and a few unknown codes) with their
expected results. ICU4C has no public API for this data, so there is no
ICU comparison.

```sh
build/bin/test_languages tests/languages/reference.jsonl
```
