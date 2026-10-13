# Number Formatting

The unit `babel.numbers` formats and parses numbers, currencies and
percentages with the patterns and symbols of a locale. The numbers are
`TDecimal` values (unit `babel.decimal`), which convert implicitly from
`Int64`, `Double` and `string`, so every function accepts `1234`,
`1234.5` or `'1234.50'`.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

```pascal
uses babel.numbers, babel.cldr_all;

FormatDecimal(1234.5, 'en');       // 1,234.5
FormatDecimal(1234.5, 'de');       // 1.234,5
FormatDecimal(1234.5, 'fr');       // 1 234,5   (narrow no-break space)
FormatDecimal(1234.5, 'de_CH');    // 1’234.5
FormatDecimal(12345678.5, 'en_IN'); // 1,23,45,678.5
FormatDecimal(-1234.5, 'sv');      // −1 234,5  (the locale's minus sign)
```

The locale's standard decimal pattern shows up to three fraction digits:

```pascal
FormatDecimal(1.2345, 'en');       // 1.234
```

A locale's minimum grouping digits apply: in Spanish and Polish a
four-digit number has no group separator.

```pascal
FormatDecimal(1234.5, 'es');       // 1234,5
FormatDecimal(12345.5, 'es');      // 12.345,5
FormatDecimal(12345, 'pl');        // 12 345
```

## Currencies

```pascal
FormatCurrency(1099.98, 'USD', 'en');      // $1,099.98
FormatCurrency(1099.98, 'EUR', 'en_US');   // €1,099.98
FormatCurrency(1099.98, 'EUR', 'de_DE');   // 1.099,98 €
FormatCurrency(1234.5, 'PEN', 'es_PE');    // S/ 1,234.50
FormatCurrency(1234.5, 'JPY', 'ja');       // ￥1,234
```

A currency is written with the number of fraction digits CLDR gives it
(2 for USD, 0 for JPY, 3 for KWD). When the symbol is a code or ends in a
letter, a no-break space separates it from the digits:

```pascal
FormatCurrency(1, 'PEN', 'en');            // PEN 1.00
```

Options are fields of a `TCurrencyOptions` record. `CurrencyOptions`
returns the defaults and each `With*` method returns a changed copy:

```pascal
FormatCurrency(-1234.5, 'USD', 'en',
  CurrencyOptions.WithFormatType('accounting'));   // ($1,234.50)
FormatCurrency(2, 'USD', 'en',
  CurrencyOptions.WithFormatType('name'));         // 2.00 US dollars
FormatCurrency(1234.5, 'EUR', 'es',
  CurrencyOptions.WithFormatType('name'));         // 1234,50 euros
FormatCurrency(1234.5678, 'USD', 'en',
  CurrencyOptions.WithCurrencyDigits(False));      // $1,234.57
```

With the format type `'name'`, the currency name takes the plural form of
the number as shown: `1` is shown `1.00`, which in English is plural.

```pascal
FormatCurrency(1, 'USD', 'en',
  CurrencyOptions.WithFormatType('name'));         // 1.00 US dollars
```

## Percentages and scientific notation

```pascal
FormatPercent(0.34, 'en');         // 34%
FormatPercent(0.34, 'de');         // 34 %
FormatPercent(1.5, 'en');          // 150%
FormatPercent(-0.05, 'sv');        // −5 %
FormatPercent(0.3456, 'en',
  NumberOptions.WithFormat('#,##0.0%'));   // 34.6%

FormatScientific(1234567, 'en');   // 1.234567E6
FormatScientific(0.000123, 'en');  // 1.23E-4
FormatScientific(1234567, 'en',
  NumberOptions.WithFormat('0.00E00'));    // 1.23E06
```

## Compact numbers

```pascal
FormatCompactDecimal(1234567, 'en');                   // 1M
FormatCompactDecimal(1234567, 'en',
  CompactOptions.WithFormatType('long'));              // 1 million
FormatCompactDecimal(1234567, 'en',
  CompactOptions.WithFormatType('long').WithFractionDigits(2));  // 1.23 million
FormatCompactDecimal(1234567, 'de',
  CompactOptions.WithFormatType('long'));              // 1 Million
FormatCompactDecimal(123456789, 'ja');                 // 1億
FormatCompactDecimal(999999, 'en');                    // 1M

FormatCompactCurrency(1234567, 'USD', 'en');           // $1M
FormatCompactCurrency(1234567, 'EUR', 'de',
  CompactOptions.WithFractionDigits(1));               // 1,2 Mio. €
```

The number is rounded to `FractionDigits` fraction digits. When rounding
reaches the next magnitude, that magnitude is used (`999999` is `1M`).

## Pattern syntax

A pattern given in the `Format` option replaces the locale's pattern. The
syntax is CLDR's number pattern syntax (UTS #35, Part 3):

| Symbol | Meaning |
|--------|---------|
| `0` | A digit, shown even when it is a leading or trailing zero |
| `#` | A digit, not shown when it is a leading or trailing zero |
| `@` | A significant digit (cannot be combined with `0` or `.`) |
| `.` | The decimal separator (written as the locale's symbol) |
| `,` | The group separator (written as the locale's symbol); its positions give the group sizes |
| `;` | Separates the positive and the negative subpattern |
| `-` | The minus sign (written as the locale's symbol) |
| `+` | The plus sign (written as the locale's symbol) |
| `%` | Multiplies by 100 and shows the percent sign |
| `‰` | Multiplies by 1000 and shows the per mille sign |
| `E` | Separates the mantissa and the exponent (scientific notation) |
| `¤` | The currency symbol (`¤¤` the code, `¤¤¤` the name) |
| `'` | Quotes literal text; `''` is an apostrophe |

```pascal
FormatDecimal(1.2345, 'en', NumberOptions.WithFormat('#,##0.##'));   // 1.23
FormatDecimal(1.2, 'en', NumberOptions.WithFormat('#,##0.00'));      // 1.20
FormatDecimal(12345, 'en', NumberOptions.WithFormat('#,##0.00'));    // 12,345.00
FormatDecimal(1234.5, 'de', NumberOptions.WithFormat('#,##0.00'));   // 1.234,50
FormatDecimal(42, 'en', NumberOptions.WithFormat('0000'));           // 0042
FormatDecimal(1234567, 'en', NumberOptions.WithFormat('#,##,##0'));  // 12,34,567
FormatDecimal(-3.14, 'en', NumberOptions.WithFormat('0.0;(0.0)'));   // (3.1)
FormatDecimal(5, 'en', NumberOptions.WithFormat('+0;-0'));           // +5
FormatDecimal(12345.678, 'en', NumberOptions.WithFormat('@@@'));     // 12300
FormatDecimal(1.5, 'en', NumberOptions.WithFormat('@@##'));          // 1.5
FormatDecimal(0.25, 'en', NumberOptions.WithFormat('#0‰'));          // 250‰
FormatDecimal(0.5, 'en', NumberOptions.WithFormat('0.0''%'''));      // 0.5%
FormatDecimal(1234.5, 'en', NumberOptions.WithFormat('''#''0'));     // #1234
FormatDecimal(1234, 'en', NumberOptions.WithFormat('0.###E0'));      // 1.234E3
FormatDecimal(0.00123, 'en', NumberOptions.WithFormat('00.###E+00')); // 12.3E-04
FormatCurrency(1234.5, 'USD', 'en',
  CurrencyOptions.WithFormat('#,##0.00 ¤¤'));                        // 1,234.50 USD
FormatCurrency(1234.5, 'USD', 'en',
  CurrencyOptions.WithFormat('#,##0.00 ¤¤¤'));                       // 1,234.50 US dollars
```

A quoted `%` is literal text and does not scale the number. In
`FormatDecimal`, which has no currency, `¤` is written as is.

The signs in a pattern are the locale's: a pattern's `-` is written as the
Swedish minus sign `−`, its `,` as the German `.`.

A pattern that mixes `@` with `0` or `.` raises `EBabelValueError`:

```pascal
FormatDecimal(1, 'en', NumberOptions.WithFormat('@@0.0'));
// EBabelValueError: Significant digit patterns can not contain "@" or "0"
```

## Rounding

Numbers are rounded half to even, on the exact decimal value:

```pascal
FormatDecimal(0.5, 'en', NumberOptions.WithFormat('0'));     // 0
FormatDecimal(1.5, 'en', NumberOptions.WithFormat('0'));     // 2
FormatDecimal(2.5, 'en', NumberOptions.WithFormat('0'));     // 2
FormatDecimal(2.665, 'en', NumberOptions.WithFormat('0.00')); // 2.66
FormatDecimal(2.675, 'en', NumberOptions.WithFormat('0.00')); // 2.68
```

A `Double` becomes the shortest decimal that converts back to the same
`Double`: `2.675` is the decimal 2.675, and rounds to `2.68`.
`TDecimal.FromDoubleExact` gives the exact binary value instead:

```pascal
uses babel.decimal;

TDecimal(2.675).ToString;                    // 2.675
TDecimal.FromDoubleExact(2.675).ToString;    // 2.67499999999999982236431605997495353221893310546875
FormatDecimal(TDecimal.FromDoubleExact(2.675), 'en',
  NumberOptions.WithFormat('0.00'));         // 2.67
```

A string keeps its digits, including trailing zeros:

```pascal
TDecimal('12.50').ToString;                  // 12.50
```

The arithmetic is exact for numbers of any number of digits:

```pascal
FormatDecimal('123456789012345678901234567890.123', 'en');
// 123,456,789,012,345,678,901,234,567,890.123
```

### Decimal quantization

By default the number is rounded to the maximum fraction digits of the
pattern. With `DecimalQuantization` set to `False`, every fraction digit
of the number is shown (at least the pattern's minimum):

```pascal
FormatDecimal('1.23456', 'en');                                            // 1.235
FormatDecimal('1.23456', 'en', NumberOptions.WithDecimalQuantization(False)); // 1.23456
FormatDecimal('1.2000', 'en', NumberOptions.WithDecimalQuantization(False));  // 1.2
```

`GroupSeparator` set to `False` leaves out the group separators:

```pascal
FormatDecimal(1234567.5, 'en', NumberOptions.WithGroupSeparator(False));  // 1234567.5
```

## Numbering systems

The `NumberingSystem` option chooses the digits and symbols. `'latn'` (the
default) gives ASCII digits; `'default'` gives the locale's default
numbering system; any system the locale has can be named:

```pascal
FormatDecimal(1234.5, 'ar_EG');                                          // 1,234.5
FormatDecimal(1234.5, 'ar_EG', NumberOptions.WithNumberingSystem('default')); // ١٬٢٣٤٫٥
FormatDecimal(1234.5, 'fa', NumberOptions.WithNumberingSystem('default'));    // ۱٬۲۳۴٫۵
FormatDecimal(1234.5, 'hi', NumberOptions.WithNumberingSystem('deva'));       // १,२३४.५
FormatDecimal(1234.5, 'th', NumberOptions.WithNumberingSystem('thai'));       // ๑,๒๓๔.๕
FormatCurrency(1234.5, 'USD', 'fa',
  CurrencyOptions.WithNumberingSystem('default'));                       // ‎$۱٬۲۳۴٫۵۰
```

A name that is not `'latn'`, `'default'` or a numeric system of CLDR
raises `EUnsupportedNumberingSystemError`, as does a system the locale has
no symbols for:

```pascal
FormatDecimal(1234.5, 'en', NumberOptions.WithNumberingSystem('zzzz'));
// EUnsupportedNumberingSystemError: Unknown numbering system zzzz for Locale en.
```

The symbols of a numbering system:

```pascal
GetDecimalSymbol('de');          // ,
GetGroupSymbol('de');            // .
GetGroupSymbol('fr');            //   (narrow no-break space)
GetMinusSignSymbol('sv');        // −
GetPlusSignSymbol('en');         // +
GetExponentialSymbol('en');      // E
GetInfinitySymbol('en');         // ∞
```

## Currency data

```pascal
GetCurrencyName('USD', 'en');          // US Dollar
GetCurrencyName('USD', 'es');          // dólar estadounidense
GetCurrencyName('USD', 2, 'en');       // US dollars
GetCurrencySymbol('USD', 'en');        // $
GetCurrencySymbol('USD', 'es');        // US$
GetCurrencySymbol('USD', 'es_MX');     // USD
GetCurrencyPrecision('USD');           // 2
GetCurrencyPrecision('JPY');           // 0
GetCurrencyPrecision('KWD');           // 3
GetCurrencyUnitPattern('USD', 'en');   // {0} {1}
NormalizeCurrency('usd');              // USD
NormalizeCurrency('xyz');              // '' (not a currency)
IsCurrency('EUR');                     // True
ValidateCurrency('XYZ');
// EUnknownCurrencyError: Unknown currency 'XYZ'.
FormatCurrency(1, 'usd', 'en');
// EUnknownCurrencyError: Unknown currency 'usd'.
```

Every function that takes a currency code raises `EUnknownCurrencyError`
for a code that is not a currency; codes are upper case, and
`NormalizeCurrency` converts one.

`ListCurrencies` gives the ISO 4217 codes of the global data (307), or
those a locale names (282 for `'es'`).

The currencies of a territory, on a date or in a period (today by
default):

```pascal
GetTerritoryCurrencies('PE');          // ['PEN']
GetTerritoryCurrencies('DE',
  TerritoryCurrencyOptions.WithStartDate(EncodeDate(1999, 6, 1)));  // ['DEM', 'EUR']
```

`GetTerritoryCurrencyDetails` adds the dates and whether the currency is
legal tender (a date of 0 means none):

```pascal
var C: TCurrencyPeriod;
for C in GetTerritoryCurrencyDetails('DE', TerritoryCurrencyOptions
    .WithStartDate(EncodeDate(1990, 1, 1)).WithEndDate(EncodeDate(2026, 1, 1))) do
  ...
// DEM  1948-06-20  2002-02-28  tender
// EUR  1999-01-01  -           tender
```

## Parsing numbers

`ParseDecimal` reads a number written in the locale's format: its decimal
and group symbols, its minus and plus signs, and digits of any script.
`ParseNumber` reads an integer into an `Int64`.

```pascal
ParseDecimal('1,099.98', 'en').ToString;     // 1099.98
ParseDecimal('1.099,98', 'de').ToString;     // 1099.98
ParseDecimal('1 099,98', 'fr').ToString;     // 1099.98
ParseDecimal('−1 234,5', 'sv').ToString;     // -1234.5
ParseDecimal('١٬٢٣٤٫٥', 'ar_EG',
  ParseOptions.WithNumberingSystem('default')).ToString;  // 1234.5
ParseNumber('1,099', 'en');                  // 1099
ParseNumber('1.099', 'de');                  // 1099
```

Text that is not a number raises `ENumberFormatError`; an integer beyond
`Int64` raises `EBabelOverflowError`:

```pascal
ParseDecimal('2,109,998x', 'en');
// ENumberFormatError: '2,109,998x' is not a valid decimal number
ParseNumber('1.099,98', 'de');
// ENumberFormatError: '1.099,98' is not a valid number
ParseNumber('99999999999999999999', 'en');
// EBabelOverflowError: 99999999999999999999 does not fit in an Int64
```

By default the group symbols are removed wherever they are. With
`StrictMode`, a group symbol in a wrong place raises `ENumberFormatError`,
whose `Suggestions` field holds the correctly formatted readings:

```pascal
ParseDecimal('11,11', 'en').ToString;        // 1111
ParseDecimal('11,11', 'en', ParseOptions.WithStrict(True));
// ENumberFormatError: '11,11' is not a properly formatted decimal number.
//   Did you mean '1,111'? Or maybe '11.11'?
```

---

[Index](index.md) · [API: babel.numbers](api/numbers.md)
