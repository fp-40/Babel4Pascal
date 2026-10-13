#!/usr/bin/env python3
"""Write test vectors for babel.core, babel.plural and babel.decimal: inputs
and the results the oracle (Python Babel 2.18.0) gives for them, one JSON
object per line, for tests/core/test_core.pas.

The oracle sees only the locales that the Pascal test program links (the
units in src/data), so that Locale.parse chooses among the same locales.

Usage: gen_core_vectors.py OUT.jsonl
"""
import decimal
import json
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

LINKED = oracle_linked.setup()
from babel import Locale, localedata  # noqa: E402
from babel import core  # noqa: E402
from babel.plural import PluralRule, RuleError, extract_operands, to_gettext, to_javascript  # noqa: E402

out = []


def case(op, args, fn):
    """Record op(args) -> fn() result, or the Python exception class name."""
    try:
        out.append({'op': op, 'args': args, 'expect': fn()})
    except (ValueError, TypeError, KeyError, OverflowError, RuleError,
            core.UnknownLocaleError, decimal.DecimalException) as e:
        name = type(e).__name__
        if isinstance(e, decimal.DecimalException):
            name = 'DecimalException'
        out.append({'op': op, 'args': args, 'error': name})


def parts(t):
    t = tuple(t) + (None,) * (5 - len(t))
    return [x or '' for x in t]


# --- identifiers -------------------------------------------------------------

IDS = ['de', 'de_DE', 'zh_CN', 'zh_Hans_CN', 'ca_es_valencia', 'en_150', 'en_us_posix',
       'it_IT@euro', 'it_IT@custom', 'it_IT@', 'en_US.UTF-8', 'de_DE.iso885915@euro',
       'not_a_LOCALE_String', '', 'DE', 'de_de', 'sr_latn', 'sr_LATN_rs', 'es_419',
       'x', 'de_DE_1999', 'de_1999', 'de_DE_A', 'de__DE', '_DE', 'de_', 'en_US_POSIX_x',
       'zh_hant_tw', 'und', 'und_AT', 'und_Hant', 'zh_TW', 'zh_HK', 'iw', 'in', 'no', 'no_NO',
       'sh', 'tl', 'mo', 'pt', 'pt_BR', 'pt_AO', 'en_AU', 'en_ZZ', 'de_Zzzz', 'xx', 'xx_YY',
       'es_PE', 'es_MX', 'fr_CA', 'ar_EG', 'az_Cyrl', 'az_Cyrl_AZ', 'uz_Arab', 'be_TARASK',
       'ca_ES_VALENCIA', 'en_GB@oxford', 'de_AT@x', 'de_XX', 'root', 'ROOT', 'ja_JP',
       'en-US', 'zh-Hant-TW', 'es-419', 'en_US.utf8', 'C', 'en1', '123', 'de_DE_DE',
       'en_Latn', 'en_Latn_US', 'sr_ME', 'sr_Latn_ME', 'hi_Latn', 'ks_Deva', 'mn_Mong']
for ident in IDS:
    for sep in ('_', '-'):
        case('parse_locale', [ident, sep], lambda: parts(core.parse_locale(ident, sep=sep)))
        for resolve in (True, False):
            case('locale_parse', [ident, sep, resolve],
                 lambda: str(Locale.parse(ident, sep=sep, resolve_likely_subtags=resolve)))

for tup, sep in [(('de', 'DE', None, '1999', 'custom'), '_'), (('fi', None, None, None, 'custom'), '_'),
                 (('zh', 'TW', 'Hant'), '-'), (('en',), '_'), (('sr', None, 'Latn', None, None), '_')]:
    case('get_locale_identifier', [parts(tup), sep], lambda: core.get_locale_identifier(tup, sep=sep))

NEG = [
    (['de_DE', 'en_US'], ['de_DE', 'de_AT'], '_', True),
    (['de_DE', 'en_US'], ['en', 'de'], '_', True),
    (['de-DE', 'de'], ['en-us', 'de-de'], '-', True),
    (['de_DE', 'de'], ['en_US', 'DE_de'], '_', True),
    (['ja', 'en_US'], ['ja_JP', 'en_US'], '_', True),
    (['no', 'sv'], ['nb_NO', 'sv_SE'], '_', True),
    (['no', 'sv'], ['nb_NO', 'sv_SE'], '_', False),
    (['en_US', 'fr'], ['de', ''], '_', True),
    ([], ['de'], '_', True),
    (['pt_BR', 'pt'], ['pt_PT'], '_', True),
    (['zh-Hant-TW'], ['zh'], '-', True),
]
for pref, avail, sep, use_aliases in NEG:
    aliases = core.LOCALE_ALIASES if use_aliases else None
    case('negotiate_locale', [pref, avail, sep, use_aliases],
         lambda: core.negotiate_locale(pref, avail, sep=sep, aliases=aliases) or '')
    case('locale_negotiate', [pref, avail, sep, use_aliases],
         lambda: str(Locale.negotiate(pref, avail, sep=sep, aliases=aliases) or ''))

# --- every linked locale -----------------------------------------------------

IN_LOCALES = [x for x in ('en', 'es', 'fr', 'ja', 'ar', 'zh_Hant', 'ru', 'de_CH') if x in LINKED]

for name in sorted(LINKED):
    loc = Locale.parse(name) if name != 'root' else Locale('root')
    d = {
        'str': str(loc), 'repr': repr(loc),
        'display_name': loc.display_name or '', 'language_name': loc.language_name or '',
        'territory_name': loc.territory_name or '', 'script_name': loc.script_name or '',
        'english_name': loc.english_name or '',
        'character_order': loc.character_order, 'text_direction': loc.text_direction,
        'first_week_day': loc.first_week_day, 'weekend_start': loc.weekend_start,
        'weekend_end': loc.weekend_end, 'min_week_days': loc.min_week_days,
        'default_numbering_system': loc.default_numbering_system,
        'periods': dict(loc.periods),
        'display_in': {x: loc.get_display_name(x) or '' for x in IN_LOCALES},
        'language_in': {x: loc.get_language_name(x) or '' for x in IN_LOCALES},
        'territory_in': {x: loc.get_territory_name(x) or '' for x in IN_LOCALES},
    }
    out.append({'op': 'locale', 'args': [name], 'expect': d})

# --- plural rules ------------------------------------------------------------

INTS = list(range(0, 32)) + [40, 41, 100, 101, 102, 111, 1000, 1001, 10000, 100000, 1000000,
                             1000001, 2000000, -1, -2, -11, -21, 9223372036854775807]
FLOATS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 0.1 + 0.2, 1e-7, 1.25, 11.0, 21.5, 1e16, 0.05, 101.1,
          -1.5, 3.0, 1000000.0, 0.001, 1.1, 2.75, 1e22]
DECS = ['0', '1', '1.0', '1.00', '0.05', '2.10', '1E+3', '1000000', '1.000000', '1e6', '-1',
        '0.0001', '21.0', '12345678901234567890.5', '1.5', '0.0', '2', '3', '4', '5', '11',
        '101', '1000000.0', '1E6', '-0', '0.10', '1.10', '22.5', '1e-3', '0E-5', '105.1',
        '1234567890123456789012345678.95', '1.000000000000000000000000000001', '١٢٣.٥']


def bits_of(x):
    """The bits of a double as 16 hex digits (JSON numbers would not keep
    values above 2^63 exactly in the Pascal reader)."""
    return '%016x' % struct.unpack('<Q', struct.pack('<d', x))[0]


def plural_vectors(label, rule):
    d = {'tags': sorted(rule.tags), 'rules': [[t, rule.rules[t]] for t, _ in rule.abstract],
         'gettext': to_gettext(rule), 'javascript': to_javascript(rule),
         'ints': [rule(n) for n in INTS], 'floats': [rule(x) for x in FLOATS],
         'decimals': [rule(decimal.Decimal(s)) for s in DECS]}
    return d


seen = {}
for name in sorted(LINKED):
    loc = Locale('root') if name == 'root' else Locale.parse(name)
    for kind, rule in (('plural', loc.plural_form), ('ordinal', loc.ordinal_form)):
        out.append({'op': 'locale_' + kind, 'args': [name], 'expect': plural_vectors(name, rule)})

out.insert(0, {'op': 'plural_inputs', 'args': [], 'expect': {
    'ints': INTS, 'floats': [bits_of(x) for x in FLOATS], 'decimals': DECS}})

RULES = [
    {'one': 'n is 1'},
    {'one': 'n in 2..4'},
    {'few': 'n within 0..2', 'other': '@integer 1'},
    {'one': 'n is not 1'},
    {'few': 'n mod 10 in 3..4,9 and n mod 100 not in 10..19,70..79,90..99'},
    {'one': 'v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11'},
    {'one': 'n = 0..1', 'many': 'e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5'},
    {'zero': 'n = 0', 'one': 'n = 1', 'two': 'n = 2', 'few': 'n % 100 = 3..10',
     'many': 'n % 100 = 11..99'},
    {'one': 'n not in 1..3'}, {'one': 'n not within 1..3'},
    {'one': 'i = 1 and v = 0 @integer 1'},
    {'one': 'n…3'}, {'one': 'n in 1...3'}, {'one': 'n in 1…3'},
    {'one': 'w = 1 or t = 2'},
    {'one': 'c = 0 and e = 0 and n is 1'},
    {'one': '  n   is   1  '},
    # malformed
    {'one': 'n == 1'}, {'one': 'x is 1'}, {'one': 'n is'}, {'one': 'n in'},
    {'one': 'n not = 1'}, {'one': 'n is 1 and'}, {'one': 'n # 1'}, {'one': 'n is 1 1'},
    {'one': 'nis 1'}, {'one': 'n mod is 1'}, {'one': 'and is 1'},
    {'uno': 'n is 1'},
]
for rules in RULES:
    items = list(rules.items())
    case('plural_rule', [items], lambda: plural_vectors('rule', PluralRule(items)))
case('plural_rule', [[['one', 'n is 1'], ['one', 'n is 2']]],
     lambda: plural_vectors('rule', PluralRule([('one', 'n is 1'), ('one', 'n is 2')])))

# --- operands and decimals -----------------------------------------------------


def ops(x):
    n, i, v, w, f, t, c, e = extract_operands(x)
    return [str(n), str(i), v, w, str(f), str(t), c, e]


for s in DECS + ['123.4500', '0.000', '9.99E+2', '5E-2', '12.5e1']:
    case('operands_decimal', [s], lambda: ops(decimal.Decimal(s)))
for x in FLOATS + [float('inf'), float('nan')]:
    case('operands_float', [bits_of(x)], lambda: ops(x))
for n in INTS:
    case('operands_int', [n], lambda: ops(n))

DEC_STRS = ['1_000', '_1', '1__0', '1_', '1.5_0', ' 12 ', '\t-0.00\n', '+.5', '5.', '.', 'e5',
            '1e', '1E+3', '1e-3', '0012.50', '-0', 'Inf', '-infinity', 'nan', 'NaN0123', 'sNaN',
            '-sNaN7', 'nan12a', '1.2.3', '1e999999999999999999', '0.000001', '0.0000001', '1e+16',
            '12345678901234567890123', '', ' ', '+', '-', '1e+', '0', '00', '0.0', '1.', '-.0',
            '123e-10', '1E-6', '1E-7', '-12.3400E+5', 'infinit', 'Infinityx', 'NaN0',
            '١٢٣', '\u00a012\u2003', '۱۲.۵', '1\u00b2']


def dec(s):
    d = decimal.Decimal(s)
    t = d.as_tuple()
    exp = t.exponent if isinstance(t.exponent, int) else 0
    kind = {'F': 'inf', 'n': 'nan', 'N': 'snan'}.get(t.exponent, 'finite') \
        if not isinstance(t.exponent, int) else 'finite'
    return [str(d), kind, t.sign, ''.join(map(str, t.digits)), exp]


for s in DEC_STRS:
    case('decimal', [s], lambda: dec(s))

# --- decimal arithmetic (Python's default context) ----------------------------

drnd = random.Random(47)


def rand_dec():
    r = drnd.random()
    if r < 0.03:
        return drnd.choice(['Infinity', '-Infinity', 'NaN', '-NaN', '0', '-0', '0E-5', '0E+3'])
    n = drnd.choice([1, 1, 2, 3, 5, 8, 15, 27, 28, 29, 30, 40])
    digits = ''.join(drnd.choice('0123456789') for _ in range(n)).lstrip('0') or '0'
    if drnd.random() < 0.3:
        digits = digits.rstrip('0') + '0' * drnd.randrange(0, 6) if digits != '0' else '0'
    exp = drnd.randrange(-40, 41) if drnd.random() < 0.7 else drnd.randrange(-8, 9)
    return ('-' if drnd.random() < 0.3 else '') + digits + 'E' + str(exp)


def dec_ops(op, a, b):
    A = decimal.Decimal(a)
    if op == 'abs': r = abs(A)
    elif op == 'normalize': r = A.normalize()
    elif op == 'adjusted': return A.adjusted()
    elif op == 'scaleb': r = A.scaleb(int(b))
    elif op == 'pow10': r = decimal.Decimal(10) ** int(b)
    elif op == 'mul': r = A * decimal.Decimal(b)
    elif op == 'div': r = A / decimal.Decimal(b)
    elif op == 'quantize': r = A.quantize(decimal.Decimal('1E' + b))
    elif op == 'round': r = round(A, int(b))
    elif op == 'fixed': return f'{A:f}'
    elif op == 'compare': return (A > decimal.Decimal(b)) - (A < decimal.Decimal(b))
    return dec(str(r)) + [str(r)]


decimal.setcontext(decimal.Context())   # the default context
for _ in range(4000):
    op = drnd.choice(['abs', 'normalize', 'adjusted', 'scaleb', 'pow10', 'mul', 'div',
                      'quantize', 'round', 'fixed', 'compare'])
    a = rand_dec()
    if op in ('scaleb', 'pow10', 'round'):
        b = str(drnd.randrange(-35, 36))
    elif op == 'quantize':
        b = str(drnd.randrange(-35, 10))
    elif op == 'compare':
        if 'N' in a.upper() and 'INF' not in a.upper():
            a = '1E1'
        b = rand_dec()
        if 'N' in b.upper() and 'INF' not in b.upper():
            b = '2'
    else:
        b = rand_dec()
    case('decimal_op', [op, a, b], lambda: dec_ops(op, a, b))
for a, b in [('1500', '1000'), ('1000', '1000'), ('1', '3'), ('12345', '100'), ('2', '3'),
             ('1', '0'), ('0', '0'), ('0', '5'), ('-7', '2'), ('1E+30', '7'), ('5', '2')]:
    case('decimal_op', ['div', a, b], lambda: dec_ops('div', a, b))

rnd = random.Random(46)
specials = [0.0, -0.0, 1.0, 0.1, 1e16, 1e15, 123456789012345680.0, 5e-324, 1.7976931348623157e308,
            1e-5, 1e-4, 0.0001234, 2.675, 562949953421312.25, 9007199254740993.0]
doubles = specials + [struct.unpack('<d', struct.pack('<Q', rnd.getrandbits(64)))[0] for _ in range(20000)]
doubles += [rnd.uniform(-1e6, 1e6) for _ in range(5000)]
doubles += [round(rnd.uniform(0, 1000), rnd.randrange(0, 6)) for _ in range(5000)]
floats = []
for x in doubles:
    if x != x:
        continue
    floats.append([bits_of(x), repr(x), str(decimal.Decimal(str(x))) if x not in (float('inf'), float('-inf')) else ''])
out.append({'op': 'float_repr', 'args': [], 'expect': floats})

with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for o in out:
        f.write(json.dumps(o, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
