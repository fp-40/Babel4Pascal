{ babel.decimal - decimal numbers as Python's decimal.Decimal holds them.

  Babel computes with Python's Decimal: a sign, a string of coefficient
  digits and a base-10 exponent (Decimal('12.50') is 1250 x 10^-2: digits
  "1250", exponent -2), plus the special values Infinity, NaN and sNaN.
  The digits keep trailing zeros, which matter: they are the "visible
  fraction digits" of the plural rules and of number formatting.

  TDecimal holds the same parts. It is a value type (a record); nothing
  needs freeing.

  Ways in:
  - TDecimal.Parse: the text syntax of Python's Decimal(str), with the same
    results (whitespace around, '_' anywhere removed, 'Inf', 'NaN123',
    exponents). Only ASCII digits are accepted (Python also accepts other
    Unicode decimal digits).
  - TDecimal.FromInt64.
  - TDecimal.FromDouble: as Babel converts a float, Decimal(str(x)): the
    shortest decimal text that reads back as the same Double
    (babel.pyfloatrepr.inc). 2.675 becomes 2.675, not the binary value
    2.67499999999999982236...

  The arithmetic is what the units of this library need so far (more is
  added as the number formatting is written); every operation is exact.

  Threading: no shared state. }
unit babel.decimal;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors;

type
  TDecimalKind = (dkFinite, dkInfinity, dkNaN, dkSNaN);

  TDecimal = record
  private
    FKind: TDecimalKind;
    FNegative: Boolean;
    FDigits: string;     { finite: no leading zeros, '0' for zero; NaN: payload }
    FExponent: Int64;    { finite only }
    function IntDigitsCount: Int64;
  public
    { Python's Decimal(S). Raises EBabelValueError when S is not a number
      (Python raises decimal.InvalidOperation). }
    class function Parse(const S: string): TDecimal; static;
    { True and Value set when S parses; False otherwise. }
    class function TryParse(const S: string; out Value: TDecimal): Boolean; static;
    class function FromInt64(V: Int64): TDecimal; static;
    { Decimal(str(V)), as Babel converts a float. }
    class function FromDouble(V: Double): TDecimal; static;
    { A finite value from its parts (Digits: ASCII digits, may be ''
      for zero; leading zeros are dropped). }
    class function Make(Negative: Boolean; const Digits: string; Exponent: Int64): TDecimal; static;

    property Kind: TDecimalKind read FKind;
    property Negative: Boolean read FNegative;
    { As Decimal.as_tuple(): the coefficient digits ('' for NaN without a
      payload, '0' for Infinity) and the exponent (finite values only). }
    property Digits: string read FDigits;
    property Exponent: Int64 read FExponent;
    function IsFinite: Boolean;
    function IsNaN: Boolean;      { NaN or sNaN }
    function IsInfinite: Boolean;
    function IsZero: Boolean;     { finite and zero }
    { The value has no fraction (Python: num == int(num)). Finite only. }
    function IsIntegral: Boolean;

    { str(Decimal): '12.50', '1E+3', '1E-7', '-0', 'Infinity', 'NaN123'. }
    function ToString: string;
    { The absolute value (Python abs(): keeps the digits and exponent). }
    function Abs: TDecimal;
    { int(Decimal): the value truncated toward zero, as an integer
      (exponent 0). Raises EBabelValueError for NaN and EBabelOverflowError
      for Infinity, as Python. }
    function Truncate: TDecimal;
    { -1, 0 or 1 comparing the values. Finite only. }
    function Compare(const B: TDecimal): Integer;
    function CompareInt(B: Int64): Integer;
    { The remainder of the division by M (M > 0), with the sign of the
      value, exact (Python's Decimal % int; the exponent is
      min(Exponent, 0)). Finite only. }
    function ModInt(M: Int64): TDecimal;
    { The value as Int64 when it is an integer that fits; else False. }
    function TryToInt64(out V: Int64): Boolean;
  end;

{ repr() of a Python float: the shortest text that reads back as X
  ('0.1', '1e+16', '0.30000000000000004', 'inf', 'nan', '-0.0'). }
function PyFloatRepr(X: Double): string;

implementation

uses
  Math;

{$I babel.pyfloatrepr.inc}

procedure NotFinite(const Op: string);
begin
  raise EBabelValueError.CreateFmt('%s of a non-finite Decimal', [Op]);
end;

function StripLeadingZeros(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I < Length(S)) and (S[I] = '0') do
    Inc(I);
  Result := Copy(S, I, MaxInt);
  if Result = '' then
    Result := '0';
end;

class function TDecimal.Make(Negative: Boolean; const Digits: string; Exponent: Int64): TDecimal;
begin
  Result := Default(TDecimal);
  Result.FKind := dkFinite;
  Result.FNegative := Negative;
  Result.FDigits := StripLeadingZeros(Digits);
  Result.FExponent := Exponent;
end;

class function TDecimal.TryParse(const S: string; out Value: TDecimal): Boolean;
var
  T, IntPart, FracPart, ExpPart, Lower: string;
  I, N: Integer;
  Neg, ExpNeg: Boolean;
  E, Digit: Int64;

  function AllDigits(const X: string): Boolean;
  var
    C: Char;
  begin
    for C in X do
      if not (C in ['0'..'9']) then
        Exit(False);
    Result := True;
  end;

begin
  Value := Default(TDecimal);
  Result := False;
  { Python strips whitespace, then removes every underscore. }
  T := StringReplace(Trim(S), '_', '', [rfReplaceAll]);
  if T = '' then
    Exit;
  Neg := False;
  if T[1] in ['+', '-'] then
  begin
    Neg := T[1] = '-';
    Delete(T, 1, 1);
  end;
  Lower := LowerCase(T);
  if (Lower = 'inf') or (Lower = 'infinity') then
  begin
    Value.FKind := dkInfinity;
    Value.FNegative := Neg;
    Value.FDigits := '0';
    Exit(True);
  end;
  if (Copy(Lower, 1, 3) = 'nan') or (Copy(Lower, 1, 4) = 'snan') then
  begin
    if Lower[1] = 's' then
    begin
      Value.FKind := dkSNaN;
      T := Copy(T, 5, MaxInt);
    end
    else
    begin
      Value.FKind := dkNaN;
      T := Copy(T, 4, MaxInt);
    end;
    if not AllDigits(T) then
      Exit;
    Value.FNegative := Neg;
    if T <> '' then
    begin
      Value.FDigits := StripLeadingZeros(T);
      if Value.FDigits = '0' then
        Value.FDigits := '';
    end;
    Exit(True);
  end;

  { digits [. digits] [e [sign] digits], at least one digit in the
    mantissa. }
  I := Pos('e', Lower);
  if I > 0 then
  begin
    ExpPart := Copy(T, I + 1, MaxInt);
    T := Copy(T, 1, I - 1);
    ExpNeg := False;
    if (ExpPart <> '') and (ExpPart[1] in ['+', '-']) then
    begin
      ExpNeg := ExpPart[1] = '-';
      Delete(ExpPart, 1, 1);
    end;
    if (ExpPart = '') or not AllDigits(ExpPart) then
      Exit;
    E := 0;
    for N := 1 to Length(ExpPart) do
    begin
      Digit := Ord(ExpPart[N]) - Ord('0');
      if E > (High(Int64) - Digit) div 10 then
        Exit;   { beyond what an Int64 exponent holds }
      E := E * 10 + Digit;
    end;
    if ExpNeg then
      E := -E;
  end
  else
    E := 0;
  I := Pos('.', T);
  if I > 0 then
  begin
    IntPart := Copy(T, 1, I - 1);
    FracPart := Copy(T, I + 1, MaxInt);
  end
  else
  begin
    IntPart := T;
    FracPart := '';
  end;
  if (IntPart = '') and (FracPart = '') then
    Exit;
  if not AllDigits(IntPart) or not AllDigits(FracPart) then
    Exit;
  if E < Low(Int64) + Length(FracPart) then
    Exit;
  Value := Make(Neg, IntPart + FracPart, E - Length(FracPart));
  Result := True;
end;

class function TDecimal.Parse(const S: string): TDecimal;
begin
  if not TryParse(S, Result) then
    raise EBabelValueError.CreateFmt('invalid literal for Decimal: ''%s''', [S]);
end;

class function TDecimal.FromInt64(V: Int64): TDecimal;
begin
  if V < 0 then
    { -High(Int64)-1 has no positive Int64: take the digits of the QWord. }
    Result := Make(True, IntToStr(QWord(-(V + 1)) + 1), 0)
  else
    Result := Make(False, IntToStr(V), 0);
end;

class function TDecimal.FromDouble(V: Double): TDecimal;
begin
  Result := Parse(PyFloatRepr(V));
end;

function TDecimal.IsFinite: Boolean;
begin
  Result := FKind = dkFinite;
end;

function TDecimal.IsNaN: Boolean;
begin
  Result := FKind in [dkNaN, dkSNaN];
end;

function TDecimal.IsInfinite: Boolean;
begin
  Result := FKind = dkInfinity;
end;

function TDecimal.IsZero: Boolean;
begin
  Result := (FKind = dkFinite) and (FDigits = '0');
end;

{ Number of digits before the decimal point: Length(FDigits) + FExponent
  (may be <= 0 for values below 1). }
function TDecimal.IntDigitsCount: Int64;
begin
  Result := Length(FDigits) + FExponent;
end;

function TDecimal.IsIntegral: Boolean;
var
  I: Int64;
begin
  if FKind <> dkFinite then
    NotFinite('IsIntegral');
  if (FExponent >= 0) or (FDigits = '0') then
    Exit(True);
  { Every digit after the point must be zero. }
  I := IntDigitsCount;
  if I < 0 then
    I := 0;
  for I := I + 1 to Length(FDigits) do
    if FDigits[I] <> '0' then
      Exit(False);
  Result := True;
end;

function TDecimal.ToString: string;
var
  LeftDigits, DotPlace: Int64;
  IntPart, FracPart, ExpPart, Sign: string;
begin
  if FNegative then
    Sign := '-'
  else
    Sign := '';
  case FKind of
    dkInfinity: Exit(Sign + 'Infinity');
    dkNaN: Exit(Sign + 'NaN' + FDigits);
    dkSNaN: Exit(Sign + 'sNaN' + FDigits);
  end;
  { Python's Decimal.__str__ (scientific notation rules). }
  LeftDigits := FExponent + Length(FDigits);
  if (FExponent <= 0) and (LeftDigits > -6) then
    DotPlace := LeftDigits
  else
    DotPlace := 1;
  if DotPlace <= 0 then
  begin
    IntPart := '0';
    FracPart := '.' + StringOfChar('0', -DotPlace) + FDigits;
  end
  else if DotPlace >= Length(FDigits) then
  begin
    IntPart := FDigits + StringOfChar('0', DotPlace - Length(FDigits));
    FracPart := '';
  end
  else
  begin
    IntPart := Copy(FDigits, 1, DotPlace);
    FracPart := '.' + Copy(FDigits, DotPlace + 1, MaxInt);
  end;
  if LeftDigits = DotPlace then
    ExpPart := ''
  else if LeftDigits - DotPlace > 0 then
    ExpPart := 'E+' + IntToStr(LeftDigits - DotPlace)
  else
    ExpPart := 'E' + IntToStr(LeftDigits - DotPlace);
  Result := Sign + IntPart + FracPart + ExpPart;
end;

function TDecimal.Abs: TDecimal;
begin
  Result := Self;
  if FKind in [dkFinite, dkInfinity] then
    Result.FNegative := False;
end;

function TDecimal.Truncate: TDecimal;
var
  N: Int64;
begin
  if FKind = dkInfinity then
    raise EBabelOverflowError.Create('cannot convert Infinity to integer');
  if FKind <> dkFinite then
    raise EBabelValueError.Create('cannot convert NaN to integer');
  if FExponent >= 0 then
  begin
    if FDigits = '0' then
      Exit(Make(FNegative, '0', 0));
    if FExponent > High(Integer) div 2 then
      raise EBabelValueError.Create('Decimal too large to convert to an integer');
    Exit(Make(FNegative, FDigits + StringOfChar('0', FExponent), 0));
  end;
  N := IntDigitsCount;
  if N <= 0 then
    Result := Make(FNegative, '0', 0)
  else
    Result := Make(FNegative, Copy(FDigits, 1, N), 0);
end;

{ Compares two non-negative integers given as digit strings without
  leading zeros. }
function CompareDigitStrings(const A, B: string): Integer;
begin
  if Length(A) <> Length(B) then
  begin
    if Length(A) < Length(B) then
      Exit(-1);
    Exit(1);
  end;
  Result := CompareStr(A, B);
  if Result < 0 then
    Result := -1
  else if Result > 0 then
    Result := 1;
end;

function TDecimal.Compare(const B: TDecimal): Integer;
var
  AZero, BZero: Boolean;
  Scale: Int64;
  DA, DB: string;
begin
  if (FKind <> dkFinite) or (B.FKind <> dkFinite) then
    NotFinite('Compare');
  AZero := FDigits = '0';
  BZero := B.FDigits = '0';
  if AZero and BZero then
    Exit(0);
  if AZero then
  begin
    if B.FNegative then Exit(1) else Exit(-1);
  end;
  if BZero then
  begin
    if FNegative then Exit(-1) else Exit(1);
  end;
  if FNegative <> B.FNegative then
  begin
    if FNegative then Exit(-1) else Exit(1);
  end;
  { Same sign, both nonzero: compare magnitudes. Different counts of
    integer digits decide at once; otherwise align the exponents. }
  if IntDigitsCount <> B.IntDigitsCount then
  begin
    if IntDigitsCount < B.IntDigitsCount then Result := -1 else Result := 1;
  end
  else
  begin
    DA := FDigits;
    DB := B.FDigits;
    Scale := FExponent - B.FExponent;
    if Scale > 0 then
      DA := DA + StringOfChar('0', Scale)
    else if Scale < 0 then
      DB := DB + StringOfChar('0', -Scale);
    Result := CompareDigitStrings(DA, DB);
  end;
  if FNegative then
    Result := -Result;
end;

function TDecimal.CompareInt(B: Int64): Integer;
begin
  Result := Compare(FromInt64(B));
end;

{ The remainder of a digit string (an integer) divided by M. }
function DigitsMod(const D: string; M: Int64): Int64;
var
  C: Char;
begin
  Result := 0;
  for C in D do
    Result := (Result * 10 + Ord(C) - Ord('0')) mod M;
end;

{ (A * B) mod M for 0 <= A, B < M without overflow. }
function MulMod(A, B, M: Int64): Int64;
begin
  Result := 0;
  A := A mod M;
  while B > 0 do
  begin
    if B and 1 = 1 then
      Result := (Result + A) mod M;
    A := (A * 2) mod M;
    B := B shr 1;
  end;
end;

{ 10^E mod M, by squaring. }
function PowMod10(E, M: Int64): Int64;
var
  Base: Int64;
begin
  Result := 1 mod M;
  Base := 10 mod M;
  while E > 0 do
  begin
    if E and 1 = 1 then
      Result := MulMod(Result, Base, M);
    Base := MulMod(Base, Base, M);
    E := E shr 1;
  end;
end;

function TDecimal.ModInt(M: Int64): TDecimal;
var
  R, P: Int64;
  N: Int64;
  IntDigits, FracDigits: string;
begin
  if FKind <> dkFinite then
    NotFinite('modulo');
  if (M <= 0) or (M > High(Int64) div 10) then
    raise EBabelValueError.Create('ModInt: modulus out of range');
  if FExponent >= 0 then
  begin
    { digits x 10^e mod m }
    R := DigitsMod(FDigits, M);
    P := PowMod10(FExponent, M);
    Exit(Make(FNegative, IntToStr(MulMod(R, P, M)), 0));
  end;
  N := IntDigitsCount;
  if N <= 0 then
  begin
    { |value| < 1: it is its own remainder. }
    Result := Self;
    Exit;
  end;
  IntDigits := Copy(FDigits, 1, N);
  FracDigits := Copy(FDigits, N + 1, MaxInt);
  Result := Make(FNegative, IntToStr(DigitsMod(IntDigits, M)) + FracDigits, FExponent);
end;

function TDecimal.TryToInt64(out V: Int64): Boolean;
var
  D: string;
  Q: QWord;
  C: Char;
begin
  V := 0;
  if (FKind <> dkFinite) or not IsIntegral then
    Exit(False);
  D := Truncate.FDigits;
  if Length(D) > 19 then
    Exit(False);
  Q := 0;
  for C in D do
  begin
    if Q > (High(QWord) - 9) div 10 then
      Exit(False);
    Q := Q * 10 + QWord(Ord(C) - Ord('0'));
  end;
  if FNegative then
  begin
    if Q > QWord(High(Int64)) + 1 then
      Exit(False);
    V := -Int64(Q - 1) - 1;
  end
  else
  begin
    if Q > QWord(High(Int64)) then
      Exit(False);
    V := Int64(Q);
  end;
  Result := True;
end;

end.
