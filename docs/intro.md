# Introduction

Programs that show dates, numbers or names to people in several countries
need to know how each language and region writes them: whether the
decimal separator is a point or a comma, which day starts the week, what
"October" is in Polish, whether "1 file" and "2 files" take different
forms, and how a time zone is named. The Unicode Common Locale Data
Repository (CLDR) collects that information for hundreds of locales.
Babel4Pascal makes it available to Free Pascal programs.

## What the library provides

- **Locale data.** A `TLocale` record for each locale identifier
  (`'es_PE'`, `'zh_Hant_TW'`, `'de_DE'`) with the localized names of
  languages, territories, scripts, currencies and calendar elements, the
  week data, the text direction and the plural rules.
- **Dates and times.** Formatting with the locale's standard formats
  (`'short'` to `'full'`), with any CLDR date pattern or skeleton,
  intervals ("Oct 13 – 16, 2026"), durations ("3 hours", "in 2 days"),
  day periods and time zone names, with the time zone rules of the
  system's IANA tz database. Simple parsing of dates and times.
- **Numbers.** Decimal, percent, scientific, compact ("1.2M") and
  currency formats (standard, accounting, currency names), with the
  locale's symbols and digits, exact decimal arithmetic, and parsing of
  localized numbers. Currency data: names, symbols, fraction digits and
  the currencies of each territory.
- **Units.** Measurements such as "12 kilometers", "150 km/h" and the
  names of units.
- **Lists.** "A, B, and C" and "A, B, or C" in each locale's styles.
- **Languages.** The official languages of a territory and their share of
  the population.
- **Plural rules.** The plural category (one, few, many, other, ...) of a
  number in each language, and the rules as C-style and JavaScript
  expressions.
- **`TFormat`.** The formatting functions bound to a locale, a time zone
  and a numbering system.

A program links the data of the locales it uses and no others: each
locale's data is a unit (`babel.cldr_es_PE`), and `babel.cldr_all` links
every generated locale.

[Index](index.md)
