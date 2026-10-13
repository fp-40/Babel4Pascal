#!/usr/bin/env python3
"""Write test vectors for babel.units: inputs and the results the oracle
(Python Babel 2.18.0) gives for them, one JSON object per line, for
tests/units/test_units.pas.

A value is written as [kind, text] as in gen_numbers_vectors.py:
["int", "12"], ["float", "<hex of the double>"], ["dec", "1.0"] or
["str", "12"] (a preformatted value, FormatUnitText on the Pascal side).

Usage: gen_units_vectors.py OUT.jsonl
"""
import decimal
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

LINKED = oracle_linked.setup()
from babel import Locale, core, numbers, units  # noqa: E402

out = []


def enc(x):
    if isinstance(x, int):
        return ['int', str(x)]
    if isinstance(x, float):
        return ['float', '%016x' % struct.unpack('<Q', struct.pack('<d', x))[0]]
    if isinstance(x, decimal.Decimal):
        return ['dec', str(x)]
    return ['str', x]


def case(op, args, fn):
    try:
        result = fn()
        # Babel's None is '' in Babel4Pascal
        out.append({'op': op, 'args': args, 'expect': '' if result is None else result})
    except (ValueError, KeyError, IndexError, TypeError, core.UnknownLocaleError,
            numbers.UnsupportedNumberingSystemError) as e:
        out.append({'op': op, 'args': args, 'error': type(e).__name__})


LENGTHS = ['long', 'short', 'narrow']
FEW_UNITS = ['length-kilometer', 'meter', 'duration-hour', 'mass-kilogram', 'temperature-celsius',
             'digital-gigabyte']
FEW_VALUES = [0, 1, 2, 5, 1.5]
MANY_UNITS = ['length-meter', 'kilometer', 'mile', 'foot', 'inch', 'centimeter', 'hour', 'minute',
              'second', 'day', 'week', 'month', 'year', 'millisecond', 'gram', 'kilogram', 'pound',
              'ton', 'liter', 'milliliter', 'gallon', 'cup', 'celsius', 'fahrenheit', 'kelvin',
              'byte', 'kilobyte', 'megabyte', 'gigabyte', 'terabyte', 'bit', 'percent', 'permille',
              'square-meter', 'square-kilometer', 'hectare', 'acre', 'cubic-meter',
              'kilometer-per-hour', 'meter-per-second', 'mile-per-hour', 'liter-per-100-kilometer',
              'mile-per-gallon', 'kilowatt-hour', 'watt', 'volt', 'hertz', 'degree', 'radian',
              'g-force', 'calorie', 'kilocalorie', 'pixel', 'em', 'karat', 'point',
              'unknown-unit', 'per', 'er', '']
MANY_VALUES = [0, 1, 2, 3, 5, 11, 21, 100, 1234, 1.5, 0.5, 2.25, -1, -2.5,
               decimal.Decimal('1.0'), decimal.Decimal('1.00'), decimal.Decimal('12345.678'),
               '1', 'many', '3,5']
MANY_LOCALES = ['en', 'en_GB', 'en_IN', 'de', 'fr', 'fr_CA', 'es', 'es_MX', 'pt', 'pt_PT', 'it',
                'nl', 'sv', 'pl', 'ru', 'uk', 'cs', 'tr', 'el', 'ar', 'ar_EG', 'fa', 'he', 'hi',
                'bn', 'th', 'ja', 'ko', 'zh', 'zh_Hant', 'id', 'vi', 'sw', 'fi', 'da', 'ca', 'cy',
                'ga', 'lt', 'sl', 'ro', 'my', 'am', 'zu']
COMPOUNDS = [('kilometer', 'hour'), ('meter', 'second'), ('mile', 'hour'), ('liter', 'kilometer'),
             ('gram', 'meter'), ('kilogram', 'square-meter'), ('', 'hour'), ('kilometer', ''),
             ('', ''), ('byte', 'second'), ('unknown', 'hour'), ('kilometer', 'unknown')]
COMPOUND_VALUES = [(1, 1), (150, 1), (2, 2), (1.5, 1), (12, 3), (decimal.Decimal('1.0'),
                   decimal.Decimal('1.0')), ('7', '1'), ('7', '2')]


def unit_value(v, unit, length, loc, fmt=None, ns='latn'):
    return units.format_unit(v, unit, length=length, format=fmt, locale=loc, numbering_system=ns)


for loc in sorted(LINKED - {'root'}):
    for unit in FEW_UNITS:
        for length in LENGTHS:
            case('unit_name', [unit, length, loc], lambda: units.get_unit_name(unit, length, loc))
            for v in FEW_VALUES:
                case('format_unit', [enc(v), unit, length, None, 'latn', loc],
                     lambda: unit_value(v, unit, length, loc))
    case('compound', [enc(150), 'kilometer', enc(1), 'hour', 'long', None, 'latn', loc],
         lambda: units.format_compound_unit(150, 'kilometer', 1, 'hour', locale=loc))
    case('compound', [enc(3), 'liter', enc(1), 'kilometer', 'short', None, 'latn', loc],
         lambda: units.format_compound_unit(3, 'liter', 1, 'kilometer', 'short', locale=loc))

for loc in MANY_LOCALES:
    for unit in MANY_UNITS:
        for length in LENGTHS + ['wide']:
            case('unit_name', [unit, length, loc], lambda: units.get_unit_name(unit, length, loc))
            for v in MANY_VALUES:
                case('format_unit', [enc(v), unit, length, None, 'latn', loc],
                     lambda: unit_value(v, unit, length, loc))
    for unit in ['meter', 'hour', 'gigabyte']:
        for fmt in ['#,##0.00', '0', '#.#']:
            for v in [1, 1234.5, decimal.Decimal('1.0')]:
                case('format_unit', [enc(v), unit, 'short', fmt, 'latn', loc],
                     lambda: unit_value(v, unit, 'short', loc, fmt))
        for v in [12, 1234.5]:
            case('format_unit', [enc(v), unit, 'long', None, 'default', loc],
                 lambda: unit_value(v, unit, 'long', loc, None, 'default'))
    for nu, du in COMPOUNDS:
        for length in LENGTHS:
            for nv, dv in COMPOUND_VALUES:
                case('compound', [enc(nv), nu, enc(dv), du, length, None, 'latn', loc],
                     lambda: units.format_compound_unit(nv, nu or None, dv, du or None, length,
                                                        locale=loc))
        case('compound', [enc(1234.5), nu, enc(2), du, 'short', '#,##0.0', 'default', loc],
             lambda: units.format_compound_unit(1234.5, nu or None, 2, du or None, 'short',
                                                '#,##0.0', loc, numbering_system='default'))

with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for c in out:
        f.write(json.dumps(c, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
