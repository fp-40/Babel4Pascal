{ test_core - checks babel.core, babel.plural and babel.decimal against the
  vectors of tests/python/gen_core_vectors.py (the results of Python Babel
  2.18.0 for the same inputs).

  Usage: test_core VECTORS.jsonl
  Prints each failing case (up to 40) and a count per operation; exit
  status 1 when any case fails. }
program test_core;

{$mode objfpc}{$H+}

uses
  cwstring,   { fpjson converts strings through UnicodeString }
  SysUtils, Classes, fpjson, jsonparser,
  babel.errors, babel.decimal, babel.plural, babel.localedata, babel.core,
  babel.cldr_all;

var
  Failures, Total: Integer;
  OpCounts, OpFails: TStringList;
  PluralInts: array of Int64;
  PluralFloats: array of Double;
  PluralDecs: array of string;

procedure Fail(const Op, Detail: string);
begin
  Inc(Failures);
  OpFails.Values[Op] := IntToStr(StrToIntDef(OpFails.Values[Op], 0) + 1);
  if Failures <= 40 then
    WriteLn('FAIL ', Op, ': ', Detail);
end;

function ErrorName(E: Exception): string;
begin
  if E is EUnknownLocaleError then Result := 'UnknownLocaleError'
  else if E is EPluralRuleError then Result := 'RuleError'
  else if E is EBabelValueError then Result := 'ValueError'
  else if E is EBabelTypeError then Result := 'TypeError'
  else if E is EBabelKeyError then Result := 'KeyError'
  else if E is EBabelOverflowError then Result := 'OverflowError'
  else Result := E.ClassName + ': ' + E.Message;
end;

function DoubleOfHex(const S: string): Double;
var
  Q: QWord;
begin
  Q := StrToQWord('$' + S);
  Move(Q, Result, 8);
end;

function StrArray(const A: array of string): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in A do
    Result.Add(S);
end;

{ ---- one case per operation; each returns the result as JSON ---- }

function PartsJSON(const P: TLocaleParts): TJSONData;
begin
  Result := StrArray([P.Language, P.Territory, P.Script, P.Variant, P.Modifier]);
end;

function ArgsParts(A: TJSONArray): TLocaleParts;
begin
  Result.Language := A.Strings[0];
  Result.Territory := A.Strings[1];
  Result.Script := A.Strings[2];
  Result.Variant := A.Strings[3];
  Result.Modifier := A.Strings[4];
end;

function StrList(A: TJSONArray): TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
    Result[I] := A.Strings[I];
end;

function PluralJSON(const R: TPluralRule): TJSONData;
var
  O: TJSONObject;
  Rules, Pair, Ints, Floats, Decs: TJSONArray;
  It: TPluralRuleItem;
  I: Integer;
begin
  O := TJSONObject.Create;
  O.Add('tags', StrArray(R.Tags));
  Rules := TJSONArray.Create;
  for It in R.Rules do
  begin
    Pair := StrArray([It.Tag, It.Expr]);
    Rules.Add(Pair);
  end;
  O.Add('rules', Rules);
  O.Add('gettext', R.ToGettext);
  O.Add('javascript', R.ToJavaScript);
  Ints := TJSONArray.Create;
  for I := 0 to High(PluralInts) do
    Ints.Add(R.Evaluate(PluralInts[I]));
  O.Add('ints', Ints);
  Floats := TJSONArray.Create;
  for I := 0 to High(PluralFloats) do
    Floats.Add(R.Evaluate(PluralFloats[I]));
  O.Add('floats', Floats);
  Decs := TJSONArray.Create;
  for I := 0 to High(PluralDecs) do
    Decs.Add(R.Evaluate(TDecimal.Parse(PluralDecs[I])));
  O.Add('decimals', Decs);
  Result := O;
end;

function OperandsJSON(const P: TPluralOperands): TJSONData;
var
  A: TJSONArray;
begin
  A := TJSONArray.Create;
  A.Add(P.N.ToString);
  A.Add(P.I.ToString);
  A.Add(P.V);
  A.Add(P.W);
  A.Add(P.F.ToString);
  A.Add(P.T.ToString);
  A.Add(P.C);
  A.Add(P.E);
  Result := A;
end;

function LocaleJSON(const Name: string): TJSONData;
var
  L, X: TLocale;
  O, Per, D1, D2, D3: TJSONObject;
  P: TCLDRValue;
  I: Integer;
  InNames: array of string = ('en', 'es', 'fr', 'ja', 'ar', 'zh_Hant', 'ru', 'de_CH');
  N: string;
begin
  if Name = 'root' then
    L := TLocale.Create('root')
  else
    L := TLocale.Parse(Name);
  O := TJSONObject.Create;
  O.Add('str', L.ToString);
  O.Add('repr', L.Repr);
  O.Add('display_name', L.DisplayName);
  O.Add('language_name', L.LanguageName);
  O.Add('territory_name', L.TerritoryName);
  O.Add('script_name', L.ScriptName);
  O.Add('english_name', L.EnglishName);
  O.Add('character_order', L.CharacterOrder);
  O.Add('text_direction', L.TextDirection);
  O.Add('first_week_day', L.FirstWeekDay);
  O.Add('weekend_start', L.WeekendStart);
  O.Add('weekend_end', L.WeekendEnd);
  O.Add('min_week_days', L.MinWeekDays);
  O.Add('default_numbering_system', L.DefaultNumberingSystem);
  Per := TJSONObject.Create;
  P := L.Periods;
  for I := 0 to P.Count - 1 do
    Per.Add(P.Keys(I).AsString, P.Items(I).AsString);
  O.Add('periods', Per);
  D1 := TJSONObject.Create;
  D2 := TJSONObject.Create;
  D3 := TJSONObject.Create;
  for N in InNames do
    if LocaleDataExists(N) then
    begin
      X := TLocale.Parse(N);
      D1.Add(N, L.GetDisplayName(X));
      D2.Add(N, L.GetLanguageName(X));
      D3.Add(N, L.GetTerritoryName(X));
    end;
  O.Add('display_in', D1);
  O.Add('language_in', D2);
  O.Add('territory_in', D3);
  Result := O;
end;

function DecimalJSON(const S: string): TJSONData;
const
  Kinds: array[TDecimalKind] of string = ('finite', 'inf', 'nan', 'snan');
var
  D: TDecimal;
  A: TJSONArray;
begin
  D := TDecimal.Parse(S);
  A := TJSONArray.Create;
  A.Add(D.ToString);
  A.Add(Kinds[D.Kind]);
  A.Add(Ord(D.Negative));
  A.Add(D.Digits);
  A.Add(D.Exponent);
  Result := A;
end;

function RuleFromArgs(A: TJSONArray): TPluralRule;
var
  Items: array of TPluralRuleItem;
  I: Integer;
begin
  Items := nil;
  SetLength(Items, A.Count);
  for I := 0 to A.Count - 1 do
  begin
    Items[I].Tag := TJSONArray(A.Items[I]).Strings[0];
    Items[I].Expr := TJSONArray(A.Items[I]).Strings[1];
  end;
  Result := TPluralRule.Create(Items);
end;

function NegAliases(Use: Boolean): TLocaleAliases;
begin
  if Use then
    Result := LocaleAliases
  else
    Result := nil;
end;

function Run(const Op: string; Args: TJSONArray): TJSONData;
var
  L: TLocale;
begin
  if Op = 'parse_locale' then
    Result := PartsJSON(ParseLocale(Args.Strings[0], Args.Strings[1]))
  else if Op = 'locale_parse' then
    Result := TJSONString.Create(TLocale.Parse(Args.Strings[0], Args.Strings[1], Args.Booleans[2]).ToString)
  else if Op = 'get_locale_identifier' then
    Result := TJSONString.Create(GetLocaleIdentifier(ArgsParts(Args.Arrays[0]), Args.Strings[1]))
  else if Op = 'negotiate_locale' then
    Result := TJSONString.Create(NegotiateLocale(StrList(Args.Arrays[0]), StrList(Args.Arrays[1]),
      NegAliases(Args.Booleans[3]), Args.Strings[2]))
  else if Op = 'locale_negotiate' then
  begin
    if TLocale.Negotiate(StrList(Args.Arrays[0]), StrList(Args.Arrays[1]),
      NegAliases(Args.Booleans[3]), L, Args.Strings[2]) then
      Result := TJSONString.Create(L.ToString)
    else
      Result := TJSONString.Create('');
  end
  else if Op = 'locale' then
    Result := LocaleJSON(Args.Strings[0])
  else if Op = 'locale_plural' then
  begin
    if Args.Strings[0] = 'root' then L := TLocale.Create('root') else L := TLocale.Parse(Args.Strings[0]);
    Result := PluralJSON(L.PluralForm);
  end
  else if Op = 'locale_ordinal' then
  begin
    if Args.Strings[0] = 'root' then L := TLocale.Create('root') else L := TLocale.Parse(Args.Strings[0]);
    Result := PluralJSON(L.OrdinalForm);
  end
  else if Op = 'plural_rule' then
    Result := PluralJSON(RuleFromArgs(Args.Arrays[0]))
  else if Op = 'operands_decimal' then
    Result := OperandsJSON(ExtractOperands(TDecimal.Parse(Args.Strings[0])))
  else if Op = 'operands_float' then
    Result := OperandsJSON(ExtractOperands(DoubleOfHex(Args.Strings[0])))
  else if Op = 'operands_int' then
    Result := OperandsJSON(ExtractOperands(Args.Int64s[0]))
  else if Op = 'decimal' then
    Result := DecimalJSON(Args.Strings[0])
  else
    raise Exception.Create('unknown op ' + Op);
end;

procedure CheckFloatRepr(Cases: TJSONArray);
var
  I: Integer;
  C: TJSONArray;
  X: Double;
  Got: string;
begin
  for I := 0 to Cases.Count - 1 do
  begin
    C := Cases.Arrays[I];
    X := DoubleOfHex(C.Strings[0]);
    Inc(Total);
    Got := PyFloatRepr(X);
    if Got <> C.Strings[1] then
      Fail('float_repr', Format('%s: got %s want %s', [C.Strings[0], Got, C.Strings[1]]));
    if C.Strings[2] <> '' then
    begin
      Inc(Total);
      Got := TDecimal.FromDouble(X).ToString;
      if Got <> C.Strings[2] then
        Fail('float_decimal', Format('%s: got %s want %s', [C.Strings[0], Got, C.Strings[2]]));
    end;
  end;
end;

procedure LoadPluralInputs(E: TJSONObject);
var
  I: Integer;
  A: TJSONArray;
begin
  A := E.Arrays['ints'];
  SetLength(PluralInts, A.Count);
  for I := 0 to A.Count - 1 do
    PluralInts[I] := A.Int64s[I];
  A := E.Arrays['floats'];
  SetLength(PluralFloats, A.Count);
  for I := 0 to A.Count - 1 do
    PluralFloats[I] := DoubleOfHex(A.Strings[I]);
  A := E.Arrays['decimals'];
  SetLength(PluralDecs, A.Count);
  for I := 0 to A.Count - 1 do
    PluralDecs[I] := A.Strings[I];
end;

procedure RunCase(Line: TJSONObject);
var
  Op, Want, GotText: string;
  Got: TJSONData;
begin
  Op := Line.Strings['op'];
  if Op = 'plural_inputs' then
  begin
    LoadPluralInputs(Line.Objects['expect']);
    Exit;
  end;
  if Op = 'float_repr' then
  begin
    CheckFloatRepr(Line.Arrays['expect']);
    Exit;
  end;
  Inc(Total);
  OpCounts.Values[Op] := IntToStr(StrToIntDef(OpCounts.Values[Op], 0) + 1);
  if Line.IndexOfName('error') >= 0 then
    Want := 'error ' + Line.Strings['error']
  else
    Want := Line.Elements['expect'].AsJSON;
  try
    Got := Run(Op, Line.Arrays['args']);
    try
      GotText := Got.AsJSON;
    finally
      Got.Free;
    end;
  except
    on E: Exception do
      GotText := 'error ' + ErrorName(E);
  end;
  if GotText <> Want then
    Fail(Op, Line.Arrays['args'].AsJSON + LineEnding + '    got  ' + Copy(GotText, 1, 400) +
      LineEnding + '    want ' + Copy(Want, 1, 400));
end;

var
  F: TextFile;
  S: string;
  J: TJSONData;
  I: Integer;
begin
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_core VECTORS.jsonl');
    Halt(2);
  end;
  { The library's strings are UTF-8; make fpjson's conversions UTF-8 too. }
  DefaultSystemCodePage := CP_UTF8;
  SetMultiByteConversionCodePage(CP_UTF8);
  OpCounts := TStringList.Create;
  OpFails := TStringList.Create;
  AssignFile(F, ParamStr(1));
  Reset(F);
  while not EOF(F) do
  begin
    ReadLn(F, S);
    if S = '' then
      Continue;
    J := GetJSON(S);
    try
      RunCase(TJSONObject(J));
    finally
      J.Free;
    end;
  end;
  CloseFile(F);
  for I := 0 to OpFails.Count - 1 do
    WriteLn('  ', OpFails.Names[I], ': ', OpFails.ValueFromIndex[I], ' failed');
  WriteLn(Total, ' cases, ', Failures, ' failed');
  if Failures > 0 then
    Halt(1);
end.
