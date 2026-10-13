#!/usr/bin/env python3
"""Write test vectors for babel.lists: inputs and the results the oracle
(Python Babel 2.18.0) gives for them, one JSON object per line, for
tests/lists/test_lists.pas.

Usage: gen_lists_vectors.py OUT.jsonl
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_linked  # noqa: E402

LINKED = oracle_linked.setup()
from babel import lists  # noqa: E402

STYLES = ['standard', 'standard-short', 'standard-narrow', 'or', 'or-short', 'or-narrow',
          'unit', 'unit-short', 'unit-narrow', 'nonexistent']
ITEMS = [[], ['A'], ['A', 'B'], ['A', 'B', 'C'], ['A', 'B', 'C', 'D'], ['A', 'B', 'C', 'D', 'E'],
         ['x{1}y', '{0}', '}{'], ['agua', 'hielo'], ['siete', 'ocho'], ['uno', 'otro', 'hora'],
         ['Paris', 'London'], ['ירושלים', 'Tel Aviv']]

out = []
for loc in sorted(LINKED - {'root'}):
    for style in STYLES:
        for items in ITEMS:
            case = {'op': 'format_list', 'args': [items, style, loc]}
            try:
                case['expect'] = lists.format_list(items, style=style, locale=loc)
            except (ValueError, KeyError, IndexError) as e:
                case['error'] = type(e).__name__
            out.append(case)
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for c in out:
        f.write(json.dumps(c, ensure_ascii=False) + '\n')
print(f'{len(out)} vectors written to {sys.argv[1]}')
