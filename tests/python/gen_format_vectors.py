#!/usr/bin/env python3
"""Write test vectors for babel.support's Format (TFormat): inputs and the
results the oracle (Python Babel 2.18.0) gives for them, one JSON object
per line, for tests/format/test_format.pas.

A Format is [locale, time zone ('' = UTC), numbering system]; numbers
are encoded as in gen_numbers_vectors.py, dates as
[y, m, d, h, mi, s, ms] in UTC.

Usage: gen_format_vectors.py OUT.jsonl
"""
import datetime
import decimal
import json
import os
import struct
import sys
import zoneinfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

oracle_linked.setup()
from babel import core, numbers, support  # noqa: E402

out = []


def enc(x):
    if isinstance(x, int):
        return ['int', str(x)]
    if isinstance(x, float):
        return ['float', '%016x' % struct.unpack('<Q', struct.pack('<d', x))[0]]
    return ['dec', str(x)]


def case(op, fmt, args, fn):
    try:
        out.append({'op': op, 'args': [fmt, *args], 'expect': fn()})
    except (ValueError, KeyError, TypeError, core.UnknownLocaleError, numbers.UnknownCurrencyError,
            numbers.UnsupportedNumberingSystemError) as e:
        out.append({'op': op, 'args': [fmt, *args], 'error': type(e).__name__})


LOCALES = ['en', 'en_GB', 'de', 'fr', 'es', 'es_PE', 'pt_BR', 'it', 'ru', 'ar', 'ar_EG', 'fa', 'he',
           'hi', 'bn', 'ja', 'zh', 'ko', 'tr', 'sw']
ZONES = ['', 'America/Lima', 'Europe/Madrid', 'Asia/Kolkata']
DTS = [datetime.datetime(2026, 10, 13, 14, 30, 5), datetime.datetime(2026, 1, 1, 0, 0, 0),
       datetime.datetime(2025, 12, 31, 23, 59, 59)]
NUMS = [0, 1, 2, 12, 123, 0.5, 1.25, decimal.Decimal('1.0'), decimal.Decimal('999.995'), 7.125]

for loc in LOCALES:
    for tz in ZONES:
        for ns in ('latn', 'default'):
            fmt = [loc, tz, ns]
            f = support.Format(loc, zoneinfo.ZoneInfo(tz) if tz else None, numbering_system=ns)
            for dt in DTS:
                d = [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, 0]
                for style in ('short', 'medium', 'long', 'full'):
                    if tz == '' and ns == 'latn':
                        case('date', fmt, [d, style], lambda: f.date(dt.date(), style))
                    case('datetime', fmt, [d, style], lambda: f.datetime(dt, style))
                    case('time', fmt, [d, style], lambda: f.time(dt, style))
            if tz != '':
                continue
            for secs in (1, 45, 3600, -86400 * 3, 86400 * 40):
                case('timedelta', fmt, [secs, 'second', 0.85, 'long', False],
                     lambda: f.timedelta(secs))
                case('timedelta', fmt, [secs, 'hour', 0.85, 'short', True],
                     lambda: f.timedelta(secs, 'hour', 0.85, 'short', True))
            for n in NUMS:
                case('number', fmt, [enc(n)], lambda: f.number(n))
                case('decimal', fmt, [enc(n), '#,##0.00'], lambda: f.decimal(n, '#,##0.00'))
                case('compact_decimal', fmt, [enc(n * 1000), 'long', 1],
                     lambda: f.compact_decimal(n * 1000, 'long', 1))
                case('currency', fmt, [enc(n), 'PEN'], lambda: f.currency(n, 'PEN'))
                case('compact_currency', fmt, [enc(n * 10000), 'EUR', 'short', 0],
                     lambda: f.compact_currency(n * 10000, 'EUR', 'short', 0))
                case('percent', fmt, [enc(n), ''], lambda: f.percent(n))
                case('scientific', fmt, [enc(n)], lambda: f.scientific(n))

with open(sys.argv[1], 'w', encoding='utf-8') as fh:
    for c in out:
        fh.write(json.dumps(c, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
