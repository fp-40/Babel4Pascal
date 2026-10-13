#!/usr/bin/env python3
"""Write test vectors for babel.dates: inputs and the results the oracle
(Python Babel 2.18.0) gives for them, one JSON object per line, for
tests/dates/test_dates.pas.

A datetime is written [y, m, d, h, n, s, ms] and is UTC (a naive datetime,
as Babel takes it); a time zone is a name ('' for none: UTC).

Usage: gen_dates_vectors.py OUT.jsonl
"""
import datetime
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

LINKED = oracle_linked.setup()
from babel import Locale, core, dates  # noqa: E402

out = []


def case(op, args, fn):
    try:
        out.append({'op': op, 'args': args, 'expect': fn()})
    except (ValueError, TypeError, KeyError, LookupError, OverflowError, IndexError,
            NotImplementedError, AttributeError, core.UnknownLocaleError) as e:
        name = type(e).__name__
        if name == 'ParseError':
            name = 'ParseError'
        elif isinstance(e, KeyError):
            name = 'KeyError'
        elif isinstance(e, IndexError):
            name = 'IndexError'
        elif isinstance(e, LookupError):
            name = 'LookupError'
        elif isinstance(e, AttributeError):
            name = 'TypeError'
        elif isinstance(e, NotImplementedError):
            name = 'NotImplementedError'
        out.append({'op': op, 'args': args, 'error': name})


def enc(dt):
    return [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, dt.microsecond // 1000]


def tz(name):
    return dates.get_timezone(name) if name else None


rnd = random.Random(49)
ZONES = ['', 'UTC', 'Europe/Madrid', 'America/New_York', 'America/Lima', 'Asia/Kolkata',
         'America/St_Johns', 'Australia/Lord_Howe', 'Europe/Dublin', 'Pacific/Chatham',
         'Etc/GMT+5', 'Asia/Tehran', 'America/Sao_Paulo', 'Asia/Kathmandu', 'Europe/London',
         'America/Los_Angeles', 'Asia/Tokyo', 'Africa/Casablanca', 'America/Argentina/Buenos_Aires']

DTS = [datetime.datetime(2026, 10, 13, 14, 30, 5, 123000),
       datetime.datetime(2026, 1, 1, 0, 0, 0),
       datetime.datetime(2025, 12, 31, 23, 59, 59, 999000),
       datetime.datetime(2026, 3, 29, 0, 59, 59), datetime.datetime(2026, 3, 29, 1, 0, 0),
       datetime.datetime(2026, 10, 25, 0, 30), datetime.datetime(2026, 10, 25, 1, 30),
       datetime.datetime(2024, 2, 29, 12, 0, 0, 290000),
       datetime.datetime(1999, 12, 27, 6, 7, 8, 500000), datetime.datetime(2021, 1, 3, 23, 0),
       datetime.datetime(2020, 12, 31, 11, 11, 11, 1000), datetime.datetime(2010, 1, 4, 12, 0),
       datetime.datetime(1900, 1, 1, 0, 0), datetime.datetime(2099, 12, 30, 18, 45, 15, 250000),
       datetime.datetime(2026, 6, 15, 12, 0), datetime.datetime(2026, 11, 1, 6, 30),
       datetime.datetime(2026, 4, 5, 15, 30), datetime.datetime(2026, 7, 4, 0, 0, 0, 5000)]
DTS += [datetime.datetime(rnd.randrange(1950, 2080), rnd.randrange(1, 13), rnd.randrange(1, 29),
                          rnd.randrange(0, 24), rnd.randrange(0, 60), rnd.randrange(0, 60),
                          rnd.randrange(0, 1000) * 1000) for _ in range(12)]
DATES = [datetime.datetime(y, m, d) for y in (2015, 2016, 2020, 2021, 2026, 2027)
         for m, d in ((1, 1), (1, 2), (1, 3), (1, 4), (1, 7), (12, 26), (12, 28), (12, 29), (12, 30), (12, 31))]

FIELDS = ['G', 'GG', 'GGG', 'GGGG', 'GGGGG', 'y', 'yy', 'yyy', 'yyyy', 'yyyyy', 'Y', 'YY', 'YYYY',
          'u', 'uu', 'Q', 'QQ', 'QQQ', 'QQQQ', 'QQQQQ', 'q', 'qq', 'qqq', 'qqqq', 'qqqqq', 'M', 'MM',
          'MMM', 'MMMM', 'MMMMM', 'L', 'LL', 'LLL', 'LLLL', 'LLLLL', 'w', 'ww', 'W', 'd', 'dd', 'D',
          'DD', 'DDD', 'F', 'E', 'EE', 'EEE', 'EEEE', 'EEEEE', 'EEEEEE', 'e', 'ee', 'eee', 'eeee',
          'eeeee', 'eeeeee', 'c', 'ccc', 'cccc', 'ccccc', 'cccccc']
TIME_FIELDS = ['a', 'aa', 'aaa', 'aaaa', 'aaaaa', 'b', 'bbbb', 'bbbbb', 'B', 'BBBB', 'BBBBB', 'h',
               'hh', 'H', 'HH', 'K', 'KK', 'k', 'kk', 'm', 'mm', 's', 'ss', 'S', 'SS', 'SSS',
               'SSSS', 'SSSSSS', 'A', 'AAAAAAAA', 'z', 'zz', 'zzz', 'zzzz', 'Z', 'ZZ', 'ZZZ',
               'ZZZZ', 'ZZZZZ', 'O', 'OOOO', 'v', 'vvvv', 'V', 'VV', 'VVV', 'VVVV', 'x', 'xx',
               'xxx', 'xxxx', 'xxxxx', 'X', 'XX', 'XXX', 'XXXX', 'XXXXX']
PATTERNS = ["d 'de' MMMM 'de' y", "EEEE, d MMMM y 'at' h:mm a", "''yy''", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "h 'o''clock' a, zzzz", "QQQ y", "w 'week' Y", 'MMMMEd']
BAD = ['dddd', 'MMMMMM', 'hhh', 'EEEEEEE', 'ccc', 'cc', 'WW', 'FF', 'OO']

ALL = sorted(LINKED - {'root'})
SOME = [x for x in ['en', 'en_GB', 'en_IN', 'de', 'fr', 'es', 'es_PE', 'pt_BR', 'it', 'sv', 'pl', 'ru',
                    'ar', 'ar_EG', 'fa', 'he', 'hi', 'bn', 'th', 'ja', 'ko', 'zh', 'zh_Hant', 'id',
                    'vi', 'sw', 'tr', 'el', 'fi', 'cs', 'uk', 'my', 'am', 'ta', 'te', 'ca', 'nl', 'da']
        if x in LINKED]

# --- names and patterns of every locale --------------------------------------

for loc in ALL:
    d = {}
    for kind, fn, widths, contexts in (
            ('day', dates.get_day_names, ('abbreviated', 'narrow', 'short', 'wide'), ('format', 'stand-alone')),
            ('month', dates.get_month_names, ('abbreviated', 'narrow', 'wide'), ('format', 'stand-alone')),
            ('quarter', dates.get_quarter_names, ('abbreviated', 'narrow', 'wide'), ('format', 'stand-alone')),
            ('period', dates.get_period_names, ('abbreviated', 'narrow', 'wide'), ('format', 'stand-alone'))):
        for w in widths:
            for c in contexts:
                try:
                    d[f'{kind}/{w}/{c}'] = {str(k): v for k, v in fn(w, c, locale=loc).items()}
                except KeyError:
                    d[f'{kind}/{w}/{c}'] = 'KeyError'
    for w in ('abbreviated', 'narrow', 'wide'):
        d[f'era/{w}'] = {str(k): v for k, v in dates.get_era_names(w, locale=loc).items()}
    for f in ('full', 'long', 'medium', 'short'):
        d[f'date/{f}'] = str(dates.get_date_format(f, locale=loc))
        d[f'time/{f}'] = str(dates.get_time_format(f, locale=loc))
        d[f'datetime/{f}'] = str(dates.get_datetime_format(f, locale=loc))
    out.append({'op': 'names', 'args': [loc], 'expect': d})
    dt = DTS[0]
    for f in ('full', 'long', 'medium', 'short'):
        case('format_date', [enc(dt), f, loc], lambda: dates.format_date(dt, f, locale=loc))
        case('format_datetime', [enc(dt), f, 'America/Lima', loc],
             lambda: dates.format_datetime(dt, f, tzinfo=tz('America/Lima'), locale=loc))

# --- every field, in some locales --------------------------------------------------

for loc in SOME:
    for dt in DTS[:14] + DATES[::5]:
        for p in FIELDS:
            case('format_date', [enc(dt), p, loc], lambda: dates.format_date(dt, p, locale=loc))
    for dt in DTS[:10]:
        for z in ('', 'Europe/Madrid', 'America/St_Johns', 'Asia/Kolkata', 'Europe/Dublin'):
            for p in TIME_FIELDS + PATTERNS:
                case('format_datetime', [enc(dt), p, z, loc],
                     lambda: dates.format_datetime(dt, p, tzinfo=tz(z), locale=loc))
            for f in ('full', 'long', 'medium', 'short', 'h:mm:ss a zzzz', 'HH:mm v', 'z', 'Z'):
                case('format_time', [enc(dt), f, z, loc],
                     lambda: dates.format_time(dt, f, tzinfo=tz(z), locale=loc))
    for dt in DATES:
        for p in ('w', 'ww', 'W', 'Y', 'YYYY', 'e', 'c', 'D'):
            case('format_date', [enc(dt), p, loc], lambda: dates.format_date(dt, p, locale=loc))
    for p in BAD:
        case('format_date', [enc(DTS[0]), p, loc], lambda: dates.format_date(DTS[0], p, locale=loc))

# --- zones --------------------------------------------------------------------------

for loc in SOME:
    for z in ZONES:
        for w in ('long', 'short'):
            for variant in (None, 'generic', 'standard', 'daylight'):
                case('tz_name', [z, w, variant or '', False, loc],
                     lambda: dates.get_timezone_name(tz(z) or dates.UTC, w, zone_variant=variant, locale=loc))
            for dt in DTS[3:8] + [DTS[14]]:
                aware = dt.replace(tzinfo=dates.UTC).astimezone(tz(z)) if z else dt.replace(tzinfo=dates.UTC)
                case('tz_name_dt', [enc(dt), z, w, loc],
                     lambda: dates.get_timezone_name(aware, w, locale=loc))
                for gw in ('long', 'short', 'iso8601', 'iso8601_short'):
                    for rz in (False, True):
                        case('tz_gmt', [enc(dt), z, gw, rz, loc],
                             lambda: dates.get_timezone_gmt(aware, gw, locale=loc, return_z=rz))
        case('tz_name', [z, 'long', '', True, loc],
             lambda: dates.get_timezone_name(tz(z) or dates.UTC, return_zone=True, locale=loc))
        for rc in (False, True):
            case('tz_location', [z, rc, loc],
                 lambda: dates.get_timezone_location(tz(z) or dates.UTC, locale=loc, return_city=rc))
case('tz_name', ['Mars/Olympus', 'long', '', False, 'en'], lambda: dates.get_timezone_name(tz('Mars/Olympus'), locale='en'))

# --- skeletons, intervals, timedelta, periods ---------------------------------------------

SKELETONS = ['yMMMd', 'yMd', 'Hm', 'hm', 'MMMEd', 'yQQQ', 'Bhm', 'ms', 'yMMMMEEEEd', 'GyMMMd',
             'MMMMd', 'Ehm', 'yw', 'hmz', 'kmm', 'jmm', 'yMMMdhm', 'Hmv', 'MEd', 'yMMM', 'XYZ']
for loc in SOME:
    for sk in SKELETONS:
        for fuzzy in (True, False):
            case('format_skeleton', [sk, enc(DTS[0]), 'Europe/Madrid', fuzzy, loc],
                 lambda: dates.format_skeleton(sk, DTS[0], tzinfo=tz('Europe/Madrid'), fuzzy=fuzzy, locale=loc))
    pairs = [(DTS[0], DTS[0].replace(minute=45)), (DTS[0], DTS[0].replace(hour=20)),
             (DTS[0], DTS[0] + datetime.timedelta(days=3)), (DTS[0], DTS[0].replace(month=12)),
             (DTS[0], DTS[0].replace(year=2027)), (DTS[0], DTS[0]), (DTS[1], DTS[1] + datetime.timedelta(hours=13))]
    for sk in ('yMMMd', 'yMd', 'Hm', 'hm', 'MMMEd', 'yMMM', 'Bhm', 'Hmv', 'yMMMMEEEEd', 'GyMMMd', 'XYZ', ''):
        for a, b in pairs:
            for z in ('', 'America/New_York'):
                case('format_interval', [enc(a), enc(b), sk, z, True, 'datetime', loc],
                     lambda: dates.format_interval(a, b, sk or None, tzinfo=tz(z), locale=loc))
            case('format_interval', [enc(a), enc(b), sk, '', True, 'date', loc],
                 lambda: dates.format_interval(a.date(), b.date(), sk or None, locale=loc))
        case('format_interval', [enc(pairs[0][0]), enc(pairs[0][1]), sk, '', False, 'datetime', loc],
             lambda: dates.format_interval(pairs[0][0], pairs[0][1], sk or None, fuzzy=False, locale=loc))
    for secs in (0, 1, 30, 59, 60, 61, 3000, 3600, 5000, 86399, 86400, 172800, 604800, 2592000,
                 31536000, 45000000, -1, -3600, -172800, -40000000):
        for gran in ('second', 'minute', 'hour', 'day', 'week', 'month', 'year'):
            for fmt in ('long', 'short', 'narrow', 'medium'):
                for direction in (False, True):
                    if gran not in ('second', 'day', 'year') and fmt != 'long':
                        continue
                    case('format_timedelta', [secs, gran, 0.85, direction, fmt, loc],
                         lambda: dates.format_timedelta(secs, gran, 0.85, direction, fmt, locale=loc))
        case('format_timedelta', [secs, 'second', 1.0, False, 'long', loc],
             lambda: dates.format_timedelta(secs, 'second', 1.0, False, 'long', locale=loc))
    case('format_timedelta', [10, 'second', 0.85, False, 'wide', loc],
         lambda: dates.format_timedelta(10, format='wide', locale=loc))
    for h in range(0, 24):
        for m in (0, 30):
            t = datetime.datetime(2026, 5, 5, h, m)
            for rt in ('', 'selection'):
                case('period_id', [enc(t), rt, '', loc],
                     lambda: dates.get_period_id(t, type=rt or None, locale=loc))

# --- parsing and patterns ------------------------------------------------------------------

DATE_STRINGS = ['2026-10-13', '20261013', '13/10/2026', '10/13/2026', '13.10.26', '2026年10月13日',
                'Oct 13, 2026', '13 oct. 2026', '٢٠٢٦-١٠-١٣', '1/2/3', '31/02/2026', 'no numbers',
                '5', '2026-13-45', '12 34']
TIME_STRINGS = ['14:30', '2:30 PM', '2:30 pm', '14:30:15', '9', '23:59:59', '٢:٣٠', '12:00 AM',
                'nothing', '25:00', '10:70', '4:05:06 PM']
for loc in SOME:
    for s in DATE_STRINGS:
        for f in ('short', 'medium', 'yyyy/MM/dd', 'dd.MM.yy'):
            def run():
                d = dates.parse_date(s, locale=loc, format=f)
                return [d.year, d.month, d.day]
            case('parse_date', [s, f, loc], run)
    for s in TIME_STRINGS:
        for f in ('short', 'medium', 'HH:mm', 'h:mm a'):
            def run():
                t = dates.parse_time(s, locale=loc, format=f)
                return [t.hour, t.minute, t.second]
            case('parse_time', [s, f, loc], run)

SK_OPTIONS = sorted(Locale.parse('en').datetime_skeletons.keys())
for sk in ['yMMMd', 'MMMMd', 'yMMMMd', 'hmz', 'kmm', 'Kmm', 'yMd', 'yQQQQ', 'MMMMEEEEd', 'Hms', 'yw', 'ab', 'z']:
    for adf in (False, True):
        case('match_skeleton', [sk, SK_OPTIONS, adf],
             lambda: dates.match_skeleton(sk, SK_OPTIONS, allow_different_fields=adf) or '')
for p in ["E d.M. – E d.M.", "Y 'text' Y 'more text'", 'MMM d – d', 'y G', 'h:mm – h:mm a']:
    case('split_interval', [p], lambda: dates.split_interval_pattern(p))
for p in PATTERNS + BAD + ["'unterminated", "a''b", "''", "'x''y'"]:
    case('tokenize', [p], lambda: [[t, v if t == 'chars' else [v[0], v[1]]] for t, v in dates.tokenize_pattern(p)])

with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for o in out:
        f.write(json.dumps(o, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
