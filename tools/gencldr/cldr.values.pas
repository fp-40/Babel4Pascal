{ cldr.values - the imported data: None, booleans, integers, floats,
  strings, lists, maps and aliases (the values cldr.encode writes).

  A map keeps its keys in insertion order; assigning to a key it has
  keeps the key's position. Keys are None, integers or strings.

  Every value is registered in one list (the arena) when created and
  freed by ArenaRelease: values created after ArenaMark go together, so
  the data of a locale is freed after it is encoded while values created
  before (shared by every locale) stay. }
unit cldr.values;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TValueKind = (vkNone, vkFalse, vkTrue, vkInt, vkFloat, vkStr, vkList, vkMap,
    vkAlias);
  TKeyKind = (kkNone, kkInt, kkStr);

  TKey = record
    Kind: TKeyKind;
    I: Int64;
    S: string;
  end;

  TValue = class;
  TValueArray = array of TValue;

  TValue = class
  private
    FHashKeys: array of string;   // the key strings (KeyString) of Keys
    FTable: array of Integer;     // open addressing: index + 1, 0 = empty
    function IndexOfKey(const K: TKey): Integer;
    procedure Rehash;
    procedure CheckKind(K: TValueKind);
  public
    Kind: TValueKind;
    I: Int64;
    F: Double;
    S: string;
    { list items, or map values (in key order) }
    Items: TValueArray;
    Count: Integer;
    { map keys }
    Keys: array of TKey;
    { alias: the path of keys }
    Path: array of string;
    constructor Create(AKind: TValueKind);
    { list }
    procedure Append(V: TValue);
    { map }
    function Has(const K: TKey): Boolean;
    function Get(const K: TKey): TValue; // nil when absent
    procedure Put(const K: TKey; V: TValue);
    { setdefault(K, new map) and setdefault(K, new list): the value at K,
      which is created when absent. }
    function SetDefaultMap(const K: TKey): TValue;
    function SetDefaultList(const K: TKey): TValue;
    { setdefault(K, V) }
    function SetDefault(const K: TKey; V: TValue): TValue;
  end;

function KS(const S: string): TKey;
function KI(I: Int64): TKey;
function KNone: TKey;
{ A key from an optional attribute: None when absent. }
function KOpt(Present: Boolean; const S: string): TKey;

function VNone: TValue;
function VBool(B: Boolean): TValue;
function VInt(I: Int64): TValue;
function VFloat(F: Double): TValue;
function VStr(const S: string): TValue;
{ A string when Present, else None. }
function VOpt(Present: Boolean; const S: string): TValue;
function VList: TValue;
function VMap: TValue;
function VAlias(const Path: array of string): TValue;

function ArenaMark: Integer;
procedure ArenaRelease(Mark: Integer);

implementation

var
  Arena: TFPList;

function ArenaMark: Integer;
begin
  Result := Arena.Count;
end;

procedure ArenaRelease(Mark: Integer);
var
  I: Integer;
begin
  for I := Arena.Count - 1 downto Mark do
    TObject(Arena[I]).Free;
  Arena.Count := Mark;
end;

function KS(const S: string): TKey;
begin
  Result.Kind := kkStr;
  Result.I := 0;
  Result.S := S;
end;

function KI(I: Int64): TKey;
begin
  Result.Kind := kkInt;
  Result.I := I;
  Result.S := '';
end;

function KNone: TKey;
begin
  Result.Kind := kkNone;
  Result.I := 0;
  Result.S := '';
end;

function KOpt(Present: Boolean; const S: string): TKey;
begin
  if Present then
    Result := KS(S)
  else
    Result := KNone;
end;

function KeyString(const K: TKey): string;
begin
  case K.Kind of
    kkNone: Result := 'N';
    kkInt: Result := 'I' + IntToStr(K.I);
  else
    Result := 'S' + K.S;
  end;
end;

function HashOf(const S: string): Cardinal;
var
  J: Integer;
begin
  Result := 2166136261;
  for J := 1 to Length(S) do
    Result := (Result xor Ord(S[J])) * 16777619;
end;

function VNone: TValue;
begin
  Result := TValue.Create(vkNone);
end;

function VBool(B: Boolean): TValue;
begin
  if B then
    Result := TValue.Create(vkTrue)
  else
    Result := TValue.Create(vkFalse);
end;

function VInt(I: Int64): TValue;
begin
  Result := TValue.Create(vkInt);
  Result.I := I;
end;

function VFloat(F: Double): TValue;
begin
  Result := TValue.Create(vkFloat);
  Result.F := F;
end;

function VStr(const S: string): TValue;
begin
  Result := TValue.Create(vkStr);
  Result.S := S;
end;

function VOpt(Present: Boolean; const S: string): TValue;
begin
  if Present then
    Result := VStr(S)
  else
    Result := VNone;
end;

function VList: TValue;
begin
  Result := TValue.Create(vkList);
end;

function VMap: TValue;
begin
  Result := TValue.Create(vkMap);
end;

function VAlias(const Path: array of string): TValue;
var
  J: Integer;
begin
  Result := TValue.Create(vkAlias);
  SetLength(Result.Path, Length(Path));
  for J := 0 to High(Path) do
    Result.Path[J] := Path[J];
end;

{ TValue }

constructor TValue.Create(AKind: TValueKind);
begin
  inherited Create;
  Kind := AKind;
  Arena.Add(Self);
end;

procedure TValue.CheckKind(K: TValueKind);
const
  Names: array[TValueKind] of string = ('None', 'bool', 'bool', 'int',
    'float', 'str', 'list', 'dict', 'Alias');
begin
  if Kind <> K then
    raise Exception.CreateFmt('a %s used as a %s', [Names[Kind], Names[K]]);
end;

procedure TValue.Append(V: TValue);
begin
  CheckKind(vkList);
  if Count = Length(Items) then
    SetLength(Items, Count * 2 + 4);
  Items[Count] := V;
  Inc(Count);
end;

procedure TValue.Rehash;
var
  Size, J: Integer;
  H: Cardinal;
begin
  Size := 16;
  while Size < Count * 2 + 2 do
    Size := Size * 2;
  FTable := nil;
  SetLength(FTable, Size);
  for J := 0 to Count - 1 do
  begin
    H := HashOf(FHashKeys[J]) and Cardinal(Size - 1);
    while FTable[H] <> 0 do
      H := (H + 1) and Cardinal(Size - 1);
    FTable[H] := J + 1;
  end;
end;

function TValue.IndexOfKey(const K: TKey): Integer;
var
  KStr: string;
  H: Cardinal;
  J: Integer;
begin
  CheckKind(vkMap);
  if Count < 8 then
  begin
    for J := 0 to Count - 1 do
      if (Keys[J].Kind = K.Kind) and (Keys[J].I = K.I) and (Keys[J].S = K.S) then
        Exit(J);
    Exit(-1);
  end;
  if Length(FTable) < Count * 2 then
    Rehash;
  KStr := KeyString(K);
  H := HashOf(KStr) and Cardinal(Length(FTable) - 1);
  while FTable[H] <> 0 do
  begin
    if FHashKeys[FTable[H] - 1] = KStr then
      Exit(FTable[H] - 1);
    H := (H + 1) and Cardinal(Length(FTable) - 1);
  end;
  Result := -1;
end;

function TValue.Has(const K: TKey): Boolean;
begin
  Result := IndexOfKey(K) >= 0;
end;

function TValue.Get(const K: TKey): TValue;
var
  J: Integer;
begin
  J := IndexOfKey(K);
  if J >= 0 then
    Result := Items[J]
  else
    Result := nil;
end;

procedure TValue.Put(const K: TKey; V: TValue);
var
  J: Integer;
  H: Cardinal;
begin
  J := IndexOfKey(K);
  if J >= 0 then
  begin
    Items[J] := V;
    Exit;
  end;
  if Count = Length(Items) then
  begin
    SetLength(Items, Count * 2 + 4);
    SetLength(Keys, Count * 2 + 4);
    SetLength(FHashKeys, Count * 2 + 4);
  end;
  Keys[Count] := K;
  Items[Count] := V;
  FHashKeys[Count] := KeyString(K);
  Inc(Count);
  if Length(FTable) > 0 then
    if Length(FTable) < Count * 2 then
      Rehash
    else
    begin
      H := HashOf(FHashKeys[Count - 1]) and Cardinal(Length(FTable) - 1);
      while FTable[H] <> 0 do
        H := (H + 1) and Cardinal(Length(FTable) - 1);
      FTable[H] := Count;
    end;
end;

function TValue.SetDefault(const K: TKey; V: TValue): TValue;
begin
  Result := Get(K);
  if Result = nil then
  begin
    Put(K, V);
    Result := V;
  end;
end;

function TValue.SetDefaultMap(const K: TKey): TValue;
begin
  Result := Get(K);
  if Result = nil then
  begin
    Result := VMap;
    Put(K, Result);
  end;
end;

function TValue.SetDefaultList(const K: TKey): TValue;
begin
  Result := Get(K);
  if Result = nil then
  begin
    Result := VList;
    Put(K, Result);
  end;
end;

initialization
  Arena := TFPList.Create;

finalization
  ArenaRelease(0);
  Arena.Free;

end.
