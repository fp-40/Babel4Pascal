"""Tests of the generator (tools/cldrgen). Run: python3 -I tests/python/test_cldrgen.py

The round-trip test reads the CLDR release that tools/gencldr.py fetch
downloads into .cache/cldr; it is skipped when that is absent."""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))

import gencldr  # noqa: E402
from cldrgen import encode, importer  # noqa: E402
from cldrgen.model import Alias  # noqa: E402

COMMON = os.path.join(gencldr.CACHE, f'cldr-common-{gencldr.CLDR_VERSION}', 'common')


class TestEncode(unittest.TestCase):
    def test_values(self):
        value = {None: [0, 1, -1, 63, -64, 64, 2**40, -2**40], 'a': {1: 'x', 'b': 'x'},
                 'f': 1.5, 't': True, 'n': False, 'z': None, 'al': Alias(['days', 'format']),
                 'u': 'ñandú – 日本', 'e': '', 'l': []}
        self.assertEqual(encode.decode(encode.encode(value)), value)

    def test_insertion_order_kept(self):
        value = {'b': 1, 'a': 2, 3: 3, None: 4}
        self.assertEqual(list(encode.decode(encode.encode(value))), ['b', 'a', 3, None])


class TestIntervalSplit(unittest.TestCase):
    # Interval patterns split into their two halves.
    def test_split_interval_examples(self):
        f = importer.split_interval_pattern
        self.assertEqual(f('E d.M. – E d.M.'), ['E d.M. – ', 'E d.M.'])
        self.assertEqual(f("Y 'text' Y 'more text'"), ["Y 'text '", "Y 'more text'"])
        self.assertEqual(f('E, MMM d – E'), ['E, MMM d – ', 'E'])
        self.assertEqual(f('MMM d'), ['MMM d'])
        self.assertEqual(f('y G'), ['y G'])
        self.assertEqual(f('MMM d – d'), ['MMM d – ', 'd'])


@unittest.skipUnless(os.path.isdir(COMMON), 'CLDR release not fetched')
class TestRoundTrip(unittest.TestCase):
    def test_every_locale(self):
        imp = importer.LocaleImporter(COMMON)
        g = importer.parse_global(COMMON)
        self.assertEqual(encode.decode(encode.encode(g)), g)
        for name in imp.locale_names():
            data = imp.import_locale(name)
            self.assertEqual(encode.decode(encode.encode(data)), data, name)


if __name__ == '__main__':
    unittest.main()
