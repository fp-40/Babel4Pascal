"""Value types of the imported data that are not plain Python values."""


class Alias:
    """A reference to another part of the same locale's data, given by the
    path of keys from the top (as Babel's localedata.Alias). It occurs in
    root only (months, days, quarters, eras, currency_formats)."""

    __slots__ = ('keys',)

    def __init__(self, keys):
        self.keys = list(keys)

    def __eq__(self, other):
        return isinstance(other, Alias) and self.keys == other.keys

    def __repr__(self):
        return f'Alias({self.keys!r})'
