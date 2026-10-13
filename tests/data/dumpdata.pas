(* dumpdata - writes the data of locales as JSON, one line per locale
  ("<name>\t<json>"), for tests/python/compare_dump.py.

  A map is written as {"m": [[key, value], ...]} in insertion order (its
  keys can be null, integers or strings); lists, strings, numbers, null and
  booleans as JSON.

  Usage: dumpdata [--global] [LOCALE ...]   (no LOCALE: every linked locale) *)
program dumpdata;

{$mode objfpc}{$H+}

uses
  SysUtils, babel.localedata, babel.cldr_all, babel.cldr_global;

procedure WriteJSONString(var F: Text; const S: string);
var
  C: Char;
begin
  Write(F, '"');
  for C in S do
    case C of
      '"': Write(F, '\"');
      '\': Write(F, '\\');
      #0..#31: Write(F, '\u', IntToHex(Ord(C), 4));
    else
      Write(F, C);
    end;
  Write(F, '"');
end;

procedure WriteValue(var F: Text; V: TCLDRValue);
var
  I: Integer;
begin
  case V.Kind of
    ckNone: Write(F, 'null');
    ckBool: if V.AsBoolean then Write(F, 'true') else Write(F, 'false');
    ckInt: Write(F, V.AsInteger);
    ckFloat: Write(F, FloatToStrF(V.AsFloat, ffGeneral, 17, 0, DefaultFormatSettings));
    ckString: WriteJSONString(F, V.AsString);
    ckList:
      begin
        Write(F, '[');
        for I := 0 to V.Count - 1 do
        begin
          if I > 0 then Write(F, ',');
          WriteValue(F, V.Items(I));
        end;
        Write(F, ']');
      end;
    ckMap:
      begin
        Write(F, '{"m":[');
        for I := 0 to V.Count - 1 do
        begin
          if I > 0 then Write(F, ',');
          Write(F, '[');
          WriteValue(F, V.Keys(I));
          Write(F, ',');
          WriteValue(F, V.Items(I));
          Write(F, ']');
        end;
        Write(F, ']}');
      end;
  else
    raise Exception.Create('unresolved alias in loaded data');
  end;
end;

var
  Names: TStringArray;
  I: Integer;
  Keys: array of string = ('cldr', 'all_currencies', 'currency_fractions', 'language_aliases',
    'likely_subtags', 'meta_zones', 'parent_exceptions', 'script_aliases',
    'territory_aliases', 'territory_currencies', 'territory_languages',
    'territory_zones', 'variant_aliases', 'windows_zone_mapping', 'zone_aliases',
    'zone_territories');
  K: string;
begin
  DefaultFormatSettings.DecimalSeparator := '.';
  if (ParamCount = 1) and (ParamStr(1) = '--global') then
  begin
    for K in Keys do
    begin
      Write(K, #9);
      WriteValue(Output, GetGlobal(K));
      WriteLn;
    end;
    Exit;
  end;
  if ParamCount > 0 then
  begin
    SetLength(Names, ParamCount);
    for I := 1 to ParamCount do
      Names[I - 1] := ParamStr(I);
  end
  else
    Names := Concat(['root'], LocaleIdentifiers);
  for I := 0 to High(Names) do
  begin
    Write(Names[I], #9);
    WriteValue(Output, LoadLocaleData(Names[I]));
    WriteLn;
  end;
end.
