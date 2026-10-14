{ test_sha2 - checks tools/gencldr/sha2.pas: the SHA-256 and SHA-512 of
  messages of 0 to 1000 'a' bytes (tests/gencldr/sha2_vectors.txt), the
  NIST examples, and a message fed in pieces of every size.

  Usage: test_sha2 VECTORS.txt   (exit status 1 when a digest differs) }
program test_sha2;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, sha2;

var
  Failed: Integer = 0;
  Total: Integer = 0;

procedure Expect(const What, Got, Want: string);
begin
  Inc(Total);
  if Got <> Want then
  begin
    Inc(Failed);
    if Failed <= 20 then
      WriteLn('FAIL ', What, ': got ', Got, ' want ', Want);
  end;
end;

function InPieces(const M: RawByteString; Piece: Integer): string;
var
  C: TSHA2Context;
  D: TSHA2Digest;
  P: Integer;
begin
  SHA2Init(C, SHA2_512);
  P := 1;
  while P <= Length(M) do
  begin
    if Length(M) - P + 1 < Piece then
      SHA2Update(C, M[P], Length(M) - P + 1)
    else
      SHA2Update(C, M[P], Piece);
    Inc(P, Piece);
  end;
  SHA2Final(C, D);
  Result := SHA2Print(D);
end;

var
  Lines: TStringList;
  Parts: TStringArray;
  I, J, N: Integer;
  M: RawByteString;
begin
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_sha2 VECTORS.txt');
    Halt(2);
  end;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(ParamStr(1));
    for I := 0 to Lines.Count - 1 do
    begin
      if (Lines[I] = '') or (Lines[I][1] = '#') then
        Continue;
      Parts := Lines[I].Split([' ']);
      N := StrToInt(Parts[0]);
      M := StringOfChar('a', N);
      Expect(Format('sha256 of %d bytes', [N]), SHA2Print(SHA2String(M, SHA2_256)), Parts[1]);
      Expect(Format('sha512 of %d bytes', [N]), SHA2Print(SHA2String(M, SHA2_512)), Parts[2]);
      if N = 1000 then
        for J in [1, 7, 64, 111, 112, 113, 127, 128, 129] do
          Expect(Format('sha512 of %d bytes in pieces of %d', [N, J]), InPieces(M, J), Parts[2]);
    end;
  finally
    Lines.Free;
  end;
  { FIPS 180-2 examples }
  Expect('sha512 abc', SHA2Print(SHA2String('abc', SHA2_512)),
    'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
  Expect('sha512 896-bit', SHA2Print(SHA2String(
    'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu', SHA2_512)),
    '8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909');
  Expect('sha256 448-bit', SHA2Print(SHA2String(
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq', SHA2_256)),
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  WriteLn(Total, ' digests, ', Failed, ' wrong');
  if Failed > 0 then
    Halt(1);
end.
