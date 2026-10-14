# tools/gencldr

The CLDR data generator of Babel4Pascal, a Free Pascal program:
`gencldr.pas` and its units `cldr.*.pas` (usage: docs/installation.md,
"Generating the locale data"):

- `cldr.etree`: the XML files as a tree of elements with the semantics
  of Python's `xml.etree.ElementTree` (text and tail, `findall` paths).
  It does not read the external DTD that the CLDR files name; the
  `fcl-xml` reader does, and adds the DTD's default attribute values;
- `cldr.pystr`: Python's `strip`, `split`, `int` and `float` on UTF-8
  text;
- `cldr.values`: the imported data (maps in insertion order);
- `cldr.importer`: reads the XML files into a map of global data and a
  map per locale (its own data). Parts derive from Python Babel 2.18.0,
  under the BSD-3-Clause license quoted in the unit;
- `cldr.locales`: the parent of a locale and the choice of locales to
  generate;
- `cldr.encode`: the data as the bytes that `src/babel.localedata.pas`
  decodes;
- `cldr.pascalout`: writes the units;
- `cldr.fetch`: the download (fcl-web's `fphttpclient` with
  `opensslsockets`), the SHA-512 check and the extraction (paszlib's
  `zipper`).

`gencldr dump` writes the imported data, before encoding, as JSON lines
(the format is in `gencldr.pas`). `tests/python/compare_dump.py` compares
it with the data as the library loads it.

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
