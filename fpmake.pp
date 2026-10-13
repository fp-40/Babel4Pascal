{ fpmake.pp - builds and installs Babel4Pascal as an FPC package (named
  babel), so that a program can use its units without -Fu options
  (README.md, "Installing").

  tools/install-package.sh                 # into ~/.fppkg (a user install)

  or by hand:

  fpc fpmake.pp && ./fpmake install --globalunitdir=<dir of the RTL units> \
    --localunitdir=$HOME/.fppkg/lib/fpc/3.2.2

  fpmake is FPC's own build tool (the fpmkunit unit): this program
  declares the package and its units; fpmake compiles them into
  units/<cpu>-<os>/ next to this file and `install` copies the .ppu and
  .o files to <prefix>/lib/fpc/<version>/units/<cpu>-<os>/babel/, a
  directory /etc/fpc.cfg searches (the ~/.fppkg line).

  The CLDR data units (src/data/babel.cldr_*.pas, from tools/gencldr.py)
  are all compiled and installed; a program links only the ones it uses.
  They are found by listing src/data. }
program fpmake;

{$mode objfpc}{$H+}

uses
  fpmkunit, SysUtils, Classes;  { fpmkunit first: it starts cthreads }

procedure AddDataUnits(P: TPackage);
var
  SR: TSearchRec;
  Names: TStringList;
  N: string;
begin
  Names := TStringList.Create;
  try
    if FindFirst('src' + PathDelim + 'data' + PathDelim + 'babel.cldr_*.pas', faAnyFile, SR) = 0 then
    begin
      repeat
        Names.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    if Names.Count = 0 then
      raise Exception.Create('no data units in src/data: run tools/gencldr.py generate');
    Names.Sort;
    { babel.cldr_all first: compiling it compiles every locale unit in one
      compiler run (about 3 s); the other targets are then up to date.
      Listing them still makes fpmake install their .ppu and .o files.
      Compiling each target in its own run takes about 50 s. }
    P.Targets.AddUnit('babel.cldr_global.pas');
    P.Targets.AddUnit('babel.cldr_all.pas');
    for N in Names do
      if (N <> 'babel.cldr_global.pas') and (N <> 'babel.cldr_all.pas') then
        P.Targets.AddUnit(N);
  finally
    Names.Free;
  end;
end;

var
  P: TPackage;
begin
  with Installer do
  begin
    P := AddPackage('babel');
    P.Version := '0.1.0';
    P.Author := 'Juan-Pablo Scaletti';
    P.License := 'MIT';
    P.Description := 'Locale data (CLDR) and localized formatting of numbers, dates and names, after Python Babel';
    P.OSes := [linux];
    P.CPUs := [x86_64, aarch64];
    P.Options.Add('-Mobjfpc');
    P.Options.Add('-Sh');
    P.Options.Add('-O2');
    P.SourcePath.Add('src');
    P.SourcePath.Add('src/data');
    P.IncludePath.Add('src');    { babel.pyfloatrepr.inc }
    P.Targets.AddUnit('babel.errors.pas');
    P.Targets.AddUnit('babel.pystr.pas');
    P.Targets.AddUnit('babel.decimal.pas');
    P.Targets.AddUnit('babel.localedata.pas');
    P.Targets.AddUnit('babel.plural.pas');
    AddDataUnits(P);
    P.Targets.AddUnit('babel.core.pas');
    P.Targets.AddUnit('babel.numbers.pas');
    P.Targets.AddUnit('babel.tz.pas');
    P.Targets.AddUnit('babel.dates.pas');
    P.Targets.AddUnit('babel.lists.pas');
    P.Targets.AddUnit('babel.units.pas');
    Run;
  end;
end.
