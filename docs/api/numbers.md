# Numbers and Currencies

Units `babel.numbers` (formatting and parsing of numbers, currencies and
percentages) and `babel.decimal` (the exact decimal type the numbers are
given in). See the [Number Formatting](../numbers.md) guide for examples.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

Every function that takes a locale takes a `TLocale`, which converts
implicitly from an identifier string (`'es_PE'`). Everything here only
reads shared data and can be called from several threads.

## babel.numbers

### Exceptions

`EUnknownCurrencyError = class(EBabelError)`
: A currency code that is not in the data, in any letter case (`'xyz'`;
  `'usd'` is `'USD'`). Field `Identifier: string` holds the code. Raised by
  `ValidateCurrency` and by every function that takes a currency code:
  `GetCurrencyName`, `GetCurrencySymbol`, `GetCurrencyPrecision`,
  `GetCurrencyUnitPattern`, `FormatCurrency`, `FormatCompactCurrency`.

`EUnsupportedNumberingSystemError = class(EBabelError)`
: A numbering system that is not `'latn'`, `'default'` or a numeric
  system of CLDR (`'zzzz'`, the algorithmic `'roman'`), or one the locale
  has no symbols for.

`EUnknownCurrencyFormatError = class(EBabelKeyError)`
: A currency format type other than `'standard'`, `'accounting'` and
  `'name'`.

`ENumberFormatError = class(EBabelValueError)`
: Text that `ParseDecimal` or `ParseNumber` cannot read. Field
  `Suggestions: TStringArray` holds the correctly formatted readings of
  the input when `ParseDecimal` runs with `StrictMode`.

### Option records

Each option record has a function that returns its defaults and `With*`
methods that return a changed copy. A record not made by that function
has `False` and `''` where the defaults are `True` and `'latn'`: always
start from the function.

```pascal
FormatDecimal(X, 'en', NumberOptions.WithFormat('#,##0.00').WithGroupSeparator(False));
```

#### TNumberOptions

Options of `FormatDecimal`, `FormatPercent` and `FormatScientific`.
Defaults: `NumberOptions`.

| Field                          | Default  | Meaning |
|--------------------------------|----------|---------|
| `Format: string`               | `''`     | The number pattern; `''` is the locale's |
| `DecimalQuantization: Boolean` | `True`   | Round to the pattern's maximum fraction digits; `False` shows every fraction digit of the number |
| `GroupSeparator: Boolean`      | `True`   | Write group separators |
| `NumberingSystem: string`      | `'latn'` | The numbering system; `'default'` is the locale's |

Methods: `WithFormat`, `WithDecimalQuantization`, `WithGroupSeparator`,
`WithNumberingSystem`.

#### TCurrencyOptions

Options of `FormatCurrency`. Defaults: `CurrencyOptions`.

| Field                          | Default      | Meaning |
|--------------------------------|--------------|---------|
| `Format: string`               | `''`         | The pattern; `''` is the locale's pattern for `FormatType` |
| `CurrencyDigits: Boolean`      | `True`       | Use the currency's fraction digits (2 for USD, 0 for JPY) instead of the pattern's |
| `FormatType: string`           | `'standard'` | `'standard'`, `'accounting'` or `'name'` (the currency's name, in the plural form of the number as shown) |
| `DecimalQuantization: Boolean` | `True`       | As in `TNumberOptions` |
| `GroupSeparator: Boolean`      | `True`       | As in `TNumberOptions` |
| `NumberingSystem: string`      | `'latn'`     | As in `TNumberOptions` |

Methods: `WithFormat`, `WithCurrencyDigits`, `WithFormatType`,
`WithDecimalQuantization`, `WithGroupSeparator`, `WithNumberingSystem`.

#### TCompactOptions

Options of `FormatCompactDecimal` and `FormatCompactCurrency`. Defaults:
`CompactOptions`.

| Field                     | Default   | Meaning |
|---------------------------|-----------|---------|
| `FormatType: string`      | `'short'` | `'short'` (`1M`) or `'long'` (`1 million`); currencies have `'short'` only |
| `FractionDigits: Integer` | `0`       | The fraction digits of the abbreviated number |
| `NumberingSystem: string` | `'latn'`  | As in `TNumberOptions` |

Methods: `WithFormatType`, `WithFractionDigits`, `WithNumberingSystem`.

#### TParseOptions

Options of `ParseNumber` and `ParseDecimal`. Defaults: `ParseOptions`.

| Field                     | Default  | Meaning |
|---------------------------|----------|---------|
| `StrictMode: Boolean`     | `False`  | `ParseDecimal` only: reject group symbols in wrong places |
| `NumberingSystem: string` | `'latn'` | The symbols to read; `'default'` is the locale's |

Methods: `WithStrict`, `WithNumberingSystem`.

#### TTerritoryCurrencyOptions

Options of `GetTerritoryCurrencies` and `GetTerritoryCurrencyDetails`.
Defaults: `TerritoryCurrencyOptions`.

| Field                  | Default | Meaning |
|------------------------|---------|---------|
| `StartDate: TDateTime` | `0`     | The start of the period; `0` is today |
| `EndDate: TDateTime`   | `0`     | The end of the period; `0` is the start date |
| `Tender: Boolean`      | `True`  | Include currencies that are legal tender |
| `NonTender: Boolean`   | `False` | Include currencies that are not legal tender |

Methods: `WithStartDate`, `WithEndDate`, `WithTender`, `WithNonTender`.

### Types

`TCurrencyPeriod = record`
: One currency of a territory: `Currency: string`, `FromDate, ToDate:
  TDateTime` (0 means none), `Tender: Boolean`. `TCurrencyPeriods` is an
  array of them.


### Option defaults

```pascal
function NumberOptions: TNumberOptions;
function CurrencyOptions: TCurrencyOptions;
function CompactOptions: TCompactOptions;
function ParseOptions: TParseOptions;
function TerritoryCurrencyOptions: TTerritoryCurrencyOptions;
```

### Currencies

```pascal
function ListCurrencies: TStringArray;
function ListCurrencies(const Locale: TLocale): TStringArray;
```
The ISO 4217 codes of the global data, or those the locale names; sorted.

```pascal
procedure ValidateCurrency(const Currency: string);
procedure ValidateCurrency(const Currency: string; const Locale: TLocale);
```
Raises `EUnknownCurrencyError` when the code, in any letter case, is not
listed.

```pascal
function IsCurrency(const Currency: string): Boolean;
function IsCurrency(const Currency: string; const Locale: TLocale): Boolean;
```
Whether the code, in any letter case, is listed.

```pascal
function NormalizeCurrency(const Currency: string): string;
function NormalizeCurrency(const Currency: string; const Locale: TLocale): string;
```
The code in upper case when it is a currency (`'usd'` gives `'USD'`);
`''` otherwise.

```pascal
function GetCurrencyName(const Currency: string; const Locale: TLocale): string;
function GetCurrencyName(const Currency: string; const Count: TDecimal; const Locale: TLocale): string;
```
The currency's name (`'US Dollar'`); with `Count`, the plural form for
that count (`'US dollars'`). The code when the locale has no name.
Raises `EUnknownCurrencyError` for a code that is not a currency.

```pascal
function GetCurrencySymbol(const Currency: string; const Locale: TLocale): string;
```
The symbol (`'$'` in `en`, `'US$'` in `es`); the code when the locale has
none. Raises `EUnknownCurrencyError` for a code that is not a currency.

```pascal
function GetCurrencyPrecision(const Currency: string): Integer;
```
The currency's number of fraction digits; 2 when CLDR gives none for the
currency. Raises `EUnknownCurrencyError` for a code that is not a
currency.

```pascal
function GetCurrencyUnitPattern(const Currency: string; const Locale: TLocale): string;
function GetCurrencyUnitPattern(const Currency: string; const Count: TDecimal; const Locale: TLocale): string;
```
The pattern that joins a number and a currency name (`'{0} {1}'`), for a
count. Raises `EUnknownCurrencyError` for a code that is not a currency.

```pascal
function GetTerritoryCurrencies(const Territory: string): TStringArray;
function GetTerritoryCurrencies(const Territory: string; const Options: TTerritoryCurrencyOptions): TStringArray;
function GetTerritoryCurrencyDetails(const Territory: string; const Options: TTerritoryCurrencyOptions): TCurrencyPeriods;
```
The currencies of a territory in use during the options' period (today by
default), in CLDR's order; the details add each currency's dates and
whether it is legal tender.

### Number symbols

```pascal
function GetDecimalSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetPlusSignSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetMinusSignSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetExponentialSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetGroupSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetInfinitySymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
```
The symbols of a numbering system of the locale (`'default'` is the
locale's default system). Raise `EUnsupportedNumberingSystemError` for a
system the locale does not have (`'foo'`); the formatting and parsing
functions raise it too.

### Precision

```pascal
function GetDecimalPrecision(const Number: TDecimal): Integer;
function GetDecimalQuantum(Precision: Int64): TDecimal;
```
`GetDecimalPrecision`: the number of fraction digits of the normalized
number (`'1.2300'` gives 2). `GetDecimalQuantum`: 10<sup>−Precision</sup>
(`3` gives `0.001`).

### Formatting

```pascal
function FormatDecimal(const Number: TDecimal; const Locale: TLocale): string;
function FormatDecimal(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string;
```
The number in the locale's decimal pattern or `Options.Format`
(`1234.5` in `en`: `1,234.5`).

```pascal
function FormatDecimalShown(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions;
  out Shown: TDecimal): string;
```
`FormatDecimal`, and in `Shown` the number as shown (rounded, with its
fraction digits), from which plural forms are chosen.

```pascal
function FormatCompactDecimal(const Number: TDecimal; const Locale: TLocale): string;
function FormatCompactDecimal(const Number: TDecimal; const Locale: TLocale; const Options: TCompactOptions): string;
```
The number abbreviated with the locale's compact patterns (`1234567` in
`en`: `1M`, long: `1 million`).

```pascal
function FormatCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale): string;
function FormatCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale;
  const Options: TCurrencyOptions): string;
```
The amount in the locale's currency pattern (`1099.98`, `'USD'`, `en`:
`$1,099.98`). Raises `EUnknownCurrencyError` for a code that is not a
currency (`'XYZ'`; `'usd'` is `'USD'`) and `EUnknownCurrencyFormatError` for an
unknown format type.

```pascal
function FormatCompactCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale): string;
function FormatCompactCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale;
  const Options: TCompactOptions): string;
```
The amount abbreviated (`1234567`, `'USD'`, `en`: `$1M`). Raises
`EUnknownCurrencyError` for a code that is not a currency.

```pascal
function FormatPercent(const Number: TDecimal; const Locale: TLocale): string;
function FormatPercent(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string;
```
The number as a percentage (`0.34` in `en`: `34%`).

```pascal
function FormatScientific(const Number: TDecimal; const Locale: TLocale): string;
function FormatScientific(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string;
```
The number in scientific notation (`1234567` in `en`: `1.234567E6`). The
scientific format has no group separators.

### Parsing

```pascal
function ParseNumber(const S: string; const Locale: TLocale): Int64;
function ParseNumber(const S: string; const Locale: TLocale; const Options: TParseOptions): Int64;
```
An integer written in the locale's format (`'1,099'` in `en`), with the
locale's minus and plus signs and digits of any script. Raises
`ENumberFormatError` for text that is not an integer and
`EBabelOverflowError` beyond `Int64`.

```pascal
function ParseDecimal(const S: string; const Locale: TLocale): TDecimal;
function ParseDecimal(const S: string; const Locale: TLocale; const Options: TParseOptions): TDecimal;
```
A decimal number written in the locale's format: its decimal and group
symbols, its minus and plus signs, digits of any script. Raises
`ENumberFormatError`. With `StrictMode`, a misplaced group symbol raises
`ENumberFormatError` with suggestions.

### Digits

```pascal
function SystemDigits(const Locale: TLocale; const NumberingSystem: string): TCodePoints;
function LocalizeDigits(const S: string; const Digits: TCodePoints): string;
```
`SystemDigits`: the ten digits of a numbering system (`'default'` is the
locale's), as code points; `nil` for `'latn'`. Raises
`EUnsupportedNumberingSystemError` for a system that is not `'latn'`,
`'default'` or a numeric system of CLDR.
`LocalizeDigits`: `S` with its ASCII digits written in `Digits`
(unchanged when `Digits` is `nil`).

## babel.decimal

### TDecimal

```pascal
type
  TDecimalKind = (dkFinite, dkInfinity, dkNaN);
  TDecimal = record ... end;
```

An exact decimal number: a sign, a string of coefficient digits and a
base-10 exponent (`12.50` is digits `1250`, exponent −2), or Infinity or
NaN. Trailing zeros are kept: they are the visible fraction digits in
formatting and in plural rules. The arithmetic is exact, with no
precision limit. `TDecimal` is a value type; nothing needs freeing.

#### Conversions

```pascal
class operator :=(V: Int64): TDecimal;
class operator :=(V: Double): TDecimal;
class operator :=(const S: string): TDecimal;
```

A function that takes a `TDecimal` accepts `1234`, `1234.5` or
`'1234.50'`:

- from `Int64`: the integer;
- from `Double`: the shortest decimal that converts back to the same
  `Double` (`2.675` is 2.675);
- from `string`: an optional sign, digits with an optional `.`, an
  optional exponent (`1.5E+3`), or `Infinity`/`Inf`/`NaN` in any case,
  with whitespace around; decimal digits of any script (`'١٢٣'` is 123).
  An invalid string raises `EBabelValueError`.

```pascal
class function Parse(const S: string): TDecimal; static;
class function TryParse(const S: string; out Value: TDecimal): Boolean; static;
class function FromInt64(V: Int64): TDecimal; static;
class function FromDouble(V: Double): TDecimal; static;
class function FromDoubleExact(V: Double): TDecimal; static;
class function Make(Negative: Boolean; const Digits: string; Exponent: Int64): TDecimal; static;
class function Pow10(N: Int64): TDecimal; static;
```
`Parse` raises `EBabelValueError` for text that is not a number;
`TryParse` returns `False`. `FromDouble` is the implicit conversion;
`FromDoubleExact` gives the exact binary value
(`2.67499999999999982236431605997495353221893310546875`). `Make` builds a
finite value from its parts (ASCII digits, may be `''` for zero).
`Pow10` gives 10<sup>N</sup>.

#### Properties and tests

| Member                            | Meaning |
|-----------------------------------|---------|
| `Kind: TDecimalKind`              | `dkFinite`, `dkInfinity` or `dkNaN` |
| `Negative: Boolean`               | The sign |
| `Digits: string`                  | The coefficient digits (`''` for NaN, `'0'` for Infinity) |
| `Exponent: Int64`                 | The exponent (finite values) |
| `IsFinite`, `IsNaN`, `IsInfinite` | The kind |
| `IsZero`                          | Finite and zero |
| `IsIntegral`                      | Finite with no fraction |
| `IsSigned`                        | The sign bit (also for −0 and −NaN) |
| `Adjusted: Int64`                 | The exponent of the most significant digit (0 for Infinity and NaN) |

#### Operations

| Method                        | Result |
|-------------------------------|--------|
| `ToString: string`            | The value in scientific-string notation: `'12.50'`, `'1E+3'`, `'1E-7'`, `'-0'`, `'Infinity'`, `'NaN'` |
| `FormatFixed: string`         | Every digit in positional notation (`'1.2E+3'` is `'1200'`) |
| `Abs                          | The absolute value |
| `Truncate`                    | The value truncated toward zero, as an integer; raises `EBabelValueError` for NaN and Infinity |
| `Normalize`                   | Trailing zeros removed (`1200` is `1.2E+3`) |
| `ScaleB(N)`                   | The value times 10<sup>N</sup> |
| `Multiply(B)`                 | The exact product |
| `Divide(B, Precision = 28)`   | The quotient rounded half to even to `Precision` significant digits; raises `EBabelDecimalError` for a division by zero |
| `Quantize(Exp)`               | Rounded half to even to the exponent `Exp`; raises `EBabelDecimalError` for Infinity |
| `Round(N)`                    | `Quantize(-N)`: `N` fraction digits |
| `Compare(B)`, `CompareInt(B)` | −1, 0 or 1; raises `EBabelValueError` for NaN |
| `ModInt(M)`                   | The remainder of the division by `M` (> 0), with the value's sign; finite values |
| `TryToInt64(out V)`           | The value as `Int64` when it is an integer that fits |

```pascal
TDecimal('1.50').Multiply('2').ToString;   // 3.00
TDecimal(1).Divide(3, 10).ToString;        // 0.3333333333
TDecimal('2.675').Round(2).ToString;       // 2.68
TDecimal('1200').Normalize.ToString;       // 1.2E+3
TDecimal('1.2E+3').FormatFixed;            // 1200
```

An invalid operation (Infinity × 0, 0 ÷ 0) and a division by zero raise
`EBabelDecimalError`.

### ShortestFloatRepr

```pascal
function ShortestFloatRepr(X: Double): string;
```
The shortest text that converts back to `X`: `'0.1'`, `'1e+16'`,
`'0.30000000000000004'`, `'inf'`, `'nan'`, `'-0.0'`.

---

[Index](../index.md) · [Guide: Number Formatting](../numbers.md)
