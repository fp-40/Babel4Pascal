# Babel4Pascal

A library that provides an integrated collection of utilities that assist with internationalizing and localizing Object Pascal applications (in particular web-based applications).

It includes data extracted from the [Common Locale Data Repository (CLDR)](https://unicode.org/cldr/), and provides a number of convenient methods for accessing and using this data for formatting dates and numbers or to access the localized names of countries, languages, time-zones, etc.

The API mimics the one used by the Python [Babel](https://babel.pocoo.org/) library.

## Status

Work in progress. Done so far:

- the CLDR data and its loading (`babel.localedata`);
- locales: `TLocale` (Babel's `Locale`), identifiers, negotiation and the
  default locale (`babel.core`);
- plural rules (`babel.plural`) and decimal numbers with the arithmetic
  of Python's `Decimal` (`babel.decimal`);
- numbers, currencies and percentages: formatting (standard, compact,
  scientific, accounting, currency names), parsing, currency data
  (`babel.numbers`).

Not written yet: dates and times, lists, units.

The target is the output of Python Babel 2.18.0, which uses CLDR 47: the
same strings, including where Babel departs from CLDR. The checks below
compare against Babel 2.18.0, the "oracle" (`tools/oracle.py` downloads
its wheel from PyPI into `.cache/oracle`; no install is needed).

## How the data works

- `tools/gencldr.py` reads the official CLDR XML release
  (`cldr-common-47.zip` from unicode.org, the same source Babel's own
  importer reads) and writes one Pascal unit per locale into `src/data/`:
  `babel.cldr_es_PE` holds the data of `es_PE` and uses the unit of the
  locale it inherits from (`babel.cldr_es_419`, then `babel.cldr_es`,
  then `babel.cldr_root`). `babel.cldr_global` holds the data that is not
  per locale (likely subtags, aliases, currencies of territories, time
  zone mappings); `babel.cldr_all` uses every generated locale.
- By default it generates the 512 locales whose CLDR coverage level is
  "modern" or that inherit from such a locale. `--locales` chooses
  others (`all`, or a list).
- A program chooses its locales by naming their units in `uses`; only
  those are linked. A program with `es_PE` alone (and the global data)
  is about 0.5 MB.
- `babel.localedata` loads a locale on first use: it merges the locale's
  data with what it inherits and resolves aliases exactly as Babel's
  `babel.localedata.load` and `LocaleDataDict` do.

## Using it

```pascal
uses babel.core, babel.cldr_es_PE, babel.cldr_en;   { the locales to link }

var L: TLocale;
begin
  L := TLocale.Parse('es_PE');
  WriteLn(L.DisplayName);                 // español (Perú)
  WriteLn(L.GetDisplayName('en'));        // Spanish (Peru): a string converts to TLocale
  WriteLn(L.Territories.Str('DE'));       // Alemania
  WriteLn(L.PluralForm.Evaluate(1));      // one
end.
```

Names follow Babel's in Pascal case (`Locale.parse` is `TLocale.Parse`,
`get_display_name` is `GetDisplayName`). Where Babel returns `None` for a
missing name, these functions return `''`. Errors are `EBabelError`
subclasses named after Babel's exceptions (`EUnknownLocaleError`,
`EBabelValueError`, `EPluralRuleError`).

```pascal
uses babel.numbers, babel.cldr_es_PE, babel.cldr_en;

WriteLn(FormatDecimal(1250, 'es_PE'));                    // 1,250
WriteLn(FormatCurrency(1234.5, 'PEN', 'es_PE'));          // S/ 1,234.50
WriteLn(FormatPercent(0.18, 'en'));                       // 18%
WriteLn(FormatCompactDecimal(1234567, 'en'));             // 1M
WriteLn(FormatCurrency(-50, 'USD', 'en',
  CurrencyOptions.WithFormatType('accounting')));         // ($50.00)
```

The optional parameters of Babel's functions are fields of an options
record (`NumberOptions`, `CurrencyOptions`, `CompactOptions`,
`ParseOptions`): start from the function, which returns Babel's
defaults, and change fields or chain `With...` calls. A number can be an
integer, a `Double`, a `TDecimal` or a string; the library remembers
which, as Babel's results depend on it.

A `Double` given to the library is read as Babel reads a Python `float`:
as the shortest decimal that converts back to the same `Double` (2.675 is
2.675, not its binary value 2.67499999...). Use `TDecimal` (or an integer)
for exact decimal values.

## Installing

Free Pascal 3.2.2 on Linux. The package is named `babel`:

```sh
tools/install-package.sh            # compiles and installs into ~/.fppkg
```

The data units in `src/data/` are not in git: the script first runs
`tools/gencldr.py generate` when they are absent, which needs python3 and
downloads the CLDR release from unicode.org into `.cache/` once. A clean
install (generating and compiling) takes about 6 s.

Then a program compiles with `fpc -Mobjfpc -Sh prog.pas`, without `-Fu`
options.

## Checks

`tests/run_all.sh` runs:

1. the generator's unit tests;
2. `tools/check_import.py`: the data the generator reads, against the
   `global.dat` and `locale-data/*.dat` files of the oracle, for all 1083
   locale files of the release;
3. `tests/data/dumpdata` with `tests/python/compare_dump.py`: the data as
   the Pascal library loads it (merged and alias-resolved), against
   the oracle's `load()`, for every generated locale and the global data;
4. `tests/core/test_core` with vectors from
   `tests/python/gen_core_vectors.py`: identifiers, `Locale.parse`,
   negotiation, names and properties of every generated locale, plural
   rules (evaluation, `rules`, gettext and JavaScript forms), plural
   operands, `Decimal` parsing and float-to-decimal conversion (30 000
   doubles), and the decimal arithmetic against Python's `decimal` (4 000
   random operations); `tests/python/check_default_locale.py`: the
   default locale under several environments;
5. `tests/numbers/test_numbers` with `tests/numbers/reference.jsonl`:
   6 448 calls of the formatting, parsing and currency functions with
   their expected results. `babel.numbers` matched Babel exactly on
   263 000 calls (commit 0535909) and then departed from it on purpose to
   follow CLDR and ICU (localized signs and digits, plural of the number
   shown, exact arithmetic, minimum grouping, currency spacing); the
   reference file records the current behavior (tests/numbers/README.md).
   `tests/numbers/test_roundtrip` formats and parses back 67 000 numbers
   (every locale, Latin and native digits). When node is installed, the
   results are also compared with ICU's on 18 000 cases
   (tests/js/README.md); the only differences allowed are those from the
   CLDR 47/48 data.

Each comparison must report 0 differences (the ICU report is
informative).

## Licenses

MIT (LICENSE). The CLDR data is under the Unicode License v3
(LICENSE-CLDR). The generator follows the rules of Babel's
`scripts/import_cldr.py` (BSD-3-Clause, tools/cldrgen/NOTICE).
