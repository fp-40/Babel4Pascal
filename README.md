 <h1><img src="docs/Babel4Pascal.png" height="128" align="middle"/> Babel<i>4Pascal</i></h1>

An integrated collection of utilities that help with the internationalization and localization of Object Pascal applications (in particular web-based applications).

The documentation is in [docs/](docs/index.md).

## Features

- **Locale data.** A `TLocale` record for each locale identifier (`'es_PE'`, `'zh_Hant_TW'`, `'de_DE'`) with the localized names of languages, territories, scripts, currencies and calendar elements, the week data, the text direction and the plural rules.
- **Dates and times.** Formatting with the locale's standard formats (`'short'` to `'full'`), with any CLDR date pattern or skeleton, intervals ("Oct 13 – 16, 2026"), durations ("3 hours", "in 2 days"), day periods and time zone names, with the time zone rules of the system's IANA tz database. Simple parsing of dates and times.
- **Numbers.** Decimal, percent, scientific, compact ("1.2M") and currency formats (standard, accounting, currency names), with the locale's symbols and digits, exact decimal arithmetic, and parsing of localized numbers. Currency data: names, symbols, fraction digits and the currencies of each territory.
- **Units.** Measurements such as "12 kilometers", "150 km/h" and the names of units.
- **Lists.** "A, B, and C" and "A, B, or C" in each locale's styles.
- **Languages.** The official languages of a territory and their share of the population.
- **Plural rules.** The plural category (one, few, many, other, ...) of a number in each language, and the rules as C-style and JavaScript expressions.
- **`TFormat`.** A helper class with the formatting functions bound to a locale, a time zone and a numbering system.


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

The data units in `src/data/` are not in git: when they are absent, the
script first compiles the generator (`tools/gencldr/gencldr.pas`) and
runs `gencldr generate`, which downloads the CLDR release from
unicode.org into `.cache/` once. Installing needs only FPC. A clean
install (compiling the generator, downloading the data, generating, and compiling) takes about 7 s.

Then a program compiles with `fpc -Mobjfpc -Sh prog.pas`, without `-Fu`
options.


## The data

The data is the [Unicode Common Locale Data Repository (CLDR)](https://unicode.org/cldr/). Where CLDR leaves the use of its data to the implementation, the library does what ICU (the reference implementation of CLDR) does, and the checks compare its results with ICU's.

The generator reads the week of a locale without a region from its likely region (`en` is US, weeks from Sunday), gives a territory that CLDR's week data does not list the world's values, leaves out alternate skeletons and interval formats (`alt="ascii"`) and the variants of the region format, and leaves out the data of unconfirmed or provisional status (`draft` attribute), whose values are then inherited from the parent locale (tools/gencldr/cldr.importer.pas).


### How it works

- The generator, `tools/gencldr/gencldr.pas` (a Free Pascal program),
  reads the official CLDR XML release
  (`cldr-common-47.zip` from unicode.org) and writes one Pascal unit per locale into `src/data/`:
  `babel.cldr_es_PE` holds the data of `es_PE` and uses the unit of the
  locale it inherits from (`babel.cldr_es_419`, then `babel.cldr_es`,
  then `babel.cldr_root`). `babel.cldr_global` holds the data that is not
  per locale (likely subtags, aliases, currencies of territories, time
  zone mappings); `babel.cldr_all` uses every generated locale.
- By default it generates the 512 locales whose CLDR coverage level is
  "modern" or that inherit from such a locale. `--locales` chooses
  others (`all`, or a list).
- Usage and options of the generator: docs/installation.md.
- A program chooses its locales by naming their units in `uses`; only
  those are linked. A program with `es_PE` alone (and the global data)
  is about 0.5 MB.
- `babel.localedata` loads a locale on first use: it merges the locale's
  data with what it inherits (key by key) and resolves the aliases of
  root (months, days, quarters, eras, currency formats).


## Checks

`tests/run_all.sh` runs the checks below. It needs FPC and Python 3
(the checkers in `tests/python/`, `tests/js/` and `tests/icu/`);
node, gcc and the ICU development headers are optional.

1. the generator's checks: `tests/gencldr/test_sha2` (the SHA-2 unit that
   verifies the downloaded release, 2 014 digests) and
   `tests/gencldr/test_gencldr` (the generator's encoding against the
   library's decoding, for a value of every kind and for the global data
   and every locale of the release; the split of interval patterns);
2. `tests/data/dumpdata` with `tests/python/compare_dump.py`: the data as
   the Pascal library loads it (decoded, merged along the parent chain,
   root's aliases resolved), against the imported data (`gencldr dump`)
   merged and resolved independently in Python, for every generated
   locale and the global data;
3. `tests/core/test_core` with `tests/core/fixed.jsonl` (the plural
   inputs and 30 000 doubles, never rewritten by `--update`) and
   `tests/core/reference.jsonl` (66 245
   cases): identifiers, `TLocale.Parse`, negotiation, names and
   properties of every generated locale, plural rules (evaluation,
   `rules`, gettext and JavaScript forms), plural operands, `Decimal`
   parsing and float-to-decimal conversion (30 000
   doubles), and the decimal arithmetic against Python's `decimal` (4 000
   random operations); `tests/python/check_default_locale.py` with
   `tests/core/default_locale.json`: the default locale under several
   environments;
4. `tests/numbers/test_numbers` with `tests/numbers/reference.jsonl`:
   6 434 calls of the formatting, parsing and currency functions with
   their expected results (tests/numbers/README.md).
   `tests/numbers/test_roundtrip` formats and parses back 67 000 numbers
   (every locale, Latin and native digits). When node is installed, the
   results are also compared with ICU's on 18 000 cases
   (tests/js/README.md); the only differences allowed are those from the
   CLDR 47/48 data;
5. `tests/tz/test_tz` with vectors from `tests/python/gen_tz_vectors.py`:
   offsets and DST of every zone of the system's tz database against
   Python's zoneinfo (581 000 lookups);
6. `tests/dates/test_dates` with `tests/dates/reference.jsonl`: 8 707
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

MIT (LICENSE).
The CLDR data is under the Unicode License v3 (LICENSE-CLDR).
