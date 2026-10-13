{ babel.dates - formatting and parsing of dates, times and durations with
  the locale's CLDR data.

  FormatDate(EncodeDate(2026, 10, 13), 'es_PE') gives '13 oct 2026';
  FormatDateAndTime(Now_UTC, 'en', DateTimeOptions.WithFormat('full')
  .WithTimeZone('America/Lima')) gives 'Tuesday, October 13, 2026 at
  9:30:00 AM Peru Standard Time'.

  Dates and times are TDateTime values in UTC. TimeZone names the zone to
  show them in ('Europe/Madrid'; '' is UTC); the rules come from the
  system's tz database (babel.tz). FormatDate formats the date of the
  value as it is, without a zone. Precision: milliseconds (TDateTime is
  decoded to milliseconds; the 'S' field shows microseconds as 0).

  The results follow CLDR as ICU applies it (tests/icu compares them with
  ICU4C): time zone names (localized GMT from the locale's hourFormat,
  zone aliases, generic names with partial locations, rearguard daylight
  time), day periods (noon only at 12:00 exactly, no midnight), skeleton
  field lengths adjusted to the request, the atTime date-time patterns,
  the week data of the locale's likely region, relative-time field
  aliases. FormatTimedelta counts months of 30 days and years of 365.
  NumberingSystem (options): the digits of the numeric fields and of the
  localized GMT ('latn' by default; 'default' for the locale's, as ICU).

  The date-and-time function is FormatDateAndTime: FormatDateTime is
  taken by SysUtils.

  Threading: everything here only reads shared data. }
unit babel.dates;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors, babel.localedata, babel.core, babel.tz;

type
  EDateParseError = class(EBabelValueError);   { a text that is not a date or time }

  TDateTimeOptions = record
    Format: string;     { 'full', 'long', 'medium' (default), 'short' or a pattern }
    TimeZone: string;   { '' = UTC }
    NumberingSystem: string;  { digits of the numeric fields: 'latn' (default),
                                'default' (the locale's) or a system ('arab') }
    function WithFormat(const Value: string): TDateTimeOptions;
    function WithTimeZone(const Value: string): TDateTimeOptions;
    function WithNumberingSystem(const Value: string): TDateTimeOptions;
  end;

  TSkeletonOptions = record
    TimeZone: string;
    Fuzzy: Boolean;     { True: the closest skeleton when the locale lacks it }
    NumberingSystem: string;
    function WithTimeZone(const Value: string): TSkeletonOptions;
    function WithFuzzy(Value: Boolean): TSkeletonOptions;
    function WithNumberingSystem(const Value: string): TSkeletonOptions;
  end;

  TIntervalKind = (ikDateTime, ikDate, ikTime);

  TIntervalOptions = record
    Skeleton: string;   { '' = none }
    TimeZone: string;
    Fuzzy: Boolean;
    Kind: TIntervalKind; { what the values are: dates, times or both;
                           ikDate uses only their dates }
    NumberingSystem: string;
    function WithSkeleton(const Value: string): TIntervalOptions;
    function WithTimeZone(const Value: string): TIntervalOptions;
    function WithFuzzy(Value: Boolean): TIntervalOptions;
    function WithKind(Value: TIntervalKind): TIntervalOptions;
    function WithNumberingSystem(const Value: string): TIntervalOptions;
  end;

  TTimedeltaOptions = record
    Granularity: string;    { 'year' .. 'second' (default) }
    Threshold: Double;      { 0.85 }
    AddDirection: Boolean;  { False }
    Format: string;         { 'narrow', 'short', 'long' (default); 'medium' = 'long' }
    NumberingSystem: string;  { 'latn' (default), 'default' or a system }
    function WithGranularity(const Value: string): TTimedeltaOptions;
    function WithThreshold(Value: Double): TTimedeltaOptions;
    function WithAddDirection(Value: Boolean): TTimedeltaOptions;
    function WithFormat(const Value: string): TTimedeltaOptions;
    function WithNumberingSystem(const Value: string): TTimedeltaOptions;
  end;

  TTimeZoneNameOptions = record
    Width: string;          { 'long' (default) or 'short' }
    Uncommon: Boolean;      { accepted and ignored }
    ZoneVariant: string;    { '' = from the date ('generic' without one), 'generic', 'standard', 'daylight' }
    ReturnZone: Boolean;    { the canonical zone name instead }
    function WithWidth(const Value: string): TTimeZoneNameOptions;
    function WithZoneVariant(const Value: string): TTimeZoneNameOptions;
    function WithReturnZone(Value: Boolean): TTimeZoneNameOptions;
  end;

  TPatternTokenKind = (ptChars, ptField);
  TPatternToken = record
    Kind: TPatternTokenKind;
    Text: string;           { ptChars: the literal text }
    Field: Char;            { ptField: the letter }
    Count: Integer;         { ptField: how many times }
  end;
  TPatternTokens = array of TPatternToken;

  { A parsed date/time pattern. }
  TDateTimePattern = record
    Pattern: string;
    Tokens: TPatternTokens;
  end;

function DateTimeOptions: TDateTimeOptions;
function SkeletonOptions: TSkeletonOptions;
function IntervalOptions: TIntervalOptions;
function TimedeltaOptions: TTimedeltaOptions;
function TimeZoneNameOptions: TTimeZoneNameOptions;

{ Names (maps: index or id -> name). }
function GetPeriodNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'stand-alone'): TCLDRValue;
function GetDayNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'format'): TCLDRValue;       { 0 = Monday }
function GetMonthNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'format'): TCLDRValue;       { 1 = January }
function GetQuarterNames(const Locale: TLocale; const Width: string = 'wide';
  const Context: string = 'format'): TCLDRValue;
function GetEraNames(const Locale: TLocale; const Width: string = 'wide'): TCLDRValue;
{ The locale's patterns ('full', 'long', 'medium', 'short'). }
function GetDateFormat(const Locale: TLocale; const Format: string = 'medium'): string;
function GetTimeFormat(const Locale: TLocale; const Format: string = 'medium'): string;
function GetDatetimeFormat(const Locale: TLocale; const Format: string = 'medium'): string;

{ Time zones }
{ The offset as text: Width 'long' ('GMT-05:00'), 'short' ('-0500'),
  'iso8601' ('-05:00'), 'iso8601_short' ('-05'); ReturnZ: 'Z' for UTC. }
function GetTimezoneGmt(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Width: string = 'long'; ReturnZ: Boolean = False): string;
{ The zone's location ('Peru Time', 'Los Angeles Time'); ReturnCity: the
  city alone. }
function GetTimezoneLocation(const TimeZone: string; const Locale: TLocale;
  ReturnCity: Boolean = False): string;
{ The zone's name: without a date, the generic name ('Pacific Time');
  with one, the standard or daylight name in effect then. }
function GetTimezoneName(const TimeZone: string; const Locale: TLocale): string; overload;
function GetTimezoneName(const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string; overload;
function GetTimezoneName(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string; overload;

{ Formatting }
function FormatDate(Date: TDateTime; const Locale: TLocale; const Format: string = 'medium'): string; overload;
{ Options: Format and NumberingSystem (the date is not converted to a zone). }
function FormatDate(Date: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string; overload;
function FormatTime(UTC: TDateTime; const Locale: TLocale): string; overload;
function FormatTime(UTC: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string; overload;
function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale): string; overload;
function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string; overload;
{ A CLDR skeleton ('yMMMd', 'Hm') in the locale's pattern for it. }
function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale): string; overload;
function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale;
  const Options: TSkeletonOptions): string; overload;
{ A duration in seconds ('3 hours', 'in 2 days'). }
function FormatTimedelta(Seconds: Int64; const Locale: TLocale): string; overload;
function FormatTimedelta(Seconds: Int64; const Locale: TLocale; const Options: TTimedeltaOptions): string; overload;
{ An interval ('Jan 5 – 10, 2026'). }
function FormatInterval(StartUTC, EndUTC: TDateTime; const Locale: TLocale): string; overload;
function FormatInterval(StartUTC, EndUTC: TDateTime; const Locale: TLocale;
  const Options: TIntervalOptions): string; overload;
{ The day period ('morning1', 'am', ...) of a time; RuleType '' or
  'selection'. }
function GetPeriodId(UTC: TDateTime; const Locale: TLocale; const RuleType: string = '';
  const TimeZone: string = ''): string;

{ Parsing: the numbers of the text read in the order of the fields of
  the locale's pattern. }
function ParseDate(const S: string; const Locale: TLocale; const Format: string = 'medium'): TDateTime;
function ParseTime(const S: string; const Locale: TLocale; const Format: string = 'medium'): TDateTime;

{ Patterns }
function TokenizeDatePattern(const Pattern: string): TPatternTokens;
function UntokenizeDatePattern(const Tokens: TPatternTokens): string;
{ Raises EBabelValueError for a field of an invalid length. }
function ParseDatePattern(const Pattern: string): TDateTimePattern;
function SplitIntervalPattern(const Pattern: string): TStringArray;
{ The skeleton of Options closest to Skeleton; '' when none fits. }
function MatchSkeleton(const Skeleton: string; const Options: array of string;
  AllowDifferentFields: Boolean = False): string;

implementation

uses
  Classes, Math, DateUtils, babel.decimal, babel.plural, babel.pystr, babel.numbers;

const
  NoInheritanceMarker = #$E2#$88#$85#$E2#$88#$85#$E2#$88#$85;   { ∅∅∅ }
  PatternChars = 'GyYuQqMLwWdDFgEecabBhHKkmsSAzZOvVxX';
  PatternCharOrder = 'GyYuUQqMLlwWdDFgEecabBChHKkjJmsSAzZOvVXx';

{ ---- options ---- }

function DateTimeOptions: TDateTimeOptions;
begin
  Result := Default(TDateTimeOptions);
  Result.Format := 'medium';
  Result.NumberingSystem := 'latn';
end;

function TDateTimeOptions.WithNumberingSystem(const Value: string): TDateTimeOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function TDateTimeOptions.WithFormat(const Value: string): TDateTimeOptions;
begin
  Result := Self;
  Result.Format := Value;
end;

function TDateTimeOptions.WithTimeZone(const Value: string): TDateTimeOptions;
begin
  Result := Self;
  Result.TimeZone := Value;
end;

function SkeletonOptions: TSkeletonOptions;
begin
  Result := Default(TSkeletonOptions);
  Result.Fuzzy := True;
  Result.NumberingSystem := 'latn';
end;

function TSkeletonOptions.WithNumberingSystem(const Value: string): TSkeletonOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function TSkeletonOptions.WithTimeZone(const Value: string): TSkeletonOptions;
begin
  Result := Self;
  Result.TimeZone := Value;
end;

function TSkeletonOptions.WithFuzzy(Value: Boolean): TSkeletonOptions;
begin
  Result := Self;
  Result.Fuzzy := Value;
end;

function IntervalOptions: TIntervalOptions;
begin
  Result := Default(TIntervalOptions);
  Result.Fuzzy := True;
  Result.Kind := ikDateTime;
  Result.NumberingSystem := 'latn';
end;

function TIntervalOptions.WithNumberingSystem(const Value: string): TIntervalOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function TIntervalOptions.WithSkeleton(const Value: string): TIntervalOptions;
begin
  Result := Self;
  Result.Skeleton := Value;
end;

function TIntervalOptions.WithTimeZone(const Value: string): TIntervalOptions;
begin
  Result := Self;
  Result.TimeZone := Value;
end;

function TIntervalOptions.WithFuzzy(Value: Boolean): TIntervalOptions;
begin
  Result := Self;
  Result.Fuzzy := Value;
end;

function TIntervalOptions.WithKind(Value: TIntervalKind): TIntervalOptions;
begin
  Result := Self;
  Result.Kind := Value;
end;

function TimedeltaOptions: TTimedeltaOptions;
begin
  Result := Default(TTimedeltaOptions);
  Result.Granularity := 'second';
  Result.Threshold := 0.85;
  Result.Format := 'long';
  Result.NumberingSystem := 'latn';
end;

function TTimedeltaOptions.WithNumberingSystem(const Value: string): TTimedeltaOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function TTimedeltaOptions.WithGranularity(const Value: string): TTimedeltaOptions;
begin
  Result := Self;
  Result.Granularity := Value;
end;

function TTimedeltaOptions.WithThreshold(Value: Double): TTimedeltaOptions;
begin
  Result := Self;
  Result.Threshold := Value;
end;

function TTimedeltaOptions.WithAddDirection(Value: Boolean): TTimedeltaOptions;
begin
  Result := Self;
  Result.AddDirection := Value;
end;

function TTimedeltaOptions.WithFormat(const Value: string): TTimedeltaOptions;
begin
  Result := Self;
  Result.Format := Value;
end;

function TimeZoneNameOptions: TTimeZoneNameOptions;
begin
  Result := Default(TTimeZoneNameOptions);
  Result.Width := 'long';
end;

function TTimeZoneNameOptions.WithWidth(const Value: string): TTimeZoneNameOptions;
begin
  Result := Self;
  Result.Width := Value;
end;

function TTimeZoneNameOptions.WithZoneVariant(const Value: string): TTimeZoneNameOptions;
begin
  Result := Self;
  Result.ZoneVariant := Value;
end;

function TTimeZoneNameOptions.WithReturnZone(Value: Boolean): TTimeZoneNameOptions;
begin
  Result := Self;
  Result.ReturnZone := Value;
end;

{ ---- small helpers ---- }

{ '%0*d' % (Width, V) }
function Pad(V: Int64; Width: Integer): string;
begin
  Result := IntToStr(System.Abs(V));
  if Length(Result) < Width - Ord(V < 0) then
    Result := StringOfChar('0', Width - Ord(V < 0) - Length(Result)) + Result;
  if V < 0 then
    Result := '-' + Result;
end;

{ '%+03d' % V }
function SignedPad2(V: Int64): string;
begin
  if V < 0 then
    Result := '-' + Pad(-V, 2)
  else
    Result := '+' + Pad(V, 2);
end;

function FloorDiv(A, B: Int64): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then
    Dec(Result);
end;

{ fmt % arg for a pattern with one '%s' }
function PercentS(const Fmt, Arg: string): string;
begin
  Result := StringReplace(Fmt, '%s', Arg, []);
end;

(* fmt % {'0': a, '1': b} *)
function PercentNamed(const Fmt, A0, A1: string): string;
begin
  Result := StringReplace(StringReplace(Fmt, '%(0)s', A0, [rfReplaceAll]), '%(1)s', A1, [rfReplaceAll]);
end;

function Need(V: TCLDRValue; const Key: string): TCLDRValue;
begin
  if V = nil then
    raise EBabelKeyError.Create(Key);
  Result := V.Get(Key);
  if Result = nil then
    raise EBabelKeyError.Create(Key);
end;

function NeedInt(V: TCLDRValue; Key: Int64): TCLDRValue;
begin
  if V = nil then
    raise EBabelKeyError.Create(IntToStr(Key));
  Result := V.GetInt(Key);
  if Result = nil then
    raise EBabelKeyError.Create(IntToStr(Key));
end;

{ ---- names and patterns of the locale ---- }

function GetPeriodNames(const Locale: TLocale; const Width, Context: string): TCLDRValue;
begin
  Result := Need(Need(Locale.Data, 'day_periods'), Context).Get(Width);
  if Result = nil then
    raise EBabelKeyError.Create(Width);
end;

function GetDayNames(const Locale: TLocale; const Width, Context: string): TCLDRValue;
begin
  Result := Need(Need(Locale.Data, 'days'), Context).Get(Width);
  if Result = nil then
    raise EBabelKeyError.Create(Width);
end;

function GetMonthNames(const Locale: TLocale; const Width, Context: string): TCLDRValue;
begin
  Result := Need(Need(Locale.Data, 'months'), Context).Get(Width);
  if Result = nil then
    raise EBabelKeyError.Create(Width);
end;

function GetQuarterNames(const Locale: TLocale; const Width, Context: string): TCLDRValue;
begin
  Result := Need(Need(Locale.Data, 'quarters'), Context).Get(Width);
  if Result = nil then
    raise EBabelKeyError.Create(Width);
end;

function GetEraNames(const Locale: TLocale; const Width: string): TCLDRValue;
begin
  Result := Need(Locale.Data, 'eras').Get(Width);
  if Result = nil then
    raise EBabelKeyError.Create(Width);
end;

function GetDateFormat(const Locale: TLocale; const Format: string): string;
begin
  Result := Need(Locale.Data, 'date_formats').Str(Format, #0);
  if Result = #0 then
    raise EBabelKeyError.Create(Format);
end;

function GetTimeFormat(const Locale: TLocale; const Format: string): string;
begin
  Result := Need(Locale.Data, 'time_formats').Str(Format, #0);
  if Result = #0 then
    raise EBabelKeyError.Create(Format);
end;

function GetDatetimeFormat(const Locale: TLocale; const Format: string): string;
var
  P: TCLDRValue;
begin
  P := Need(Locale.Data, 'datetime_formats');
  if not P.Has(Format) then
  begin
    { a length the locale does not have: the entry without a length,
      which CLDR does not give (EBabelKeyError) }
    if P.GetNone = nil then
      raise EBabelKeyError.Create('None');
    Exit(P.GetNone.AsString);
  end;
  Result := P.Str(Format);
end;

function IsPredefined(const Format: string): Boolean;
begin
  Result := (Format = 'full') or (Format = 'long') or (Format = 'medium') or (Format = 'short');
end;

{ ---- patterns: tokens, parsing, interval splitting ---- }

function IsPatternChar(C: Char): Boolean; inline;
begin
  Result := Pos(C, PatternChars) > 0;
end;

function TokenizeDatePattern(const Pattern: string): TPatternTokens;
var
  P: string;
  Quoting: Boolean;
  QuoteBuf, CharBuf: string;
  FieldChar: Char;
  FieldNum, I: Integer;

  procedure Add(Kind: TPatternTokenKind; const Text: string; F: Char; N: Integer);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Kind := Kind;
    Result[High(Result)].Text := Text;
    Result[High(Result)].Field := F;
    Result[High(Result)].Count := N;
  end;

  procedure AppendChars;
  begin
    Add(ptChars, StringReplace(CharBuf, #0, '''', [rfReplaceAll]), #0, 0);
    CharBuf := '';
  end;

  procedure AppendField;
  begin
    Add(ptField, '', FieldChar, FieldNum);
    FieldChar := #0;
    FieldNum := 0;
  end;

begin
  Result := nil;
  P := StringReplace(Pattern, '''''', #0, [rfReplaceAll]);
  Quoting := False;
  QuoteBuf := '';
  CharBuf := '';
  FieldChar := #0;
  FieldNum := 0;
  for I := 1 to Length(P) do
  begin
    if not Quoting then
    begin
      if P[I] = '''' then
      begin
        if FieldChar <> #0 then
          AppendField
        else if CharBuf <> '' then
          AppendChars;
        Quoting := True;
        QuoteBuf := '';
      end
      else if IsPatternChar(P[I]) then
      begin
        if CharBuf <> '' then
          AppendChars;
        if P[I] = FieldChar then
          Inc(FieldNum)
        else
        begin
          if FieldChar <> #0 then
            AppendField;
          FieldChar := P[I];
          FieldNum := 1;
        end;
      end
      else
      begin
        if FieldChar <> #0 then
          AppendField;
        CharBuf := CharBuf + P[I];
      end;
    end
    else
    begin
      if P[I] = '''' then
      begin
        CharBuf := CharBuf + QuoteBuf;
        Quoting := False;
      end
      else
        QuoteBuf := QuoteBuf + P[I];
    end;
  end;
  if FieldChar <> #0 then
    AppendField
  else if CharBuf <> '' then
    AppendChars;
end;

(* A literal text in pattern syntax: apostrophes doubled, and the span
  from its first to its last ASCII letter quoted (CLDR reserves all
  letters for fields): ' o''clock ' is written " 'o''clock' ". *)
function QuoteLiteral(const Text: string): string;
var
  I, First, Last: Integer;

  function Escaped(const S: string): string;
  begin
    Result := StringReplace(S, '''', '''''', [rfReplaceAll]);
  end;

begin
  First := 0;
  Last := 0;
  for I := 1 to Length(Text) do
    if Text[I] in ['A'..'Z', 'a'..'z'] then
    begin
      if First = 0 then
        First := I;
      Last := I;
    end;
  if First = 0 then
    Exit(Escaped(Text));
  Result := Escaped(Copy(Text, 1, First - 1)) + '''' + Escaped(Copy(Text, First, Last - First + 1)) +
    '''' + Escaped(Copy(Text, Last + 1, MaxInt));
end;

{ The pattern of the tokens; tokenizing it gives the same tokens, with
  consecutive texts joined. }
function UntokenizeDatePattern(const Tokens: TPatternTokens): string;
var
  T: TPatternToken;
  Text: string;
begin
  Result := '';
  Text := '';
  for T in Tokens do
    if T.Kind = ptField then
    begin
      Result := Result + QuoteLiteral(Text) + StringOfChar(T.Field, T.Count);
      Text := '';
    end
    else
      { consecutive texts as one: quoting each apart would write two
        quotes between them, which read as an apostrophe }
      Text := Text + T.Text;
  Result := Result + QuoteLiteral(Text);
end;

{ The lengths each field allows; '' = any. }
function AllowedLengths(F: Char): string;
begin
  case F of
    'G', 'Q', 'q', 'M', 'L', 'a', 'b', 'B', 'Z', 'x', 'X': Result := '12345';
    'w', 'd', 'h', 'H', 'K', 'k', 'm', 's': Result := '12';
    'W', 'F': Result := '1';
    'D': Result := '123';
    'E', 'e': Result := '123456';
    'c': Result := '13456';
    'z', 'V': Result := '1234';
    'O', 'v': Result := '14';
  else
    Result := '';    { y Y u g S A }
  end;
end;

function ParseDatePattern(const Pattern: string): TDateTimePattern;
var
  T: TPatternToken;
  Allowed: string;
begin
  Result.Pattern := Pattern;
  Result.Tokens := TokenizeDatePattern(Pattern);
  for T in Result.Tokens do
    if T.Kind = ptField then
    begin
      Allowed := AllowedLengths(T.Field);
      if (Allowed <> '') and ((T.Count > 9) or (Pos(Chr(Ord('0') + T.Count), Allowed) = 0)) then
        raise EBabelValueError.CreateFmt('Invalid length for field: ''%s''',
          [StringOfChar(T.Field, T.Count)]);
    end;
end;

function SplitIntervalPattern(const Pattern: string): TStringArray;
var
  Tokens, Part: TPatternTokens;
  Seen: string;
  T: TPatternToken;
begin
  Result := nil;
  Tokens := TokenizeDatePattern(Pattern);
  Seen := '';
  Part := nil;
  for T in Tokens do
  begin
    if T.Kind = ptField then
    begin
      if Pos(T.Field, Seen) > 0 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := UntokenizeDatePattern(Part);
        Part := nil;
        Seen := '';
      end;
      Seen := Seen + T.Field;
    end;
    SetLength(Part, Length(Part) + 1);
    Part[High(Part)] := T;
  end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := UntokenizeDatePattern(Part);
end;

{ The width of each field of a skeleton (the last token of a letter wins,
  as dict() keeps the last). }
function FieldWidth(const Tokens: TPatternTokens; F: Char): Integer;
var
  T: TPatternToken;
begin
  Result := 0;
  for T in Tokens do
    if (T.Kind = ptField) and (T.Field = F) then
      Result := T.Count;
end;

function MatchSkeleton(const Skeleton: string; const Options: array of string;
  AllowDifferentFields: Boolean): string;
var
  Sorted: array of string;
  I, J, Distance, BestDistance, InW, OptW: Integer;
  S, T, Option: string;
  InTokens, OptTokens: TPatternTokens;
  F: Char;
  Rejected: Boolean;

  function AnyHas(C: Char): Boolean;
  var
    X: string;
  begin
    for X in Sorted do
      if Pos(C, X) > 0 then
        Exit(True);
    Result := False;
  end;

begin
  Result := '';
  Sorted := nil;
  for S in Options do
    if S <> '' then
    begin
      SetLength(Sorted, Length(Sorted) + 1);
      Sorted[High(Sorted)] := S;
    end;
  for I := 1 to High(Sorted) do
  begin
    T := Sorted[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(Sorted[J], T) > 0) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := T;
  end;
  S := Skeleton;
  if (Pos('z', S) > 0) and not AnyHas('z') then S := StringReplace(S, 'z', 'v', [rfReplaceAll]);
  if (Pos('k', S) > 0) and not AnyHas('k') then S := StringReplace(S, 'k', 'H', [rfReplaceAll]);
  if (Pos('K', S) > 0) and not AnyHas('K') then S := StringReplace(S, 'K', 'h', [rfReplaceAll]);
  if (Pos('a', S) > 0) and not AnyHas('a') then S := StringReplace(S, 'a', '', [rfReplaceAll]);
  if (Pos('b', S) > 0) and not AnyHas('b') then S := StringReplace(S, 'b', '', [rfReplaceAll]);
  InTokens := TokenizeDatePattern(S);
  BestDistance := 0;
  for Option in Sorted do
  begin
    OptTokens := TokenizeDatePattern(Option);
    Distance := 0;
    Rejected := False;
    for F in PatternChars do
    begin
      InW := FieldWidth(InTokens, F);
      OptW := FieldWidth(OptTokens, F);
      if InW = OptW then
        Continue;
      if (OptW = 0) or (InW = 0) then
      begin
        if not AllowDifferentFields then
        begin
          Rejected := True;
          Break;
        end;
        Inc(Distance, $1000);
      end
      else if (F = 'M') and (((InW > 2) and (OptW <= 2)) or ((InW <= 2) and (OptW > 2))) then
        Inc(Distance, $100)
      else
        Inc(Distance, System.Abs(InW - OptW));
    end;
    if Rejected then
      Continue;
    if (Result = '') or (Distance < BestDistance) then
    begin
      Result := Option;
      BestDistance := Distance;
    end;
    if Distance = 0 then
      Break;
  end;
end;

{ ---- values ---- }

type
  TValueKind = (vkDate, vkTime, vkDateTime);

  { A date, a time or a datetime as the field formatting sees it: the
    local fields, and for times and datetimes the zone. }
  TValue = record
    Kind: TValueKind;
    Y, M, D, H, N, S, Micro: Integer;
    ZoneName: string;           { 'UTC' or the zone's key }
    Zone: TTimeZone;
    Fold: Integer;
    HasRef: Boolean;            { a time with a reference date }
    RefY, RefM, RefD: Integer;
    Digits: TCodePoints;        { of the numeric fields; nil: ASCII }
    HasMinute, HasSecond: Boolean;  { the pattern shows them (for noon) }
  end;

procedure DecodeFields(DT: TDateTime; var V: TValue);
var
  Y, M, D, H, N, S, MS: Word;
begin
  DecodeDateTimeMs(DT, Y, M, D, H, N, S, MS);
  V.Y := Y; V.M := M; V.D := D;
  V.H := H; V.N := N; V.S := S;
  V.Micro := MS * 1000;
end;

function DateValue(DT: TDateTime): TValue;
begin
  Result := Default(TValue);
  Result.Kind := vkDate;
  DecodeFields(DT, Result);
  Result.ZoneName := 'UTC';
  Result.Zone := GetTimeZone('');
end;

{ A datetime in a zone: UTC converted to the zone, with the fold of a
  repeated local time. }
function DateTimeValue(UTC: TDateTime; const TimeZone: string): TValue;
var
  Info: TZoneInfo;
  Local: TDateTime;
  LocalSecs: Int64;
begin
  Result := Default(TValue);
  Result.Kind := vkDateTime;
  Result.Zone := GetTimeZone(TimeZone);
  Result.ZoneName := Result.Zone.Name;
  Info := Result.Zone.InfoAt(UTC);
  Local := DateUtils.IncSecond(UTC, Info.UTCOffset);
  DecodeFields(Local, Result);
  { the second of two repeated local times has fold 1 }
  LocalSecs := UnixSeconds(UTC) + Info.UTCOffset;
  if (Result.Zone.InfoAtLocal(LocalSecs, 0).UTCOffset <> Info.UTCOffset) and
     (Result.Zone.InfoAtLocal(LocalSecs, 1).UTCOffset = Info.UTCOffset) then
    Result.Fold := 1;
end;

function LocalSeconds(const V: TValue): Int64;
var
  Y, M, D: Integer;
begin
  if V.Kind = vkTime then
  begin
    Y := V.RefY; M := V.RefM; D := V.RefD;
  end
  else
  begin
    Y := V.Y; M := V.M; D := V.D;
  end;
  Result := UnixSeconds(EncodeDate(Y, M, D)) + V.H * 3600 + V.N * 60 + V.S;
end;

{ The UTC offset and daylight saving time of the value (a time with a
  reference date is combined with it; the fold is kept). }
function ZoneInfoOf(const V: TValue): TZoneInfo;
begin
  Result := V.Zone.InfoAtLocal(LocalSeconds(V), V.Fold);
end;

function Weekday(Y, M, D: Integer): Integer;   { 0 = Monday }
begin
  Result := DayOfTheWeek(EncodeDate(Y, M, D)) - 1;
end;

function DayOfYear(Y, M, D: Integer): Integer;
begin
  Result := Trunc(EncodeDate(Y, M, D) - EncodeDate(Y, 1, 1)) + 1;
end;

{ ---- time zone names ---- }

{ CLDR's localized GMT format: gmtFormat around hourFormat
  ('+HH:mm;-HH:mm', the locale's signs), in the given digits. Short (the
  'O' field and the short fallback of 'z'): hours without a leading zero
  and minutes only when not zero ('GMT-5', 'GMT-3:30'). }
function LocalizedGmt(OffsetSeconds: Integer; const Locale: TLocale; Short: Boolean;
  const Digits: TCodePoints): string;
var
  HourFormat, Part, Hour: string;
  P, H, M, Hours, Minutes, Secs: Integer;
begin
  { as ICU: a zero offset is written with the positive pattern ('GMT+0',
    'GMT+00:00'); CLDR's gmtZeroFormat is not used }
  HourFormat := Locale.Data.Path(['gmt_formats']).Str('hour', '+HH:mm;-HH:mm');
  P := Pos(';', HourFormat);
  if OffsetSeconds >= 0 then
    Part := Copy(HourFormat, 1, P - 1)
  else
    Part := Copy(HourFormat, P + 1, MaxInt);
  Secs := System.Abs(OffsetSeconds);
  Hours := Secs div 3600;
  Minutes := (Secs mod 3600) div 60;
  M := Pos('mm', Part);
  H := Pos('H', Part);
  if (H = 0) or (M = 0) then
    raise EBabelValueError.CreateFmt('Invalid hour format %s', [HourFormat]);
  { short without minutes: the pattern up to the hours (ICU's
    truncateOffsetPattern drops what follows them) }
  if Short and (Minutes = 0) then
    Part := Copy(Part, 1, H + Ord(Copy(Part, H, 2) = 'HH'));
  { the hours have one digit or more in the short form, two in the long
    one, whatever the pattern has ('GMT+00:00' from cs's '+H:mm') }
  if Short then
    Hour := LocalizeDigits(IntToStr(Hours), Digits)
  else
    Hour := LocalizeDigits(Pad(Hours, 2), Digits);
  if Copy(Part, H, 2) = 'HH' then
    Part := Copy(Part, 1, H - 1) + Hour + Copy(Part, H + 2, MaxInt)
  else
    Part := Copy(Part, 1, H - 1) + Hour + Copy(Part, H + 1, MaxInt);
  Part := StringReplace(Part, 'mm', LocalizeDigits(Pad(Minutes, 2), Digits), []);
  Result := PercentS(Need(Locale.Data, 'zone_formats').Str('gmt'), Part);
end;

{ GetTimezoneGmt: Width 'long' is CLDR's localized GMT ('GMT-05:00',
  'GMT+00:00' for UTC), 'localized_short' its short form ('GMT-5');
  'short' ('-0500'), 'iso8601' ('-05:00') and 'iso8601_short' ('-05') are
  ISO 8601 forms. }
function GmtText(OffsetSeconds: Integer; const Width: string; const Locale: TLocale;
  ReturnZ: Boolean; const Digits: TCodePoints = nil): string;
var
  Sign: string;
  Hours, Minutes: Integer;
begin
  if ReturnZ and (OffsetSeconds = 0) then
    Exit('Z');
  if Width = 'long' then
    Exit(LocalizedGmt(OffsetSeconds, Locale, False, Digits));
  if Width = 'localized_short' then
    Exit(LocalizedGmt(OffsetSeconds, Locale, True, Digits));
  if OffsetSeconds < 0 then Sign := '-' else Sign := '+';
  Hours := System.Abs(OffsetSeconds) div 3600;
  Minutes := (System.Abs(OffsetSeconds) mod 3600) div 60;
  if (Minutes = 0) and (Width = 'iso8601_short') then
    Exit(Sign + Pad(Hours, 2));
  if (Width = 'short') or (Width = 'iso8601_short') then
    Exit(Sign + Pad(Hours, 2) + Pad(Minutes, 2));
  Result := Sign + Pad(Hours, 2) + ':' + Pad(Minutes, 2);
end;

function GetTimezoneGmt(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Width: string; ReturnZ: Boolean): string;
begin
  Result := GmtText(GetTimeZone(TimeZone).InfoAt(UTC).UTCOffset, Width, Locale, ReturnZ);
end;

function CanonicalZone(const Zone: string): string;
begin
  Result := GetGlobal('zone_aliases').Str(Zone, Zone);
end;

{ The ids a zone may be found under in CLDR's tables: the name given,
  its canonical IANA name, and the other names that are aliases of it
  (CLDR keeps names and metazones under older ids such as Asia/Calcutta
  for Asia/Kolkata). }
function ZoneIds(const Zone: string): TStringArray;
var
  Canon: string;
  Aliases: TCLDRValue;
  I: Integer;

  procedure Add(const S: string);
  var
    X: string;
  begin
    for X in Result do
      if X = S then
        Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := S;
  end;

begin
  Result := nil;
  Add(Zone);
  Canon := CanonicalZone(Zone);
  Add(Canon);
  Aliases := GetGlobal('zone_aliases');
  for I := 0 to Aliases.Count - 1 do
    if Aliases.Items(I).AsString = Canon then
      Add(Aliases.Keys(I).AsString);
end;

{ The first entry of Map under one of the zone's ids; nil if none. }
function ByZone(Map: TCLDRValue; const Zone: string): TCLDRValue;
var
  Id: string;
begin
  Result := nil;
  if Map = nil then
    Exit;
  for Id in ZoneIds(Zone) do
  begin
    Result := Map.Get(Id);
    if Result <> nil then
      Exit;
  end;
end;

function MetazoneOf(const Zone: string): string;
var
  V: TCLDRValue;
begin
  V := ByZone(GetGlobal('meta_zones'), Zone);
  if V = nil then
    Result := ''
  else
    Result := V.AsString;
end;

function TerritoryOf(const Zone: string): string;
var
  V: TCLDRValue;
begin
  V := ByZone(GetGlobal('zone_territories'), Zone);
  if V = nil then
    Result := ''
  else
    Result := V.AsString;
end;

{ A name of the zone's tables (width 'long' or 'short', variant
  'generic', 'standard' or 'daylight'); '' when absent or ∅∅∅ (CLDR's
  "no value"). }
function NameIn(Info: TCLDRValue; const Width, Variant: string): string;
begin
  Result := '';
  if Info <> nil then
    Result := Info.Path([Width]).Str(Variant, '');
  if Result = NoInheritanceMarker then
    Result := '';
end;

{ The zone's exemplar city: the locale's, else the last part of the id
  ('Los Angeles'). Unknown (the VVV field, as ICU): for an id that names
  no place (Etc/UTC, Etc/GMT+5, EST5EDT), the name of the unknown city
  ('Unknown Location') instead of the id's last part. }
function ExemplarCity(const Zone: string; const Locale: TLocale; Unknown: Boolean = False): string;
var
  Info, MetaInfo: TCLDRValue;
  Canon: string;
begin
  Info := ByZone(Locale.TimeZones, Zone);
  if (Info <> nil) and Info.Has('city') then
    Exit(Info.Str('city'));
  MetaInfo := Locale.MetaZones.Get(MetazoneOf(Zone));
  if (MetaInfo <> nil) and MetaInfo.Has('city') then
    Exit(MetaInfo.Str('city'));
  Canon := CanonicalZone(Zone);
  if Unknown and ((Pos('/', Canon) = 0) or (Copy(Canon, 1, 4) = 'Etc/') or (Copy(Canon, 1, 8) = 'SystemV/')) then
  begin
    Info := Locale.TimeZones.Get('Etc/Unknown');
    if (Info <> nil) and Info.Has('city') then
      Exit(Info.Str('city'));
    Exit('Unknown');
  end;
  if Pos('/', Canon) > 0 then
    Result := StringReplace(Copy(Canon, LastDelimiter('/', Canon) + 1, MaxInt), '_', ' ', [rfReplaceAll])
  else
    Result := StringReplace(Canon, '_', ' ', [rfReplaceAll]);
end;

{ The country of a zone when it stands for the whole country: the only
  zone of its country, or the country's primary zone (Europe/Madrid for
  Spain); '' otherwise. }
function CountryNameFor(const Zone: string; const Locale: TLocale; out Territory: string): string;
var
  Zones: TCLDRValue;
begin
  Result := '';
  Territory := TerritoryOf(Zone);
  if (Territory = '') or (Territory = '001') or (Territory = 'ZZ') then
    Exit;
  Zones := GetGlobal('territory_zones').Get(Territory);
  if ((Zones <> nil) and (Zones.Count = 1)) or
     (GetGlobal('primary_zones').Str(Territory, '') = CanonicalZone(Zone)) then
    Result := Locale.Territories.Str(Territory, '');
end;

{ CLDR's generic location format ('Spain Time', 'Los Angeles Time'); ''
  for a zone of no country (UTC, Etc/GMT+5). }
function GenericLocation(const Zone: string; const Locale: TLocale): string;
var
  Territory, Country: string;
begin
  Country := CountryNameFor(Zone, Locale, Territory);
  if (Territory = '') or (Territory = '001') or (Territory = 'ZZ') then
    Exit('');
  if Country <> '' then
    Result := PercentS(Need(Locale.Data, 'zone_formats').Str('region'), Country)
  else
    Result := PercentS(Need(Locale.Data, 'zone_formats').Str('region'), ExemplarCity(Zone, Locale));
end;

{ The zone's offsets at an instant in tzdata's rearguard form, which ICU
  and CLDR's names follow: the system's (vanguard) data gives
  Europe/Dublin a negative daylight saving time in winter (Irish Standard
  Time is then the summer's standard time) and Africa/Casablanca one
  during Ramadan; in the rearguard form those periods are standard time
  and the rest of the year is daylight time. }
function NameInfoAt(const Zone: string; UTCSeconds: Int64): TZoneInfo;
var
  Z: TTimeZone;
  Other: TZoneInfo;
  K: Integer;
begin
  Z := GetTimeZone(Zone);
  Result := Z.InfoAt(UTCSeconds);
  if Result.DSTOffset < 0 then
    Result.DSTOffset := 0
  else if Result.DSTOffset = 0 then
    for K := -53 to 53 do
    begin
      Other := Z.InfoAt(UTCSeconds + Int64(K) * 7 * 86400);
      if Other.DSTOffset < 0 then
      begin
        Result.DSTOffset := -Other.DSTOffset;
        Break;
      end;
    end;
end;

{ Whether the zone has daylight saving time within 184 days of an
  instant (ICU's check before it uses the standard name as the generic
  one), sampled daily. }
function DstNear(const Zone: string; UTCSeconds: Int64): Boolean;
var
  Z: TTimeZone;
  K: Integer;
begin
  Z := GetTimeZone(Zone);
  for K := -184 to 184 do
    if Z.InfoAt(UTCSeconds + Int64(K) * 86400).DSTOffset <> 0 then
      Exit(True);
  Result := False;
end;

{ CLDR's specific non-location format ('Pacific Daylight Time', 'PDT');
  '' when there is none. }
function SpecificName(const Zone, Width, Variant: string; const Locale: TLocale): string;
begin
  Result := NameIn(ByZone(Locale.TimeZones, Zone), Width, Variant);
  if Result = '' then
    Result := NameIn(Locale.MetaZones.Get(MetazoneOf(Zone)), Width, Variant);
end;

{ The region of a locale: its own, else its likely one ('en': US,
  'zh_Hant': TW); '001' when none is known. }
function LocaleRegion(const Locale: TLocale): string;
var
  Likely: string;
  Parts: TStringArray;
begin
  Result := Locale.Territory;
  if Result <> '' then
    Exit;
  Likely := '';
  if Locale.Script <> '' then
    Likely := GetGlobal('likely_subtags').Str(Locale.Language + '_' + Locale.Script, '');
  if Likely = '' then
    Likely := GetGlobal('likely_subtags').Str(Locale.Language, '');
  Parts := Likely.Split(['_']);
  if Length(Parts) >= 2 then
    Result := Parts[High(Parts)]
  else
    Result := '001';
end;

{ The reference zone of a metazone for a region (CLDR's mapZone), else
  for 001. }
function GoldenZone(const Metazone, Region: string): string;
var
  Golden: TCLDRValue;
begin
  Result := '';
  Golden := GetGlobal('metazone_golden_zones').Get(Metazone);
  if Golden <> nil then
  begin
    Result := Golden.Str(Region, '');
    if Result = '' then
      Result := Golden.Str('001', '');
  end;
end;

{ CLDR's generic non-location format ('Pacific Time'), as ICU builds it
  for an instant (TimeZoneGenericNames::formatGenericNonLocationName):
  the zone's own generic name; else, from its metazone, the standard name
  when the zone has no daylight time within 184 days ('India Standard
  Time') and that name differs from the generic one; else the metazone's
  generic name, with the location ('Pacific Time (Vancouver)': the
  country when the zone is its country's reference zone, else the city)
  when the zone's offsets differ from those of the metazone's reference
  zone for the locale's region. '' when there is no name. }
function GenericName(const Zone, Width: string; HasDate: Boolean; UTCSeconds: Int64;
  const Locale: TLocale): string;
var
  MetaInfo: TCLDRValue;
  Metazone, Standard, Golden, Territory, Location: string;
  ZI, GI: TZoneInfo;
begin
  Result := NameIn(ByZone(Locale.TimeZones, Zone), Width, 'generic');
  if Result <> '' then
    Exit;
  Metazone := MetazoneOf(Zone);
  if Metazone = '' then
    Exit;
  MetaInfo := Locale.MetaZones.Get(Metazone);
  if HasDate then
    ZI := NameInfoAt(Zone, UTCSeconds);
  if HasDate and (ZI.DSTOffset = 0) and not DstNear(Zone, UTCSeconds) then
  begin
    Standard := SpecificName(Zone, Width, 'standard', Locale);
    { ICU compares ignoring case; the names that match are identical }
    if (Standard <> '') and (Standard <> NameIn(MetaInfo, Width, 'generic')) then
      Exit(Standard);
  end;
  Result := NameIn(MetaInfo, Width, 'generic');
  if (Result = '') or not HasDate then
    Exit;
  Golden := GoldenZone(Metazone, LocaleRegion(Locale));
  if (Golden = '') or (CanonicalZone(Golden) = CanonicalZone(Zone)) then
    Exit;
  GI := NameInfoAt(Golden, UTCSeconds);
  if (ZI.UTCOffset = GI.UTCOffset) and (ZI.DSTOffset = GI.DSTOffset) then
    Exit;
  Territory := TerritoryOf(Zone);
  if (Territory <> '') and (Territory <> '001') and (Territory <> 'ZZ') and
     (CanonicalZone(GetGlobal('metazone_golden_zones').Path([Metazone]).Str(Territory, '')) = CanonicalZone(Zone)) then
    Location := Locale.Territories.Str(Territory, Territory)
  else
    Location := ExemplarCity(Zone, Locale);
  Result := PercentNamed(Need(Locale.Data, 'zone_formats').Str('fallback'), Location, Result);
end;

function GetTimezoneLocation(const TimeZone: string; const Locale: TLocale; ReturnCity: Boolean): string;
var
  Zone: string;
begin
  Zone := TimeZone;
  if Zone = '' then
    Zone := 'UTC';
  if ReturnCity then
    Exit(ExemplarCity(Zone, Locale));
  Result := GenericLocation(Zone, Locale);
  if Result = '' then
    Result := LocalizedGmt(0, Locale, False, nil);
end;

{ The zone's name; HasDate: a datetime was given (its DST and offset). }
function TimezoneNameOf(const TimeZone: string; HasDate: Boolean; DSTOffset, UTCOffset: Integer;
  UTCSeconds: Int64; const Locale: TLocale; const Options: TTimeZoneNameOptions;
  const Digits: TCodePoints = nil): string;
var
  Zone, Variant, Width: string;
begin
  Variant := Options.ZoneVariant;
  Width := Options.Width;
  if Variant = '' then
  begin
    if not HasDate then
      Variant := 'generic'
    else if DSTOffset <> 0 then
      Variant := 'daylight'
    else
      Variant := 'standard';
  end
  else if (Variant <> 'generic') and (Variant <> 'standard') and (Variant <> 'daylight') then
    raise EBabelValueError.Create('Invalid zone variation');
  Zone := TimeZone;
  if Zone = '' then
    Zone := 'UTC';
  if Options.ReturnZone then
    Exit(CanonicalZone(Zone));
  { the fallbacks, as ICU: a generic name falls back to the generic
    location ('Spain Time'), a specific one to the localized GMT }
  if Variant = 'generic' then
    Result := GenericName(Zone, Width, HasDate, UTCSeconds, Locale)
  else
    Result := SpecificName(Zone, Width, Variant, Locale);
  if Result <> '' then
    Exit;
  if (Variant = 'generic') or not HasDate then
    Result := GenericLocation(Zone, Locale);
  if Result = '' then
    Result := LocalizedGmt(UTCOffset, Locale, Width = 'short', Digits);
end;

function GetTimezoneName(const TimeZone: string; const Locale: TLocale): string;
begin
  Result := GetTimezoneName(TimeZone, Locale, TimeZoneNameOptions);
end;

function GetTimezoneName(const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string;
var
  Info: TZoneInfo;
  Secs: Int64;
begin
  { an unknown zone raises EUnknownTimeZoneError; the offset of the
    localized GMT fallback is the current one }
  Secs := UnixSeconds(LocalTimeToUniversal(Now));
  Info := NameInfoAt(TimeZone, Secs);
  Result := TimezoneNameOf(TimeZone, False, Info.DSTOffset, Info.UTCOffset, Secs, Locale, Options);
end;

function GetTimezoneName(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string;
var
  Info: TZoneInfo;
begin
  Info := NameInfoAt(TimeZone, UnixSeconds(UTC));
  Result := TimezoneNameOf(TimeZone, True, Info.DSTOffset, Info.UTCOffset, UnixSeconds(UTC), Locale, Options);
end;

{ ---- periods of the day ---- }

function PeriodIdAt(SecondsPastMidnight: Integer; const Locale: TLocale; const RuleType: string;
  UseAt: Boolean = True): string;
var
  Rulesets, Rules, Rule: TCLDRValue;
  I, J: Integer;
  StartOk, EndOk: Boolean;
  T: Integer;

  function Field(R: TCLDRValue; const K: string): Integer;
  begin
    Result := R.Get(K).AsInteger;
  end;

begin
  T := SecondsPastMidnight;
  if RuleType = '' then
    Rulesets := Locale.DayPeriodRules.GetNone
  else
    Rulesets := Locale.DayPeriodRules.Get(RuleType);
  if Rulesets <> nil then
  begin
    for I := 0 to Rulesets.Count - 1 do
    begin
      Rules := Rulesets.Items(I);
      for J := 0 to Rules.Count - 1 do
      begin
        Rule := Rules.Items(J);
        if UseAt and Rule.Has('at') and (Field(Rule, 'at') = T) then
          Exit(Rulesets.Keys(I).AsString);
      end;
    end;
    for I := 0 to Rulesets.Count - 1 do
    begin
      Rules := Rulesets.Items(I);
      for J := 0 to Rules.Count - 1 do
      begin
        Rule := Rules.Items(J);
        if Rule.Has('from') and Rule.Has('before') then
        begin
          if Field(Rule, 'from') < Field(Rule, 'before') then
          begin
            if (Field(Rule, 'from') <= T) and (T < Field(Rule, 'before')) then
              Exit(Rulesets.Keys(I).AsString);
          end
          else if ((Field(Rule, 'from') <= T) and (T < 86400)) or ((0 <= T) and (T < Field(Rule, 'before'))) then
            Exit(Rulesets.Keys(I).AsString);
        end;
        StartOk := Rule.Has('from') and (T >= Field(Rule, 'from'));
        EndOk := (Rule.Has('to') and (T <= Field(Rule, 'to'))) or
                 (Rule.Has('before') and (T < Field(Rule, 'before')));
        if Rule.Has('after') then
          raise EBabelNotImplementedError.Create('''after'' is deprecated as of CLDR 29.');
        if StartOk and EndOk then
          Exit(Rulesets.Keys(I).AsString);
      end;
    end;
  end;
  if T < 43200 then
    Result := 'am'
  else
    Result := 'pm';
end;

function GetPeriodId(UTC: TDateTime; const Locale: TLocale; const RuleType, TimeZone: string): string;
var
  V: TValue;
begin
  V := DateTimeValue(UTC, TimeZone);
  Result := PeriodIdAt(V.H * 3600 + V.N * 60 + V.S, Locale, RuleType);
end;

{ ---- fields ---- }

procedure NeedDate(const V: TValue; F: Char);
begin
  if V.Kind = vkTime then
    raise EBabelTypeError.CreateFmt('a time has no ''%s'' field', [F]);
end;

procedure NeedTime(const V: TValue; F: Char);
begin
  if V.Kind = vkDate then
    raise EBabelTypeError.CreateFmt('a date has no ''%s'' field', [F]);
end;

function WeekNumber(const V: TValue; const Locale: TLocale; DayOfPeriod, DayOfWeek: Integer): Integer;
var
  FirstDay: Integer;
begin
  FirstDay := (DayOfWeek - Locale.FirstWeekDay - DayOfPeriod + 1) mod 7;
  if FirstDay < 0 then
    Inc(FirstDay, 7);
  Result := (DayOfPeriod + FirstDay - 1) div 7;
  if 7 - FirstDay >= Locale.MinWeekDays then
    Inc(Result);
end;

function WeekOfYear(const V: TValue; const Locale: TLocale): Integer;
var
  Wd: Integer;
begin
  Result := WeekNumber(V, Locale, DayOfYear(V.Y, V.M, V.D), Weekday(V.Y, V.M, V.D));
  if Result = 0 then
    Result := WeekNumber(V, Locale, DayOfYear(V.Y - 1, 12, 31), Weekday(V.Y - 1, 12, 31))
  else if Result > 52 then
  begin
    Wd := Weekday(V.Y + 1, 1, 1);
    if (WeekNumber(V, Locale, 1, Wd) = 1) and
       (32 - (((Wd - Locale.FirstWeekDay) mod 7 + 7) mod 7) <= V.D) then
      Result := 1;
  end;
end;

function WidthName(Num: Integer; const Six: string = ''): string;
begin
  case Num of
    3: Result := 'abbreviated';
    4: Result := 'wide';
    5: Result := 'narrow';
    6: Result := Six;
  else
    raise EBabelKeyError.Create(IntToStr(Num));
  end;
end;

{ The zone fields, as ICU formats them: z the specific name ('PDT',
  'Pacific Daylight Time'), v the generic one ('PT', 'Pacific Time'), both
  falling back to the localized GMT; O the localized GMT; V the BCP 47 id
  ('usnyc'), the IANA id, the exemplar city or the generic location;
  Z, x and X the ISO offsets (ZZZZ: the localized GMT). }
function FormatTimezoneField(const V: TValue; F: Char; Num: Integer; const Locale: TLocale): string;
var
  Width: string;
  Info: TZoneInfo;
  O: TTimeZoneNameOptions;
  UTCSeconds: Int64;
  Bcp: TCLDRValue;
begin
  NeedTime(V, F);
  if Num <= 3 then Width := 'short'
  else if Num = 4 then Width := 'long'
  else Width := 'iso8601';
  Info := ZoneInfoOf(V);
  UTCSeconds := LocalSeconds(V) - Info.UTCOffset;
  Info := NameInfoAt(V.ZoneName, UTCSeconds);
  O := TimeZoneNameOptions.WithWidth(Width);
  case F of
    'z':
      begin
        if Num > 4 then
          O := O.WithWidth('long');
        Result := TimezoneNameOf(V.ZoneName, True, Info.DSTOffset, Info.UTCOffset, UTCSeconds,
          Locale, O, V.Digits);
      end;
    'Z':
      if Num = 5 then
        Result := GmtText(Info.UTCOffset, Width, Locale, True)
      else
        Result := GmtText(Info.UTCOffset, Width, Locale, False, V.Digits);
    'O':
      Result := LocalizedGmt(Info.UTCOffset, Locale, Num < 4, V.Digits);
    'v':
      begin
        if Num <> 4 then
          O := O.WithWidth('short');
        Result := TimezoneNameOf(V.ZoneName, True, Info.DSTOffset, Info.UTCOffset, UTCSeconds,
          Locale, O.WithZoneVariant('generic'), V.Digits);
      end;
    'V':
      case Num of
        1:
          begin
            Bcp := ByZone(GetGlobal('zone_bcp47'), V.ZoneName);
            if Bcp = nil then
              Result := 'unk'
            else
              Result := Bcp.AsString;
          end;
        2: Result := V.ZoneName;          { the id as given, as ICU }
        3: Result := ExemplarCity(V.ZoneName, Locale, True);
      else
        Result := GenericLocation(V.ZoneName, Locale);
        if Result = '' then
          Result := LocalizedGmt(Info.UTCOffset, Locale, False, V.Digits);
      end;
  else
    { X and x }
    case Num of
      1: Width := 'iso8601_short';
      2, 4: Width := 'short';
    else
      Width := 'iso8601';
    end;
    Result := GmtText(Info.UTCOffset, Width, Locale, F = 'X');
  end;
end;

{ The name of a day period in the format context: the width asked for,
  else the abbreviated one, which CLDR's root aliases the narrow and wide
  names to ('nachm.' for BBBBB in de, 'po południu' for BBBB in pl).
  '' when absent. }
function PeriodName(const Locale: TLocale; const Width, Period: string): string;
var
  Names: TCLDRValue;
begin
  Names := GetPeriodNames(Locale, Width, 'format');
  if Names.Has(Period) then
    Exit(Names.Str(Period));
  Names := GetPeriodNames(Locale, 'abbreviated', 'format');
  if Names.Has(Period) then
    Exit(Names.Str(Period));
  Result := '';
end;

{ a, b and B as ICU formats them. b and B: noon only when the time shown
  is 12:00 exactly (the minutes and seconds the pattern shows are zero)
  and the locale has it; midnight is not used (ICU suppresses it: it
  could be the start or the end of the day); B is otherwise the day
  period of the time. A missing name falls back to the day period, then
  to AM/PM. }
function FormatPeriodField(const V: TValue; F: Char; Num: Integer; const Locale: TLocale): string;
var
  Width, AmPm: string;
begin
  NeedTime(V, F);
  if Num < 3 then Width := WidthName(3) else Width := WidthName(Num);
  if V.H >= 12 then AmPm := 'pm' else AmPm := 'am';
  Result := '';
  if (F <> 'a') and (V.H = 12) and (not V.HasMinute or (V.N = 0)) and (not V.HasSecond or (V.S = 0)) and
     (PeriodIdAt(12 * 3600, Locale, '') = 'noon') then
    Result := PeriodName(Locale, Width, 'noon');
  if (Result = '') and (F = 'B') then
    Result := PeriodName(Locale, Width, PeriodIdAt(V.H * 3600 + V.N * 60 + V.S, Locale, '', False));
  if Result = '' then
    Result := PeriodName(Locale, Width, AmPm);
  if Result = '' then
    raise EBabelValueError.CreateFmt('Could not format period %s in %s', [AmPm, Locale.ToString]);
end;

function FormatField(const V: TValue; F: Char; Num: Integer; const Locale: TLocale): string;
var
  Value, Q, Week, Wd: Integer;
  Width, Context: string;
begin
  case F of
    'G':
      begin
        NeedDate(V, F);
        if Num < 3 then Width := WidthName(3) else Width := WidthName(Num);
        Result := NeedInt(GetEraNames(Locale, Width), Ord(V.Y >= 0)).AsString;
      end;
    'y', 'Y', 'u':
      begin
        NeedDate(V, F);
        Value := V.Y;
        if F = 'Y' then
        begin
          if (V.M = 1) and (V.D < 7) and (WeekOfYear(V, Locale) >= 52) then
            Dec(Value)
          else if (V.M = 12) and (V.D > 25) and (WeekOfYear(V, Locale) <= 2) then
            Inc(Value);
        end;
        Result := Pad(Value, Num);
        if Num = 2 then
          Result := Copy(Result, Length(Result) - 1, 2);
      end;
    'Q', 'q':
      begin
        NeedDate(V, F);
        Q := (V.M - 1) div 3 + 1;
        if Num <= 2 then
          Exit(Pad(Q, Num));
        if F = 'Q' then Context := 'format' else Context := 'stand-alone';
        Result := NeedInt(GetQuarterNames(Locale, WidthName(Num), Context), Q).AsString;
      end;
    'M', 'L':
      begin
        NeedDate(V, F);
        if Num <= 2 then
          Exit(Pad(V.M, Num));
        if F = 'M' then Context := 'format' else Context := 'stand-alone';
        Result := NeedInt(GetMonthNames(Locale, WidthName(Num), Context), V.M).AsString;
      end;
    'w':
      begin
        NeedDate(V, F);
        Result := Pad(WeekOfYear(V, Locale), Num);
      end;
    'W':
      begin
        NeedDate(V, F);
        Week := WeekNumber(V, Locale, V.D, Weekday(V.Y, V.M, V.D));
        Result := IntToStr(Week);
      end;
    'd': begin NeedDate(V, F); Result := Pad(V.D, Num); end;
    'D': begin NeedDate(V, F); Result := Pad(DayOfYear(V.Y, V.M, V.D), Num); end;
    'F': begin NeedDate(V, F); Result := IntToStr((V.D - 1) div 7 + 1); end;
    'E', 'e', 'c':
      begin
        NeedDate(V, F);
        Wd := Weekday(V.Y, V.M, V.D);
        if Num < 3 then
        begin
          if F in ['e', 'c'] then
          begin
            Value := 7 - Locale.FirstWeekDay + Wd;
            Exit(Pad(Value mod 7 + 1, Num));
          end;
          Num := 3;
        end;
        if F = 'c' then Context := 'stand-alone' else Context := 'format';
        Result := NeedInt(GetDayNames(Locale, WidthName(Num, 'short'), Context), Wd).AsString;
      end;
    'a', 'b', 'B': Result := FormatPeriodField(V, F, Num, Locale);
    'h':
      begin
        NeedTime(V, F);
        if V.H mod 12 = 0 then Result := Pad(12, Num) else Result := Pad(V.H mod 12, Num);
      end;
    'H': begin NeedTime(V, F); Result := Pad(V.H, Num); end;
    'K': begin NeedTime(V, F); Result := Pad(V.H mod 12, Num); end;
    'k':
      begin
        NeedTime(V, F);
        if V.H = 0 then Result := Pad(24, Num) else Result := Pad(V.H, Num);
      end;
    'm': begin NeedTime(V, F); Result := Pad(V.N, Num); end;
    's': begin NeedTime(V, F); Result := Pad(V.S, Num); end;
    'S':
      begin
        { the first Num digits of the fraction, truncated (CLDR: 290 ms
          is '29' for SS) }
        NeedTime(V, F);
        Result := Copy(Pad(V.Micro, 6) + StringOfChar('0', Max(0, Num - 6)), 1, Num);
      end;
    'A':
      begin
        NeedTime(V, F);
        Result := Pad(V.Micro div 1000 + V.S * 1000 + V.N * 60000 + Int64(V.H) * 3600000, Num);
      end;
    'z', 'Z', 'v', 'V', 'x', 'X', 'O': Result := FormatTimezoneField(V, F, Num, Locale);
  else
    raise EBabelKeyError.CreateFmt('Unsupported date/time field ''%s''', [F]);
  end;
end;

function ApplyPattern(const P: TDateTimePattern; const Value: TValue; const Locale: TLocale): string;
var
  T: TPatternToken;
  V: TValue;
begin
  V := Value;
  V.HasMinute := False;
  V.HasSecond := False;
  for T in P.Tokens do
    if T.Kind = ptField then
    begin
      if T.Field = 'm' then V.HasMinute := True;
      if T.Field = 's' then V.HasSecond := True;
    end;
  Result := '';
  for T in P.Tokens do
    if T.Kind = ptChars then
      Result := Result + T.Text
    else if (V.Digits = nil) or (T.Field in ['z', 'Z', 'v', 'V', 'x', 'X', 'O']) then
      Result := Result + FormatField(V, T.Field, T.Count, Locale)
    else
      { the names have no ASCII digits: only the numbers change }
      Result := Result + LocalizeDigits(FormatField(V, T.Field, T.Count, Locale), V.Digits);
end;

{ ---- formatting ---- }

function FormatDateValue(const V: TValue; const Locale: TLocale; const Format: string): string;
var
  Fmt: string;
  D: TValue;
begin
  D := V;
  D.Kind := vkDate;
  Fmt := Format;
  if IsPredefined(Fmt) then
    Fmt := GetDateFormat(Locale, Fmt);
  Result := ApplyPattern(ParseDatePattern(Fmt), D, Locale);
end;

{ FormatTime of a datetime value in a zone: a time with the value's date
  as reference }
function FormatTimeValue(const V: TValue; const Locale: TLocale; const Format: string;
  RefY, RefM, RefD: Integer): string;
var
  Fmt: string;
  T: TValue;
begin
  T := V;
  T.Kind := vkTime;
  T.HasRef := True;
  T.RefY := RefY; T.RefM := RefM; T.RefD := RefD;
  Fmt := Format;
  if IsPredefined(Fmt) then
    Fmt := GetTimeFormat(Locale, Fmt);
  Result := ApplyPattern(ParseDatePattern(Fmt), T, Locale);
end;

function FormatDate(Date: TDateTime; const Locale: TLocale; const Format: string): string;
begin
  Result := FormatDateValue(DateValue(Date), Locale, Format);
end;

function FormatDate(Date: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string;
var
  V: TValue;
begin
  V := DateValue(Date);
  V.Digits := SystemDigits(Locale, Options.NumberingSystem);
  Result := FormatDateValue(V, Locale, Options.Format);
end;

function FormatTime(UTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatTime(UTC, Locale, DateTimeOptions);
end;

function FormatTime(UTC: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string;
var
  V: TValue;
begin
  { the zone fields use the local date of the time (near midnight the
    UTC date can have another offset or name) }
  V := DateTimeValue(UTC, Options.TimeZone);
  V.Digits := SystemDigits(Locale, Options.NumberingSystem);
  Result := FormatTimeValue(V, Locale, Options.Format, V.Y, V.M, V.D);
end;

(* The date-time combination pattern ('{1}, {0}', "{1} 'at' {0}") with
  the time and the date put in: quoted text is literal ('' is a quote). *)
function CombineDateTime(const Pattern, Time, Date: string): string;
var
  I: Integer;
  Quoted: Boolean;
begin
  Result := '';
  Quoted := False;
  I := 1;
  while I <= Length(Pattern) do
  begin
    if Pattern[I] = '''' then
    begin
      if (I < Length(Pattern)) and (Pattern[I + 1] = '''') then
      begin
        Result := Result + '''';
        Inc(I, 2);
        Continue;
      end;
      Quoted := not Quoted;
      Inc(I);
      Continue;
    end;
    if not Quoted and (Copy(Pattern, I, 3) = '{0}') then
    begin
      Result := Result + Time;
      Inc(I, 3);
    end
    else if not Quoted and (Copy(Pattern, I, 3) = '{1}') then
    begin
      Result := Result + Date;
      Inc(I, 3);
    end
    else
    begin
      Result := Result + Pattern[I];
      Inc(I);
    end;
  end;
end;

{ The pattern that combines a date of length Format with a time: CLDR's
  atTime variant when the locale has one, as ICU uses it ('Tuesday,
  October 13, 2026 at 9:30 AM'; '13/10/2026, 09:30' in pt_BR), else the
  standard one. }
function DateTimeCombination(const Locale: TLocale; const Format: string): string;
var
  AtTime: TCLDRValue;
begin
  AtTime := Locale.Data.Path(['datetime_formats_at_time', Format]);
  if AtTime <> nil then
    Exit(AtTime.AsString);
  Result := GetDatetimeFormat(Locale, Format);
end;

function FormatDateTimeValue(const V: TValue; const Locale: TLocale; const Format: string): string;
begin
  if IsPredefined(Format) then
    Result := CombineDateTime(DateTimeCombination(Locale, Format),
      FormatTimeValue(V, Locale, Format, V.Y, V.M, V.D), FormatDateValue(V, Locale, Format))
  else
    Result := ApplyPattern(ParseDatePattern(Format), V, Locale);
end;

function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatDateAndTime(UTC, Locale, DateTimeOptions);
end;

function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string;
var
  V: TValue;
begin
  V := DateTimeValue(UTC, Options.TimeZone);
  V.Digits := SystemDigits(Locale, Options.NumberingSystem);
  Result := FormatDateTimeValue(V, Locale, Options.Format);
end;

function SkeletonKeys(M: TCLDRValue): TStringArray;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to M.Count - 1 do
    if M.Keys(I).Kind = ckString then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := M.Keys(I).AsString;
    end;
end;

{ The locale's hour cycles from CLDR's timeData: Preferred ('h', 'H')
  and the first allowed form ('hB', 'h', 'H', ...), looked up by
  language_REGION, then REGION (the locale's, or its likely one), then
  001. }
procedure HourCycle(const Locale: TLocale; out Preferred, Allowed: string);
var
  Region: string;
  Data, Entry: TCLDRValue;
  Parts: TStringArray;
begin
  Region := LocaleRegion(Locale);
  Data := GetGlobal('time_data');
  Entry := Data.Get(Locale.Language + '_' + Region);
  if Entry = nil then
    Entry := Data.Get(Region);
  if Entry = nil then
    Entry := Data.Get('001');
  Preferred := Entry.Str('preferred', 'H');
  Allowed := Entry.Str('allowed', Preferred);
  Parts := Allowed.Split([' ']);
  Allowed := Parts[0];
end;

{ A skeleton with CLDR's hour-cycle characters replaced: j (the locale's
  preferred hour), J (the same without a day period), C (the first
  allowed hour form, with its flexible day period: hB gives h and B). }
function ExpandHourChars(const Skeleton: string; const Locale: TLocale): string;
var
  I, N: Integer;
  C: Char;
  Preferred, Allowed, Hour, Period: string;
begin
  if (Pos('j', Skeleton) = 0) and (Pos('J', Skeleton) = 0) and (Pos('C', Skeleton) = 0) then
    Exit(Skeleton);
  HourCycle(Locale, Preferred, Allowed);
  Result := '';
  I := 1;
  while I <= Length(Skeleton) do
  begin
    C := Skeleton[I];
    if C in ['j', 'J', 'C'] then
    begin
      N := 0;
      while (I <= Length(Skeleton)) and (Skeleton[I] = C) do
      begin
        Inc(N);
        Inc(I);
      end;
      if C = 'C' then
      begin
        Hour := Copy(Allowed, 1, 1);
        Period := Copy(Allowed, 2, 1);
      end
      else
      begin
        Hour := Preferred;
        Period := '';
      end;
      Result := Result + StringOfChar(Hour[1], Min(N, 2));
      if Period <> '' then
      begin
        if N <= 2 then Result := Result + Period
        else if N <= 4 then Result := Result + StringOfChar(Period[1], 4)
        else Result := Result + StringOfChar(Period[1], 5);
      end;
    end
    else
    begin
      Result := Result + C;
      Inc(I);
    end;
  end;
end;

{ The kind of field of a pattern letter (ICU's field types): letters of
  the same kind are variants of one field (M and L, E e and c). }
function FieldKind(C: Char): Char;
begin
  case C of
    'y', 'Y', 'u', 'U', 'r': Result := 'y';
    'Q', 'q': Result := 'Q';
    'M', 'L': Result := 'M';
    'E', 'e', 'c': Result := 'E';
    'd', 'g': Result := 'd';
    'a', 'b', 'B': Result := 'a';
    'H', 'h', 'K', 'k': Result := 'H';
    's', 'A': Result := 's';
    'z', 'Z', 'O', 'v', 'V', 'X', 'x': Result := 'z';
  else
    Result := C;
  end;
end;

{ Whether a field of that letter and length is a number (M, MM) rather
  than text (MMM). }
function IsNumericField(C: Char; Len: Integer): Boolean;
begin
  case C of
    'Q', 'q', 'M', 'L', 'e', 'c': Result := Len <= 2;
    'G', 'E', 'a', 'b', 'B', 'U', 'z', 'Z', 'O', 'v', 'V', 'X', 'x': Result := False;
  else
    Result := True;
  end;
end;

{ The letter and length of the field of Kind in a skeleton; Len 0 when
  absent. }
procedure SkeletonField(const Skeleton: string; Kind: Char; out C: Char; out Len: Integer);
var
  I: Integer;
begin
  Len := 0;
  C := #0;
  for I := 1 to Length(Skeleton) do
    if FieldKind(Skeleton[I]) = Kind then
    begin
      if Len = 0 then
        C := Skeleton[I];
      if Skeleton[I] = C then
        Inc(Len);
    end;
end;

{ A skeleton as ICU's pattern generator reads it: a 12-hour skeleton
  without a day period gets 'a' ('hm' is 'ahm': the pattern's B becomes
  a, as in zh_Hant); a 24-hour one loses its day period. }
function WithDayPeriod(const Skeleton: string): string;
var
  I: Integer;
  Has12, HasPeriod: Boolean;
begin
  Has12 := (Pos('h', Skeleton) > 0) or (Pos('K', Skeleton) > 0);
  HasPeriod := (Pos('a', Skeleton) > 0) or (Pos('b', Skeleton) > 0) or (Pos('B', Skeleton) > 0);
  if Has12 then
  begin
    if HasPeriod then
      Result := Skeleton
    else
      Result := Skeleton + 'a';
  end
  else if (Pos('H', Skeleton) > 0) or (Pos('k', Skeleton) > 0) then
  begin
    Result := '';
    for I := 1 to Length(Skeleton) do
      if not (Skeleton[I] in ['a', 'b', 'B']) then
        Result := Result + Skeleton[I];
  end
  else
    Result := Skeleton;
end;

{ The pattern of the Matched skeleton with its field lengths adjusted to
  the Requested skeleton, as ICU's DateTimePatternGenerator does
  (adjustFieldTypes): 'MMM d, y' for yMMMd gives 'MMMM d, y' for yMMMMd.
  Hours, minutes and seconds keep their length; a field keeps it too when
  the matched skeleton already has the requested length, or when one of
  the pattern and the skeleton has it as a number and the other as text. }
function AdjustFieldLengths(const Pattern, Requested, Matched: string): TDateTimePattern;
var
  Req, Mat: string;
  Tokens: TPatternTokens;
  I, ReqLen, SkelLen, AdjLen: Integer;
  Kind, ReqChar, SkelChar, C: Char;
begin
  Req := WithDayPeriod(Requested);
  Mat := WithDayPeriod(Matched);
  Result := ParseDatePattern(Pattern);
  Tokens := Result.Tokens;
  for I := 0 to High(Tokens) do
  begin
    if Tokens[I].Kind <> ptField then
      Continue;
    Kind := FieldKind(Tokens[I].Field);
    SkeletonField(Req, Kind, ReqChar, ReqLen);
    if (ReqLen = 0) or (Kind in ['H', 'm', 's']) then
      Continue;
    if (ReqChar = 'E') and (ReqLen < 3) then
      ReqLen := 3;
    AdjLen := ReqLen;
    if not (ReqChar in ['c', 'e']) then
    begin
      SkeletonField(Mat, Kind, SkelChar, SkelLen);
      if (SkelLen = ReqLen) or
         (IsNumericField(Tokens[I].Field, Tokens[I].Count) <> IsNumericField(SkelChar, SkelLen)) then
        AdjLen := Tokens[I].Count;
    end;
    if (Kind in ['M', 'E']) or ((Kind = 'y') and (ReqChar <> 'Y')) then
      C := Tokens[I].Field
    else
      C := ReqChar;
    if (C = 'E') and (AdjLen < 3) then
      C := 'e';
    Tokens[I].Field := C;
    Tokens[I].Count := AdjLen;
  end;
  Result.Tokens := Tokens;
end;

{ The fields of a skeleton or pattern, sorted ('E4,M4,d1,y1'). The
  stand-alone letters (L, c) differ from the format ones, as in ICU. }
function FieldSet(const S: string): string;
var
  T: TPatternToken;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    for T in TokenizeDatePattern(S) do
      if T.Kind = ptField then
        L.Add(T.Field + IntToStr(T.Count));
    L.Sort;
    Result := L.DelimitedText;
  finally
    L.Free;
  end;
end;

{ The locale's standard date or time pattern with exactly the fields of
  the skeleton; '' if none. ICU's pattern generator has these patterns
  besides the available formats ('EEEE 'den' d. MMMM y' for yMMMMEEEEd
  in da). }
function StandardPatternFor(const Skeleton: string; const Locale: TLocale): string;
const
  Lengths: array[0..3] of string = ('full', 'long', 'medium', 'short');
var
  Want, L: string;
begin
  Want := FieldSet(Skeleton);
  for L in Lengths do
  begin
    Result := GetDateFormat(Locale, L);
    if FieldSet(Result) = Want then
      Exit;
    Result := GetTimeFormat(Locale, L);
    if FieldSet(Result) = Want then
      Exit;
  end;
  Result := '';
end;

function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatSkeleton(Skeleton, UTC, Locale, SkeletonOptions);
end;

function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale;
  const Options: TSkeletonOptions): string;
var
  Skeletons: TCLDRValue;
  Requested, S, Pattern: string;
  V: TValue;
begin
  Skeletons := Locale.DatetimeSkeletons;
  Requested := ExpandHourChars(Skeleton, Locale);
  V := DateTimeValue(UTC, Options.TimeZone);
  V.Digits := SystemDigits(Locale, Options.NumberingSystem);
  if Options.Fuzzy and not Skeletons.Has(Requested) then
  begin
    Pattern := StandardPatternFor(Requested, Locale);
    if Pattern <> '' then
      Exit(FormatDateTimeValue(V, Locale, Pattern));
  end;
  S := Requested;
  if Options.Fuzzy and not Skeletons.Has(S) then
    S := MatchSkeleton(S, SkeletonKeys(Skeletons));
  if (S = '') or not Skeletons.Has(S) then
    raise EBabelKeyError.Create(Skeleton);
  Result := ApplyPattern(AdjustFieldLengths(Skeletons.Str(S), Requested, S), V, Locale);
end;

{ ---- durations ---- }

function FormatTimedelta(Seconds: Int64; const Locale: TLocale): string;
begin
  Result := FormatTimedelta(Seconds, Locale, TimedeltaOptions);
end;

function FormatTimedelta(Seconds: Int64; const Locale: TLocale; const Options: TTimedeltaOptions): string;
const
  Units: array[0..6] of string = ('year', 'month', 'week', 'day', 'hour', 'minute', 'second');
  Secs: array[0..6] of Int64 = (3600 * 24 * 365, 3600 * 24 * 30, 3600 * 24 * 7, 3600 * 24, 3600, 60, 1);
var
  Fmt, PluralForm, Pattern, Direction, Field: string;
  DateFields, UnitPatterns, Rel, Pats, Aliases: TCLDRValue;
  I, K: Integer;
  Value: Double;
  IValue: Int64;
  Candidates: array of TCLDRValue;

  procedure AddCandidate(V: TCLDRValue);
  begin
    SetLength(Candidates, Length(Candidates) + 1);
    Candidates[High(Candidates)] := V;
  end;

begin
  Fmt := Options.Format;
  if (Fmt <> 'narrow') and (Fmt <> 'short') and (Fmt <> 'medium') and (Fmt <> 'long') then
    raise EBabelTypeError.Create('Format must be one of "narrow", "short" or "long"');
  if Fmt = 'medium' then
    Fmt := 'long';
  DateFields := Need(Locale.Data, 'date_fields');
  UnitPatterns := Need(Locale.Data, 'unit_patterns');
  Aliases := Locale.Data.Get('date_field_aliases');
  for I := 0 to High(Units) do
  begin
    Value := System.Abs(Seconds) / Secs[I];
    if (Value >= Options.Threshold) or (Units[I] = Options.Granularity) then
    begin
      if (Units[I] = Options.Granularity) and (Value > 0) then
        Value := Max(1, Value);
      IValue := Round(Value);     { half to even }
      PluralForm := Locale.PluralForm.Evaluate(IValue);
      Candidates := nil;
      if Options.AddDirection then
      begin
        if Seconds >= 0 then Direction := 'future' else Direction := 'past';
        { the field of the width, then the ones CLDR aliases it to
          ('second-narrow' to 'second-short' to 'second'), for each
          direction (de 'month-short' has only the past; the narrow es
          'second' is 'hace 3 s') }
        Field := Units[I] + '-' + Fmt;
        while Field <> '' do
        begin
          Rel := DateFields.Get(Field);
          if Rel <> nil then
            AddCandidate(Rel.Get(Direction));
          if Aliases <> nil then
            Field := Aliases.Str(Field, '')
          else
            Field := '';
        end;
        Rel := DateFields.Get(Units[I]);
        if Rel <> nil then
          AddCandidate(Rel.Get(Direction));
      end;
      Pats := UnitPatterns.Get('duration-' + Units[I]);
      if Pats <> nil then
      begin
        AddCandidate(Pats.Get(Fmt));
        if (Fmt = 'long') or (Fmt = 'narrow') then
          AddCandidate(Pats.Get('short'));
      end;
      Pattern := '';
      for K := 0 to High(Candidates) do
        if Candidates[K] <> nil then
        begin
          Pattern := Candidates[K].Str(PluralForm, '');
          if Pattern = '' then
            Pattern := Candidates[K].Str('other', '');
          if Pattern <> '' then
            Break;
        end;
      if Pattern = '' then
        Exit('');
      Exit(StringReplace(Pattern, '{0}', LocalizeDigits(IntToStr(IValue),
        SystemDigits(Locale, Options.NumberingSystem)), [rfReplaceAll]));
    end;
  end;
  Result := '';
end;

{ ---- intervals ---- }

{ What an interval compares for a field: whether the two ends differ in
  it. }
function Extract(const V: TValue; F: Char; const Locale: TLocale): string;
begin
  case F of
    'y': Result := IntToStr(V.Y);
    'M', 'L': Result := IntToStr(V.M);
    'd': Result := IntToStr(V.D);
    'H', 'k': Result := IntToStr(V.H);
    'h', 'K': Result := IntToStr(V.H mod 12);
    'm': Result := IntToStr(V.N);
    'a': Result := IntToStr(Ord(V.H >= 12));
    'B': Result := PeriodIdAt(V.H * 3600 + V.N * 60 + V.S, Locale, '', False);
    'b': Result := IntToStr(Ord(V.H >= 12));
  else
    Result := FormatField(V, F, 1, Locale);
  end;
end;

function FallbackInterval(StartUTC, EndUTC: TDateTime; const Skeleton: string;
  const Options: TIntervalOptions; const Locale: TLocale): string;

  function Fmt(DT: TDateTime): string;
  begin
    if (Skeleton <> '') and Locale.DatetimeSkeletons.Has(Skeleton) then
      Result := FormatSkeleton(Skeleton, DT, Locale, SkeletonOptions.WithTimeZone(Options.TimeZone)
        .WithNumberingSystem(Options.NumberingSystem))
    else if Options.Kind = ikDate then
      Result := FormatDate(DT, Locale, DateTimeOptions.WithNumberingSystem(Options.NumberingSystem))
    else if Options.Kind = ikTime then
      Result := FormatTime(DT, Locale, DateTimeOptions.WithTimeZone(Options.TimeZone)
        .WithNumberingSystem(Options.NumberingSystem))
    else
      Result := FormatDateAndTime(DT, Locale, DateTimeOptions.WithTimeZone(Options.TimeZone)
        .WithNumberingSystem(Options.NumberingSystem));
  end;

var
  FS, FE, Pattern: string;
  V: TCLDRValue;
begin
  FS := Fmt(StartUTC);
  FE := Fmt(EndUTC);
  if FS = FE then
    Exit(FS);
  V := Locale.IntervalFormats.GetNone;
  if V <> nil then
    Pattern := V.AsString
  else
    Pattern := '{0}-{1}';
  Result := StringReplace(StringReplace(Pattern, '{0}', FS, [rfReplaceAll]), '{1}', FE, [rfReplaceAll]);
end;

function FormatInterval(StartUTC, EndUTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatInterval(StartUTC, EndUTC, Locale, IntervalOptions);
end;

function FormatInterval(StartUTC, EndUTC: TDateTime; const Locale: TLocale;
  const Options: TIntervalOptions): string;
var
  Formats, Skel, Parts: TCLDRValue;
  Skeleton: string;
  SV, EV: TValue;
  F: Char;
  K: Integer;
begin
  if Options.Kind = ikDate then
  begin
    { dates: the time of day is not part of them }
    StartUTC := DateOf(StartUTC);
    EndUTC := DateOf(EndUTC);
  end;
  Formats := Locale.IntervalFormats;
  Skeleton := ExpandHourChars(Options.Skeleton, Locale);
  if (Skeleton = '') or not Formats.Has(Skeleton) then
  begin
    if (Skeleton <> '') and Options.Fuzzy then
      Skeleton := MatchSkeleton(Skeleton, SkeletonKeys(Formats))
    else
      Skeleton := '';
    if Skeleton = '' then
      Exit(FallbackInterval(StartUTC, EndUTC, '', Options, Locale));
  end;
  Skel := Formats.Get(Skeleton);
  if StartUTC = EndUTC then
    Exit(FormatSkeleton(Skeleton, StartUTC, Locale,
      SkeletonOptions.WithTimeZone(Options.TimeZone).WithFuzzy(Options.Fuzzy)
      .WithNumberingSystem(Options.NumberingSystem)));
  SV := DateTimeValue(StartUTC, Options.TimeZone);
  EV := DateTimeValue(EndUTC, Options.TimeZone);
  SV.Digits := SystemDigits(Locale, Options.NumberingSystem);
  EV.Digits := SV.Digits;
  for F in PatternCharOrder do
    if Skel.Has(F) and (Extract(SV, F, Locale) <> Extract(EV, F, Locale)) then
    begin
      Parts := Skel.Get(F);
      Result := '';
      for K := 0 to Min(Parts.Count, 2) - 1 do
        if K = 0 then
          Result := Result + ApplyPattern(ParseDatePattern(Parts.Items(K).AsString), SV, Locale)
        else
          Result := Result + ApplyPattern(ParseDatePattern(Parts.Items(K).AsString), EV, Locale);
      Exit;
    end;
  Result := FallbackInterval(StartUTC, EndUTC, Skeleton, Options, Locale);
end;

{ ---- parsing ---- }

{ The runs of decimal digits of S (any script), as re.findall(r'\d+'). }
function DigitRuns(const S: string): TStringArray;
var
  I, L, D: Integer;
  Cur: string;
  InRun: Boolean;
begin
  Result := nil;
  Cur := '';
  InRun := False;
  I := 1;
  while I <= Length(S) do
  begin
    D := DecimalDigitValue(CodePointAt(S, I, L));
    if D >= 0 then
    begin
      Cur := Cur + Chr(Ord('0') + D);
      InRun := True;
    end
    else if InRun then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Cur;
      Cur := '';
      InRun := False;
    end;
    Inc(I, L);
  end;
  if InRun then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Cur;
  end;
end;

function NumberAt(const Numbers: TStringArray; I: Integer): Int64;
begin
  if I > High(Numbers) then
    raise EBabelIndexError.Create('list index out of range');
  Result := StrToInt64(Numbers[I]);
end;

{ The order (0, 1, 2) of three positions, sorted by position, then by
  name. }
procedure OrderOf(const P: array of Double; out Order: array of Integer);
var
  I, J: Integer;
begin
  for I := 0 to 2 do
  begin
    Order[I] := 0;
    for J := 0 to 2 do
      if (P[J] < P[I]) or ((P[J] = P[I]) and (J < I)) then
        Inc(Order[I]);
  end;
end;

function IsoAlike(const S: string; out Y, M, D: Integer): Boolean;
var
  T: string;
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9', '-']) then
      Exit;
  (* ^(\d{4})-?([01]\d)-?([0-3]\d)$ *)
  T := S;
  if (Length(T) < 8) or not TryStrToInt(Copy(T, 1, 4), Y) or (Pos('-', Copy(T, 1, 4)) > 0) then
    Exit;
  Delete(T, 1, 4);
  if (T <> '') and (T[1] = '-') then Delete(T, 1, 1);
  if (Length(T) < 4) or not (T[1] in ['0', '1']) or not (T[2] in ['0'..'9']) then
    Exit;
  M := StrToInt(Copy(T, 1, 2));
  Delete(T, 1, 2);
  if (T <> '') and (T[1] = '-') then Delete(T, 1, 1);
  if (Length(T) <> 2) or not (T[1] in ['0'..'3']) or not (T[2] in ['0'..'9']) then
    Exit;
  D := StrToInt(T);
  Result := True;
end;

function ParseDate(const S: string; const Locale: TLocale; const Format: string): TDateTime;
var
  Numbers: TStringArray;
  FormatStr: string;
  YearIdx, MonthIdx, DayIdx: Integer;
  Order: array[0..2] of Integer;
  Year, Month, Day, T: Int64;
  IY, IM, ID: Integer;
begin
  Numbers := DigitRuns(S);
  if Length(Numbers) = 0 then
    raise EDateParseError.Create('No numbers were found in input');
  if IsPredefined(Format) and IsoAlike(S, IY, IM, ID) then
    if IsValidDate(IY, IM, ID) then
      Exit(EncodeDate(IY, IM, ID));
  if IsPredefined(Format) then
    FormatStr := LowerCase(GetDateFormat(Locale, Format))
  else
    FormatStr := LowerCase(ParseDatePattern(Format).Pattern);
  YearIdx := Pos('y', FormatStr) - 1;
  if YearIdx < 0 then
    raise EBabelValueError.Create('substring not found');
  MonthIdx := Pos('m', FormatStr) - 1;
  if MonthIdx < 0 then
  begin
    MonthIdx := Pos('l', FormatStr) - 1;
    if MonthIdx < 0 then
      raise EBabelValueError.Create('substring not found');
  end;
  DayIdx := Pos('d', FormatStr) - 1;
  if DayIdx < 0 then
    raise EBabelValueError.Create('substring not found');
  OrderOf([YearIdx, MonthIdx, DayIdx], Order);
  Year := NumberAt(Numbers, Order[0]);
  if Length(Numbers[Order[0]]) = 2 then
    Year := 2000 + Year;
  Month := NumberAt(Numbers, Order[1]);
  Day := NumberAt(Numbers, Order[2]);
  if Month > 12 then
  begin
    T := Month; Month := Day; Day := T;
  end;
  if (Year < 1) or (Year > 9999) or (Month < 1) or (Month > 12) or (Day < 1) or
     not IsValidDate(Year, Month, Day) then
    raise EBabelValueError.Create('day is out of range for month');
  Result := EncodeDate(Year, Month, Day);
end;

function ParseTime(const S: string; const Locale: TLocale; const Format: string): TDateTime;
var
  Numbers: TStringArray;
  FormatStr: string;
  HourIdx, MinIdx: Integer;
  SecIdx: Double;
  Order: array[0..2] of Integer;
  Hour, Minute, Second, Offset: Int64;
begin
  Numbers := DigitRuns(S);
  if Length(Numbers) = 0 then
    raise EDateParseError.Create('No numbers were found in input');
  if IsPredefined(Format) then
    FormatStr := LowerCase(GetTimeFormat(Locale, Format))
  else
    FormatStr := LowerCase(ParseDatePattern(Format).Pattern);
  HourIdx := Pos('h', FormatStr) - 1;
  if HourIdx < 0 then
  begin
    HourIdx := Pos('k', FormatStr) - 1;
    if HourIdx < 0 then
      raise EBabelValueError.Create('substring not found');
  end;
  MinIdx := Pos('m', FormatStr) - 1;
  if MinIdx < 0 then
    raise EBabelValueError.Create('substring not found');
  if Pos('s', FormatStr) > 0 then
    SecIdx := Pos('s', FormatStr) - 1
  else
    SecIdx := Infinity;
  OrderOf([HourIdx, MinIdx, SecIdx], Order);
  Offset := 0;
  if (Pos('a', FormatStr) > 0) and (Pos('pm', LowerCase(S)) > 0) then
    Offset := 12;
  Minute := 0;
  Second := 0;
  Hour := NumberAt(Numbers, Order[0]) + Offset;
  if Length(Numbers) > 1 then
  begin
    Minute := NumberAt(Numbers, Order[1]);
    if Length(Numbers) > 2 then
      Second := NumberAt(Numbers, Order[2]);
  end;
  if (Hour > 23) or (Minute > 59) or (Second > 59) then
    raise EBabelValueError.Create('hour must be in 0..23');
  Result := EncodeTime(Hour, Minute, Second, 0);
end;

end.
