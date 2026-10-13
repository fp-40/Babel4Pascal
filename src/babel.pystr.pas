{ babel.pystr - the parts of Python's str semantics that Babel's results
  depend on, for UTF-8 strings: code points, str.isspace and str.strip,
  the Unicode decimal digits that int() and Decimal() accept
  ('١٢٣' is 123), and str.format with positional fields.

  The tables are those of Unicode 16.0, the version of the Python (3.14)
  the oracle runs on: 76 runs of ten decimal digits (category Nd, each run
  0..9 in order), the 29 characters for which str.isspace() is true, and
  the 243 ranges of the categories S and Z.

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
{ True for a character of the Unicode general categories S (symbols) and
  Z (separators): the complement of CLDR's currencySpacing currencyMatch
  [[:^S:]&[:^Z:]]. }
function IsSymbolOrSeparator(C: Cardinal): Boolean;
(* Fmt.format( *Args) for positional fields: '{0}', '{1}', '{}' (numbered
  in order), '{{' and '}}' for braces, in one pass (an argument's text is
  not read as a field). Raises EBabelIndexError for a field without an
  argument and EBabelValueError for a malformed or unsupported field
  ('{0:>5}', a single '}'), as Python's ValueError. *)
function PyFormat(const Fmt: string; const Args: array of string): string;

implementation

uses
  SysUtils, babel.errors;

function PyFormat(const Fmt: string; const Args: array of string): string;
var
  I, J, Index, Auto: Integer;
  Field: string;
begin
  Result := '';
  Auto := 0;
  I := 1;
  while I <= Length(Fmt) do
  begin
    if Fmt[I] = '{' then
    begin
      if (I < Length(Fmt)) and (Fmt[I + 1] = '{') then
      begin
        Result := Result + '{';
        Inc(I, 2);
        Continue;
      end;
      J := I + 1;
      while (J <= Length(Fmt)) and (Fmt[J] <> '}') do
        Inc(J);
      if J > Length(Fmt) then
        raise EBabelValueError.Create('Single ''{'' encountered in format string');
      Field := Copy(Fmt, I + 1, J - I - 1);
      if Field = '' then
      begin
        Index := Auto;
        Inc(Auto);
      end
      else if not TryStrToInt(Field, Index) or (Index < 0) or (Field[1] in ['+', '-', ' ']) then
        raise EBabelValueError.CreateFmt('Unsupported format field {%s}', [Field]);
      if Index > High(Args) then
        raise EBabelIndexError.CreateFmt('Replacement index %d out of range for positional args tuple', [Index]);
      Result := Result + Args[Index];
      I := J + 1;
    end
    else if Fmt[I] = '}' then
    begin
      if (I < Length(Fmt)) and (Fmt[I + 1] = '}') then
      begin
        Result := Result + '}';
        Inc(I, 2);
        Continue;
      end;
      raise EBabelValueError.Create('Single ''}'' encountered in format string');
    end
    else
    begin
      Result := Result + Fmt[I];
      Inc(I);
    end;
  end;
end;

const
  DigitZeros: array[0..75] of Cardinal = (
    $30, $660, $6F0, $7C0, $966, $9E6, $A66, $AE6, $B66, $BE6, $C66, $CE6, $D66, $DE6, $E50,
    $ED0, $F20, $1040, $1090, $17E0, $1810, $1946, $19D0, $1A80, $1A90, $1B50, $1BB0, $1C40,
    $1C50, $A620, $A8D0, $A900, $A9D0, $A9F0, $AA50, $ABF0, $FF10, $104A0, $10D30, $10D40,
    $11066, $110F0, $11136, $111D0, $112F0, $11450, $114D0, $11650, $116C0, $116D0, $116DA,
    $11730, $118E0, $11950, $11BF0, $11C50, $11D50, $11DA0, $11F50, $16130, $16A60, $16AC0,
    $16B50, $16D70, $1CCF0, $1D7CE, $1D7D8, $1D7E2, $1D7EC, $1D7F6, $1E140, $1E2F0, $1E4F0,
    $1E5F1, $1E950, $1FBF0);

type
  TCodeRange = record
    Lo, Hi: Cardinal;
  end;

const
  SymbolOrSeparatorRanges: array[0..242] of TCodeRange = (
    (Lo: $20; Hi: $20), (Lo: $24; Hi: $24), (Lo: $2B; Hi: $2B), (Lo: $3C; Hi: $3E), (Lo: $5E; Hi: $5E), (Lo: $60; Hi: $60), (Lo: $7C; Hi: $7C), (Lo: $7E; Hi: $7E),
    (Lo: $A0; Hi: $A0), (Lo: $A2; Hi: $A6), (Lo: $A8; Hi: $A9), (Lo: $AC; Hi: $AC), (Lo: $AE; Hi: $B1), (Lo: $B4; Hi: $B4), (Lo: $B8; Hi: $B8), (Lo: $D7; Hi: $D7),
    (Lo: $F7; Hi: $F7), (Lo: $2C2; Hi: $2C5), (Lo: $2D2; Hi: $2DF), (Lo: $2E5; Hi: $2EB), (Lo: $2ED; Hi: $2ED), (Lo: $2EF; Hi: $2FF), (Lo: $375; Hi: $375),
    (Lo: $384; Hi: $385), (Lo: $3F6; Hi: $3F6), (Lo: $482; Hi: $482), (Lo: $58D; Hi: $58F), (Lo: $606; Hi: $608), (Lo: $60B; Hi: $60B),
    (Lo: $60E; Hi: $60F), (Lo: $6DE; Hi: $6DE), (Lo: $6E9; Hi: $6E9), (Lo: $6FD; Hi: $6FE), (Lo: $7F6; Hi: $7F6), (Lo: $7FE; Hi: $7FF),
    (Lo: $888; Hi: $888), (Lo: $9F2; Hi: $9F3), (Lo: $9FA; Hi: $9FB), (Lo: $AF1; Hi: $AF1), (Lo: $B70; Hi: $B70), (Lo: $BF3; Hi: $BFA),
    (Lo: $C7F; Hi: $C7F), (Lo: $D4F; Hi: $D4F), (Lo: $D79; Hi: $D79), (Lo: $E3F; Hi: $E3F), (Lo: $F01; Hi: $F03), (Lo: $F13; Hi: $F13),
    (Lo: $F15; Hi: $F17), (Lo: $F1A; Hi: $F1F), (Lo: $F34; Hi: $F34), (Lo: $F36; Hi: $F36), (Lo: $F38; Hi: $F38), (Lo: $FBE; Hi: $FC5),
    (Lo: $FC7; Hi: $FCC), (Lo: $FCE; Hi: $FCF), (Lo: $FD5; Hi: $FD8), (Lo: $109E; Hi: $109F), (Lo: $1390; Hi: $1399), (Lo: $166D; Hi: $166D),
    (Lo: $1680; Hi: $1680), (Lo: $17DB; Hi: $17DB), (Lo: $1940; Hi: $1940), (Lo: $19DE; Hi: $19FF), (Lo: $1B61; Hi: $1B6A), (Lo: $1B74; Hi: $1B7C),
    (Lo: $1FBD; Hi: $1FBD), (Lo: $1FBF; Hi: $1FC1), (Lo: $1FCD; Hi: $1FCF), (Lo: $1FDD; Hi: $1FDF), (Lo: $1FED; Hi: $1FEF), (Lo: $1FFD; Hi: $1FFE),
    (Lo: $2000; Hi: $200A), (Lo: $2028; Hi: $2029), (Lo: $202F; Hi: $202F), (Lo: $2044; Hi: $2044), (Lo: $2052; Hi: $2052), (Lo: $205F; Hi: $205F),
    (Lo: $207A; Hi: $207C), (Lo: $208A; Hi: $208C), (Lo: $20A0; Hi: $20C0), (Lo: $2100; Hi: $2101), (Lo: $2103; Hi: $2106), (Lo: $2108; Hi: $2109),
    (Lo: $2114; Hi: $2114), (Lo: $2116; Hi: $2118), (Lo: $211E; Hi: $2123), (Lo: $2125; Hi: $2125), (Lo: $2127; Hi: $2127), (Lo: $2129; Hi: $2129),
    (Lo: $212E; Hi: $212E), (Lo: $213A; Hi: $213B), (Lo: $2140; Hi: $2144), (Lo: $214A; Hi: $214D), (Lo: $214F; Hi: $214F), (Lo: $218A; Hi: $218B),
    (Lo: $2190; Hi: $2307), (Lo: $230C; Hi: $2328), (Lo: $232B; Hi: $2429), (Lo: $2440; Hi: $244A), (Lo: $249C; Hi: $24E9), (Lo: $2500; Hi: $2767),
    (Lo: $2794; Hi: $27C4), (Lo: $27C7; Hi: $27E5), (Lo: $27F0; Hi: $2982), (Lo: $2999; Hi: $29D7), (Lo: $29DC; Hi: $29FB), (Lo: $29FE; Hi: $2B73),
    (Lo: $2B76; Hi: $2B95), (Lo: $2B97; Hi: $2BFF), (Lo: $2CE5; Hi: $2CEA), (Lo: $2E50; Hi: $2E51), (Lo: $2E80; Hi: $2E99), (Lo: $2E9B; Hi: $2EF3),
    (Lo: $2F00; Hi: $2FD5), (Lo: $2FF0; Hi: $3000), (Lo: $3004; Hi: $3004), (Lo: $3012; Hi: $3013), (Lo: $3020; Hi: $3020), (Lo: $3036; Hi: $3037),
    (Lo: $303E; Hi: $303F), (Lo: $309B; Hi: $309C), (Lo: $3190; Hi: $3191), (Lo: $3196; Hi: $319F), (Lo: $31C0; Hi: $31E5), (Lo: $31EF; Hi: $31EF),
    (Lo: $3200; Hi: $321E), (Lo: $322A; Hi: $3247), (Lo: $3250; Hi: $3250), (Lo: $3260; Hi: $327F), (Lo: $328A; Hi: $32B0), (Lo: $32C0; Hi: $33FF),
    (Lo: $4DC0; Hi: $4DFF), (Lo: $A490; Hi: $A4C6), (Lo: $A700; Hi: $A716), (Lo: $A720; Hi: $A721), (Lo: $A789; Hi: $A78A), (Lo: $A828; Hi: $A82B),
    (Lo: $A836; Hi: $A839), (Lo: $AA77; Hi: $AA79), (Lo: $AB5B; Hi: $AB5B), (Lo: $AB6A; Hi: $AB6B), (Lo: $FB29; Hi: $FB29), (Lo: $FBB2; Hi: $FBC2),
    (Lo: $FD40; Hi: $FD4F), (Lo: $FDCF; Hi: $FDCF), (Lo: $FDFC; Hi: $FDFF), (Lo: $FE62; Hi: $FE62), (Lo: $FE64; Hi: $FE66), (Lo: $FE69; Hi: $FE69),
    (Lo: $FF04; Hi: $FF04), (Lo: $FF0B; Hi: $FF0B), (Lo: $FF1C; Hi: $FF1E), (Lo: $FF3E; Hi: $FF3E), (Lo: $FF40; Hi: $FF40), (Lo: $FF5C; Hi: $FF5C),
    (Lo: $FF5E; Hi: $FF5E), (Lo: $FFE0; Hi: $FFE6), (Lo: $FFE8; Hi: $FFEE), (Lo: $FFFC; Hi: $FFFD), (Lo: $10137; Hi: $1013F),
    (Lo: $10179; Hi: $10189), (Lo: $1018C; Hi: $1018E), (Lo: $10190; Hi: $1019C), (Lo: $101A0; Hi: $101A0), (Lo: $101D0; Hi: $101FC),
    (Lo: $10877; Hi: $10878), (Lo: $10AC8; Hi: $10AC8), (Lo: $10D8E; Hi: $10D8F), (Lo: $1173F; Hi: $1173F), (Lo: $11FD5; Hi: $11FF1),
    (Lo: $16B3C; Hi: $16B3F), (Lo: $16B45; Hi: $16B45), (Lo: $1BC9C; Hi: $1BC9C), (Lo: $1CC00; Hi: $1CCEF), (Lo: $1CD00; Hi: $1CEB3),
    (Lo: $1CF50; Hi: $1CFC3), (Lo: $1D000; Hi: $1D0F5), (Lo: $1D100; Hi: $1D126), (Lo: $1D129; Hi: $1D164), (Lo: $1D16A; Hi: $1D16C),
    (Lo: $1D183; Hi: $1D184), (Lo: $1D18C; Hi: $1D1A9), (Lo: $1D1AE; Hi: $1D1EA), (Lo: $1D200; Hi: $1D241), (Lo: $1D245; Hi: $1D245),
    (Lo: $1D300; Hi: $1D356), (Lo: $1D6C1; Hi: $1D6C1), (Lo: $1D6DB; Hi: $1D6DB), (Lo: $1D6FB; Hi: $1D6FB), (Lo: $1D715; Hi: $1D715),
    (Lo: $1D735; Hi: $1D735), (Lo: $1D74F; Hi: $1D74F), (Lo: $1D76F; Hi: $1D76F), (Lo: $1D789; Hi: $1D789), (Lo: $1D7A9; Hi: $1D7A9),
    (Lo: $1D7C3; Hi: $1D7C3), (Lo: $1D800; Hi: $1D9FF), (Lo: $1DA37; Hi: $1DA3A), (Lo: $1DA6D; Hi: $1DA74), (Lo: $1DA76; Hi: $1DA83),
    (Lo: $1DA85; Hi: $1DA86), (Lo: $1E14F; Hi: $1E14F), (Lo: $1E2FF; Hi: $1E2FF), (Lo: $1ECAC; Hi: $1ECAC), (Lo: $1ECB0; Hi: $1ECB0),
    (Lo: $1ED2E; Hi: $1ED2E), (Lo: $1EEF0; Hi: $1EEF1), (Lo: $1F000; Hi: $1F02B), (Lo: $1F030; Hi: $1F093), (Lo: $1F0A0; Hi: $1F0AE),
    (Lo: $1F0B1; Hi: $1F0BF), (Lo: $1F0C1; Hi: $1F0CF), (Lo: $1F0D1; Hi: $1F0F5), (Lo: $1F10D; Hi: $1F1AD), (Lo: $1F1E6; Hi: $1F202),
    (Lo: $1F210; Hi: $1F23B), (Lo: $1F240; Hi: $1F248), (Lo: $1F250; Hi: $1F251), (Lo: $1F260; Hi: $1F265), (Lo: $1F300; Hi: $1F6D7),
    (Lo: $1F6DC; Hi: $1F6EC), (Lo: $1F6F0; Hi: $1F6FC), (Lo: $1F700; Hi: $1F776), (Lo: $1F77B; Hi: $1F7D9), (Lo: $1F7E0; Hi: $1F7EB),
    (Lo: $1F7F0; Hi: $1F7F0), (Lo: $1F800; Hi: $1F80B), (Lo: $1F810; Hi: $1F847), (Lo: $1F850; Hi: $1F859), (Lo: $1F860; Hi: $1F887),
    (Lo: $1F890; Hi: $1F8AD), (Lo: $1F8B0; Hi: $1F8BB), (Lo: $1F8C0; Hi: $1F8C1), (Lo: $1F900; Hi: $1FA53), (Lo: $1FA60; Hi: $1FA6D),
    (Lo: $1FA70; Hi: $1FA7C), (Lo: $1FA80; Hi: $1FA89), (Lo: $1FA8F; Hi: $1FAC6), (Lo: $1FACE; Hi: $1FADC), (Lo: $1FADF; Hi: $1FAE9),
    (Lo: $1FAF0; Hi: $1FAF8), (Lo: $1FB00; Hi: $1FB92), (Lo: $1FB94; Hi: $1FBEF));

function IsSymbolOrSeparator(C: Cardinal): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := High(SymbolOrSeparatorRanges);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if C < SymbolOrSeparatorRanges[Mid].Lo then
      Hi := Mid - 1
    else if C > SymbolOrSeparatorRanges[Mid].Hi then
      Lo := Mid + 1
    else
      Exit(True);
  end;
  Result := False;
end;

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
