# tools/gencldr

The CLDR data generator of Babel4Pascal, a Free Pascal program:
`gencldr.pas` and its units `cldr.*.pas` (usage: docs/installation.md,
"Generating the locale data"). It writes the same files, byte for byte,
as the Python generator `tools/gencldr.py` (with `tools/cldrgen/`), and
its units follow the Python modules:

- `cldr.etree`: the XML files as a tree of elements with the semantics
  of Python's `xml.etree.ElementTree` (text and tail, `findall` paths).
  It does not read the external DTD that the CLDR files name; the
  `fcl-xml` reader does, and adds the DTD's default attribute values;
- `cldr.pystr`: Python's `strip`, `split`, `int` and `float` on UTF-8
  text;
- `cldr.values`: the imported data (maps in insertion order);
- `cldr.importer`, `cldr.locales`, `cldr.encode`, `cldr.pascalout`:
  `importer.py`, `locales.py`, `encode.py` and `pascal.py`;
- `cldr.fetch`: the download (fcl-web's `fphttpclient` with
  `opensslsockets`), the SHA-512 check and the extraction (paszlib's
  `zipper`).

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
