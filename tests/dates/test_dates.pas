{ test_dates - checks babel.dates against the vectors of
  tests/python/gen_dates_vectors.py (the results of Python Babel 2.18.0
  for the same inputs).

  Usage: test_dates VECTORS.jsonl   (exit status 1 when a case fails)
         test_dates VECTORS.jsonl --update OUT.jsonl
           (writes the cases with the results obtained, to update
           tests/dates/reference.jsonl after a deliberate change) }
program test_dates;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, fpjson, testkit,
  babel.errors, babel.localedata, babel.core, babel.dates, babel.cldr_all;

function DT(A: TJSONArray): TDateTime;
begin
  Result := EncodeDateTime(A.Integers[0], A.Integers[1], A.Integers[2], A.Integers[3],
    A.Integers[4], A.Integers[5], A.Integers[6]);
end;

function MapJSON(M: TCLDRValue): TJSONData;
var
  O: TJSONObject;
  I: Integer;
  K: string;
begin
  O := TJSONObject.Create;
  for I := 0 to M.Count - 1 do
  begin
    case M.Keys(I).Kind of
      ckInt: K := IntToStr(M.Keys(I).AsInteger);
      ckNone: K := 'None';
    else
      K := M.Keys(I).AsString;
    end;
    O.Add(K, M.Items(I).AsString);
  end;
  Result := O;
end;

function NamesJSON(const Loc: string): TJSONData;
const
  Kinds: array[0..3] of string = ('day', 'month', 'quarter', 'period');
  Contexts: array[0..1] of string = ('format', 'stand-alone');
  Lengths: array[0..3] of string = ('full', 'long', 'medium', 'short');
var
  O: TJSONObject;
  Kind, W, C, F: string;
  Widths: array of string;
  M: TCLDRValue;
begin
  O := TJSONObject.Create;
  for Kind in Kinds do
  begin
    if Kind = 'day' then
      Widths := ['abbreviated', 'narrow', 'short', 'wide']
    else
      Widths := ['abbreviated', 'narrow', 'wide'];
    for W in Widths do
      for C in Contexts do
        try
          if Kind = 'day' then M := GetDayNames(Loc, W, C)
          else if Kind = 'month' then M := GetMonthNames(Loc, W, C)
          else if Kind = 'quarter' then M := GetQuarterNames(Loc, W, C)
          else M := GetPeriodNames(Loc, W, C);
          O.Add(Kind + '/' + W + '/' + C, MapJSON(M));
        except
          on EBabelKeyError do
            O.Add(Kind + '/' + W + '/' + C, 'KeyError');
        end;
  end;
  for W in ['abbreviated', 'narrow', 'wide'] do
    O.Add('era/' + W, MapJSON(GetEraNames(Loc, W)));
  for F in Lengths do
  begin
    O.Add('date/' + F, GetDateFormat(Loc, F));
    O.Add('time/' + F, GetTimeFormat(Loc, F));
    O.Add('datetime/' + F, GetDatetimeFormat(Loc, F));
  end;
  Result := O;
end;

function Kind(const S: string): TIntervalKind;
begin
  if S = 'date' then Result := ikDate
  else if S = 'time' then Result := ikTime
  else Result := ikDateTime;
end;

function Handle(const Op: string; Args: TJSONArray): TJSONData;
var
  A: TJSONArray;
  Toks: TPatternTokens;
  T: TPatternToken;
  D: TDateTime;
  Y, M, Dd, H, N, S, MS: Word;
  Parts: TStringArray;
begin
  if Op = 'names' then
    Result := NamesJSON(Args.Strings[0])
  else if Op = 'format_date' then
    Result := TJSONString.Create(FormatDate(DT(Args.Arrays[0]), Args.Strings[2], Args.Strings[1]))
  else if Op = 'format_datetime' then
    Result := TJSONString.Create(FormatDateAndTime(DT(Args.Arrays[0]), Args.Strings[3],
      DateTimeOptions.WithFormat(Args.Strings[1]).WithTimeZone(Args.Strings[2])))
  else if Op = 'format_time' then
    Result := TJSONString.Create(FormatTime(DT(Args.Arrays[0]), Args.Strings[3],
      DateTimeOptions.WithFormat(Args.Strings[1]).WithTimeZone(Args.Strings[2])))
  else if Op = 'tz_name' then
    Result := TJSONString.Create(GetTimezoneName(Args.Strings[0], Args.Strings[4],
      TimeZoneNameOptions.WithWidth(Args.Strings[1]).WithZoneVariant(Args.Strings[2])
      .WithReturnZone(Args.Booleans[3])))
  else if Op = 'tz_name_dt' then
    Result := TJSONString.Create(GetTimezoneName(DT(Args.Arrays[0]), Args.Strings[1], Args.Strings[3],
      TimeZoneNameOptions.WithWidth(Args.Strings[2])))
  else if Op = 'tz_gmt' then
    Result := TJSONString.Create(GetTimezoneGmt(DT(Args.Arrays[0]), Args.Strings[1], Args.Strings[4],
      Args.Strings[2], Args.Booleans[3]))
  else if Op = 'tz_location' then
    Result := TJSONString.Create(GetTimezoneLocation(Args.Strings[0], Args.Strings[2], Args.Booleans[1]))
  else if Op = 'format_skeleton' then
    Result := TJSONString.Create(FormatSkeleton(Args.Strings[0], DT(Args.Arrays[1]), Args.Strings[4],
      SkeletonOptions.WithTimeZone(Args.Strings[2]).WithFuzzy(Args.Booleans[3])))
  else if Op = 'format_interval' then
    Result := TJSONString.Create(FormatInterval(DT(Args.Arrays[0]), DT(Args.Arrays[1]), Args.Strings[6],
      IntervalOptions.WithSkeleton(Args.Strings[2]).WithTimeZone(Args.Strings[3])
      .WithFuzzy(Args.Booleans[4]).WithKind(Kind(Args.Strings[5]))))
  else if Op = 'format_timedelta' then
    Result := TJSONString.Create(FormatTimedelta(Args.Int64s[0], Args.Strings[5],
      TimedeltaOptions.WithGranularity(Args.Strings[1]).WithThreshold(Args.Floats[2])
      .WithAddDirection(Args.Booleans[3]).WithFormat(Args.Strings[4])))
  else if Op = 'period_id' then
    Result := TJSONString.Create(GetPeriodId(DT(Args.Arrays[0]), Args.Strings[3], Args.Strings[1], Args.Strings[2]))
  else if Op = 'parse_date' then
  begin
    D := ParseDate(Args.Strings[0], Args.Strings[2], Args.Strings[1]);
    DecodeDate(D, Y, M, Dd);
    Result := TJSONArray.Create([Y, M, Dd]);
  end
  else if Op = 'parse_time' then
  begin
    D := ParseTime(Args.Strings[0], Args.Strings[2], Args.Strings[1]);
    DecodeTime(D, H, N, S, MS);
    Result := TJSONArray.Create([H, N, S]);
  end
  else if Op = 'match_skeleton' then
    Result := TJSONString.Create(MatchSkeleton(Args.Strings[0], StrList(Args.Arrays[1]), Args.Booleans[2]))
  else if Op = 'split_interval' then
  begin
    Parts := SplitIntervalPattern(Args.Strings[0]);
    Result := StrArray(Parts);
  end
  else if Op = 'tokenize' then
  begin
    Toks := TokenizeDatePattern(Args.Strings[0]);
    A := TJSONArray.Create;
    for T in Toks do
      if T.Kind = ptChars then
        A.Add(TJSONArray.Create(['chars', T.Text]))
      else
        A.Add(TJSONArray.Create(['field', TJSONArray.Create([string(T.Field), T.Count])]));
    Result := A;
  end
  else
    raise Exception.Create('unknown op ' + Op);
end;

begin
  if (ParamCount = 3) and (ParamStr(2) = '--update') then
  begin
    RunVectors(ParamStr(1), @Handle, nil, ParamStr(3));
    Exit;
  end;
  if ParamCount <> 1 then
  begin
    WriteLn('usage: test_dates VECTORS.jsonl [--update OUT.jsonl]');
    Halt(2);
  end;
  if RunVectors(ParamStr(1), @Handle) > 0 then
    Halt(1);
end.
