{ cldr.importer - reads the CLDR XML release (cldr-common-<version>.zip,
  extracted) into values (cldr.values): one map of global data
  (ParseGlobal) and one sparse map per locale (TLocaleImporter.
  ImportLocale: the locale's own data; the library merges the parent
  chain).

  Import rules, where CLDR leaves a choice, as ICU reads the data:

  - elements of draft status unconfirmed or provisional are left out (and
    the containers they leave empty), so their values are inherited;
  - the week data of a locale without a region is its likely region's (en:
    US), and a key a territory does not list has the world's value;
  - alternate skeletons and interval formats (alt="ascii", "variant") are
    left out;
  - the plain regionFormat is taken, not its daylight or standard variant.

  Representation:

  - number and date patterns are kept as their pattern strings;
  - a plural rule is a list of [category, condition] pairs, the condition
    as written in CLDR without its samples;
  - an alias of root is an alias value (the path of keys it refers to).

  The text of an element that has none is the string 'None' where the
  value is written as a string, and None where the value is the text
  itself (the output of tools/cldrgen/importer.py, which this unit
  reproduces; tests/run_all.sh compares the generated units).

  ---

  Parts of the generator derive from `scripts/import_cldr.py` and
  the date pattern tokenizer (babel/dates.py) of Python Babel 2.18.0
  (https://github.com/python-babel/babel), under this license:

  Copyright (c) 2013-2025 by the Babel Team, see AUTHORS for more information.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions
  are met:

   1. Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
   2. Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in
      the documentation and/or other materials provided with the
      distribution.
   3. Neither the name of the copyright holder nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. }
unit cldr.importer;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, cldr.pystr, cldr.etree, cldr.values;

{ The global data: likely subtags, aliases, parent locales, currencies,
  time zone mappings, territory languages. }
function ParseGlobal(const SrcDir: string): TValue;

type
  { Holds the supplemental data shared by every locale and imports one
    locale file at a time. Its values are created when it is created
    (before an ArenaMark of the caller). }
  TLocaleImporter = class
  private
    FSrcDir: string;
    FSup: TXDoc;
    FDayPeriodRules: TValue;
    { territory -> its containers (a sorted TStringList) }
    FContainment: TStringList;
    FLikely: TValue;
    FPlural, FOrdinal: TValue;
    function ContainersOf(const Territory: string): TStringList;
  public
    constructor Create(const SrcDir: string);
    destructor Destroy; override;
    { Every locale of the release (the stems of main/*.xml), root first. }
    function LocaleNames: TStringArray;
    function ImportLocale(const Name: string): TValue;
  end;

implementation

const
  PatternChars = ['G', 'y', 'Y', 'u', 'Q', 'q', 'M', 'L', 'w', 'W', 'd', 'D',
    'F', 'g', 'E', 'e', 'c', 'a', 'b', 'B', 'h', 'H', 'K', 'k', 'm', 's', 'S',
    'A', 'z', 'Z', 'O', 'v', 'V', 'x', 'X'];

{ TStringList.CustomSort: code point order. }
function CompareStringListBytes(List: TStringList; I1, I2: Integer): Integer;
begin
  Result := CompareBytes(List[I1], List[I2]);
end;

function Weekday(const Day: string): Integer;
const
  Names: array[0..6] of string = ('mon', 'tue', 'wed', 'thu', 'fri', 'sat',
    'sun');
var
  J: Integer;
begin
  for J := 0 to 6 do
    if Names[J] = Day then
      Exit(J);
  raise Exception.CreateFmt('unknown weekday %s', [Day]);
end;

function MapName(const Name: string; out Mapped: string): Boolean;
begin
  Result := True;
  if Name = 'dateFormats' then Mapped := 'date_formats'
  else if Name = 'dateTimeFormats' then Mapped := 'datetime_formats'
  else if Name = 'eraAbbr' then Mapped := 'abbreviated'
  else if Name = 'eraNames' then Mapped := 'wide'
  else if Name = 'eraNarrow' then Mapped := 'narrow'
  else if Name = 'timeFormats' then Mapped := 'time_formats'
  else
  begin
    Mapped := Name;
    Result := False;
  end;
end;

function IsWordChar(C: Char): Boolean; inline;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

function IsName(const S: string): Boolean;
var
  J: Integer;
begin
  Result := S <> '';
  for J := 1 to Length(S) do
    if not IsWordChar(S[J]) then
      Exit(False);
end;

{ TYPE_ATTR_RE: "name[@type='X']" gives X. }
function MatchTypeAttr(const Part: string; out Value: string): Boolean;
const
  Mid = '[@type=''';
var
  J, Last: Integer;
begin
  Result := False;
  J := 1;
  while (J <= Length(Part)) and IsWordChar(Part[J]) do
    Inc(J);
  if J = 1 then
    Exit;
  if Copy(Part, J, Length(Mid)) <> Mid then
    Exit;
  Inc(J, Length(Mid));
  Last := Length(Part);
  if (Last < J + 1) or (Copy(Part, Last - 1, 2) <> ''']') then
    Exit;
  Value := Copy(Part, J, Last - 1 - J);
  if Pos(#10, Value) > 0 then
    Exit;
  Result := True;
end;

function TranslateAlias(const Ctxt: array of string; const Path: string): TStringArray;
var
  Parts: TStringArray;
  Part, V, Mapped: string;
  N, J: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Ctxt));
  for J := 0 to High(Ctxt) do
    Result[J] := Ctxt[J];
  N := Length(Ctxt);
  Parts := PySplitSep(Path, '/');
  for Part in Parts do
    if Part = '..' then
    begin
      if N = 0 then
        raise Exception.CreateFmt('alias path %s leaves the data', [Path]);
      Dec(N);
      SetLength(Result, N);
    end
    else
    begin
      if MatchTypeAttr(Part, V) then
        Mapped := V
      else
      begin
        if not IsName(Part) then
          raise Exception.CreateFmt('alias path part %s', [Part]);
        MapName(Part, Mapped);
      end;
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := Mapped;
    end;
end;

{ str(elem.text) }
function StrOf(E: TXElem): string;
begin
  if E.HasText then
    Result := E.Text
  else
    Result := 'None';
end;

{ elem.text }
function VText(E: TXElem): TValue;
begin
  Result := VOpt(E.HasText, E.Text);
end;

{ str(elem.findtext(path)) }
function StrFindText(E: TXElem; const Path: string): string;
begin
  if not E.FindText(Path, Result) then
    Result := 'None';
end;

{ The text of an element, its descendants and its tail, stripped (each
  descendant's stripped likewise). }
function ElemText(E: TXElem): string;
var
  J: Integer;
begin
  Result := E.Text;
  for J := 0 to E.ChildCount - 1 do
    Result := Result + ElemText(E.Children[J]);
  Result := PyStrip(Result + E.Tail);
end;

function IsDraftOrAlt(E: TXElem): Boolean;
begin
  Result := E.HasAttr('draft') or E.HasAttr('alt');
end;

{ A draft or alternate element is skipped when Dest is nil or already
  holds its key. }
function ShouldSkip(E: TXElem; const K: TKey; Dest: TValue): Boolean;
begin
  Result := IsDraftOrAlt(E) and ((Dest = nil) or Dest.Has(K));
end;

{ Only the Latin numbering system is imported (the formats of other
  systems are in numbering_system_formats). }
function ShouldSkipNumber(E: TXElem): Boolean;
begin
  Result := E.AttrDef('numberSystem', 'latn') <> 'latn';
end;

procedure ImportTypeText(Dest: TValue; E: TXElem; const K: TKey;
  AllowVariantAndDraft: Boolean = True);
begin
  if Dest.Has(K) then
    Exit;
  if not AllowVariantAndDraft and IsDraftOrAlt(E) then
    Exit;
  Dest.Put(K, VStr(ElemText(E)));
end;

function TypeKey(E: TXElem): TKey;
begin
  Result := KS(E.Attr('type'));
end;

{ Removes the elements of unconfirmed or provisional status (and what
  they contain), as ICU does: their values are inherited from the parent
  locale instead. A container left empty goes too, so that the parent's
  value is used. Contributed and approved data stay. }
procedure DropUnconfirmed(Root: TXElem);
var
  All: TXElemArray;
  E, P, G: TXElem;
  D: string;
begin
  All := Root.Iter;
  for E in All do
  begin
    if not (E.TryAttr('draft', D) and ((D = 'unconfirmed') or (D = 'provisional'))) then
      Continue;
    P := E.Parent;
    if (P = nil) or (P.IndexOfChild(E) < 0) then
      Continue; // already removed with an ancestor
    P.RemoveChild(E);
    while (P.Parent <> nil) and (P.ChildCount = 0) and (PyStrip(P.Text) = '') do
    begin
      G := P.Parent;
      G.RemoveChild(P);
      P := G;
    end;
  end;
end;

function ParseCurrencyDate(Present: Boolean; const S: string): TValue;
var
  Parts: TStringArray;
  J: Integer;
begin
  if not Present or (S = '') then
    Exit(VNone);
  Parts := PySplitSep(S, '-', 2);
  Result := VList;
  for J := 0 to 2 do
    if J < Length(Parts) then
      Result.Append(VInt(PyInt(Parts[J])))
    else
      Result.Append(VInt(1));
end;

function TimeToSeconds(const Expr: string): Int64;
var
  T: string;
  Parts: TStringArray;
  J, Colons: Integer;
begin
  T := Expr;
  Colons := 0;
  for J := 1 to Length(T) do
    if T[J] = ':' then
      Inc(Colons);
  if Colons = 1 then
    T := T + ':00';
  Parts := PySplitSep(T, ':');
  if Length(Parts) <> 3 then
    raise Exception.CreateFmt('bad time %s', [Expr]);
  Result := PyInt(Parts[0]) * 3600 + PyInt(Parts[1]) * 60 + PyInt(Parts[2]);
end;

{ A map locale -> list of [category, condition]. The samples that follow the
  condition ('@integer 1, 21, ...') are dropped. }
function ExtractPluralRules(const Path: string): TValue;
var
  Doc: TXDoc;
  Elem, Rule: TXElem;
  Rules, Pair: TValue;
  Locale: string;
begin
  Result := VMap;
  Doc := TXDoc.LoadFromFile(Path);
  try
    for Elem in Doc.Root.FindAll('.//plurals/pluralRules') do
    begin
      Rules := VList;
      for Rule in Elem.FindAll('pluralRule') do
      begin
        Pair := VList;
        Pair.Append(VStr(Rule.Attr('count')));
        Pair.Append(VStr(PyStrip(PySplitSep(StrOf(Rule), '@', 1)[0])));
        Rules.Append(Pair);
      end;
      for Locale in PySplit(Elem.Attr('locales')) do
        Result.Put(KS(Locale), Rules);
    end;
  finally
    Doc.Free;
  end;
end;

{ --- date patterns ---------------------------------------------------------- }

type
  TToken = record
    IsField: Boolean;
    FieldChar: Char;
    FieldNum: Integer;
    Chars: string;
  end;
  TTokenArray = array of TToken;

function TokenizeDatePattern(const Pattern: string): TTokenArray;
var
  N: Integer;
  InQuote: Boolean;
  QuoteBuf, CharBuf: string;
  FieldChar: Char;
  FieldNum: Integer;
  P: string;
  C: Char;

  procedure AddField;
  begin
    if N = Length(Result) then
      SetLength(Result, N * 2 + 4);
    Result[N].IsField := True;
    Result[N].FieldChar := FieldChar;
    Result[N].FieldNum := FieldNum;
    Result[N].Chars := '';
    Inc(N);
  end;

  procedure AddChars;
  begin
    if N = Length(Result) then
      SetLength(Result, N * 2 + 4);
    Result[N].IsField := False;
    Result[N].FieldChar := #0;
    Result[N].FieldNum := 0;
    Result[N].Chars := StringReplace(CharBuf, #0, '''', [rfReplaceAll]);
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  InQuote := False;
  QuoteBuf := '';
  CharBuf := '';
  FieldChar := #0;
  FieldNum := 0;
  P := StringReplace(Pattern, '''''', #0, [rfReplaceAll]);
  for C in P do
    if not InQuote then
    begin
      if C = '''' then
      begin
        if FieldChar <> #0 then
        begin
          AddField;
          FieldChar := #0;
          FieldNum := 0;
        end
        else if CharBuf <> '' then
        begin
          AddChars;
          CharBuf := '';
        end;
        InQuote := True;
        QuoteBuf := '';
      end
      else if C in PatternChars then
      begin
        if CharBuf <> '' then
        begin
          AddChars;
          CharBuf := '';
        end;
        if C = FieldChar then
          Inc(FieldNum)
        else
        begin
          if FieldChar <> #0 then
            AddField;
          FieldChar := C;
          FieldNum := 1;
        end;
      end
      else
      begin
        if FieldChar <> #0 then
        begin
          AddField;
          FieldChar := #0;
          FieldNum := 0;
        end;
        CharBuf := CharBuf + C;
      end;
    end
    else if C = '''' then
    begin
      CharBuf := CharBuf + QuoteBuf;
      InQuote := False;
    end
    else
      QuoteBuf := QuoteBuf + C;
  if FieldChar <> #0 then
    AddField
  else if CharBuf <> '' then
    AddChars;
  SetLength(Result, N);
end;

function UntokenizeDatePattern(const Tokens: TTokenArray; First, Last: Integer): string;
var
  J, K: Integer;
  HasPatternChar: Boolean;
begin
  Result := '';
  for J := First to Last do
    if Tokens[J].IsField then
      Result := Result + StringOfChar(Tokens[J].FieldChar, Tokens[J].FieldNum)
    else
    begin
      HasPatternChar := False;
      for K := 1 to Length(Tokens[J].Chars) do
        if Tokens[J].Chars[K] in PatternChars then
          HasPatternChar := True;
      if not HasPatternChar then
        Result := Result + Tokens[J].Chars
      else
        Result := Result + '''' + StringReplace(Tokens[J].Chars, '''', '''''',
          [rfReplaceAll]) + '''';
    end;
end;

function SplitIntervalPattern(const Pattern: string): TStringArray;
var
  Tokens: TTokenArray;
  Seen: set of Char;
  J, Start, N: Integer;
begin
  Tokens := TokenizeDatePattern(Pattern);
  Seen := [];
  Result := nil;
  N := 0;
  Start := 0;
  for J := 0 to High(Tokens) do
    if Tokens[J].IsField then
    begin
      if Tokens[J].FieldChar in Seen then
      begin
        SetLength(Result, N + 1);
        Result[N] := UntokenizeDatePattern(Tokens, Start, J - 1);
        Inc(N);
        Start := J;
        Seen := [];
      end;
      Include(Seen, Tokens[J].FieldChar);
    end;
  SetLength(Result, N + 1);
  Result[N] := UntokenizeDatePattern(Tokens, Start, High(Tokens));
end;

{ --- global data ------------------------------------------------------------- }

function ReadVersion(const DtdPath: string): string;
const
  Prefix = '<!ATTLIST version cldrVersion CDATA #FIXED "';
var
  S: string;
  P, Q: Integer;
begin
  S := ReadFileBytes(DtdPath);
  P := Pos(Prefix, S);
  while P > 0 do
  begin
    Q := P + Length(Prefix) + 1; // at least one character
    while (Q <= Length(S)) and (S[Q] <> '"') and (S[Q] <> #10) do
      Inc(Q);
    if (Q <= Length(S)) and (S[Q] = '"') then
      Exit(Copy(S, P + Length(Prefix), Q - P - Length(Prefix)));
    P := Pos(Prefix, S, P + 1);
  end;
  raise Exception.Create('no CLDR version in dtd/ldml.dtd');
end;

{ The sort key of a territory's currency: tender ones first, then by
  start date ((1, 1, 1) when none). }
function CurrencyLess(A, B: TValue): Boolean;

  procedure KeyOf(V: TValue; out T: Integer; out D: array of Int64);
  var
    Start: TValue;
    J: Integer;
  begin
    if V.Items[3].Kind = vkTrue then
      T := 0
    else
      T := 1;
    Start := V.Items[1];
    for J := 0 to 2 do
      if Start.Kind = vkList then
        D[J] := Start.Items[J].I
      else
        D[J] := 1;
  end;

var
  TA, TB, J: Integer;
  DA, DB: array[0..2] of Int64;
begin
  KeyOf(A, TA, DA);
  KeyOf(B, TB, DB);
  if TA <> TB then
    Exit(TA < TB);
  for J := 0 to 2 do
    if DA[J] <> DB[J] then
      Exit(DA[J] < DB[J]);
  Result := False;
end;

procedure SortCurrencies(L: TValue);
var
  J, K: Integer;
  V: TValue;
begin
  // insertion sort: stable, as Python's sort
  for J := 1 to L.Count - 1 do
  begin
    V := L.Items[J];
    K := J - 1;
    while (K >= 0) and CurrencyLess(V, L.Items[K]) do
    begin
      L.Items[K + 1] := L.Items[K];
      Dec(K);
    end;
    L.Items[K + 1] := V;
  end;
end;

function SortedStrings(L: TStringList): TValue;
var
  A: TStringArray;
  J, K: Integer;
  T: string;
begin
  SetLength(A, L.Count);
  for J := 0 to L.Count - 1 do
    A[J] := L[J];
  for J := 1 to High(A) do
  begin
    T := A[J];
    K := J - 1;
    while (K >= 0) and (CompareBytes(T, A[K]) < 0) do
    begin
      A[K + 1] := A[K];
      Dec(K);
    end;
    A[K + 1] := T;
  end;
  Result := VList;
  for T in A do
    Result.Append(VStr(T));
end;

function ParseGlobal(const SrcDir: string): TValue;
var
  SupDir: string;
  Sup, Bcp47Tz, WinZones, SupMeta, SupLikely, TzSup, NumSys: TXDoc;
  G, TerritoryZones, ZoneAliases, ZoneTerritories, WinMapping,
    LanguageAliases, TerritoryAliases, ScriptAliases, VariantAliases,
    LikelySubtags, TerritoryCurrencies, ParentExceptions, CurrencyFractions,
    TerritoryLanguages, ZoneTerritoryMap, MetaZones, AllCurrenciesMap, Digits,
    Primary, Golden, Bcp47, TimeData, Languages, V, RegionCurrencies, Cur,
    Info, Fr: TValue;
  AllCurrencies: TStringList; // code -> TStringList of regions, in insertion order
  MapZone, KeyElem, Elem, Child, Alias, Region, Currency, Block, Paternity,
    Fraction, Ns, Territory, Language, Hours: TXElem;
  Tzid, S, Iana, Territ, C, Repl, RegionCode, CurCode, Parent, Tender,
    Status, CashD, CashR: string;
  Aliases, Parts: TStringArray;
  DigitsN, Rounding, J, Idx: Integer;
  Found: Boolean;
  Regions: TStringList;
begin
  SupDir := IncludeTrailingPathDelimiter(SrcDir) + 'supplemental' + PathDelim;
  G := VMap;
  Result := G;
  V := VMap;
  V.Put(KS('version'), VStr(ReadVersion(IncludeTrailingPathDelimiter(SrcDir) +
    'dtd' + PathDelim + 'ldml.dtd')));
  G.Put(KS('cldr'), V);
  TerritoryZones := G.SetDefaultMap(KS('territory_zones'));
  ZoneAliases := G.SetDefaultMap(KS('zone_aliases'));
  ZoneTerritories := G.SetDefaultMap(KS('zone_territories'));
  WinMapping := G.SetDefaultMap(KS('windows_zone_mapping'));
  LanguageAliases := G.SetDefaultMap(KS('language_aliases'));
  TerritoryAliases := G.SetDefaultMap(KS('territory_aliases'));
  ScriptAliases := G.SetDefaultMap(KS('script_aliases'));
  VariantAliases := G.SetDefaultMap(KS('variant_aliases'));
  LikelySubtags := G.SetDefaultMap(KS('likely_subtags'));
  TerritoryCurrencies := G.SetDefaultMap(KS('territory_currencies'));
  ParentExceptions := G.SetDefaultMap(KS('parent_exceptions'));
  CurrencyFractions := G.SetDefaultMap(KS('currency_fractions'));
  TerritoryLanguages := G.SetDefaultMap(KS('territory_languages'));

  Sup := nil; Bcp47Tz := nil; WinZones := nil; SupMeta := nil;
  SupLikely := nil; TzSup := nil; NumSys := nil;
  AllCurrencies := TStringList.Create;
  AllCurrencies.OwnsObjects := True;
  try
    Sup := TXDoc.LoadFromFile(SupDir + 'supplementalData.xml');
    Bcp47Tz := TXDoc.LoadFromFile(IncludeTrailingPathDelimiter(SrcDir) + 'bcp47' +
      PathDelim + 'timezone.xml');
    WinZones := TXDoc.LoadFromFile(SupDir + 'windowsZones.xml');
    SupMeta := TXDoc.LoadFromFile(SupDir + 'supplementalMetadata.xml');
    SupLikely := TXDoc.LoadFromFile(SupDir + 'likelySubtags.xml');

    ZoneTerritoryMap := VMap;
    for MapZone in WinZones.Root.FindAll('.//windowsZones/mapTimezones/mapZone') do
    begin
      if MapZone.TryAttr('territory', S) and (S = '001') then
      begin
        Parts := PySplit(MapZone.Attr('type'));
        if Length(Parts) = 0 then
          raise Exception.Create('mapZone without a type');
        WinMapping.Put(KS(MapZone.Attr('other')), VStr(Parts[0]));
      end;
      for Tzid in PySplit(MapZone.Attr('type')) do
        ZoneTerritoryMap.Put(KS(Tzid), VStr(MapZone.Attr('territory')));
    end;
    for KeyElem in Bcp47Tz.Root.FindAll('.//keyword/key') do
      if KeyElem.Attr('name') = 'tz' then
      begin
        for Elem in KeyElem.FindAll('type') do
        begin
          if Elem.HasAttr('deprecated') then
            Continue;
          Aliases := PySplit(Elem.Attr('alias'));
          // The canonical IANA name when CLDR gives one (CLDR's own
          // canonical ids are often older names: Asia/Calcutta).
          if not (Elem.TryAttr('iana', Iana) and (Iana <> '')) then
          begin
            if Length(Aliases) = 0 then
              raise Exception.Create('zone without aliases');
            Iana := Aliases[0];
          end;
          Tzid := Iana;
          // windowsZones may name the zone by any of its aliases.
          Territ := '001';
          Found := False;
          if ZoneTerritoryMap.Has(KS(Tzid)) then
          begin
            Territ := ZoneTerritoryMap.Get(KS(Tzid)).S;
            Found := True;
          end;
          if not Found then
            for C in Aliases do
              if ZoneTerritoryMap.Has(KS(C)) then
              begin
                Territ := ZoneTerritoryMap.Get(KS(C)).S;
                Break;
              end;
          TerritoryZones.SetDefaultList(KS(Territ)).Append(VStr(Tzid));
          ZoneTerritories.Put(KS(Tzid), VStr(Territ));
          for C in Aliases do
            if C <> Tzid then
              ZoneAliases.Put(KS(C), VStr(Tzid));
        end;
        Break;
      end;

    MetaZones := G.SetDefaultMap(KS('meta_zones'));
    TzSup := TXDoc.LoadFromFile(SupDir + 'metaZones.xml');
    for Elem in TzSup.Root.FindAll('.//timezone') do
      for Child in Elem.FindAll('usesMetazone') do
        if not Child.HasAttr('to') then
          MetaZones.Put(KS(Elem.Attr('type')), VStr(Child.Attr('mzone')));

    for Alias in SupMeta.Root.FindAll('.//alias/languageAlias') do
    begin
      if Pos('_', Alias.Attr('type')) > 0 then
        Continue;
      LanguageAliases.Put(KS(Alias.Attr('type')), VStr(Alias.Attr('replacement')));
    end;
    for Alias in SupMeta.Root.FindAll('.//alias/territoryAlias') do
    begin
      V := VList;
      for S in PySplit(Alias.Attr('replacement')) do
        V.Append(VStr(S));
      TerritoryAliases.Put(KS(Alias.Attr('type')), V);
    end;
    for Alias in SupMeta.Root.FindAll('.//alias/scriptAlias') do
      ScriptAliases.Put(KS(Alias.Attr('type')), VStr(Alias.Attr('replacement')));
    for Alias in SupMeta.Root.FindAll('.//alias/variantAlias') do
      if Alias.TryAttr('replacement', Repl) and (Repl <> '') then
        VariantAliases.Put(KS(Alias.Attr('type')), VStr(Repl));

    for Elem in SupLikely.Root.FindAll('.//likelySubtags/likelySubtag') do
      LikelySubtags.Put(KS(Elem.Attr('from')), VStr(Elem.Attr('to')));

    for Region in Sup.Root.FindAll('.//currencyData/region') do
    begin
      RegionCode := Region.Attr('iso3166');
      RegionCurrencies := VList;
      for Currency in Region.FindAll('./currency') do
      begin
        CurCode := Currency.Attr('iso4217');
        Cur := VList;
        Cur.Append(VStr(CurCode));
        Cur.Append(ParseCurrencyDate(Currency.TryAttr('from', S), S));
        Cur.Append(ParseCurrencyDate(Currency.TryAttr('to', S), S));
        Tender := Currency.AttrDef('tender', 'true');
        Cur.Append(VBool(Tender = 'true'));
        RegionCurrencies.Append(Cur);
        Idx := AllCurrencies.IndexOf(CurCode);
        if Idx < 0 then
        begin
          Regions := TStringList.Create;
          Regions.Sorted := True;
          Regions.Duplicates := dupIgnore;
          Regions.CaseSensitive := True;
          AllCurrencies.AddObject(CurCode, Regions);
        end
        else
          Regions := TStringList(AllCurrencies.Objects[Idx]);
        Regions.Add(RegionCode);
      end;
      SortCurrencies(RegionCurrencies);
      TerritoryCurrencies.Put(KS(RegionCode), RegionCurrencies);
    end;
    AllCurrenciesMap := VMap;
    for J := 0 to AllCurrencies.Count - 1 do
      AllCurrenciesMap.Put(KS(AllCurrencies[J]),
        SortedStrings(TStringList(AllCurrencies.Objects[J])));
    G.Put(KS('all_currencies'), AllCurrenciesMap);

    // Only unqualified parentLocales blocks; parent "root" (localeRules=
    // "nonlikelyScript") is applied at load time.
    for Block in Sup.Root.FindAll('.//parentLocales') do
    begin
      if Block.TryAttr('component', S) and (S <> '') then
        Continue;
      for Paternity in Block.FindAll('./parentLocale') do
      begin
        Parent := Paternity.Attr('parent');
        if Parent = 'root' then
          Continue;
        for C in PySplit(Paternity.Attr('locales')) do
          ParentExceptions.Put(KS(C), VStr(Parent));
      end;
    end;

    for Fraction in Sup.Root.FindAll('.//currencyData/fractions/info') do
    begin
      DigitsN := PyInt(Fraction.Attr('digits'));
      Rounding := PyInt(Fraction.Attr('rounding'));
      Fr := VList;
      Fr.Append(VInt(DigitsN));
      Fr.Append(VInt(Rounding));
      if Fraction.TryAttr('cashDigits', CashD) then
        Fr.Append(VInt(PyInt(CashD)))
      else
        Fr.Append(VInt(DigitsN));
      if Fraction.TryAttr('cashRounding', CashR) then
        Fr.Append(VInt(PyInt(CashR)))
      else
        Fr.Append(VInt(Rounding));
      CurrencyFractions.Put(KS(Fraction.Attr('iso4217')), Fr);
    end;

    // The digits of each numeric numbering system, so that numbers can be
    // written in the locale's digits.
    Digits := G.SetDefaultMap(KS('numbering_system_digits'));
    NumSys := TXDoc.LoadFromFile(SupDir + 'numberingSystems.xml');
    for Ns in NumSys.Root.FindAll('.//numberingSystem') do
      if Ns.TryAttr('type', S) and (S = 'numeric') then
        Digits.Put(KS(Ns.Attr('id')), VStr(Ns.Attr('digits')));

    // The primary zone of countries with several zones
    // (Europe/Madrid for ES: 'Spain Time'), the golden zone of each
    // metazone per territory (for partial location names), and the short
    // BCP 47 id of each zone (the V field: 'usnyc').
    Primary := G.SetDefaultMap(KS('primary_zones'));
    for Elem in TzSup.Root.FindAll('.//primaryZones/primaryZone') do
      Primary.Put(KS(Elem.Attr('iso3166')), VText(Elem));
    Golden := G.SetDefaultMap(KS('metazone_golden_zones'));
    for Elem in TzSup.Root.FindAll('.//mapTimezones/mapZone') do
      Golden.SetDefaultMap(KS(Elem.Attr('other'))).Put(KS(Elem.Attr('territory')),
        VStr(Elem.Attr('type')));
    Bcp47 := G.SetDefaultMap(KS('zone_bcp47'));
    for KeyElem in Bcp47Tz.Root.FindAll('.//keyword/key') do
      if KeyElem.Attr('name') = 'tz' then
        for Elem in KeyElem.FindAll('type') do
        begin
          if Elem.HasAttr('deprecated') then
            Continue;
          for C in PySplit(Elem.AttrDef('alias', '')) do
            Bcp47.SetDefault(KS(C), VStr(Elem.Attr('name')));
          if Elem.TryAttr('iana', Iana) and (Iana <> '') then
            Bcp47.SetDefault(KS(Iana), VStr(Elem.Attr('name')));
        end;

    // The hour cycles of each region or locale (for the
    // skeleton characters j, J and C).
    TimeData := G.SetDefaultMap(KS('time_data'));
    for Hours in Sup.Root.FindAll('.//timeData/hours') do
      for C in PySplit(Hours.Attr('regions')) do
      begin
        Info := VMap;
        Info.Put(KS('preferred'), VStr(Hours.Attr('preferred')));
        Info.Put(KS('allowed'), VStr(Hours.Attr('allowed')));
        TimeData.Put(KS(C), Info);
      end;

    for Territory in Sup.Root.FindAll('.//territoryInfo/territory') do
    begin
      Languages := VMap;
      for Language in Territory.FindAll('./languagePopulation') do
      begin
        Info := VMap;
        Info.Put(KS('population_percent'),
          VFloat(PyFloat(Language.Attr('populationPercent'))));
        Info.Put(KS('official_status'),
          VOpt(Language.TryAttr('officialStatus', Status), Status));
        Languages.Put(KS(Language.Attr('type')), Info);
      end;
      TerritoryLanguages.Put(KS(Territory.Attr('type')), Languages);
    end;
  finally
    Sup.Free; Bcp47Tz.Free; WinZones.Free; SupMeta.Free; SupLikely.Free;
    TzSup.Free; NumSys.Free;
    AllCurrencies.Free;
  end;
end;

{ --- per-locale data --------------------------------------------------------- }

function ParseDayPeriodRules(Doc: TXDoc): TValue;
const
  RuleKeys: array[0..4] of string = ('after', 'at', 'before', 'from', 'to');
var
  RuleSet, Rules, Rule: TXElem;
  RsType, Typ, S, Locale: string;
  RsHas: Boolean;
  Locales: TStringArray;
  Compact: TValue;
  K: string;
begin
  Result := VMap;
  for RuleSet in Doc.Root.FindAll('.//dayPeriodRuleSet') do
  begin
    RsHas := RuleSet.TryAttr('type', RsType); // None or "selection"
    for Rules in RuleSet.FindAll('dayPeriodRules') do
    begin
      Locales := PySplit(Rules.Attr('locales'));
      for Rule in Rules.FindAll('dayPeriodRule') do
      begin
        Typ := Rule.Attr('type');
        if (Typ = 'am') or (Typ = 'pm') then
          Continue;
        Compact := VMap;
        for K in RuleKeys do
          if Rule.TryAttr(K, S) then
            Compact.Put(KS(K), VInt(TimeToSeconds(S)));
        for Locale in Locales do
          Result.SetDefaultMap(KS(Locale)).SetDefaultMap(KOpt(RsHas, RsType))
            .SetDefaultList(KS(Typ)).Append(Compact);
      end;
    end;
  end;
end;

procedure ParseLocaleDisplayNames(Data: TValue; Root: TXElem; IsGlobal: Boolean);
const
  Keys: array[0..3] of string = ('territories', 'languages', 'variants', 'scripts');
  Paths: array[0..3] of string = ('.//territories/territory', './/languages/language',
    './/variants/variant', './/scripts/script');
var
  J: Integer;
  Dest: TValue;
  E: TXElem;
begin
  for J := 0 to 3 do
  begin
    Dest := Data.SetDefaultMap(KS(Keys[J]));
    for E in Root.FindAll(Paths[J]) do
      ImportTypeText(Dest, E, TypeKey(E), IsGlobal);
  end;
end;

procedure ParseListPatterns(Data: TValue; Root: TXElem);
var
  ListPatterns: TValue;
  El, Part: TXElem;
begin
  ListPatterns := Data.SetDefaultMap(KS('list_patterns'));
  for El in Root.FindAll('.//listPatterns/listPattern') do
    for Part in El.FindAll('listPatternPart') do
      ListPatterns.SetDefaultMap(KS(El.AttrDef('type', 'standard')))
        .Put(KS(Part.Attr('type')), VStr(ElemText(Part)));
end;

function InList(const S: string; const L: TStringArray): Boolean;
var
  T: string;
begin
  for T in L do
    if T = S then
      Exit(True);
  Result := False;
end;

procedure ParseDates(Data: TValue; Root: TXElem; Sup: TXDoc; Regions: TStringList;
  const Territory: string);
const
  WeekTags: array[0..3] of string = ('minDays', 'firstDay', 'weekendStart', 'weekendEnd');
  WeekKeys: array[0..3] of string = ('min_days', 'first_day', 'weekend_start', 'weekend_end');
  ZoneTags: array[0..3] of string = ('gmtFormat', 'regionFormat', 'fallbackFormat',
    'fallbackRegionFormat');
  ZoneKeys: array[0..3] of string = ('gmt', 'region', 'fallback', 'fallback_region');
var
  WeekData, ZoneFormats, Dest, Info: TValue;
  SupElem, Elem, Child: TXElem;
  J, R: Integer;
  Territories: TStringArray;
  Match: Boolean;
  S, City: string;

  function WeekValue(E: TXElem; J: Integer): TValue;
  begin
    if J = 0 then
      Result := VInt(PyInt(E.Attr('count')))
    else
      Result := VInt(Weekday(E.Attr('day')));
  end;

begin
  WeekData := Data.SetDefaultMap(KS('week_data'));
  SupElem := Sup.Root.Find('.//weekData');
  for J := 0 to 3 do
  begin
    for Elem in SupElem.FindAll(WeekTags[J]) do
    begin
      if ShouldSkip(Elem, KNone, nil) then
        Continue;
      Territories := PySplit(Elem.Attr('territories'));
      Match := InList(Territory, Territories);
      if not Match and (Regions <> nil) then
        for R := 0 to Regions.Count - 1 do
          if InList(Regions[R], Territories) then
          begin
            Match := True;
            Break;
          end;
      if Match then
        WeekData.Put(KS(WeekKeys[J]), WeekValue(Elem, J));
    end;
    // A territory not listed has the world's value (CLDR): fr_CA's
    // minimal days are 1, not fr's 4.
    if not WeekData.Has(KS(WeekKeys[J])) then
      for Elem in SupElem.FindAll(WeekTags[J]) do
        if not ShouldSkip(Elem, KNone, nil) and
          InList('001', PySplit(Elem.Attr('territories'))) then
          WeekData.Put(KS(WeekKeys[J]), WeekValue(Elem, J));
  end;

  ZoneFormats := Data.SetDefaultMap(KS('zone_formats'));
  for J := 0 to 3 do
    for Elem in Root.FindAll('.//timeZoneNames/' + ZoneTags[J]) do
      // the plain regionFormat (in fr_CA the daylight variant
      // '{0} (heure avancée)' comes first)
      if not ShouldSkip(Elem, KNone, nil) and not Elem.HasAttr('type') then
      begin
        S := StrOf(Elem);
        if J < 2 then
          S := StringReplace(S, '{0}', '%s', [rfReplaceAll])
        else
          S := StringReplace(StringReplace(S, '{0}', '%(0)s', [rfReplaceAll]),
            '{1}', '%(1)s', [rfReplaceAll]);
        ZoneFormats.Put(KS(ZoneKeys[J]), VStr(S));
        Break;
      end;

  for J := 0 to 1 do
  begin
    if J = 0 then
      Dest := Data.SetDefaultMap(KS('time_zones'))
    else
      Dest := Data.SetDefaultMap(KS('meta_zones'));
    if J = 0 then
      S := 'zone'
    else
      S := 'metazone';
    for Elem in Root.FindAll('.//timeZoneNames/' + S) do
    begin
      Info := VMap;
      if Elem.FindText('exemplarCity', City) and (City <> '') then
        Info.Put(KS('city'), VStr(City));
      for Child in Elem.FindAll('long/*') do
        Info.SetDefaultMap(KS('long')).Put(KS(Child.Tag), VStr(StrOf(Child)));
      for Child in Elem.FindAll('short/*') do
        Info.SetDefaultMap(KS('short')).Put(KS(Child.Tag), VStr(StrOf(Child)));
      Dest.Put(KS(Elem.Attr('type')), Info);
    end;
  end;
end;

type
  TConvertType = function(const S: string): TKey;

function IntKey(const S: string): TKey;
begin
  Result := KI(PyInt(S));
end;

function WeekdayKey(const S: string): TKey;
begin
  Result := KI(Weekday(S));
end;

{ months, days and quarters: context -> width -> index -> name. }
procedure ParseCalendarContext(Data: TValue; Calendar: TXElem; const Key, ItemTag: string;
  Convert: TConvertType);
var
  Dest, Ctxts, Widths: TValue;
  Ctxt, Width, Elem: TXElem;
  CtxtType, WidthType: string;
  J: Integer;
begin
  Dest := Data.SetDefaultMap(KS(Key));
  for Ctxt in Calendar.FindAll(Key + '/' + ItemTag + 'Context') do
  begin
    CtxtType := Ctxt.Attr('type');
    Ctxts := Dest.SetDefaultMap(KS(CtxtType));
    for Width in Ctxt.FindAll(ItemTag + 'Width') do
    begin
      WidthType := Width.Attr('type');
      Widths := Ctxts.SetDefaultMap(KS(WidthType));
      for J := 0 to Width.ChildCount - 1 do
      begin
        Elem := Width.Children[J];
        if Elem.Tag = ItemTag then
          ImportTypeText(Widths, Elem, Convert(Elem.Attr('type')))
        else if Elem.Tag = 'alias' then
          Ctxts.Put(KS(WidthType), VAlias(TranslateAlias([Key, CtxtType, WidthType],
            Elem.Attr('path'))));
      end;
    end;
  end;
end;

procedure ParseCalendarEras(Data: TValue; Calendar: TXElem);
var
  Eras, Widths: TValue;
  Width, Elem: TXElem;
  WidthType: string;
  J: Integer;
begin
  Eras := Data.SetDefaultMap(KS('eras'));
  for Width in Calendar.FindAll('eras/*') do
  begin
    if not MapName(Width.Tag, WidthType) then
      raise Exception.CreateFmt('unknown era width %s', [Width.Tag]);
    Widths := Eras.SetDefaultMap(KS(WidthType));
    for J := 0 to Width.ChildCount - 1 do
    begin
      Elem := Width.Children[J];
      if Elem.Tag = 'era' then
        ImportTypeText(Widths, Elem, KI(PyInt(Elem.Attr('type'))))
      else if Elem.Tag = 'alias' then
        Eras.Put(KS(WidthType), VAlias(TranslateAlias(['eras', WidthType],
          Elem.Attr('path'))));
    end;
  end;
end;

procedure ParseCalendarPeriods(Data: TValue; Calendar: TXElem);
var
  Periods, Dest: TValue;
  Ctx, Width, DayPeriod: TXElem;
begin
  Periods := Data.SetDefaultMap(KS('day_periods'));
  for Ctx in Calendar.FindAll('dayPeriods/dayPeriodContext') do
    for Width in Ctx.FindAll('dayPeriodWidth') do
    begin
      Dest := Periods.SetDefaultMap(KS(Ctx.Attr('type'))).SetDefaultMap(KS(Width.Attr('type')));
      for DayPeriod in Width.FindAll('dayPeriod') do
        if not DayPeriod.HasAttr('alt') then
          Dest.Put(KS(DayPeriod.Attr('type')), VStr(StrOf(DayPeriod)));
    end;
end;

{ date_formats and time_formats: length -> pattern. An alias element
  replaces the local variable only, so it never reaches the data (root's
  formats have no alias). }
procedure ParseCalendarFormats(Data: TValue; Calendar: TXElem; const ContainerTag,
  LengthTag, Key, PatternPath: string);
var
  Formats: TValue;
  Container, Elem: TXElem;
  J: Integer;
  T: string;
  K: TKey;
begin
  Formats := Data.SetDefaultMap(KS(Key));
  for Container in Calendar.FindAll(ContainerTag) do
    for J := 0 to Container.ChildCount - 1 do
    begin
      Elem := Container.Children[J];
      if Elem.Tag = LengthTag then
      begin
        K := KOpt(Elem.TryAttr('type', T), T);
        if ShouldSkip(Elem, K, Formats) then
          Continue;
        Formats.Put(K, VStr(StrFindText(Elem, PatternPath)));
      end
      else if Elem.Tag = 'alias' then
        Formats := VAlias(TranslateAlias([Key], Elem.Attr('path')));
    end;
end;

{ datetime_formats and datetime_skeletons. Alternates (alt="ascii":
  'h:mm a' for 'h:mm a' in en; alt="variant") are skipped, as ICU
  does. }
procedure ParseCalendarDatetimeSkeletons(Data: TValue; Calendar: TXElem);
var
  DatetimeFormats, Skeletons: TValue;
  Container, Elem, Skeleton: TXElem;
  J: Integer;
  T: string;
  K: TKey;
begin
  DatetimeFormats := Data.SetDefaultMap(KS('datetime_formats'));
  Skeletons := Data.SetDefaultMap(KS('datetime_skeletons'));
  for Container in Calendar.FindAll('dateTimeFormats') do
    for J := 0 to Container.ChildCount - 1 do
    begin
      Elem := Container.Children[J];
      if Elem.Tag = 'dateTimeFormatLength' then
      begin
        K := KOpt(Elem.TryAttr('type', T), T);
        if ShouldSkip(Elem, K, DatetimeFormats) then
          Continue;
        DatetimeFormats.Put(K, VStr(StrFindText(Elem, 'dateTimeFormat/pattern')));
      end
      else if Elem.Tag = 'alias' then
        DatetimeFormats := VAlias(TranslateAlias(['datetime_formats'], Elem.Attr('path')))
      else if Elem.Tag = 'availableFormats' then
        for Skeleton in Elem.FindAll('dateFormatItem') do
        begin
          if Skeleton.HasAttr('alt') then
            Continue;
          Skeletons.Put(KS(Skeleton.Attr('id')), VStr(StrOf(Skeleton)));
        end;
    end;
end;

{ interval_formats; alternate differences skipped as for skeletons. }
procedure ParseIntervalFormats(Data: TValue; Calendar: TXElem);
var
  IntervalFormats, SkelData, Parts: TValue;
  Elem, Sub: TXElem;
  J: Integer;
  S: string;
begin
  IntervalFormats := Data.SetDefaultMap(KS('interval_formats'));
  for Elem in Calendar.FindAll('dateTimeFormats/intervalFormats/*') do
  begin
    if Elem.HasAttr('draft') then
      Continue;
    if Elem.Tag = 'intervalFormatFallback' then
      IntervalFormats.Put(KNone, VText(Elem))
    else if Elem.Tag = 'intervalFormatItem' then
    begin
      SkelData := IntervalFormats.SetDefaultMap(KS(Elem.Attr('id')));
      for J := 0 to Elem.ChildCount - 1 do
      begin
        Sub := Elem.Children[J];
        if Sub.Tag <> 'greatestDifference' then
          raise Exception.CreateFmt('NotImplemented: %s', [Sub.Tag]);
        if Sub.HasAttr('alt') then
          Continue;
        if not Sub.HasText then
          raise Exception.Create('greatestDifference without a pattern');
        Parts := VList;
        for S in SplitIntervalPattern(Sub.Text) do
          Parts.Append(VStr(S));
        SkelData.Put(KS(Sub.Attr('id')), Parts);
      end;
    end;
  end;
end;

procedure ParseNumberSymbols(Data: TValue; Root: TXElem);
var
  NumberSymbols: TValue;
  SystemElem, Symbol: TXElem;
  Ns: string;
begin
  NumberSymbols := Data.SetDefaultMap(KS('number_symbols'));
  for SystemElem in Root.FindAll('.//numbers/symbols') do
  begin
    if not SystemElem.TryAttr('numberSystem', Ns) or (Ns = '') then
      Continue;
    for Symbol in SystemElem.FindAll('./*') do
    begin
      if ShouldSkip(Symbol, KNone, nil) then
        Continue;
      NumberSymbols.SetDefaultMap(KS(Ns)).Put(KS(Symbol.Tag), VStr(StrOf(Symbol)));
    end;
  end;
end;

procedure ParseNumberingSystems(Data: TValue; Root: TXElem);
var
  Node: TXElem;
  NumberingSystems: TValue;
  J: Integer;
begin
  Node := Root.Find('.//numbers/defaultNumberingSystem');
  if Node <> nil then
    Data.Put(KS('default_numbering_system'), VText(Node));
  NumberingSystems := Data.SetDefaultMap(KS('numbering_systems'));
  // An element with no children counts as absent.
  Node := Root.Find('.//numbers/otherNumberingSystems');
  if (Node <> nil) and (Node.ChildCount > 0) then
    for J := 0 to Node.ChildCount - 1 do
      NumberingSystems.Put(KS(Node.Children[J].Tag), VText(Node.Children[J]));
end;

procedure ParseDecimalFormats(Data: TValue; Root: TXElem);
var
  DecimalFormats, Compact: TValue;
  DfElem, Elem, PatternEl: TXElem;
  T, PatternType, Pattern: string;
  LengthKey: TKey;
begin
  DecimalFormats := Data.SetDefaultMap(KS('decimal_formats'));
  for DfElem in Root.FindAll('.//decimalFormats') do
  begin
    if ShouldSkipNumber(DfElem) then
      Continue;
    for Elem in DfElem.FindAll('./decimalFormatLength') do
    begin
      LengthKey := KOpt(Elem.TryAttr('type', T), T);
      if ShouldSkip(Elem, LengthKey, DecimalFormats) then
        Continue;
      if Length(Elem.FindAll('./alias')) > 0 then
        Continue;
      for PatternEl in Elem.FindAll('./decimalFormat/pattern') do
      begin
        Pattern := StrOf(PatternEl);
        if PatternEl.TryAttr('type', PatternType) and (PatternType <> '') then
        begin
          Compact := Data.SetDefaultMap(KS('compact_decimal_formats'));
          Compact.SetDefaultMap(LengthKey).SetDefaultMap(KS(PatternEl.Attr('count')))
            .Put(KS(PatternType), VStr(Pattern));
        end
        else
          DecimalFormats.Put(LengthKey, VStr(Pattern));
      end;
    end;
  end;
end;

{ scientific_formats and percent_formats: length -> pattern. }
procedure ParseSimpleNumberFormats(Data: TValue; Root: TXElem; const ContainerTag,
  LengthPath, Key, PatternPath: string);
var
  Formats: TValue;
  Container, Elem: TXElem;
  T: string;
  K: TKey;
begin
  Formats := Data.SetDefaultMap(KS(Key));
  for Container in Root.FindAll('.//' + ContainerTag) do
  begin
    if ShouldSkipNumber(Container) then
      Continue;
    for Elem in Container.FindAll(LengthPath) do
    begin
      K := KOpt(Elem.TryAttr('type', T), T);
      if ShouldSkip(Elem, K, Formats) then
        Continue;
      Formats.Put(K, VStr(StrFindText(Elem, PatternPath)));
    end;
  end;
end;

procedure ParseCurrencyFormats(Data: TValue; Root: TXElem);
var
  CurrencyFormats, Compact: TValue;
  CurrencyFormat, LengthElem, Elem, Child: TXElem;
  CurrLengthType, T, PatternType, S: string;
  HasLength: Boolean;
  K: TKey;
begin
  CurrencyFormats := Data.SetDefaultMap(KS('currency_formats'));
  for CurrencyFormat in Root.FindAll('.//currencyFormats') do
  begin
    if ShouldSkipNumber(CurrencyFormat) then
      Continue;
    for LengthElem in CurrencyFormat.FindAll('./currencyFormatLength') do
    begin
      HasLength := LengthElem.TryAttr('type', CurrLengthType);
      for Elem in LengthElem.FindAll('currencyFormat') do
      begin
        K := KOpt(Elem.TryAttr('type', T), T);
        if ShouldSkip(Elem, K, CurrencyFormats) then
          Continue;
        for Child in Elem.Iter do
          if Child.Tag = 'alias' then
            CurrencyFormats.Put(K, VAlias(TranslateAlias(['currency_formats',
              Elem.Attr('type')], Child.Attr('path'))))
          else if Child.Tag = 'pattern' then
          begin
            if (Child.TryAttr('draft', S) and (S <> '')) or
              (Child.TryAttr('alt', S) and (S <> '')) then
              Continue;
            if Child.TryAttr('type', PatternType) and (PatternType <> '') then
            begin
              Compact := Data.SetDefaultMap(KS('compact_currency_formats'));
              Compact.SetDefaultMap(KOpt(HasLength, CurrLengthType))
                .SetDefaultMap(KS(Child.Attr('count'))).Put(KS(PatternType),
                VStr(StrOf(Child)));
            end
            else
              CurrencyFormats.Put(K, VStr(StrOf(Child)));
          end;
      end;
    end;
  end;
end;

{ minimumGroupingDigits, the currencySpacing of the Latin numbering system,
  and the patterns of the other numbering systems. }
procedure ParseNumberExtras(Data: TValue; Root: TXElem);
const
  Tags: array[0..2] of string = ('decimalFormats', 'percentFormats', 'scientificFormats');
  LengthPaths: array[0..2] of string = ('decimalFormatLength', 'percentFormatLength',
    'scientificFormatLength');
  PatternPaths: array[0..2] of string = ('decimalFormat/pattern', 'percentFormat/pattern',
    'scientificFormat/pattern');
  Kinds: array[0..2] of string = ('decimal', 'percent', 'scientific');
  Sides: array[0..1] of string = ('beforeCurrency', 'afterCurrency');
var
  Elem, Formats, Spacing, SideElem, Child, Len, Pattern, Fmt: TXElem;
  Dest, M, BySystem: TValue;
  D, Ns, Kind: string;
  J, K: Integer;
begin
  for Elem in Root.FindAll('.//numbers/minimumGroupingDigits') do
  begin
    if (Elem.TryAttr('draft', D) and ((D = 'unconfirmed') or (D = 'provisional'))) or
      Elem.HasAttr('alt') then
      Continue;
    if not Elem.HasText then
      raise Exception.Create('minimumGroupingDigits without a value');
    Data.Put(KS('min_grouping_digits'), VInt(PyInt(Elem.Text)));
  end;
  for Formats in Root.FindAll('.//currencyFormats') do
  begin
    if ShouldSkipNumber(Formats) then
      Continue;
    Spacing := Formats.Find('currencySpacing');
    if (Spacing = nil) or (Spacing.Find('alias') <> nil) then
      Continue;
    Dest := VMap;
    for J := 0 to 1 do
    begin
      SideElem := Spacing.Find(Sides[J]);
      if SideElem <> nil then
      begin
        M := VMap;
        for K := 0 to SideElem.ChildCount - 1 do
        begin
          Child := SideElem.Children[K];
          M.Put(KS(Child.Tag), VStr(Child.Text));
        end;
        Dest.Put(KS(Sides[J]), M);
      end;
    end;
    if Dest.Count > 0 then
      Data.Put(KS('currency_spacing'), Dest);
  end;

  // The patterns of the other numbering systems (system -> kind ->
  // pattern): CLDR gives some their own (fa's arab and arabext currency
  // pattern has no space; bn's beng percent pattern groups by three). An
  // alias (to the latn patterns) adds nothing: latn is the fallback.
  BySystem := VMap;
  for J := 0 to 2 do
    for Formats in Root.FindAll('.//numbers/' + Tags[J]) do
    begin
      Ns := Formats.AttrDef('numberSystem', 'latn');
      if (Ns = 'latn') or (Formats.Find('alias') <> nil) then
        Continue;
      for Len in Formats.FindAll(LengthPaths[J]) do
      begin
        if Len.HasAttr('type') or IsDraftOrAlt(Len) or (Len.Find('alias') <> nil) then
          Continue;
        for Pattern in Len.FindAll(PatternPaths[J]) do
        begin
          if Pattern.HasAttr('type') or IsDraftOrAlt(Pattern) then
            Continue;
          BySystem.SetDefaultMap(KS(Ns)).SetDefault(KS(Kinds[J]), VStr(StrOf(Pattern)));
        end;
      end;
    end;
  for Formats in Root.FindAll('.//numbers/currencyFormats') do
  begin
    Ns := Formats.AttrDef('numberSystem', 'latn');
    if (Ns = 'latn') or (Formats.Find('alias') <> nil) then
      Continue;
    for Len in Formats.FindAll('currencyFormatLength') do
    begin
      if Len.HasAttr('type') then
        Continue;
      for Fmt in Len.FindAll('currencyFormat') do
      begin
        Kind := 'currency_' + Fmt.AttrDef('type', 'standard');
        if IsDraftOrAlt(Fmt) or (Fmt.Find('alias') <> nil) then
          Continue;
        for Pattern in Fmt.FindAll('pattern') do
        begin
          if Pattern.HasAttr('type') or IsDraftOrAlt(Pattern) then
            Continue;
          BySystem.SetDefaultMap(KS(Ns)).SetDefault(KS(Kind), VStr(StrOf(Pattern)));
        end;
      end;
    end;
  end;
  if BySystem.Count > 0 then
    Data.Put(KS('numbering_system_formats'), BySystem);
end;

{ hourFormat and gmtZeroFormat (localized GMT), the atTime variant of the
  Gregorian date-time patterns, and the aliases between relative-time
  fields. }
procedure ParseDateExtras(Data: TValue; Root: TXElem);
const
  Tags: array[0..1] of string = ('hourFormat', 'gmtZeroFormat');
  Keys: array[0..1] of string = ('hour', 'gmt_zero');
var
  Gmt, AtTime, Aliases: TValue;
  Elem, Calendar, Len, Fmt, Field, Alias: TXElem;
  J: Integer;
  Pattern, T, Path, Captured: string;

  { re.search(r"field\[@type='([^']+)'\]", Path) }
  function SearchField(const Path: string; out Value: string): Boolean;
  const
    Prefix = 'field[@type=''';
  var
    P, Q: Integer;
  begin
    P := Pos(Prefix, Path);
    while P > 0 do
    begin
      Q := P + Length(Prefix);
      while (Q <= Length(Path)) and (Path[Q] <> '''') do
        Inc(Q);
      if (Q > P + Length(Prefix)) and (Q + 1 <= Length(Path)) and (Path[Q + 1] = ']') then
      begin
        Value := Copy(Path, P + Length(Prefix), Q - P - Length(Prefix));
        Exit(True);
      end;
      P := Pos(Prefix, Path, P + 1);
    end;
    Result := False;
  end;

begin
  Gmt := VMap;
  for J := 0 to 1 do
    for Elem in Root.FindAll('.//timeZoneNames/' + Tags[J]) do
      if not ShouldSkip(Elem, KNone, nil) then
      begin
        Gmt.Put(KS(Keys[J]), VStr(StrOf(Elem)));
        Break;
      end;
  if Gmt.Count > 0 then
    Data.Put(KS('gmt_formats'), Gmt);
  for Calendar in Root.FindAll('.//calendars/calendar') do
  begin
    if Calendar.Attr('type') <> 'gregorian' then
      Continue;
    AtTime := VMap;
    for Len in Calendar.FindAll('dateTimeFormats/dateTimeFormatLength') do
    begin
      if IsDraftOrAlt(Len) then
        Continue;
      for Fmt in Len.FindAll('dateTimeFormat') do
        if Fmt.FindText('pattern', Pattern) and (Fmt.AttrDef('type', '') = 'atTime') and
          not IsDraftOrAlt(Fmt) and (Pattern <> '') then
          AtTime.Put(KOpt(Len.TryAttr('type', T), T), VStr(Pattern));
    end;
    if AtTime.Count > 0 then
      Data.Put(KS('datetime_formats_at_time'), AtTime);
  end;
  // The aliases between relative-time fields ('second-narrow' is
  // 'second-short' in root); the aliased fields themselves are empty.
  Aliases := VMap;
  for Field in Root.FindAll('.//dates/fields/field') do
  begin
    Alias := Field.Find('alias');
    if Alias <> nil then
    begin
      Path := Alias.Attr('path');
      if SearchField(Path, Captured) then
        Aliases.Put(KS(Field.Attr('type')), VStr(Captured));
    end;
  end;
  if Aliases.Count > 0 then
    Data.Put(KS('date_field_aliases'), Aliases);
end;

procedure ParseCurrencyUnitPatterns(Data: TValue; Root: TXElem);
var
  Patterns: TValue;
  Elem, UnitPattern: TXElem;
begin
  Patterns := Data.SetDefaultMap(KS('currency_unit_patterns'));
  for Elem in Root.FindAll('.//currencyFormats') do
  begin
    if ShouldSkipNumber(Elem) then
      Continue;
    for UnitPattern in Elem.FindAll('./unitPattern') do
      Patterns.Put(KS(UnitPattern.Attr('count')), VStr(StrOf(UnitPattern)));
  end;
end;

procedure ParseCurrencyNames(Data: TValue; Root: TXElem);
var
  Names, NamesPlural, Symbols: TValue;
  Elem, Name, Symbol: TXElem;
  Code, S: string;
begin
  Names := Data.SetDefaultMap(KS('currency_names'));
  NamesPlural := Data.SetDefaultMap(KS('currency_names_plural'));
  Symbols := Data.SetDefaultMap(KS('currency_symbols'));
  for Elem in Root.FindAll('.//currencies/currency') do
  begin
    Code := Elem.Attr('type');
    for Name in Elem.FindAll('displayName') do
    begin
      if Name.HasAttr('draft') and Names.Has(KS(Code)) then
        Continue;
      if Name.HasAttr('count') then
        NamesPlural.SetDefaultMap(KS(Code)).Put(KS(Name.Attr('count')), VStr(StrOf(Name)))
      else
        Names.Put(KS(Code), VStr(StrOf(Name)));
    end;
    for Symbol in Elem.FindAll('symbol') do
    begin
      if Symbol.HasAttr('draft') or Symbol.HasAttr('choice') then
        Continue;
      if Symbol.TryAttr('alt', S) and (S <> '') then
        Continue;
      Symbols.Put(KS(Code), VStr(StrOf(Symbol)));
    end;
  end;
end;

procedure ParseUnitPatterns(Data: TValue; Root: TXElem);
var
  UnitPatterns, CompoundPatterns, DisplayNames, Dest, Info, Variations: TValue;
  Elem, AUnit, Pattern, PerUnit, DisplayName, Child: TXElem;
  Len, UnitType, S, First: string;
  J, K: Integer;
  AllSame: Boolean;
begin
  UnitPatterns := Data.SetDefaultMap(KS('unit_patterns'));
  CompoundPatterns := Data.SetDefaultMap(KS('compound_unit_patterns'));
  DisplayNames := Data.SetDefaultMap(KS('unit_display_names'));
  for Elem in Root.FindAll('.//units/unitLength') do
  begin
    Len := Elem.Attr('type');
    for AUnit in Elem.FindAll('unit') do
    begin
      UnitType := AUnit.Attr('type');
      Dest := UnitPatterns.SetDefaultMap(KS(UnitType)).SetDefaultMap(KS(Len));
      for Pattern in AUnit.FindAll('unitPattern') do
      begin
        if Pattern.AttrDef('case', 'nominative') <> 'nominative' then
          Continue;
        Dest.Put(KS(Pattern.Attr('count')), VStr(ElemText(Pattern)));
      end;
      PerUnit := AUnit.Find('perUnitPattern');
      if PerUnit <> nil then
        Dest.Put(KS('per'), VStr(ElemText(PerUnit)));
      DisplayName := AUnit.Find('displayName');
      if DisplayName <> nil then
        DisplayNames.SetDefaultMap(KS(UnitType)).Put(KS(Len), VStr(ElemText(DisplayName)));
    end;
    for AUnit in Elem.FindAll('compoundUnit') do
    begin
      Info := VMap;
      Variations := VMap;
      for J := 0 to AUnit.ChildCount - 1 do
      begin
        Child := AUnit.Children[J];
        if Child.AttrDef('case', 'nominative') <> 'nominative' then
          Continue;
        if Child.Tag = 'unitPrefixPattern' then
          Info.Put(KS('prefix'), VStr(ElemText(Child)))
        else if Child.Tag = 'compoundUnitPattern' then
          Variations.Put(KNone, VStr(ElemText(Child)))
        else if Child.Tag = 'compoundUnitPattern1' then
          Variations.Put(KOpt(Child.TryAttr('count', S), S), VStr(ElemText(Child)));
      end;
      if Variations.Count > 0 then
      begin
        First := Variations.Items[0].S;
        AllSame := True;
        for K := 1 to Variations.Count - 1 do
          if Variations.Items[K].S <> First then
            AllSame := False;
        if AllSame then
          Info.Put(KS('compound'), VStr(First))
        else
          Info.Put(KS('compound_variations'), Variations);
      end;
      CompoundPatterns.SetDefaultMap(KS(AUnit.Attr('type'))).Put(KS(Len), Info);
    end;
  end;
end;

procedure ParseDateFields(Data: TValue; Root: TXElem);
var
  DateFields, FieldMap: TValue;
  Elem, RelTime, Pattern: TXElem;
  FieldType: string;
begin
  DateFields := Data.SetDefaultMap(KS('date_fields'));
  for Elem in Root.FindAll('.//dates/fields/field') do
  begin
    FieldType := Elem.Attr('type');
    FieldMap := DateFields.SetDefaultMap(KS(FieldType));
    for RelTime in Elem.FindAll('relativeTime') do
      for Pattern in RelTime.FindAll('relativeTimePattern') do
        FieldMap.SetDefaultMap(KS(RelTime.Attr('type'))).Put(KS(Pattern.Attr('count')),
          VStr(StrOf(Pattern)));
  end;
end;

{ TLocaleImporter }

constructor TLocaleImporter.Create(const SrcDir: string);
var
  SupDir, Group, Territory: string;
  Regions: TStringList; // group -> TStringArray boxed as TStringList
  Doc: TXDoc;
  Elem: TXElem;
  J, Idx, GIdx, K: Integer;
  Members, Containers, GroupContainers: TStringList;
begin
  inherited Create;
  FSrcDir := SrcDir;
  SupDir := IncludeTrailingPathDelimiter(SrcDir) + 'supplemental' + PathDelim;
  FSup := TXDoc.LoadFromFile(SupDir + 'supplementalData.xml');
  Doc := TXDoc.LoadFromFile(SupDir + 'dayPeriods.xml');
  try
    FDayPeriodRules := ParseDayPeriodRules(Doc);
  finally
    Doc.Free;
  end;
  // group -> its members, sorted by group (the result depends on the order)
  Regions := TStringList.Create;
  Regions.OwnsObjects := True;
  Regions.CaseSensitive := True;
  try
    for Elem in FSup.Root.FindAll('.//territoryContainment/group') do
    begin
      Members := TStringList.Create;
      Members.AddStrings(PySplit(Elem.Attr('contains')));
      Idx := Regions.IndexOf(Elem.Attr('type'));
      if Idx >= 0 then
        Regions.Objects[Idx] := Members // a later group of the same type wins
      else
        Regions.AddObject(Elem.Attr('type'), Members);
    end;
    Regions.CustomSort(@CompareStringListBytes);
    // The containers of each territory.
    FContainment := TStringList.Create;
    FContainment.OwnsObjects := True;
    FContainment.CaseSensitive := True;
    FContainment.Sorted := True;
    for J := 0 to Regions.Count - 1 do
    begin
      Group := Regions[J];
      Members := TStringList(Regions.Objects[J]);
      for K := 0 to Members.Count - 1 do
      begin
        Territory := Members[K];
        Containers := ContainersOf(Territory);
        if Containers = nil then
        begin
          Containers := TStringList.Create;
          Containers.CaseSensitive := True;
          Containers.Sorted := True;
          Containers.Duplicates := dupIgnore;
          FContainment.AddObject(Territory, Containers);
        end;
        GroupContainers := ContainersOf(Group);
        if (GroupContainers <> nil) and (GroupContainers <> Containers) then
          for GIdx := 0 to GroupContainers.Count - 1 do
            Containers.Add(GroupContainers[GIdx]);
        Containers.Add(Group);
      end;
    end;
  finally
    Regions.Free;
  end;
  FLikely := VMap;
  Doc := TXDoc.LoadFromFile(SupDir + 'likelySubtags.xml');
  try
    for Elem in Doc.Root.FindAll('.//likelySubtags/likelySubtag') do
      FLikely.Put(KS(Elem.Attr('from')), VStr(Elem.Attr('to')));
  finally
    Doc.Free;
  end;
  FPlural := ExtractPluralRules(SupDir + 'plurals.xml');
  FOrdinal := ExtractPluralRules(SupDir + 'ordinals.xml');
end;

destructor TLocaleImporter.Destroy;
begin
  FSup.Free;
  FContainment.Free;
  inherited Destroy;
end;

function TLocaleImporter.ContainersOf(const Territory: string): TStringList;
var
  Idx: Integer;
begin
  if FContainment.Find(Territory, Idx) then
    Result := TStringList(FContainment.Objects[Idx])
  else
    Result := nil;
end;

function TLocaleImporter.LocaleNames: TStringArray;
var
  SR: TSearchRec;
  Names: TStringList;
  J, N: Integer;
  F: string;
begin
  Names := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(FSrcDir) + 'main' + PathDelim + '*',
      faAnyFile, SR) = 0 then
    try
      repeat
        F := SR.Name;
        if (F = '.') or (F = '..') then
          Continue;
        if (Length(F) >= 4) and (Copy(F, Length(F) - 3, 4) = '.xml') then
          Names.Add(Copy(F, 1, Length(F) - 4));
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    J := Names.IndexOf('root');
    if J < 0 then
      raise Exception.Create('main/root.xml is missing');
    Names.Delete(J);
    Names.CustomSort(@CompareStringListBytes);
    Result := nil;
    SetLength(Result, Names.Count + 1);
    Result[0] := 'root';
    N := 1;
    for J := 0 to Names.Count - 1 do
    begin
      Result[N] := Names[J];
      Inc(N);
    end;
  finally
    Names.Free;
  end;
end;

function TLocaleImporter.ImportLocale(const Name: string): TValue;
var
  Doc: TXDoc;
  Root, Elem, Calendar: TXElem;
  Language, Territory, LocaleId, WeekTerritory, LikelyStr, T: string;
  HasLanguage: Boolean;
  Regions, WeekRegions: TStringList;
  Data, MeasurementSystems, V: TValue;
  Likely: TStringArray;
  Last: string;
  J: Integer;
  Fits: Boolean;
begin
  Doc := TXDoc.LoadFromFile(IncludeTrailingPathDelimiter(FSrcDir) + 'main' + PathDelim +
    Name + '.xml');
  try
    Root := Doc.Root;
    DropUnconfirmed(Root);
    Language := '';
    HasLanguage := False;
    Elem := Root.Find('.//identity/language');
    if Elem <> nil then
    begin
      Language := Elem.Attr('type');
      HasLanguage := True;
    end;
    Territory := '001';
    Elem := Root.Find('.//identity/territory');
    if Elem <> nil then
      Territory := Elem.Attr('type');
    Regions := ContainersOf(Territory);
    LocaleId := '';
    if HasLanguage and (Language <> '') then
      LocaleId := Language;
    if (Territory <> '001') and (Territory <> '') then
      if LocaleId = '' then
        LocaleId := Territory
      else
        LocaleId := LocaleId + '_' + Territory;

    Data := VMap;
    Result := Data;
    Data.Put(KS('locale_id'), VStr(LocaleId));
    V := FPlural.Get(KS(LocaleId));
    if V <> nil then
      Data.Put(KS('plural_form'), V);
    V := FOrdinal.Get(KS(LocaleId));
    if V <> nil then
      Data.Put(KS('ordinal_form'), V);
    V := FDayPeriodRules.Get(KS(LocaleId));
    if V <> nil then
      Data.Put(KS('day_period_rules'), V);

    ParseLocaleDisplayNames(Data, Root, Pos('_', LocaleId) = 0);
    ParseListPatterns(Data, Root);
    // The week of a locale without a region is its likely region's (en:
    // US, Sunday), as CLDR specifies and ICU does.
    WeekTerritory := Territory;
    WeekRegions := Regions;
    if (Territory = '001') and (Name <> 'root') then
    begin
      // by the full name first: zh_Hant is TW, zh is CN
      V := FLikely.Get(KS(Name));
      if V = nil then
        V := FLikely.Get(KS(LocaleId));
      if V <> nil then
        LikelyStr := V.S
      else
        LikelyStr := '';
      Likely := PySplitSep(LikelyStr, '_');
      if Length(Likely) >= 2 then
      begin
        Last := Likely[High(Likely)];
        Fits := False;
        if Length(Last) = 2 then
          Fits := (Last[1] in ['A'..'Z']) and (Last[2] in ['A'..'Z'])
        else if Length(Last) = 3 then
        begin
          Fits := True;
          for J := 1 to 3 do
            if not (Last[J] in ['0'..'9']) then
              Fits := False;
        end;
        if Fits then
        begin
          WeekTerritory := Last;
          WeekRegions := ContainersOf(WeekTerritory);
        end;
      end;
    end;
    ParseDates(Data, Root, FSup, WeekRegions, WeekTerritory);
    for Calendar in Root.FindAll('.//calendars/calendar') do
    begin
      if Calendar.Attr('type') <> 'gregorian' then
        Continue;
      ParseCalendarContext(Data, Calendar, 'months', 'month', @IntKey);
      ParseCalendarContext(Data, Calendar, 'days', 'day', @WeekdayKey);
      ParseCalendarContext(Data, Calendar, 'quarters', 'quarter', @IntKey);
      ParseCalendarEras(Data, Calendar);
      ParseCalendarPeriods(Data, Calendar);
      ParseCalendarFormats(Data, Calendar, 'dateFormats', 'dateFormatLength',
        'date_formats', 'dateFormat/pattern');
      ParseCalendarFormats(Data, Calendar, 'timeFormats', 'timeFormatLength',
        'time_formats', 'timeFormat/pattern');
      ParseCalendarDatetimeSkeletons(Data, Calendar);
      ParseIntervalFormats(Data, Calendar);
    end;
    ParseNumberSymbols(Data, Root);
    ParseNumberingSystems(Data, Root);
    ParseDecimalFormats(Data, Root);
    ParseSimpleNumberFormats(Data, Root, 'scientificFormats', './scientificFormatLength',
      'scientific_formats', 'scientificFormat/pattern');
    ParseSimpleNumberFormats(Data, Root, 'percentFormats', './/percentFormatLength',
      'percent_formats', 'percentFormat/pattern');
    ParseCurrencyFormats(Data, Root);
    ParseNumberExtras(Data, Root);
    ParseDateExtras(Data, Root);
    ParseCurrencyUnitPatterns(Data, Root);
    ParseCurrencyNames(Data, Root);
    ParseUnitPatterns(Data, Root);
    ParseDateFields(Data, Root);
    for Elem in Root.FindAll('.//layout/orientation/characterOrder') do
      Data.Put(KS('character_order'), VText(Elem));
    MeasurementSystems := Data.SetDefaultMap(KS('measurement_systems'));
    for Elem in Root.FindAll('.//measurementSystemNames/measurementSystemName') do
    begin
      T := Elem.Attr('type');
      if not ShouldSkip(Elem, KS(T), MeasurementSystems) then
        ImportTypeText(MeasurementSystems, Elem, KS(T));
    end;
  finally
    Doc.Free;
  end;
end;

end.
