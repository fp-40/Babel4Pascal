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
