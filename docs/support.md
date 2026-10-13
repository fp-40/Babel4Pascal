# Support Classes and Functions

The unit `babel.support` provides `TFormat`, a record that binds a locale,
a time zone and a numbering system to the formatting functions of
`babel.dates` and `babel.numbers`. An application that formats many
values for one user creates one `TFormat` and calls its methods, instead
of passing the locale and the options to every call.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

This page also shows the smaller helpers that applications use next to
it: lists (`babel.lists`), measurement units (`babel.units`) and the
languages of a territory (`babel.languages`).

## Binding a locale, a time zone and a numbering system

```pascal
uses
  SysUtils, DateUtils, babel.core, babel.support, babel.cldr_all;

var
  F: TFormat;
  T: TDateTime;
begin
  T := EncodeDateTime(2026, 10, 13, 14, 30, 5, 0);   // UTC
  F := TFormat.Create('es_PE', 'America/Lima');
```

`TFormat.Create` takes the locale (a `TLocale`, or a string that converts
to one), the time zone (an IANA tz database name; `''` is UTC) and the
numbering system (`'latn'` by default). The three are fields of the
record (`Locale`, `TimeZone`, `NumberingSystem`) and can be changed
afterwards.

## Dates and times

`Date` formats the date of the value as it is, without a time zone.
`DateTime` and `Time` take a UTC value and show it in the bound time
zone. The format is `'short'`, `'medium'` (default), `'long'`, `'full'` or
a date pattern (see [Date and Time](dates.md)).

```pascal
  WriteLn(F.Date(T));                  // 13 oct. 2026
  WriteLn(F.Date(T, 'full'));          // martes, 13 de octubre de 2026
  WriteLn(F.DateTime(T));              // 13 oct. 2026, 9:30:05 a. m.
  WriteLn(F.DateTime(T, 'short'));     // 13/10/26, 9:30 a. m.
  WriteLn(F.Time(T));                  // 9:30:05 a. m.
  WriteLn(F.Time(T, 'long'));          // 9:30:05 a. m. PET
```

## Durations

`Timedelta` formats a number of seconds in the largest unit that reaches
`Threshold` (0.85 by default), or in `Granularity` at the smallest.
`AddDirection` adds the direction ('in 3 days', '3 days ago').

```pascal
  WriteLn(F.Timedelta(3600));                                   // 1 hora
  WriteLn(F.Timedelta(-86400 * 3, 'second', 0.85, 'long', True)); // hace 3 días
  WriteLn(F.Timedelta(5400, 'hour', 0.85, 'short'));            // 2 h
```

## Numbers, currencies and percentages

The number methods take a `TDecimal`, which converts from integers,
doubles and decimal strings (see [Number Formatting](numbers.md)).

```pascal
  WriteLn(F.Number(1234567.891));                   // 1,234,567.891
  WriteLn(F.Decimal(1234.5, '#,##0.00'));           // 1,234.50
  WriteLn(F.CompactDecimal(1234567));               // 1 M
  WriteLn(F.CompactDecimal(1234567, 'long', 1));    // 1.2 millones
  WriteLn(F.Currency(1234.5, 'PEN'));               // S/ 1,234.50
  WriteLn(F.Currency(1234.5, 'USD'));               // USD 1,234.50
  WriteLn(F.CompactCurrency(1234567, 'PEN'));       // S/ 1 M
  WriteLn(F.Percent(0.256));                        // 26%
  WriteLn(F.Percent(0.256, '#,##0.0%'));            // 25.6%
  WriteLn(F.Scientific(1234.5));                    // 1.2345E3
```

## The locale's own digits

With the numbering system `'default'`, numbers, dates and times are
written in the locale's default digits:

```pascal
  F := TFormat.Create('ar_EG', 'Africa/Cairo', 'default');
  WriteLn(F.Number(1234.5));         // ١٬٢٣٤٫٥
  WriteLn(F.Time(T, 'short'));       // ٥:٣٠ م
```

## Lists

`FormatList` (unit `babel.lists`) joins items with the locale's
patterns. The style selects 'and' lists, 'or' lists or lists of
measurements.

```pascal
uses babel.lists;

  WriteLn(FormatList(['apples', 'oranges', 'pears'], 'en'));        // apples, oranges, and pears
  WriteLn(FormatList(['apples', 'oranges', 'pears'], 'en', 'or'));  // apples, oranges, or pears
  WriteLn(FormatList(['3 feet', '7 inches'], 'en', 'unit'));        // 3 feet, 7 inches
  WriteLn(FormatList(['A', 'B', 'C'], 'zh'));                       // A、B和C
  WriteLn(FormatList(['padre', 'hijo'], 'es'));                     // padre e hijo
```

See [List Formatting](api/lists.md).

## Measurement units

`FormatUnit` and `FormatCompoundUnit` (unit `babel.units`) write a value
with a unit in the locale's words or symbols.

```pascal
uses babel.units;

  WriteLn(FormatUnit(12, 'length-kilometer', 'en'));                       // 12 kilometers
  WriteLn(FormatUnit(12, 'kilometer', 'es', UnitOptions.WithLength('short'))); // 12 km
  WriteLn(FormatUnit(2, 'hour', 'ru'));                                    // 2 часа
  WriteLn(FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'en'));          // 150 kilometers per hour
  WriteLn(FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'en',
    UnitOptions.WithLength('short')));                                     // 150 km/h
```

See [Units](api/units.md).

## Languages of a territory

`GetOfficialLanguages` (unit `babel.languages`) gives the official
languages of a territory, the most spoken first; an application can use
it to choose a default language for a country.

```pascal
uses babel.languages;

  WriteLn(string.Join(', ', GetOfficialLanguages('CH')));        // de, fr, it
  WriteLn(string.Join(', ', GetOfficialLanguages('PE')));        // es, qu
```

See [Languages](api/languages.md).

---

[Documentation index](index.md) · API: [babel.support](api/support.md)
