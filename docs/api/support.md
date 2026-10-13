# General Support Functionality

Unit `babel.support`.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

```pascal
uses babel.support;
```

The unit declares `TFormat`, a record that holds a locale, a time zone
and a numbering system, and whose methods call the formatting functions
of `babel.dates` and `babel.numbers` with them. A `TFormat` is a value:
copying it copies its fields, and its methods only read shared data, so
it can be used from several threads.

## TFormat

```pascal
type
  TFormat = record
    Locale: TLocale;
    TimeZone: string;
    NumberingSystem: string;
    class function Create(const ALocale: TLocale; const ATimeZone: string = '';
      const ANumberingSystem: string = 'latn'): TFormat; static;
    function Date(D: TDateTime; const Format: string = 'medium'): string;
    function DateTime(UTC: TDateTime; const Format: string = 'medium'): string;
    function Time(UTC: TDateTime; const Format: string = 'medium'): string;
    function Timedelta(Seconds: Int64; const Granularity: string = 'second';
      Threshold: Double = 0.85; const Format: string = 'long'; AddDirection: Boolean = False): string;
    function Number(const N: TDecimal): string;
    function Decimal(const N: TDecimal; const Format: string = ''): string;
    function CompactDecimal(const N: TDecimal; const FormatType: string = 'short';
      FractionDigits: Integer = 0): string;
    function Currency(const N: TDecimal; const CurrencyCode: string): string;
    function CompactCurrency(const N: TDecimal; const CurrencyCode: string;
      const FormatType: string = 'short'; FractionDigits: Integer = 0): string;
    function Percent(const N: TDecimal; const Format: string = ''): string;
    function Scientific(const N: TDecimal): string;
  end;
```

### Fields

- `Locale`: the locale of every method.
- `TimeZone`: the IANA tz database name in which `DateTime` and `Time`
  show their UTC values; `''` is UTC.
- `NumberingSystem`: the digits of numbers, dates and times: `'latn'`
  (ASCII digits), `'default'` (the locale's default system) or a CLDR
  numbering system id with decimal digits (`'arab'`, `'deva'`...). Any
  other value raises `EUnsupportedNumberingSystemError` when a method
  formats.

### TFormat.Create

```pascal
class function Create(const ALocale: TLocale; const ATimeZone: string = '';
  const ANumberingSystem: string = 'latn'): TFormat; static;
```

A `TFormat` with the three fields set. `ALocale` accepts a string
(`'es_PE'`), converted as `TLocale` converts identifiers.

```pascal
F := TFormat.Create('es_PE', 'America/Lima');
F := TFormat.Create('ar_EG', 'Africa/Cairo', 'default');
F := TFormat.Create('en');            // UTC, ASCII digits
```

Errors: an unknown locale raises `EUnknownLocaleError` (from the `TLocale`
conversion). The time zone is checked when `DateTime` or `Time` uses it.

### TFormat.Date

```pascal
function Date(D: TDateTime; const Format: string = 'medium'): string;
```

`FormatDate` of `D` in `Locale`: the date as it is, without a time zone.
`Format` is `'short'`, `'medium'`, `'long'`, `'full'` or a date pattern.

```pascal
F := TFormat.Create('es_PE', 'America/Lima');
F.Date(EncodeDate(2026, 10, 13));           // '13 oct. 2026'
F.Date(EncodeDate(2026, 10, 13), 'full');   // 'martes, 13 de octubre de 2026'
```

### TFormat.DateTime

```pascal
function DateTime(UTC: TDateTime; const Format: string = 'medium'): string;
```

`FormatDateAndTime` of the UTC value `UTC`, shown in `TimeZone`.

```pascal
T := EncodeDateTime(2026, 10, 13, 14, 30, 5, 0);
TFormat.Create('es_PE', 'America/Lima').DateTime(T);           // '13 oct. 2026, 9:30:05 a. m.'
TFormat.Create('en').DateTime(T, 'full');
  // 'Tuesday, October 13, 2026 at 2:30:05 PM Coordinated Universal Time'
```

Errors: an unknown time zone raises `EUnknownTimeZoneError`.

### TFormat.Time

```pascal
function Time(UTC: TDateTime; const Format: string = 'medium'): string;
```

`FormatTime` of the UTC value `UTC`, shown in `TimeZone`.

```pascal
F := TFormat.Create('es_PE', 'America/Lima');
F.Time(T);           // '9:30:05 a. m.'
F.Time(T, 'long');   // '9:30:05 a. m. PET'
```

### TFormat.Timedelta

```pascal
function Timedelta(Seconds: Int64; const Granularity: string = 'second';
  Threshold: Double = 0.85; const Format: string = 'long'; AddDirection: Boolean = False): string;
```

`FormatTimedelta` of a duration in seconds: the largest unit (year,
month, week, day, hour, minute, second) in which the duration reaches
`Threshold`, or `Granularity` at the smallest. `Format` is `'narrow'`,
`'short'` or `'long'`. `AddDirection` writes the direction (future for a
positive value, past for a negative one).

```pascal
F := TFormat.Create('es_PE');
F.Timedelta(3600);                                    // '1 hora'
F.Timedelta(-86400 * 3, 'second', 0.85, 'long', True); // 'hace 3 días'
F.Timedelta(5400, 'hour', 0.85, 'short');             // '2 h'
```

### TFormat.Number

```pascal
function Number(const N: TDecimal): string;
```

`FormatDecimal` of `N` with the locale's decimal pattern.

```pascal
TFormat.Create('es_PE').Number(1234567.891);   // '1,234,567.891'
TFormat.Create('ar_EG', '', 'default').Number(1234.5);   // '١٬٢٣٤٫٥'
```

### TFormat.Decimal

```pascal
function Decimal(const N: TDecimal; const Format: string = ''): string;
```

`FormatDecimal` of `N` with the pattern `Format` (`''`: the locale's).

```pascal
TFormat.Create('es_PE').Decimal(1234.5, '#,##0.00');   // '1,234.50'
```

### TFormat.CompactDecimal

```pascal
function CompactDecimal(const N: TDecimal; const FormatType: string = 'short';
  FractionDigits: Integer = 0): string;
```

`FormatCompactDecimal` of `N`: `FormatType` `'short'` ('1 M') or
`'long'` ('1 millón'), with at most `FractionDigits` fraction digits.

```pascal
F := TFormat.Create('es_PE');
F.CompactDecimal(1234567);              // '1 M'
F.CompactDecimal(1234567, 'long', 1);   // '1.2 millones'
```

### TFormat.Currency

```pascal
function Currency(const N: TDecimal; const CurrencyCode: string): string;
```

`FormatCurrency` of `N` in the currency `CurrencyCode` (ISO 4217), with
the currency's fraction digits.

```pascal
F := TFormat.Create('es_PE');
F.Currency(1234.5, 'PEN');   // 'S/ 1,234.50'
F.Currency(1234.5, 'USD');   // 'USD 1,234.50'
```

A code not in CLDR's currency data raises `EUnknownCurrencyError`
(`F.Currency(1, 'XYZ')`).

### TFormat.CompactCurrency

```pascal
function CompactCurrency(const N: TDecimal; const CurrencyCode: string;
  const FormatType: string = 'short'; FractionDigits: Integer = 0): string;
```

`FormatCompactCurrency` of `N` in `CurrencyCode`.

```pascal
TFormat.Create('es_PE').CompactCurrency(1234567, 'PEN');   // 'S/ 1 M'
```

### TFormat.Percent

```pascal
function Percent(const N: TDecimal; const Format: string = ''): string;
```

`FormatPercent` of `N` (0.25 is 25 %), with the pattern `Format` (`''`:
the locale's).

```pascal
F := TFormat.Create('es_PE');
F.Percent(0.256);                // '26%'
F.Percent(0.256, '#,##0.0%');    // '25.6%'
```

### TFormat.Scientific

```pascal
function Scientific(const N: TDecimal): string;
```

`FormatScientific` of `N` with the locale's scientific pattern.

```pascal
TFormat.Create('es_PE').Scientific(1234.5);   // '1.2345E3'
```

---

[API index](index.md) · [Documentation index](../index.md) · Guide: [Support Classes and Functions](../support.md)
