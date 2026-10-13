{ test_format - checks babel.support's TFormat against vector files: its
  reference cases (tests/format/reference.jsonl).

  Usage: test_format VECTORS.jsonl   (exit status 1 when a case fails)
         test_format VECTORS.jsonl --update OUT.jsonl }
program test_format;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, fpjson, testkit, babel.decimal, babel.support, babel.cldr_all;

function Num(A: TJSONArray): TDecimal;
begin
  if A.Strings[0] = 'int' then Result := StrToInt64(A.Strings[1])
  else if A.Strings[0] = 'float' then Result := DoubleOfHex(A.Strings[1])
  else Result := TDecimal.Parse(A.Strings[1]);
end;

function DT(A: TJSONArray): TDateTime;
begin
  Result := EncodeDateTime(A.Integers[0], A.Integers[1], A.Integers[2], A.Integers[3],
    A.Integers[4], A.Integers[5], A.Integers[6]);
end;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
var
  F: TFormat;
  S: string;
begin
  F := TFormat.Create(Args.Arrays[0].Strings[0], Args.Arrays[0].Strings[1], Args.Arrays[0].Strings[2]);
  if Op = 'date' then S := F.Date(DT(Args.Arrays[1]), Args.Strings[2])
  else if Op = 'datetime' then S := F.DateTime(DT(Args.Arrays[1]), Args.Strings[2])
  else if Op = 'time' then S := F.Time(DT(Args.Arrays[1]), Args.Strings[2])
  else if Op = 'timedelta' then
    S := F.Timedelta(Args.Int64s[1], Args.Strings[2], Args.Floats[3], Args.Strings[4], Args.Booleans[5])
  else if Op = 'number' then S := F.Number(Num(Args.Arrays[1]))
  else if Op = 'decimal' then S := F.Decimal(Num(Args.Arrays[1]), Args.Strings[2])
  else if Op = 'compact_decimal' then
    S := F.CompactDecimal(Num(Args.Arrays[1]), Args.Strings[2], Args.Integers[3])
  else if Op = 'currency' then S := F.Currency(Num(Args.Arrays[1]), Args.Strings[2])
  else if Op = 'compact_currency' then
    S := F.CompactCurrency(Num(Args.Arrays[1]), Args.Strings[2], Args.Strings[3], Args.Integers[4])
  else if Op = 'percent' then S := F.Percent(Num(Args.Arrays[1]), Args.Strings[2])
  else if Op = 'scientific' then S := F.Scientific(Num(Args.Arrays[1]))
  else
    raise Exception.Create('unknown op ' + Op);
  Result := TJSONString.Create(S);
end;

begin
  if (ParamCount = 3) and (ParamStr(2) = '--update') then
  begin
    RunVectors(ParamStr(1), @Handle, nil, ParamStr(3));
    Exit;
  end;
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_format VECTORS.jsonl [--update OUT.jsonl]');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
