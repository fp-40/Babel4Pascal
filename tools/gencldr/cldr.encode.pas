{ cldr.encode - the imported data (cldr.values) as the bytes that
  src/babel.localedata.pas decodes.

  Layout of one blob (all counts and indexes are unsigned LEB128 varints):

    'B4PC'           magic
    1                format version (one byte)
    nstrings         then nstrings x (byte length, UTF-8 bytes): the string
                     table; strings are stored once and referenced by index,
                     the most frequent first (equal counts in code point
                     order)
    value            the top-level value (a map)

  A value starts with a tag byte:

    0 None   1 False   2 True
    3 int    zigzag varint
    4 float  8 bytes, IEEE 754 binary64, little-endian
    5 str    index into the string table
    6 list   count, then count values
    7 map    count, then count x (key value, value), in insertion order
             (keys are None, int or str values)
    8 alias  count, then count string indexes: the path of keys }
unit cldr.encode;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, cldr.values, cldr.pystr;

function Encode(V: TValue): TBytes;

implementation

const
  T_NONE = 0; T_FALSE = 1; T_TRUE = 2; T_INT = 3; T_FLOAT = 4; T_STR = 5;
  T_LIST = 6; T_MAP = 7; T_ALIAS = 8;

type
  { The strings of a value with their counts, then their indexes. }
  TStringTable = class
  private
    FTable: array of Integer; // index + 1 into Strs, 0 = empty
    function Slot(const S: string): Cardinal;
    procedure Grow;
  public
    Strs: array of string;
    Counts: array of Integer;
    Indexes: array of Integer;
    N: Integer;
    constructor Create;
    procedure Add(const S: string);
    function IndexOf(const S: string): Integer; // the table index
    procedure Collect(V: TValue);
    procedure Sort(out Order: TStringArray);
  end;

function HashOf(const S: string): Cardinal;
var
  J: Integer;
begin
  Result := 2166136261;
  for J := 1 to Length(S) do
    Result := (Result xor Ord(S[J])) * 16777619;
end;

constructor TStringTable.Create;
begin
  SetLength(FTable, 1024);
end;

function TStringTable.Slot(const S: string): Cardinal;
var
  Mask: Cardinal;
begin
  Mask := Cardinal(Length(FTable) - 1);
  Result := HashOf(S) and Mask;
  while (FTable[Result] <> 0) and (Strs[FTable[Result] - 1] <> S) do
    Result := (Result + 1) and Mask;
end;

procedure TStringTable.Grow;
var
  J: Integer;
  Mask, H: Cardinal;
begin
  FTable := nil;
  J := 1024; // a power of two

  while J < (N + 1) * 4 do
    J := J * 2;
  SetLength(FTable, J);
  Mask := Cardinal(J - 1);
  for J := 0 to N - 1 do
  begin
    H := HashOf(Strs[J]) and Mask;
    while FTable[H] <> 0 do
      H := (H + 1) and Mask;
    FTable[H] := J + 1;
  end;
end;

procedure TStringTable.Add(const S: string);
var
  H: Cardinal;
begin
  H := Slot(S);
  if FTable[H] <> 0 then
  begin
    Inc(Counts[FTable[H] - 1]);
    Exit;
  end;
  if N = Length(Strs) then
  begin
    SetLength(Strs, N * 2 + 64);
    SetLength(Counts, N * 2 + 64);
  end;
  Strs[N] := S;
  Counts[N] := 1;
  Inc(N);
  FTable[H] := N;
  if N * 2 > Length(FTable) then
    Grow;
end;

function TStringTable.IndexOf(const S: string): Integer;
var
  H: Cardinal;
begin
  H := Slot(S);
  if FTable[H] = 0 then
    raise Exception.Create('string not in the table: ' + S);
  Result := Indexes[FTable[H] - 1];
end;

procedure TStringTable.Collect(V: TValue);
var
  J: Integer;
begin
  case V.Kind of
    vkStr: Add(V.S);
    vkList:
      for J := 0 to V.Count - 1 do
        Collect(V.Items[J]);
    vkMap:
      for J := 0 to V.Count - 1 do
      begin
        if V.Keys[J].Kind = kkStr then
          Add(V.Keys[J].S);
        Collect(V.Items[J]);
      end;
    vkAlias:
      for J := 0 to High(V.Path) do
        Add(V.Path[J]);
  end;
end;

procedure TStringTable.Sort(out Order: TStringArray);
var
  Idx: array of Integer;

  function Less(A, B: Integer): Boolean;
  begin
    if Counts[A] <> Counts[B] then
      Result := Counts[A] > Counts[B]
    else
      Result := CompareBytes(Strs[A], Strs[B]) < 0;
  end;

  procedure QSort(L, R: Integer);
  var
    I, J, Pivot, T: Integer;
  begin
    while L < R do
    begin
      I := L;
      J := R;
      Pivot := Idx[(L + R) shr 1];
      repeat
        while Less(Idx[I], Pivot) do
          Inc(I);
        while Less(Pivot, Idx[J]) do
          Dec(J);
        if I <= J then
        begin
          T := Idx[I];
          Idx[I] := Idx[J];
          Idx[J] := T;
          Inc(I);
          Dec(J);
        end;
      until I > J;
      if J - L < R - I then
      begin
        QSort(L, J);
        L := I;
      end
      else
      begin
        QSort(I, R);
        R := J;
      end;
    end;
  end;

var
  J: Integer;
begin
  SetLength(Idx, N);
  for J := 0 to N - 1 do
    Idx[J] := J;
  if N > 1 then
    QSort(0, N - 1);
  SetLength(Indexes, N);
  SetLength(Order, N);
  for J := 0 to N - 1 do
  begin
    Indexes[Idx[J]] := J;
    Order[J] := Strs[Idx[J]];
  end;
end;

type
  TOut = record
    Buf: TBytes;
    Len: Integer;
  end;

procedure PutByte(var O: TOut; B: Byte); inline;
begin
  if O.Len = Length(O.Buf) then
    SetLength(O.Buf, O.Len * 2 + 4096);
  O.Buf[O.Len] := B;
  Inc(O.Len);
end;

procedure PutBytes(var O: TOut; const P; N: Integer);
begin
  if N = 0 then
    Exit;
  while O.Len + N > Length(O.Buf) do
    SetLength(O.Buf, Length(O.Buf) * 2 + 4096);
  Move(P, O.Buf[O.Len], N);
  Inc(O.Len, N);
end;

procedure PutVarint(var O: TOut; N: QWord);
var
  B: Byte;
begin
  repeat
    B := N and $7F;
    N := N shr 7;
    if N <> 0 then
      PutByte(O, B or $80)
    else
      PutByte(O, B);
  until N = 0;
end;

function Encode(V: TValue): TBytes;
var
  Table: TStringTable;
  Order: TStringArray;
  O: TOut;
  J: Integer;

  procedure PutStr(const S: string);
  begin
    PutByte(O, T_STR);
    PutVarint(O, Table.IndexOf(S));
  end;

  procedure Put(X: TValue);
  var
    K: Integer;
    D: Double;
  begin
    case X.Kind of
      vkNone: PutByte(O, T_NONE);
      vkFalse: PutByte(O, T_FALSE);
      vkTrue: PutByte(O, T_TRUE);
      vkInt:
        begin
          PutByte(O, T_INT);
          if X.I >= 0 then
            PutVarint(O, QWord(X.I) shl 1)
          else
            PutVarint(O, (QWord(-X.I) shl 1) - 1);
        end;
      vkFloat:
        begin
          PutByte(O, T_FLOAT);
          D := X.F;
          {$IFDEF ENDIAN_BIG}
          raise Exception.Create('big-endian hosts are not supported');
          {$ENDIF}
          PutBytes(O, D, 8);
        end;
      vkStr: PutStr(X.S);
      vkList:
        begin
          PutByte(O, T_LIST);
          PutVarint(O, X.Count);
          for K := 0 to X.Count - 1 do
            Put(X.Items[K]);
        end;
      vkMap:
        begin
          PutByte(O, T_MAP);
          PutVarint(O, X.Count);
          for K := 0 to X.Count - 1 do
          begin
            case X.Keys[K].Kind of
              kkNone: PutByte(O, T_NONE);
              kkInt:
                begin
                  PutByte(O, T_INT);
                  if X.Keys[K].I >= 0 then
                    PutVarint(O, QWord(X.Keys[K].I) shl 1)
                  else
                    PutVarint(O, (QWord(-X.Keys[K].I) shl 1) - 1);
                end;
              kkStr: PutStr(X.Keys[K].S);
            end;
            Put(X.Items[K]);
          end;
        end;
      vkAlias:
        begin
          PutByte(O, T_ALIAS);
          PutVarint(O, Length(X.Path));
          for K := 0 to High(X.Path) do
            PutVarint(O, Table.IndexOf(X.Path[K]));
        end;
    end;
  end;

begin
  Table := TStringTable.Create;
  try
    Table.Collect(V);
    Table.Sort(Order);
    O.Buf := nil;
    O.Len := 0;
    PutBytes(O, PChar('B4PC')^, 4);
    PutByte(O, 1);
    PutVarint(O, Length(Order));
    for J := 0 to High(Order) do
    begin
      PutVarint(O, Length(Order[J]));
      if Length(Order[J]) > 0 then
        PutBytes(O, Order[J][1], Length(Order[J]));
    end;
    Put(V);
    SetLength(O.Buf, O.Len);
    Result := O.Buf;
  finally
    Table.Free;
  end;
end;

end.
