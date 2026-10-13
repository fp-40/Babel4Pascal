#!/usr/bin/env python3
"""Write test vectors for babel.languages: inputs and the results the
oracle (Python Babel 2.18.0) gives for them, one JSON object per line,
for tests/languages/test_languages.pas.

Usage: gen_languages_vectors.py OUT.jsonl
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

oracle_linked.setup()
from babel import languages  # noqa: E402
from babel.core import get_global  # noqa: E402

out = []
territories = sorted(get_global('territory_languages')) + ['ch', 'Pe', 'XX', 'ZZ', '001', '']
for t in territories:
    for regional in (False, True):
        for de_facto in (False, True):
            out.append({'op': 'official', 'args': [t, regional, de_facto],
                        'expect': list(languages.get_official_languages(t, regional, de_facto))})
    info = languages.get_territory_language_info(t)
    out.append({'op': 'info', 'args': [t],
                'expect': [[lang, i['population_percent'], i.get('official_status') or '']
                           for lang, i in info.items()]})
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for c in out:
        f.write(json.dumps(c, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
