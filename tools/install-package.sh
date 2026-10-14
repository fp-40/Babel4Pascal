#!/bin/sh
# Builds Babel4Pascal as an FPC package named babel (fpmake.pp) and installs
# its units into the user's fppkg directory,
# ~/.fppkg/lib/fpc/<version>/units/x86_64-linux/babel, which /etc/fpc.cfg
# searches: afterwards a program compiles with `fpc -Mobjfpc -Sh prog.pas`,
# without -Fu options (README.md, "Installing").
#
# The CLDR data units (src/data) are generated first when absent: the
# generator (tools/gencldr/gencldr.pas) is compiled into build/gencldr and
# runs `gencldr generate`, which downloads the CLDR release from
# unicode.org into .cache/ once. Only FPC is needed.
#
# Usage: tools/install-package.sh
# Env: PREFIX overrides ~/.fppkg (the units go to
#      $PREFIX/lib/fpc/<version>/units/x86_64-linux/babel).
#
# fpmake needs the directory that holds the compiler's own units (to check
# the implicit dependency on the RTL); it is found by asking fpc where it
# loads system.ppu from.
# Exit status 0 only when the install succeeded.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ ! -f "$ROOT/src/data/babel.cldr_all.pas" ]; then
  GEN=$ROOT/build/gencldr
  mkdir -p "$GEN"
  fpc -Mobjfpc -Sh -O2 -FU"$GEN" -FE"$GEN" "$ROOT/tools/gencldr/gencldr.pas" \
    > "$GEN/gencldr.build.log" 2>&1 \
    || { echo "install-package: the generator did not compile (see $GEN/gencldr.build.log)"; exit 1; }
  "$GEN/gencldr" --root "$ROOT" generate \
    || { echo "install-package: generating the CLDR data units failed"; exit 1; }
fi
PREFIX=${PREFIX:-$HOME/.fppkg}
T=$(mktemp -d)
printf 'program p;\nbegin\nend.\n' > "$T/p.pas"
SYS=$(cd "$T" && fpc -vt p.pas 2>&1 | grep -m1 -o '/[^ ]*/units/[^ /]*/rtl/system.ppu' || true)
rm -rf "$T"
[ -n "$SYS" ] || { echo "install-package: cannot find where fpc loads system.ppu from"; exit 1; }
GU=${SYS%/units/*}
OUT=$ROOT/build/fpmake
mkdir -p "$OUT"
fpc -Mobjfpc -Sh -FE"$OUT" -FU"$OUT" "$ROOT/fpmake.pp" > "$OUT/fpmake.build.log" 2>&1 \
  || { echo "install-package: fpmake.pp did not compile (see $OUT/fpmake.build.log)"; exit 1; }
cd "$ROOT"
"$OUT/fpmake" install --prefix="$PREFIX" --globalunitdir="$GU" \
  --localunitdir="$PREFIX/lib/fpc/$(fpc -iV)" > "$OUT/install.log" 2>&1 \
  || { tail -n 3 "$OUT/install.log"; echo "install-package: FAILED (see $OUT/install.log)"; exit 1; }
echo "install-package: babel (x86_64-linux) installed under $PREFIX/lib/fpc/$(fpc -iV)/units/x86_64-linux/babel"
