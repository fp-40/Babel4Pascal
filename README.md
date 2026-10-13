# Babel4Pascal

A library that provides an integrated collection of utilities that assist with internationalizing and localizing Object Pascal applications (in particular web-based applications).

It includes data extracted from the [Common Locale Data Repository (CLDR)](https://unicode.org/cldr/), and provides a number of convenient methods for accessing and using this data for formatting dates and numbers or to access the localized names of countries, languages, time-zones, etc.

The documentation is in [docs/](docs/index.md): a user guide and the API
reference of every unit.

## Status

Work in progress. Done so far:

- the CLDR data and its loading (`babel.localedata`);
- locales: `TLocale`, identifiers, negotiation and the
  default locale (`babel.core`);
- plural rules (`babel.plural`) and decimal numbers with the arithmetic
  of Python's `Decimal` (`babel.decimal`);
- numbers, currencies and percentages: formatting (standard, compact,
  scientific, accounting, currency names), parsing, currency data
  (`babel.numbers`);
- dates and times: formatting with the locale's patterns and with any
  CLDR pattern or skeleton, intervals, durations, day periods, time zone
  names, simple parsing (`babel.dates`), with the time zone rules of the
  system's tz database (`babel.tz`);
- lists ('A, B, and C') in the locale's styles (`babel.lists`);
- measurement units ('12 kilometers', '150 km/h'), unit names, compound
  units (`babel.units`);
- the official languages of a territory and their population shares
  (`babel.languages`);
- `TFormat`, the formatting functions bound to a locale, a time zone and
  a numbering system (`babel.support`).

Not included: message translation (gettext catalogs).

The data is CLDR 47. Where CLDR leaves the use of its data to the
implementation, the library does what ICU (the reference implementation
of CLDR) does, and the checks compare its results with ICU's. The
generator reads the week of a locale without a region from its likely
region (`en` is US, weeks from Sunday), gives a territory that CLDR's
week data does not list the world's values, leaves out alternate
skeletons and interval formats (`alt="ascii"`) and the variants of the
region format, and leaves out the data of unconfirmed or provisional
status (`draft` attribute), whose values are then inherited from the
parent locale (tools/cldrgen/importer.py).

## How the data works

- `tools/gencldr.py` reads the official CLDR XML release
  (`cldr-common-47.zip` from unicode.org) and writes one Pascal unit per locale into `src/data/`:
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
  data with what it inherits (key by key) and resolves the aliases of
  root (months, days, quarters, eras, currency formats).

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

Names are in Pascal case (`TLocale.Parse`, `GetDisplayName`). A missing
name is returned as `''`. Errors are `EBabelError` subclasses
(`EUnknownLocaleError`, `EBabelValueError`, `EPluralRuleError`).

```pascal
uses babel.numbers, babel.cldr_es_PE, babel.cldr_en;

WriteLn(FormatDecimal(1250, 'es_PE'));                    // 1,250
WriteLn(FormatCurrency(1234.5, 'PEN', 'es_PE'));          // S/ 1,234.50
WriteLn(FormatPercent(0.18, 'en'));                       // 18%
WriteLn(FormatCompactDecimal(1234567, 'en'));             // 1M
WriteLn(FormatCurrency(-50, 'USD', 'en',
  CurrencyOptions.WithFormatType('accounting')));         // ($50.00)
```

```pascal
uses babel.dates, babel.cldr_es_PE, babel.cldr_en;

T := EncodeDateTime(2026, 10, 13, 14, 30, 0, 0);          // UTC
FormatDate(T, 'es_PE', 'full');                           // martes, 13 de octubre de 2026
FormatDateAndTime(T, 'en', DateTimeOptions.WithFormat('full')
  .WithTimeZone('America/Lima'));                         // Tuesday, October 13, 2026 at 9:30:00 AM Peru Standard Time
FormatInterval(T, IncDay(T, 3), 'en',
  IntervalOptions.WithSkeleton('yMMMd'));                 // Oct 13 – 16, 2026
FormatTimedelta(-3 * 3600, 'es_PE',
  TimedeltaOptions.WithAddDirection(True));               // hace 3 horas
```

A `TDateTime` is taken as UTC; the time zone to show it in is an option.
The function that formats a date and a time is `FormatDateAndTime`, as
SysUtils already has a `FormatDateTime`.

Optional parameters are fields of an options record (`NumberOptions`,
`CurrencyOptions`, `CompactOptions`, `ParseOptions`, `DateTimeOptions`,
...): start from the function of the same name, which returns the
defaults, and change fields or chain `With...` calls. A number can be an
integer, a `Double`, a `TDecimal` or a string, converted to `TDecimal`
(which keeps its digits: 1.0 and 1 have different plural operands).

A `Double` is read as the shortest decimal that converts back to the
same `Double` (2.675 is 2.675, not its binary value 2.67499999...). Use
`TDecimal` (or an integer) for exact decimal values.

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
2. `tests/data/dumpdata` with `tests/python/compare_dump.py`: the data as
   the Pascal library loads it (decoded, merged along the parent chain,
   root's aliases resolved), against the importer's data merged and
   resolved independently in Python, for every generated locale and the
   global data;
3. `tests/core/test_core` with `tests/core/reference.jsonl` (66 245
   cases): identifiers, `TLocale.Parse`, negotiation, names and
   properties of every generated locale, plural rules (evaluation,
   `rules`, gettext and JavaScript forms), plural operands, `Decimal`
   parsing and float-to-decimal conversion (30 000
   doubles), and the decimal arithmetic against Python's `decimal` (4 000
   random operations); `tests/python/check_default_locale.py` with
   `tests/core/default_locale.json`: the default locale under several
   environments;
4. `tests/numbers/test_numbers` with `tests/numbers/reference.jsonl`:
   6 448 calls of the formatting, parsing and currency functions with
   their expected results (tests/numbers/README.md).
   `tests/numbers/test_roundtrip` formats and parses back 67 000 numbers
   (every locale, Latin and native digits). When node is installed, the
   results are also compared with ICU's on 18 000 cases
   (tests/js/README.md); the only differences allowed are those from the
   CLDR 47/48 data;
5. `tests/tz/test_tz` with vectors from `tests/python/gen_tz_vectors.py`:
   offsets and DST of every zone of the system's tz database against
   Python's zoneinfo (581 000 lookups);
6. `tests/dates/test_dates` with `tests/dates/reference.jsonl`: 8 695
   calls of the dates functions (every pattern field and length,
   predefined formats, skeletons, intervals, durations, day periods, zone
   names in 19 zones, parsing) with their expected results
   (tests/dates/README.md). When gcc and the ICU development headers are
   installed, the results are also compared with ICU4C's on 90 720 cases
   (tests/icu/README.md); the only differences allowed are those from the
   CLDR 47/48 data;
7. `tests/lists/test_lists` and `tests/units/test_units` with their
   reference files (tests/lists/README.md, tests/units/README.md), and,
   when gcc and the ICU headers are installed, compared with ICU4C;
8. `tests/languages/test_languages` and `tests/format/test_format` with
   their reference files (tests/languages/README.md,
   tests/format/README.md).

Each comparison must report 0 differences, except the listed data
differences of the ICU comparisons.

## Licenses

MIT (LICENSE). The CLDR data is under the Unicode License v3
(LICENSE-CLDR). Parts of the generator derive from third-party code
under the BSD-3-Clause license; see tools/cldrgen/NOTICE.
