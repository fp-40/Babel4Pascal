# Installation

Babel4Pascal is a Free Pascal package named `babel`. It is built and
installed with fpmake, Free Pascal's build tool.

## Requirements

- Free Pascal 3.2.2 on Linux (x86_64 or aarch64), with its standard
  packages. The locale data generator is a Free Pascal program.
- Network access to unicode.org the first time, to download the CLDR
  release, and the OpenSSL library (`libssl`), which Free Pascal's HTTP
  client loads for HTTPS.
- The system's IANA tz database: the TZif files under
  `/usr/share/zoneinfo` (the `tzdata` package). The directory can be
  changed with the `TZDIR` environment variable or with
  `SetZoneInfoPath` (unit `babel.tz`).

## Generating the locale data

The locale data is a set of Pascal units in `src/data/`, generated from
the CLDR XML release by the program `tools/gencldr/gencldr.pas`
(`tools/install-package.sh` compiles and runs it when `src/data/` has no
units). By hand:

```sh
fpc -Mobjfpc -Sh -O2 -FUbuild/gencldr -FEbuild/gencldr tools/gencldr/gencldr.pas
build/gencldr/gencldr fetch       # download and extract the CLDR release into .cache/cldr/
build/gencldr/gencldr generate    # write src/data/babel.cldr_*.pas
```

`fetch` downloads `cldr-common-47.zip` from unicode.org once, checks its
SHA-512 and prints the path of the extracted `common/` directory.
`generate` fetches when needed, then writes:

- one unit per locale: `babel.cldr_es_PE` holds the data of `es_PE` and
  uses the unit of the locale it inherits from (`babel.cldr_es_419`,
  `babel.cldr_es`, then `babel.cldr_root`);
- `babel.cldr_global`, the data that is not per locale (likely subtags,
  aliases, parent locales, currencies of territories, time zone
  mappings);
- `babel.cldr_all`, which uses every generated locale.

Options of `generate`:

- `--locales modern` (the default): the 512 locales whose CLDR coverage
  level is "modern" and the locales that inherit from them;
- `--locales all`: every locale of the release;
- `--locales es_PE,en,de`: the locales listed. The locales they inherit
  from, up to root, are always added;
- `--out DIR`: the directory to write (default `src/data`; it is emptied
  of `babel.cldr_*.pas` files first).

Options of every command:

- `--root DIR`: the repository root, which the default paths are
  relative to. Without it, the program takes the first directory that
  holds `fpmake.pp` and `tools/gencldr/gencldr.pas`, searching upwards
  from the program's own directory (`build/gencldr/` is inside the
  repository), then from the current directory;
- `--cache DIR`: where the CLDR release is downloaded and extracted
  (default `.cache/cldr` under the root).

`gencldr dump [--locales ...] [--out FILE]` writes the imported data of
the locales that `generate` writes as JSON lines instead of units (to
standard output without `--out`); `gencldr dump --global` writes the
global data. The development checks (`tests/run_all.sh`) use it.

## Installing the package

```sh
tools/install-package.sh
```

The script generates the data units when `src/data/` has none, builds
the package with fpmake and installs its units into
`~/.fppkg/lib/fpc/<version>/units/<cpu>-linux/babel`, a directory that
`/etc/fpc.cfg` searches. Set `PREFIX` to install elsewhere:

```sh
PREFIX=/opt/fpc-packages tools/install-package.sh
# units in /opt/fpc-packages/lib/fpc/3.2.2/units/x86_64-linux/babel
```

The data units of every generated locale are compiled and installed; a
program links only the ones it uses.

## Using the library from a program

After the install, a program compiles without `-Fu` options:

```sh
fpc -Mobjfpc -Sh prog.pas
```

Without installing, point the compiler at the sources:

```sh
fpc -Mobjfpc -Sh -Fu/path/to/Babel4Pascal/src -Fu/path/to/Babel4Pascal/src/data prog.pas
```

A program names the units it needs and the data units of its locales:

```pascal
program hello;

{$mode objfpc}{$H+}

uses
  babel.core, babel.numbers, babel.cldr_es_PE, babel.cldr_en;

begin
  WriteLn(TLocale.Parse('es_PE').DisplayName);    // español (Perú)
  WriteLn(FormatDecimal(1250, 'es_PE'));          // 1,250
end.
```

`babel.cldr_global` is always linked through the data units. Use
`babel.cldr_all` to link every generated locale (about 11 MB of data in all);
a program with `es_PE` alone links about 0.5 MB.

The units use `{$mode objfpc}` and `{$modeswitch advancedrecords}`; a
program may use any mode.

[Index](index.md)
