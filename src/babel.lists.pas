{ babel.lists - lists of items joined by the locale's patterns, as Python
  Babel's babel.lists.

  FormatList(['apples', 'oranges', 'pears'], 'en') gives 'apples,
  oranges, and pears'; with Style 'or' in 'fi', 'omena, peruna tai
  aplari'.

  Styles (CLDR's list pattern types): 'standard', 'standard-short',
  'standard-narrow', 'or', 'or-short', 'or-narrow', 'unit', 'unit-short',
  'unit-narrow'. A style the locale lacks falls back as CLDR's root
  aliases say ('unit-narrow' to 'unit-short', 'unit', 'standard').

  Threading: everything here only reads shared data. }
unit babel.lists;

{$mode objfpc}{$H+}

interface

uses
  babel.core;

{ The items joined; '' for none, the item itself for one. Raises
  EBabelValueError for a style the locale has no patterns for. }
function FormatList(const Items: array of string; const Locale: TLocale;
  const Style: string = 'standard'): string;

implementation

uses
  SysUtils, babel.errors, babel.localedata, babel.pystr;

{ The patterns of a style ('start', 'middle', 'end', '2'), following
  Babel's fallbacks (from CLDR 45's root aliases). }
function ResolveListStyle(const Locale: TLocale; const Style: string): TCLDRValue;
var
  Candidates: array of string;
  S: string;
  Patterns: TCLDRValue;
begin
  if Style = 'or-narrow' then Candidates := ['or-narrow', 'or-short', 'or']
  else if Style = 'or-short' then Candidates := ['or-short', 'or']
  else if Style = 'standard-narrow' then Candidates := ['standard-narrow', 'standard-short', 'standard']
  else if Style = 'standard-short' then Candidates := ['standard-short', 'standard']
  else if Style = 'unit' then Candidates := ['unit', 'unit-short', 'standard']
  else if Style = 'unit-narrow' then Candidates := ['unit-narrow', 'unit-short', 'unit', 'standard']
  else if Style = 'unit-short' then Candidates := ['unit-short', 'standard']
  else Candidates := [Style];
  Patterns := Locale.ListPatterns;
  for S in Candidates do
  begin
    Result := Patterns.Get(S);
    if Result <> nil then
      Exit;
  end;
  raise EBabelValueError.CreateFmt('Locale %s does not support list formatting style ''%s''',
    [Locale.ToString, Style]);
end;

function Need(Patterns: TCLDRValue; const Key: string): string;
var
  V: TCLDRValue;
begin
  V := Patterns.Get(Key);
  if V = nil then
    raise EBabelKeyError.Create(Key);
  Result := V.AsString;
end;

function FormatList(const Items: array of string; const Locale: TLocale; const Style: string): string;
var
  Patterns: TCLDRValue;
  I: Integer;
begin
  if Length(Items) = 0 then
    Exit('');
  if Length(Items) = 1 then
    Exit(Items[0]);
  Patterns := ResolveListStyle(Locale, Style);
  if (Length(Items) = 2) and Patterns.Has('2') then
    Exit(PyFormat(Need(Patterns, '2'), [Items[0], Items[1]]));
  Result := PyFormat(Need(Patterns, 'start'), [Items[0], Items[1]]);
  for I := 2 to High(Items) - 1 do
    Result := PyFormat(Need(Patterns, 'middle'), [Result, Items[I]]);
  Result := PyFormat(Need(Patterns, 'end'), [Result, Items[High(Items)]]);
end;

end.
