{ babel.decimal - exact decimal numbers.

  A TDecimal is a sign, a string of coefficient digits and a base-10
  exponent (12.50 is 1250 x 10^-2: digits "1250", exponent -2), or one of
  the special values Infinity and NaN. The digits keep trailing zeros,
  which matter: they are the visible fraction digits of number formatting
  and of the plural rules (1.50 has two). The arithmetic is exact, with
  no precision limit.

  TDecimal is a value type (a record); nothing needs freeing.

  Ways in (also as implicit conversions, so a function that takes a
  TDecimal accepts 1234, 1234.5 or '1234.50'):
  - from a string: optional sign,
    digits with an optional '.', an optional exponent ('1.5E+3'),
    'Infinity' or 'Inf', 'NaN', in any case, with whitespace around;
    decimal digits of any script are accepted ('١٢٣' is 123). An invalid
    string raises EBabelValueError.
  - from an Int64.
  - from a Double: the shortest decimal text that reads back as the same
    Double (babel.floatrepr.inc): 2.675 is 2.675, not its binary value
    2.67499999999999982236...
    FromDoubleExact gives the binary value.

  Arithmetic: products, scaling, normalization and quantization are exact.
  Quantize rounds half-even (ROUND_HALF_EVEN, the default rounding of
  CLDR's number formatting). Division rounds its result to a given number of significant
  digits. An invalid operation (infinity * 0, 0 / 0) and division by zero
  raise EBabelDecimalError.

  Threading: no shared state. }
unit babel.decimal;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors, babel.pystr;

type
  TDecimalKind = (dkFinite, dkInfinity, dkNaN);

  TDecimal = record
  private
    FKind: TDecimalKind;
    FNegative: Boolean;
    FDigits: string;     { finite: no leading zeros, '0' for zero; Infinity: '0'; NaN: '' }
    FExponent: Int64;    { finite only }
    function IntDigitsCount: Int64;
  public
    { The number written in S (see above). Raises EBabelValueError when S
      is not a number. }
    class function Parse(const S: string): TDecimal; static;
    { True and Value set when S parses; False otherwise. }
    class function TryParse(const S: string; out Value: TDecimal): Boolean; static;
    class function FromInt64(V: Int64): TDecimal; static;
    { The shortest decimal that reads back as V; an integer when V is
      integral (1.0 is 1). }
    class function FromDouble(V: Double): TDecimal; static;
    { The exact binary value of V
      (2.675 is 2.67499999999999982236431605997495353221893310546875). }
    class function FromDoubleExact(V: Double): TDecimal; static;
    { A finite value from its parts (Digits: ASCII digits, may be ''
      for zero; leading zeros are dropped). }
    class function Make(Negative: Boolean; const Digits: string; Exponent: Int64): TDecimal; static;

    class operator :=(V: Int64): TDecimal;
    class operator :=(V: Double): TDecimal;
    class operator :=(const S: string): TDecimal;

    property Kind: TDecimalKind read FKind;
    property Negative: Boolean read FNegative;
    { The coefficient digits ('' for NaN, '0' for Infinity) and the
      exponent (finite values only). }
    property Digits: string read FDigits;
    property Exponent: Int64 read FExponent;
    function IsFinite: Boolean;
    function IsNaN: Boolean;
    function IsInfinite: Boolean;
    function IsZero: Boolean;     { finite and zero }
    { The value has no fraction. Finite only. }
    function IsIntegral: Boolean;

    { The value as text, in the notation of the General Decimal
      Arithmetic specification (to-scientific-string): '12.50', '1E+3',
      '1E-7', '-0', 'Infinity', 'NaN'. }
    function ToString: string;
    { The absolute value (a NaN keeps its sign). }
    function Abs: TDecimal;
    { The value truncated toward zero, as an integer (exponent 0). Raises
      EBabelValueError for NaN and Infinity. }
    function Truncate: TDecimal;
    { The exponent of the most significant digit (0 for Infinity and
      NaN). }
    function Adjusted: Int64;
    { The sign bit (also for -0 and -NaN). }
    function IsSigned: Boolean;
    { Trailing zeros stripped (1200 is 1.2E+3); a zero is 0 with its
      sign. }
    function Normalize: TDecimal;
    { The value times 10^N (the exponent moved by N). }
    function ScaleB(N: Int64): TDecimal;
    { 10^N. }
    class function Pow10(N: Int64): TDecimal; static;
    { The exact product. }
    function Multiply(const B: TDecimal): TDecimal;
    { The quotient rounded half-even to Precision significant digits; an
      exact quotient keeps no more trailing zeros than the operands' call
      for (1500 / 1000 is 1.5). Raises EBabelDecimalError for x / 0. }
    function Divide(const B: TDecimal; Precision: Integer = 28): TDecimal;
    { Rounded half-even to the exponent Exp (Quantize(-2) gives two
      fraction digits). Raises EBabelDecimalError for Infinity. }
    function Quantize(Exp: Int64): TDecimal;
    { Quantize(-N): N fraction digits. }
    function Round(N: Int64): TDecimal;
    { Every digit in positional notation ('1.2E+3' is '1200', '1E-7' is
      '0.0000001'); 'NaN', 'Infinity' with a '-' sign when signed. }
    function FormatFixed: string;
    { -1, 0 or 1 comparing the values (infinities included; NaN raises
      EBabelValueError). }
    function Compare(const B: TDecimal): Integer;
    function CompareInt(B: Int64): Integer;
    { The remainder of the division by M (M > 0), with the sign of the
      value, exact (the exponent is min(Exponent, 0)). Finite only. }
    function ModInt(M: Int64): TDecimal;
    { The value as Int64 when it is an integer that fits; else False. }
    function TryToInt64(out V: Int64): Boolean;
  end;

{ The shortest text that reads back as X ('0.1', '1e+16',
  '0.30000000000000004', 'inf', 'nan', '-0.0'). }
function ShortestFloatRepr(X: Double): string;

implementation

uses
  Math;

{$I babel.floatrepr.inc}


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

{ A digit string times a small factor. }
function DigitsMulSmall(const D: string; F: Integer): string;
var
  I, Carry, T: Integer;
begin
  Result := D;
  Carry := 0;
  for I := Length(Result) downto 1 do
  begin
    T := (Ord(Result[I]) - 48) * F + Carry;
    Result[I] := Chr(48 + T mod 10);
    Carry := T div 10;
  end;
  while Carry > 0 do
  begin
    Result := Chr(48 + Carry mod 10) + Result;
    Carry := Carry div 10;
  end;
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
  { whitespace around; decimal digits of any script }
  T := AsciiDigits(PyStrip(S));
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
  if Lower = 'nan' then
  begin
    Value.FKind := dkNaN;
    Value.FNegative := Neg;
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
    raise EBabelValueError.CreateFmt('not a number: ''%s''', [S]);
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
var
  R: string;
begin
  R := ShortestFloatRepr(V);
  { an integral double is an integer: 1.0 is 1 }
  if (Length(R) > 2) and (Copy(R, Length(R) - 1, 2) = '.0') then
    SetLength(R, Length(R) - 2);
  Result := Parse(R);
end;

class function TDecimal.FromDoubleExact(V: Double): TDecimal;
var
  Bits: QWord;
  Mant: QWord;
  E: Integer;
  Neg: Boolean;
  D: string;
  I: Integer;
begin
  if Math.IsNan(V) or Math.IsInfinite(V) then
    Exit(FromDouble(V));
  Move(V, Bits, 8);
  Neg := Bits shr 63 = 1;
  E := (Bits shr 52) and $7FF;
  Mant := Bits and ((QWord(1) shl 52) - 1);
  if E = 0 then
    E := 1                       { subnormal }
  else
    Mant := Mant or (QWord(1) shl 52);
  E := E - 1075;                 { value = Mant * 2^E }
  if Mant = 0 then
    Exit(Make(Neg, '0', 0));
  { strip factors of two so the decimal coefficient is exact and short }
  while (Mant and 1 = 0) and (E < 0) do
  begin
    Mant := Mant shr 1;
    Inc(E);
  end;
  D := IntToStr(Mant);
  if E >= 0 then
  begin
    for I := 1 to E do
      D := DigitsMulSmall(D, 2);
    Result := Make(Neg, D, 0);
  end
  else
  begin
    { Mant / 2^-E = Mant * 5^-E / 10^-E }
    for I := 1 to -E do
      D := DigitsMulSmall(D, 5);
    Result := Make(Neg, D, E);
  end;
end;

class operator TDecimal.:=(V: Int64): TDecimal;
begin
  Result := TDecimal.FromInt64(V);
end;

class operator TDecimal.:=(V: Double): TDecimal;
begin
  Result := TDecimal.FromDouble(V);
end;

class operator TDecimal.:=(const S: string): TDecimal;
begin
  Result := TDecimal.Parse(S);
end;

function TDecimal.IsFinite: Boolean;
begin
  Result := FKind = dkFinite;
end;

function TDecimal.IsNaN: Boolean;
begin
  Result := FKind = dkNaN;
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
    dkNaN: Exit(Sign + 'NaN');
  end;
  { to-scientific-string: plain notation unless the exponent is positive
    or the adjusted exponent is below -6 }
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
  if FKind <> dkNaN then
    Result.FNegative := False;
end;

function TDecimal.Truncate: TDecimal;
var
  N: Int64;
begin
  if FKind = dkInfinity then
    raise EBabelValueError.Create('cannot convert Infinity to integer');
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
  if IsNaN or B.IsNaN then
    NotFinite('Compare');
  { Infinities order around every finite value. }
  if (FKind = dkInfinity) or (B.FKind = dkInfinity) then
  begin
    if (FKind = dkInfinity) and (B.FKind = dkInfinity) and (FNegative = B.FNegative) then
      Exit(0);
    if FKind = dkInfinity then
    begin
      if FNegative then Exit(-1) else Exit(1);
    end;
    if B.FNegative then Exit(1) else Exit(-1);
  end;
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


{ ---- arithmetic ---- }

procedure Signal(const Condition: string);
begin
  raise EBabelDecimalError.Create(Condition);
end;

{ The NaN operand is the result of an operation on NaN. Callers test
  IsNaN first. }
function CheckNaNs(const A, B: TDecimal): TDecimal;
begin
  if A.IsNaN then
    Result := A
  else
    Result := B;
end;

function Triple(Negative: Boolean; const Digits: string; Exponent: Int64): TDecimal;
begin
  Result := TDecimal.Make(Negative, Digits, Exponent);
end;

function InfinityOf(Negative: Boolean): TDecimal;
begin
  Result := Default(TDecimal);
  Result.FKind := dkInfinity;
  Result.FNegative := Negative;
  Result.FDigits := '0';
end;

function AllZeros(const D: string; From: Integer): Boolean;
var
  I: Integer;
begin
  for I := From to Length(D) do
    if D[I] <> '0' then
      Exit(False);
  Result := True;
end;

{ Rounding half-even of coefficient D keeping Keep digits: 1 to round
  up, 0 when the dropped digits are zero, -1 to truncate. }
function RoundHalfEven(const D: string; Keep: Integer): Integer;
begin
  if D[Keep + 1] in ['5'..'9'] then
    Result := 1
  else if AllZeros(D, Keep + 1) then
    Result := 0
  else
    Result := -1;
  { an exact half rounds to the even digit }
  if (D[Keep + 1] = '5') and AllZeros(D, Keep + 2) and
     ((Keep = 0) or ((Ord(D[Keep]) - Ord('0')) mod 2 = 0)) then
    Result := -1;
end;

{ Adds one to a string of digits. }
function DigitsInc(const D: string): string;
var
  I: Integer;
begin
  Result := D;
  I := Length(Result);
  while (I >= 1) and (Result[I] = '9') do
  begin
    Result[I] := '0';
    Dec(I);
  end;
  if I = 0 then
    Result := '1' + Result
  else
    Result[I] := Chr(Ord(Result[I]) + 1);
end;

{ The value rounded half-even to Precision significant digits (for the
  division, whose result may not end). }
function RoundToDigits(const V: TDecimal; Precision: Integer): TDecimal;
var
  Drop: Integer;
  Coeff: string;
begin
  Result := V;
  if (V.Kind <> dkFinite) or (Length(V.FDigits) <= Precision) then
    Exit;
  Drop := Length(V.FDigits) - Precision;
  Coeff := Copy(V.FDigits, 1, Precision);
  if RoundHalfEven(V.FDigits, Precision) = 1 then
  begin
    Coeff := DigitsInc(Coeff);
    if Length(Coeff) > Precision then
    begin
      SetLength(Coeff, Length(Coeff) - 1);
      Inc(Drop);
    end;
  end;
  Result := Triple(V.FNegative, Coeff, V.FExponent + Drop);
end;

function TDecimal.Adjusted: Int64;
begin
  if FKind <> dkFinite then
    Exit(0);
  Result := FExponent + Length(FDigits) - 1;
end;

function TDecimal.IsSigned: Boolean;
begin
  Result := FNegative;
end;

function TDecimal.Normalize: TDecimal;
var
  Last: Integer;
  E: Int64;
begin
  if FKind <> dkFinite then
    Exit(Self);
  if FDigits = '0' then
    Exit(Triple(FNegative, '0', 0));
  Last := Length(FDigits);
  E := FExponent;
  while FDigits[Last] = '0' do
  begin
    Inc(E);
    Dec(Last);
  end;
  Result := Triple(FNegative, Copy(FDigits, 1, Last), E);
end;

function TDecimal.ScaleB(N: Int64): TDecimal;
begin
  if FKind <> dkFinite then
    Exit(Self);
  Result := Triple(FNegative, FDigits, FExponent + N);
end;

class function TDecimal.Pow10(N: Int64): TDecimal;
begin
  Result := Triple(False, '1', N);
end;

{ Product of two digit strings. }
function DigitsMul(const A, B: string): string;
var
  R: array of Integer;
  I, J, Carry, T: Integer;
begin
  R := nil;
  SetLength(R, Length(A) + Length(B));
  for I := Length(A) downto 1 do
  begin
    Carry := 0;
    for J := Length(B) downto 1 do
    begin
      T := R[I + J - 1] + (Ord(A[I]) - 48) * (Ord(B[J]) - 48) + Carry;
      R[I + J - 1] := T mod 10;
      Carry := T div 10;
    end;
    R[I - 1] := R[I - 1] + Carry;
  end;
  SetLength(Result, Length(R));
  for I := 0 to High(R) do
    Result[I + 1] := Chr(48 + R[I]);
  Result := StripLeadingZeros(Result);
end;

{ A - B for digit strings with A >= B. }
function DigitsSub(const A, B: string): string;
var
  I, J, Borrow, T: Integer;
begin
  Result := A;
  Borrow := 0;
  J := Length(B);
  for I := Length(A) downto 1 do
  begin
    T := Ord(Result[I]) - 48 - Borrow;
    if J >= 1 then
    begin
      T := T - (Ord(B[J]) - 48);
      Dec(J);
    end;
    if T < 0 then
    begin
      Inc(T, 10);
      Borrow := 1;
    end
    else
      Borrow := 0;
    Result[I] := Chr(48 + T);
  end;
  Result := StripLeadingZeros(Result);
end;

{ Long division of digit strings (B <> '0'). }
procedure DigitsDivMod(const A, B: string; out Q, R: string);
var
  I, Digit: Integer;
begin
  Q := '';
  R := '0';
  for I := 1 to Length(A) do
  begin
    if R = '0' then
      R := A[I]
    else
      R := R + A[I];
    Digit := 0;
    while CompareDigitStrings(R, B) >= 0 do
    begin
      R := DigitsSub(R, B);
      Inc(Digit);
    end;
    Q := Q + Chr(48 + Digit);
  end;
  Q := StripLeadingZeros(Q);
end;

function TDecimal.Multiply(const B: TDecimal): TDecimal;
var
  Neg: Boolean;
begin
  Neg := FNegative <> B.FNegative;
  if (FKind <> dkFinite) or (B.FKind <> dkFinite) then
  begin
    if IsNaN or B.IsNaN then
      Exit(CheckNaNs(Self, B));
    if IsZero or B.IsZero then
      Signal('invalid operation: infinity * 0');
    Exit(InfinityOf(Neg));
  end;
  if (FDigits = '0') or (B.FDigits = '0') then
    Exit(Triple(Neg, '0', FExponent + B.FExponent));
  Result := Triple(Neg, DigitsMul(FDigits, B.FDigits), FExponent + B.FExponent);
end;

function TDecimal.Divide(const B: TDecimal; Precision: Integer): TDecimal;
var
  Neg: Boolean;
  Shift, Exp, IdealExp: Int64;
  Op1, Op2, Coeff, Remainder: string;
begin
  Neg := FNegative <> B.FNegative;
  if (FKind <> dkFinite) or (B.FKind <> dkFinite) then
  begin
    if IsNaN or B.IsNaN then
      Exit(CheckNaNs(Self, B));
    if (FKind = dkInfinity) and (B.FKind = dkInfinity) then
      Signal('invalid operation: infinity / infinity');
    if FKind = dkInfinity then
      Exit(InfinityOf(Neg));
    Exit(Triple(Neg, '0', 0));   { finite / infinity }
  end;
  if B.FDigits = '0' then
  begin
    if FDigits = '0' then
      Signal('invalid operation: 0 / 0');
    Signal('division by zero');
  end;
  if FDigits = '0' then
    Exit(Triple(Neg, '0', FExponent - B.FExponent));
  { Precision + 1 digits of quotient, the last one made inexact (sticky)
    when there is a remainder, then rounded; an exact quotient keeps only
    the trailing zeros its operands' exponents call for (1500 / 1000 is
    1.5), as the General Decimal Arithmetic specification divides. }
  Shift := Length(B.FDigits) - Length(FDigits) + Precision + 1;
  Exp := FExponent - B.FExponent - Shift;
  if Shift >= 0 then
  begin
    Op1 := FDigits + StringOfChar('0', Shift);
    Op2 := B.FDigits;
  end
  else
  begin
    Op1 := FDigits;
    Op2 := B.FDigits + StringOfChar('0', -Shift);
  end;
  DigitsDivMod(Op1, Op2, Coeff, Remainder);
  if Remainder <> '0' then
  begin
    if (Ord(Coeff[Length(Coeff)]) - 48) mod 5 = 0 then
      Coeff := DigitsInc(Coeff);
  end
  else
  begin
    IdealExp := FExponent - B.FExponent;
    while (Exp < IdealExp) and (Length(Coeff) > 1) and (Coeff[Length(Coeff)] = '0') do
    begin
      SetLength(Coeff, Length(Coeff) - 1);
      Inc(Exp);
    end;
  end;
  Result := RoundToDigits(Triple(Neg, Coeff, Exp), Precision);
end;

function TDecimal.Quantize(Exp: Int64): TDecimal;
var
  Keep: Int64;
  D, Coeff: string;
begin
  if FKind = dkNaN then
    Exit(Self);
  if FKind = dkInfinity then
    Signal('invalid operation: quantize of infinity');
  if FDigits = '0' then
    Exit(Triple(FNegative, '0', Exp));
  if FExponent >= Exp then
    Exit(Triple(FNegative, FDigits + StringOfChar('0', FExponent - Exp), Exp));
  { round half-even at exponent Exp }
  D := FDigits;
  Keep := Length(D) + FExponent - Exp;
  if Keep < 0 then
  begin
    D := '1';                    { far below the quantum: rounds to 0 }
    Keep := 0;
  end;
  Coeff := Copy(D, 1, Keep);
  if Coeff = '' then
    Coeff := '0';
  if RoundHalfEven(D, Keep) = 1 then
    Coeff := DigitsInc(Coeff);
  Result := Triple(FNegative, Coeff, Exp);
end;

function TDecimal.Round(N: Int64): TDecimal;
begin
  Result := Quantize(-N);
end;

function TDecimal.FormatFixed: string;
var
  DotPlace: Int64;
  IntPart, FracPart, Sign: string;
begin
  if FNegative then
    Sign := '-'
  else
    Sign := '';
  case FKind of
    dkInfinity: Exit(Sign + 'Infinity');
    dkNaN: Exit(Sign + 'NaN');
  end;
  { a zero with a positive exponent is written as 0 }
  if (FDigits = '0') and (FExponent > 0) then
    Exit(Sign + '0');
  DotPlace := FExponent + Length(FDigits);
  if DotPlace < 0 then
  begin
    IntPart := '0';
    FracPart := StringOfChar('0', -DotPlace) + FDigits;
  end
  else if DotPlace > Length(FDigits) then
  begin
    IntPart := FDigits + StringOfChar('0', DotPlace - Length(FDigits));
    FracPart := '';
  end
  else
  begin
    IntPart := Copy(FDigits, 1, DotPlace);
    if IntPart = '' then
      IntPart := '0';
    FracPart := Copy(FDigits, DotPlace + 1, MaxInt);
  end;
  Result := Sign + IntPart;
  if FracPart <> '' then
    Result := Result + '.' + FracPart;
end;

end.
