{ gencldr - generates the CLDR data units of Babel4Pascal (src/data/*.pas)
  from the CLDR XML release.

  gencldr fetch
      Download cldr-common-<version>.zip from unicode.org into the cache
      directory (checking its SHA-512) and extract it there. Prints the
      path of its common/ directory.

  gencldr generate [--locales modern|all|ID,ID,...] [--out DIR]
      Fetch if needed, then write one unit per locale, babel.cldr_global
      and babel.cldr_all into DIR (default <root>/src/data; its
      babel.cldr_*.pas files are deleted first). modern (the default): the
      locales whose coverage level in common/properties/coverageLevels.txt
      is "modern", or that inherit from such a locale. all: every locale
      of the release. A list: those locales. The locales they inherit from
      (up to root) are always added.

  Options of both commands:
    --root DIR   the repository root. Default: the first directory, from
                 the directory of this program upwards, then from the
                 current directory upwards, that holds fpmake.pp and
                 tools/gencldr/gencldr.pas.
    --cache DIR  the cache directory (default <root>/.cache/cldr).

  Build: fpc -Mobjfpc -Sh -O2 -FUbuild/gencldr -FEbuild/gencldr
  tools/gencldr/gencldr.pas (tools/install-package.sh does). Needs only
  FPC's own packages (fcl-net, fcl-web for HTTPS with OpenSSL, paszlib)
  and tools/gencldr/sha2.pas.

  The output is the same, byte for byte, as tools/gencldr.py's (the
  Python generator kept for the development checks; tests/run_all.sh
  compares them). }
program gencldr;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, cldr.pystr, cldr.values, cldr.etree, cldr.encode,
  cldr.importer, cldr.locales, cldr.pascalout, cldr.fetch;

type
  EUsage = class(Exception);

procedure Usage;
begin
  WriteLn('usage: gencldr [--root DIR] [--cache DIR] fetch');
  WriteLn('       gencldr [--root DIR] [--cache DIR] generate [--locales modern|all|ID,ID,...] [--out DIR]');
end;

function IsRoot(const Dir: string): Boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(Dir) + 'fpmake.pp') and
    FileExists(IncludeTrailingPathDelimiter(Dir) + 'tools' + PathDelim + 'gencldr' +
    PathDelim + 'gencldr.pas');
end;

function SearchUp(const Start: string): string;
var
  Dir, Parent: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(Start));
  while True do
  begin
    if IsRoot(Dir) then
      Exit(Dir);
    Parent := ExcludeTrailingPathDelimiter(ExtractFileDir(Dir));
    if (Parent = Dir) or (Parent = '') then
      Exit('');
    Dir := Parent;
  end;
end;

function FindRoot: string;
begin
  Result := SearchUp(ExtractFileDir(ExpandFileName(ParamStr(0))));
  if Result = '' then
    Result := SearchUp(GetCurrentDir);
  if Result = '' then
    raise EUsage.Create('cannot find the repository root (fpmake.pp and ' +
      'tools/gencldr/gencldr.pas) from this program''s directory or the current ' +
      'directory; give --root');
end;

function Contains(const A: TStringArray; const S: string): Boolean;
var
  T: string;
begin
  for T in A do
    if T = S then
      Exit(True);
  Result := False;
end;

procedure Generate(const Selection, OutDir, CacheDir: string);
var
  SrcDir, Name, F, Dir: string;
  GlobalData: TValue;
  Imp: TLocaleImporter;
  AllNames, Wanted, Names, Unknown, Units: TStringArray;
  Files, Sorted: TStringList;
  SR: TSearchRec;
  Total: Int64;
  Blob: TBytes;
  Mark, J: Integer;
begin
  SrcDir := Fetch(CacheDir);
  GlobalData := ParseGlobal(SrcDir);
  Imp := TLocaleImporter.Create(SrcDir);
  try
    AllNames := Imp.LocaleNames;
    if Selection = 'modern' then
      Wanted := ModernLocales(AllNames, SrcDir, GlobalData)
    else if Selection = 'all' then
      Wanted := AllNames
    else
    begin
      Wanted := nil;
      for Name in PySplitSep(Selection, ',') do
        if PyStrip(Name) <> '' then
        begin
          SetLength(Wanted, Length(Wanted) + 1);
          Wanted[High(Wanted)] := PyStrip(Name);
        end;
      Sorted := TStringList.Create;
      try
        Sorted.CaseSensitive := True;
        Sorted.Sorted := True;
        Sorted.Duplicates := dupIgnore;
        for Name in Wanted do
          if not Contains(AllNames, Name) then
            Sorted.Add(Name);
        if Sorted.Count > 0 then
        begin
          Unknown := nil;
          SetLength(Unknown, Sorted.Count);
          for J := 0 to Sorted.Count - 1 do
            Unknown[J] := Sorted[J];
          raise EUsage.Create('unknown locales: ' + string.Join(', ', Unknown));
        end;
      finally
        Sorted.Free;
      end;
    end;
    Names := WithAncestors(Wanted, GlobalData);

    Files := TStringList.Create;
    try
      Files.CaseSensitive := True;
      Files.Sorted := True;
      Files.Duplicates := dupIgnore;
      for Name in Names do
        Files.Add(FileName(UnitName(Name)));
      if Files.Count <> Length(Names) then
        raise EUsage.Create('two locales map to the same unit file name');
    finally
      Files.Free;
    end;

    Dir := ExcludeTrailingPathDelimiter(OutDir);
    if DirectoryExists(Dir) then
    begin
      if FindFirst(IncludeTrailingPathDelimiter(Dir) + 'babel.cldr_*.pas', faAnyFile, SR) = 0 then
      try
        repeat
          F := SR.Name;
          if (Copy(F, 1, 11) = 'babel.cldr_') and (Copy(F, Length(F) - 3, 4) = '.pas') then
            DeleteFile(IncludeTrailingPathDelimiter(Dir) + F);
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;
    if not ForceDirectories(Dir) then
      raise EUsage.CreateFmt('cannot create %s', [Dir]);

    Total := 0;
    Blob := Encode(GlobalData);
    Inc(Total, Length(Blob));
    WriteGlobalUnit(Dir, CldrVersion, Blob);
    SetLength(Units, Length(Names));
    for J := 0 to High(Names) do
    begin
      Mark := ArenaMark;
      Blob := Encode(Imp.ImportLocale(Names[J]));
      ArenaRelease(Mark);
      Inc(Total, Length(Blob));
      Units[J] := WriteLocaleUnit(Dir, CldrVersion, Names[J], ParentOf(Names[J], GlobalData),
        Blob);
    end;
    WriteAllUnit(Dir, CldrVersion, Units);
    WriteLn(Length(Names), ' locales (', Length(Wanted), ' selected), ', Total,
      ' bytes of data, in ', OutDir);
  finally
    Imp.Free;
  end;
end;

var
  Command, Locales, OutDir, Root, CacheDir, Arg, Opt, Value: string;
  I, Eq: Integer;
  HasOut: Boolean;
begin
  Command := '';
  Locales := 'modern';
  OutDir := '';
  HasOut := False;
  Root := '';
  CacheDir := '';
  try
    I := 1;
    while I <= ParamCount do
    begin
      Arg := ParamStr(I);
      if (Arg = '-h') or (Arg = '--help') then
      begin
        Usage;
        Halt(0);
      end;
      if Copy(Arg, 1, 2) = '--' then
      begin
        Eq := Pos('=', Arg);
        if Eq > 0 then
        begin
          Opt := Copy(Arg, 1, Eq - 1);
          Value := Copy(Arg, Eq + 1, MaxInt);
        end
        else
        begin
          Opt := Arg;
          Inc(I);
          if I > ParamCount then
            raise EUsage.CreateFmt('%s needs a value', [Opt]);
          Value := ParamStr(I);
        end;
        if Opt = '--locales' then
          Locales := Value
        else if Opt = '--out' then
        begin
          OutDir := Value;
          HasOut := True;
        end
        else if Opt = '--root' then
          Root := Value
        else if Opt = '--cache' then
          CacheDir := Value
        else
          raise EUsage.CreateFmt('unknown option %s', [Opt]);
      end
      else if Command = '' then
        Command := Arg
      else
        raise EUsage.CreateFmt('unexpected argument %s', [Arg]);
      Inc(I);
    end;
    if (Command <> 'fetch') and (Command <> 'generate') then
    begin
      Usage;
      Halt(2);
    end;
    if (Command = 'fetch') and (HasOut or (Locales <> 'modern')) then
      raise EUsage.Create('fetch takes no --locales or --out');
    if Root = '' then
      Root := FindRoot
    else
      Root := ExcludeTrailingPathDelimiter(ExpandFileName(Root));
    if CacheDir = '' then
      CacheDir := Root + PathDelim + '.cache' + PathDelim + 'cldr';
    if not HasOut then
      OutDir := Root + PathDelim + 'src' + PathDelim + 'data';
    if Command = 'fetch' then
      WriteLn(Fetch(CacheDir))
    else
      Generate(Locales, OutDir, CacheDir);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'gencldr: ', E.Message);
      Halt(1);
    end;
  end;
end.
