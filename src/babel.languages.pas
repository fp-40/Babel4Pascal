{ babel.languages - the languages of a territory, from CLDR's
  territoryInfo, as Python Babel's babel.languages.

  GetOfficialLanguages('CH') gives ['de', 'fr', 'it'];
  GetTerritoryLanguageInfo('CH') gives the share of the population that
  speaks each language and its official status.

  Threading: everything here only reads shared data. }
unit babel.languages;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TTerritoryLanguage = record
    Language: string;            { 'de' }
    PopulationPercent: Double;   { 76.0 }
    OfficialStatus: string;      { 'official', 'official_regional',
                                   'de_facto_official'; '' = none }
  end;
  TTerritoryLanguages = array of TTerritoryLanguage;

{ The official languages of a territory (case-insensitive code), the most
  spoken first; Regional adds the regional official languages, DeFacto
  the de facto official ones. Empty for an unknown territory. }
function GetOfficialLanguages(const Territory: string; Regional: Boolean = False;
  DeFacto: Boolean = False): TStringArray;
{ The languages spoken in a territory, in CLDR's order (by population). }
function GetTerritoryLanguageInfo(const Territory: string): TTerritoryLanguages;

implementation

uses
  babel.localedata, babel.core;

function GetTerritoryLanguageInfo(const Territory: string): TTerritoryLanguages;
var
  Langs, Info, Status: TCLDRValue;
  I: Integer;
begin
  Result := nil;
  Langs := GetGlobal('territory_languages').Get(UpperCase(Territory));
  if Langs = nil then
    Exit;
  SetLength(Result, Langs.Count);
  for I := 0 to Langs.Count - 1 do
  begin
    Info := Langs.Items(I);
    Result[I].Language := Langs.Keys(I).AsString;
    Result[I].PopulationPercent := Info.Get('population_percent').AsFloat;
    Status := Info.Get('official_status');
    if (Status = nil) or (Status.Kind = ckNone) then
      Result[I].OfficialStatus := ''
    else
      Result[I].OfficialStatus := Status.AsString;
  end;
end;

function GetOfficialLanguages(const Territory: string; Regional, DeFacto: Boolean): TStringArray;
var
  Info, Pairs: TTerritoryLanguages;
  L: TTerritoryLanguage;
  I, J: Integer;
  T: TTerritoryLanguage;

  function Before(const A, B: TTerritoryLanguage): Boolean;
  begin
    { Python's sort(reverse=True) of (percent, language) pairs }
    if A.PopulationPercent <> B.PopulationPercent then
      Result := A.PopulationPercent > B.PopulationPercent
    else
      Result := A.Language > B.Language;
  end;

begin
  Info := GetTerritoryLanguageInfo(Territory);
  Pairs := nil;
  for L in Info do
    if (L.OfficialStatus = 'official') or
       (Regional and (L.OfficialStatus = 'official_regional')) or
       (DeFacto and (L.OfficialStatus = 'de_facto_official')) then
    begin
      SetLength(Pairs, Length(Pairs) + 1);
      Pairs[High(Pairs)] := L;
    end;
  Result := nil;
  { insertion sort: the lists are short }
  for I := 1 to High(Pairs) do
  begin
    T := Pairs[I];
    J := I - 1;
    while (J >= 0) and Before(T, Pairs[J]) do
    begin
      Pairs[J + 1] := Pairs[J];
      Dec(J);
    end;
    Pairs[J + 1] := T;
  end;
  SetLength(Result, Length(Pairs));
  for I := 0 to High(Pairs) do
    Result[I] := Pairs[I].Language;
end;

end.
