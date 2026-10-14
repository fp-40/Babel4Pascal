# tools/gencldr

`sha2.pas` (with `sha256i386.inc`, `sha256x64.inc`, `sha512x64.inc`) is a
copy of the SHA-2 unit of https://github.com/DrPeaboss/sha2, commit
35807c8, under the MIT license (`LICENSE-sha2.txt`). The generator uses
it to verify the SHA-512 of the CLDR release it downloads.

Change from the original: the padding of `SHA2Final` (`>=` for `>` in
two comparisons). With 56 bytes pending in SHA-256, or 112 in SHA-512,
the original adds no padding block, and the digest of a message whose
length is 56 modulo 64 (SHA-256) or 112 modulo 128 (SHA-512) is wrong.
`tests/gencldr/test_sha2.pas` checks every length from 0 to 1000 against
digests computed independently.
