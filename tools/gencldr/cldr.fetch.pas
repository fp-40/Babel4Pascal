{ cldr.fetch - the CLDR release the library uses: downloaded once from
  unicode.org into the cache directory, checked against its SHA-512 and
  extracted there. }
unit cldr.fetch;

{$mode objfpc}{$H+}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  SysUtils, Classes;

const
  CldrVersion = '47.0';
  CldrUrl = 'https://unicode.org/Public/cldr/47/cldr-common-47.zip';
  CldrSha512 =
    '3b1eb2a046dae23cf16f611f452833e2a95affb1aa2ae3fa599753d229d15257' +
    '7114c2ff44ca98a7f369fa41dc6f45b0d7a6647653ca79694aacfd3f3be59801';

type
  EFetchError = class(Exception);

{ The common/ directory of the extracted release in CacheDir: when
  absent, cldr-common-<version>.zip is downloaded into CacheDir (unless
  there), its SHA-512 checked, and the zip extracted into
  CacheDir/cldr-common-<version>. Raises EFetchError when the SHA-512
  differs or a member of the zip would land outside that directory
  (an absolute path, a '..' component or a backslash). }
function Fetch(const CacheDir: string): string;
{ The SHA-512 of a file, in lowercase hexadecimal. }
function FileSha512(const Path: string): string;
{ True when a zip member name stays below the extraction directory. }
function SafeMemberName(const Name: string): Boolean;

implementation

uses
  fphttpclient, opensslsockets, zipper, sha2;

function FileSha512(const Path: string): string;
var
  F: TFileStream;
  C: TSHA2Context;
  D: TSHA2Digest;
  Buf: array of Byte;
  N: Integer;
begin
  SetLength(Buf, 1 shl 20);
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SHA2Init(C, SHA2_512);
    repeat
      N := F.Read(Buf[0], Length(Buf));
      if N > 0 then
        SHA2Update(C, Buf[0], N);
    until N <= 0;
    SHA2Final(C, D);
  finally
    F.Free;
  end;
  Result := SHA2Print(D, True);
end;

function SafeMemberName(const Name: string): Boolean;
var
  Part: string;
begin
  Result := False;
  if (Name = '') or (Name[1] = '/') or (Pos('\', Name) > 0) then
    Exit;
  for Part in Name.Split(['/']) do
    if Part = '..' then
      Exit;
  Result := True;
end;

procedure DeleteTree(const Dir: string);
var
  SR: TSearchRec;
  Path: string;
begin
  if not DirectoryExists(Dir) then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile or faSymLink, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Path := IncludeTrailingPathDelimiter(Dir) + SR.Name;
      if (SR.Attr and faDirectory <> 0) and (SR.Attr and faSymLink = 0) then
        DeleteTree(Path)
      else
        DeleteFile(Path);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(Dir);
end;

procedure Download(const Url, Path: string);
var
  Client: TFPHTTPClient;
  F: TFileStream;
begin
  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.AddHeader('User-Agent', 'Babel4Pascal-gencldr');
    F := TFileStream.Create(Path, fmCreate);
    try
      Client.Get(Url, F);
    finally
      F.Free;
    end;
  except
    DeleteFile(Path);
    Client.Free;
    raise;
  end;
  Client.Free;
end;

function Fetch(const CacheDir: string): string;
var
  Dest, Common, ZipPath, Tmp: string;
  UnZipper: TUnZipper;
  J: Integer;
begin
  Dest := IncludeTrailingPathDelimiter(CacheDir) + 'cldr-common-' + CldrVersion;
  Common := Dest + PathDelim + 'common';
  Result := Common;
  if DirectoryExists(Common + PathDelim + 'main') then
    Exit;
  if not ForceDirectories(CacheDir) then
    raise EFetchError.CreateFmt('cannot create %s', [CacheDir]);
  ZipPath := IncludeTrailingPathDelimiter(CacheDir) + 'cldr-common-' + CldrVersion + '.zip';
  if not FileExists(ZipPath) then
  begin
    WriteLn(StdErr, 'downloading ', CldrUrl);
    Download(CldrUrl, ZipPath + '.part');
    if not RenameFile(ZipPath + '.part', ZipPath) then
      raise EFetchError.CreateFmt('cannot rename %s.part', [ZipPath]);
  end;
  if FileSha512(ZipPath) <> CldrSha512 then
    raise EFetchError.CreateFmt('%s: SHA-512 mismatch; delete it and run again', [ZipPath]);
  Tmp := Dest + '.part';
  DeleteTree(Tmp);
  UnZipper := TUnZipper.Create;
  try
    UnZipper.FileName := ZipPath;
    UnZipper.Examine;
    // Extract only below the destination (no absolute or .. paths).
    for J := 0 to UnZipper.Entries.Count - 1 do
      if not SafeMemberName(UnZipper.Entries[J].ArchiveFileName) then
        raise EFetchError.CreateFmt('%s: unsafe member ''%s''',
          [ZipPath, UnZipper.Entries[J].ArchiveFileName]);
    if not ForceDirectories(Tmp) then
      raise EFetchError.CreateFmt('cannot create %s', [Tmp]);
    UnZipper.OutputPath := Tmp;
    UnZipper.UnZipAllFiles;
  finally
    UnZipper.Free;
  end;
  if not RenameFile(Tmp, Dest) then
    raise EFetchError.CreateFmt('cannot rename %s to %s', [Tmp, Dest]);
  if not DirectoryExists(Common + PathDelim + 'main') then
    raise EFetchError.CreateFmt('%s has no common/main directory', [ZipPath]);
end;

end.
