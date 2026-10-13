# Babel4Pascal

Babel4Pascal is a Free Pascal library for internationalizing and
localizing applications. It carries the locale data of the Unicode Common
Locale Data Repository (CLDR) and formats dates, times, numbers,
currencies, percentages, measurement units and lists the way each locale
writes them; it also gives the localized names of languages, territories,
scripts, currencies and time zones, and the plural rules of each
language.

## User Documentation

- [Introduction](intro.md)
- [Installation](installation.md)
- [Locale Data](locale.md)
- [Date and Time](dates.md)
- [Number Formatting](numbers.md)
- [Support Classes and Functions](support.md)

## API Reference

- [API Reference](api/index.md)
  - [Core Functionality](api/core.md)
  - [Date and Time](api/dates.md)
  - [Languages](api/languages.md)
  - [List Formatting](api/lists.md)
  - [Numbers and Currencies](api/numbers.md)
  - [Pluralization Support](api/plural.md)
  - [General Support Functionality](api/support.md)
  - [Units](api/units.md)

## Conventions

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

Examples are Pascal snippets in `{$mode objfpc}{$H+}`; the output of a
call is shown in a comment after it.
