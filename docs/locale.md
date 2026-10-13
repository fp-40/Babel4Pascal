# Locale Data

The Unicode Common Locale Data Repository (CLDR) describes, for each
locale, how its language and region write names, dates and numbers.
Babel4Pascal holds that data in one unit per locale and gives access to
it through the `TLocale` record (unit `babel.core`). The formatting
functions of the other units take a `TLocale` too.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

## The `TLocale` record

A `TLocale` holds the parts of a locale identifier (language, script,
territory, variant, modifier) and the locale's data. It is a record: it
is copied like a string and needs no freeing. A string converts to a
`TLocale` implicitly, so every function that takes a locale accepts
`'es_PE'` as well.

The data of a locale is available when its data unit is linked into the
program (`babel.cldr_es_MX` for `es_MX`, or `babel.cldr_all` for every
generated locale). Each accessor returns a map of the locale's data; the
territory names, for example:

```pascal
uses babel.core, babel.cldr_all;

var
  L: TLocale;
begin
  L := TLocale.Create('en', 'US');
  WriteLn(L.Territories.Str('US'));   // United States
  L := TLocale.Create('es', 'MX');
  WriteLn(L.Territories.Str('US'));   // Estados Unidos
end.
```

Other accessors give the names of languages, scripts and currencies, the
calendar names, the number symbols and formats, the week data and the
plural rules; the [Core Functionality](api/core.md) reference lists them
all.

## Likely subtags

`TLocale.Parse` reads an identifier and finds the locale whose data
best matches it. When the identifier is incomplete, it adds the subtags
CLDR gives as the most likely ones ("likely subtags"): Chinese as written
in Taiwan is Traditional Chinese, and a locale for Azerbaijan with an
undetermined language (`und`) is Azerbaijani in Latin script.

```pascal
WriteLn(TLocale.Parse('zh_TW').ToString);    // zh_Hant_TW
WriteLn(TLocale.Parse('und_AZ').ToString);   // az_Latn_AZ
WriteLn(TLocale.Parse('und_DE').ToString);   // de_DE
```

Only locales whose data is linked are accepted. Without likely subtags,
`zh_TW` names no locale of CLDR:

```pascal
TLocale.Parse('zh_TW', '_', False);
// raises EUnknownLocaleError: unknown locale 'zh_TW'
```

## Locale display names

A locale has a display name, in its own language or in another one:

```pascal
var
  L: TLocale;
begin
  L := TLocale.Parse('de_DE');
  WriteLn(L.GetDisplayName('en_US'));   // German (Germany)
  WriteLn(L.GetDisplayName('fr_FR'));   // allemand (Allemagne)
  WriteLn(L.DisplayName);               // Deutsch (Deutschland)
end.
```

The language, territory and script names are available apart:

```pascal
L := TLocale.Parse('de_DE');
WriteLn(L.GetLanguageName('en'));    // German
WriteLn(L.GetTerritoryName('en'));   // Germany

L := 'zh_Hant_TW';
WriteLn(L.GetDisplayName('en'));     // Chinese (Traditional, Taiwan)
WriteLn(L.GetScriptName('en'));      // Traditional
```

`DisplayName`, `LanguageName`, `TerritoryName` and `ScriptName` give the
names in the locale's own language:

```pascal
L := 'es_PE';
WriteLn(L.DisplayName);     // español (Perú)
WriteLn(L.LanguageName);    // español
WriteLn(L.TerritoryName);   // Perú
```

A name the data does not have is returned as `''`.

## Calendar display names

The names of months, weekdays, quarters, eras and day periods are part of
the locale data. They serve, for example, to fill a list of months in a
form. `TLocale.Months` gives the map of month names by context and
width; the months are numbered from 1:

```pascal
var
  Names: TCLDRValue;
  I: Integer;
begin
  Names := TLocale('en').Months.Path(['format', 'wide']);
  for I := 1 to 3 do
    WriteLn(I, ' ', Names.GetInt(I).AsString);
  // 1 January
  // 2 February
  // 3 March
end.
```

The unit `babel.dates` has functions that return the same maps with
defaults:

```pascal
uses babel.dates, babel.cldr_all;

GetMonthNames('es', 'wide', 'format').GetInt(1).AsString;   // enero
GetMonthNames('es', 'abbreviated').GetInt(1).AsString;      // ene
GetDayNames('es').GetInt(0).AsString;                       // lunes (0 = Monday)
```

`TCLDRValue` is the type of the data (unit `babel.localedata`); the
values belong to the library and are never freed by the caller.

[Index](index.md)
