# Units

Unit `babel.units`.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

```pascal
uses babel.units;
```

Measurement units in the locale's words or symbols: '12 kilometers',
'12 km', '150 km/h'.

## Unit identifiers

A unit is named by its CLDR id, which starts with its category:
`'length-kilometer'`, `'duration-hour'`, `'mass-kilogram'`,
`'temperature-celsius'`, `'digital-gigabyte'`,
`'speed-kilometer-per-hour'`, `'concentr-percent'`. The end of an id is
also accepted (`'kilometer'`, `'hour'`): the shortest id that ends with
the given text is used (see `FindUnitPattern`).

## Lengths

- `'long'` (default): '12 kilometers'
- `'short'`: '12 km'
- `'narrow'`: '12km'

Where the locale has no data for the long or the narrow length of a
unit, the short length's data is used, as CLDR specifies. Another length
string matches no data, and the result is the number followed by the
unit's id.

## Plural forms

The pattern is chosen by the plural form of the number as it is shown,
not of the value: `'1.0'` is shown `1`, so the singular is used. A plural
form the locale has no pattern for uses the `'other'` pattern.

## TUnitOptions

```pascal
type
  TUnitOptions = record
    Length: string;
    Format: string;
    NumberingSystem: string;
    function WithLength(const Value: string): TUnitOptions;
    function WithFormat(const Value: string): TUnitOptions;
    function WithNumberingSystem(const Value: string): TUnitOptions;
  end;
```

- `Length`: `'long'` (default), `'short'` or `'narrow'`.
- `Format`: the number pattern of the value (`'#,##0.00'`); `''` (default)
  is the locale's decimal pattern.
- `NumberingSystem`: the digits of the value: `'latn'` (default),
  `'default'` (the locale's) or a CLDR numbering system id.

The `With*` methods return a copy with one field changed, so options
chain: `UnitOptions.WithLength('short').WithFormat('0.0')`.

## UnitOptions

```pascal
function UnitOptions: TUnitOptions;
```

The default options: `Length = 'long'`, `Format = ''`,
`NumberingSystem = 'latn'`.

## FormatUnit

```pascal
function FormatUnit(const Value: TDecimal; const MeasurementUnit: string;
  const Locale: TLocale): string; overload;
function FormatUnit(const Value: TDecimal; const MeasurementUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string; overload;
```

`Value` formatted as a number and placed in the unit's pattern for the
locale, the length and the plural form of the number shown.

```pascal
FormatUnit(12, 'length-kilometer', 'en');                                  // '12 kilometers'
FormatUnit(12, 'kilometer', 'es', UnitOptions.WithLength('short'));        // '12 km'
FormatUnit(12, 'kilometer', 'es', UnitOptions.WithLength('narrow'));       // '12km'
FormatUnit(1, 'meter', 'en');                                              // '1 meter'
FormatUnit('1.0', 'meter', 'en');                                          // '1 meter'
FormatUnit(1.5, 'hour', 'en');                                             // '1.5 hours'
FormatUnit(2, 'hour', 'ru');                                               // '2 часа'
FormatUnit(5, 'hour', 'ru');                                               // '5 часов'
FormatUnit(1234.5, 'meter', 'de');                                         // '1.234,5 Meter'
FormatUnit(1234.5, 'meter', 'en', UnitOptions.WithFormat('#,##0.00'));     // '1,234.50 meters'
FormatUnit(12, 'kilogram', 'ar_EG', UnitOptions.WithNumberingSystem('default'));  // '١٢ كيلوغرام'
FormatUnit(3, 'g-force', 'de');                                            // '3 G' (short data)
```

Errors: an unknown unit raises `EUnknownUnitError`:

```pascal
FormatUnit(1, 'banana', 'en');   // EUnknownUnitError: banana is not a known unit in en
```

## FormatUnitText

```pascal
function FormatUnitText(const FormattedValue, MeasurementUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string;
```

A value already formatted by the caller, placed in the unit's singular
(`'one'`) pattern. `Options.Format` and `Options.NumberingSystem` are not
used. (A separate function, because `TDecimal` converts from strings: an
overload of `FormatUnit` taking a string would be ambiguous.)

```pascal
FormatUnitText('one and a half', 'hour', 'en', UnitOptions);   // 'one and a half hour'
```

Errors: `EUnknownUnitError` for an unknown unit.

## FormatCompoundUnit

```pascal
function FormatCompoundUnit(const NumeratorValue: TDecimal; const NumeratorUnit: string;
  const DenominatorValue: TDecimal; const DenominatorUnit: string;
  const Locale: TLocale): string; overload;
function FormatCompoundUnit(const NumeratorValue: TDecimal; const NumeratorUnit: string;
  const DenominatorValue: TDecimal; const DenominatorUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string; overload;
```

A quantity per another: '150 kilometers per hour', '12 kg/m'.

- When both units are given, the denominator is 1 and the locale has a
  unit for the pair (`kilometer` and `hour` give
  `'speed-kilometer-per-hour'`), that unit is used.
- Otherwise the numerator is formatted (with its unit, or as a bare
  number when `NumeratorUnit` is `''`), and:
  - with a denominator of 1 and a denominator unit, the unit's
    "per" pattern of the locale is used ('{0} per meter'), or the
    compound pattern with the unit's name without a number;
  - else the denominator is formatted (with its unit or as a bare
    number) and both are joined with the locale's compound pattern
    ('{0}/{1}', '{0} per {1}').

```pascal
FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'en');                // '150 kilometers per hour'
FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'en',
  UnitOptions.WithLength('short'));                                   // '150 km/h'
FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'es');                // '150 kilómetros por hora'
FormatCompoundUnit(12, 'kilogram', 1, 'meter', 'en');                 // '12 kilograms per meter'
FormatCompoundUnit(12, 'kilogram', 1, 'meter', 'en',
  UnitOptions.WithLength('short'));                                   // '12 kg/m'
FormatCompoundUnit(5, 'kilometer', 1, 'byte', 'en');                 // '5 kilometers per byte'
FormatCompoundUnit(32, 'kilogram', 2, 'meter', 'en',
  UnitOptions.WithLength('short'));                                   // '32 kg/2 m'
FormatCompoundUnit(5, '', 1, 'hour', 'en');                           // '5 per hour'
FormatCompoundUnit(5, 'kilometer', 2, '', 'en');                      // '5 kilometers per 2'
FormatCompoundUnit(5, '', 2, '', 'en');                               // '5 per 2'
```

Errors: `EUnknownUnitError` for an unknown unit that has to be
formatted.

## FormatCompoundUnitText

```pascal
function FormatCompoundUnitText(const NumeratorValue, NumeratorUnit, DenominatorValue,
  DenominatorUnit: string; const Locale: TLocale; const Options: TUnitOptions): string;
```

`FormatCompoundUnit` with both values already formatted by the caller.
The values are placed as they are; a preformatted denominator is not
read as 1, so the compound pattern joins the two.

```pascal
FormatCompoundUnitText('7', 'liter', 'two', 'kilometer', 'en',
  UnitOptions.WithLength('short'));                                   // '7/two'
```

## GetUnitName

```pascal
function GetUnitName(const MeasurementUnit: string; const Locale: TLocale;
  const Length: string = 'long'): string;
```

The unit's display name in the locale; for the long and narrow lengths
the short name when the locale has none. `''` when the locale has no
name.

```pascal
GetUnitName('kilometer', 'en');               // 'kilometers'
GetUnitName('kilometer', 'en', 'short');      // 'km'
GetUnitName('length-kilometer', 'es');        // 'kilómetros'
GetUnitName('celsius', 'en', 'narrow');       // '°C'
```

Errors: `EUnknownUnitError` for an unknown unit.

## FindUnitPattern

```pascal
function FindUnitPattern(const UnitId: string; const Locale: TLocale): string;
```

The full id of a unit: `UnitId` itself when the locale has it, else the
shortest id that ends with `UnitId` (the first in the data among ids of
the same length); `''` when none does.

```pascal
FindUnitPattern('kilometer', 'en');            // 'length-kilometer'
FindUnitPattern('hour', 'en');                 // 'duration-hour'
FindUnitPattern('kilometer-per-hour', 'en');   // 'speed-kilometer-per-hour'
FindUnitPattern('banana', 'en');               // ''
```

The match is on the end of the text, so a short fragment can select an
unrelated unit: give the full id where it matters.

## EUnknownUnitError

```pascal
type
  EUnknownUnitError = class(EBabelValueError);
```

Raised for a unit the locale does not have. Its message names the unit
and the locale: `'banana is not a known unit in en'`.

---

[API index](index.md) · [Documentation index](../index.md)
