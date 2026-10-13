{ test_languages - checks babel.languages against vector files: its
  reference cases (tests/languages/reference.jsonl) or Python Babel's
  (tests/python/gen_languages_vectors.py).

  Usage: test_languages VECTORS.jsonl   (exit status 1 when a case fails)
         test_languages VECTORS.jsonl --update OUT.jsonl }
program test_languages;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, testkit, babel.languages, babel.cldr_all;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
var
  Info: TTerritoryLanguages;
  L: TTerritoryLanguage;
  A: TJSONArray;
begin
  if Op = 'official' then
    Result := StrArray(GetOfficialLanguages(Args.Strings[0], Args.Booleans[1], Args.Booleans[2]))
  else if Op = 'info' then
  begin
    Info := GetTerritoryLanguageInfo(Args.Strings[0]);
    A := TJSONArray.Create;
    for L in Info do
      A.Add(TJSONArray.Create([L.Language, TJSONFloatNumber.Create(L.PopulationPercent), L.OfficialStatus]));
    Result := A;
  end
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
    WriteLn('usage: test_languages VECTORS.jsonl [--update OUT.jsonl]');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
