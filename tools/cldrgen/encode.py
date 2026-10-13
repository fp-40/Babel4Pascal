"""Encode imported data (dicts, lists, strings, numbers, Alias) as bytes
that src/babel.localedata.pas decodes.

Layout of one blob (all counts and indexes are unsigned LEB128 varints):

  'B4PC'           magic
  1                format version (one byte)
  nstrings         then nstrings × (byte length, UTF-8 bytes): the string
                   table; strings are stored once and referenced by index
  value            the top-level value (a map)

A value starts with a tag byte:

  0 None   1 False   2 True
  3 int    zigzag varint
  4 float  8 bytes, IEEE 754 binary64, little-endian
  5 str    index into the string table
  6 list   count, then count values
  7 map    count, then count × (key value, value), in insertion order
           (keys are None, int or str values)
  8 alias  count, then count string indexes: the path of keys
"""
import collections
import struct

from .model import Alias

MAGIC = b'B4PC'
VERSION = 1

T_NONE, T_FALSE, T_TRUE, T_INT, T_FLOAT, T_STR, T_LIST, T_MAP, T_ALIAS = range(9)


def _varint(n, out):
    assert n >= 0
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def _collect_strings(value, counter):
    if isinstance(value, str):
        counter[value] += 1
    elif isinstance(value, dict):
        for k, v in value.items():
            _collect_strings(k, counter)
            _collect_strings(v, counter)
    elif isinstance(value, list):
        for v in value:
            _collect_strings(v, counter)
    elif isinstance(value, Alias):
        for k in value.keys:
            counter[k] += 1


def encode(value):
    counter = collections.Counter()
    _collect_strings(value, counter)
    # The most frequent strings get the shortest indexes.
    strings = sorted(counter, key=lambda s: (-counter[s], s))
    index = {s: i for i, s in enumerate(strings)}

    out = bytearray(MAGIC)
    out.append(VERSION)
    _varint(len(strings), out)
    for s in strings:
        b = s.encode('utf-8')
        _varint(len(b), out)
        out += b

    def put(v):
        if v is None:
            out.append(T_NONE)
        elif v is False:
            out.append(T_FALSE)
        elif v is True:
            out.append(T_TRUE)
        elif isinstance(v, int):
            out.append(T_INT)
            _varint((v << 1) if v >= 0 else ((-v << 1) - 1), out)
        elif isinstance(v, float):
            out.append(T_FLOAT)
            out.extend(struct.pack('<d', v))
        elif isinstance(v, str):
            out.append(T_STR)
            _varint(index[v], out)
        elif isinstance(v, list):
            out.append(T_LIST)
            _varint(len(v), out)
            for x in v:
                put(x)
        elif isinstance(v, dict):
            out.append(T_MAP)
            _varint(len(v), out)
            for k, x in v.items():
                assert k is None or isinstance(k, (int, str)), k
                put(k)
                put(x)
        elif isinstance(v, Alias):
            out.append(T_ALIAS)
            _varint(len(v.keys), out)
            for k in v.keys:
                _varint(index[k], out)
        else:
            raise TypeError(f'cannot encode {type(v).__name__}: {v!r}')

    put(value)
    return bytes(out)


def decode(blob):
    """The inverse of encode (for tests of the encoder)."""
    assert blob[:4] == MAGIC and blob[4] == VERSION
    pos = 5

    def varint():
        nonlocal pos
        n = shift = 0
        while True:
            b = blob[pos]
            pos += 1
            n |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                return n

    strings = []
    for _ in range(varint()):
        n = varint()
        strings.append(blob[pos:pos + n].decode('utf-8'))
        pos += n

    def get():
        nonlocal pos
        tag = blob[pos]
        pos += 1
        if tag == T_NONE:
            return None
        if tag == T_FALSE:
            return False
        if tag == T_TRUE:
            return True
        if tag == T_INT:
            z = varint()
            return (z >> 1) if not z & 1 else -((z + 1) >> 1)
        if tag == T_FLOAT:
            pos += 8
            return struct.unpack('<d', blob[pos - 8:pos])[0]
        if tag == T_STR:
            return strings[varint()]
        if tag == T_LIST:
            return [get() for _ in range(varint())]
        if tag == T_MAP:
            d = {}
            for _ in range(varint()):
                k = get()
                d[k] = get()
            return d
        if tag == T_ALIAS:
            return Alias([strings[varint()] for _ in range(varint())])
        raise ValueError(f'bad tag {tag} at {pos - 1}')

    value = get()
    assert pos == len(blob)
    return value
