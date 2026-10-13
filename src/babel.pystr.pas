{ babel.pystr - the parts of Python's str semantics that Babel's results
  depend on, for UTF-8 strings: code points, str.isspace and str.strip,
  and the Unicode decimal digits that int() and Decimal() accept
  ('١٢٣' is 123).

  The tables are those of Unicode 16.0, the version of the Python (3.14)
  the oracle runs on: 76 runs of ten decimal digits (category Nd, each run
  0..9 in order) and the 29 characters for which str.isspace() is true.

  Threading: no state. }
unit babel.pystr;

{$mode objfpc}{$H+}

interface

type
  TCodePoints = array of Cardinal;

{ The code point of the UTF-8 sequence at S[I] and its length in bytes (a
  malformed byte counts as one code point). }
function CodePointAt(const S: string; I: Integer; out Len: Integer): Cardinal;
function CodePoints(const S: string): TCodePoints;
function CodePointsToUTF8(const C: TCodePoints; First, Count: Integer): string;
{ str.isspace() for one code point. }
function IsPySpace(C: Cardinal): Boolean;
{ str.strip(). }
function PyStrip(const S: string): string;
{ The value 0..9 of a Unicode decimal digit; -1 for anything else. }
function DecimalDigitValue(C: Cardinal): Integer;
{ S with every Unicode decimal digit replaced by its ASCII digit, as
  Python normalizes the text it gives int() and Decimal(). }
function AsciiDigits(const S: string): string;

implementation

const
  DigitZeros: array[0..75] of Cardinal = (
    $30, $660, $6F0, $7C0, $966, $9E6, $A66, $AE6, $B66, $BE6, $C66, $CE6, $D66, $DE6, $E50,
    $ED0, $F20, $1040, $1090, $17E0, $1810, $1946, $19D0, $1A80, $1A90, $1B50, $1BB0, $1C40,
    $1C50, $A620, $A8D0, $A900, $A9D0, $A9F0, $AA50, $ABF0, $FF10, $104A0, $10D30, $10D40,
    $11066, $110F0, $11136, $111D0, $112F0, $11450, $114D0, $11650, $116C0, $116D0, $116DA,
    $11730, $118E0, $11950, $11BF0, $11C50, $11D50, $11DA0, $11F50, $16130, $16A60, $16AC0,
    $16B50, $16D70, $1CCF0, $1D7CE, $1D7D8, $1D7E2, $1D7EC, $1D7F6, $1E140, $1E2F0, $1E4F0,
    $1E5F1, $1E950, $1FBF0);

function CodePointAt(const S: string; I: Integer; out Len: Integer): Cardinal;
var
  B: Byte;
begin
  B := Ord(S[I]);
  if B < $80 then
  begin
    Len := 1;
    Exit(B);
  end;
  if (B and $E0 = $C0) and (I + 1 <= Length(S)) then
  begin
    Len := 2;
    Exit(((B and $1F) shl 6) or (Ord(S[I + 1]) and $3F));
  end;
  if (B and $F0 = $E0) and (I + 2 <= Length(S)) then
  begin
    Len := 3;
    Exit(((B and $0F) shl 12) or ((Ord(S[I + 1]) and $3F) shl 6) or (Ord(S[I + 2]) and $3F));
  end;
  if (B and $F8 = $F0) and (I + 3 <= Length(S)) then
  begin
    Len := 4;
    Exit(((B and $07) shl 18) or ((Ord(S[I + 1]) and $3F) shl 12) or
      ((Ord(S[I + 2]) and $3F) shl 6) or (Ord(S[I + 3]) and $3F));
  end;
  Len := 1;
  Result := B;
end;

function CodePoints(const S: string): TCodePoints;
var
  I, L, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(S));
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Result[N] := CodePointAt(S, I, L);
    Inc(N);
    Inc(I, L);
  end;
  SetLength(Result, N);
end;

function EncodeUTF8(C: Cardinal): string;
begin
  if C < $80 then
    Result := Chr(C)
  else if C < $800 then
    Result := Chr($C0 or (C shr 6)) + Chr($80 or (C and $3F))
  else if C < $10000 then
    Result := Chr($E0 or (C shr 12)) + Chr($80 or ((C shr 6) and $3F)) + Chr($80 or (C and $3F))
  else
    Result := Chr($F0 or (C shr 18)) + Chr($80 or ((C shr 12) and $3F)) +
      Chr($80 or ((C shr 6) and $3F)) + Chr($80 or (C and $3F));
end;

function CodePointsToUTF8(const C: TCodePoints; First, Count: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := First to First + Count - 1 do
    if (I >= 0) and (I <= High(C)) then
      Result := Result + EncodeUTF8(C[I]);
end;

function IsPySpace(C: Cardinal): Boolean;
begin
  case C of
    9..13, $1C..$20, $85, $A0, $1680, $2000..$200A, $2028, $2029, $202F, $205F, $3000:
      Result := True;
  else
    Result := False;
  end;
end;

function PyStrip(const S: string): string;
var
  P, L, First, Stop: Integer;
begin
  First := 0;
  Stop := 0;
  P := 1;
  while P <= Length(S) do
  begin
    if not IsPySpace(CodePointAt(S, P, L)) then
    begin
      if First = 0 then
        First := P;
      Stop := P + L;
    end;
    Inc(P, L);
  end;
  if First = 0 then
    Result := ''
  else
    Result := Copy(S, First, Stop - First);
end;

function DecimalDigitValue(C: Cardinal): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  { the last run whose zero is <= C }
  Lo := 0;
  Hi := High(DigitZeros);
  Result := -1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if DigitZeros[Mid] <= C then
    begin
      if C - DigitZeros[Mid] <= 9 then
        Exit(C - DigitZeros[Mid]);
      Lo := Mid + 1;
    end
    else
      Hi := Mid - 1;
  end;
end;

function AsciiDigits(const S: string): string;
var
  I, L, D: Integer;
  C: Cardinal;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    C := CodePointAt(S, I, L);
    D := DecimalDigitValue(C);
    if (D >= 0) and (L > 1) then
      Result := Result + Chr(Ord('0') + D)
    else
      Result := Result + Copy(S, I, L);
    Inc(I, L);
  end;
end;

end.
