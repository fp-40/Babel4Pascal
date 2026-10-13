{ test_lists - checks babel.lists against vector files: its reference
  cases (tests/lists/reference.jsonl), ICU4C's results
  (tests/icu/icu_lists_units.c, the icu_list operation).

  Usage: test_lists VECTORS.jsonl   (exit status 1 when a case fails)
         test_lists VECTORS.jsonl --update OUT.jsonl }
program test_lists;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, testkit, babel.lists, babel.cldr_all;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
begin
  if (Op = 'format_list') or (Op = 'icu_list') then
    Result := TJSONString.Create(FormatList(StrList(Args.Arrays[0]), Args.Strings[2], Args.Strings[1]))
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
    WriteLn('usage: test_lists VECTORS.jsonl [--update OUT.jsonl]');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
