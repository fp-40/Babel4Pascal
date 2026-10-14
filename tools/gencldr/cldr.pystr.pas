{ cldr.pystr - string operations of the generator with the results of
  Python's str methods on UTF-8 text: strip and split without arguments
  (Unicode whitespace, as str.isspace), split with a separator, int() and
  float() of decimal strings. }
unit cldr.pystr;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ True for the code points of Python's str.isspace. }
function PyIsSpace(CP: Cardinal): Boolean;
{ str.strip(): S without leading and trailing whitespace. }
function PyStrip(const S: string): string;
{ str.split(): the words of S between runs of whitespace. }
function PySplit(const S: string): TStringArray;
{ str.split(Sep, MaxSplit): MaxSplit < 0 for no limit. }
function PySplitSep(const S: string; Sep: Char; MaxSplit: Integer = -1): TStringArray;
{ int(S) for a decimal integer (sign, digits, single underscores between
  digits, surrounding whitespace); raises EConvertError otherwise. }
function PyInt(const S: string): Int64;
{ float(S) for a decimal number of at most 15 significant digits and an
  exponent of at most 22 in magnitude, correctly rounded (one exact
  integer, one division or multiplication by an exact power of ten);
  raises EConvertError for other input. }
function PyFloat(const S: string): Double;
{ The UTF-8 encoding of a code point. }
function CodePointToUTF8(CP: Cardinal): string;
{ Byte-wise comparison (the code point order of UTF-8 text). }
function CompareBytes(const A, B: string): Integer;

implementation

function PyIsSpace(CP: Cardinal): Boolean;
begin
  case CP of
    $09..$0D, $1C..$20, $85, $A0, $1680, $2000..$200A, $2028, $2029, $202F,
    $205F, $3000:
      Result := True;
  else
    Result := False;
  end;
end;

{ The code point at S[P] (P is moved past it). Invalid UTF-8 yields the
  byte value. }
function DecodeAt(const S: string; var P: Integer): Cardinal;
var
  B: Byte;
  N, I: Integer;
begin
  B := Ord(S[P]);
  if B < $80 then
  begin
    Inc(P);
    Exit(B);
  end;
  if B and $E0 = $C0 then
  begin
    Result := B and $1F;
    N := 1;
  end
  else if B and $F0 = $E0 then
  begin
    Result := B and $0F;
    N := 2;
  end
  else if B and $F8 = $F0 then
  begin
    Result := B and $07;
    N := 3;
  end
  else
  begin
    Inc(P);
    Exit(B);
  end;
  if P + N > Length(S) then
  begin
    Inc(P);
    Exit(B);
  end;
  for I := 1 to N do
    Result := (Result shl 6) or (Ord(S[P + I]) and $3F);
  Inc(P, N + 1);
end;

{ The start of the code point that ends at S[P]. }
function StartBefore(const S: string; P: Integer): Integer;
begin
  Result := P;
  while (Result > 1) and (Ord(S[Result]) and $C0 = $80) do
    Dec(Result);
end;

function PyStrip(const S: string): string;
var
  First, Last, P, Q: Integer;
begin
  First := 1;
  while First <= Length(S) do
  begin
    P := First;
    if not PyIsSpace(DecodeAt(S, P)) then
      Break;
    First := P;
  end;
  Last := Length(S);
  while Last >= First do
  begin
    Q := StartBefore(S, Last);
    P := Q;
    if not PyIsSpace(DecodeAt(S, P)) then
      Break;
    Last := Q - 1;
  end;
  if (First = 1) and (Last = Length(S)) then
    Result := S
  else
    Result := Copy(S, First, Last - First + 1);
end;

function PySplit(const S: string): TStringArray;
var
  P, Start, Prev, N: Integer;
  Space: Boolean;
begin
  Result := nil;
  N := 0;
  P := 1;
  Start := 0;
  while P <= Length(S) do
  begin
    Prev := P;
    Space := PyIsSpace(DecodeAt(S, P));
    if Space then
    begin
      if Start > 0 then
      begin
        if N = Length(Result) then
          SetLength(Result, N * 2 + 4);
        Result[N] := Copy(S, Start, Prev - Start);
        Inc(N);
        Start := 0;
      end;
    end
    else if Start = 0 then
      Start := Prev;
  end;
  if Start > 0 then
  begin
    if N = Length(Result) then
      SetLength(Result, N + 1);
    Result[N] := Copy(S, Start, Length(S) + 1 - Start);
    Inc(N);
  end;
  SetLength(Result, N);
end;

function PySplitSep(const S: string; Sep: Char; MaxSplit: Integer): TStringArray;
var
  P, Start, N: Integer;
begin
  Result := nil;
  N := 0;
  Start := 1;
  for P := 1 to Length(S) do
    if (S[P] = Sep) and ((MaxSplit < 0) or (N < MaxSplit)) then
    begin
      SetLength(Result, N + 1);
      Result[N] := Copy(S, Start, P - Start);
      Inc(N);
      Start := P + 1;
    end;
  SetLength(Result, N + 1);
  Result[N] := Copy(S, Start, Length(S) + 1 - Start);
end;

function PyInt(const S: string): Int64;
var
  T: string;
  P: Integer;
  Neg, LastDigit: Boolean;
begin
  T := PyStrip(S);
  P := 1;
  Neg := False;
  if (P <= Length(T)) and (T[P] in ['+', '-']) then
  begin
    Neg := T[P] = '-';
    Inc(P);
  end;
  if (P > Length(T)) or not (T[P] in ['0'..'9']) then
    raise EConvertError.CreateFmt('invalid literal for int(): %s', [S]);
  Result := 0;
  LastDigit := False;
  while P <= Length(T) do
  begin
    case T[P] of
      '0'..'9':
        begin
          Result := Result * 10 + (Ord(T[P]) - Ord('0'));
          LastDigit := True;
        end;
      '_':
        begin
          if not LastDigit or (P = Length(T)) then
            raise EConvertError.CreateFmt('invalid literal for int(): %s', [S]);
          LastDigit := False;
        end;
    else
      raise EConvertError.CreateFmt('invalid literal for int(): %s', [S]);
    end;
    Inc(P);
  end;
  if Neg then
    Result := -Result;
end;

function PyFloat(const S: string): Double;
const
  Pow10: array[0..22] of Double = (1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7,
    1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
    1e20, 1e21, 1e22);
var
  T: string;
  P, Digits, Exp10, E: Integer;
  Mant: Int64;
  Neg, NegE, Any: Boolean;
  M: Double;
begin
  T := PyStrip(S);
  P := 1;
  Neg := False;
  if (P <= Length(T)) and (T[P] in ['+', '-']) then
  begin
    Neg := T[P] = '-';
    Inc(P);
  end;
  Mant := 0;
  Digits := 0;
  Exp10 := 0;
  Any := False;
  while (P <= Length(T)) and (T[P] in ['0'..'9']) do
  begin
    Any := True;
    if (Mant > 0) or (T[P] <> '0') then
      Inc(Digits);
    Mant := Mant * 10 + (Ord(T[P]) - Ord('0'));
    if Digits > 15 then
      raise EConvertError.CreateFmt('float(): too many digits: %s', [S]);
    Inc(P);
  end;
  if (P <= Length(T)) and (T[P] = '.') then
  begin
    Inc(P);
    while (P <= Length(T)) and (T[P] in ['0'..'9']) do
    begin
      Any := True;
      if (Mant > 0) or (T[P] <> '0') then
        Inc(Digits);
      Mant := Mant * 10 + (Ord(T[P]) - Ord('0'));
      Dec(Exp10);
      if Digits > 15 then
        raise EConvertError.CreateFmt('float(): too many digits: %s', [S]);
      Inc(P);
    end;
  end;
  if not Any then
    raise EConvertError.CreateFmt('could not convert string to float: %s', [S]);
  if (P <= Length(T)) and (T[P] in ['e', 'E']) then
  begin
    Inc(P);
    NegE := False;
    if (P <= Length(T)) and (T[P] in ['+', '-']) then
    begin
      NegE := T[P] = '-';
      Inc(P);
    end;
    if (P > Length(T)) or not (T[P] in ['0'..'9']) then
      raise EConvertError.CreateFmt('could not convert string to float: %s', [S]);
    E := 0;
    while (P <= Length(T)) and (T[P] in ['0'..'9']) do
    begin
      E := E * 10 + (Ord(T[P]) - Ord('0'));
      if E > 1000 then
        raise EConvertError.CreateFmt('float(): exponent out of range: %s', [S]);
      Inc(P);
    end;
    if NegE then
      Dec(Exp10, E)
    else
      Inc(Exp10, E);
  end;
  if P <= Length(T) then
    raise EConvertError.CreateFmt('could not convert string to float: %s', [S]);
  if (Exp10 < -22) or (Exp10 > 22) then
    raise EConvertError.CreateFmt('float(): exponent out of range: %s', [S]);
  M := Mant; // exact: at most 15 digits
  if Exp10 < 0 then
    Result := M / Pow10[-Exp10]
  else
    Result := M * Pow10[Exp10];
  if Neg then
    Result := -Result;
end;

function CodePointToUTF8(CP: Cardinal): string;
begin
  if CP < $80 then
    Result := Chr(CP)
  else if CP < $800 then
    Result := Chr($C0 or (CP shr 6)) + Chr($80 or (CP and $3F))
  else if CP < $10000 then
    Result := Chr($E0 or (CP shr 12)) + Chr($80 or ((CP shr 6) and $3F)) +
      Chr($80 or (CP and $3F))
  else
    Result := Chr($F0 or (CP shr 18)) + Chr($80 or ((CP shr 12) and $3F)) +
      Chr($80 or ((CP shr 6) and $3F)) + Chr($80 or (CP and $3F));
end;

function CompareBytes(const A, B: string): Integer;
var
  N, R: Integer;
begin
  N := Length(A);
  if Length(B) < N then
    N := Length(B);
  if N > 0 then
  begin
    R := CompareByte(A[1], B[1], N);
    if R <> 0 then
      Exit(R);
  end;
  Result := Length(A) - Length(B);
end;

end.
