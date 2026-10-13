# List Formatting

Unit `babel.lists`.

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

```pascal
uses babel.lists;
```

## FormatList

```pascal
function FormatList(const Items: array of string; const Locale: TLocale;
  const Style: string = 'standard'): string;
```

The items joined with the locale's list patterns.

Parameters:

- `Items`: the texts to join, in order. They are inserted as they are:
  braces or pattern placeholders in an item are not interpreted.
- `Locale`: the locale (a `TLocale` or an identifier string).
- `Style`: one of CLDR's list pattern types:

  | Style               | Use                                    | `en`, items A, B, C |
  |---------------------|----------------------------------------|---------------------|
  | `'standard'`        | 'and' list                             | A, B, and C         |
  | `'standard-short'`  | 'and' list of short items              | A, B, & C           |
  | `'standard-narrow'` | 'and' list where space is limited      | A, B, C             |
  | `'or'`              | 'or' list                              | A, B, or C          |
  | `'or-short'`        | 'or' list of short items               | A, B, or C          |
  | `'or-narrow'`       | 'or' list where space is limited       | A, B, or C          |
  | `'unit'`            | measurements, wide                     | A, B, C             |
  | `'unit-short'`      | measurements, short                    | A, B, C             |
  | `'unit-narrow'`     | measurements, narrow                   | A B C               |

Result: `''` for no items; the item itself for one; for two items the
locale's two-item pattern; for more, the start pattern, the middle
pattern for each inner item and the end pattern.

Each part of a style (start, middle, end, two items) that the locale does
not define comes from the style CLDR aliases it to: `'unit-narrow'` and
`'unit'` to `'unit-short'`, `'unit-short'` to `'standard'`,
`'standard-narrow'` to `'standard-short'` to `'standard'`, `'or-narrow'`
to `'or-short'` to `'or'`.

```pascal
FormatList(['apples', 'oranges', 'pears'], 'en');          // 'apples, oranges, and pears'
FormatList(['apples', 'oranges'], 'en');                   // 'apples and oranges'
FormatList(['apples', 'oranges', 'pears'], 'en', 'or');    // 'apples, oranges, or pears'
FormatList(['omena', 'peruna', 'aplari'], 'fi', 'or');     // 'omena, peruna tai aplari'
FormatList(['3 feet', '7 inches'], 'en', 'unit');          // '3 feet, 7 inches'
FormatList(['3′', '7″'], 'en', 'unit-narrow');             // '3′ 7″'
FormatList(['A', 'B', 'C'], 'zh');                         // 'A、B和C'
FormatList(['A', 'B', 'C'], 'de', 'unit');                 // 'A, B und C'
FormatList(['A', 'B'], 'af', 'standard-narrow');           // 'A en B'
FormatList(['x{1}y', '{0}'], 'en');                        // 'x{1}y and {0}'
FormatList([], 'en');                                      // ''
FormatList(['A'], 'en');                                   // 'A'
```

### Contextual conjunctions

In Spanish and Hebrew the conjunction depends on the item that follows
it. When the locale's pattern is the plain conjunction, it changes:

- Spanish `'y'` becomes `'e'` before a word that starts with the sound
  *i*: an initial `i`, or `hi` not followed by `a` or `e`.
- Spanish `'o'` becomes `'u'` before a word that starts with the sound
  *o*: an initial `o`, `ho`, `8`, or the number `11`.
- Hebrew `'ו'` takes a hyphen (`'ו-'`) before an item that does not start
  with a Hebrew letter.

```pascal
FormatList(['padre', 'hijo'], 'es');               // 'padre e hijo'
FormatList(['agua', 'hielo'], 'es');               // 'agua y hielo'
FormatList(['siete', 'ocho'], 'es', 'or');         // 'siete u ocho'
FormatList(['uno', 'otro', 'hora'], 'es', 'or');   // 'uno, otro u hora'
FormatList(['Paris', 'London'], 'he');             // 'Paris ו-London'
FormatList(['לוד', 'ירושלים'], 'he');              // 'לוד וירושלים'
```

Errors: a style that is none of the above and that the locale does not
have raises `EBabelValueError`:

```pascal
FormatList(['A', 'B'], 'en', 'nonexistent');
  // EBabelValueError: Locale en does not support list formatting style 'nonexistent'
```

An unknown locale raises `EUnknownLocaleError` (from the `TLocale`
conversion).

---

[API index](index.md) · [Documentation index](../index.md)
