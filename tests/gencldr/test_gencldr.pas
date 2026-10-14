{ test_gencldr - checks the generator's encoding (tools/gencldr/cldr.encode)
  against the library's decoding (src/babel.localedata), and the
  importer's split of interval patterns.

  - a value with every kind (None key, integers up to 2^40 and High(Int64)
    and negative ones, nested map, float, booleans, None, alias, UTF-8
    string, empty string, empty list) and the key order of a map, encoded
    and decoded;
  - SplitIntervalPattern on examples;
  - with COMMON_DIR (the common/ directory of the CLDR release, as
    `gencldr fetch` prints it): the global data and the own data of every
    locale of the release, imported, encoded and decoded.

  The library decodes a blob registered with RegisterLocaleData and read
  back with LoadLocaleData(Name, False) (the locale's own data, aliases
  kept).

  Usage: test_gencldr [COMMON_DIR]   (exit status 1 when a check fails) }
program test_gencldr;

{$mode objfpc}{$H+}

uses
  SysUtils, cldr.values, cldr.encode, cldr.importer, babel.localedata;

var
  Failed: Integer = 0;
  Total: Integer = 0;
  Blobs: array of TBytes; // registered blobs stay valid for the whole run

procedure Expect(const What: string; OK: Boolean; const Detail: string = '');
begin
  Inc(Total);
  if not OK then
  begin
    Inc(Failed);
    if Failed <= 20 then
      WriteLn('FAIL ', What, ' ', Detail);
  end;
end;

{ The value encoded, then decoded by the library. }
function RoundTrip(const Name: string; V: TValue): TCLDRValue;
begin
  SetLength(Blobs, Length(Blobs) + 1);
  Blobs[High(Blobs)] := Encode(V);
  RegisterLocaleData('test:' + Name, '', @Blobs[High(Blobs)][0], Length(Blobs[High(Blobs)]));
  Result := LoadLocaleData('test:' + Name, False);
end;

function KeyText(const K: TKey): string;
begin
  case K.Kind of
    kkNone: Result := 'None';
    kkInt: Result := IntToStr(K.I);
  else
    Result := '''' + K.S + '''';
  end;
end;

{ '' when B (decoded) equals A (imported); else where they differ. }
function Difference(A: TValue; B: TCLDRValue; const Path: string): string;
var
  J: Integer;
  K: TCLDRValue;
  P: TStringArray;
  KindOK: Boolean;
  F: Double;
begin
  case A.Kind of
    vkNone: KindOK := B.Kind = ckNone;
    vkFalse, vkTrue: KindOK := B.Kind = ckBool;
    vkInt: KindOK := B.Kind = ckInt;
    vkFloat: KindOK := B.Kind = ckFloat;
    vkStr: KindOK := B.Kind = ckString;
    vkList: KindOK := B.Kind = ckList;
    vkMap: KindOK := B.Kind = ckMap;
    vkAlias: KindOK := B.Kind = ckAlias;
  else
    KindOK := False;
  end;
  if not KindOK then
    Exit(Path + ': kind differs');
  Result := '';
  case A.Kind of
    vkFalse, vkTrue:
      if B.AsBoolean <> (A.Kind = vkTrue) then
        Result := Path + ': boolean differs';
    vkInt:
      if B.AsInteger <> A.I then
        Result := Format('%s: %d, not %d', [Path, B.AsInteger, A.I]);
    vkFloat:
      begin
        F := B.AsFloat;
        if not CompareMem(@A.F, @F, 8) then
          Result := Path + ': float differs';
      end;
    vkStr:
      if B.AsString <> A.S then
        Result := Format('%s: "%s", not "%s"', [Path, B.AsString, A.S]);
    vkList:
      if B.Count <> A.Count then
        Result := Path + ': list length differs'
      else
        for J := 0 to A.Count - 1 do
        begin
          Result := Difference(A.Items[J], B.Items(J), Path + '[' + IntToStr(J) + ']');
          if Result <> '' then
            Exit;
        end;
    vkMap:
      if B.Count <> A.Count then
        Result := Path + ': map size differs'
      else
        for J := 0 to A.Count - 1 do
        begin
          K := B.Keys(J);
          case A.Keys[J].Kind of
            kkNone: KindOK := K.Kind = ckNone;
            kkInt: KindOK := (K.Kind = ckInt) and (K.AsInteger = A.Keys[J].I);
            kkStr: KindOK := (K.Kind = ckString) and (K.AsString = A.Keys[J].S);
          end;
          if not KindOK then
            Exit(Format('%s: key %d is not %s', [Path, J, KeyText(A.Keys[J])]));
          Result := Difference(A.Items[J], B.Items(J), Path + '[' + KeyText(A.Keys[J]) + ']');
          if Result <> '' then
            Exit;
        end;
    vkAlias:
      begin
        P := B.AliasKeys;
        if Length(P) <> Length(A.Path) then
          Exit(Path + ': alias path length differs');
        for J := 0 to High(P) do
          if P[J] <> A.Path[J] then
            Exit(Path + ': alias path differs');
      end;
  end;
end;

procedure ExpectRoundTrip(const Name: string; V: TValue);
var
  D: string;
begin
  D := Difference(V, RoundTrip(Name, V), Name);
  Expect('round trip of ' + Name, D = '', D);
end;

procedure TestValues;
const
  Utf8 = 'ñandú – 日本';
  Ints: array[0..9] of Int64 = (0, 1, -1, 63, -64, 64, Int64(1) shl 40,
    -(Int64(1) shl 40), High(Int64), -High(Int64));
var
  V, L, M: TValue;
  I: Int64;
begin
  Expect('the UTF-8 literal is 18 bytes', Length(Utf8) = 18);
  V := VMap;
  L := VList;
  for I in Ints do
    L.Append(VInt(I));
  V.Put(KNone, L);
  M := VMap;
  M.Put(KI(1), VStr('x'));
  M.Put(KS('b'), VStr('x'));
  V.Put(KS('a'), M);
  V.Put(KS('f'), VFloat(1.5));
  V.Put(KS('t'), VBool(True));
  V.Put(KS('n'), VBool(False));
  V.Put(KS('z'), VNone);
  V.Put(KS('al'), VAlias(['days', 'format']));
  V.Put(KS('u'), VStr(Utf8));
  V.Put(KS('e'), VStr(''));
  V.Put(KS('l'), VList);
  V.Put(KI(-7), VInt(-7));
  ExpectRoundTrip('values', V);

  V := VMap;
  V.Put(KS('b'), VInt(1));
  V.Put(KS('a'), VInt(2));
  V.Put(KI(3), VInt(3));
  V.Put(KNone, VInt(4));
  ExpectRoundTrip('insertion order', V);
end;

procedure ExpectSplit(const Pattern: string; const Want: array of string);
var
  Got: TStringArray;
  J: Integer;
  OK: Boolean;
begin
  Got := SplitIntervalPattern(Pattern);
  OK := Length(Got) = Length(Want);
  if OK then
    for J := 0 to High(Want) do
      OK := OK and (Got[J] = Want[J]);
  Expect('SplitIntervalPattern(' + Pattern + ')', OK,
    '["' + string.Join('", "', Got) + '"]');
end;

procedure TestIntervalSplit;
begin
  ExpectSplit('E d.M. – E d.M.', ['E d.M. – ', 'E d.M.']);
  ExpectSplit('Y ''text'' Y ''more text''', ['Y ''text ''', 'Y ''more text''']);
  ExpectSplit('E, MMM d – E', ['E, MMM d – ', 'E']);
  ExpectSplit('MMM d', ['MMM d']);
  ExpectSplit('y G', ['y G']);
  ExpectSplit('MMM d – d', ['MMM d – ', 'd']);
end;

procedure TestRelease(const SrcDir: string);
var
  Imp: TLocaleImporter;
  Name: string;
  Mark, N: Integer;
begin
  ExpectRoundTrip('global data', ParseGlobal(SrcDir));
  Imp := TLocaleImporter.Create(SrcDir);
  try
    N := 0;
    for Name in Imp.LocaleNames do
    begin
      Mark := ArenaMark;
      ExpectRoundTrip(Name, Imp.ImportLocale(Name));
      ArenaRelease(Mark);
      Inc(N);
    end;
    WriteLn(N, ' locales of the release encoded and decoded');
  finally
    Imp.Free;
  end;
end;

begin
  if ParamCount > 1 then
  begin
    WriteLn('usage: test_gencldr [COMMON_DIR]');
    Halt(2);
  end;
  TestValues;
  TestIntervalSplit;
  if ParamCount = 1 then
    TestRelease(ParamStr(1))
  else
    WriteLn('(no COMMON_DIR: the data of the release not checked)');
  WriteLn(Total, ' checks, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
