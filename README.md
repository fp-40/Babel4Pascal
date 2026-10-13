# Babel4Pascal

A library that provides an integrated collection of utilities that assist with internationalizing and localizing Object Pascal applications (in particular web-based applications).

It includes data extracted from the [Common Locale Data Repository (CLDR)](https://unicode.org/cldr/), and provides a number of convenient methods for accessing and using this data for formatting dates and numbers or to access the localized names of countries, languages, time-zones, etc.

The API mimics the one used by the Python [Babel](https://babel.pocoo.org/) library.

## Status

Work in progress. Done so far: the CLDR data and its loading
(`babel.localedata`). The formatting API (`Locale`, numbers, dates,
plurals, lists, units) is not written yet.

The target is the output of Python Babel 2.17.0, which uses CLDR 46: the
same strings, including where Babel departs from CLDR. The checks below
compare against an installed Babel 2.17.0.

## How the data works

- `tools/gencldr.py` reads the official CLDR XML release
  (`cldr-common-46.0.zip` from unicode.org, the same source Babel's own
  importer reads) and writes one Pascal unit per locale into `src/data/`:
  `babel.cldr_es_PE` holds the data of `es_PE` and uses the unit of the
  locale it inherits from (`babel.cldr_es_419`, then `babel.cldr_es`,
  then `babel.cldr_root`). `babel.cldr_global` holds the data that is not
  per locale (likely subtags, aliases, currencies of territories, time
  zone mappings); `babel.cldr_all` uses every generated locale.
- By default it generates the 498 locales whose CLDR coverage level is
  "modern" or that inherit from such a locale. `--locales` chooses
  others (`all`, or a list).
- A program chooses its locales by naming their units in `uses`; only
  those are linked. A program with `es_PE` alone (and the global data)
  is about 0.5 MB.
- `babel.localedata` loads a locale on first use: it merges the locale's
  data with what it inherits and resolves aliases exactly as Babel's
  `babel.localedata.load` and `LocaleDataDict` do.

## Installing

Free Pascal 3.2.2 on Linux. The package is named `babel`:

```sh
tools/install-package.sh            # compiles and installs into ~/.fppkg
```

The data units in `src/data/` are not in git: the script first runs
`tools/gencldr.py generate` when they are absent, which needs python3 and
downloads the CLDR release (34 MB) from unicode.org into `.cache/` once.

Then a program compiles with `fpc -Mobjfpc -Sh prog.pas`, without `-Fu`
options.

## Checks

`tests/run_all.sh` runs:

1. the generator's unit tests;
2. `tools/check_import.py`: the data the generator reads, against the
   `global.dat` and `locale-data/*.dat` files of the installed Python
   Babel, for all 1067 locales of the release;
3. `tests/data/dumpdata` with `tests/python/compare_dump.py`: the data as
   the Pascal library loads it (merged and alias-resolved), against
   Babel's `load()`, for every generated locale and the global data.

Each comparison must report 0 differences (keys, their order and values).

## Licenses

MIT (LICENSE). The CLDR data is under the Unicode License v3
(LICENSE-CLDR). The generator follows the rules of Babel's
`scripts/import_cldr.py` (BSD-3-Clause, tools/cldrgen/NOTICE).
