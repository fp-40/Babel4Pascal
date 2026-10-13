{ babel.lists - lists of items joined by the locale's patterns.

  FormatList(['apples', 'oranges', 'pears'], 'en') gives 'apples,
  oranges, and pears'; with Style 'or' in 'fi', 'omena, peruna tai
  aplari'.

  Styles (CLDR's list pattern types): 'standard', 'standard-short',
  'standard-narrow', 'or', 'or-short', 'or-narrow', 'unit', 'unit-short',
  'unit-narrow'. Each part of a style the locale lacks comes from the
  style CLDR's root aliases it to ('unit-narrow' to 'unit-short' to
  'standard').

  Each part of a style is resolved on its own, and the conjunction of
  some languages depends on the next item ('padre e hijo', 'siete u
  ocho', Hebrew 'ו-' before other scripts).

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

(* The styles a style's patterns are looked up in, as CLDR's root aliases
  them: 'unit-narrow' to 'unit-short' to 'standard'. *)
function StyleChain(const Style: string): TStringArray;
begin
  if Style = 'or-narrow' then Result := ['or-narrow', 'or-short', 'or']
  else if Style = 'or-short' then Result := ['or-short', 'or']
  else if Style = 'standard-narrow' then Result := ['standard-narrow', 'standard-short', 'standard']
  else if Style = 'standard-short' then Result := ['standard-short', 'standard']
  else if (Style = 'unit') or (Style = 'unit-narrow') then Result := [Style, 'unit-short', 'standard']
  else if Style = 'unit-short' then Result := ['unit-short', 'standard']
  else Result := [Style];
end;

(* The pattern of a part ('start', 'middle', 'end', '2') in the first
  style of the chain that has it: a locale may give only some parts of a
  style (af's 'standard-narrow' has '2' and 'end'), the others are
  inherited through the alias. *)
function PartPattern(const Locale: TLocale; const Chain: TStringArray; const Part: string): string;
var
  S: string;
  V: TCLDRValue;
begin
  for S in Chain do
  begin
    V := Locale.ListPatterns.Get(S);
    if (V <> nil) and V.Has(Part) then
      Exit(V.Str(Part));
  end;
  raise EBabelKeyError.Create(Part);
end;

function StartsWithI(const S: string; I: Integer; C: Char): Boolean;
begin
  Result := (Length(S) >= I) and (UpCase(S[I]) = UpCase(C));
end;

(* The contextual conjunctions: Spanish 'y' is 'e'
  before a word that starts with the sound i ('i', 'hi', but not 'hia',
  'hie': 'padre e hijo', 'agua y hielo'), 'o' is 'u' before the sound o
  ('o', 'ho', '8', '11': 'siete u ocho'); Hebrew 'ו' takes a hyphen
  before a word not in Hebrew script ('Paris ו-London'). Only the
  locale's patterns written exactly so are changed. *)
function Contextual(const Locale: TLocale; const Pattern, Next: string): string;
const
  Vav = #$D7#$95;   { U+05D5 }
var
  C: Cardinal;
  Len: Integer;
begin
  Result := Pattern;
  if Next = '' then
    Exit;
  if Locale.Language = 'es' then
  begin
    if (Pattern = '{0} y {1}') and
       (StartsWithI(Next, 1, 'i') or
        (StartsWithI(Next, 1, 'h') and StartsWithI(Next, 2, 'i') and
         not StartsWithI(Next, 3, 'a') and not StartsWithI(Next, 3, 'e'))) then
      Result := '{0} e {1}'
    else if (Pattern = '{0} o {1}') and
       (StartsWithI(Next, 1, 'o') or (Next[1] = '8') or
        (StartsWithI(Next, 1, 'h') and StartsWithI(Next, 2, 'o')) or
        ((Copy(Next, 1, 2) = '11') and ((Length(Next) = 2) or not (Next[3] in ['0'..'9'])))) then
      Result := '{0} u {1}';
  end
  else if (Locale.Language = 'he') and (Pattern = '{0} ' + Vav + '{1}') then
  begin
    { not a letter of the Hebrew block (U+0590..U+05FF) or of the Hebrew
      presentation forms (U+FB1D..U+FB4F) }
    C := CodePointAt(Next, 1, Len);
    if not (((C >= $0590) and (C <= $05FF)) or ((C >= $FB1D) and (C <= $FB4F))) then
      Result := '{0} ' + Vav + '-{1}';
  end;
end;

function HasAnyStyle(const Locale: TLocale; const Chain: TStringArray): Boolean;
var
  S: string;
begin
  for S in Chain do
    if Locale.ListPatterns.Get(S) <> nil then
      Exit(True);
  Result := False;
end;

function FormatList(const Items: array of string; const Locale: TLocale; const Style: string): string;
var
  Chain: TStringArray;
  I: Integer;
  Last: string;
begin
  if Length(Items) = 0 then
    Exit('');
  if Length(Items) = 1 then
    Exit(Items[0]);
  Chain := StyleChain(Style);
  if not HasAnyStyle(Locale, Chain) then
    raise EBabelValueError.CreateFmt('Locale %s does not support list formatting style ''%s''',
      [Locale.ToString, Style]);
  Last := Items[High(Items)];
  if Length(Items) = 2 then
    Exit(PyFormat(Contextual(Locale, PartPattern(Locale, Chain, '2'), Last), [Items[0], Last]));
  Result := PyFormat(PartPattern(Locale, Chain, 'start'), [Items[0], Items[1]]);
  for I := 2 to High(Items) - 1 do
    Result := PyFormat(PartPattern(Locale, Chain, 'middle'), [Result, Items[I]]);
  Result := PyFormat(Contextual(Locale, PartPattern(Locale, Chain, 'end'), Last), [Result, Last]);
end;

end.
