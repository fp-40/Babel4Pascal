{ babel.numbers - formatting and parsing of numbers, currencies and
  percentages, as Python Babel's babel.numbers.

  FormatDecimal(1234.5, 'es_PE') gives '1,234.5'; FormatCurrency(1234.5,
  'PEN', 'es_PE') gives 'S/ 1,234.50'. The results are Babel's, character
  for character, including where Babel departs from CLDR: the percent and
  minus signs of a pattern are written as they are (not localized), and
  digits are always ASCII (the numbering system only selects the
  separators).

  Numbers. A TNumber is made implicitly from an Int64, a Double, a
  TDecimal or a string, and remembers which, because Babel's results
  depend on it: a Double is read as Python reads a float (2.675 is
  2.675), and the plural rule sees 1.0 as the integer 1 but
  TDecimal('1.0') as having one fraction digit ("1.00 US dollar" against
  "1.00 US dollars"). Numbers are computed with Python's decimal rules
  (babel.decimal), so a number with more than 28 significant digits after
  scaling fails with EBabelDecimalError, as in Babel.

  Options. The optional parameters of Babel's functions are fields of an
  options record: NumberOptions, CurrencyOptions and CompactOptions return
  Babel's defaults, and the With* methods return a changed copy:

    FormatDecimal(X, 'en', NumberOptions.WithGroupSeparator(False));
    FormatCurrency(X, 'USD', 'en', CurrencyOptions.WithFormatType('accounting'));

  A record that was not made by these functions has False and '' where
  Babel's defaults are True and 'latn': always start from them.

  An empty Format means the locale's pattern (Babel's None); a currency
  of '' is Babel's None.

  Threading: everything here only reads shared data. }
unit babel.numbers;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Math, babel.errors, babel.decimal, babel.localedata, babel.plural, babel.core,
  babel.pystr;

type
  EUnknownCurrencyError = class(EBabelError)
  public
    Identifier: string;
    constructor CreateFor(const AIdentifier: string);
  end;
  EUnsupportedNumberingSystemError = class(EBabelError);
  EUnknownCurrencyFormatError = class(EBabelKeyError);
  ENumberFormatError = class(EBabelValueError)
  public
    { Properly formatted numbers derived from the input (parse_decimal
      with Strict). }
    Suggestions: TStringArray;
    constructor CreateWith(const Msg: string; const ASuggestions: TStringArray);
  end;

  TNumberKind = (nkInt, nkFloat, nkDecimal, nkString);

  { A number as a caller gives it: Babel's int, float, Decimal or str. }
  TNumber = record
  private
    FKind: TNumberKind;
    FInt: Int64;
    FFloat: Double;
    FDecimal: TDecimal;
    FString: string;
  public
    class operator :=(V: Int64): TNumber;
    class operator :=(V: Double): TNumber;
    class operator :=(const V: TDecimal): TNumber;
    class operator :=(const V: string): TNumber;
    property Kind: TNumberKind read FKind;
    { Decimal(str(value)), as Babel converts a number before formatting;
      a TDecimal stays as it is. Raises EBabelDecimalError for a string
      that is not a number. }
    function ToDecimal: TDecimal;
    { The plural category of the number under Rule (Babel calls the rule
      with the value as given; a string raises EBabelTypeError). }
    function PluralCategory(const Rule: TPluralRule): string;
  end;

  { format_decimal, format_percent and format_scientific options. }
  TNumberOptions = record
    Format: string;                 { '' = the locale's pattern }
    DecimalQuantization: Boolean;   { True }
    GroupSeparator: Boolean;        { True (format_scientific has none) }
    NumberingSystem: string;        { 'latn'; 'default' = the locale's }
    function WithFormat(const Value: string): TNumberOptions;
    function WithDecimalQuantization(Value: Boolean): TNumberOptions;
    function WithGroupSeparator(Value: Boolean): TNumberOptions;
    function WithNumberingSystem(const Value: string): TNumberOptions;
  end;

  { format_currency options. }
  TCurrencyOptions = record
    Format: string;                 { '' = the locale's pattern }
    CurrencyDigits: Boolean;        { True: the currency's fraction digits }
    FormatType: string;             { 'standard', 'accounting' or 'name' }
    DecimalQuantization: Boolean;   { True }
    GroupSeparator: Boolean;        { True }
    NumberingSystem: string;        { 'latn' }
    function WithFormat(const Value: string): TCurrencyOptions;
    function WithCurrencyDigits(Value: Boolean): TCurrencyOptions;
    function WithFormatType(const Value: string): TCurrencyOptions;
    function WithDecimalQuantization(Value: Boolean): TCurrencyOptions;
    function WithGroupSeparator(Value: Boolean): TCurrencyOptions;
    function WithNumberingSystem(const Value: string): TCurrencyOptions;
  end;

  { format_compact_decimal and format_compact_currency options. }
  TCompactOptions = record
    FormatType: string;             { 'short' or 'long' (currency: 'short') }
    FractionDigits: Integer;        { 0 }
    NumberingSystem: string;        { 'latn' }
    function WithFormatType(const Value: string): TCompactOptions;
    function WithFractionDigits(Value: Integer): TCompactOptions;
    function WithNumberingSystem(const Value: string): TCompactOptions;
  end;

  { parse_number and parse_decimal options. }
  TParseOptions = record
    StrictMode: Boolean;            { Babel's strict (False; parse_decimal only);
                                      Strict is a reserved word here }
    NumberingSystem: string;        { 'latn' }
    function WithStrict(Value: Boolean): TParseOptions;
    function WithNumberingSystem(const Value: string): TParseOptions;
  end;

  { get_territory_currencies options. A date of 0 is Babel's None: the
    start date defaults to today and the end date to the start date. }
  TTerritoryCurrencyOptions = record
    StartDate, EndDate: TDateTime;
    Tender: Boolean;                { True }
    NonTender: Boolean;             { False }
    function WithStartDate(Value: TDateTime): TTerritoryCurrencyOptions;
    function WithEndDate(Value: TDateTime): TTerritoryCurrencyOptions;
    function WithTender(Value: Boolean): TTerritoryCurrencyOptions;
    function WithNonTender(Value: Boolean): TTerritoryCurrencyOptions;
  end;

  { One currency of a territory (include_details=True); a date of 0 is
    None. }
  TCurrencyPeriod = record
    Currency: string;
    FromDate, ToDate: TDateTime;
    Tender: Boolean;
  end;
  TCurrencyPeriods = array of TCurrencyPeriod;

  TIntPair = record
    Min, Max: Integer;
  end;

  { NumberPattern.apply options. }
  TApplyOptions = record
    Currency: string;               { '' = None }
    CurrencyDigits: Boolean;        { True }
    DecimalQuantization: Boolean;   { True }
    GroupSeparator: Boolean;        { True }
    NumberingSystem: string;        { 'latn' }
  end;

  { A parsed number pattern (Babel's NumberPattern). }
  TNumberPattern = record
    Pattern: string;
    PosPrefix, NegPrefix, PosSuffix, NegSuffix: string;
    NumberPattern: string;           { the number part, without the exponent }
    Grouping: TIntPair;              { Min = primary, Max = secondary size }
    IntPrec, FracPrec: TIntPair;
    HasExp: Boolean;                 { exp_prec is not None }
    ExpPrec: TIntPair;
    ExpPlus: Boolean;
    Scale: Integer;                  { 0, 2 (percent) or 3 (per mille) }
    function Apply(const Value: TNumber; const Locale: TLocale; const Options: TApplyOptions): string;
  end;

function NumberOptions: TNumberOptions;
function CurrencyOptions: TCurrencyOptions;
function CompactOptions: TCompactOptions;
function ParseOptions: TParseOptions;
function TerritoryCurrencyOptions: TTerritoryCurrencyOptions;
function ApplyOptions: TApplyOptions;

{ Currencies }
{ The ISO 4217 codes known to the locale, or (no locale) every currency
  of the global data; sorted (Babel returns a set). }
function ListCurrencies: TStringArray; overload;
function ListCurrencies(const Locale: TLocale): TStringArray; overload;
{ Raises EUnknownCurrencyError when the code is not listed. }
procedure ValidateCurrency(const Currency: string); overload;
procedure ValidateCurrency(const Currency: string; const Locale: TLocale); overload;
function IsCurrency(const Currency: string): Boolean; overload;
function IsCurrency(const Currency: string; const Locale: TLocale): Boolean; overload;
{ The code in upper case when it is a currency; '' otherwise. }
function NormalizeCurrency(const Currency: string): string; overload;
function NormalizeCurrency(const Currency: string; const Locale: TLocale): string; overload;
{ The currency's name; with Count, the plural form for that count. }
function GetCurrencyName(const Currency: string; const Locale: TLocale): string; overload;
function GetCurrencyName(const Currency: string; const Count: TNumber; const Locale: TLocale): string; overload;
function GetCurrencySymbol(const Currency: string; const Locale: TLocale): string;
{ The currency's number of fraction digits (2 when not listed). }
function GetCurrencyPrecision(const Currency: string): Integer;
(* The pattern that joins number and currency name ('{0} {1}'). *)
function GetCurrencyUnitPattern(const Currency: string; const Locale: TLocale): string; overload;
function GetCurrencyUnitPattern(const Currency: string; const Count: TNumber; const Locale: TLocale): string; overload;
function GetTerritoryCurrencies(const Territory: string): TStringArray; overload;
function GetTerritoryCurrencies(const Territory: string; const Options: TTerritoryCurrencyOptions): TStringArray; overload;
function GetTerritoryCurrencyDetails(const Territory: string; const Options: TTerritoryCurrencyOptions): TCurrencyPeriods;

{ Symbols of a numbering system ('latn' by default; 'default' = the
  locale's). Raise EUnsupportedNumberingSystemError for a system the
  locale does not have. }
function GetDecimalSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetPlusSignSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetMinusSignSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetExponentialSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetGroupSymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;
function GetInfinitySymbol(const Locale: TLocale; const NumberingSystem: string = 'latn'): string;

{ get_decimal_precision: the number of fraction digits of the normalized
  number. get_decimal_quantum: 10 ** -Precision. }
function GetDecimalPrecision(const Number: TDecimal): Integer;
function GetDecimalQuantum(Precision: Int64): TDecimal;

{ Formatting }
function FormatDecimal(const Number: TNumber; const Locale: TLocale): string; overload;
function FormatDecimal(const Number: TNumber; const Locale: TLocale; const Options: TNumberOptions): string; overload;
function FormatCompactDecimal(const Number: TNumber; const Locale: TLocale): string; overload;
function FormatCompactDecimal(const Number: TNumber; const Locale: TLocale; const Options: TCompactOptions): string; overload;
function FormatCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale): string; overload;
function FormatCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale;
  const Options: TCurrencyOptions): string; overload;
function FormatCompactCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale): string; overload;
function FormatCompactCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale;
  const Options: TCompactOptions): string; overload;
function FormatPercent(const Number: TNumber; const Locale: TLocale): string; overload;
function FormatPercent(const Number: TNumber; const Locale: TLocale; const Options: TNumberOptions): string; overload;
function FormatScientific(const Number: TNumber; const Locale: TLocale): string; overload;
function FormatScientific(const Number: TNumber; const Locale: TLocale; const Options: TNumberOptions): string; overload;

{ Parsing }
{ parse_number: an integer written in the locale's format ('1,099' in
  en). Raises ENumberFormatError. Beyond Int64 raises EBabelOverflowError
  (Python's int has no limit). }
function ParseNumber(const S: string; const Locale: TLocale): Int64; overload;
function ParseNumber(const S: string; const Locale: TLocale; const Options: TParseOptions): Int64; overload;
{ parse_decimal: a decimal number written in the locale's format. With
  Strict, a misplaced group symbol raises ENumberFormatError with
  suggestions. }
function ParseDecimal(const S: string; const Locale: TLocale): TDecimal; overload;
function ParseDecimal(const S: string; const Locale: TLocale; const Options: TParseOptions): TDecimal; overload;

{ Patterns }
{ parse_grouping: the primary and secondary group sizes of the integer
  part of a pattern (1000, 1000 when it has no ','). }
function ParseGrouping(const P: string): TIntPair;
{ parse_pattern. Raises EBabelValueError for a pattern that mixes '@'
  with '.' and '0'. }
function ParseNumberPattern(const Pattern: string): TNumberPattern;

implementation

{ ---- small helpers with Python's string semantics ---- }

{ s[-n:] (all of s when n = 0) }
function PyTail(const S: string; N: Integer): string;
begin
  if (N <= 0) or (N >= Length(S)) then
    Result := S
  else
    Result := Copy(S, Length(S) - N + 1, N);
end;

{ s[:-n] ('' when n = 0) }
function PyDropTail(const S: string; N: Integer): string;
begin
  if (N <= 0) or (N >= Length(S)) then
    Result := ''
  else
    Result := Copy(S, 1, Length(S) - N);
end;

{ s.rstrip(ch) }
function RStripChar(const S: string; C: Char): string;
var
  N: Integer;
begin
  N := Length(S);
  while (N > 0) and (S[N] = C) do
    Dec(N);
  Result := Copy(S, 1, N);
end;

(* str.format for a pattern with positional fields '{0}', '{1}' and the
  escapes '{{' and '}}' (the CLDR patterns use nothing else). *)
function PyFormat2(const Pattern, A0, A1: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(Pattern) do
  begin
    if (Pattern[I] = '{') and (I < Length(Pattern)) and (Pattern[I + 1] = '{') then
    begin
      Result := Result + '{';
      Inc(I, 2);
    end
    else if (Pattern[I] = '}') and (I < Length(Pattern)) and (Pattern[I + 1] = '}') then
    begin
      Result := Result + '}';
      Inc(I, 2);
    end
    else if (Pattern[I] = '{') and (I + 2 <= Length(Pattern)) and (Pattern[I + 2] = '}') and
            (Pattern[I + 1] in ['0', '1']) then
    begin
      if Pattern[I + 1] = '0' then
        Result := Result + A0
      else
        Result := Result + A1;
      Inc(I, 3);
    end
    else
    begin
      Result := Result + Pattern[I];
      Inc(I);
    end;
  end;
end;

function SortedStrings(const A: TStringArray): TStringArray;
var
  I, J: Integer;
  T: string;
begin
  Result := Copy(A);
  for I := 1 to High(Result) do
  begin
    T := Result[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(Result[J], T) > 0) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := T;
  end;
end;

function MapKeys(M: TCLDRValue): TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, M.Count);
  for I := 0 to M.Count - 1 do
    Result[I] := M.Keys(I).AsString;
end;

{ ---- exceptions ---- }

constructor EUnknownCurrencyError.CreateFor(const AIdentifier: string);
begin
  inherited CreateFmt('Unknown currency ''%s''.', [AIdentifier]);
  Identifier := AIdentifier;
end;

constructor ENumberFormatError.CreateWith(const Msg: string; const ASuggestions: TStringArray);
begin
  inherited Create(Msg);
  Suggestions := ASuggestions;
end;

{ ---- TNumber ---- }

class operator TNumber.:=(V: Int64): TNumber;
begin
  Result := Default(TNumber);
  Result.FKind := nkInt;
  Result.FInt := V;
end;

class operator TNumber.:=(V: Double): TNumber;
begin
  Result := Default(TNumber);
  Result.FKind := nkFloat;
  Result.FFloat := V;
end;

class operator TNumber.:=(const V: TDecimal): TNumber;
begin
  Result := Default(TNumber);
  Result.FKind := nkDecimal;
  Result.FDecimal := V;
end;

class operator TNumber.:=(const V: string): TNumber;
begin
  Result := Default(TNumber);
  Result.FKind := nkString;
  Result.FString := V;
end;

function TNumber.ToDecimal: TDecimal;
begin
  case FKind of
    nkInt: Result := TDecimal.FromInt64(FInt);
    nkFloat: Result := TDecimal.FromDouble(FFloat);
    nkDecimal: Result := FDecimal;
  else
    Result := TDecimal.Parse(FString);
  end;
end;

function TNumber.PluralCategory(const Rule: TPluralRule): string;
begin
  case FKind of
    nkInt: Result := Rule.Evaluate(FInt);
    nkFloat: Result := Rule.Evaluate(FFloat);
    nkDecimal: Result := Rule.Evaluate(FDecimal);
  else
    raise EBabelTypeError.Create('bad operand type for abs(): ''str''');
  end;
end;

{ float(s) for a string, with Python's float() syntax. }
function PyFloatOf(const S: string): Double;
var
  T, L: string;
  Code: Integer;
  D: TDecimal;
begin
  T := AsciiDigits(PyStrip(S));
  L := LowerCase(T);
  if (L = 'inf') or (L = '+inf') or (L = 'infinity') or (L = '+infinity') then
    Exit(Infinity);
  if (L = '-inf') or (L = '-infinity') then
    Exit(NegInfinity);
  if (L = 'nan') or (L = '+nan') or (L = '-nan') then
    Exit(NaN);
  { the same syntax as Decimal for finite values (digits, '.', exponent,
    underscores); FPC's Val reads the normalized form digits'E'exponent }
  if not TDecimal.TryParse(T, D) or not D.IsFinite then
    raise EBabelValueError.CreateFmt('could not convert string to float: ''%s''', [S]);
  L := D.Digits + 'E' + IntToStr(D.Exponent);
  if D.Negative then
    L := '-' + L;
  Val(L, Result, Code);
  if Code <> 0 then
    raise EBabelValueError.CreateFmt('could not convert string to float: ''%s''', [S]);
end;

{ ---- option records ---- }

function NumberOptions: TNumberOptions;
begin
  Result := Default(TNumberOptions);
  Result.DecimalQuantization := True;
  Result.GroupSeparator := True;
  Result.NumberingSystem := 'latn';
end;

function TNumberOptions.WithFormat(const Value: string): TNumberOptions;
begin
  Result := Self;
  Result.Format := Value;
end;

function TNumberOptions.WithDecimalQuantization(Value: Boolean): TNumberOptions;
begin
  Result := Self;
  Result.DecimalQuantization := Value;
end;

function TNumberOptions.WithGroupSeparator(Value: Boolean): TNumberOptions;
begin
  Result := Self;
  Result.GroupSeparator := Value;
end;

function TNumberOptions.WithNumberingSystem(const Value: string): TNumberOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function CurrencyOptions: TCurrencyOptions;
begin
  Result := Default(TCurrencyOptions);
  Result.CurrencyDigits := True;
  Result.FormatType := 'standard';
  Result.DecimalQuantization := True;
  Result.GroupSeparator := True;
  Result.NumberingSystem := 'latn';
end;

function TCurrencyOptions.WithFormat(const Value: string): TCurrencyOptions;
begin
  Result := Self;
  Result.Format := Value;
end;

function TCurrencyOptions.WithCurrencyDigits(Value: Boolean): TCurrencyOptions;
begin
  Result := Self;
  Result.CurrencyDigits := Value;
end;

function TCurrencyOptions.WithFormatType(const Value: string): TCurrencyOptions;
begin
  Result := Self;
  Result.FormatType := Value;
end;

function TCurrencyOptions.WithDecimalQuantization(Value: Boolean): TCurrencyOptions;
begin
  Result := Self;
  Result.DecimalQuantization := Value;
end;

function TCurrencyOptions.WithGroupSeparator(Value: Boolean): TCurrencyOptions;
begin
  Result := Self;
  Result.GroupSeparator := Value;
end;

function TCurrencyOptions.WithNumberingSystem(const Value: string): TCurrencyOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function CompactOptions: TCompactOptions;
begin
  Result := Default(TCompactOptions);
  Result.FormatType := 'short';
  Result.FractionDigits := 0;
  Result.NumberingSystem := 'latn';
end;

function TCompactOptions.WithFormatType(const Value: string): TCompactOptions;
begin
  Result := Self;
  Result.FormatType := Value;
end;

function TCompactOptions.WithFractionDigits(Value: Integer): TCompactOptions;
begin
  Result := Self;
  Result.FractionDigits := Value;
end;

function TCompactOptions.WithNumberingSystem(const Value: string): TCompactOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function ParseOptions: TParseOptions;
begin
  Result := Default(TParseOptions);
  Result.NumberingSystem := 'latn';
end;

function TParseOptions.WithStrict(Value: Boolean): TParseOptions;
begin
  Result := Self;
  Result.StrictMode := Value;
end;

function TParseOptions.WithNumberingSystem(const Value: string): TParseOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function TerritoryCurrencyOptions: TTerritoryCurrencyOptions;
begin
  Result := Default(TTerritoryCurrencyOptions);
  Result.Tender := True;
end;

function TTerritoryCurrencyOptions.WithStartDate(Value: TDateTime): TTerritoryCurrencyOptions;
begin
  Result := Self;
  Result.StartDate := Value;
end;

function TTerritoryCurrencyOptions.WithEndDate(Value: TDateTime): TTerritoryCurrencyOptions;
begin
  Result := Self;
  Result.EndDate := Value;
end;

function TTerritoryCurrencyOptions.WithTender(Value: Boolean): TTerritoryCurrencyOptions;
begin
  Result := Self;
  Result.Tender := Value;
end;

function TTerritoryCurrencyOptions.WithNonTender(Value: Boolean): TTerritoryCurrencyOptions;
begin
  Result := Self;
  Result.NonTender := Value;
end;

function ApplyOptions: TApplyOptions;
begin
  Result := Default(TApplyOptions);
  Result.CurrencyDigits := True;
  Result.DecimalQuantization := True;
  Result.GroupSeparator := True;
  Result.NumberingSystem := 'latn';
end;

{ ---- currencies ---- }

function ListCurrencies: TStringArray;
begin
  Result := SortedStrings(MapKeys(GetGlobal('all_currencies')));
end;

function ListCurrencies(const Locale: TLocale): TStringArray;
begin
  Result := SortedStrings(MapKeys(Locale.Currencies));
end;

procedure ValidateCurrency(const Currency: string);
begin
  if not GetGlobal('all_currencies').Has(Currency) then
    raise EUnknownCurrencyError.CreateFor(Currency);
end;

procedure ValidateCurrency(const Currency: string; const Locale: TLocale);
begin
  if not Locale.Currencies.Has(Currency) then
    raise EUnknownCurrencyError.CreateFor(Currency);
end;

function IsCurrency(const Currency: string): Boolean;
begin
  Result := (Currency <> '') and GetGlobal('all_currencies').Has(Currency);
end;

function IsCurrency(const Currency: string; const Locale: TLocale): Boolean;
begin
  Result := (Currency <> '') and Locale.Currencies.Has(Currency);
end;

function NormalizeCurrency(const Currency: string): string;
begin
  Result := UpperCase(Currency);
  if not IsCurrency(Result) then
    Result := '';
end;

function NormalizeCurrency(const Currency: string; const Locale: TLocale): string;
begin
  Result := UpperCase(Currency);
  if not IsCurrency(Result, Locale) then
    Result := '';
end;

function GetCurrencyName(const Currency: string; const Locale: TLocale): string;
begin
  Result := Locale.Currencies.Str(Currency, Currency);
end;

function GetCurrencyName(const Currency: string; const Count: TNumber; const Locale: TLocale): string;
var
  Form: string;
  Names, ForCurrency: TCLDRValue;
begin
  try
    Form := Count.PluralCategory(Locale.PluralForm);
  except
    on EBabelOverflowError do Form := 'other';
    on EBabelValueError do Form := 'other';
  end;
  Names := Locale.Data.Get('currency_names_plural');
  if Names = nil then
    raise EBabelKeyError.Create('currency_names_plural');
  ForCurrency := Names.Get(Currency);
  if ForCurrency <> nil then
  begin
    if ForCurrency.Has(Form) then
      Exit(ForCurrency.Str(Form));
    if ForCurrency.Has('other') then
      Exit(ForCurrency.Str('other'));
  end;
  Result := Locale.Currencies.Str(Currency, Currency);
end;

function GetCurrencySymbol(const Currency: string; const Locale: TLocale): string;
begin
  Result := Locale.CurrencySymbols.Str(Currency, Currency);
end;

function GetCurrencyPrecision(const Currency: string): Integer;
var
  F, V: TCLDRValue;
begin
  F := GetGlobal('currency_fractions');
  V := F.Get(Currency);
  if V = nil then
    V := F.Get('DEFAULT');
  Result := V.Items(0).AsInteger;
end;

function UnitPatterns(const Locale: TLocale): TCLDRValue;
begin
  Result := Locale.Data.Get('currency_unit_patterns');
  if Result = nil then
    raise EBabelKeyError.Create('currency_unit_patterns');
end;

function GetCurrencyUnitPattern(const Currency: string; const Locale: TLocale): string;
var
  P: TCLDRValue;
begin
  P := UnitPatterns(Locale);
  if not P.Has('other') then
    raise EBabelKeyError.Create('other');
  Result := P.Str('other');
end;

function GetCurrencyUnitPattern(const Currency: string; const Count: TNumber; const Locale: TLocale): string;
var
  P: TCLDRValue;
  Form: string;
begin
  Form := Count.PluralCategory(Locale.PluralForm);
  P := UnitPatterns(Locale);
  if P.Has(Form) then
    Exit(P.Str(Form));
  Result := GetCurrencyUnitPattern(Currency, Locale);
end;

function DateOfData(V: TCLDRValue): TDateTime;
begin
  if (V = nil) or (V.Kind = ckNone) then
    Exit(0);
  Result := EncodeDate(V.Items(0).AsInteger, V.Items(1).AsInteger, V.Items(2).AsInteger);
end;

function GetTerritoryCurrencyDetails(const Territory: string; const Options: TTerritoryCurrencyOptions): TCurrencyPeriods;
var
  StartDate, EndDate, F, T: TDateTime;
  Curs, C: TCLDRValue;
  I: Integer;
  IsTender, Active: Boolean;
  P: TCurrencyPeriod;
begin
  Result := nil;
  StartDate := Options.StartDate;
  if StartDate = 0 then
    StartDate := Date
  else
    StartDate := Int(StartDate);
  EndDate := Options.EndDate;
  if EndDate = 0 then
    EndDate := StartDate
  else
    EndDate := Int(EndDate);
  Curs := GetGlobal('territory_currencies').Get(UpperCase(Territory));
  if Curs = nil then
    Exit;
  for I := 0 to Curs.Count - 1 do
  begin
    C := Curs.Items(I);
    F := DateOfData(C.Items(1));
    T := DateOfData(C.Items(2));
    IsTender := C.Items(3).AsBoolean;
    Active := ((F = 0) or (F <= EndDate)) and ((T = 0) or (T >= StartDate));
    if ((IsTender and Options.Tender) or (not IsTender and Options.NonTender)) and Active then
    begin
      P.Currency := C.Items(0).AsString;
      P.FromDate := F;
      P.ToDate := T;
      P.Tender := IsTender;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := P;
    end;
  end;
end;

function GetTerritoryCurrencies(const Territory: string): TStringArray;
begin
  Result := GetTerritoryCurrencies(Territory, TerritoryCurrencyOptions);
end;

function GetTerritoryCurrencies(const Territory: string; const Options: TTerritoryCurrencyOptions): TStringArray;
var
  D: TCurrencyPeriods;
  I: Integer;
begin
  D := GetTerritoryCurrencyDetails(Territory, Options);
  Result := nil;
  SetLength(Result, Length(D));
  for I := 0 to High(D) do
    Result[I] := D[I].Currency;
end;

{ ---- symbols ---- }

function NumberSymbols(const Locale: TLocale; const NumberingSystem: string): TCLDRValue;
var
  NS: string;
begin
  NS := NumberingSystem;
  if NS = 'default' then
    NS := Locale.DefaultNumberingSystem;
  Result := Locale.NumberSymbols.Get(NS);
  if Result = nil then
    raise EUnsupportedNumberingSystemError.CreateFmt('Unknown numbering system %s for Locale %s.',
      [NS, Locale.ToString]);
end;

function GetDecimalSymbol(const Locale: TLocale; const NumberingSystem: string): string;
begin
  Result := NumberSymbols(Locale, NumberingSystem).Str('decimal', '.');
end;

function GetPlusSignSymbol(const Locale: TLocale; const NumberingSystem: string): string;
begin
  Result := NumberSymbols(Locale, NumberingSystem).Str('plusSign', '+');
end;

function GetMinusSignSymbol(const Locale: TLocale; const NumberingSystem: string): string;
begin
  Result := NumberSymbols(Locale, NumberingSystem).Str('minusSign', '-');
end;

function GetExponentialSymbol(const Locale: TLocale; const NumberingSystem: string): string;
begin
  Result := NumberSymbols(Locale, NumberingSystem).Str('exponential', 'E');
end;

function GetGroupSymbol(const Locale: TLocale; const NumberingSystem: string): string;
begin
  Result := NumberSymbols(Locale, NumberingSystem).Str('group', ',');
end;

function GetInfinitySymbol(const Locale: TLocale; const NumberingSystem: string): string;
begin
  Result := NumberSymbols(Locale, NumberingSystem).Str('infinity', #$E2#$88#$9E);
end;

function GetDecimalPrecision(const Number: TDecimal): Integer;
var
  N: TDecimal;
begin
  N := Number.Normalize;
  if (not N.IsFinite) or (N.Exponent >= 0) then
    Exit(0);
  Result := -N.Exponent;
end;

function GetDecimalQuantum(Precision: Int64): TDecimal;
begin
  Result := TDecimal.Pow10(-Precision);
end;

{ ---- patterns ---- }
function ParseGrouping(const P: string): TIntPair;
var
  C: TCodePoints;
  Width, G1, G2, I: Integer;
begin
  { Python counts characters: work on code points. }
  C := CodePoints(P);
  Width := Length(C);
  G1 := -1;
  for I := Width - 1 downto 0 do
    if C[I] = Ord(',') then
    begin
      G1 := I;
      Break;
    end;
  if G1 = -1 then
  begin
    Result.Min := 1000;
    Result.Max := 1000;
    Exit;
  end;
  G1 := Width - G1 - 1;
  { p[:-g1 - 1].rfind(',') }
  G2 := -1;
  for I := Width - G1 - 2 downto 0 do
    if C[I] = Ord(',') then
    begin
      G2 := I;
      Break;
    end;
  if G2 = -1 then
  begin
    Result.Min := G1;
    Result.Max := G1;
    Exit;
  end;
  Result.Min := G1;
  Result.Max := Width - G1 - G2 - 2;
end;

{ _number_pattern_re: prefix ((?:[^'0-9@#.,]|'[^']*')*), number
  ([0-9@#.,E+]*) and suffix (.* : up to a line break). }
procedure MatchNumber(const P: string; out Prefix, Number, Suffix: string);
var
  I, J: Integer;
begin
  I := 1;
  while I <= Length(P) do
  begin
    if P[I] = '''' then
    begin
      J := I + 1;
      while (J <= Length(P)) and (P[J] <> '''') do
        Inc(J);
      if J > Length(P) then
        Break;            { an unclosed quote ends the prefix }
      I := J + 1;
    end
    else if P[I] in ['0'..'9', '@', '#', '.', ','] then
      Break
    else
      Inc(I);
  end;
  Prefix := Copy(P, 1, I - 1);
  J := I;
  while (J <= Length(P)) and (P[J] in ['0'..'9', '@', '#', '.', ',', 'E', '+']) do
    Inc(J);
  Number := Copy(P, I, J - I);
  I := J;
  while (J <= Length(P)) and (P[J] <> #10) do
    Inc(J);
  Suffix := Copy(P, I, J - I);
end;

function ParsePrecision(const P: string): TIntPair;
var
  C: Char;
begin
  Result.Min := 0;
  Result.Max := 0;
  for C in P do
    if C in ['@', '0'] then
    begin
      Inc(Result.Min);
      Inc(Result.Max);
    end
    else if C = '#' then
      Inc(Result.Max)
    else if C = ',' then
      Continue
    else
      Break;
end;

function ParseNumberPattern(const Pattern: string): TNumberPattern;
var
  PosPattern, NegPattern, Number, Dummy, Exp, IntegerPart, Fraction: string;
  P: Integer;
begin
  Result := Default(TNumberPattern);
  Result.Pattern := Pattern;
  P := Pos(';', Pattern);
  if P > 0 then
  begin
    PosPattern := Copy(Pattern, 1, P - 1);
    NegPattern := Copy(Pattern, P + 1, MaxInt);
    MatchNumber(PosPattern, Result.PosPrefix, Number, Result.PosSuffix);
    MatchNumber(NegPattern, Result.NegPrefix, Dummy, Result.NegSuffix);
  end
  else
  begin
    MatchNumber(Pattern, Result.PosPrefix, Number, Result.PosSuffix);
    Result.NegPrefix := '-' + Result.PosPrefix;
    Result.NegSuffix := Result.PosSuffix;
  end;
  P := Pos('E', Number);
  if P > 0 then
  begin
    Exp := Copy(Number, P + 1, MaxInt);
    Number := Copy(Number, 1, P - 1);
  end
  else
    Exp := '';
  if (Pos('@', Number) > 0) and (Pos('.', Number) > 0) and (Pos('0', Number) > 0) then
    raise EBabelValueError.Create('Significant digit patterns can not contain "@" or "0"');
  P := 0;
  if Pos('.', Number) > 0 then
  begin
    P := Length(Number);
    while Number[P] <> '.' do
      Dec(P);
    IntegerPart := Copy(Number, 1, P - 1);
    Fraction := Copy(Number, P + 1, MaxInt);
  end
  else
  begin
    IntegerPart := Number;
    Fraction := '';
  end;
  Result.IntPrec := ParsePrecision(IntegerPart);
  Result.FracPrec := ParsePrecision(Fraction);
  if Exp <> '' then
  begin
    Result.HasExp := True;
    Result.ExpPlus := Exp[1] = '+';
    while (Exp <> '') and (Exp[1] = '+') do
      Delete(Exp, 1, 1);
    Result.ExpPrec := ParsePrecision(Exp);
  end;
  Result.Grouping := ParseGrouping(IntegerPart);
  Result.NumberPattern := Number;
  if (Pos('%', Result.PosPrefix + Result.NegPrefix + Result.PosSuffix + Result.NegSuffix) > 0) then
    Result.Scale := 2
  else if Pos(#$E2#$80#$B0, Result.PosPrefix + Result.NegPrefix + Result.PosSuffix + Result.NegSuffix) > 0 then
    Result.Scale := 3;   { per mille }
end;

{ ---- NumberPattern.apply ---- }

function FormatInt(const Pat: TNumberPattern; const Value: string; Min: Integer;
  const Locale: TLocale; const NumberingSystem: string): string;
var
  V, Symbol: string;
  GSize: Integer;
begin
  V := Value;
  if Length(V) < Min then
    V := StringOfChar('0', Min - Length(V)) + V;
  GSize := Pat.Grouping.Min;
  Result := '';
  Symbol := GetGroupSymbol(Locale, NumberingSystem);
  while Length(V) > GSize do
  begin
    Result := Symbol + PyTail(V, GSize) + Result;
    V := PyDropTail(V, GSize);
    GSize := Pat.Grouping.Max;
  end;
  Result := V + Result;
end;

function FormatFrac(const Value: string; const Prec: TIntPair; const Locale: TLocale;
  const NumberingSystem: string): string;
var
  V: string;
  AllZero: Boolean;
  C: Char;
begin
  V := Value;
  if Length(V) < Prec.Min then
    V := V + StringOfChar('0', Prec.Min - Length(V));
  AllZero := True;
  for C in V do
    if C <> '0' then
      AllZero := False;
  if (Prec.Max = 0) or ((Prec.Min = 0) and AllZero) then
    Exit('');
  while (Length(V) > Prec.Min) and (V[Length(V)] = '0') do
    SetLength(V, Length(V) - 1);
  Result := GetDecimalSymbol(Locale, NumberingSystem) + V;
end;

function QuantizeValue(const Pat: TNumberPattern; const Value: TDecimal; const Locale: TLocale;
  const FracPrec: TIntPair; GroupSeparator: Boolean; const NumberingSystem: string): string;
var
  Rounded: TDecimal;
  Text, A, B, IntegerPart: string;
  P: Integer;
begin
  if Value.IsInfinite then
    Exit(GetInfinitySymbol(Locale, NumberingSystem));
  Rounded := Value.Quantize(-FracPrec.Max);
  Text := Rounded.FormatFixed;
  P := Pos('.', Text);
  if P > 0 then
  begin
    A := Copy(Text, 1, P - 1);
    B := Copy(Text, P + 1, MaxInt);
  end
  else
  begin
    A := Text;
    B := '';
  end;
  IntegerPart := A;
  if GroupSeparator then
    IntegerPart := FormatInt(Pat, A, Pat.IntPrec.Min, Locale, NumberingSystem);
  if B = '' then
    B := '0';
  Result := IntegerPart + FormatFrac(B, FracPrec, Locale, NumberingSystem);
end;

function FormatSignificant(const Value: TDecimal; Minimum, Maximum: Integer): string;
var
  Exp, Scale: Int64;
  Digits, IntPart, FracPart, FracExtra: string;
  I, J, Fill: Int64;
begin
  Exp := Value.Adjusted;
  Scale := Maximum - 1 - Exp;
  Digits := Value.ScaleB(Scale).Quantize(0).ToString;
  if Scale <= 0 then
    Result := Digits + StringOfChar('0', -Scale)
  else
  begin
    IntPart := PyDropTail(Digits, Scale);
    I := Length(IntPart);
    J := I;
    if Minimum - I > 0 then
      J := I + (Minimum - I);
    if Exp + 1 < 0 then
      Fill := -(Exp + 1)
    else
      Fill := 0;
    FracPart := Copy(Digits, I + 1, J - I);
    FracExtra := RStripChar(Copy(Digits, J + 1, MaxInt), '0');
    if IntPart = '' then
      IntPart := '0';
    Result := RStripChar(IntPart + '.' + StringOfChar('0', Fill) + FracPart + FracExtra, '.');
  end;
end;

{ re.sub(r"'([^']*)'", lambda m: m.group(1) or "'", s) }
function Unquote(const S: string): string;
var
  I, J: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '''' then
    begin
      J := I + 1;
      while (J <= Length(S)) and (S[J] <> '''') do
        Inc(J);
      if J <= Length(S) then
      begin
        if J = I + 1 then
          Result := Result + ''''
        else
          Result := Result + Copy(S, I + 1, J - I - 1);
        I := J + 1;
        Continue;
      end;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
end;

function TNumberPattern.Apply(const Value: TNumber; const Locale: TLocale;
  const Options: TApplyOptions): string;
var
  V: TDecimal;
  IsNegative: Boolean;
  Exp, LeadShift: Int64;
  ExpSign, Number, Text, A, B: string;
  Frac: TIntPair;
  Prec, P: Integer;
  NS: string;
begin
  NS := Options.NumberingSystem;
  V := Value.ToDecimal;
  V := V.ScaleB(Scale);
  IsNegative := V.IsSigned;
  V := V.Abs.Normalize;

  Exp := 0;
  ExpSign := '';
  if HasExp then
  begin
    { scientific_notation_elements }
    Exp := V.Adjusted;
    V := V.Multiply(GetDecimalQuantum(Exp));
    if IntPrec.Min > 1 then
      LeadShift := IntPrec.Min - 1
    else
      LeadShift := 0;
    Exp := Exp - LeadShift;
    V := V.Multiply(GetDecimalQuantum(-LeadShift));
    if Exp < 0 then
      ExpSign := GetMinusSignSymbol(Locale, NS)
    else if ExpPlus then
      ExpSign := GetPlusSignSymbol(Locale, NS);
    Exp := System.Abs(Exp);
  end;

  if (Options.Currency <> '') and Options.CurrencyDigits then
  begin
    Frac.Min := GetCurrencyPrecision(Options.Currency);
    Frac.Max := Frac.Min;
  end
  else
    Frac := FracPrec;

  if not Options.DecimalQuantization or (HasExp and (Frac.Min = 0) and (Frac.Max = 0)) then
  begin
    Prec := GetDecimalPrecision(V);
    if Prec > Frac.Max then
      Frac.Max := Prec;
  end;

  if HasExp then
    Number := QuantizeValue(Self, V, Locale, Frac, Options.GroupSeparator, NS) +
      GetExponentialSymbol(Locale, NS) + ExpSign +
      FormatInt(Self, IntToStr(Exp), ExpPrec.Min, Locale, NS)
  else if Pos('@', Pattern) > 0 then
  begin
    Text := FormatSignificant(V, IntPrec.Min, IntPrec.Max);
    P := Pos('.', Text);
    if P > 0 then
    begin
      A := Copy(Text, 1, P - 1);
      B := Copy(Text, P + 1, MaxInt);
    end
    else
    begin
      A := Text;
      B := '';
    end;
    Number := FormatInt(Self, A, 0, Locale, NS);
    if P > 0 then
      Number := Number + GetDecimalSymbol(Locale, NS) + B;
  end
  else
    Number := QuantizeValue(Self, V, Locale, Frac, Options.GroupSeparator, NS);

  if IsNegative then
    Result := NegPrefix
  else
    Result := PosPrefix;
  if NumberPattern <> '' then
    Result := Result + Number;
  if IsNegative then
    Result := Result + NegSuffix
  else
    Result := Result + PosSuffix;

  if (Pos(#$C2#$A4, Result) > 0) and (Options.Currency <> '') then
  begin
    Result := StringReplace(Result, #$C2#$A4#$C2#$A4#$C2#$A4,
      GetCurrencyName(Options.Currency, V, Locale), [rfReplaceAll]);
    Result := StringReplace(Result, #$C2#$A4#$C2#$A4, UpperCase(Options.Currency), [rfReplaceAll]);
    Result := StringReplace(Result, #$C2#$A4, GetCurrencySymbol(Options.Currency, Locale), [rfReplaceAll]);
  end;
  Result := Unquote(Result);
end;

{ ---- format functions ---- }

function PatternOf(const Locale: TLocale; Formats: TCLDRValue; const Key: string; IsNone: Boolean): string;
var
  V: TCLDRValue;
begin
  if IsNone then
    V := Formats.GetNone
  else
    V := Formats.Get(Key);
  if V = nil then
    raise EBabelKeyError.CreateFmt('no format %s for locale %s', [Key, Locale.ToString]);
  Result := V.AsString;
end;

function FormatDecimal(const Number: TNumber; const Locale: TLocale): string;
begin
  Result := FormatDecimal(Number, Locale, NumberOptions);
end;

function FormatDecimal(const Number: TNumber; const Locale: TLocale; const Options: TNumberOptions): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := PatternOf(Locale, Locale.DecimalFormats, '', True);
  AO := ApplyOptions;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
end;

{ _get_compact_format: the number to format and the pattern ('' when
  none applies). }
procedure GetCompactFormat(const Number: TNumber; CompactFormat: TCLDRValue; const Locale: TLocale;
  FractionDigits: Integer; out Value: TDecimal; out Format: string);

  { a > b for non-negative integers written without leading zeros }
  function Greater(const A, B: string): Boolean;
  begin
    if Length(A) <> Length(B) then
      Result := Length(A) > Length(B)
    else
      Result := CompareStr(A, B) > 0;
  end;

var
  Others: TCLDRValue;
  Mags: array of string;     { magnitudes as digit strings (up to 10^19 and more) }
  I, J, Zeros: Integer;
  T, MagKey, Divisor, Pat, PluralForm: string;
  Rounded, AbsValue: TDecimal;
  C: Char;
begin
  Format := '';
  Value := Number.ToDecimal;
  if Value.IsNaN or Value.IsInfinite then
    Exit;
  Others := CompactFormat.Get('other');
  if Others = nil then
    raise EBabelKeyError.Create('other');
  Mags := nil;
  SetLength(Mags, Others.Count);
  for I := 0 to Others.Count - 1 do
    { int(m), back to str: the keys are plain integers }
    Mags[I] := TDecimal.Parse(Others.Keys(I).AsString).Truncate.ToString;
  { sorted, descending }
  for I := 1 to High(Mags) do
  begin
    T := Mags[I];
    J := I - 1;
    while (J >= 0) and Greater(T, Mags[J]) do
    begin
      Mags[J + 1] := Mags[J];
      Dec(J);
    end;
    Mags[J + 1] := T;
  end;
  for MagKey in Mags do
  begin
    if Value.Abs.Compare(TDecimal.Parse(MagKey)) >= 0 then
    begin
      Format := Others.Str(MagKey);
      Pat := ParseNumberPattern(Format).Pattern;
      if Pat = '0' then
        Break;
      Zeros := 0;
      for C in Pat do
        if C = '0' then
          Inc(Zeros);
      if Zeros = 0 then
        raise EBabelTypeError.Create('unsupported operand type(s) for /: ''decimal.Decimal'' and ''float''');
      { magnitude // 10 ** (zeros - 1): drop that many digits }
      if Length(MagKey) > Zeros - 1 then
        Divisor := Copy(MagKey, 1, Length(MagKey) - (Zeros - 1))
      else
        Divisor := '0';
      Value := Value.Divide(TDecimal.Parse(Divisor));
      Rounded := Value.Round(FractionDigits);
      AbsValue := Value.Abs;
      PluralForm := Locale.PluralForm.Evaluate(AbsValue);
      if not CompactFormat.Has(PluralForm) then
        PluralForm := 'other';
      if (Value.CompareInt(1) = 0) and CompactFormat.Has('1') then
        PluralForm := '1';
      if not CompactFormat.Get(PluralForm).Has(MagKey) then
        PluralForm := 'other';
      Format := CompactFormat.Get(PluralForm).Str(MagKey);
      Value := Rounded;
      Break;
    end;
  end;
end;

function FormatCompactDecimal(const Number: TNumber; const Locale: TLocale): string;
begin
  Result := FormatCompactDecimal(Number, Locale, CompactOptions);
end;

function FormatCompactDecimal(const Number: TNumber; const Locale: TLocale; const Options: TCompactOptions): string;
var
  Compact: TCLDRValue;
  Value: TDecimal;
  Fmt: string;
  AO: TApplyOptions;
begin
  Compact := Locale.CompactDecimalFormats.Get(Options.FormatType);
  if Compact = nil then
    raise EBabelKeyError.Create(Options.FormatType);
  GetCompactFormat(Number, Compact, Locale, Options.FractionDigits, Value, Fmt);
  if Fmt = '' then
    Fmt := PatternOf(Locale, Locale.DecimalFormats, '', True);
  AO := ApplyOptions;
  AO.DecimalQuantization := False;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Value, Locale, AO);
end;

function FormatCurrencyLongName(const Number: TNumber; const Currency: string; const Locale: TLocale;
  const Options: TCurrencyOptions): string;
var
  N: TNumber;
  UnitPattern, DisplayName, Fmt, NumberPart: string;
  AO: TApplyOptions;
begin
  if Number.Kind = nkString then
    N := PyFloatOf(Number.FString)
  else
    N := Number;
  UnitPattern := GetCurrencyUnitPattern(Currency, N, Locale);
  DisplayName := GetCurrencyName(Currency, N, Locale);
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := PatternOf(Locale, Locale.DecimalFormats, '', True);
  AO := ApplyOptions;
  AO.Currency := Currency;
  AO.CurrencyDigits := Options.CurrencyDigits;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  NumberPart := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
  Result := PyFormat2(UnitPattern, NumberPart, DisplayName);
end;

function FormatCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale): string;
begin
  Result := FormatCurrency(Number, Currency, Locale, CurrencyOptions);
end;

function FormatCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale;
  const Options: TCurrencyOptions): string;
var
  Fmt: string;
  V: TCLDRValue;
  AO: TApplyOptions;
begin
  if Options.FormatType = 'name' then
    Exit(FormatCurrencyLongName(Number, Currency, Locale, Options));
  if Options.Format <> '' then
    Fmt := Options.Format
  else
  begin
    V := Locale.CurrencyFormats.Get(Options.FormatType);
    if V = nil then
      raise EUnknownCurrencyFormatError.CreateFmt('''%s'' is not a known currency format type',
        [Options.FormatType]);
    Fmt := V.AsString;
  end;
  AO := ApplyOptions;
  AO.Currency := Currency;
  AO.CurrencyDigits := Options.CurrencyDigits;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
end;

{ re.sub(r'[^0\s\¤]', '', s), re.sub(r'(\s)\s+', r'\1', s), .strip() }
function CompactCurrencySkeleton(const S: string): string;
var
  I, L: Integer;
  C: Cardinal;
  Kept: string;
  PrevSpace: Boolean;
begin
  Kept := '';
  I := 1;
  while I <= Length(S) do
  begin
    C := CodePointAt(S, I, L);
    if (C = Ord('0')) or (C = $A4) or IsPySpace(C) then
      Kept := Kept + Copy(S, I, L);
    Inc(I, L);
  end;
  Result := '';
  PrevSpace := False;
  I := 1;
  while I <= Length(Kept) do
  begin
    C := CodePointAt(Kept, I, L);
    if IsPySpace(C) then
    begin
      if not PrevSpace then
        Result := Result + Copy(Kept, I, L);
      PrevSpace := True;
    end
    else
    begin
      Result := Result + Copy(Kept, I, L);
      PrevSpace := False;
    end;
    Inc(I, L);
  end;
  Result := PyStrip(Result);
end;

function FormatCompactCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale): string;
begin
  Result := FormatCompactCurrency(Number, Currency, Locale, CompactOptions);
end;

function FormatCompactCurrency(const Number: TNumber; const Currency: string; const Locale: TLocale;
  const Options: TCompactOptions): string;
var
  Compact, Others: TCLDRValue;
  Value: TDecimal;
  Fmt, P: string;
  I: Integer;
  AO: TApplyOptions;
  Found: Boolean;
begin
  Compact := Locale.CompactCurrencyFormats.Get(Options.FormatType);
  if Compact = nil then
    raise EUnknownCurrencyFormatError.CreateFmt('''%s'' is not a known compact currency format type',
      [Options.FormatType]);
  GetCompactFormat(Number, Compact, Locale, Options.FractionDigits, Value, Fmt);
  Found := Fmt <> '';
  if (Fmt = '') or (Pos(#$C2#$A4, Fmt) = 0) then
  begin
    Others := Compact.Get('other');
    if Others = nil then
      raise EBabelKeyError.Create('other');
    for I := 0 to Others.Count - 1 do
    begin
      P := Others.Items(I).AsString;
      Fmt := P;
      Found := True;
      if Pos(#$C2#$A4, P) = 0 then
        Continue;
      Fmt := CompactCurrencySkeleton(P);
      Break;
    end;
  end;
  if not Found then
    raise EBabelValueError.Create('No compact currency format found for the given number and locale.');
  AO := ApplyOptions;
  AO.Currency := Currency;
  AO.CurrencyDigits := False;
  AO.DecimalQuantization := False;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Value, Locale, AO);
end;

function FormatPercent(const Number: TNumber; const Locale: TLocale): string;
begin
  Result := FormatPercent(Number, Locale, NumberOptions);
end;

function FormatPercent(const Number: TNumber; const Locale: TLocale; const Options: TNumberOptions): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := PatternOf(Locale, Locale.PercentFormats, '', True);
  AO := ApplyOptions;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
end;

function FormatScientific(const Number: TNumber; const Locale: TLocale): string;
begin
  Result := FormatScientific(Number, Locale, NumberOptions);
end;

function FormatScientific(const Number: TNumber; const Locale: TLocale; const Options: TNumberOptions): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := PatternOf(Locale, Locale.ScientificFormats, '', True);
  AO := ApplyOptions;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
end;

{ ---- parsing ---- }

const
  SpaceChars: array[0..2] of string = (' ', #$C2#$A0, #$E2#$80#$AF);

function IsSpaceChar(const S: string): Boolean;
var
  X: string;
begin
  for X in SpaceChars do
    if X = S then
      Exit(True);
  Result := False;
end;

function HasSpaceChar(const S: string): Boolean;
var
  X: string;
begin
  for X in SpaceChars do
    if Pos(X, S) > 0 then
      Exit(True);
  Result := False;
end;

function ReplaceSpaceChars(const S, By: string): string;
var
  X: string;
begin
  Result := S;
  for X in SpaceChars do
    Result := StringReplace(Result, X, By, [rfReplaceAll]);
end;

{ int(s): Python's syntax (whitespace, sign, digits with single '_'
  between them), within Int64. }
function PyIntOf(const S: string; out V: Int64): Boolean;
var
  T: string;
  I: Integer;
  Neg: Boolean;
  Q: QWord;
  D: Integer;
begin
  V := 0;
  Result := False;
  T := AsciiDigits(PyStrip(S));
  if T = '' then
    Exit;
  Neg := False;
  I := 1;
  if T[1] in ['+', '-'] then
  begin
    Neg := T[1] = '-';
    Inc(I);
  end;
  if (I > Length(T)) or not (T[I] in ['0'..'9']) or not (T[Length(T)] in ['0'..'9']) then
    Exit;
  Q := 0;
  while I <= Length(T) do
  begin
    if T[I] = '_' then
    begin
      if not (T[I + 1] in ['0'..'9']) then
        Exit;
      Inc(I);
      Continue;
    end;
    if not (T[I] in ['0'..'9']) then
      Exit;
    D := Ord(T[I]) - 48;
    if Q > (QWord(High(Int64)) + 1 - QWord(D)) div 10 then
      raise EBabelOverflowError.CreateFmt('%s does not fit in an Int64', [S]);
    Q := Q * 10 + QWord(D);
    Inc(I);
  end;
  if Neg then
  begin
    if Q > QWord(High(Int64)) + 1 then
      raise EBabelOverflowError.CreateFmt('%s does not fit in an Int64', [S]);
    V := -Int64(Q - 1) - 1;
  end
  else
  begin
    if Q > QWord(High(Int64)) then
      raise EBabelOverflowError.CreateFmt('%s does not fit in an Int64', [S]);
    V := Int64(Q);
  end;
  Result := True;
end;

function PyRepr(const S: string): string;
begin
  Result := '''' + S + '''';
end;

function ParseNumber(const S: string; const Locale: TLocale): Int64;
begin
  Result := ParseNumber(S, Locale, ParseOptions);
end;

function ParseNumber(const S: string; const Locale: TLocale; const Options: TParseOptions): Int64;
var
  Group, T: string;
begin
  Group := GetGroupSymbol(Locale, Options.NumberingSystem);
  T := S;
  if IsSpaceChar(Group) and (Pos(Group, T) = 0) and HasSpaceChar(T) then
    T := ReplaceSpaceChars(T, Group);
  if not PyIntOf(StringReplace(T, Group, '', [rfReplaceAll]), Result) then
    raise ENumberFormatError.CreateWith(PyRepr(T) + ' is not a valid number', nil);
end;

function RemoveTrailingZerosAfterDecimal(const S, DecimalSymbol: string): string;
var
  P: Integer;
  IntegerPart, DecimalPart: string;
begin
  P := Pos(DecimalSymbol, S);
  if P = 0 then
    Exit(S);
  IntegerPart := Copy(S, 1, P - 1);
  DecimalPart := Copy(S, P + Length(DecimalSymbol), MaxInt);
  if DecimalPart = '' then
    Exit(S);
  DecimalPart := RStripChar(DecimalPart, '0');
  if DecimalPart <> '' then
    Result := IntegerPart + DecimalSymbol + DecimalPart
  else
    Result := IntegerPart;
end;

function ParseDecimal(const S: string; const Locale: TLocale): TDecimal;
begin
  Result := ParseDecimal(S, Locale, ParseOptions);
end;

function ParseDecimal(const S: string; const Locale: TLocale; const Options: TParseOptions): TDecimal;
var
  Group, Dec, T, Proper, ProperAlt: string;
  Alt: TDecimal;
  NO: TNumberOptions;
begin
  Group := GetGroupSymbol(Locale, Options.NumberingSystem);
  Dec := GetDecimalSymbol(Locale, Options.NumberingSystem);
  T := S;
  if not Options.StrictMode and IsSpaceChar(Group) and (Pos(Group, T) = 0) and HasSpaceChar(T) then
    T := ReplaceSpaceChars(T, Group);
  if not TDecimal.TryParse(StringReplace(StringReplace(T, Group, '', [rfReplaceAll]), Dec, '.',
    [rfReplaceAll]), Result) then
    raise ENumberFormatError.CreateWith(PyRepr(T) + ' is not a valid decimal number', nil);
  if Options.StrictMode and (Pos(Group, T) > 0) then
  begin
    NO := NumberOptions.WithDecimalQuantization(False).WithNumberingSystem(Options.NumberingSystem);
    Proper := FormatDecimal(Result, Locale, NO);
    if (T <> Proper) and (Proper <> RemoveTrailingZerosAfterDecimal(T, Dec)) then
    begin
      if not TDecimal.TryParse(StringReplace(StringReplace(T, Dec, '', [rfReplaceAll]), Group, '.',
        [rfReplaceAll]), Alt) then
        raise ENumberFormatError.CreateWith(PyRepr(T) + ' is not a properly formatted decimal number. ' +
          'Did you mean ' + PyRepr(Proper) + '?', [Proper]);
      ProperAlt := FormatDecimal(Alt, Locale, NO);
      if ProperAlt = Proper then
        raise ENumberFormatError.CreateWith(PyRepr(T) + ' is not a properly formatted decimal number. ' +
          'Did you mean ' + PyRepr(Proper) + '?', [Proper])
      else
        raise ENumberFormatError.CreateWith(PyRepr(T) + ' is not a properly formatted decimal number. ' +
          'Did you mean ' + PyRepr(Proper) + '? Or maybe ' + PyRepr(ProperAlt) + '?', [Proper, ProperAlt]);
    end;
  end;
end;

end.
