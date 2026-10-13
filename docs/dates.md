# Date and Time

The unit `babel.dates` formats dates, times and date-times with the
locale's CLDR patterns, formats durations and intervals, gives the
localized names of time zones, and reads simple dates and times back.

>[!NOTE]
> In the example outputs, no-break spaces (U+00A0) and narrow no-break
> spaces (U+202F) are shown as ordinary spaces.

```pascal
uses SysUtils, DateUtils, babel.core, babel.dates, babel.cldr_all;

var
  D: TDateTime;
begin
  D := EncodeDateTime(2026, 10, 13, 14, 30, 5, 123);   // UTC
  WriteLn(FormatDate(D, 'en'));         // Oct 13, 2026
  WriteLn(FormatDate(D, 'de_DE'));      // 13.10.2026
  WriteLn(FormatDate(D, 'es_PE'));      // 13 oct. 2026
end.
```

Every function takes the locale as a `TLocale`; a string such as `'en'`
or `'es_PE'` converts to one (see [Locale Data](locale.md)).

The four predefined lengths are `full`, `long`, `medium` (the default)
and `short`:

```pascal
WriteLn(FormatDate(D, 'en', 'full'));     // Tuesday, October 13, 2026
WriteLn(FormatDate(D, 'en', 'long'));     // October 13, 2026
WriteLn(FormatDate(D, 'en', 'medium'));   // Oct 13, 2026
WriteLn(FormatDate(D, 'en', 'short'));    // 10/13/26
```

Times and date-times take their options in a `TDateTimeOptions` record,
built from `DateTimeOptions` with `With*` methods:

```pascal
WriteLn(FormatTime(D, 'en', DateTimeOptions.WithFormat('full')
  .WithTimeZone('America/Lima')));
// 9:30:05 AM Peru Standard Time
WriteLn(FormatTime(D, 'en', DateTimeOptions.WithFormat('short')
  .WithTimeZone('America/Lima')));
// 9:30 AM

WriteLn(FormatDateAndTime(D, 'en', DateTimeOptions.WithFormat('full')
  .WithTimeZone('Europe/Madrid')));
// Tuesday, October 13, 2026 at 4:30:05 PM Central European Summer Time
WriteLn(FormatDateAndTime(D, 'en', DateTimeOptions.WithFormat('long')
  .WithTimeZone('Europe/Madrid')));
// October 13, 2026 at 4:30:05 PM GMT+2
WriteLn(FormatDateAndTime(D, 'en', DateTimeOptions.WithFormat('short')
  .WithTimeZone('Europe/Madrid')));
// 10/13/26, 4:30 PM
WriteLn(FormatDateAndTime(D, 'fr', DateTimeOptions.WithFormat('full')
  .WithTimeZone('Europe/Paris')));
// mardi 13 octobre 2026 à 16:30:05 heure d’été d’Europe centrale
```

A date-time joins the locale's date and time patterns with its
date-time pattern; where the locale has a separate pattern for joining a
date with a time of day ('at' in English, 'à' in French), that one is
used.

The function for date-times is `FormatDateAndTime`, because
`SysUtils` already declares `FormatDateTime`.

## Core time concepts

- A `TDateTime` given to these functions is an instant in UTC.
- The time zone to show it in is a separate argument, the `TimeZone`
  field of the options: an IANA zone name such as `'Europe/Madrid'` or
  `'America/Lima'`. An empty name is UTC.
- `FormatDate` formats the date of the value as it is, without
  converting it to a zone. To format the local date of an instant, use
  a pattern with `FormatDateAndTime`, or convert the instant first with
  `GetTimeZone(Name).ToLocal(UTC)` (unit `babel.tz`).
- `FormatTime` shows the time of day in the zone; the zone's name or
  offset, when the pattern has one, is the one in effect at that instant.
- The precision is the millisecond: the fields of a `TDateTime` are
  decoded to the nearest millisecond. Fraction digits beyond the third
  (`SSSS`...) are zeros.

To show an instant in the zone of the machine, pass `LocalTimeZoneName`
(unit `babel.tz`):

```pascal
WriteLn(FormatDateAndTime(D, 'en',
  DateTimeOptions.WithTimeZone(LocalTimeZoneName)));
// Oct 13, 2026, 9:30:05 AM   (on a machine set to America/Lima)
```

## Pattern syntax

Besides the four lengths, `Format` accepts a CLDR date pattern (UTS #35,
"Date Format Patterns"). Letters are fields; the number of repetitions
selects the field's width. Text between apostrophes is literal, and two
apostrophes write one. Other characters (spaces, punctuation) are
literal.

```pascal
WriteLn(FormatDate(D, 'en', 'EEE, MMM d, ''''yy'));        // Tue, Oct 13, '26
WriteLn(FormatDate(D, 'es', 'd ''de'' MMMM ''de'' y'));     // 13 de octubre de 2026
WriteLn(FormatTime(D, 'en', DateTimeOptions.WithFormat('HH:mm:ss.SSS')));
// 14:30:05.123
WriteLn(FormatDateAndTime(D, 'en', DateTimeOptions
  .WithFormat('h ''o''''clock'' a, zzzz').WithTimeZone('America/New_York')));
// 10 o'clock AM, Eastern Daylight Time
WriteLn(FormatDateAndTime(D, 'en', DateTimeOptions
  .WithFormat('yyyy-MM-dd''T''HH:mm:ssXXX').WithTimeZone('Asia/Kolkata')));
// 2026-10-13T20:00:05+05:30
```

`FormatDate` accepts only date fields; a time field in its pattern
raises `EBabelTypeError` ("a date has no 'H' field").

A field of a length its letter does not allow ('MMMMMM') raises
`EBabelValueError`.

### Date fields

Examples for 2026-10-13 (a Tuesday) in `en`:

| Field | Letters | Meaning | Example |
|---|---|---|---|
| Era | `G`, `GG`, `GGG` | abbreviated | AD |
| | `GGGG` | wide | Anno Domini |
| | `GGGGG` | narrow | A |
| Year | `y` | the year | 2026 |
| | `yy` | two digits | 26 |
| | `yyyy` | at least four digits | 2026 |
| | `Y` | year of the week-of-year (`w`) | 2026 |
| | `u` | extended year | 2026 |
| Quarter | `Q`, `QQ` | number | 4, 04 |
| | `QQQ` | abbreviated | Q4 |
| | `QQQQ` | wide | 4th quarter |
| | `q`... | the same, stand-alone form | 4 |
| Month | `M`, `MM` | number | 10, 10 |
| | `MMM` | abbreviated | Oct |
| | `MMMM` | wide | October |
| | `MMMMM` | narrow | O |
| | `L`... | the same, stand-alone form | Oct, October |
| Week | `w` | week of the year | 42 |
| | `W` | week of the month | 3 |
| Day | `d`, `dd` | day of the month | 13 |
| | `D` | day of the year | 286 |
| | `F` | day of week in month (2nd Tuesday) | 2 |
| Weekday | `E`, `EE`, `EEE` | abbreviated | Tue |
| | `EEEE` | wide | Tuesday |
| | `EEEEE` | narrow | T |
| | `EEEEEE` | short | Tu |
| | `e`, `ee` | local day number (1 = first day of the week) | 3 |
| | `eee`... | as `E` | Tue |
| | `c`... | as `e`, stand-alone form | 3, Tuesday |

The stand-alone forms (`L`, `q`, `c`) are the names used alone, without
a day number; some languages inflect the month differently in a date:

```pascal
// ru: stand-alone 'октябрь', in a date 'октября'
```

The week fields use the locale's first day of the week and minimal days
in the first week, from CLDR's week data for the locale's region (or its
likely region: `en` is the United States, weeks starting on Sunday).

### Time fields

Examples for 14:30:05.123 UTC in `en`; the zone fields in
`America/Los_Angeles` (Pacific Daylight Time):

| Field | Letters | Meaning | Example |
|---|---|---|---|
| Period | `a`...`aaa` | AM or PM, abbreviated | PM |
| | `aaaa` | wide | PM |
| | `aaaaa` | narrow | p |
| | `b`... | AM, PM, or noon at 12:00 | PM |
| | `B`... | flexible day period | in the afternoon |
| Hour | `h`, `hh` | 1–12 | 2, 02 |
| | `H`, `HH` | 0–23 | 14 |
| | `K` | 0–11 | 2 |
| | `k` | 1–24 | 14 |
| Minute | `m`, `mm` | minute | 30 |
| Second | `s`, `ss` | second | 5 |
| | `S`... | fraction of a second, truncated to the letters' count | 123 (`SSS`) |
| | `A` | milliseconds in the day | 52205123 |
| Zone | `z`, `zz`, `zzz` | specific short name | PDT |
| | `zzzz` | specific long name | Pacific Daylight Time |
| | `Z`, `ZZ`, `ZZZ` | ISO 8601 basic offset | -0700 |
| | `ZZZZ` | localized GMT | GMT-07:00 |
| | `ZZZZZ` | ISO 8601 extended offset, `Z` for zero | -07:00 |
| | `O` | short localized GMT | GMT-7 |
| | `OOOO` | long localized GMT | GMT-07:00 |
| | `v` | generic short name | PT |
| | `vvvv` | generic long name | Pacific Time |
| | `V` | short zone id | uslax |
| | `VV` | zone id | America/Los_Angeles |
| | `VVV` | exemplar city | Los Angeles |
| | `VVVV` | generic location | Los Angeles Time |
| | `X` | ISO 8601 offset, hours (minutes when not zero), `Z` for zero | -07 |
| | `XXX` | ISO 8601 extended, `Z` for zero | -07:00 |
| | `x`, `xx`, `xxx` | the same as `X`..., without `Z` | -07, -0700, -07:00 |

The localized GMT format uses the locale's GMT text and hour format:
`GMT+0` and `GMT+00:00` for a zero offset, `UTC+05:30` in French.

## Skeletons

A skeleton lists the fields wanted, without order or punctuation
(`'yMMMd'`: year, abbreviated month, day). `FormatSkeleton` gives the
locale's pattern for those fields:

```pascal
WriteLn(FormatSkeleton('yMMMd', D, 'en'));    // Oct 13, 2026
WriteLn(FormatSkeleton('yMMMd', D, 'de'));    // 13. Okt. 2026
WriteLn(FormatSkeleton('yMMMd', D, 'ja'));    // 2026年10月13日
WriteLn(FormatSkeleton('MMMEd', D, 'en'));    // Tue, Oct 13
WriteLn(FormatSkeleton('Hm', D, 'en'));       // 14:30
```

`j` in a skeleton is the locale's preferred hour (12- or 24-hour):

```pascal
WriteLn(FormatSkeleton('jm', D, 'en',
  SkeletonOptions.WithTimeZone('America/Lima')));    // 9:30 AM
WriteLn(FormatSkeleton('jm', D, 'de',
  SkeletonOptions.WithTimeZone('Europe/Berlin')));   // 16:30
```

`J` is also the preferred hour letter, and `C` the first hour form CLDR
allows for the locale's region, with its day period letter when that
form has one. A 12-hour skeleton without a day period gets the locale's
AM/PM marker.

When the locale has no pattern for the skeleton, the closest one is
taken (`Fuzzy`, the default) and the widths of its fields are adjusted
to the ones requested:

```pascal
WriteLn(FormatSkeleton('yMMMMd', D, 'en'));   // October 13, 2026
```

With `SkeletonOptions.WithFuzzy(False)`, a skeleton the locale lacks
raises `EBabelKeyError`.

## Intervals

`FormatInterval` formats a range between two instants with the locale's
interval patterns, writing the parts the two ends share once:

```pascal
var
  T1, T2: TDateTime;
begin
  T1 := EncodeDateTime(2026, 10, 13, 9, 0, 0, 0);
  T2 := EncodeDateTime(2026, 10, 16, 18, 0, 0, 0);
  WriteLn(FormatInterval(T1, T2, 'en', IntervalOptions.WithSkeleton('yMMMd')));
  // Oct 13 – 16, 2026
  WriteLn(FormatInterval(T1, EncodeDateTime(2026, 12, 2, 0, 0, 0, 0), 'de',
    IntervalOptions.WithSkeleton('yMMMd')));
  // 13. Okt. – 2. Dez. 2026
  WriteLn(FormatInterval(T1, EncodeDateTime(2027, 1, 5, 0, 0, 0, 0), 'es',
    IntervalOptions.WithSkeleton('yMMMd')));
  // 13 oct 2026 – 5 ene 2027
  WriteLn(FormatInterval(T1, EncodeDateTime(2026, 10, 13, 17, 30, 0, 0), 'en',
    IntervalOptions.WithSkeleton('hm')));
  // 9:00 AM – 5:30 PM
  WriteLn(FormatInterval(T1, EncodeDateTime(2026, 10, 13, 17, 30, 0, 0), 'en',
    IntervalOptions.WithSkeleton('Hm')));
  // 09:00 – 17:30
end.
```

When both ends are the same in the fields of the skeleton, the result is
one value:

```pascal
WriteLn(FormatInterval(T1, EncodeDateTime(2026, 10, 13, 17, 0, 0, 0), 'en',
  IntervalOptions.WithSkeleton('yMMMd')));
// Oct 13, 2026
```

Without a skeleton, or when the locale has no interval pattern for it,
the two ends are formatted whole and joined with the locale's fallback
pattern. `Kind` says what the values stand for:

```pascal
WriteLn(FormatInterval(T1, T2, 'en'));
// Oct 13, 2026, 9:00:00 AM – Oct 16, 2026, 6:00:00 PM
WriteLn(FormatInterval(T1, T2, 'en', IntervalOptions.WithKind(ikDate)));
// Oct 13, 2026 – Oct 16, 2026
WriteLn(FormatInterval(T1, EncodeDateTime(2026, 10, 13, 17, 30, 0, 0), 'en',
  IntervalOptions.WithKind(ikTime)));
// 9:00:00 AM – 5:30:00 PM
```

## Time delta formatting

`FormatTimedelta` writes a duration given in seconds with the largest
unit that reaches the threshold (0.85 by default), rounded:

```pascal
WriteLn(FormatTimedelta(3 * 3600, 'en'));        // 3 hours
WriteLn(FormatTimedelta(-2 * 86400, 'en'));      // 2 days
WriteLn(FormatTimedelta(40 * 86400, 'en'));      // 1 month
WriteLn(FormatTimedelta(23 * 3600, 'en'));       // 1 day
WriteLn(FormatTimedelta(0, 'en'));               // 0 seconds
```

23 hours are 0.96 of a day, above the threshold. A higher threshold keeps
smaller units:

```pascal
WriteLn(FormatTimedelta(23 * 3600, 'en', TimedeltaOptions.WithThreshold(1.1)));
// 23 hours
```

`Granularity` is the smallest unit to use (`'year'`, `'month'`,
`'week'`, `'day'`, `'hour'`, `'minute'`, `'second'`); a smaller duration
is shown as one of that unit:

```pascal
WriteLn(FormatTimedelta(45, 'en', TimedeltaOptions.WithGranularity('minute')));
// 1 minute
```

Months count 30 days and years 365.

`AddDirection` writes the duration as relative to now, in the future
for a positive value and in the past for a negative one:

```pascal
WriteLn(FormatTimedelta(3 * 3600, 'en', TimedeltaOptions.WithAddDirection(True)));
// in 3 hours
WriteLn(FormatTimedelta(-3 * 3600, 'en', TimedeltaOptions.WithAddDirection(True)));
// 3 hours ago
WriteLn(FormatTimedelta(3 * 3600, 'de', TimedeltaOptions.WithAddDirection(True)));
// in 3 Stunden
```

`Format` is the width: `'long'` (default), `'short'` or `'narrow'`
(`'medium'` is the same as `'long'`); another value raises
`EBabelTypeError`:

```pascal
WriteLn(FormatTimedelta(3 * 3600, 'en', TimedeltaOptions.WithFormat('short')));
// 3 hr
WriteLn(FormatTimedelta(3 * 3600, 'en', TimedeltaOptions.WithFormat('narrow')));
// 3h
WriteLn(FormatTimedelta(-180, 'es', TimedeltaOptions.WithAddDirection(True)
  .WithFormat('narrow')));
// hace 3 min
```

## Time-zone support

The rules of time zones (the offset from UTC and daylight saving time at
each instant) come from the IANA tz database installed on the system,
as TZif files under `/usr/share/zoneinfo` (or the directory in the
`TZDIR` environment variable). The unit `babel.tz` reads them; the names
of the zones come from CLDR.

A zone is given by its IANA name in the `TimeZone` field of the
options. An unknown name raises `EUnknownTimeZoneError`.

```pascal
uses babel.tz;

var
  Z: TTimeZone;
  Info: TZoneInfo;
begin
  Z := GetTimeZone('Europe/Madrid');
  Info := Z.InfoAt(EncodeDateTime(2026, 10, 13, 14, 30, 5, 0));
  WriteLn(Info.UTCOffset, ' ', Info.DSTOffset, ' ', Info.Abbreviation);
  // 7200 3600 CEST
  WriteLn(FormatDateTime('yyyy-mm-dd hh:nn',
    Z.ToLocal(EncodeDateTime(2026, 10, 13, 14, 30, 5, 0))));
  // 2026-10-13 16:30
end.
```

`GetTimezoneGmt` gives the offset of a zone at an instant:

```pascal
WriteLn(GetTimezoneGmt(D, 'America/Lima', 'en'));                   // GMT-05:00
WriteLn(GetTimezoneGmt(D, 'America/Lima', 'en', 'short'));          // -0500
WriteLn(GetTimezoneGmt(D, 'America/Lima', 'en', 'iso8601'));        // -05:00
WriteLn(GetTimezoneGmt(D, 'America/Lima', 'en', 'iso8601_short'));  // -05
WriteLn(GetTimezoneGmt(D, 'Asia/Kolkata', 'fr'));                   // UTC+05:30
WriteLn(GetTimezoneGmt(D, '', 'en', 'iso8601', True));              // Z
```

`GetTimezoneLocation` gives the zone's location: the country when the
zone is the only one or the main one of its country, else the city:

```pascal
WriteLn(GetTimezoneLocation('Europe/Madrid', 'en'));              // Spain Time
WriteLn(GetTimezoneLocation('America/Los_Angeles', 'en'));        // Los Angeles Time
WriteLn(GetTimezoneLocation('America/Los_Angeles', 'de'));        // Los Angeles (Ortszeit)
WriteLn(GetTimezoneLocation('America/Lima', 'fr'));               // heure : Pérou
WriteLn(GetTimezoneLocation('America/Los_Angeles', 'de', True));  // Los Angeles
```

### Localized time-zone names

`GetTimezoneName` without a date gives the generic name of the zone,
the name that does not say whether daylight saving time is in effect:

```pascal
WriteLn(GetTimezoneName('America/Los_Angeles', 'en'));   // Pacific Time
WriteLn(GetTimezoneName('America/Los_Angeles', 'en',
  TimeZoneNameOptions.WithWidth('short')));              // PT
WriteLn(GetTimezoneName('Europe/Berlin', 'de'));         // Mitteleuropäische Zeit
WriteLn(GetTimezoneName('America/Lima', 'es'));          // hora de Perú
```

With a date, it gives the specific name in effect then, standard or
daylight:

```pascal
WriteLn(GetTimezoneName(EncodeDateTime(2026, 7, 1, 12, 0, 0, 0),
  'America/Los_Angeles', 'en', TimeZoneNameOptions));
// Pacific Daylight Time
WriteLn(GetTimezoneName(EncodeDateTime(2026, 1, 1, 12, 0, 0, 0),
  'America/Los_Angeles', 'en', TimeZoneNameOptions));
// Pacific Standard Time
WriteLn(GetTimezoneName(EncodeDateTime(2026, 7, 1, 12, 0, 0, 0),
  'America/Los_Angeles', 'en', TimeZoneNameOptions.WithWidth('short')));
// PDT
WriteLn(GetTimezoneName(EncodeDateTime(2026, 7, 1, 12, 0, 0, 0),
  'Europe/Berlin', 'de', TimeZoneNameOptions));
// Mitteleuropäische Sommerzeit
```

`ZoneVariant` chooses the variant (`'generic'`, `'standard'`,
`'daylight'`) whatever the date. A zone with no name in the locale falls
back to its location ('Spain Time'), and a zone of no country to the
localized GMT format ('GMT-05:00' for `Etc/GMT+5`). Older zone names are
accepted: `Asia/Calcutta` is `Asia/Kolkata`, and `ReturnZone` gives that
canonical name.

The zone fields of patterns (`z`, `v`, `V`, `O`...) follow the same
rules at the instant formatted. A generic name (`v`) that would be wrong
at that instant is replaced: the standard name when the zone has no
daylight saving time within half a year ('India Standard Time'), and the
name with the city or country when the zone's offset differs from the
main zone of its region then.

## Day periods

The `B` field writes the flexible day periods of CLDR ('in the
morning', 'at night'), whose limits depend on the language:

```pascal
WriteLn(FormatTime(D, 'en', DateTimeOptions.WithFormat('h:mm B')));
// 2:30 in the afternoon
WriteLn(FormatTime(EncodeDateTime(2026, 10, 13, 21, 0, 0, 0), 'es',
  DateTimeOptions.WithFormat('h:mm B')));
// 9:00 de la noche
WriteLn(FormatTime(EncodeDateTime(2026, 10, 13, 5, 0, 0, 0), 'de',
  DateTimeOptions.WithFormat('h:mm BBBB')));
// 5:00 morgens
```

'Noon' is used only when the time shown is 12:00 exactly (the minutes
and seconds the pattern shows are zero); 'midnight' is not used:

```pascal
WriteLn(FormatTime(EncodeDateTime(2026, 10, 13, 12, 0, 0, 0), 'en',
  DateTimeOptions.WithFormat('h:mm B')));
// 12:00 noon
```

`GetPeriodId` gives the id of the day period of an instant:

```pascal
WriteLn(GetPeriodId(D, 'en'));                                         // afternoon1
WriteLn(GetPeriodId(EncodeDateTime(2026, 10, 13, 9, 0, 0, 0), 'en'));  // morning1
WriteLn(GetPeriodId(EncodeDateTime(2026, 10, 13, 12, 0, 0, 0), 'en')); // noon
WriteLn(GetPeriodId(D, 'en', '', 'Asia/Tokyo'));                       // night1
```

## Numbering systems

The numeric fields use ASCII digits by default (numbering system
`'latn'`). `NumberingSystem` selects another: `'default'` is the
locale's own, or a CLDR numbering system id (`'arab'`, `'deva'`,
`'thai'`...). The localized GMT offset uses the same digits; the ISO
8601 offsets always use ASCII digits.

```pascal
WriteLn(FormatDate(D, 'ar_EG', 'long'));
// 13 أكتوبر 2026
WriteLn(FormatDate(D, 'ar_EG', DateTimeOptions.WithFormat('long')
  .WithNumberingSystem('default')));
// ١٣ أكتوبر ٢٠٢٦
WriteLn(FormatDateAndTime(D, 'fa', DateTimeOptions.WithFormat('short')
  .WithNumberingSystem('default').WithTimeZone('Asia/Tehran')));
// ۲۰۲۶/۱۰/۱۳, ۱۸:۰۰
WriteLn(FormatDate(D, 'en', DateTimeOptions.WithFormat('long')
  .WithNumberingSystem('deva')));
// October १३, २०२६
WriteLn(FormatTimedelta(3 * 86400, 'ar_EG',
  TimedeltaOptions.WithNumberingSystem('default')));
// ٣ أيام
```

## Parsing

`ParseDate` and `ParseTime` read the numbers of a text in the order of
the fields of the locale's pattern. `ParseDate` also reads a month name
of the locale, and `ParseTime` an am/pm marker. Digits of any script are
accepted.

```pascal
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('10/13/26', 'en', 'short')));  // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('13.10.2026', 'de')));         // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('13/10/26', 'en_GB', 'short'))); // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('2026-10-13', 'en')));         // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('١٣/١٠/٢٠٢٦', 'ar')));          // 2026-10-13
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('15:30', 'de')));                // 15:30:00
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('3:30:15 PM', 'en')));           // 15:30:15
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('Oct 13, 2026', 'en')));       // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('13 de octubre de 2026', 'es', 'long'))); // 2026-10-13
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('12:30 PM', 'en', 'short')));    // 12:30:00
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('12:30 AM', 'en', 'short')));    // 00:30:00
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('12:30 a. m.', 'es', 'short'))); // 00:30:00
```

The rules:

- A date is read as year, month and day in the order the locale's
  pattern (or the pattern given as `Format`) has them. A two-digit year
  is in 2000–2099. When the month read is above 12, month and day are
  swapped. A text of the form `YYYY-MM-DD` or `YYYYMMDD` is read as
  ISO 8601 when `Format` is one of the four lengths.
- When the text contains a month name of the locale (wide or
  abbreviated, format or stand-alone; a trailing period optional), that
  is the month, and the numbers give the day and the year in the
  pattern's order. Names are matched as whole words; ASCII letters are
  compared without case.
- A time is read as hour, minute and second (the minute and second may
  be missing). An am or pm marker in the text (the locale's names in any
  width, or `am`/`pm`, compared without case, spaces and periods: `p.m.`,
  `p. m.` and `PM` are the same marker) reads the hour on the
  12-hour clock: 12 am is 0:00, 12 pm is 12:00, 1 pm to 11 pm are 13:00
  to 23:00.
- A text without digits, or with fewer numbers than the date needs,
  raises `EDateParseError`; a value out of range raises
  `EBabelValueError`.

---

[Index](index.md) · [API: babel.dates](api/dates.md)
