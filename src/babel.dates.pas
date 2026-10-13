{ babel.dates - formatting and parsing of dates, times and durations, as
  Python Babel's babel.dates.

  FormatDate(EncodeDate(2026, 10, 13), 'es_PE') gives '13 oct 2026';
  FormatDateAndTime(Now_UTC, 'en', DateTimeOptions.WithFormat('full')
  .WithTimeZone('America/Lima')) gives 'Tuesday, October 13, 2026 at
  9:30:00 AM Peru Standard Time'.

  Dates and times are TDateTime values in UTC (Babel's naive datetimes are
  UTC as well). TimeZone names the zone to show them in ('Europe/Madrid';
  '' is UTC); the rules come from the system's tz database (babel.tz).
  FormatDate formats the date of the value as it is, without a zone (as
  Babel's format_date takes a date). Precision: milliseconds (TDateTime
  is decoded to milliseconds; the 'S' field shows microseconds as 0).

  The results are Babel's, including its formulas: the week numbers of
  the locale's first day and minimal days, fractional seconds through
  Python's round(), offsets split with floor division, format_timedelta's
  months of 30 days.

  Babel's format_datetime is FormatDateAndTime here: FormatDateTime is
  taken by SysUtils.

  Threading: everything here only reads shared data. }
unit babel.dates;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors, babel.localedata, babel.core, babel.tz;

type
  EDateParseError = class(EBabelValueError);   { Babel's ParseError }

  TDateTimeOptions = record
    Format: string;     { 'full', 'long', 'medium' (default), 'short' or a pattern }
    TimeZone: string;   { '' = UTC }
    function WithFormat(const Value: string): TDateTimeOptions;
    function WithTimeZone(const Value: string): TDateTimeOptions;
  end;

  TSkeletonOptions = record
    TimeZone: string;
    Fuzzy: Boolean;     { True: the closest skeleton when the locale lacks it }
    function WithTimeZone(const Value: string): TSkeletonOptions;
    function WithFuzzy(Value: Boolean): TSkeletonOptions;
  end;

  TIntervalKind = (ikDateTime, ikDate, ikTime);

  TIntervalOptions = record
    Skeleton: string;   { '' = none }
    TimeZone: string;
    Fuzzy: Boolean;
      Kind: TIntervalKind; { what the values are (Babel tells by their Python
                           type); ikDate uses only their dates }
    function WithSkeleton(const Value: string): TIntervalOptions;
    function WithTimeZone(const Value: string): TIntervalOptions;
    function WithFuzzy(Value: Boolean): TIntervalOptions;
    function WithKind(Value: TIntervalKind): TIntervalOptions;
  end;

  TTimedeltaOptions = record
    Granularity: string;    { 'year' .. 'second' (default) }
    Threshold: Double;      { 0.85 }
    AddDirection: Boolean;  { False }
    Format: string;         { 'narrow', 'short', 'long' (default); 'medium' = 'long' }
    function WithGranularity(const Value: string): TTimedeltaOptions;
    function WithThreshold(Value: Double): TTimedeltaOptions;
    function WithAddDirection(Value: Boolean): TTimedeltaOptions;
    function WithFormat(const Value: string): TTimedeltaOptions;
  end;

  TTimeZoneNameOptions = record
    Width: string;          { 'long' (default) or 'short' }
    Uncommon: Boolean;      { accepted and ignored, as in Babel }
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

  { A parsed date/time pattern (Babel's DateTimePattern). }
  TDateTimePattern = record
    Pattern: string;
    Tokens: TPatternTokens;
  end;

function DateTimeOptions: TDateTimeOptions;
function SkeletonOptions: TSkeletonOptions;
function IntervalOptions: TIntervalOptions;
function TimedeltaOptions: TTimedeltaOptions;
function TimeZoneNameOptions: TTimeZoneNameOptions;

{ Names (maps: index or id -> name), as Babel's get_*_names. }
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
function FormatDate(Date: TDateTime; const Locale: TLocale; const Format: string = 'medium'): string;
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

{ Parsing (Babel's simple guessing from the order of the fields). }
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
  Math, DateUtils, babel.decimal, babel.plural, babel.pystr;

const
  NoInheritanceMarker = #$E2#$88#$85#$E2#$88#$85#$E2#$88#$85;   { ∅∅∅ }
  PatternChars = 'GyYuQqMLwWdDFgEecabBhHKkmsSAzZOvVxX';
  PatternCharOrder = 'GyYuUQqMLlwWdDFgEecabBChHKkjJmsSAzZOvVXx';

{ ---- options ---- }

function DateTimeOptions: TDateTimeOptions;
begin
  Result := Default(TDateTimeOptions);
  Result.Format := 'medium';
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
    { Babel falls back to patterns[None], which does not exist }
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

{ ---- patterns (Babel's tokenize_pattern and friends) ---- }

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

function UntokenizeDatePattern(const Tokens: TPatternTokens): string;
var
  T: TPatternToken;
  C: Char;
  NeedsQuote: Boolean;
begin
  Result := '';
  for T in Tokens do
    if T.Kind = ptField then
      Result := Result + StringOfChar(T.Field, T.Count)
    else
    begin
      NeedsQuote := False;
      for C in T.Text do
        if IsPatternChar(C) then
          NeedsQuote := True;
      if NeedsQuote then
        Result := Result + '''' + StringReplace(T.Text, '''', '''''', [rfReplaceAll]) + ''''
      else
        Result := Result + T.Text;
    end;
end;

{ The lengths each field allows (Babel's PATTERN_CHARS); '' = any. }
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

  { A date, a time or a datetime as Babel's DateTimeFormat sees it: the
    local fields, and for times and datetimes the zone. }
  TValue = record
    Kind: TValueKind;
    Y, M, D, H, N, S, Micro: Integer;
    ZoneName: string;           { 'UTC' or the zone's key }
    Zone: TTimeZone;
    Fold: Integer;
    HasRef: Boolean;            { a time with a reference date }
    RefY, RefM, RefD: Integer;
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

{ An aware datetime: UTC converted to the zone, with zoneinfo's fold. }
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

{ utcoffset() and dst() of the value (a time with a reference date is
  combined with it, as Babel does; the fold is kept). }
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

function GmtText(OffsetSeconds: Integer; const Width: string; const Locale: TLocale;
  ReturnZ: Boolean): string;
var
  Hours, Secs: Int64;
  Pattern: string;
begin
  Hours := FloorDiv(OffsetSeconds, 3600);
  Secs := OffsetSeconds - Hours * 3600;
  if ReturnZ and (Hours = 0) and (Secs = 0) then
    Exit('Z');
  if (Secs = 0) and (Width = 'iso8601_short') then
    Exit(SignedPad2(Hours));
  if (Width = 'short') or (Width = 'iso8601_short') then
    Exit(SignedPad2(Hours) + Pad(Secs div 60, 2));
  if Width = 'iso8601' then
    Exit(SignedPad2(Hours) + ':' + Pad(Secs div 60, 2));
  Pattern := Need(Locale.Data, 'zone_formats').Str('gmt');
  Result := PercentS(Pattern, SignedPad2(Hours) + ':' + Pad(Secs div 60, 2));
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

function GetTimezoneLocation(const TimeZone: string; const Locale: TLocale; ReturnCity: Boolean): string;
var
  Zone, RegionFormat, Territory, TerritoryName, FallbackFormat, City, Metazone: string;
  Info, MetaInfo, Zones: TCLDRValue;
begin
  Zone := TimeZone;
  if Zone = '' then
    Zone := 'UTC';
  Zone := CanonicalZone(Zone);
  Info := Locale.TimeZones.Get(Zone);
  RegionFormat := Need(Locale.Data, 'zone_formats').Str('region');
  Territory := GetGlobal('zone_territories').Str(Zone, '');
  if (Territory = '') or not Locale.Territories.Has(Territory) then
    Territory := 'ZZ';
  if not Locale.Territories.Has(Territory) then
    raise EBabelKeyError.Create(Territory);
  TerritoryName := Locale.Territories.Str(Territory);
  Zones := GetGlobal('territory_zones').Get(Territory);
  if not ReturnCity and (Zones <> nil) and (Zones.Count = 1) then
    Exit(PercentS(RegionFormat, TerritoryName));
  FallbackFormat := Need(Locale.Data, 'zone_formats').Str('fallback');
  if (Info <> nil) and Info.Has('city') then
    City := Info.Str('city')
  else
  begin
    Metazone := GetGlobal('meta_zones').Str(Zone, '');
    MetaInfo := Locale.MetaZones.Get(Metazone);
    if (MetaInfo <> nil) and MetaInfo.Has('city') then
      City := MetaInfo.Str('city')
    else if Pos('/', Zone) > 0 then
      City := StringReplace(Copy(Zone, Pos('/', Zone) + 1, MaxInt), '_', ' ', [rfReplaceAll])
    else
      City := StringReplace(Zone, '_', ' ', [rfReplaceAll]);
  end;
  if ReturnCity then
    Exit(City);
  Result := PercentS(RegionFormat, PercentNamed(FallbackFormat, City, TerritoryName));
end;

{ get_timezone_name; HasDate: a datetime was given (its DST and offset). }
function TimezoneNameOf(const TimeZone: string; HasDate: Boolean; DSTOffset, UTCOffset: Integer;
  const Locale: TLocale; const Options: TTimeZoneNameOptions): string;
var
  Zone, Variant, Width, Metazone, Name: string;
  Info, MetaInfo, V: TCLDRValue;
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
  Zone := CanonicalZone(Zone);
  if Options.ReturnZone then
    Exit(Zone);
  Info := Locale.TimeZones.Get(Zone);
  V := Info.Path([Width, Variant]);
  if (V <> nil) and (V.AsString <> NoInheritanceMarker) then
    Exit(V.AsString);
  Metazone := GetGlobal('meta_zones').Str(Zone, '');
  if Metazone <> '' then
  begin
    MetaInfo := Locale.MetaZones.Get(Metazone);
    if (MetaInfo <> nil) and MetaInfo.Has(Width) then
    begin
      Name := MetaInfo.Get(Width).Str(Variant, '');
      if (Width = 'short') and (Name = NoInheritanceMarker) then
        Name := MetaInfo.Path(['long']).Str(Variant, '');
      if (Name <> '') and (Name <> NoInheritanceMarker) then
        Exit(Name);
    end;
  end;
  if HasDate then
    Exit(GmtText(UTCOffset, Width, Locale, False));
  Result := GetTimezoneLocation(TimeZone, Locale);
end;

function GetTimezoneName(const TimeZone: string; const Locale: TLocale): string;
begin
  Result := GetTimezoneName(TimeZone, Locale, TimeZoneNameOptions);
end;

function GetTimezoneName(const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string;
begin
  GetTimeZone(TimeZone);    { an unknown zone raises, as in Babel }
  Result := TimezoneNameOf(TimeZone, False, 0, 0, Locale, Options);
end;

function GetTimezoneName(UTC: TDateTime; const TimeZone: string; const Locale: TLocale;
  const Options: TTimeZoneNameOptions): string;
var
  Info: TZoneInfo;
begin
  Info := GetTimeZone(TimeZone).InfoAt(UTC);
  Result := TimezoneNameOf(TimeZone, True, Info.DSTOffset, Info.UTCOffset, Locale, Options);
end;

{ ---- periods of the day (get_period_id) ---- }

function PeriodIdAt(SecondsPastMidnight: Integer; const Locale: TLocale; const RuleType: string): string;
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
        if Rule.Has('at') and (Field(Rule, 'at') = T) then
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

{ ---- fields (Babel's DateTimeFormat) ---- }

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

{ Python's round(x, n) for a float: the decimal rounding of its exact
  value, half to even. }
function PyRound(X: Double; N: Integer): Double;
var
  Code: Integer;
begin
  Val(TDecimal.FromDoubleExact(X).Quantize(-N).ToString, Result, Code);
end;

{ Babel's int(round(microsecond / 1000000, num) * 10 ** num), in Double
  arithmetic as Python does it (FPC would compute the product in Extended
  precision: 0.123 * 1000 would truncate to 122). }
function FracSeconds(Micro, Num: Integer): Int64;
var
  R, P, Prod: Double;
  I: Integer;
begin
  R := PyRound(Micro / 1000000, Num);
  P := 1;
  for I := 1 to Num do
    P := P * 10;
  Prod := R * P;
  Result := Trunc(Prod);
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

function FormatTimezoneField(const V: TValue; F: Char; Num: Integer; const Locale: TLocale): string;
var
  Width: string;
  Info: TZoneInfo;
  O: TTimeZoneNameOptions;
begin
  NeedTime(V, F);
  if Num <= 3 then Width := 'short'
  else if Num = 4 then Width := 'long'
  else Width := 'iso8601';
  Info := ZoneInfoOf(V);
  O := TimeZoneNameOptions.WithWidth(Width);
  case F of
    'z': Result := TimezoneNameOf(V.ZoneName, True, Info.DSTOffset, Info.UTCOffset, Locale, O);
    'Z':
      if Num = 5 then
        Result := GmtText(Info.UTCOffset, Width, Locale, True)
      else
        Result := GmtText(Info.UTCOffset, Width, Locale, False);
    'O':
      if Num = 4 then
        Result := GmtText(Info.UTCOffset, Width, Locale, False)
      else
        Result := 'None';     { Babel returns None, formatted as 'None' }
    'v': Result := TimezoneNameOf(V.ZoneName, False, 0, 0, Locale, O);
    'V':
      case Num of
        1: Result := TimezoneNameOf(V.ZoneName, False, 0, 0, Locale, O);
        2: Result := TimezoneNameOf(V.ZoneName, False, 0, 0, Locale, O.WithReturnZone(True).WithWidth('long'));
        3: Result := GetTimezoneLocation(V.ZoneName, Locale, True);
      else
        Result := GetTimezoneLocation(V.ZoneName, Locale);
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

function FormatPeriodField(const V: TValue; F: Char; Num: Integer; const Locale: TLocale): string;
var
  Widths: array[0..3] of string;
  Period, Context, W: string;
  Names: TCLDRValue;
begin
  NeedTime(V, F);
  if Num < 3 then Widths[0] := WidthName(3) else Widths[0] := WidthName(Num);
  Widths[1] := 'wide';
  Widths[2] := 'narrow';
  Widths[3] := 'abbreviated';
  if F = 'a' then
  begin
    if V.H >= 12 then Period := 'pm' else Period := 'am';
    Context := 'format';
  end
  else
  begin
    Period := PeriodIdAt(V.H * 3600 + V.N * 60 + V.S, Locale, '');
    if F = 'B' then Context := 'format' else Context := 'stand-alone';
  end;
  for W in Widths do
  begin
    Names := GetPeriodNames(Locale, W, Context);
    if Names.Has(Period) then
      Exit(Names.Str(Period));
  end;
  raise EBabelValueError.CreateFmt('Could not format period %s in %s', [Period, Locale.ToString]);
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
        NeedTime(V, F);
        Result := Pad(FracSeconds(V.Micro, Num), Num);
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

function ApplyPattern(const P: TDateTimePattern; const V: TValue; const Locale: TLocale): string;
var
  T: TPatternToken;
begin
  Result := '';
  for T in P.Tokens do
    if T.Kind = ptChars then
      Result := Result + T.Text
    else
      Result := Result + FormatField(V, T.Field, T.Count, Locale);
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

{ format_time of an aware datetime value: a time with the value's date as
  reference }
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

function FormatTime(UTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatTime(UTC, Locale, DateTimeOptions);
end;

function FormatTime(UTC: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string;
var
  Y, M, D, H, N, S, MS: Word;
begin
  { the reference date is the date of the value before conversion (as
    Babel's format_time) }
  DecodeDateTimeMs(UTC, Y, M, D, H, N, S, MS);
  Result := FormatTimeValue(DateTimeValue(UTC, Options.TimeZone), Locale, Options.Format, Y, M, D);
end;

function FormatDateTimeValue(const V: TValue; const Locale: TLocale; const Format: string): string;
begin
  if IsPredefined(Format) then
  begin
    Result := StringReplace(GetDatetimeFormat(Locale, Format), '''', '', [rfReplaceAll]);
    Result := StringReplace(Result, '{0}', FormatTimeValue(V, Locale, Format, V.Y, V.M, V.D), [rfReplaceAll]);
    Result := StringReplace(Result, '{1}', FormatDateValue(V, Locale, Format), [rfReplaceAll]);
  end
  else
    Result := ApplyPattern(ParseDatePattern(Format), V, Locale);
end;

function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatDateAndTime(UTC, Locale, DateTimeOptions);
end;

function FormatDateAndTime(UTC: TDateTime; const Locale: TLocale; const Options: TDateTimeOptions): string;
begin
  Result := FormatDateTimeValue(DateTimeValue(UTC, Options.TimeZone), Locale, Options.Format);
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

function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale): string;
begin
  Result := FormatSkeleton(Skeleton, UTC, Locale, SkeletonOptions);
end;

function FormatSkeleton(const Skeleton: string; UTC: TDateTime; const Locale: TLocale;
  const Options: TSkeletonOptions): string;
var
  Skeletons: TCLDRValue;
  S: string;
begin
  Skeletons := Locale.DatetimeSkeletons;
  S := Skeleton;
  if Options.Fuzzy and not Skeletons.Has(S) then
    S := MatchSkeleton(S, SkeletonKeys(Skeletons));
  if (S = '') or not Skeletons.Has(S) then
    raise EBabelKeyError.Create(Skeleton);
  Result := FormatDateTimeValue(DateTimeValue(UTC, Options.TimeZone), Locale, Skeletons.Str(S));
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
  Fmt, PluralForm, Pattern: string;
  DateFields, UnitPatterns, Rel, Pats: TCLDRValue;
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
  for I := 0 to High(Units) do
  begin
    Value := System.Abs(Seconds) / Secs[I];
    if (Value >= Options.Threshold) or (Units[I] = Options.Granularity) then
    begin
      if (Units[I] = Options.Granularity) and (Value > 0) then
        Value := Max(1, Value);
      IValue := Round(Value);     { Python's round(): half to even }
      PluralForm := Locale.PluralForm.Evaluate(IValue);
      Candidates := nil;
      if Options.AddDirection then
      begin
        Rel := DateFields.Get(Units[I] + '-' + Fmt);
        if (Rel = nil) or (Rel.Count = 0) then
          Rel := Need(DateFields, Units[I]);
        { as Babel: a missing direction is a KeyError }
        if Seconds >= 0 then
          AddCandidate(Need(Rel, 'future'))
        else
          AddCandidate(Need(Rel, 'past'));
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
      Exit(StringReplace(Pattern, '{0}', IntToStr(IValue), [rfReplaceAll]));
    end;
  end;
  Result := '';
end;

{ ---- intervals ---- }

function Extract(const V: TValue; F: Char): Integer;
begin
  case F of
    'y': Result := V.Y;
    'M': Result := V.M;
    'd': Result := V.D;
    'H': Result := V.H;
    'h':
      begin
        Result := V.H mod 12;
        if Result = 0 then
          Result := 12;
      end;
    'm': Result := V.N;
    'a': Result := Ord(V.H >= 12);
  else
    raise EBabelNotImplementedError.CreateFmt('Not implemented: extracting ''%s''', [F]);
  end;
end;

function FallbackInterval(StartUTC, EndUTC: TDateTime; const Skeleton: string;
  const Options: TIntervalOptions; const Locale: TLocale): string;

  function Fmt(DT: TDateTime): string;
  begin
    if (Skeleton <> '') and Locale.DatetimeSkeletons.Has(Skeleton) then
      Result := FormatSkeleton(Skeleton, DT, Locale, SkeletonOptions.WithTimeZone(Options.TimeZone))
    else if Options.Kind = ikDate then
      Result := FormatDate(DT, Locale)
    else if Options.Kind = ikTime then
      Result := FormatTime(DT, Locale, DateTimeOptions.WithTimeZone(Options.TimeZone))
    else
      Result := FormatDateAndTime(DT, Locale, DateTimeOptions.WithTimeZone(Options.TimeZone));
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
  Skeleton := Options.Skeleton;
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
      SkeletonOptions.WithTimeZone(Options.TimeZone).WithFuzzy(Options.Fuzzy)));
  SV := DateTimeValue(StartUTC, Options.TimeZone);
  EV := DateTimeValue(EndUTC, Options.TimeZone);
  for F in PatternCharOrder do
    if Skel.Has(F) and (Extract(SV, F) <> Extract(EV, F)) then
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

{ The order (0, 1, 2) of three positions, as Python's sorted() of
  (position, name) pairs. }
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
