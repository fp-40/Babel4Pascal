{ testkit - runs a file of test vectors (one JSON object per line:
  {"op", "args", "expect" | "error"}) through a handler and compares the
  results, for the test programs under tests/.

  The handler returns the result of one case as JSON; the expected value
  and the result are compared by their fpjson serialization. An exception
  is compared by the name of the Python exception it stands for
  (ErrorName). Strings are UTF-8 throughout (cwstring and CP_UTF8). }
unit testkit;

{$mode objfpc}{$H+}

interface

uses
  cwstring, SysUtils, Classes, fpjson, jsonparser;

type
  TCaseHandler = function(const Op: string; Args: TJSONArray): TJSONData;
  { For lines that are not a single case (inputs shared by later cases,
    or a batch checked by the handler itself); returns True when it
    handled the line. }
  TLineHandler = function(Line: TJSONObject): Boolean;

{ Runs the file; prints failures (up to 40) and a summary; returns the
  number of failed cases. With UpdateFile <> '', also writes the file
  again there with the results obtained as the expected values (to
  update a reference file after a deliberate change; review the diff). }
function RunVectors(const FileName: string; Handler: TCaseHandler;
  LineHandler: TLineHandler = nil; const UpdateFile: string = ''): Integer;
{ Counts a case checked outside RunVectors' comparison. }
procedure Check(const Op: string; OK: Boolean; const Detail: string);
function ErrorName(E: Exception): string;
function StrArray(const A: array of string): TJSONArray;
function StrList(A: TJSONArray): TStringArray;
{ A double from 16 hex digits of its bits. }
function DoubleOfHex(const S: string): Double;

implementation

uses
  babel.errors, babel.core, babel.plural, babel.numbers;

var
  Failures, Total: Integer;
  OpFails: TStringList;
  Updating: Boolean;
  UpdateOut: TextFile;

function ErrorName(E: Exception): string;
begin
  if E is EUnknownLocaleError then Result := 'UnknownLocaleError'
  else if E is EPluralRuleError then Result := 'RuleError'
  else if E is EUnknownCurrencyError then Result := 'UnknownCurrencyError'
  else if E is EUnsupportedNumberingSystemError then Result := 'UnsupportedNumberingSystemError'
  else if E is EUnknownCurrencyFormatError then Result := 'UnknownCurrencyFormatError'
  else if E is ENumberFormatError then Result := 'NumberFormatError'
  else if E is EBabelValueError then Result := 'ValueError'
  else if E is EBabelTypeError then Result := 'TypeError'
  else if E is EBabelKeyError then Result := 'KeyError'
  else if E is EBabelOverflowError then Result := 'OverflowError'
  else if E is EBabelDecimalError then Result := 'DecimalException'
  else Result := E.ClassName + ': ' + E.Message;
end;

function StrArray(const A: array of string): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in A do
    Result.Add(S);
end;

function StrList(A: TJSONArray): TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
    Result[I] := A.Strings[I];
end;

function DoubleOfHex(const S: string): Double;
var
  Q: QWord;
begin
  Q := StrToQWord('$' + S);
  Move(Q, Result, 8);
end;

procedure Fail(const Op, Detail: string);
begin
  Inc(Failures);
  OpFails.Values[Op] := IntToStr(StrToIntDef(OpFails.Values[Op], 0) + 1);
  if Failures <= 40 then
    WriteLn('FAIL ', Op, ': ', Detail);
end;

procedure Check(const Op: string; OK: Boolean; const Detail: string);
begin
  Inc(Total);
  if not OK then
    Fail(Op, Detail);
end;

{ The line with GotText ('error X' or JSON) as its expected result. }
procedure WriteUpdated(Line: TJSONObject; const GotText: string);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.Add('op', Line.Strings['op']);
    O.Add('args', Line.Arrays['args'].Clone);
    if Copy(GotText, 1, 6) = 'error ' then
      O.Add('error', Copy(GotText, 7, MaxInt))
    else
      O.Add('expect', GetJSON(GotText));
    WriteLn(UpdateOut, O.AsJSON);
  finally
    O.Free;
  end;
end;

procedure RunCase(Line: TJSONObject; Handler: TCaseHandler);
var
  Op, Want, GotText: string;
  Got: TJSONData;
begin
  Op := Line.Strings['op'];
  Inc(Total);
  if Line.IndexOfName('error') >= 0 then
    Want := 'error ' + Line.Strings['error']
  else
    Want := Line.Elements['expect'].AsJSON;
  try
    Got := Handler(Op, Line.Arrays['args']);
    try
      GotText := Got.AsJSON;
    finally
      Got.Free;
    end;
  except
    on E: Exception do
      GotText := 'error ' + ErrorName(E);
  end;
  if GotText <> Want then
    Fail(Op, Line.Arrays['args'].AsJSON + LineEnding + '    got  ' + Copy(GotText, 1, 400) +
      LineEnding + '    want ' + Copy(Want, 1, 400));
  if Updating then
    WriteUpdated(Line, GotText);
end;

function RunVectors(const FileName: string; Handler: TCaseHandler; LineHandler: TLineHandler;
  const UpdateFile: string): Integer;
var
  F: TextFile;
  S: string;
  J: TJSONData;
  I: Integer;
begin
  DefaultSystemCodePage := CP_UTF8;
  SetMultiByteConversionCodePage(CP_UTF8);
  Updating := UpdateFile <> '';
  if Updating then
  begin
    AssignFile(UpdateOut, UpdateFile);
    Rewrite(UpdateOut);
  end;
  AssignFile(F, FileName);
  Reset(F);
  while not EOF(F) do
  begin
    ReadLn(F, S);
    if S = '' then
      Continue;
    J := GetJSON(S);
    try
      if not (Assigned(LineHandler) and LineHandler(TJSONObject(J))) then
        RunCase(TJSONObject(J), Handler);
    finally
      J.Free;
    end;
  end;
  CloseFile(F);
  if Updating then
    CloseFile(UpdateOut);
  for I := 0 to OpFails.Count - 1 do
    WriteLn('  ', OpFails.Names[I], ': ', OpFails.ValueFromIndex[I], ' failed');
  WriteLn(Total, ' cases, ', Failures, ' failed');
  Result := Failures;
end;

initialization
  OpFails := TStringList.Create;
finalization
  OpFails.Free;
end.
