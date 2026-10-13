{ test_tz - checks babel.tz against the vectors of
  tests/python/gen_tz_vectors.py (Python's zoneinfo on the same tz
  database files).

  Usage: test_tz VECTORS.jsonl   (exit status 1 when a case fails) }
program test_tz;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, testkit, babel.tz;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
var
  Z: TTimeZone;
  Instants, Row, A: TJSONArray;
  I: Integer;
  Info: TZoneInfo;
begin
  if (Op <> 'tz') and (Op <> 'tz_local') then
    raise Exception.Create('unknown op ' + Op);
  Z := GetTimeZone(Args.Strings[0]);
  Instants := Args.Arrays[1];
  A := TJSONArray.Create;
  for I := 0 to Instants.Count - 1 do
  begin
    if Op = 'tz' then
      Info := Z.InfoAt(Instants.Int64s[I])
    else
      Info := Z.InfoAtLocal(Instants.Arrays[I].Int64s[0], Instants.Arrays[I].Integers[1]);
    Row := TJSONArray.Create([Info.UTCOffset, Info.DSTOffset, Info.Abbreviation]);
    A.Add(Row);
  end;
  Result := A;
end;

begin
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_tz VECTORS.jsonl');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
