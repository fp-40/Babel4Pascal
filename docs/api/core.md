# Core Functionality

The unit `babel.core` holds the locale type, `TLocale`, and the
functions on locale identifiers. The unit `babel.localedata` holds the
CLDR data of the linked locales, and `babel.errors` the exception classes
shared by all units.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

A locale identifier names a language and optionally a script, a
territory, a variant and a modifier: `'es_PE'`, `'zh_Hant_TW'`,
`'ca_ES_VALENCIA'`, `'de_DE@euro'`. A locale exists when its data unit is
linked into the program (`babel.cldr_es_PE` for `es_PE`; `babel.cldr_all`
for every generated locale).

All functions of `babel.core` only read shared data and may be called
from any thread. `DefaultLocale` reads environment variables.

## Locales

### TLocale

```pascal
type
  TLocale = record
    ...
    property Language: string;
    property Territory: string;
    property Script: string;
    property Variant: string;
    property Modifier: string;
    property Data: TCLDRValue;
  end;
```

A locale: the parts of its identifier and its CLDR data, merged with the
data it inherits. `TLocale` is a record; it is copied like a string and
needs no freeing. A missing part is `''`.

A string converts to a `TLocale` implicitly (through `TLocale.Parse`),
so every function that takes a `TLocale` accepts an identifier:

```pascal
var
  L: TLocale;
begin
  L := 'ca_ES_VALENCIA';
  WriteLn(L.Language);              // ca
  WriteLn(L.Territory);             // ES
  WriteLn(L.Variant);               // VALENCIA
  WriteLn(L.GetDisplayName('en'));  // Catalan (Spain, Valencian)
end.
```

#### TLocale.Create

```pascal
class function Create(const Language: string; const Territory: string = '';
  const Script: string = ''; const Variant: string = '';
  const Modifier: string = ''): TLocale; static;
```

The locale of the given parts, as they are (no likely subtags are
added). Raises `EUnknownLocaleError` when no data of the identifier, or
of the identifier without its modifier, is linked. Parts given in another
case than the data's (`'ES'`) load that data.

```pascal
TLocale.Create('de', 'DE').ToString;                 // de_DE
TLocale.Create('sr', 'RS', 'Latn').ToString;         // sr_Latn_RS
TLocale.Create('de', 'DE', '', '', 'euro').ToString; // de_DE@euro
TLocale.Create('xx');   // raises EUnknownLocaleError: unknown locale 'xx'
```

#### TLocale.Parse

```pascal
class function Parse(const Identifier: string; const Sep: string = '_';
  ResolveLikelySubtags: Boolean = True): TLocale; static;
```

The locale of an identifier whose parts are separated by `Sep`. It tries
the identifier as given, then with language and territory aliases
replaced and, when `ResolveLikelySubtags` is `True`, with the likely
subtags of CLDR added, and returns the first match among the linked
locales.

Raises `EBabelValueError` for a malformed or empty identifier and
`EUnknownLocaleError` when no linked locale matches.

```pascal
TLocale.Parse('zh_TW').ToString;            // zh_Hant_TW
TLocale.Parse('und_AZ').ToString;           // az_Latn_AZ
TLocale.Parse('de-AT', '-').ToString;       // de_AT
TLocale.Parse('zh_TW', '_', False);         // raises EUnknownLocaleError
TLocale.Parse('not a locale!');
// raises EBabelValueError: expected only letters, got 'not a locale!'
```

#### TLocale.Default

```pascal
class function Default(const Category: string = ''): TLocale; overload; static;
class function Default(const Category: string; const Aliases: TLocaleAliases): TLocale; overload; static;
```

The locale named by the environment, as `DefaultLocale` finds it.
Raises `EBabelTypeError` when the environment names none.

```pascal
// LANG=fr_FR.UTF-8
TLocale.Default.ToString;   // fr_FR

// no locale variable set
TLocale.Default;
// raises EBabelTypeError: No locale identifier in the environment (LANGUAGE, LC_ALL, LC_CTYPE, LANG)
TLocale.Default('LC_TIME');
// raises EBabelTypeError: No locale identifier in the environment (LC_TIME, LANGUAGE, LC_ALL, LC_CTYPE, LANG)
```

#### TLocale.Negotiate

```pascal
class function Negotiate(const Preferred, Available: array of string;
  out Locale: TLocale; const Sep: string = '_'): Boolean; overload; static;
class function Negotiate(const Preferred, Available: array of string;
  const Aliases: TLocaleAliases; out Locale: TLocale; const Sep: string = '_'): Boolean; overload; static;
```

The best match of the preferred identifiers among the available ones, as
`NegotiateLocale` finds it, parsed into `Locale`. Returns `False` when
nothing matches.

```pascal
var
  M: TLocale;
begin
  if TLocale.Negotiate(['de_DE', 'en_US'], ['de_DE', 'de_AT'], M) then
    WriteLn(M.ToString);   // de_DE
end.
```

#### Operators

```pascal
class operator :=(const Identifier: string): TLocale;
class operator =(const A, B: TLocale): Boolean;
```

`:=` converts an identifier with `TLocale.Parse`. Two locales are equal
when all their parts are equal.

```pascal
TLocale('es_PE') = 'es_PE';   // True
```

#### ToString, Repr

```pascal
function ToString: string;
function Repr: string;
```

`ToString` gives the identifier (`'zh_Hant_TW'`, `'de_DE@euro'`); `Repr`
a description of the parts: `Locale('de', territory='DE')`.

#### Names

```pascal
function GetDisplayName: string; overload;
function GetDisplayName(const InLocale: TLocale): string; overload;
function GetLanguageName: string; overload;
function GetLanguageName(const InLocale: TLocale): string; overload;
function GetTerritoryName: string; overload;
function GetTerritoryName(const InLocale: TLocale): string; overload;
function GetScriptName: string; overload;
function GetScriptName(const InLocale: TLocale): string; overload;
function DisplayName: string;
function LanguageName: string;
function TerritoryName: string;
function ScriptName: string;
function EnglishName: string;
```

The name of the locale, of its language, territory or script, in
`InLocale` (or, without it, in the locale itself). The display name is
the language name followed by the other parts in parentheses.
`EnglishName` is the display name in English; it needs the `en` data
linked. A name the data does not have is `''`.

```pascal
L := TLocale.Parse('de_DE');
L.GetDisplayName('en_US');    // German (Germany)
L.GetDisplayName('fr_FR');    // allemand (Allemagne)
L.DisplayName;                // Deutsch (Deutschland)
L.GetLanguageName('en');      // German
L.GetTerritoryName('en');     // Germany
L.EnglishName;                // German (Germany)
TLocale('zh_Hant_TW').GetScriptName('en');   // Traditional
```

#### Locale data accessors

```pascal
function Languages: TCLDRValue;
function Scripts: TCLDRValue;
function Territories: TCLDRValue;
function Variants: TCLDRValue;
```

Maps of code to localized name.

```pascal
TLocale('fr').Languages.Str('en');     // anglais
TLocale('en').Scripts.Str('Cyrl');     // Cyrillic
TLocale('es_MX').Territories.Str('US');   // Estados Unidos
```

```pascal
function Currencies: TCLDRValue;
function CurrencySymbols: TCLDRValue;
function NumberSymbols: TCLDRValue;
function OtherNumberingSystems: TCLDRValue;
function DefaultNumberingSystem: string;
function DecimalFormats: TCLDRValue;
function CompactDecimalFormats: TCLDRValue;
function CurrencyFormats: TCLDRValue;
function CompactCurrencyFormats: TCLDRValue;
function PercentFormats: TCLDRValue;
function ScientificFormats: TCLDRValue;
```

Number data. `Currencies` maps a currency code to its name and
`CurrencySymbols` to its symbol. `NumberSymbols` maps a numbering system
to its symbols (`decimal`, `group`, `minusSign`, `percentSign`, ...).
`OtherNumberingSystems` maps `'native'`, `'traditional'` and `'finance'`
to numbering systems; `DefaultNumberingSystem` is the locale's
(`'latn'`, `'arab'`, ...). The format maps hold number patterns as
strings.

```pascal
TLocale('en').Currencies.Str('EUR');                       // Euro
TLocale('en').CurrencySymbols.Str('USD');                  // $
TLocale('de').NumberSymbols.Path(['latn']).Str('decimal'); // ,
TLocale('ar_EG').DefaultNumberingSystem;                   // arab
TLocale('en').DecimalFormats.GetNone.AsString;             // #,##0.###
```

```pascal
function Periods: TCLDRValue;
function DayPeriods: TCLDRValue;
function DayPeriodRules: TCLDRValue;
function Days: TCLDRValue;
function Months: TCLDRValue;
function Quarters: TCLDRValue;
function Eras: TCLDRValue;
function TimeZones: TCLDRValue;
function MetaZones: TCLDRValue;
function ZoneFormats: TCLDRValue;
function DateFormats: TCLDRValue;
function TimeFormats: TCLDRValue;
function DatetimeFormats: TCLDRValue;
function DatetimeSkeletons: TCLDRValue;
function IntervalFormats: TCLDRValue;
```

Calendar data of the Gregorian calendar. `Days`, `Months` and `Quarters`
are maps by context (`'format'`, `'stand-alone'`) and width (`'wide'`,
`'abbreviated'`, `'narrow'`, and `'short'` for days) to maps of index to
name (days 0 = Monday to 6 = Sunday; months 1 to 12; quarters 1 to 4).
`Eras` maps a width to the names of index 0 (BC) and 1 (AD). `Periods`
gives the stand-alone wide AM/PM names; `DayPeriods` all day period
names and `DayPeriodRules` the rules that choose them. `TimeZones` and
`MetaZones` hold the localized names of zones and metazones. The format
maps hold the standard patterns by length (`'full'`, `'long'`,
`'medium'`, `'short'`), the available skeletons and the interval
formats.

```pascal
TLocale('en').Months.Path(['format', 'wide']).GetInt(1).AsString;     // January
TLocale('fr').Days.Path(['format', 'wide']).GetInt(6).AsString;       // dimanche
TLocale('en').Quarters.Path(['format', 'wide']).GetInt(1).AsString;   // 1st quarter
TLocale('en').Eras.Path(['abbreviated']).GetInt(1).AsString;          // AD
TLocale('en').DateFormats.Str('short');                               // M/d/yy
TLocale('en').DatetimeSkeletons.Str('yMMMd');                         // MMM d, y
TLocale('en').MetaZones.Path(['Europe_Central', 'long']).Str('standard');
// Central European Standard Time
```

```pascal
function FirstWeekDay: Integer;
function WeekendStart: Integer;
function WeekendEnd: Integer;
function MinWeekDays: Integer;
```

The week data of the locale's territory, or of its likely territory when
it has none. Days are numbered from 0 (Monday) to 6 (Sunday).
`MinWeekDays` is the number of days of a year's first week.

```pascal
TLocale('en').FirstWeekDay;   // 6 (Sunday: en is the United States)
TLocale('de').FirstWeekDay;   // 0
TLocale('de').MinWeekDays;    // 4
```

```pascal
function PluralForm: TPluralRule;
function OrdinalForm: TPluralRule;
```

The cardinal and ordinal plural rules of the locale (unit
[`babel.plural`](plural.md)). A locale without rules gets the rule that
always answers `'other'`.

```pascal
TLocale('ru').PluralForm.Evaluate(3);    // few
TLocale('en').OrdinalForm.Evaluate(2);   // two
```

```pascal
function ListPatterns: TCLDRValue;
function MeasurementSystems: TCLDRValue;
function CharacterOrder: string;
function TextDirection: string;
function UnitDisplayNames: TCLDRValue;
```

`ListPatterns` holds the list patterns by style (unit
[`babel.lists`](lists.md) uses them). `MeasurementSystems` maps a system
(`'metric'`, `'US'`, `'UK'`) to its name. `CharacterOrder` is
`'left-to-right'` or `'right-to-left'`; `TextDirection` is `'ltr'`,
`'rtl'` or `'ttb'`. `UnitDisplayNames` maps a unit to its names by length.

```pascal
TLocale('ar').TextDirection;                                    // rtl
TLocale('en').ListPatterns.Path(['standard']).Str('end');       // {0}, and {1}
TLocale('en').UnitDisplayNames.Path(['length-meter']).Str('long');   // meters
```

### EUnknownLocaleError

```pascal
type
  EUnknownLocaleError = class(EBabelError)
  public
    Identifier: string;
    constructor CreateFor(const AIdentifier: string);
  end;
```

Raised when no linked locale matches an identifier. `Identifier` holds
the identifier asked for.

```pascal
try
  TLocale.Parse('xx_YY');
except
  on E: EUnknownLocaleError do
    WriteLn(E.Message, ' [', E.Identifier, ']');   // unknown locale 'xx_YY' [xx_YY]
end;
```

## Identifiers

### TLocaleParts

```pascal
type
  TLocaleParts = record
    Language, Territory, Script, Variant, Modifier: string;
  end;
```

The parts of an identifier; `''` for an absent part.

### ParseLocale

```pascal
function ParseLocale(const Identifier: string; const Sep: string = '_'): TLocaleParts;
```

Splits an identifier into its parts, without checking that a locale
exists. Raises `EBabelValueError` for a malformed identifier.

```pascal
P := ParseLocale('zh_Hant_TW');        // Language 'zh', Script 'Hant', Territory 'TW'
P := ParseLocale('de-DE@euro', '-');   // Language 'de', Territory 'DE', Modifier 'euro'
```

### GetLocaleIdentifier

```pascal
function GetLocaleIdentifier(const Parts: TLocaleParts; const Sep: string = '_'): string;
```

The parts joined in the order language, script, territory, variant, then
`'@'` and the modifier.

```pascal
GetLocaleIdentifier(ParseLocale('sr_Latn_RS'));   // sr_Latn_RS
```

## Negotiation and the default locale

### TLocaleAlias, LocaleAliases

```pascal
type
  TLocaleAlias = record
    Alias, Identifier: string;
  end;
  TLocaleAliases = array of TLocaleAlias;

function LocaleAliases: TLocaleAliases;
```

The language-only identifiers that clients often send, mapped to a full
identifier: 39 pairs such as `'ar'` → `'ar_SY'`, `'ca'` → `'ca_ES'`,
`'no'` → `'nb_NO'`. `NegotiateLocale`, `DefaultLocale` and their
`TLocale` counterparts use them by default.

### NegotiateLocale

```pascal
function NegotiateLocale(const Preferred, Available: array of string;
  const Sep: string = '_'): string; overload;
function NegotiateLocale(const Preferred, Available: array of string;
  const Aliases: TLocaleAliases; const Sep: string = '_'): string; overload;
```

Chooses, for a list of preferred identifiers (as a browser's
Accept-Language gives them, most preferred first), the first one found
in `Available`, comparing without regard to case. When a preferred
identifier is not available, its alias is tried, then its language
alone. Returns the preferred identifier as written in `Preferred` (or
its alias, or its language), or `''` when none matches. Pass an empty
`Aliases` array to use no aliases.

```pascal
NegotiateLocale(['de_DE', 'en_US'], ['de_de', 'de_at']);   // de_DE
NegotiateLocale(['de_DE', 'en_US'], ['en', 'de']);         // de
NegotiateLocale(['de_DE', 'de'], ['en_US']);               // ''
NegotiateLocale(['no', 'en'], ['nb_NO', 'en_US']);         // nb_NO
NegotiateLocale(['no'], ['nb_NO'], []);                    // ''
```

### DefaultLocale

```pascal
function DefaultLocale(const Category: string = ''): string; overload;
function DefaultLocale(const Categories: array of string; const Aliases: TLocaleAliases): string; overload;
```

The locale named by the environment: the first of the variables
`Category` (when given), `LANGUAGE`, `LC_ALL`, `LC_CTYPE` and `LANG`
that names a locale, without its encoding (`fr_FR.UTF-8` gives
`fr_FR`). `LANGUAGE` may list several, separated by colons; the first is
taken (`LANGUAGE=de:en` gives `de_DE`, through the alias of `de`). `'C'` and `'POSIX'` mean `en_US_POSIX`. `Aliases` (by default
`LocaleAliases`) map a whole value. Returns `''` when no variable names
a locale.

```pascal
// LANG=fr_FR.UTF-8
DefaultLocale;               // fr_FR
// LANG=en_US.UTF-8 LC_TIME=de_DE.UTF-8
DefaultLocale('LC_TIME');    // de_DE
// LANG=C
DefaultLocale;               // en_US_POSIX
```

## Locale data

### TCLDRValue

```pascal
type
  TCLDRKind = (ckNone, ckBool, ckInt, ckFloat, ckString, ckList, ckMap,
    ckAlias, ckAliasMerge);

  TCLDRValue = class
  public
    property Kind: TCLDRKind;
    function IsNone: Boolean;
    function AsBoolean: Boolean;
    function AsInteger: Int64;
    function AsFloat: Double;
    function AsString: string;
    function Count: Integer;
    function Items(I: Integer): TCLDRValue;
    function Keys(I: Integer): TCLDRValue;
    function Get(const Key: string): TCLDRValue;
    function GetInt(Key: Int64): TCLDRValue;
    function GetNone: TCLDRValue;
    function Has(const Key: string): Boolean;
    function Path(const KeyPath: array of string): TCLDRValue;
    function Str(const Key: string; const Default: string = ''): string;
    function AliasKeys: TStringArray;
  end;
```

(Unit `babel.localedata`.) One value of the locale data: none, a
boolean, an integer, a float, a string (UTF-8), a list or a map. Map keys
are none, integers or strings, in insertion order.

- `Count`: the number of items of a list or entries of a map.
- `Items(I)`: item `I` of a list, or the value of entry `I` of a map
  (0-based).
- `Keys(I)`: the key of entry `I` of a map.
- `Get`, `GetInt`, `GetNone`: the value under a string, integer or none
  key; `nil` when absent or when the value is not a map.
- `Has`: whether a map has the string key.
- `Path`: follows string keys from a map; `nil` when one is absent.
- `Str`: the string under a key, or `Default` when absent or not a
  string.
- `AliasKeys`: the path of an alias; aliases (`ckAlias`, `ckAliasMerge`)
  occur only in data loaded with `MergeInherited = False`.

Every `TCLDRValue` belongs to the library and lives until the program
ends; callers never free one. The values never change, and any thread
may read them.

```pascal
TLocale('en').NumberSymbols.Path(['latn']).Str('decimal');   // .
TLocale('en').Languages.Count;                               // 659
```

### Locale data functions

```pascal
function LoadLocaleData(const Name: string; MergeInherited: Boolean = True): TCLDRValue;
function LocaleDataExists(const Name: string): Boolean;
function NormalizeLocale(const Name: string): string;
function LocaleIdentifiers: TStringArray;
function GetGlobal(const Key: string): TCLDRValue;
function GetCLDRVersion: string;
function EmptyCLDRMap: TCLDRValue;
```

(Unit `babel.localedata`; `babel.core` also exports `GetGlobal` and
`GetCLDRVersion`.)

- `LoadLocaleData`: the data of a linked locale, merged with what it
  inherits and with aliases resolved; with `MergeInherited = False`, the
  locale's own data only. The data is built once per locale, on first
  use. Raises `ELocaleDataError` when the locale is not linked.
- `LocaleDataExists`: whether the locale's data is linked (exact match
  first, then ignoring case).
- `NormalizeLocale`: the linked identifier that equals `Name` ignoring
  case; `''` if none.
- `LocaleIdentifiers`: every linked identifier except root, sorted.
- `GetGlobal`: one map of the data that is not per locale
  (`'likely_subtags'`, `'parent_exceptions'`, `'territory_currencies'`,
  `'zone_aliases'`, ...); an empty map for an unknown key. Raises
  `ELocaleDataError` when no data unit is linked.
- `GetCLDRVersion`: the version of the CLDR release of the data.
- `EmptyCLDRMap`: a shared map without entries.

```pascal
LoadLocaleData('es_PE', False).Count;              // 36 (its own keys)
LoadLocaleData('es_PE').Count;                     // 47 (with inherited keys)
LocaleDataExists('es_PE');                         // True
NormalizeLocale('ES_pe');                          // es_PE
Length(LocaleIdentifiers);                         // 512 (with babel.cldr_all)
GetGlobal('likely_subtags').Str('pt');             // pt_Latn_BR
GetCLDRVersion;                                    // 47
LoadLocaleData('xx');   // raises ELocaleDataError: no locale data for xx
```

### Registration

```pascal
procedure RegisterLocaleData(const Name, Parent: string; Data: PByte; Len: SizeInt);
procedure RegisterGlobalData(Data: PByte; Len: SizeInt);
```

Called by the generated data units in their initialization sections. A
program does not call them.

### ELocaleDataError

```pascal
type
  ELocaleDataError = class(Exception);
```

Raised by `babel.localedata` when a locale's data or the global data is
not linked.

## Exceptions

```pascal
type
  EBabelError = class(Exception);
  EBabelValueError = class(EBabelError);
  EBabelTypeError = class(EBabelError);
  EBabelKeyError = class(EBabelError);
  EBabelOverflowError = class(EBabelError);
  EBabelIndexError = class(EBabelError);
  EBabelNotImplementedError = class(EBabelError);
  EBabelDecimalError = class(EBabelError);
```

(Unit `babel.errors`.) `EBabelError` is the base class of the library's
exceptions. Its subclasses:

- `EBabelValueError`: a malformed argument (an identifier, a number, a
  pattern).
- `EBabelTypeError`: an argument of the wrong kind, or a missing one.
- `EBabelKeyError`: data the locale does not have.
- `EBabelOverflowError`: a value out of range.
- `EBabelIndexError`: an index out of range.
- `EBabelNotImplementedError`: an unsupported case.
- `EBabelDecimalError`: a failed decimal operation (invalid operation,
  division by zero, overflow).

The units add their own subclasses: `EUnknownLocaleError` (above),
`EPluralRuleError` ([babel.plural](plural.md)), and those of the
formatting units, described on their pages.

[API Reference](index.md) · [Index](../index.md)
