"""Write test vectors for babel.tz: for every zone of the system's tz
database, the UTC offset, the DST offset and the abbreviation that Python's
zoneinfo gives at many instants (random ones from 1850 to 2100, every
transition of the zone's file and one second before it).

Usage: gen_tz_vectors.py OUT.jsonl
"""

import datetime
import json
import random
import sys
import zoneinfo
from zoneinfo import _zoneinfo  # the pure-Python implementation exposes the transitions

UTC = datetime.UTC
rnd = random.Random(48)
lo = int(datetime.datetime(1850, 1, 1, tzinfo=UTC).timestamp())
hi = int(datetime.datetime(2100, 12, 31, tzinfo=UTC).timestamp())
out = []

for name in sorted(zoneinfo.available_timezones()):
    try:
        z = zoneinfo.ZoneInfo(name)
    except Exception:
        continue
    instants = [rnd.randrange(lo, hi) for _ in range(150)]
    instants += [
        int(datetime.datetime(y, m, 1, tzinfo=UTC).timestamp())
        for y in (1900, 1970, 2000, 2024, 2026, 2037, 2038, 2050, 2099)
        for m in (1, 4, 7, 10)
    ]
    for t in _zoneinfo.ZoneInfo.no_cache(name)._trans_utc[:400]:
        instants += [t - 1, t]
    rows = []
    for t in instants:
        dt = datetime.datetime.fromtimestamp(t, z)
        rows.append(
            [
                t,
                int(dt.utcoffset().total_seconds()),
                int(dt.dst().total_seconds()),
                dt.tzname(),
            ]
        )
    out.append(
        {
            "op": "tz",
            "args": [name, [r[0] for r in rows]],
            "expect": [r[1:] for r in rows],
        }
    )
    # local wall-clock lookups (zoneinfo's _find_trans), fold 0 and 1
    lrows = []
    for t in (
        instants[:120] + [i + d for i in instants[150:] for d in (-3600, 1800)][:300]
    ):
        for fold in (0, 1):
            dt = datetime.datetime(1970, 1, 1) + datetime.timedelta(seconds=t)
            dt = dt.replace(tzinfo=z, fold=fold)
            lrows.append(
                [
                    t,
                    fold,
                    int(dt.utcoffset().total_seconds()),
                    int(dt.dst().total_seconds()),
                    dt.tzname(),
                ]
            )
    out.append(
        {
            "op": "tz_local",
            "args": [name, [r[:2] for r in lrows]],
            "expect": [r[2:] for r in lrows],
        }
    )

with open(sys.argv[1], "w", encoding="utf-8") as f:
    for o in out:
        f.write(json.dumps(o, ensure_ascii=False) + "\n")

print(
    f"{len(out)} zones, {sum(len(o['expect']) for o in out)} instants written to {sys.argv[1]}"
)
