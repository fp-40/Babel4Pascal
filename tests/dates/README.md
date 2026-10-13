# babel.dates tests

`reference.jsonl` holds the expected results of 8 462 calls of
`babel.dates` (one JSON object per line: `op`, `args`, and `expect` or
`error`). `test_dates` runs them:

```sh
build/bin/test_dates tests/dates/reference.jsonl
```

After a deliberate change, update it from the library's own results and
review the diff:

```sh
build/bin/test_dates tests/dates/reference.jsonl --update /tmp/new.jsonl
mv /tmp/new.jsonl tests/dates/reference.jsonl
git diff tests/dates/reference.jsonl
```

## Behavior checked against ICU4C

Where CLDR leaves the use of its data to the implementation, babel.dates
does what ICU does (tests/icu/README.md):

- localized GMT: the locale's hourFormat with its signs, 'GMT+0' and
  'GMT+00:00' for a zero offset (never gmtZeroFormat), two-digit hours in
  the long form, the short form cut after the hours ('GMT-5');
- zone names: found under CLDR's older ids too (Asia/Calcutta for
  Asia/Kolkata); ∅∅∅ is no name; a specific name falls back to the
  localized GMT, a generic one to the generic location; the generic
  name is the standard one when the zone has no daylight time within 184
  days ('India Standard Time'), with the location when the zone's offset
  differs from the metazone's reference zone ('Pacific Time
  (Vancouver)'); the generic location names the country when the zone
  is its only or primary zone ('Spain Time'), else the city; daylight
  time in tzdata's rearguard form (Europe/Dublin); V is the BCP 47 id,
  VV the id given, VVV 'Unknown Location' for zones of no place;
- day periods: noon only at 12:00 exactly as shown, no midnight; narrow
  and wide names fall back to the abbreviated ones (CLDR's aliases); b is
  am/pm or noon;
- skeletons: field lengths adjusted to the request (yMMMMd: 'October');
  a 12-hour skeleton gets a day period 'a'; the locale's standard date
  and time patterns count as available skeletons; j, J and C from
  CLDR's time data;
- the atTime date-time patterns for every length that has one;
- weeks: the likely region's first day and minimal days (en: Sunday);
- relative times: CLDR's aliases between widths ('hace 3 s');
- S truncates; FormatTime uses the local date; intervals compare any
  field;
- NumberingSystem option ('default': the locale's digits).
