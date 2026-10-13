#!/usr/bin/env python3
"""Write test vectors for babel.numbers: inputs and the results the oracle
(Python Babel 2.18.0) gives for them, one JSON object per line, for
tests/numbers/test_numbers.pas.

A number is written as [kind, text]: ["int", "123"], ["float", "<16 hex
digits of the double>"], ["dec", "1.50"] or ["str", "1.5"], so that the
Pascal side gives the library the same kind of value Babel received.

Usage: gen_numbers_vectors.py OUT.jsonl
"""
import datetime
import decimal
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

LINKED = oracle_linked.setup()
from babel import Locale, core, numbers  # noqa: E402

out = []


def case(op, args, fn):
    try:
        out.append({'op': op, 'args': args, 'expect': fn()})
    except (ValueError, TypeError, KeyError, OverflowError, core.UnknownLocaleError,
            decimal.DecimalException, numbers.UnknownCurrencyError,
            numbers.UnsupportedNumberingSystemError) as e:
        name = type(e).__name__
        if isinstance(e, decimal.DecimalException):
            name = 'DecimalException'
        out.append({'op': op, 'args': args, 'error': name})


def enc(x):
    if isinstance(x, bool):
        raise TypeError
    if isinstance(x, int):
        return ['int', str(x)]
    if isinstance(x, float):
        return ['float', '%016x' % struct.unpack('<Q', struct.pack('<d', x))[0]]
    if isinstance(x, decimal.Decimal):
        return ['dec', str(x)]
    return ['str', x]


INTS = [0, 1, -1, 2, 5, 12, 123, 1234, -1234, 12345, 123456, 1234567, -1234567, 1000000,
        10 ** 15, 9223372036854775807, -9223372036854775807]
FLOATS = [0.0, -0.0, 0.5, 1.0, 1.5, 2.5, -2.5, 1234.5678, 0.1 + 0.2, 1e-7, 1e16, 2.675, 1.005,
          999.995, 0.000123, float('inf'), float('-inf'), float('nan'), 1e22, 1e25, 12345.0,
          -0.004, 0.125]
DECS = [decimal.Decimal(s) for s in ['1.50', '1.0', '0.05', '12345.6789', '-0', '1E+3', '1.2E+3',
                                     '123456789012345678901234.5', 'NaN', 'Infinity', '-Infinity',
                                     '0.0000', '1E-30', '-123.456', '0.999', '99.5', '1000.0']]
STRS = ['1.5', '1,5', 'abc', '  12 ', '1e3', '-0.25', '1_000']
NUMS = INTS + FLOATS + DECS + STRS
SMALL = [0, 1, -1, 1234, -1234.5, 0.5, 2.675, decimal.Decimal('1.0'), decimal.Decimal('-0'),
         float('nan'), float('inf'), '1234.5', 1000000]

ALL = sorted(LINKED - {'root'})
SOME = [x for x in ['en', 'en_US', 'en_IN', 'de', 'de_CH', 'fr', 'fr_CA', 'es', 'es_PE', 'es_MX',
                    'pt_BR', 'it', 'nl', 'sv', 'fi', 'pl', 'ru', 'uk', 'cs', 'tr', 'ar', 'ar_EG',
                    'fa', 'he', 'hi', 'bn', 'th', 'ja', 'ko', 'zh', 'zh_Hant', 'id', 'vi', 'sw',
                    'el', 'hu', 'ro', 'nb', 'da', 'ur', 'my', 'ne', 'mr', 'ta', 'ca', 'eu', 'gl',
                    'lt', 'lv', 'et', 'sk', 'sl', 'hr', 'sr', 'bg', 'ms', 'fil', 'af', 'zu']
        if x in LINKED]

FORMATS = [None, '#,##0.00', '#,##,##0.###', '0.00E0', '##0.##E+00', '@@@', '@##', '#.##%',
           "'#'#", '0000.0', '#,##0;(#)', "#,##0.00 'and' ''", '#,##0‰', '0;0-', '#',
           '0', '.00', '#,##0.0#', '00E00', '#E0', '@@@@@@', '¤#,##0.00', ';', '#,#,#0']

# --- format_decimal ------------------------------------------------------------

for loc in ALL:
    for n in SMALL:
        case('format_decimal', [enc(n), loc, None, True, True, 'latn'],
             lambda: numbers.format_decimal(n, locale=loc))
        case('format_percent', [enc(n), loc, None, True, True, 'latn'],
             lambda: numbers.format_percent(n, locale=loc))
    case('format_scientific', [enc(1234.5), loc, None, True, True, 'latn'],
         lambda: numbers.format_scientific(1234.5, locale=loc))
    for ns in ('latn', 'default'):
        case('symbols', [loc, ns], lambda: [
            numbers.get_decimal_symbol(loc, numbering_system=ns),
            numbers.get_plus_sign_symbol(loc, numbering_system=ns),
            numbers.get_minus_sign_symbol(loc, numbering_system=ns),
            numbers.get_exponential_symbol(loc, numbering_system=ns),
            numbers.get_group_symbol(loc, numbering_system=ns),
            numbers.get_infinity_symbol(loc, numbering_system=ns)])

for loc in SOME:
    for n in NUMS:
        for fmt in FORMATS:
            for dq, gs in ((True, True), (False, True), (True, False)):
                if fmt not in (None, '#,##0.00', '@##') and not (dq and gs):
                    continue
                case('format_decimal', [enc(n), loc, fmt, dq, gs, 'latn'],
                     lambda: numbers.format_decimal(n, format=fmt, locale=loc,
                                                    decimal_quantization=dq, group_separator=gs))
        for fmt in (None, '#,##0.0%', '0‰'):
            case('format_percent', [enc(n), loc, fmt, True, True, 'latn'],
                 lambda: numbers.format_percent(n, format=fmt, locale=loc))
        for fmt in (None, '0.###E0', '00.##E+0', '#E0'):
            for dq in (True, False):
                case('format_scientific', [enc(n), loc, fmt, dq, True, 'latn'],
                     lambda: numbers.format_scientific(n, format=fmt, locale=loc,
                                                       decimal_quantization=dq))
    for ns in ('default', 'arab', 'xyz'):
        case('format_decimal', [enc(-1234.5), loc, None, True, True, ns],
             lambda: numbers.format_decimal(-1234.5, locale=loc, numbering_system=ns))

# --- currencies --------------------------------------------------------------

CURS = ['USD', 'EUR', 'JPY', 'PEN', 'CHF', 'BHD', 'GBP', 'INR', 'XXX', 'ZZZ', 'usd', 'CLP', 'BTC']
for loc in SOME:
    for cur in CURS:
        for n in [0, 1, -1, 1.0, 2, 1234.5, -1234.567, decimal.Decimal('1.0'), decimal.Decimal('1'),
                  '1', '2.5', 0.5, float('nan'), float('inf'), 1e25, decimal.Decimal('-0')]:
            for ft in ('standard', 'accounting', 'name'):
                for cd in (True, False):
                    if not cd and ft != 'standard':
                        continue
                    case('format_currency', [enc(n), cur, loc, None, cd, ft, True, True, 'latn'],
                         lambda: numbers.format_currency(n, cur, locale=loc, currency_digits=cd,
                                                         format_type=ft))
        for fmt in ('#,##0.00 ¤¤', '¤¤¤ #,##0', '¤ #,##0.00;¤ -#,##0.00', '#,##0'):
            case('format_currency', [enc(1234.5), cur, loc, fmt, True, 'standard', True, True, 'latn'],
                 lambda: numbers.format_currency(1234.5, cur, format=fmt, locale=loc))
        case('format_currency', [enc(1234.5), cur, loc, None, True, 'standard', False, False, 'latn'],
             lambda: numbers.format_currency(1234.5, cur, locale=loc, decimal_quantization=False,
                                             group_separator=False))
        case('format_currency', [enc(1.5), cur, loc, None, True, 'nonexistent', True, True, 'latn'],
             lambda: numbers.format_currency(1.5, cur, locale=loc, format_type='nonexistent'))
        case('currency_info', [cur, loc], lambda: [
            numbers.get_currency_name(cur, locale=loc),
            numbers.get_currency_symbol(cur, locale=loc),
            numbers.get_currency_precision(cur),
            numbers.get_currency_unit_pattern(cur, locale=loc),
            numbers.is_currency(cur, locale=loc),
            numbers.normalize_currency(cur, locale=loc) or ''])
        for cnt in [0, 1, 2, 5, 1.0, 1.5, decimal.Decimal('1.0'), 21, float('nan')]:
            case('currency_name', [cur, enc(cnt), loc],
                 lambda: [numbers.get_currency_name(cur, count=cnt, locale=loc),
                          numbers.get_currency_unit_pattern(cur, count=cnt, locale=loc)])
    case('list_currencies', [loc], lambda: sorted(numbers.list_currencies(loc)))
case('list_currencies', [''], lambda: sorted(numbers.list_currencies()))
for cur in CURS + ['', 'eur']:
    case('is_currency_global', [cur], lambda: [numbers.is_currency(cur),
                                                numbers.normalize_currency(cur) or ''])

for terr in ['US', 'DE', 'ZW', 'PE', 'CU', 'xk', 'ZZ', 'BT', 'CH']:
    for start, end, tender, non_tender in [((2026, 1, 1), None, True, False),
                                           ((1990, 1, 1), (2020, 12, 31), True, False),
                                           ((1950, 6, 1), None, True, True),
                                           ((2000, 1, 1), None, False, True)]:
        def run():
            s = datetime.date(*start)
            e = datetime.date(*end) if end else None
            d = numbers.get_territory_currencies(terr, s, e, tender, non_tender, include_details=True)
            return [[x['currency'], x['from'].isoformat() if x['from'] else '',
                     x['to'].isoformat() if x['to'] else '', x['tender']] for x in d]
        case('territory_currencies', [terr, list(start), list(end) if end else [], tender, non_tender], run)

# --- compact -------------------------------------------------------------------

COMPACT = [0, 1, 999, 1000, -1000, 1234, 1500, 9999, 10000, 12345, 99999, 100000, 999999,
           1000000, 1234567, -1234567, 10 ** 9, 1.5e12, 10 ** 15, 10 ** 18, 0.5, 2.675,
           decimal.Decimal('1000.0'), decimal.Decimal('2E+3'), float('nan'), float('inf'),
           '12345', 1999, 2000]
for loc in SOME:
    for n in COMPACT:
        for ft in ('short', 'long', 'medium'):
            for fd in (0, 1, 2):
                case('format_compact_decimal', [enc(n), loc, ft, fd, 'latn'],
                     lambda: numbers.format_compact_decimal(n, format_type=ft, locale=loc,
                                                            fraction_digits=fd))
        for cur in ('USD', 'EUR', 'JPY'):
            for fd in (0, 2):
                case('format_compact_currency', [enc(n), cur, loc, 'short', fd, 'latn'],
                     lambda: numbers.format_compact_currency(n, cur, locale=loc, fraction_digits=fd))
        case('format_compact_currency', [enc(n), 'USD', loc, 'long', 0, 'latn'],
             lambda: numbers.format_compact_currency(n, 'USD', locale=loc, format_type='long'))

# --- parsing ---------------------------------------------------------------------

PARSE = ['1,099', '1.099', '1 099', '1\xa0099', '1 099', '1099', '-1,099', '+5', ' 12 ',
         '1_000', '_1', 'abc', '', '1,099.98', '1.099,98', '1,0', '12,345,678.9', '1,23,456.7',
         '0.000', '1e3', '١٢٣', '99,', ',5', '1..2', '5.']
for loc in SOME:
    for s in PARSE:
        case('parse_number', [s, loc], lambda: numbers.parse_number(s, locale=loc))
        for strict in (False, True):
            def run():
                try:
                    return str(numbers.parse_decimal(s, locale=loc, strict=strict))
                except numbers.NumberFormatError as e:
                    return ['NumberFormatError', e.suggestions or []]
            case('parse_decimal', [s, loc, strict], run)

# --- patterns ---------------------------------------------------------------------

for p in FORMATS[1:] + ['#,##,##0', '###,###,##0.00', ',##0', '#,', "'a;b'0", '0.0;-0.0',
                        '@.0', '@0', '@,@@@', '+0', '0E', '0E++0', "'''0", "'abc", '0\nx']:
    def run():
        np = numbers.parse_pattern(p)
        return [np.prefix[0], np.prefix[1], np.suffix[0], np.suffix[1], np.number_pattern,
                list(np.grouping), list(np.int_prec), list(np.frac_prec),
                list(np.exp_prec) if np.exp_prec is not None else None,
                np.exp_plus if np.exp_plus is not None else None, np.scale]
    case('parse_pattern', [p], run)
    case('parse_grouping', [p], lambda: list(numbers.parse_grouping(p)))

with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for o in out:
        f.write(json.dumps(o, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
