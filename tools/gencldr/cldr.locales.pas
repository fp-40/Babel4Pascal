{ cldr.locales - locale inheritance and the choice of locales to
  generate. }
unit cldr.locales;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, cldr.pystr, cldr.values, cldr.etree;

{ The locale whose data Name inherits: an explicit CLDR parentLocale; root
  for a 'lang_Script' locale whose script is not the language's likely
  script; else the identifier without its last subtag; root for a
  language alone. '' for root. }
function ParentOf(const Name: string; GlobalData: TValue): string;
{ Name, its parent, ..., up to (and without) root. }
function Chain(const Name: string; GlobalData: TValue): TStringArray;
{ The locales whose nearest ancestor (or themselves) listed in
  common/properties/coverageLevels.txt has level 'modern'. }
function ModernLocales(const AllNames: TStringArray; const SrcDir: string;
  GlobalData: TValue): TStringArray;
{ Names plus every locale they inherit from, root first, then sorted. }
function WithAncestors(const Names: TStringArray; GlobalData: TValue): TStringArray;

implementation

{ The script subtag of a 'lang_Script' identifier (title case), else ''. }
function ScriptOf(const Name: string): string;
var
  Parts: TStringArray;
  J: Integer;
begin
  Result := '';
  Parts := PySplitSep(Name, '_');
  if (Length(Parts) <> 2) or (Length(Parts[1]) <> 4) then
    Exit;
  for J := 1 to 4 do
    if not (Parts[1][J] in ['A'..'Z', 'a'..'z']) then
      Exit;
  Result := UpperCase(Parts[1][1]) + LowerCase(Copy(Parts[1], 2, 3));
end;

function ParentOf(const Name: string; GlobalData: TValue): string;
var
  V: TValue;
  Script, Lang: string;
  Parts, LParts: TStringArray;
  J: Integer;
begin
  if Name = 'root' then
    Exit('');
  V := GlobalData.Get(KS('parent_exceptions')).Get(KS(Name));
  if (V <> nil) and (V.S <> '') then
    Exit(V.S);
  Parts := PySplitSep(Name, '_');
  Script := ScriptOf(Name);
  if Script <> '' then
  begin
    Lang := Parts[0];
    V := GlobalData.Get(KS('likely_subtags')).Get(KS(Lang));
    if (V <> nil) and (V.S <> '') then
    begin
      LParts := PySplitSep(V.S, '_');
      if Length(LParts) > 2 then
        SetLength(LParts, 2);
      if ScriptOf(string.Join('_', LParts)) <> Script then
        Exit('root');
    end;
  end;
  if Length(Parts) = 1 then
    Exit('root');
  Result := Parts[0];
  for J := 1 to High(Parts) - 1 do
    Result := Result + '_' + Parts[J];
end;

function Chain(const Name: string; GlobalData: TValue): TStringArray;
var
  N: string;
begin
  Result := nil;
  N := Name;
  while N <> 'root' do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := N;
    N := ParentOf(N, GlobalData);
  end;
end;

function ModernLocales(const AllNames: TStringArray; const SrcDir: string;
  GlobalData: TValue): TStringArray;
var
  Levels: TValue;
  Lines: TStringList;
  Line, Name, C, Level: string;
  Parts: TStringArray;
  V: TValue;
  N: Integer;
begin
  Levels := VMap;
  Lines := TStringList.Create;
  try
    Lines.Text := ReadFileBytes(IncludeTrailingPathDelimiter(SrcDir) + 'properties' +
      PathDelim + 'coverageLevels.txt');
    for Line in Lines do
    begin
      if (Copy(Line, 1, 1) = '#') or (Pos(';', Line) = 0) then
        Continue;
      Parts := PySplitSep(Line, ';');
      Levels.Put(KS(PyStrip(Parts[0])), VStr(PyStrip(Parts[1])));
    end;
  finally
    Lines.Free;
  end;
  Result := nil;
  N := 0;
  for Name in AllNames do
  begin
    if Name = 'root' then
      Continue;
    Level := '';
    for C in Chain(Name, GlobalData) do
    begin
      V := Levels.Get(KS(C));
      if V <> nil then
      begin
        Level := V.S;
        Break;
      end;
    end;
    if Level = 'modern' then
    begin
      SetLength(Result, N + 1);
      Result[N] := Name;
      Inc(N);
    end;
  end;
end;

function CompareStringListBytes(List: TStringList; I1, I2: Integer): Integer;
begin
  Result := CompareBytes(List[I1], List[I2]);
end;

function WithAncestors(const Names: TStringArray; GlobalData: TValue): TStringArray;
var
  Out_: TStringList;
  Name, C: string;
  J: Integer;
begin
  Out_ := TStringList.Create;
  try
    Out_.CaseSensitive := True;
    Out_.Sorted := True;
    Out_.Duplicates := dupIgnore;
    for Name in Names do
      for C in Chain(Name, GlobalData) do
        Out_.Add(C);
    Out_.Sorted := False;
    Out_.CustomSort(@CompareStringListBytes);
    Result := nil;
    SetLength(Result, Out_.Count + 1);
    Result[0] := 'root';
    for J := 0 to Out_.Count - 1 do
      Result[J + 1] := Out_[J];
  finally
    Out_.Free;
  end;
end;

end.
