{ test_numbers - checks babel.numbers against the vectors of
  tests/python/gen_numbers_vectors.py (the results of Python Babel 2.18.0
  for the same inputs).

  Usage: test_numbers VECTORS.jsonl   (exit status 1 when a case fails) }
program test_numbers;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, fpjson, testkit,
  babel.errors, babel.decimal, babel.core, babel.numbers, babel.cldr_all;

{ A number as the vectors encode it: [kind, text]. }
function Num(A: TJSONArray): TNumber;
var
  Kind, Text: string;
begin
  Kind := A.Strings[0];
  Text := A.Strings[1];
  if Kind = 'int' then Result := StrToInt64(Text)
  else if Kind = 'float' then Result := DoubleOfHex(Text)
  else if Kind = 'dec' then Result := TDecimal.Parse(Text)
  else Result := Text;
end;

function OptStr(A: TJSONArray; I: Integer): string;
begin
  if A.Items[I].IsNull then
    Result := ''
  else
    Result := A.Strings[I];
end;

function DateOf(A: TJSONArray): TDateTime;
begin
  if A.Count = 0 then
    Result := 0
  else
    Result := EncodeDate(A.Integers[0], A.Integers[1], A.Integers[2]);
end;

function IsoOf(D: TDateTime): string;
begin
  if D = 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy-mm-dd', D);
end;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
var
  NO: TNumberOptions;
  CO: TCurrencyOptions;
  KO: TCompactOptions;
  TO_: TTerritoryCurrencyOptions;
  PO: TParseOptions;
  A: TJSONArray;
  P: TNumberPattern;
  Periods: TCurrencyPeriods;
  I: Integer;
begin
  if (Op = 'format_decimal') or (Op = 'format_percent') or (Op = 'format_scientific') then
  begin
    NO := NumberOptions.WithFormat(OptStr(Args, 2)).WithDecimalQuantization(Args.Booleans[3])
      .WithGroupSeparator(Args.Booleans[4]).WithNumberingSystem(Args.Strings[5]);
    if Op = 'format_decimal' then
      Result := TJSONString.Create(FormatDecimal(Num(Args.Arrays[0]), Args.Strings[1], NO))
    else if Op = 'format_percent' then
      Result := TJSONString.Create(FormatPercent(Num(Args.Arrays[0]), Args.Strings[1], NO))
    else
      Result := TJSONString.Create(FormatScientific(Num(Args.Arrays[0]), Args.Strings[1], NO));
  end
  else if Op = 'symbols' then
    Result := StrArray([GetDecimalSymbol(Args.Strings[0], Args.Strings[1]),
      GetPlusSignSymbol(Args.Strings[0], Args.Strings[1]),
      GetMinusSignSymbol(Args.Strings[0], Args.Strings[1]),
      GetExponentialSymbol(Args.Strings[0], Args.Strings[1]),
      GetGroupSymbol(Args.Strings[0], Args.Strings[1]),
      GetInfinitySymbol(Args.Strings[0], Args.Strings[1])])
  else if Op = 'format_currency' then
  begin
    CO := CurrencyOptions.WithFormat(OptStr(Args, 3)).WithCurrencyDigits(Args.Booleans[4])
      .WithFormatType(Args.Strings[5]).WithDecimalQuantization(Args.Booleans[6])
      .WithGroupSeparator(Args.Booleans[7]).WithNumberingSystem(Args.Strings[8]);
    Result := TJSONString.Create(FormatCurrency(Num(Args.Arrays[0]), Args.Strings[1], Args.Strings[2], CO));
  end
  else if Op = 'currency_info' then
  begin
    A := TJSONArray.Create;
    A.Add(GetCurrencyName(Args.Strings[0], Args.Strings[1]));
    A.Add(GetCurrencySymbol(Args.Strings[0], Args.Strings[1]));
    A.Add(GetCurrencyPrecision(Args.Strings[0]));
    A.Add(GetCurrencyUnitPattern(Args.Strings[0], Args.Strings[1]));
    A.Add(IsCurrency(Args.Strings[0], Args.Strings[1]));
    A.Add(NormalizeCurrency(Args.Strings[0], Args.Strings[1]));
    Result := A;
  end
  else if Op = 'currency_name' then
    Result := StrArray([GetCurrencyName(Args.Strings[0], Num(Args.Arrays[1]), Args.Strings[2]),
      GetCurrencyUnitPattern(Args.Strings[0], Num(Args.Arrays[1]), Args.Strings[2])])
  else if Op = 'list_currencies' then
  begin
    if Args.Strings[0] = '' then
      Result := StrArray(ListCurrencies)
    else
      Result := StrArray(ListCurrencies(Args.Strings[0]));
  end
  else if Op = 'is_currency_global' then
  begin
    A := TJSONArray.Create;
    A.Add(IsCurrency(Args.Strings[0]));
    A.Add(NormalizeCurrency(Args.Strings[0]));
    Result := A;
  end
  else if Op = 'territory_currencies' then
  begin
    TO_ := TerritoryCurrencyOptions.WithStartDate(DateOf(Args.Arrays[1]))
      .WithEndDate(DateOf(Args.Arrays[2])).WithTender(Args.Booleans[3]).WithNonTender(Args.Booleans[4]);
    Periods := GetTerritoryCurrencyDetails(Args.Strings[0], TO_);
    A := TJSONArray.Create;
    for I := 0 to High(Periods) do
    begin
      A.Add(TJSONArray.Create([Periods[I].Currency, IsoOf(Periods[I].FromDate),
        IsoOf(Periods[I].ToDate), Periods[I].Tender]));
    end;
    Result := A;
  end
  else if Op = 'format_compact_decimal' then
  begin
    KO := CompactOptions.WithFormatType(Args.Strings[2]).WithFractionDigits(Args.Integers[3])
      .WithNumberingSystem(Args.Strings[4]);
    Result := TJSONString.Create(FormatCompactDecimal(Num(Args.Arrays[0]), Args.Strings[1], KO));
  end
  else if Op = 'format_compact_currency' then
  begin
    KO := CompactOptions.WithFormatType(Args.Strings[3]).WithFractionDigits(Args.Integers[4])
      .WithNumberingSystem(Args.Strings[5]);
    Result := TJSONString.Create(FormatCompactCurrency(Num(Args.Arrays[0]), Args.Strings[1],
      Args.Strings[2], KO));
  end
  else if Op = 'parse_number' then
    Result := TJSONInt64Number.Create(ParseNumber(Args.Strings[0], Args.Strings[1]))
  else if Op = 'parse_decimal' then
  begin
    PO := ParseOptions.WithStrict(Args.Booleans[2]);
    try
      Result := TJSONString.Create(ParseDecimal(Args.Strings[0], Args.Strings[1], PO).ToString);
    except
      on E: ENumberFormatError do
        Result := TJSONArray.Create(['NumberFormatError', StrArray(E.Suggestions)]);
    end;
  end
  else if Op = 'parse_pattern' then
  begin
    P := ParseNumberPattern(Args.Strings[0]);
    A := TJSONArray.Create;
    A.Add(P.PosPrefix);
    A.Add(P.NegPrefix);
    A.Add(P.PosSuffix);
    A.Add(P.NegSuffix);
    A.Add(P.NumberPattern);
    A.Add(TJSONArray.Create([P.Grouping.Min, P.Grouping.Max]));
    A.Add(TJSONArray.Create([P.IntPrec.Min, P.IntPrec.Max]));
    A.Add(TJSONArray.Create([P.FracPrec.Min, P.FracPrec.Max]));
    if P.HasExp then
    begin
      A.Add(TJSONArray.Create([P.ExpPrec.Min, P.ExpPrec.Max]));
      A.Add(P.ExpPlus);
    end
    else
    begin
      A.Add(TJSONNull.Create);
      A.Add(TJSONNull.Create);
    end;
    A.Add(P.Scale);
    Result := A;
  end
  else if Op = 'parse_grouping' then
    Result := TJSONArray.Create([ParseGrouping(Args.Strings[0]).Min, ParseGrouping(Args.Strings[0]).Max])
  else
    raise Exception.Create('unknown op ' + Op);
end;

begin
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_numbers VECTORS.jsonl');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
