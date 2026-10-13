{ babel.numbers - formatting and parsing of numbers, currencies and
  percentages.

  FormatDecimal(1234.5, 'es_PE') gives '1,234.5'; FormatCurrency(1234.5,
  'PEN', 'es_PE') gives 'S/ 1,234.50'.

  The results follow CLDR (UTS #35) as ICU applies it:
  - the signs of a pattern are the locale's: '-' is the minus sign ('−'
    in Swedish), '%' the percent sign ('٪؜' in Arabic), and so on, except
    inside quotes;
  - digits are written in the numbering system asked for
    (NumberingSystem 'default' gives ar_EG's '١٬٢٣٤٫٥'; 'latn', the
    default, gives ASCII digits);
  - a plural form depends on the number as shown: FormatCurrency(1, 'USD',
    'en') with the 'name' format type gives '1.00 US dollars', as ICU;
  - NaN is the locale's nan symbol;
  - the arithmetic is exact, for numbers of any number of digits;
  - minimumGroupingDigits: es writes 1234 and 12.345;
  - currencySpacing: a no-break space between a currency code or a
    symbol that ends in a letter and the digits ('PEN 1.00');
  - each numbering system uses its own patterns when CLDR has them (fa's
    arabext currency pattern, bn's beng percent pattern);
  - compact forms round the number shown to FractionDigits in every
    case, go to the next magnitude when rounding reaches it (999999 is
    1M), group large numbers ('1,000,000T', with at least two digits
    before the first separator), take the plural form of the number shown
    when CLDR has no special form for it, and fall back from 'long' to
    'short';
  - ParseDecimal and ParseNumber read the locale's minus and plus signs
    (and its separators and digits) as FormatDecimal writes them.

  Node's ICU (78.2, CLDR 48) gives the same results on 18 000 cases,
  except where the CLDR 47 and 48 data differ (tests/js/README.md).

  Numbers are TDecimal (babel.decimal), which converts implicitly from an
  Int64, a Double (its shortest decimal: 2.675 is 2.675) and a string.

  Options. The optional parameters are fields of an options record:
  NumberOptions, CurrencyOptions and CompactOptions return the defaults,
  and the With* methods return a changed copy:

    FormatDecimal(X, 'en', NumberOptions.WithGroupSeparator(False));
    FormatCurrency(X, 'USD', 'en', CurrencyOptions.WithFormatType('accounting'));

  A record that is not made by these functions has False and '' where
  the defaults are True and 'latn': always start from them.

  An empty Format means the locale's pattern; a currency of '' means
  none.

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
    { Correctly formatted numbers derived from the input (ParseDecimal
      with StrictMode). }
    Suggestions: TStringArray;
    constructor CreateWith(const Msg: string; const ASuggestions: TStringArray);
  end;

  { FormatDecimal, FormatPercent and FormatScientific options. }
  TNumberOptions = record
    Format: string;                 { '' = the locale's pattern }
    DecimalQuantization: Boolean;   { True }
    GroupSeparator: Boolean;        { True (FormatScientific has none) }
    NumberingSystem: string;        { 'latn'; 'default' = the locale's }
    function WithFormat(const Value: string): TNumberOptions;
    function WithDecimalQuantization(Value: Boolean): TNumberOptions;
    function WithGroupSeparator(Value: Boolean): TNumberOptions;
    function WithNumberingSystem(const Value: string): TNumberOptions;
  end;

  { FormatCurrency options. }
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

  { FormatCompactDecimal and FormatCompactCurrency options. }
  TCompactOptions = record
    FormatType: string;             { 'short' or 'long' (currency: 'short') }
    FractionDigits: Integer;        { 0 }
    NumberingSystem: string;        { 'latn' }
    function WithFormatType(const Value: string): TCompactOptions;
    function WithFractionDigits(Value: Integer): TCompactOptions;
    function WithNumberingSystem(const Value: string): TCompactOptions;
  end;

  { ParseNumber and ParseDecimal options. }
  TParseOptions = record
    StrictMode: Boolean;            { strict parsing (False; ParseDecimal only);
                                      Strict is a reserved word here }
    NumberingSystem: string;        { 'latn' }
    function WithStrict(Value: Boolean): TParseOptions;
    function WithNumberingSystem(const Value: string): TParseOptions;
  end;

  { GetTerritoryCurrencies options. A date of 0 means none: the start
    date defaults to today and the end date to the start date. }
  TTerritoryCurrencyOptions = record
    StartDate, EndDate: TDateTime;
    Tender: Boolean;                { True }
    NonTender: Boolean;             { False }
    function WithStartDate(Value: TDateTime): TTerritoryCurrencyOptions;
    function WithEndDate(Value: TDateTime): TTerritoryCurrencyOptions;
    function WithTender(Value: Boolean): TTerritoryCurrencyOptions;
    function WithNonTender(Value: Boolean): TTerritoryCurrencyOptions;
  end;

  { One currency of a territory (GetTerritoryCurrencyDetails); a date of 0
    means none. }
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
    Currency: string;               { '' = none }
    CurrencyDigits: Boolean;        { True }
    DecimalQuantization: Boolean;   { True }
    GroupSeparator: Boolean;        { True }
    NumberingSystem: string;        { 'latn' }
    MinGrouping: Integer;           { 0: the locale's minimumGroupingDigits }
  end;

  { A parsed number pattern. }
  TNumberPattern = record
    Pattern: string;
    PosPrefix, NegPrefix, PosSuffix, NegSuffix: string;
    NumberPattern: string;           { the number part, without the exponent }
    Grouping: TIntPair;              { Min = primary, Max = secondary size }
    IntPrec, FracPrec: TIntPair;
    HasExp: Boolean;                 { the pattern has an exponent }
    ExpPrec: TIntPair;
    ExpPlus: Boolean;
    Scale: Integer;                  { 0, 2 (percent) or 3 (per mille) }
    function Apply(const Value: TDecimal; const Locale: TLocale; const Options: TApplyOptions): string;
    { Apply, and in Shown the number as shown (rounded, with the fraction
      digits written), from which plural forms are chosen. }
    function ApplyShown(const Value: TDecimal; const Locale: TLocale; const Options: TApplyOptions;
      out Shown: TDecimal): string;
  end;

function NumberOptions: TNumberOptions;
function CurrencyOptions: TCurrencyOptions;
function CompactOptions: TCompactOptions;
function ParseOptions: TParseOptions;
function TerritoryCurrencyOptions: TTerritoryCurrencyOptions;
function ApplyOptions: TApplyOptions;

{ Currencies }
{ The ISO 4217 codes known to the locale, or (no locale) every currency
  of the global data; sorted. }
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
function GetCurrencyName(const Currency: string; const Count: TDecimal; const Locale: TLocale): string; overload;
function GetCurrencySymbol(const Currency: string; const Locale: TLocale): string;
{ The currency's number of fraction digits (2 when not listed). }
function GetCurrencyPrecision(const Currency: string): Integer;
(* The pattern that joins number and currency name ('{0} {1}'). *)
function GetCurrencyUnitPattern(const Currency: string; const Locale: TLocale): string; overload;
function GetCurrencyUnitPattern(const Currency: string; const Count: TDecimal; const Locale: TLocale): string; overload;
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

{ GetDecimalPrecision: the number of fraction digits of the normalized
  number. GetDecimalQuantum: 10 ** -Precision. }
function GetDecimalPrecision(const Number: TDecimal): Integer;
function GetDecimalQuantum(Precision: Int64): TDecimal;

{ Formatting }
function FormatDecimal(const Number: TDecimal; const Locale: TLocale): string; overload;
function FormatDecimal(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string; overload;
{ FormatDecimal, and in Shown the number as shown (rounded, with its
  fraction digits), from which plural forms are chosen. }
function FormatDecimalShown(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions;
  out Shown: TDecimal): string;
function FormatCompactDecimal(const Number: TDecimal; const Locale: TLocale): string; overload;
function FormatCompactDecimal(const Number: TDecimal; const Locale: TLocale; const Options: TCompactOptions): string; overload;
function FormatCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale): string; overload;
function FormatCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale;
  const Options: TCurrencyOptions): string; overload;
function FormatCompactCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale): string; overload;
function FormatCompactCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale;
  const Options: TCompactOptions): string; overload;
function FormatPercent(const Number: TDecimal; const Locale: TLocale): string; overload;
function FormatPercent(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string; overload;
function FormatScientific(const Number: TDecimal; const Locale: TLocale): string; overload;
function FormatScientific(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string; overload;

{ Parsing }
{ ParseNumber: an integer written in the locale's format ('1,099' in
  en; the locale's minus and plus signs, digits of any script). Raises
  ENumberFormatError. Beyond Int64 raises EBabelOverflowError. }
function ParseNumber(const S: string; const Locale: TLocale): Int64; overload;
function ParseNumber(const S: string; const Locale: TLocale; const Options: TParseOptions): Int64; overload;
{ ParseDecimal: a decimal number written in the locale's format (as
  FormatDecimal writes it: the locale's separators, minus and plus
  signs, digits of any script). With StrictMode, a misplaced group symbol
  raises ENumberFormatError with suggestions. }
function ParseDecimal(const S: string; const Locale: TLocale): TDecimal; overload;
function ParseDecimal(const S: string; const Locale: TLocale; const Options: TParseOptions): TDecimal; overload;

{ Patterns }
{ ParseGrouping: the primary and secondary group sizes of the integer
  part of a pattern (1000, 1000 when it has no ','). }
function ParseGrouping(const P: string): TIntPair;
{ The parsed pattern. Raises EBabelValueError for a pattern that mixes '@'
  with '.' and '0'. }
function ParseNumberPattern(const Pattern: string): TNumberPattern;
{ The ten digits of a numbering system ('default': the locale's; nil for
  'latn' or a system without digits). }
function SystemDigits(const Locale: TLocale; const NumberingSystem: string): TCodePoints;
{ S with its ASCII digits written in Digits (unchanged when nil). }
function LocalizeDigits(const S: string; const Digits: TCodePoints): string;

implementation

{ ---- small string helpers (code points) ---- }

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

{ The plural category of Count in the locale ('other' for NaN and
  infinity). }
function PluralOf(const Count: TDecimal; const Locale: TLocale): string;
begin
  if not Count.IsFinite then
    Exit('other');
  Result := Locale.PluralForm.Evaluate(Count);
end;

function GetCurrencyName(const Currency: string; const Count: TDecimal; const Locale: TLocale): string;
var
  Form: string;
  Names, ForCurrency: TCLDRValue;
begin
  Form := PluralOf(Count, Locale);
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

function GetCurrencyUnitPattern(const Currency: string; const Count: TDecimal; const Locale: TLocale): string;
var
  P: TCLDRValue;
  Form: string;
begin
  Form := PluralOf(Count, Locale);
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
  { characters are code points }
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

{ The text of an affix outside its quotes. }
function Unquoted(const Affix: string): string;
var
  I: Integer;
  Quoted: Boolean;
begin
  Result := '';
  Quoted := False;
  for I := 1 to Length(Affix) do
    if Affix[I] = '''' then
      Quoted := not Quoted
    else if not Quoted then
      Result := Result + Affix[I];
end;

function ParseNumberPattern(const Pattern: string): TNumberPattern;
var
  PosPattern, NegPattern, Number, Dummy, Exp, IntegerPart, Fraction, Affixes: string;
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
  { a percent or per mille sign outside quotes scales the number }
  Affixes := Unquoted(Result.PosPrefix) + Unquoted(Result.NegPrefix) +
    Unquoted(Result.PosSuffix) + Unquoted(Result.NegSuffix);
  if Pos('%', Affixes) > 0 then
    Result.Scale := 2
  else if Pos(#$E2#$80#$B0, Affixes) > 0 then
    Result.Scale := 3;
end;

{ ---- NumberPattern.apply ---- }

{ The ten digits of a numbering system ('' for 'latn' or a system without
  digits in the data: ASCII digits are kept). }
function SystemDigits(const Locale: TLocale; const NumberingSystem: string): TCodePoints;
var
  NS: string;
  V: TCLDRValue;
begin
  Result := nil;
  NS := NumberingSystem;
  if NS = 'default' then
    NS := Locale.DefaultNumberingSystem;
  if NS = 'latn' then
    Exit;
  V := GetGlobal('numbering_system_digits').Get(NS);
  if (V <> nil) and (V.Kind = ckString) then
  begin
    Result := CodePoints(V.AsString);
    if Length(Result) <> 10 then
      Result := nil;
  end;
end;

{ S with its ASCII digits written in Digits (unchanged when Digits is
  empty). }
function LocalizeDigits(const S: string; const Digits: TCodePoints): string;
var
  C: Char;
  One: TCodePoints;
begin
  if Digits = nil then
    Exit(S);
  Result := '';
  SetLength(One, 1);
  for C in S do
    if C in ['0'..'9'] then
    begin
      One[0] := Digits[Ord(C) - Ord('0')];
      Result := Result + CodePointsToUTF8(One, 0, 1);
    end
    else
      Result := Result + C;
end;

{ The integer digits Value padded to Min digits and grouped. CLDR's
  minimumGroupingDigits: no separator unless at least MinGrouping digits
  come before the first one (es: 1234, 12.345). }
function FormatInt(const Pat: TNumberPattern; const Value: string; Min, MinGrouping: Integer;
  const Locale: TLocale; const NumberingSystem: string): string;
var
  V, Symbol: string;
  GSize: Integer;
begin
  V := Value;
  if Length(V) < Min then
    V := StringOfChar('0', Min - Length(V)) + V;
  if Length(V) < Pat.Grouping.Min + MinGrouping then
    Exit(V);
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

{ The fraction digits shown: Value padded to Prec.Min, trailing zeros
  dropped down to Prec.Min, '' when none are shown. }
function FractionShown(const Value: string; const Prec: TIntPair): string;
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
  Result := V;
end;

{ The rounded number with its symbols (ASCII digits), and in Shown the
  digits shown ('1234.50'). }
function QuantizeValue(const Pat: TNumberPattern; const Value: TDecimal; const Locale: TLocale;
  const FracPrec: TIntPair; GroupSeparator: Boolean; MinGrouping: Integer;
  const NumberingSystem: string; out Shown: string): string;
var
  Text, A, B, IntegerPart, Frac: string;
  P: Integer;
begin
  Text := Value.Quantize(-FracPrec.Max).FormatFixed;
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
  if B = '' then
    B := '0';
  IntegerPart := A;
  if GroupSeparator then
    IntegerPart := FormatInt(Pat, A, Pat.IntPrec.Min, MinGrouping, Locale, NumberingSystem);
  Frac := FractionShown(B, FracPrec);
  Shown := A;
  Result := IntegerPart;
  if Frac <> '' then
  begin
    Shown := Shown + '.' + Frac;
    Result := Result + GetDecimalSymbol(Locale, NumberingSystem) + Frac;
  end;
end;

function FormatSignificant(const Value: TDecimal; Minimum, Maximum: Integer): string;
var
  Exp, Scale: Int64;
  Digits, IntPart, FracPart, FracExtra: string;
  I, J, Fill: Int64;
begin
  Exp := Value.Adjusted;
  Scale := Maximum - 1 - Exp;
  Digits := Value.ScaleB(Scale).Quantize(0).FormatFixed;
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

{ An affix (prefix or suffix) as written: quoted text is literal ('' is a
  quote); outside quotes '-', '+', '%' and the per mille sign are the
  locale's symbols and the currency signs are replaced (UTS #35, "Special
  Pattern Characters"). }
function ExpandAffix(const Affix: string; const Locale: TLocale; const Options: TApplyOptions;
  const Shown: TDecimal; out CurrencyFirst, CurrencyLast: Boolean): string;
var
  I, J, N: Integer;
  NS: string;
begin
  NS := Options.NumberingSystem;
  Result := '';
  CurrencyFirst := False;
  CurrencyLast := False;
  I := 1;
  while I <= Length(Affix) do
  begin
    if Affix[I] = '''' then
    begin
      J := I + 1;
      while (J <= Length(Affix)) and (Affix[J] <> '''') do
        Inc(J);
      if J > Length(Affix) then
      begin
        Result := Result + Copy(Affix, I, MaxInt);   { unclosed: literal }
        Break;
      end;
      if J = I + 1 then
        Result := Result + ''''
      else
        Result := Result + Copy(Affix, I + 1, J - I - 1);
      I := J + 1;
      Continue;
    end;
    if Copy(Affix, I, 2) = #$C2#$A4 then
    begin
      N := 1;
      while Copy(Affix, I + 2 * N, 2) = #$C2#$A4 do
        Inc(N);
      if Options.Currency = '' then
        Result := Result + Copy(Affix, I, 2 * N)
      else
        case N of
          1: Result := Result + GetCurrencySymbol(Options.Currency, Locale);
          2: Result := Result + UpperCase(Options.Currency);
        else
          Result := Result + GetCurrencyName(Options.Currency, Shown, Locale);
        end;
      if Options.Currency <> '' then
      begin
        if I = 1 then
          CurrencyFirst := True;
        if I + 2 * N > Length(Affix) then
          CurrencyLast := True;
      end;
      Inc(I, 2 * N);
      Continue;
    end;
    if Affix[I] = '-' then
      Result := Result + GetMinusSignSymbol(Locale, NS)
    else if Affix[I] = '+' then
      Result := Result + GetPlusSignSymbol(Locale, NS)
    else if Affix[I] = '%' then
      Result := Result + NumberSymbols(Locale, NS).Str('percentSign', '%')
    else if Copy(Affix, I, 3) = #$E2#$80#$B0 then
    begin
      Result := Result + NumberSymbols(Locale, NS).Str('perMille', #$E2#$80#$B0);
      Inc(I, 3);
      Continue;
    end
    else
      Result := Result + Affix[I];
    Inc(I);
  end;
end;

function FirstCodePoint(const S: string): Cardinal;
var
  L: Integer;
begin
  if S = '' then
    Exit(0);
  Result := CodePointAt(S, 1, L);
end;

function LastCodePoint(const S: string): Cardinal;
var
  I, L: Integer;
begin
  if S = '' then
    Exit(0);
  I := Length(S);
  while (I > 1) and (Ord(S[I]) and $C0 = $80) do
    Dec(I);
  Result := CodePointAt(S, I, L);
end;

{ CLDR's currencySpacing (Side 'beforeCurrency' or 'afterCurrency'): the
  text to insert between a currency sign whose character next to the
  number is CurrencyChar and the number's character next to it,
  NumberChar. CLDR 47 has one rule, in root: when CurrencyChar is not a
  symbol or separator ([[:^S:]&[:^Z:]]) and NumberChar is a digit, insert
  a no-break space. Other match sets are not recognized (nothing is
  inserted). }
function CurrencySpacing(const Locale: TLocale; const Side: string;
  CurrencyChar, NumberChar: Cardinal): string;
var
  Rule: TCLDRValue;
begin
  Result := '';
  Rule := Locale.Data.Path(['currency_spacing', Side]);
  if Rule = nil then
    Exit;
  if (Rule.Str('currencyMatch') <> '[[:^S:]&[:^Z:]]') or (Rule.Str('surroundingMatch') <> '[:digit:]') then
    Exit;
  if (CurrencyChar = 0) or IsSymbolOrSeparator(CurrencyChar) then
    Exit;
  if DecimalDigitValue(NumberChar) < 0 then
    Exit;
  Result := Rule.Str('insertBetween');
end;

function TNumberPattern.ApplyShown(const Value: TDecimal; const Locale: TLocale;
  const Options: TApplyOptions; out Shown: TDecimal): string;
var
  V: TDecimal;
  IsNegative: Boolean;
  Exp, LeadShift: Int64;
  ExpSign, Number, Text, A, B, ShownText, ExpDigits: string;
  Frac: TIntPair;
  Prec, P, MinGrouping: Integer;
  NS, Prefix, Suffix: string;
  CurFirst, CurLast, Dummy: Boolean;
  MG: TCLDRValue;
begin
  NS := Options.NumberingSystem;
  MinGrouping := Options.MinGrouping;
  if MinGrouping <= 0 then
  begin
    MG := Locale.Data.Get('min_grouping_digits');
    if MG <> nil then
      MinGrouping := MG.AsInteger
    else
      MinGrouping := 1;
  end;
  V := Value.ScaleB(Scale);
  IsNegative := V.IsSigned and not V.IsNaN;
  V := V.Abs.Normalize;
  Shown := V;

  Exp := 0;
  ExpSign := '';
  if HasExp and V.IsFinite then
  begin
    Exp := V.Adjusted;
    V := V.ScaleB(-Exp);
    if IntPrec.Min > 1 then
      LeadShift := IntPrec.Min - 1
    else
      LeadShift := 0;
    Exp := Exp - LeadShift;
    V := V.ScaleB(LeadShift);
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

  if V.IsNaN then
    Number := NumberSymbols(Locale, NS).Str('nan', 'NaN')
  else if V.IsInfinite then
    Number := GetInfinitySymbol(Locale, NS)
  else if HasExp then
  begin
    Number := QuantizeValue(Self, V, Locale, Frac, Options.GroupSeparator, MinGrouping, NS, ShownText);
    Shown := TDecimal.Parse(ShownText).ScaleB(Exp);
    ExpDigits := IntToStr(Exp);
    if Length(ExpDigits) < ExpPrec.Min then
      ExpDigits := StringOfChar('0', ExpPrec.Min - Length(ExpDigits)) + ExpDigits;
    Number := Number + GetExponentialSymbol(Locale, NS) + ExpSign + ExpDigits;
  end
  else if Pos('@', NumberPattern) > 0 then
  begin
    Text := FormatSignificant(V, IntPrec.Min, IntPrec.Max);
    Shown := TDecimal.Parse(Text);
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
    Number := FormatInt(Self, A, 0, MinGrouping, Locale, NS);
    if P > 0 then
      Number := Number + GetDecimalSymbol(Locale, NS) + B;
  end
  else
  begin
    Number := QuantizeValue(Self, V, Locale, Frac, Options.GroupSeparator, MinGrouping, NS, ShownText);
    Shown := TDecimal.Parse(ShownText);
  end;
  Number := LocalizeDigits(Number, SystemDigits(Locale, NS));

  if IsNegative then
  begin
    Prefix := ExpandAffix(NegPrefix, Locale, Options, Shown, Dummy, CurLast);
    Suffix := ExpandAffix(NegSuffix, Locale, Options, Shown, CurFirst, Dummy);
  end
  else
  begin
    Prefix := ExpandAffix(PosPrefix, Locale, Options, Shown, Dummy, CurLast);
    Suffix := ExpandAffix(PosSuffix, Locale, Options, Shown, CurFirst, Dummy);
  end;
  if NumberPattern = '' then
    Number := '';
  if Number <> '' then
  begin
    { CLDR currencySpacing: a currency sign next to a digit }
    if CurLast then
      Prefix := Prefix + CurrencySpacing(Locale, 'afterCurrency', LastCodePoint(Prefix),
        FirstCodePoint(Number));
    if CurFirst then
      Suffix := CurrencySpacing(Locale, 'beforeCurrency', FirstCodePoint(Suffix),
        LastCodePoint(Number)) + Suffix;
  end;
  Result := Prefix + Number + Suffix;
end;

function TNumberPattern.Apply(const Value: TDecimal; const Locale: TLocale;
  const Options: TApplyOptions): string;
var
  Shown: TDecimal;
begin
  Result := ApplyShown(Value, Locale, Options, Shown);
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

{ The locale's pattern of a kind ('decimal', 'percent', 'scientific',
  'currency_standard', 'currency_accounting') for a numbering system: the
  system's own pattern when CLDR gives one, else the latn pattern (where
  CLDR's aliases lead). An accounting pattern falls back to the system's
  standard pattern when root defines the system's currency formats (as
  CLDR's alias in root says). Raises EBabelKeyError when there is none. }
function LocalePattern(const Locale: TLocale; const Kind, NumberingSystem: string): string;
var
  NS: string;
  V: TCLDRValue;
begin
  NS := NumberingSystem;
  if NS = 'default' then
    NS := Locale.DefaultNumberingSystem;
  if NS <> 'latn' then
  begin
    V := Locale.Data.Path(['numbering_system_formats', NS, Kind]);
    { root gives a few systems (arab) their own currency formats, whose
      accounting pattern is an alias of the standard one; the other
      systems are aliases of latn }
    if (V = nil) and (Kind = 'currency_accounting') and
       (LoadLocaleData('root').Path(['numbering_system_formats', NS, 'currency_standard']) <> nil) then
      V := Locale.Data.Path(['numbering_system_formats', NS, 'currency_standard']);
    if V <> nil then
      Exit(V.AsString);
  end;
  if Kind = 'decimal' then
    Result := PatternOf(Locale, Locale.DecimalFormats, '', True)
  else if Kind = 'percent' then
    Result := PatternOf(Locale, Locale.PercentFormats, '', True)
  else if Kind = 'scientific' then
    Result := PatternOf(Locale, Locale.ScientificFormats, '', True)
  else
  begin
    V := Locale.CurrencyFormats.Get(Copy(Kind, Length('currency_') + 1, MaxInt));
    if V = nil then
      raise EBabelKeyError.CreateFmt('no %s pattern for locale %s', [Kind, Locale.ToString]);
    Result := V.AsString;
  end;
end;

function FormatDecimal(const Number: TDecimal; const Locale: TLocale): string;
begin
  Result := FormatDecimal(Number, Locale, NumberOptions);
end;

function FormatDecimal(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := LocalePattern(Locale, 'decimal', Options.NumberingSystem);
  AO := ApplyOptions;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
end;

function FormatDecimalShown(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions;
  out Shown: TDecimal): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := LocalePattern(Locale, 'decimal', Options.NumberingSystem);
  AO := ApplyOptions;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).ApplyShown(Number, Locale, AO, Shown);
end;

{ The compact form of Number: Value, the number to show (divided and
  rounded to FractionDigits), and Format, the compact pattern ('' when
  no abbreviation applies: the number is then shown whole, rounded).

  The pattern is chosen from CompactFormat: the largest magnitude not
  above the number, the plural form of the number shown. As in ICU, the
  number is rounded in every case, and when rounding
  reaches the next magnitude, that magnitude is used (999999 is 1M, not
  1000K). }
procedure GetCompactFormat(const Number: TDecimal; CompactFormat: TCLDRValue; const Locale: TLocale;
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
  Mags: array of string;     { magnitudes as digit strings, largest first }
  I, J, Idx, Forced, Zeros, Round_: Integer;
  T, MagKey, Divisor, Pat, PluralForm: string;
  Scaled, Rounded, Effective: TDecimal;
  C: Char;

  { the index of the largest magnitude not above X; -1 if none }
  function MagnitudeOf(const X: TDecimal): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Mags) do
      if X.Compare(TDecimal.Parse(Mags[K])) >= 0 then
        Exit(K);
    Result := -1;
  end;

  function IsPlain(K: Integer): Boolean;
  begin
    Result := ParseNumberPattern(Others.Str(Mags[K])).Pattern = '0';
  end;

begin
  Format := '';
  Value := Number;
  if Value.IsNaN or Value.IsInfinite then
    Exit;
  Others := CompactFormat.Get('other');
  if Others = nil then
    raise EBabelKeyError.Create('other');
  Mags := nil;
  SetLength(Mags, Others.Count);
  for I := 0 to Others.Count - 1 do
    Mags[I] := TDecimal.Parse(Others.Keys(I).AsString).Truncate.ToString;
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

  Forced := -1;
  for Round_ := 1 to 4 do
  begin
    if Forced >= 0 then
      Idx := Forced
    else
      Idx := MagnitudeOf(Value.Abs);
    if (Idx < 0) or IsPlain(Idx) then
    begin
      { no abbreviation: the whole number, rounded }
      Rounded := Number.Round(FractionDigits);
      J := MagnitudeOf(Rounded.Abs);
      if (J >= 0) and (J <> Idx) and not IsPlain(J) then
      begin
        Forced := J;          { rounding reached an abbreviated magnitude }
        Continue;
      end;
      Value := Rounded;
      Exit;
    end;
    MagKey := Mags[Idx];
    { the zeros of the number of the positive pattern ('elfu 0;elfu -0'
      has one) }
    Pat := ParseNumberPattern(Others.Str(MagKey)).NumberPattern;
    Zeros := 0;
    for C in Pat do
      if C = '0' then
        Inc(Zeros);
    if Zeros = 0 then
      raise EBabelValueError.CreateFmt('compact pattern without digits: %s', [Pat]);
    { magnitude // 10 ** (zeros - 1) }
    if Length(MagKey) > Zeros - 1 then
      Divisor := Copy(MagKey, 1, Length(MagKey) - (Zeros - 1))
    else
      Divisor := '0';
    if (Divisor <> '0') and (Divisor[1] = '1') and
       (Copy(Divisor, 2, MaxInt) = StringOfChar('0', Length(Divisor) - 1)) then
      Scaled := Number.ScaleB(-(Length(Divisor) - 1))
    else
      Scaled := Number.Divide(TDecimal.Parse(Divisor));
    Rounded := Scaled.Round(FractionDigits);
    { rounding up to the next magnitude (999.95K is 1M) }
    Effective := Rounded.Abs.Multiply(TDecimal.Parse(Divisor));
    J := MagnitudeOf(Effective);
    if (J >= 0) and (J < Idx) and not IsPlain(J) then
    begin
      Forced := J;
      Continue;
    end;
    Rounded := Rounded.Normalize;
    { the form for exactly 1 ('1': 'mille'), else the plural form of the
      number shown, else 'other': the first that has this magnitude }
    PluralForm := Locale.PluralForm.Evaluate(Rounded.Abs);
    Format := '';
    if (Rounded.CompareInt(1) = 0) and CompactFormat.Has('1') and
       CompactFormat.Get('1').Has(MagKey) then
      Format := CompactFormat.Get('1').Str(MagKey)
    else if CompactFormat.Has(PluralForm) and CompactFormat.Get(PluralForm).Has(MagKey) then
      Format := CompactFormat.Get(PluralForm).Str(MagKey)
    else
      Format := Others.Str(MagKey);
    Value := Rounded;
    Exit;
  end;
  Value := Number.Round(FractionDigits);
end;

{ The minimum grouping for compact numbers: two digits before the first
  separator at least, as ICU (de: 1234, 12.346). }
function CompactMinGrouping(const Locale: TLocale): Integer;
var
  MG: TCLDRValue;
begin
  MG := Locale.Data.Get('min_grouping_digits');
  Result := 2;
  if (MG <> nil) and (MG.AsInteger > 2) then
    Result := MG.AsInteger;
end;

{ A compact pattern takes its grouping from the locale's decimal pattern
  when it has none (1,000,000T). }
function CompactPattern(const Fmt: string; const Locale: TLocale; const NumberingSystem: string): TNumberPattern;
var
  Dec: TNumberPattern;
begin
  Dec := ParseNumberPattern(LocalePattern(Locale, 'decimal', NumberingSystem));
  if Fmt = '' then
    Exit(Dec);
  Result := ParseNumberPattern(Fmt);
  if Pos(',', Result.NumberPattern) = 0 then
    Result.Grouping := Dec.Grouping;
end;

function FormatCompactDecimal(const Number: TDecimal; const Locale: TLocale): string;
begin
  Result := FormatCompactDecimal(Number, Locale, CompactOptions);
end;

function FormatCompactDecimal(const Number: TDecimal; const Locale: TLocale; const Options: TCompactOptions): string;
var
  Compact: TCLDRValue;
  Value: TDecimal;
  Fmt: string;
  AO: TApplyOptions;
begin
  Compact := Locale.CompactDecimalFormats.Get(Options.FormatType);
  { as ICU, a locale without long forms uses the short ones }
  if (Compact = nil) and (Options.FormatType = 'long') then
    Compact := Locale.CompactDecimalFormats.Get('short');
  if Compact = nil then
    raise EBabelKeyError.Create(Options.FormatType);
  GetCompactFormat(Number, Compact, Locale, Options.FractionDigits, Value, Fmt);
  AO := ApplyOptions;
  AO.DecimalQuantization := False;
  AO.NumberingSystem := Options.NumberingSystem;
  AO.MinGrouping := CompactMinGrouping(Locale);
  Result := CompactPattern(Fmt, Locale, Options.NumberingSystem).Apply(Value, Locale, AO);
end;

function FormatCurrencyLongName(const Number: TDecimal; const Currency: string; const Locale: TLocale;
  const Options: TCurrencyOptions): string;
var
  UnitPattern, DisplayName, Fmt, NumberPart: string;
  AO: TApplyOptions;
  Shown: TDecimal;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := LocalePattern(Locale, 'decimal', Options.NumberingSystem);
  AO := ApplyOptions;
  AO.Currency := Currency;
  AO.CurrencyDigits := Options.CurrencyDigits;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  NumberPart := ParseNumberPattern(Fmt).ApplyShown(Number, Locale, AO, Shown);
  { the plural forms of the number as shown ('1.00' is not 'one' in en) }
  UnitPattern := GetCurrencyUnitPattern(Currency, Shown.Abs, Locale);
  DisplayName := GetCurrencyName(Currency, Shown.Abs, Locale);
  Result := PyFormat2(UnitPattern, NumberPart, DisplayName);
end;

function FormatCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale): string;
begin
  Result := FormatCurrency(Number, Currency, Locale, CurrencyOptions);
end;

function FormatCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale;
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
    Fmt := LocalePattern(Locale, 'currency_' + Options.FormatType, Options.NumberingSystem);
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

function FormatCompactCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale): string;
begin
  Result := FormatCompactCurrency(Number, Currency, Locale, CompactOptions);
end;

function FormatCompactCurrency(const Number: TDecimal; const Currency: string; const Locale: TLocale;
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
  AO.MinGrouping := CompactMinGrouping(Locale);
  Result := CompactPattern(Fmt, Locale, Options.NumberingSystem).Apply(Value, Locale, AO);
end;

function FormatPercent(const Number: TDecimal; const Locale: TLocale): string;
begin
  Result := FormatPercent(Number, Locale, NumberOptions);
end;

function FormatPercent(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := LocalePattern(Locale, 'percent', Options.NumberingSystem);
  AO := ApplyOptions;
  AO.DecimalQuantization := Options.DecimalQuantization;
  AO.GroupSeparator := Options.GroupSeparator;
  AO.NumberingSystem := Options.NumberingSystem;
  Result := ParseNumberPattern(Fmt).Apply(Number, Locale, AO);
end;

function FormatScientific(const Number: TDecimal; const Locale: TLocale): string;
begin
  Result := FormatScientific(Number, Locale, NumberOptions);
end;

function FormatScientific(const Number: TDecimal; const Locale: TLocale; const Options: TNumberOptions): string;
var
  Fmt: string;
  AO: TApplyOptions;
begin
  Fmt := Options.Format;
  if Fmt = '' then
    Fmt := LocalePattern(Locale, 'scientific', Options.NumberingSystem);
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

{ An integer: optional whitespace and sign, decimal digits of any script,
  within Int64. }
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

{ Bidi marks that CLDR puts around signs (LRM, RLM, ALM). }
function StripBidiMarks(const S: string): string;
begin
  Result := StringReplace(S, #$E2#$80#$8E, '', [rfReplaceAll]);
  Result := StringReplace(Result, #$E2#$80#$8F, '', [rfReplaceAll]);
  Result := StringReplace(Result, #$D8#$9C, '', [rfReplaceAll]);
end;

{ The text to parse with the locale's minus and plus signs (as
  FormatDecimal writes them: '−' in sv, '‎-' in ar) written '-' and
  '+', and the bidi marks around them removed. }
function NormalizeSigns(const S: string; const Locale: TLocale; const NumberingSystem: string): string;
var
  Minus, Plus: string;
begin
  Result := StripBidiMarks(S);
  Minus := StripBidiMarks(GetMinusSignSymbol(Locale, NumberingSystem));
  Plus := StripBidiMarks(GetPlusSignSymbol(Locale, NumberingSystem));
  if (Minus <> '') and (Minus <> '-') then
    Result := StringReplace(Result, Minus, '-', [rfReplaceAll]);
  if (Plus <> '') and (Plus <> '+') then
    Result := StringReplace(Result, Plus, '+', [rfReplaceAll]);
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
  T := NormalizeSigns(S, Locale, Options.NumberingSystem);
  if IsSpaceChar(Group) and (Pos(Group, T) = 0) and HasSpaceChar(T) then
    T := ReplaceSpaceChars(T, Group);
  if not PyIntOf(StringReplace(T, Group, '', [rfReplaceAll]), Result) then
    raise ENumberFormatError.CreateWith(PyRepr(S) + ' is not a valid number', nil);
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
  Group, Dec, T, Suggested, SuggestedN, SuggestedAlt: string;
  Alt: TDecimal;
  NO: TNumberOptions;
begin
  Group := GetGroupSymbol(Locale, Options.NumberingSystem);
  Dec := GetDecimalSymbol(Locale, Options.NumberingSystem);
  T := NormalizeSigns(S, Locale, Options.NumberingSystem);
  if not Options.StrictMode and IsSpaceChar(Group) and (Pos(Group, T) = 0) and HasSpaceChar(T) then
    T := ReplaceSpaceChars(T, Group);
  if not TDecimal.TryParse(StringReplace(StringReplace(T, Group, '', [rfReplaceAll]), Dec, '.',
    [rfReplaceAll]), Result) then
    raise ENumberFormatError.CreateWith(PyRepr(S) + ' is not a valid decimal number', nil);
  if Options.StrictMode and (Pos(Group, T) > 0) then
  begin
    NO := NumberOptions.WithDecimalQuantization(False).WithNumberingSystem(Options.NumberingSystem);
    Suggested := FormatDecimal(Result, Locale, NO);
    { compared with the signs written alike on both sides }
    SuggestedN := NormalizeSigns(Suggested, Locale, Options.NumberingSystem);
    if (T <> SuggestedN) and (SuggestedN <> RemoveTrailingZerosAfterDecimal(T, Dec)) then
    begin
      if not TDecimal.TryParse(StringReplace(StringReplace(T, Dec, '', [rfReplaceAll]), Group, '.',
        [rfReplaceAll]), Alt) then
        raise ENumberFormatError.CreateWith(PyRepr(S) + ' is not a properly formatted decimal number. ' +
          'Did you mean ' + PyRepr(Suggested) + '?', [Suggested]);
      SuggestedAlt := FormatDecimal(Alt, Locale, NO);
      if SuggestedAlt = Suggested then
        raise ENumberFormatError.CreateWith(PyRepr(S) + ' is not a properly formatted decimal number. ' +
          'Did you mean ' + PyRepr(Suggested) + '?', [Suggested])
      else
        raise ENumberFormatError.CreateWith(PyRepr(S) + ' is not a properly formatted decimal number. ' +
          'Did you mean ' + PyRepr(Suggested) + '? Or maybe ' + PyRepr(SuggestedAlt) + '?', [Suggested, SuggestedAlt]);
    end;
  end;
end;

end.
