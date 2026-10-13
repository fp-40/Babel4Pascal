{ test_units - checks babel.units against vector files: its reference
  cases (tests/units/reference.jsonl), ICU4C's results
  (tests/icu/icu_lists_units.c).

  Usage: test_units VECTORS.jsonl   (exit status 1 when a case fails)
         test_units VECTORS.jsonl --update OUT.jsonl }
program test_units;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, testkit, babel.decimal, babel.units, babel.cldr_all;

function Num(A: TJSONArray): TDecimal;
var
  Kind, Text: string;
begin
  Kind := A.Strings[0];
  Text := A.Strings[1];
  if Kind = 'int' then Result := StrToInt64(Text)
  else if Kind = 'float' then Result := DoubleOfHex(Text)
  else Result := TDecimal.Parse(Text);
end;

function IsText(A: TJSONArray): Boolean;
begin
  Result := A.Strings[0] = 'str';
end;

function OptStr(A: TJSONArray; I: Integer): string;
begin
  if A.Items[I].IsNull then
    Result := ''
  else
    Result := A.Strings[I];
end;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
var
  O: TUnitOptions;
begin
  if Op = 'unit_name' then
    Result := TJSONString.Create(GetUnitName(Args.Strings[0], Args.Strings[2], Args.Strings[1]))
  else if Op = 'format_unit' then
  begin
    O := UnitOptions.WithLength(Args.Strings[2]).WithFormat(OptStr(Args, 3))
      .WithNumberingSystem(Args.Strings[4]);
    if IsText(Args.Arrays[0]) then
      Result := TJSONString.Create(FormatUnitText(Args.Arrays[0].Strings[1], Args.Strings[1],
        Args.Strings[5], O))
    else
      Result := TJSONString.Create(FormatUnit(Num(Args.Arrays[0]), Args.Strings[1], Args.Strings[5], O));
  end
  else if Op = 'compound' then
  begin
    O := UnitOptions.WithLength(Args.Strings[4]).WithFormat(OptStr(Args, 5))
      .WithNumberingSystem(Args.Strings[6]);
    if IsText(Args.Arrays[0]) then
      Result := TJSONString.Create(FormatCompoundUnitText(Args.Arrays[0].Strings[1], Args.Strings[1],
        Args.Arrays[2].Strings[1], Args.Strings[3], Args.Strings[7], O))
    else
      Result := TJSONString.Create(FormatCompoundUnit(Num(Args.Arrays[0]), Args.Strings[1],
        Num(Args.Arrays[2]), Args.Strings[3], Args.Strings[7], O));
  end
  { ICU4C's results (tests/icu/icu_lists_units.c), with the locale's digits }
  else if Op = 'icu_unit' then
    Result := TJSONString.Create(FormatUnit(TDecimal.Parse(Args.Strings[0]), Args.Strings[1],
      Args.Strings[3], UnitOptions.WithLength(Args.Strings[2]).WithNumberingSystem('default')))
  else if Op = 'icu_unit_per' then
    Result := TJSONString.Create(FormatCompoundUnit(TDecimal.Parse(Args.Strings[0]), Args.Strings[1],
      1, Args.Strings[2], Args.Strings[4], UnitOptions.WithLength(Args.Strings[3])
      .WithNumberingSystem('default')))
  else
    raise Exception.Create('unknown op ' + Op);
end;

begin
  if (ParamCount = 3) and (ParamStr(2) = '--update') then
  begin
    RunVectors(ParamStr(1), @Handle, nil, ParamStr(3));
    Exit;
  end;
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_units VECTORS.jsonl [--update OUT.jsonl]');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
