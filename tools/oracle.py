"""The test oracle: Python Babel 2.18.0 (CLDR 47), the version whose output
Babel4Pascal reproduces.

ensure() downloads its wheel from PyPI once into .cache/oracle (checking
the SHA-256 below), extracts it, puts it first on sys.path and returns
the extracted directory. The wheel includes Babel's generated data files
(global.dat, locale-data/*.dat). It is pure Python: no pip or venv is
needed. The checks import babel only after calling ensure(), so an
installed system Babel of another version is never used.
"""
import hashlib
import os
import sys
import urllib.request
import zipfile

VERSION = '2.18.0'
WHEEL = f'babel-{VERSION}-py3-none-any.whl'
URL = ('https://files.pythonhosted.org/packages/py3/b/babel/' + WHEEL)
SHA256 = 'e2b422b277c2b9a9630c1d7903c2a00d0830c409c59ac8cae9081c92f1aeba35'

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, '.cache', 'oracle')


def ensure():
    dest = os.path.join(CACHE, f'babel-{VERSION}')
    if not os.path.isdir(os.path.join(dest, 'babel')):
        os.makedirs(CACHE, exist_ok=True)
        wheel = os.path.join(CACHE, WHEEL)
        if not os.path.exists(wheel):
            print(f'downloading {URL}', file=sys.stderr)
            urllib.request.urlretrieve(URL, wheel + '.part')
            os.replace(wheel + '.part', wheel)
        with open(wheel, 'rb') as f:
            if hashlib.sha256(f.read()).hexdigest() != SHA256:
                raise SystemExit(f'{wheel}: SHA-256 mismatch; delete it and run again')
        tmp = dest + '.part'
        with zipfile.ZipFile(wheel) as z:
            for name in z.namelist():
                if name.startswith('/') or '..' in name.split('/'):
                    raise SystemExit(f'{wheel}: unsafe member {name!r}')
            z.extractall(tmp)
        os.replace(tmp, dest)
    sys.path.insert(0, dest)
    import babel
    if babel.__version__ != VERSION:
        raise SystemExit(f'oracle: imported babel {babel.__version__} from {babel.__file__}, '
                         f'expected {VERSION}')
    return dest


# Where the values of Babel's locale data are objects rather than strings.
DATE_PATTERN_KEYS = ('date_formats', 'time_formats', 'datetime_skeletons')
NUMBER_PATTERN_KEYS = ('decimal_formats', 'currency_formats', 'percent_formats',
                       'scientific_formats', 'compact_decimal_formats', 'compact_currency_formats')


def to_babel(value, key=None):
    """Locale data from tools/cldrgen/importer.py in Babel's representation:
    patterns parsed, plural rules and aliases as Babel's objects. key: the
    top-level key the value belongs to."""
    from babel import dates, numbers
    from babel.localedata import Alias as BabelAlias
    from babel.plural import PluralRule
    from cldrgen.model import Alias
    if isinstance(value, Alias):
        return BabelAlias(value.keys)
    if key in ('plural_form', 'ordinal_form'):
        return PluralRule(value)
    if isinstance(value, dict):
        return {k: to_babel(v, k if key is None else key) for k, v in value.items()}
    if isinstance(value, list):
        return [to_babel(v, key) for v in value]
    if isinstance(value, str) and key in DATE_PATTERN_KEYS:
        return dates.parse_pattern(value)
    if isinstance(value, str) and key in NUMBER_PATTERN_KEYS:
        return numbers.parse_pattern(value)
    return value


def correct_babel_data():
    """Make Babel read each locale's data from tools/cldrgen/importer.py
    (the same CLDR release) instead of its locale-data files, so that the
    checks run Babel's code on the corrected data: the importer departs
    from Babel's import where it is wrong (week data of the likely region
    and of unlisted territories, alternate skeletons and interval formats,
    region format variants, unconfirmed and provisional data). With
    babel_compat the importer reproduces Babel's files exactly
    (tools/check_import.py). Call after ensure(), before Babel loads any
    locale."""
    import pickle
    import subprocess
    from babel import localedata
    sys.path.insert(0, os.path.join(ROOT, 'tools'))
    from cldrgen.importer import EXTRA_LOCALE_KEYS, LocaleImporter
    common = subprocess.run([sys.executable, '-I', os.path.join(ROOT, 'tools', 'gencldr.py'), 'fetch'],
                            check=True, capture_output=True, text=True).stdout.strip()
    imp = LocaleImporter(common)

    class Loader:
        @staticmethod
        def load(fileobj):
            data = pickle.load(fileobj)
            name = os.path.splitext(os.path.basename(fileobj.name))[0]
            if not os.path.exists(os.path.join(common, 'main', name + '.xml')):
                return data
            ours = {k: v for k, v in imp.import_locale(name).items() if k not in EXTRA_LOCALE_KEYS}
            corrected = to_babel(ours)
            if '_version' in data:
                corrected['_version'] = data['_version']
            return corrected

    localedata.pickle = Loader
