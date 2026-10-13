(* ShortestFloatRepr: the shortest decimal text of a Double that reads back as
  the same Double.

  Why not FloatToStrF: trying precisions 1..17 with FloatToStrF and keeping
  the first that reads back as X gives wrong results, because FPC 3.2.2's
  FloatToStrF is exact at 17 digits but rounds twice at fewer digits (some
  values come out one digit longer or one unit off). This file implements
  the free-format algorithm of Burger and Dybvig ("Printing Floating-Point
  Numbers Quickly and Accurately", PLDI 1996) with exact integer arithmetic
  on fixed-size bignums (no heap use): the shortest digit string that
  reads back as X under round-half-even, and among those the one closest
  to X; an exact tie between two last digits takes the even digit
  (562949953421312.25 gives 562949953421312.2).

  Layout: exponent form when the decimal point position DecPt <= -4 or
  DecPt > 16, written d[.ddd]e+XX with at least two exponent digits;
  otherwise fixed notation with '.0' added to integers; 'inf', '-inf',
  'nan', '-0.0'. *)

const
  PFR_LIMBS = 40;                       { 1 280 bits: the largest value is about 2^1132 }

type
  TPfrBig = record
    N: Integer;                         { limbs in use; 0 = zero }
    L: array[0..PFR_LIMBS - 1] of LongWord;
  end;

procedure PfrSet(out A: TPfrBig; V: QWord);
begin
  A.N := 0;
  while V <> 0 do
  begin
    A.L[A.N] := LongWord(V);
    V := V shr 32;
    Inc(A.N);
  end;
end;

procedure PfrMulSmall(var A: TPfrBig; M: LongWord);
var I: Integer; C: QWord;
begin
  C := 0;
  for I := 0 to A.N - 1 do
  begin
    C := QWord(A.L[I]) * M + C;
    A.L[I] := LongWord(C);
    C := C shr 32;
  end;
  if C <> 0 then
  begin
    Assert(A.N < PFR_LIMBS, 'ShortestFloatRepr bignum overflow');
    A.L[A.N] := LongWord(C);
    Inc(A.N);
  end;
end;

procedure PfrShl(var A: TPfrBig; Bits: Integer);
var Words, B, I: Integer; Carry, V: LongWord;
begin
  if (A.N = 0) or (Bits = 0) then Exit;
  Words := Bits div 32;
  B := Bits mod 32;
  if B <> 0 then
  begin
    Carry := 0;
    for I := 0 to A.N - 1 do
    begin
      V := A.L[I];
      A.L[I] := (V shl B) or Carry;
      Carry := V shr (32 - B);
    end;
    if Carry <> 0 then
    begin
      Assert(A.N < PFR_LIMBS, 'ShortestFloatRepr bignum overflow');
      A.L[A.N] := Carry;
      Inc(A.N);
    end;
  end;
  if Words > 0 then
  begin
    Assert(A.N + Words <= PFR_LIMBS, 'ShortestFloatRepr bignum overflow');
    for I := A.N - 1 downto 0 do
      A.L[I + Words] := A.L[I];
    for I := 0 to Words - 1 do
      A.L[I] := 0;
    Inc(A.N, Words);
  end;
end;

procedure PfrMulPow10(var A: TPfrBig; K: Integer);
begin
  while K >= 9 do
  begin
    PfrMulSmall(A, 1000000000);
    Dec(K, 9);
  end;
  while K > 0 do
  begin
    PfrMulSmall(A, 10);
    Dec(K);
  end;
end;

function PfrCmp(const A, B: TPfrBig): Integer;
var I: Integer;
begin
  if A.N <> B.N then
    if A.N < B.N then Exit(-1) else Exit(1);
  for I := A.N - 1 downto 0 do
    if A.L[I] <> B.L[I] then
      if A.L[I] < B.L[I] then Exit(-1) else Exit(1);
  Result := 0;
end;

procedure PfrAdd(const A, B: TPfrBig; out C: TPfrBig);
var I, N: Integer; S: QWord;
begin
  N := A.N;
  if B.N > N then N := B.N;
  S := 0;
  for I := 0 to N - 1 do
  begin
    if I < A.N then S := S + A.L[I];
    if I < B.N then S := S + B.L[I];
    C.L[I] := LongWord(S);
    S := S shr 32;
  end;
  C.N := N;
  if S <> 0 then
  begin
    Assert(N < PFR_LIMBS, 'ShortestFloatRepr bignum overflow');
    C.L[N] := LongWord(S);
    C.N := N + 1;
  end;
end;

procedure PfrSub(var A: TPfrBig; const B: TPfrBig);   { A >= B }
var I: Integer; D: Int64; Borrow: Int64;
begin
  Borrow := 0;
  for I := 0 to A.N - 1 do
  begin
    D := Int64(A.L[I]) - Borrow;
    if I < B.N then D := D - Int64(B.L[I]);
    if D < 0 then
    begin
      D := D + (Int64(1) shl 32);
      Borrow := 1;
    end
    else
      Borrow := 0;
    A.L[I] := LongWord(D);
  end;
  while (A.N > 0) and (A.L[A.N - 1] = 0) do
    Dec(A.N);
end;

{ Shortest, closest digits of a finite X > 0: X ~ 0.Digits * 10^DecPt }
procedure ShortestDigits(X: Double; out Digits: string; out DecPt: Integer);
var
  Bits: QWord; BE, E, K, D, C: Integer; F: QWord;
  R, S, MPlus, MMinus, T: TPfrBig;
  Even, Low, High: Boolean;
begin
  Bits := PQWord(@X)^ and $7FFFFFFFFFFFFFFF;
  BE := Integer(Bits shr 52);
  F := Bits and $FFFFFFFFFFFFF;
  if BE = 0 then
    E := -1074
  else
  begin
    F := F or (QWord(1) shl 52);
    E := BE - 1075;
  end;
  Even := (F and 1) = 0;                 { round-half-even reader: the bounds belong to X }
  { v = R / S; the high and low half-gaps are MPlus / S and MMinus / S }
  if E >= 0 then
  begin
    if F <> (QWord(1) shl 52) then
    begin
      PfrSet(R, F); PfrShl(R, E + 1);
      PfrSet(S, 2);
      PfrSet(MPlus, 1); PfrShl(MPlus, E);
      MMinus := MPlus;
    end
    else
    begin
      PfrSet(R, F); PfrShl(R, E + 2);
      PfrSet(S, 4);
      PfrSet(MPlus, 1); PfrShl(MPlus, E + 1);
      PfrSet(MMinus, 1); PfrShl(MMinus, E);
    end;
  end
  else if (BE <= 1) or (F <> (QWord(1) shl 52)) then
  begin
    PfrSet(R, F); PfrShl(R, 1);
    PfrSet(S, 1); PfrShl(S, 1 - E);
    PfrSet(MPlus, 1);
    PfrSet(MMinus, 1);
  end
  else
  begin
    PfrSet(R, F); PfrShl(R, 2);
    PfrSet(S, 1); PfrShl(S, 2 - E);
    PfrSet(MPlus, 2);
    PfrSet(MMinus, 1);
  end;
  { estimate K = ceil(log10 X); it is exact or one too small, fixed below }
  K := Ceil(Log10(X) - 1E-10);
  if K >= 0 then
    PfrMulPow10(S, K)
  else
  begin
    PfrMulPow10(R, -K);
    PfrMulPow10(MPlus, -K);
    PfrMulPow10(MMinus, -K);
  end;
  PfrAdd(R, MPlus, T);
  C := PfrCmp(T, S);
  if (C > 0) or (Even and (C = 0)) then  { the high bound reaches 10^K: one more digit position }
  begin
    Inc(K);
    PfrMulSmall(S, 10);
  end;
  DecPt := K;
  Digits := '';
  repeat
    PfrMulSmall(R, 10);
    PfrMulSmall(MPlus, 10);
    PfrMulSmall(MMinus, 10);
    D := 0;
    while PfrCmp(R, S) >= 0 do           { quotient digit, 0..9 }
    begin
      PfrSub(R, S);
      Inc(D);
    end;
    C := PfrCmp(R, MMinus);
    Low := (C < 0) or (Even and (C = 0));          { stopping with D stays above the low bound }
    PfrAdd(R, MPlus, T);
    C := PfrCmp(T, S);
    High := (C > 0) or (Even and (C = 0));         { stopping with D + 1 stays below the high bound }
    if Low and High then
    begin
      PfrAdd(R, R, T);                   { compare 2R with S: which last digit is closer }
      C := PfrCmp(T, S);
      if (C > 0) or ((C = 0) and Odd(D)) then Inc(D);   { tie: the even digit }
    end
    else if High then
      Inc(D);
    Assert(D <= 9, 'ShortestFloatRepr digit overflow');
    Digits := Digits + Chr(Ord('0') + D);
  until Low or High;
end;

function ShortestFloatRepr(X: Double): string;
var Digits, M: string; DecPt, N, E: Integer; Neg: Boolean;
begin
  if IsNan(X) then Exit('nan');
  if IsInfinite(X) then
    if X > 0 then Exit('inf') else Exit('-inf');
  Neg := (PQWord(@X)^ shr 63) <> 0;
  if X = 0 then
    if Neg then Exit('-0.0') else Exit('0.0');
  ShortestDigits(Abs(X), Digits, DecPt);
  N := Length(Digits);
  if (DecPt <= -4) or (DecPt > 16) then
  begin
    M := Digits[1];
    if N > 1 then M := M + '.' + Copy(Digits, 2, N - 1);
    E := DecPt - 1;
    if E < 0 then
      M := M + 'e-' + Format('%.2d', [-E])
    else
      M := M + 'e+' + Format('%.2d', [E]);
    Result := M;
  end
  else if DecPt <= 0 then
    Result := '0.' + StringOfChar('0', -DecPt) + Digits
  else if DecPt >= N then
    Result := Digits + StringOfChar('0', DecPt - N) + '.0'
  else
    Result := Copy(Digits, 1, DecPt) + '.' + Copy(Digits, DecPt + 1, N - DecPt);
  if Neg then Result := '-' + Result;
end;
