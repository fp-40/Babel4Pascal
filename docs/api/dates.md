# Date and Time

Units `babel.dates` (formatting and parsing) and `babel.tz` (time zone
rules). For an introduction with examples, see [Date and Time](../dates.md).

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

Locales are `TLocale` values (unit `babel.core`); a string converts to
one. Instants are `TDateTime` values in UTC. Zones are IANA names
(`'Europe/Madrid'`); `''` is UTC.

## babel.dates

### Exceptions

#### EDateParseError

```pascal
EDateParseError = class(EBabelValueError);
```

Raised by `ParseDate` and `ParseTime` for a text that contains no
numbers.

The functions of this unit also raise these exceptions of
`babel.errors`:

- `EBabelValueError`: an invalid pattern field length, an invalid zone
  variant, a parsed value out of range.
- `EBabelTypeError`: a time field in a date pattern; an invalid
  `FormatTimedelta` width.
- `EBabelKeyError`: a width, context or format the locale data does not
  have; a skeleton the locale lacks when `Fuzzy` is `False`.

and `EUnknownTimeZoneError` (unit `babel.tz`) for an unknown zone.

### Option records

Each record has a function that returns it with its defaults, and
`With*` methods that return a copy with one field changed, so options
read as a chain:

```pascal
DateTimeOptions.WithFormat('full').WithTimeZone('America/Lima')
```

#### TDateTimeOptions

```pascal
TDateTimeOptions = record
  Format: string;
  TimeZone: string;
  NumberingSystem: string;
  function WithFormat(const Value: string): TDateTimeOptions;
  function WithTimeZone(const Value: string): TDateTimeOptions;
  function WithNumberingSystem(const Value: string): TDateTimeOptions;
end;

function DateTimeOptions: TDateTimeOptions;
```

Options of `FormatDate`, `FormatTime` and `FormatDateAndTime`.

| Field             | Default    | Meaning |
|-------------------|------------|---------|
| `Format`          | `'medium'` | `'full'`, `'long'`, `'medium'`, `'short'`, or a date pattern |
| `TimeZone`        | `''` (UTC) | the zone to show the instant in; ignored by `FormatDate` |
| `NumberingSystem` | `'latn'`   | digits of the numeric fields and of the localized GMT: `'latn'`, `'default'` (the locale's) or a CLDR numbering system id |

#### TSkeletonOptions

```pascal
TSkeletonOptions = record
  TimeZone: string;
  Fuzzy: Boolean;
  NumberingSystem: string;
  function WithTimeZone(const Value: string): TSkeletonOptions;
  function WithFuzzy(Value: Boolean): TSkeletonOptions;
  function WithNumberingSystem(const Value: string): TSkeletonOptions;
end;

function SkeletonOptions: TSkeletonOptions;
```

Options of `FormatSkeleton`.

| Field             | Default    | Meaning |
|-------------------|------------|---------|
| `TimeZone`        | `''` (UTC) | the zone to show the instant in |
| `Fuzzy`           | `True`     | use the closest skeleton when the locale lacks the one asked for |
| `NumberingSystem` | `'latn'`   | as in `TDateTimeOptions` |

#### TIntervalKind

```pascal
TIntervalKind = (ikDateTime, ikDate, ikTime);
```

What the two ends of an interval stand for: date-times, dates (only
their dates are used) or times. It chooses the format when no interval
pattern applies.

#### TIntervalOptions

```pascal
TIntervalOptions = record
  Skeleton: string;
  TimeZone: string;
  Fuzzy: Boolean;
  Kind: TIntervalKind;
  NumberingSystem: string;
  function WithSkeleton(const Value: string): TIntervalOptions;
  function WithTimeZone(const Value: string): TIntervalOptions;
  function WithFuzzy(Value: Boolean): TIntervalOptions;
  function WithKind(Value: TIntervalKind): TIntervalOptions;
  function WithNumberingSystem(const Value: string): TIntervalOptions;
end;

function IntervalOptions: TIntervalOptions;
```

Options of `FormatInterval`.

| Field             | Default      | Meaning |
|-------------------|--------------|---------|
| `Skeleton`        | `''` (none)  | the fields to show (`'yMMMd'`) |
| `TimeZone`        | `''` (UTC)   | the zone to show the instants in |
| `Fuzzy`           | `True`       | use the closest skeleton when the locale lacks the one asked for |
| `Kind`            | `ikDateTime` | what the values stand for |
| `NumberingSystem` | `'latn'`     | as in `TDateTimeOptions` |

#### TTimedeltaOptions

```pascal
TTimedeltaOptions = record
  Granularity: string;
  Threshold: Double;
  AddDirection: Boolean;
  Format: string;
  NumberingSystem: string;
  function WithGranularity(const Value: string): TTimedeltaOptions;
  function WithThreshold(Value: Double): TTimedeltaOptions;
  function WithAddDirection(Value: Boolean): TTimedeltaOptions;
  function WithFormat(const Value: string): TTimedeltaOptions;
  function WithNumberingSystem(const Value: string): TTimedeltaOptions;
end;

function TimedeltaOptions: TTimedeltaOptions;
```

Options of `FormatTimedelta`.

| Field             | Default    | Meaning |
|-------------------|------------|---------|
| `Granularity`     | `'second'` | the smallest unit: `'year'`, `'month'`, `'week'`, `'day'`, `'hour'`, `'minute'`, `'second'` |
| `Threshold`       | `0.85`     | the fraction of a unit from which that unit is used |
| `AddDirection`    | `False`    | write the duration relative to now ('in 3 hours', '3 hours ago') |
| `Format`          | `'long'`   | `'long'`, `'short'` or `'narrow'`; `'medium'` is `'long'` |
| `NumberingSystem` | `'latn'`   | digits of the number |

#### TTimeZoneNameOptions

```pascal
TTimeZoneNameOptions = record
  Width: string;
  ZoneVariant: string;
  ReturnZone: Boolean;
  function WithWidth(const Value: string): TTimeZoneNameOptions;
  function WithZoneVariant(const Value: string): TTimeZoneNameOptions;
  function WithReturnZone(Value: Boolean): TTimeZoneNameOptions;
end;

function TimeZoneNameOptions: TTimeZoneNameOptions;
```

Options of `GetTimezoneName`.

| Field         | Default  | Meaning |
|---------------|----------|---------|
| `Width`       | `'long'` | `'long'` ('Pacific Time') or `'short'` ('PT') |
| `ZoneVariant` | `''`     | `'generic'`, `'standard'`, `'daylight'`; `''` takes it from the date (generic without a date) |
| `ReturnZone`  | `False`  | return the canonical zone name instead of a display name |

### Pattern types

#### TPatternTokenKind, TPatternToken, TPatternTokens

```pascal
TPatternTokenKind = (ptChars, ptField);
TPatternToken = record
  Kind: TPatternTokenKind;
  Text: string;     // ptChars: the literal text
  Field: Char;      // ptField: the letter
  Count: Integer;   // ptField: how many times
end;
TPatternTokens = array of TPatternToken;
```

One part of a date pattern: literal text or a field. Text between
apostrophes is a separate `ptChars` token.

#### TDateTimePattern

```pascal
TDateTimePattern = record
  Pattern: string;
  Tokens: TPatternTokens;
end;
```

A pattern and its tokens, as `ParseDatePattern` returns them.

### Names and patterns of a locale

The name functions return a `TCLDRValue` map (unit `babel.localedata`)
with integer keys; read a name with `GetInt(Key).AsString`. They raise
`EBabelKeyError` for a width or context the data does not have.

#### GetPeriodNames

```pascal
function GetPeriodNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'stand-alone'): TCLDRValue;
```

The names of the day periods, keyed by period id (`'am'`, `'pm'`,
`'noon'`, `'morning1'`...); read them with `Str(Id)`. Width:
`'abbreviated'`, `'narrow'`, `'wide'`; Context: `'format'`,
`'stand-alone'`.

```pascal
WriteLn(GetPeriodNames('en').Str('am'));                          // AM
WriteLn(GetPeriodNames('en', 'wide', 'format').Str('morning1'));  // in the morning
```

#### GetDayNames

```pascal
function GetDayNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'format'): TCLDRValue;
```

The weekday names, keyed 0 (Monday) to 6 (Sunday). Width:
`'abbreviated'`, `'narrow'`, `'short'`, `'wide'`.

```pascal
WriteLn(GetDayNames('en').GetInt(0).AsString);                 // Monday
WriteLn(GetDayNames('en', 'abbreviated').GetInt(6).AsString);  // Sun
```

#### GetMonthNames

```pascal
function GetMonthNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'format'): TCLDRValue;
```

The month names, keyed 1 (January) to 12.

```pascal
WriteLn(GetMonthNames('es').GetInt(1).AsString);                           // enero
WriteLn(GetMonthNames('ru', 'wide', 'stand-alone').GetInt(10).AsString);   // октябрь
WriteLn(GetMonthNames('ru').GetInt(10).AsString);                          // октября
```

#### GetQuarterNames

```pascal
function GetQuarterNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'format'): TCLDRValue;
```

The quarter names, keyed 1 to 4.

```pascal
WriteLn(GetQuarterNames('en').GetInt(1).AsString);   // 1st quarter
```

#### GetEraNames

```pascal
function GetEraNames(const Locale: TLocale; const Width: string = 'wide'): TCLDRValue;
```

The era names, keyed 0 (before the common era) and 1.

```pascal
WriteLn(GetEraNames('en').GetInt(1).AsString);                 // Anno Domini
WriteLn(GetEraNames('en', 'abbreviated').GetInt(0).AsString);  // BC
```

#### GetDateFormat, GetTimeFormat, GetDatetimeFormat

```pascal
function GetDateFormat(const Locale: TLocale; const Format: string = 'medium'): string;
function GetTimeFormat(const Locale: TLocale; const Format: string = 'medium'): string;
function GetDatetimeFormat(const Locale: TLocale; const Format: string = 'medium'): string;
```

The locale's date, time and date-time patterns for `'full'`, `'long'`,
`'medium'` or `'short'`. The date-time pattern has `{1}` for the date
and `{0}` for the time.

```pascal
WriteLn(GetDateFormat('en'));              // MMM d, y
WriteLn(GetDateFormat('de', 'full'));      // EEEE, d. MMMM y
WriteLn(GetTimeFormat('en', 'short'));     // h:mm a
WriteLn(GetDatetimeFormat('en'));          // {1}, {0}
```

### Time zones

#### GetTimezoneGmt

```pascal
function GetTimezoneGmt(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Width: string = 'long'; ReturnZ: Boolean = False): string;
```

The offset of `TimeZone` at the instant `UTC`.

| Width               | Example |
|---------------------|---------|
| `'long'`            | GMT-05:00 (the locale's localized GMT format) |
| `'localized_short'` | GMT-5 |
| `'short'`           | -0500 |
| `'iso8601'`         | -05:00 |
| `'iso8601_short'`   | -05 |

`ReturnZ`: `'Z'` for a zero offset.

```pascal
WriteLn(GetTimezoneGmt(D, 'America/Lima', 'en'));                   // GMT-05:00
WriteLn(GetTimezoneGmt(D, 'Asia/Kolkata', 'fr'));                   // UTC+05:30
WriteLn(GetTimezoneGmt(D, 'Asia/Kolkata', 'en', 'localized_short')); // GMT+5:30
WriteLn(GetTimezoneGmt(D, '', 'en', 'iso8601', True));              // Z
```

#### GetTimezoneLocation

```pascal
function GetTimezoneLocation(const TimeZone: string; const Locale: TLocale;
  ReturnCity: Boolean = False): string;
```

The zone's location in the locale's region format: the country when the
zone is the only or the main zone of its country, else the exemplar
city; the localized GMT format for a zone of no country. `ReturnCity`:
the exemplar city alone.

```pascal
WriteLn(GetTimezoneLocation('Europe/Madrid', 'en'));              // Spain Time
WriteLn(GetTimezoneLocation('America/Los_Angeles', 'de'));        // Los Angeles (Ortszeit)
WriteLn(GetTimezoneLocation('America/Los_Angeles', 'de', True));  // Los Angeles
WriteLn(GetTimezoneLocation('UTC', 'en'));                        // GMT+00:00
```

#### GetTimezoneName

```pascal
function GetTimezoneName(const TimeZone: string; const Locale: TLocale): string; overload;
function GetTimezoneName(const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string; overload;
function GetTimezoneName(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string; overload;
```

The zone's display name. Without a date, the generic name; with a date
(`UTC`), the standard or daylight name in effect then, unless
`Options.ZoneVariant` says which. A name the locale lacks falls back to
the generic location, then to the localized GMT format. Older zone ids
are accepted (`Asia/Calcutta`).

Raises `EUnknownTimeZoneError` for an unknown zone and `EBabelValueError`
for an invalid `ZoneVariant`.

```pascal
WriteLn(GetTimezoneName('America/Los_Angeles', 'en'));    // Pacific Time
WriteLn(GetTimezoneName(EncodeDateTime(2026, 7, 1, 12, 0, 0, 0),
  'America/Los_Angeles', 'en', TimeZoneNameOptions.WithWidth('short')));  // PDT
WriteLn(GetTimezoneName('Asia/Calcutta', 'en',
  TimeZoneNameOptions.WithReturnZone(True)));            // Asia/Kolkata
WriteLn(GetTimezoneName('Etc/GMT+5', 'en'));             // GMT-05:00
```

### Formatting

#### FormatDate

```pascal
function FormatDate(Date: TDateTime; const Locale: TLocale;
  const Format: string = 'medium'): string; overload;
function FormatDate(Date: TDateTime; const Locale: TLocale;
  const Options: TDateTimeOptions): string; overload;
```

The date of `Date`, as it is (no zone conversion), in a predefined
length or a pattern with date fields only. Of the options, `Format` and
`NumberingSystem` apply.

Raises `EBabelTypeError` for a time field in the pattern and
`EBabelValueError` for an invalid field length.

```pascal
WriteLn(FormatDate(D, 'en', 'full'));            // Tuesday, October 13, 2026
WriteLn(FormatDate(D, 'en', 'EEE, MMM d'));      // Tue, Oct 13
```

#### FormatTime

```pascal
function FormatTime(UTC: TDateTime; const Locale: TLocale): string; overload;
function FormatTime(UTC: TDateTime; const Locale: TLocale;
  const Options: TDateTimeOptions): string; overload;
```

The time of day of the instant in `Options.TimeZone`. Zone fields refer
to the zone at that instant.

```pascal
WriteLn(FormatTime(D, 'en', DateTimeOptions.WithFormat('full')
  .WithTimeZone('America/Lima')));               // 9:30:05 AM Peru Standard Time
```

#### FormatDateAndTime

```pascal
function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale): string; overload;
function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale;
  const Options: TDateTimeOptions): string; overload;
```

The date and time of the instant in `Options.TimeZone`. A predefined
length joins the date and time patterns of that length with the
locale's date-time pattern (its "at time" variant when the locale has
one); a pattern may use any field.

```pascal
WriteLn(FormatDateAndTime(D, 'en'));                       // Oct 13, 2026, 2:30:05 PM
WriteLn(FormatDateAndTime(D, 'en', DateTimeOptions.WithFormat('long')
  .WithTimeZone('Europe/Madrid')));                        // October 13, 2026 at 4:30:05 PM GMT+2
```

#### FormatSkeleton

```pascal
function FormatSkeleton(const Skeleton: string; UTC: TDateTime;
  const Locale: TLocale): string; overload;
function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale;
  const Options: TSkeletonOptions): string; overload;
```

The instant in the locale's pattern for a CLDR skeleton. `j`, `J` and
`C` stand for the locale's hour forms. With `Fuzzy`, a skeleton the
locale lacks is matched to the closest one (its standard date and time
patterns count too), and the field widths are adjusted to the ones
asked for.

Raises `EBabelKeyError` when no pattern fits.

```pascal
WriteLn(FormatSkeleton('yMMMd', D, 'de'));     // 13. Okt. 2026
WriteLn(FormatSkeleton('yMMMMd', D, 'en'));    // October 13, 2026
```

#### FormatTimedelta

```pascal
function FormatTimedelta(Seconds: Int64; const Locale: TLocale): string; overload;
function FormatTimedelta(Seconds: Int64; const Locale: TLocale;
  const Options: TTimedeltaOptions): string; overload;
```

A duration in seconds in the largest unit that reaches
`Options.Threshold` (or `Options.Granularity`), rounded half to even.
Months are 30 days, years 365. With `AddDirection`, a positive value is
in the future and a negative one in the past; without it, the sign is
ignored. Relative-time patterns the locale lacks for a width come from
the width CLDR aliases it to.

Raises `EBabelTypeError` for a `Format` other than `'narrow'`,
`'short'`, `'medium'` or `'long'`.

```pascal
WriteLn(FormatTimedelta(3 * 3600, 'en'));          // 3 hours
WriteLn(FormatTimedelta(-3 * 3600, 'en',
  TimedeltaOptions.WithAddDirection(True)));       // 3 hours ago
```

#### FormatInterval

```pascal
function FormatInterval(StartUTC, EndUTC: TDateTime; const Locale: TLocale): string; overload;
function FormatInterval(StartUTC, EndUTC: TDateTime; const Locale: TLocale;
  const Options: TIntervalOptions): string; overload;
```

A range between two instants. With a skeleton the locale has interval
patterns for, the pattern for the largest field in which the two ends
differ is used; when they do not differ in its fields, one value is
shown. Otherwise both ends are formatted (with the skeleton, or by
`Kind`) and joined with the locale's fallback pattern.

```pascal
WriteLn(FormatInterval(T1, T2, 'en',
  IntervalOptions.WithSkeleton('yMMMd')));         // Oct 13 – 16, 2026
```

#### GetPeriodId

```pascal
function GetPeriodId(UTC: TDateTime; const Locale: TLocale;
  const RuleType: string = ''; const TimeZone: string = ''): string;
```

The id of the day period of the instant in `TimeZone`
(`'morning1'`, `'afternoon1'`, `'noon'`, `'am'`...), from the locale's
day period rules. `RuleType`: `''` for the format rules, `'selection'`
for the selection rules.

```pascal
WriteLn(GetPeriodId(D, 'en'));                       // afternoon1
WriteLn(GetPeriodId(D, 'en', '', 'Asia/Tokyo'));     // night1
```

### Parsing

#### ParseDate

```pascal
function ParseDate(const S: string; const Locale: TLocale;
  const Format: string = 'medium'): TDateTime;
```

A date from the numbers of `S`, read as year, month and day in the order
of the locale's pattern for `Format` (or of `Format` itself when it is a
pattern). Digits of any script are read. A two-digit year is in
2000–2099; a month above 12 is swapped with the day; `YYYY-MM-DD` and
`YYYYMMDD` are read as ISO 8601 when `Format` is a predefined length.
When `S` contains a month name of the locale (wide or abbreviated,
format or stand-alone, as a whole word; ASCII letters without case; a
trailing period optional), that is the month, and the numbers give the
day and the year in the pattern's order. The result has no time part.

Raises `EDateParseError` for a text without digits or with fewer numbers
than needed, `EBabelValueError` for an invalid date or a pattern without
year, month or day.

```pascal
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('13.10.2026', 'de')));     // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('Oct 13, 2026', 'en')));   // 2026-10-13
WriteLn(FormatDateTime('yyyy-mm-dd', ParseDate('13 oct 2026', 'es')));    // 2026-10-13
```

#### ParseTime

```pascal
function ParseTime(const S: string; const Locale: TLocale;
  const Format: string = 'medium'): TDateTime;
```

A time from the numbers of `S`, read as hour, minute and second in the
order of the locale's pattern; minute and second may be missing. An am
or pm marker in `S` (the locale's am/pm names in every width, format and
stand-alone, or `am`/`pm`; as a whole word, compared without case,
spaces and periods, so `p.m.`, `p. m.` and `PM` are the same marker)
reads the hour on the 12-hour clock:
12 am is 0, 1 pm to 11 pm are 13 to 23. The result has no date part.

Raises `EDateParseError` for a text without digits and
`EBabelValueError` for a value out of range.

```pascal
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('3:30:15 PM', 'en')));          // 15:30:15
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('12:30 AM', 'en', 'short')));   // 00:30:00
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('12:30 p. m.', 'es', 'short'))); // 12:30:00
WriteLn(FormatDateTime('hh:nn:ss', ParseTime('3:15 p.m.', 'es', 'short')));   // 15:15:00
```

### Patterns

#### TokenizeDatePattern

```pascal
function TokenizeDatePattern(const Pattern: string): TPatternTokens;
```

The tokens of a pattern. Each quoted text is its own `ptChars` token.

```pascal
// 'EEE, MMM d ''at'' h:mm a' gives:
// field(E,3) chars(', ') field(M,3) chars(' ') field(d,1) chars(' ')
// chars('at ') field(h,1) chars(':') field(m,2) chars(' ') field(a,1)
```

#### UntokenizeDatePattern

```pascal
function UntokenizeDatePattern(const Tokens: TPatternTokens): string;
```

A pattern for the tokens; tokenizing it gives the same tokens, with
consecutive texts joined. Apostrophes are doubled, and the span of a
text from its first to its last ASCII letter is quoted.

```pascal
WriteLn(UntokenizeDatePattern(TokenizeDatePattern('h ''o''''clock'' a')));
// h 'o''clock' a
```

#### ParseDatePattern

```pascal
function ParseDatePattern(const Pattern: string): TDateTimePattern;
```

The pattern and its tokens. Raises `EBabelValueError` for a field of a
length its letter does not allow (`'MMMMMM'`).

#### SplitIntervalPattern

```pascal
function SplitIntervalPattern(const Pattern: string): TStringArray;
```

An interval pattern split where a field repeats: the part for the start
and the part for the end.

```pascal
// 'MMM d – d, y' gives ['MMM d – ', 'd, y']
```

#### MatchSkeleton

```pascal
function MatchSkeleton(const Skeleton: string; const Options: array of string;
  AllowDifferentFields: Boolean = False): string;
```

The skeleton of `Options` closest to `Skeleton`, `''` when none has the
same fields. `AllowDifferentFields`: accept a skeleton with other fields.

```pascal
MatchSkeleton('yMMMMd', ['yMd', 'yMMMd', 'MMMd', 'Hm'])    // 'yMMMd'
MatchSkeleton('yQQQ', ['yMd', 'Hm'])                       // ''
MatchSkeleton('yQQQ', ['yMd', 'Hm'], True)                 // 'yMd'
```

## babel.tz

Time zone rules from the IANA tz database installed on the system: the
TZif files under `/usr/share/zoneinfo`, or under the directory given by
the `TZDIR` environment variable or `SetZoneInfoPath`. A zone's file is
read once and kept. Lookups are safe from several threads.

### EUnknownTimeZoneError

```pascal
EUnknownTimeZoneError = class(EBabelError);
```

A zone name with no file.

### TZoneInfo

```pascal
TZoneInfo = record
  UTCOffset: Integer;     // seconds east of UTC
  DSTOffset: Integer;     // seconds of daylight saving time; 0 in standard time
  Abbreviation: string;   // 'CEST', '-05'
end;
```

What applies at one instant.

### TTimeZone

```pascal
TTimeZone = record
  property Name: string;
  function IsUTC: Boolean;
  function InfoAt(UTCSeconds: Int64): TZoneInfo; overload;
  function InfoAt(UTC: TDateTime): TZoneInfo; overload;
  function ToLocal(UTC: TDateTime): TDateTime;
  function InfoAtLocal(LocalSeconds: Int64; Fold: Integer = 0): TZoneInfo;
end;
```

A zone, as `GetTimeZone` returns it.

- `Name`: the zone's name (`'Europe/Madrid'`; `'UTC'` for `GetTimeZone('')`).
- `IsUTC`: the zone is UTC.
- `InfoAt`: the rules at an instant given in UTC (as seconds since
  1970-01-01 or a `TDateTime`). After the last transition of the file,
  the rule of its footer is computed for the year.
- `ToLocal`: the local time of an instant given in UTC.
- `InfoAtLocal`: the rules at a local wall-clock time, given as seconds
  since 1970-01-01 as if the local time were UTC. For a time that
  occurs twice (the end of daylight saving time), `Fold` 0 takes the
  first and 1 the second; for a time that does not occur, the rules
  before the gap (0) or after it (1).

```pascal
Z := GetTimeZone('Europe/Madrid');
Info := Z.InfoAt(EncodeDateTime(2026, 10, 13, 14, 30, 5, 0));
// Info.UTCOffset = 7200, Info.DSTOffset = 3600, Info.Abbreviation = 'CEST'
Info := Z.InfoAtLocal(UnixSeconds(EncodeDateTime(2026, 10, 25, 2, 30, 0, 0)), 0);
// 7200 CEST
Info := Z.InfoAtLocal(UnixSeconds(EncodeDateTime(2026, 10, 25, 2, 30, 0, 0)), 1);
// 3600 CET
```

### GetTimeZone

```pascal
function GetTimeZone(const Name: string): TTimeZone;
```

The zone. `''` and the names of UTC that have no file are UTC. Raises
`EUnknownTimeZoneError` when no file has that name.

### LocalTimeZoneName

```pascal
function LocalTimeZoneName: string;
```

The zone of the machine: the `TZ` environment variable, then the link
of `/etc/localtime`, then `/etc/timezone`; `'UTC'` when none gives one.

### ZoneInfoPath, SetZoneInfoPath

```pascal
function ZoneInfoPath: string;
procedure SetZoneInfoPath(const Path: string);
```

The directory of the zone files: `/usr/share/zoneinfo` by default, or
`TZDIR` when set.

### UnixSeconds, DateTimeOfUnix

```pascal
function UnixSeconds(DT: TDateTime): Int64;
function DateTimeOfUnix(Seconds: Int64): TDateTime;
```

Seconds since 1970-01-01 of a `TDateTime` taken as UTC (exact to the
second), and back.

```pascal
UnixSeconds(EncodeDateTime(1970, 1, 2, 0, 0, 0, 0))   // 86400
```

### DecodeDateTimeMs

```pascal
procedure DecodeDateTimeMs(DT: TDateTime; out Y, M, D, H, N, S, MS: Word);
```

The fields of a `TDateTime` rounded to the nearest millisecond.
`SysUtils.DecodeDateTime` truncates: a value encoded with 123 ms can
decode as 122.

---

[Index](../index.md) · [API Reference](index.md)
