{ test_testkit - checks DecodeNonAsciiEscapes: lines with \u escapes,
  parsed through it and fpjson, give the right UTF-8 strings, including
  consecutive escapes of characters from U+0800 up, which FPC 3.2.2's
  fpjson alone decodes wrongly. The backslash is built at run time (B),
  so the escapes are in the strings parsed and nowhere else. }
program test_testkit;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, testkit;

var
  B: string;
  Failed: Integer = 0;
  Total: Integer = 0;

procedure CheckLine(const Esc, Expected: string);
var
  J: TJSONData;
  Src, Got: string;
begin
  Inc(Total);
  Src := '{"s": "' + StringReplace(Esc, '%', B, [rfReplaceAll]) + '"}';
  J := GetJSON(DecodeNonAsciiEscapes(Src));
  try
    Got := TJSONObject(J).Strings['s'];
  finally
    J.Free;
  end;
  if Got <> Expected then
  begin
    Inc(Failed);
    WriteLn('FAIL ', Src, ': got ', Got);
  end;
end;

begin
  DefaultSystemCodePage := CP_UTF8;
  SetMultiByteConversionCodePage(CP_UTF8);
  B := Chr(92);
  CheckLine('%u2013', #$E2#$80#$93);
  CheckLine('a%u2013b', 'a'#$E2#$80#$93'b');
  CheckLine('%u2009%u2013', #$E2#$80#$89#$E2#$80#$93);
  CheckLine('%u2013%u2013', #$E2#$80#$93#$E2#$80#$93);
  CheckLine('%u2009%u2013%u2009', #$E2#$80#$89#$E2#$80#$93#$E2#$80#$89);
  CheckLine('%u00e9%u00e9%u00e9', #$C3#$A9#$C3#$A9#$C3#$A9);
  CheckLine('%u0041%u0042', 'AB');
  CheckLine('%ud83d%ude00', #$F0#$9F#$98#$80);
  CheckLine('%ud83d%ude00%u2013', #$F0#$9F#$98#$80#$E2#$80#$93);
  { escapes kept for fpjson: quote, backslash, control characters }
  CheckLine('%u0022%u005c', '"\');
  CheckLine('%%u2013', B + 'u2013');
  CheckLine('%%%u2013', '\'#$E2#$80#$93);
  CheckLine('%n%t', #10#9);
  WriteLn(Total, ' cases, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
