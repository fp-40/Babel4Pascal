(* gencldr - generates the CLDR data units of Babel4Pascal (src/data/*.pas)
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

  gencldr dump [--locales modern|all|ID,ID,...] [--out FILE]
  gencldr dump --global [--out FILE]
      Fetch if needed, then write the imported data, before encoding, as
      JSON, one line per entry, into FILE (default: standard output).
      Without --global: one line "<locale><TAB><json>" per locale that
      generate writes (same --locales), root first, with the locale's own
      data. With --global: one line "<key><TAB><json>" per entry of the
      global data. A map is {"m": [[key, value], ...]} in insertion order
      (keys null, integers or strings), an alias is {"alias": [key, ...]}
      (the path of keys it refers to), a list is an array; strings,
      numbers (a float always has a "." or an exponent), booleans and
      null as JSON. tests/python/compare_dump.py reads it.

  Options of every command:
    --root DIR   the repository root. Default: the first directory, from
                 the directory of this program upwards, then from the
                 current directory upwards, that holds fpmake.pp and
                 tools/gencldr/gencldr.pas.
    --cache DIR  the cache directory (default <root>/.cache/cldr).

  Build: fpc -Mobjfpc -Sh -O2 -FUbuild/gencldr -FEbuild/gencldr
  tools/gencldr/gencldr.pas (tools/install-package.sh does). Needs only
  FPC's own packages (fcl-net, fcl-web for HTTPS with OpenSSL, paszlib)
  and tools/gencldr/sha2.pas. *)
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
  WriteLn('       gencldr [--root DIR] [--cache DIR] dump [--locales modern|all|ID,ID,...] [--out FILE]');
  WriteLn('       gencldr [--root DIR] [--cache DIR] dump --global [--out FILE]');
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

{ The locales to generate for Selection (modern, all or a list) and the
  locales they inherit from: root first, then sorted. Wanted: the
  selected ones. }
function SelectLocales(const Selection, SrcDir: string; Imp: TLocaleImporter;
  GlobalData: TValue; out Wanted: TStringArray): TStringArray;
var
  Name: string;
  AllNames, Unknown: TStringArray;
  Sorted: TStringList;
  J: Integer;
begin
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
  Result := WithAncestors(Wanted, GlobalData);
end;

procedure Generate(const Selection, OutDir, CacheDir: string);
var
  SrcDir, Name, F, Dir: string;
  GlobalData: TValue;
  Imp: TLocaleImporter;
  Wanted, Names, Units: TStringArray;
  Files: TStringList;
  SR: TSearchRec;
  Total: Int64;
  Blob: TBytes;
  Mark, J: Integer;
begin
  SrcDir := Fetch(CacheDir);
  GlobalData := ParseGlobal(SrcDir);
  Imp := TLocaleImporter.Create(SrcDir);
  try
    Names := SelectLocales(Selection, SrcDir, Imp, GlobalData, Wanted);

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

{ ---- dump: the imported data as JSON lines ---- }

var
  JSONFormat: TFormatSettings;

procedure AppendJSONString(SB: TStringBuilder; const S: string);
var
  C: Char;
begin
  SB.Append('"');
  for C in S do
    case C of
      '"': SB.Append('\"');
      '\': SB.Append('\\');
      #0..#31: SB.Append('\u' + IntToHex(Ord(C), 4));
    else
      SB.Append(C);
    end;
  SB.Append('"');
end;

procedure AppendJSON(SB: TStringBuilder; V: TValue);
var
  J: Integer;
  T: string;
begin
  case V.Kind of
    vkNone: SB.Append('null');
    vkFalse: SB.Append('false');
    vkTrue: SB.Append('true');
    vkInt: SB.Append(IntToStr(V.I));
    vkFloat:
      begin
        T := FloatToStrF(V.F, ffGeneral, 17, 0, JSONFormat);
        if LastDelimiter('.E', T) = 0 then
          T := T + '.0';
        SB.Append(T);
      end;
    vkStr: AppendJSONString(SB, V.S);
    vkList:
      begin
        SB.Append('[');
        for J := 0 to V.Count - 1 do
        begin
          if J > 0 then
            SB.Append(',');
          AppendJSON(SB, V.Items[J]);
        end;
        SB.Append(']');
      end;
    vkMap:
      begin
        SB.Append('{"m":[');
        for J := 0 to V.Count - 1 do
        begin
          if J > 0 then
            SB.Append(',');
          SB.Append('[');
          case V.Keys[J].Kind of
            kkNone: SB.Append('null');
            kkInt: SB.Append(IntToStr(V.Keys[J].I));
            kkStr: AppendJSONString(SB, V.Keys[J].S);
          end;
          SB.Append(',');
          AppendJSON(SB, V.Items[J]);
          SB.Append(']');
        end;
        SB.Append(']}');
      end;
    vkAlias:
      begin
        SB.Append('{"alias":[');
        for J := 0 to High(V.Path) do
        begin
          if J > 0 then
            SB.Append(',');
          AppendJSONString(SB, V.Path[J]);
        end;
        SB.Append(']}');
      end;
  end;
end;

procedure WriteJSONLine(Stream: TStream; const Name: string; V: TValue);
var
  SB: TStringBuilder;
  Line: string;
begin
  SB := TStringBuilder.Create(1 shl 16);
  try
    SB.Append(Name);
    SB.Append(#9);
    AppendJSON(SB, V);
    SB.Append(#10);
    Line := SB.ToString;
  finally
    SB.Free;
  end;
  Stream.WriteBuffer(Line[1], Length(Line));
end;

procedure Dump(const Selection, OutFile, CacheDir: string; IsGlobal: Boolean);
var
  SrcDir: string;
  GlobalData: TValue;
  Imp: TLocaleImporter;
  Wanted, Names: TStringArray;
  Stream: TStream;
  Mark, J: Integer;
begin
  SrcDir := Fetch(CacheDir);
  GlobalData := ParseGlobal(SrcDir);
  if OutFile = '' then
    Stream := THandleStream.Create(StdOutputHandle)
  else
    Stream := TFileStream.Create(OutFile, fmCreate);
  try
    if IsGlobal then
    begin
      for J := 0 to GlobalData.Count - 1 do
      begin
        if GlobalData.Keys[J].Kind <> kkStr then
          raise Exception.Create('a key of the global data is not a string');
        WriteJSONLine(Stream, GlobalData.Keys[J].S, GlobalData.Items[J]);
      end;
      Exit;
    end;
    Imp := TLocaleImporter.Create(SrcDir);
    try
      Names := SelectLocales(Selection, SrcDir, Imp, GlobalData, Wanted);
      for J := 0 to High(Names) do
      begin
        Mark := ArenaMark;
        WriteJSONLine(Stream, Names[J], Imp.ImportLocale(Names[J]));
        ArenaRelease(Mark);
      end;
    finally
      Imp.Free;
    end;
  finally
    Stream.Free;
  end;
end;

var
  Command, Locales, OutDir, Root, CacheDir, Arg, Opt, Value: string;
  I, Eq: Integer;
  HasOut, IsGlobal: Boolean;
begin
  JSONFormat := DefaultFormatSettings;
  JSONFormat.DecimalSeparator := '.';
  IsGlobal := False;
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
      if Arg = '--global' then
        IsGlobal := True
      else if Copy(Arg, 1, 2) = '--' then
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
    if (Command <> 'fetch') and (Command <> 'generate') and (Command <> 'dump') then
    begin
      Usage;
      Halt(2);
    end;
    if (Command = 'fetch') and (HasOut or (Locales <> 'modern')) then
      raise EUsage.Create('fetch takes no --locales or --out');
    if IsGlobal and ((Command <> 'dump') or (Locales <> 'modern')) then
      raise EUsage.Create('--global is an option of dump, without --locales');
    if Root = '' then
      Root := FindRoot
    else
      Root := ExcludeTrailingPathDelimiter(ExpandFileName(Root));
    if CacheDir = '' then
      CacheDir := Root + PathDelim + '.cache' + PathDelim + 'cldr';
    if Command = 'fetch' then
      WriteLn(Fetch(CacheDir))
    else if Command = 'dump' then
      Dump(Locales, OutDir, CacheDir, IsGlobal)
    else
    begin
      if not HasOut then
        OutDir := Root + PathDelim + 'src' + PathDelim + 'data';
      Generate(Locales, OutDir, CacheDir);
    end;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'gencldr: ', E.Message);
      Halt(1);
    end;
  end;
end.
