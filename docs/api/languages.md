# Languages

Unit `babel.languages`.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

```pascal
uses babel.languages;
```

The languages spoken in a territory, from CLDR's territory information:
the share of the population that uses each language and its official
status.

## TTerritoryLanguage

```pascal
type
  TTerritoryLanguage = record
    Language: string;
    PopulationPercent: Double;
    OfficialStatus: string;
  end;
  TTerritoryLanguages = array of TTerritoryLanguage;
```

- `Language`: the language code (`'de'`, `'gsw'`).
- `PopulationPercent`: the percentage of the territory's population that
  uses the language (76.0 for 76 %).
- `OfficialStatus`: `'official'`, `'official_regional'`,
  `'de_facto_official'`, or `''` for a language without official status.

## GetOfficialLanguages

```pascal
function GetOfficialLanguages(const Territory: string; Regional: Boolean = False;
  DeFacto: Boolean = False): TStringArray;
```

The official languages of a territory, the most spoken first (languages
with the same share in reverse alphabetical order).

Parameters:

- `Territory`: the territory code (`'CH'`); upper or lower case.
- `Regional`: also the languages official in a region of the territory.
- `DeFacto`: also the languages official in practice.

Result: the language codes; an empty array for an unknown territory or a
territory without an official language.

```pascal
GetOfficialLanguages('CH');               // ['de', 'fr', 'it']
GetOfficialLanguages('ch', True);         // ['de', 'fr', 'it', 'rm']
GetOfficialLanguages('CH', True, True);   // ['de', 'gsw', 'fr', 'it', 'rm']
GetOfficialLanguages('PE');               // ['es', 'qu']
GetOfficialLanguages('US');               // []
GetOfficialLanguages('US', False, True);  // ['en']
GetOfficialLanguages('XX');               // []
```

## GetTerritoryLanguageInfo

```pascal
function GetTerritoryLanguageInfo(const Territory: string): TTerritoryLanguages;
```

The languages used in a territory with their population share and
official status, in CLDR's order (by population). An empty array for an
unknown territory.

```pascal
for L in GetTerritoryLanguageInfo('CH') do
  WriteLn(L.Language, ' ', FloatToStr(L.PopulationPercent), ' [', L.OfficialStatus, ']');
// de 76 [official]
// gsw 66 [de_facto_official]
// en 45 []
// fr 39 [official]
// it 15 [official]
// lmo 4.1 []
// pt 3.4 []
// rm 0.5 [official_regional]
// rmo 0.29 []
// wae 0.11 []
```

---

[API index](index.md) · [Documentation index](../index.md)
