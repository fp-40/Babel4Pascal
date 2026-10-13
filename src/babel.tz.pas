{ babel.tz - time zone rules from the system's tz database.

  CLDR names time zones; the rules (the offset from UTC and whether
  daylight saving time is in effect at an instant) come from the IANA tz
  database, which Linux installs as TZif files under /usr/share/zoneinfo
  (one file per zone: Europe/Madrid, America/Lima, ...). This unit reads
  those files, as Python's zoneinfo module (which Babel uses) does, with
  the same results:
  - the transitions of the file (version 2+ data, 64-bit times);
  - after the last transition, the POSIX TZ rule of the file's footer
    ('CET-1CEST,M3.5.0,M10.5.0/3'), computed for the year of the instant;
  - before the first transition, the first standard-time type of the file;
  - the DST offset (zoneinfo's dst()) inferred from the isdst flags as
    zoneinfo infers it.

  GetTimeZone('') is UTC. LocalTimeZoneName gives the zone of the machine
  (the TZ variable, then /etc/localtime's link, then /etc/timezone).

  A zone's file is read once and kept until the program ends.

  Threading: loading is done under a lock; the loaded data never changes,
  so any thread may query it. }
unit babel.tz;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, babel.errors;

type
  { Babel's (Python's) LookupError for an unknown zone. }
  EUnknownTimeZoneError = class(EBabelError);

  { What applies at one instant. }
  TZoneInfo = record
    UTCOffset: Integer;     { seconds east of UTC }
    DSTOffset: Integer;     { seconds of daylight saving time (zoneinfo's dst()); 0 in standard time }
    Abbreviation: string;   { 'CEST', '-05' }
  end;

  TZoneData = class;

  TTimeZone = record
  private
    FName: string;
    FData: TZoneData;       { nil for UTC }
  public
    { The zone's name ('Europe/Madrid'; 'UTC' for GetTimeZone('')). }
    property Name: string read FName;
    function IsUTC: Boolean;
    { The rules at an instant given in UTC. }
    function InfoAt(UTCSeconds: Int64): TZoneInfo; overload;
    function InfoAt(UTC: TDateTime): TZoneInfo; overload;
    { The local time of an instant given in UTC. }
    function ToLocal(UTC: TDateTime): TDateTime;
    { The rules at a local wall-clock time (seconds since 1970 as if the
      local time were UTC), as zoneinfo's utcoffset() and dst() of a
      datetime with this zone: Fold 0 takes the first of two repeated
      times, 1 the second. }
    function InfoAtLocal(LocalSeconds: Int64; Fold: Integer = 0): TZoneInfo;
  end;

  { The parsed contents of a TZif file (internal; one per zone). }
  TZoneData = class
  private
    Trans: array of Int64;            { UTC seconds }
    TransIdx: array of Integer;       { type index per transition }
    UtcOff, DstOff: array of Integer; { per type }
    IsDst: array of Boolean;
    Abbr: array of string;
    BeforeType: Integer;              { -1: none }
    { the footer }
    HasRule, RuleIsFixed: Boolean;
    StdAbbr, DstAbbr: string;
    StdOffset, DstOffsetRule: Integer;
    StartRule, EndRule: record
      Kind: Char;                     { 'M', 'J' or 'N' }
      M, W, D: Integer;               { M: month, week, weekday; J/N: day number in D }
      Time: Integer;                  { seconds after midnight, may be negative or > 24h }
    end;
    TransLocal: array[0..1] of array of Int64;   { zoneinfo's _trans_local }
    function RuleInfo(UTCSeconds: Int64): TZoneInfo;
    function RuleInfoLocal(LocalSeconds: Int64; Fold: Integer): TZoneInfo;
    function TypeInfo(T: Integer): TZoneInfo;
  public
    function InfoAt(UTCSeconds: Int64): TZoneInfo;
    function InfoAtLocal(LocalSeconds: Int64; Fold: Integer): TZoneInfo;
  end;

{ The zone; '' and 'UTC'-like names that have no file are UTC. Raises
  EUnknownTimeZoneError when no file has that name. }
function GetTimeZone(const Name: string): TTimeZone;
{ The machine's zone name ('UTC' when none is found). }
function LocalTimeZoneName: string;
{ Where the zone files are read (default /usr/share/zoneinfo, or the
  PYTHONTZPATH-like variable TZDIR when set). }
function ZoneInfoPath: string;
procedure SetZoneInfoPath(const Path: string);
{ Seconds since 1970-01-01 of a TDateTime taken as UTC (exact to the
  second, from its decoded fields), and back. }
function UnixSeconds(DT: TDateTime): Int64;
function DateTimeOfUnix(Seconds: Int64): TDateTime;
{ The fields of a TDateTime rounded to the nearest millisecond
  (DecodeDateTime truncates: a value encoded with 123 ms gives 122). }
procedure DecodeDateTimeMs(DT: TDateTime; out Y, M, D, H, N, S, MS: Word);

implementation

uses
  DateUtils, BaseUnix;

var
  Lock: TRTLCriticalSection;
  Zones: TStringList;          { name -> TZoneData; sorted }
  ZonePath: string;

{ ---- calendar helpers ---- }

function IsLeap(Y: Integer): Boolean;
begin
  Result := (Y mod 4 = 0) and ((Y mod 100 <> 0) or (Y mod 400 = 0));
end;

{ Days from 1970-01-01 to Y-M-D (proleptic Gregorian). }
function DaysFromCivil(Y, M, D: Integer): Int64;
var
  Era, Yoe, Doy, Doe: Int64;
begin
  if M <= 2 then
    Dec(Y);
  if Y >= 0 then Era := Y div 400 else Era := (Y - 399) div 400;
  Yoe := Y - Era * 400;
  if M > 2 then Doy := (153 * (M - 3) + 2) div 5 + D - 1
  else Doy := (153 * (M + 9) + 2) div 5 + D - 1;
  Doe := Yoe * 365 + Yoe div 4 - Yoe div 100 + Doy;
  Result := Era * 146097 + Doe - 719468;
end;

procedure CivilFromDays(Z: Int64; out Y, M, D: Integer);
var
  Era, Doe, Yoe, Doy, Mp: Int64;
begin
  Z := Z + 719468;
  if Z >= 0 then Era := Z div 146097 else Era := (Z - 146096) div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe div 1460 + Doe div 36524 - Doe div 146096) div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe div 4 - Yoe div 100);
  Mp := (5 * Doy + 2) div 153;
  D := Doy - (153 * Mp + 2) div 5 + 1;
  if Mp < 10 then M := Mp + 3 else M := Mp - 9;
  if M <= 2 then
    Inc(Y);
end;

function FloorDiv(A, B: Int64): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then
    Dec(Result);
end;

procedure DecodeDateTimeMs(DT: TDateTime; out Y, M, D, H, N, S, MS: Word);
var
  Day: Int64;
  Ms_: Int64;
begin
  Day := Trunc(DT);
  Ms_ := Round(Abs(DT - Day) * 86400000);
  if Ms_ >= 86400000 then
  begin
    Dec(Ms_, 86400000);
    if DT >= 0 then Inc(Day) else Dec(Day);
  end;
  DecodeDate(Day, Y, M, D);
  H := Ms_ div 3600000;
  N := (Ms_ div 60000) mod 60;
  S := (Ms_ div 1000) mod 60;
  MS := Ms_ mod 1000;
end;

function UnixSeconds(DT: TDateTime): Int64;
var
  Y, M, D, H, N, S, MS: Word;
begin
  DecodeDateTimeMs(DT, Y, M, D, H, N, S, MS);
  Result := DaysFromCivil(Y, M, D) * 86400 + H * 3600 + N * 60 + S;
end;

function DateTimeOfUnix(Seconds: Int64): TDateTime;
var
  Y, M, D: Integer;
  Rest: Int64;
begin
  CivilFromDays(FloorDiv(Seconds, 86400), Y, M, D);
  Rest := Seconds - FloorDiv(Seconds, 86400) * 86400;
  Result := EncodeDateTime(Y, M, D, Rest div 3600, (Rest mod 3600) div 60, Rest mod 60, 0);
end;

{ ---- TZif ---- }

function ReadBE32(const B: TBytes; var P: Integer): LongInt;
begin
  if P + 4 > Length(B) then
    raise EUnknownTimeZoneError.Create('truncated zone file');
  Result := LongInt((LongWord(B[P]) shl 24) or (LongWord(B[P + 1]) shl 16) or
    (LongWord(B[P + 2]) shl 8) or LongWord(B[P + 3]));
  Inc(P, 4);
end;

function ReadBE64(const B: TBytes; var P: Integer): Int64;
var
  Hi, Lo: LongWord;
begin
  Hi := LongWord(ReadBE32(B, P));
  Lo := LongWord(ReadBE32(B, P));
  Result := Int64((QWord(Hi) shl 32) or QWord(Lo));
end;

type
  THeader = record
    Version: Char;
    IsUtCnt, IsStdCnt, LeapCnt, TimeCnt, TypeCnt, CharCnt: Integer;
  end;

function ReadHeader(const B: TBytes; var P: Integer): THeader;
begin
  if (P + 44 > Length(B)) or (B[P] <> Ord('T')) or (B[P + 1] <> Ord('Z')) or
     (B[P + 2] <> Ord('i')) or (B[P + 3] <> Ord('f')) then
    raise EUnknownTimeZoneError.Create('not a TZif file');
  Result.Version := Chr(B[P + 4]);
  Inc(P, 20);
  Result.IsUtCnt := ReadBE32(B, P);
  Result.IsStdCnt := ReadBE32(B, P);
  Result.LeapCnt := ReadBE32(B, P);
  Result.TimeCnt := ReadBE32(B, P);
  Result.TypeCnt := ReadBE32(B, P);
  Result.CharCnt := ReadBE32(B, P);
end;

{ zoneinfo's _utcoff_to_dstoff: the DST offset of each type, inferred
  from the neighbouring standard-time types. }
procedure InferDstOffsets(Z: TZoneData);
var
  TypeCnt, DstCnt, DstFound, I, Idx, CompIdx, Dstoff: Integer;
  Completed: Boolean;
begin
  TypeCnt := Length(Z.IsDst);
  SetLength(Z.DstOff, TypeCnt);
  for I := 0 to TypeCnt - 1 do
    Z.DstOff[I] := 0;
  DstCnt := 0;
  for I := 0 to TypeCnt - 1 do
    if Z.IsDst[I] then
      Inc(DstCnt);
  DstFound := 0;
  Completed := True;              { the loop ends without break }
  for I := 1 to High(Z.TransIdx) do
  begin
    if DstCnt = DstFound then
    begin
      Completed := False;
      Break;
    end;
    Idx := Z.TransIdx[I];
    if not Z.IsDst[Idx] then
      Continue;
    if Z.DstOff[Idx] <> 0 then
      Continue;
    Dstoff := 0;
    CompIdx := Z.TransIdx[I - 1];
    if not Z.IsDst[CompIdx] then
      Dstoff := Z.UtcOff[Idx] - Z.UtcOff[CompIdx];
    if (Dstoff = 0) and (Idx < TypeCnt - 1) and (I + 1 <= High(Z.TransIdx)) then
    begin
      CompIdx := Z.TransIdx[I + 1];
      if Z.IsDst[CompIdx] then
        Continue;
      Dstoff := Z.UtcOff[Idx] - Z.UtcOff[CompIdx];
    end;
    if Dstoff <> 0 then
    begin
      Inc(DstFound);
      Z.DstOff[Idx] := Dstoff;
    end;
  end;
  if Completed then
    for I := 0 to TypeCnt - 1 do
      if (Z.DstOff[I] = 0) and Z.IsDst[I] then
        Z.DstOff[I] := 3600;
end;

{ [+-]h[:mm[:ss]] as seconds (sign as written). }
function ParseHMS(const S: string; MaxHours: Integer; out Secs: Integer): Boolean;
var
  Parts: TStringArray;
  Sign, H, M, Sec: Integer;
  T: string;
begin
  Result := False;
  T := S;
  Sign := 1;
  if (T <> '') and (T[1] in ['+', '-']) then
  begin
    if T[1] = '-' then
      Sign := -1;
    Delete(T, 1, 1);
  end;
  Parts := T.Split([':']);
  if (Length(Parts) < 1) or (Length(Parts) > 3) then
    Exit;
  if not TryStrToInt(Parts[0], H) or (Length(Parts[0]) > 3) or (H > MaxHours) then
    Exit;
  M := 0;
  Sec := 0;
  if (Length(Parts) > 1) and ((Length(Parts[1]) <> 2) or not TryStrToInt(Parts[1], M)) then
    Exit;
  if (Length(Parts) > 2) and ((Length(Parts[2]) <> 2) or not TryStrToInt(Parts[2], Sec)) then
    Exit;
  Secs := Sign * (H * 3600 + M * 60 + Sec);
  Result := True;
end;

{ A name of the TZ string: letters, or <...>; returns the text after it. }
function TakeAbbr(var S: string; out Abbr: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if S = '' then
    Exit;
  if S[1] = '<' then
  begin
    I := Pos('>', S);
    if I = 0 then
      Exit;
    Abbr := Copy(S, 2, I - 2);
    Delete(S, 1, I);
  end
  else
  begin
    I := 1;
    while (I <= Length(S)) and not (S[I] in ['0'..'9', ':', '.', '+', '-', ',', '<']) do
      Inc(I);
    if I = 1 then
      Exit;
    Abbr := Copy(S, 1, I - 1);
    Delete(S, 1, I - 1);
  end;
  Result := True;
end;

function TakeOffset(var S: string; out Secs: Integer): Boolean;
var
  I: Integer;
begin
  I := 1;
  if (I <= Length(S)) and (S[I] in ['+', '-']) then
    Inc(I);
  while (I <= Length(S)) and (S[I] in ['0'..'9', ':']) do
    Inc(I);
  Result := (I > 1) and ParseHMS(Copy(S, 1, I - 1), 24, Secs);
  if Result then
  begin
    Secs := -Secs;          { POSIX: +5 means 5 hours west }
    Delete(S, 1, I - 1);
  end;
end;

procedure ParseRuleDate(const Spec: string; var R: Char; var M, W, D, Time: Integer);
var
  DatePart, TimePart: string;
  P: Integer;
  Parts: TStringArray;
begin
  P := Pos('/', Spec);
  if P > 0 then
  begin
    DatePart := Copy(Spec, 1, P - 1);
    TimePart := Copy(Spec, P + 1, MaxInt);
    if not ParseHMS(TimePart, 167, Time) then
      raise EUnknownTimeZoneError.Create('invalid TZ rule time ' + Spec);
  end
  else
  begin
    DatePart := Spec;
    Time := 2 * 3600;
  end;
  if (DatePart <> '') and (DatePart[1] = 'M') then
  begin
    Parts := Copy(DatePart, 2, MaxInt).Split(['.']);
    if (Length(Parts) <> 3) or not TryStrToInt(Parts[0], M) or not TryStrToInt(Parts[1], W) or
       not TryStrToInt(Parts[2], D) then
      raise EUnknownTimeZoneError.Create('invalid TZ rule date ' + Spec);
    R := 'M';
  end
  else if (DatePart <> '') and (DatePart[1] = 'J') then
  begin
    if not TryStrToInt(Copy(DatePart, 2, MaxInt), D) then
      raise EUnknownTimeZoneError.Create('invalid TZ rule date ' + Spec);
    R := 'J';
  end
  else
  begin
    if not TryStrToInt(DatePart, D) then
      raise EUnknownTimeZoneError.Create('invalid TZ rule date ' + Spec);
    R := 'N';
  end;
end;

procedure ParseFooter(Z: TZoneData; const TZ: string);
var
  S, Rules: string;
  P: Integer;
  Parts: TStringArray;
begin
  Z.HasRule := False;
  if TZ = '' then
    Exit;
  P := Pos(',', TZ);
  if P > 0 then
  begin
    S := Copy(TZ, 1, P - 1);
    Rules := Copy(TZ, P + 1, MaxInt);
  end
  else
  begin
    S := TZ;
    Rules := '';
  end;
  if not TakeAbbr(S, Z.StdAbbr) then
    raise EUnknownTimeZoneError.Create('invalid TZ string ' + TZ);
  Z.StdOffset := 0;
  if (S <> '') and not TakeOffset(S, Z.StdOffset) then
    raise EUnknownTimeZoneError.Create('invalid TZ string ' + TZ);
  Z.HasRule := True;
  if S = '' then
  begin
    Z.RuleIsFixed := True;   { a fixed offset }
    Exit;
  end;
  if not TakeAbbr(S, Z.DstAbbr) then
    raise EUnknownTimeZoneError.Create('invalid TZ string ' + TZ);
  Z.DstOffsetRule := Z.StdOffset + 3600;
  if (S <> '') and not TakeOffset(S, Z.DstOffsetRule) then
    raise EUnknownTimeZoneError.Create('invalid TZ string ' + TZ);
  if S <> '' then
    raise EUnknownTimeZoneError.Create('invalid TZ string ' + TZ);
  Parts := Rules.Split([',']);
  if Length(Parts) <> 2 then
    raise EUnknownTimeZoneError.Create('missing transition rules in ' + TZ);
  Z.RuleIsFixed := False;
  ParseRuleDate(Parts[0], Z.StartRule.Kind, Z.StartRule.M, Z.StartRule.W, Z.StartRule.D, Z.StartRule.Time);
  ParseRuleDate(Parts[1], Z.EndRule.Kind, Z.EndRule.M, Z.EndRule.W, Z.EndRule.D, Z.EndRule.Time);
end;

{ zoneinfo's _ts_to_local: the transitions in local wall-clock time, for
  fold 0 (the larger of the two offsets around each) and fold 1. }
procedure ComputeTransLocal(Z: TZoneData);
var
  I, N: Integer;
  Off0, Off1, T: Integer;
begin
  N := Length(Z.Trans);
  SetLength(Z.TransLocal[0], N);
  SetLength(Z.TransLocal[1], N);
  if N = 0 then
    Exit;
  if Length(Z.UtcOff) > 1 then
  begin
    Off0 := Z.UtcOff[0];
    Off1 := Z.UtcOff[Z.TransIdx[0]];
    if Off1 > Off0 then
    begin
      T := Off0; Off0 := Off1; Off1 := T;
    end;
  end
  else
  begin
    Off0 := Z.UtcOff[0];
    Off1 := Off0;
  end;
  Z.TransLocal[0][0] := Z.Trans[0] + Off0;
  Z.TransLocal[1][0] := Z.Trans[0] + Off1;
  for I := 1 to N - 1 do
  begin
    Off0 := Z.UtcOff[Z.TransIdx[I - 1]];
    Off1 := Z.UtcOff[Z.TransIdx[I]];
    if Off1 > Off0 then
    begin
      T := Off0; Off0 := Off1; Off1 := T;
    end;
    Z.TransLocal[0][I] := Z.Trans[I] + Off0;
    Z.TransLocal[1][I] := Z.Trans[I] + Off1;
  end;
end;

function LoadZone(const Bytes: TBytes): TZoneData;
var
  P, I, Skip: Integer;
  H: THeader;
  CharStart: Integer;
  AbbrIdx: array of Integer;
  Footer: string;
  E: Integer;
begin
  Result := TZoneData.Create;
  try
    P := 0;
    H := ReadHeader(Bytes, P);
    if H.Version >= '2' then
    begin
      Skip := H.TimeCnt * 5 + H.TypeCnt * 6 + H.CharCnt + H.LeapCnt * 8 + H.IsStdCnt + H.IsUtCnt;
      Inc(P, Skip);
      H := ReadHeader(Bytes, P);
    end;
    SetLength(Result.Trans, H.TimeCnt);
    SetLength(Result.TransIdx, H.TimeCnt);
    for I := 0 to H.TimeCnt - 1 do
      if H.Version >= '2' then
        Result.Trans[I] := ReadBE64(Bytes, P)
      else
        Result.Trans[I] := ReadBE32(Bytes, P);
    if P + H.TimeCnt > Length(Bytes) then
      raise EUnknownTimeZoneError.Create('truncated zone file');
    for I := 0 to H.TimeCnt - 1 do
    begin
      Result.TransIdx[I] := Bytes[P];
      Inc(P);
      if Result.TransIdx[I] >= H.TypeCnt then
        raise EUnknownTimeZoneError.Create('invalid transition index');
    end;
    SetLength(Result.UtcOff, H.TypeCnt);
    SetLength(Result.IsDst, H.TypeCnt);
    SetLength(Result.Abbr, H.TypeCnt);
    SetLength(AbbrIdx, H.TypeCnt);
    for I := 0 to H.TypeCnt - 1 do
    begin
      Result.UtcOff[I] := ReadBE32(Bytes, P);
      if P + 2 > Length(Bytes) then
        raise EUnknownTimeZoneError.Create('truncated zone file');
      Result.IsDst[I] := Bytes[P] <> 0;
      AbbrIdx[I] := ShortInt(Bytes[P + 1]);
      Inc(P, 2);
    end;
    CharStart := P;
    for I := 0 to H.TypeCnt - 1 do
    begin
      E := CharStart + AbbrIdx[I];
      while (E < CharStart + H.CharCnt) and (E < Length(Bytes)) and (Bytes[E] <> 0) do
        Inc(E);
      SetLength(Result.Abbr[I], E - (CharStart + AbbrIdx[I]));
      if Length(Result.Abbr[I]) > 0 then
        Move(Bytes[CharStart + AbbrIdx[I]], Result.Abbr[I][1], Length(Result.Abbr[I]));
    end;
    Inc(P, H.CharCnt);
    InferDstOffsets(Result);
    ComputeTransLocal(Result);
    { the first standard-time type is used before the first transition }
    Result.BeforeType := -1;
    for I := 0 to H.TypeCnt - 1 do
      if not Result.IsDst[I] then
      begin
        Result.BeforeType := I;
        Break;
      end;
    if (Result.BeforeType = -1) and (H.TimeCnt > 0) then
      Result.BeforeType := Result.TransIdx[0];
    { footer (version 2+): newline, TZ string, newline }
    Footer := '';
    if H.Version >= '2' then
    begin
      Inc(P, H.LeapCnt * 12 + H.IsStdCnt + H.IsUtCnt);
      if (P < Length(Bytes)) and (Bytes[P] = 10) then
      begin
        Inc(P);
        E := P;
        while (E < Length(Bytes)) and (Bytes[E] <> 10) do
          Inc(E);
        SetLength(Footer, E - P);
        if E > P then
          Move(Bytes[P], Footer[1], E - P);
      end;
    end;
    ParseFooter(Result, Footer);
    if not Result.HasRule and (H.TypeCnt = 0) then
      raise EUnknownTimeZoneError.Create('no time zone information found');
  except
    Result.Free;
    raise;
  end;
end;

{ ---- lookups (zoneinfo's fromutc) ---- }

function TZoneData.TypeInfo(T: Integer): TZoneInfo;
begin
  Result.UTCOffset := UtcOff[T];
  Result.DSTOffset := DstOff[T];
  Result.Abbreviation := Abbr[T];
end;

{ The local wall-clock epoch of a rule's transition in Year. }
function RuleEpoch(Kind: Char; M, W, D, Time, Year: Integer): Int64;
var
  Days: Int64;
  FirstWeekday, DaysInMonth, MonthDay: Integer;
begin
  case Kind of
    'J':
      begin
        { 1..365, February 29 never counted }
        Days := D;
        if (D >= 59) and IsLeap(Year) then
          Inc(Days);
        Result := (DaysFromCivil(Year, 1, 1) - 1 + Days) * 86400 + Time;
      end;
    'N':
      { CPython's zoneinfo counts n from December 31 of the year before
        (POSIX: from January 1); its result is followed }
      Result := (DaysFromCivil(Year, 1, 1) - 1 + D) * 86400 + Time;
  else
    begin
      { day D (0 = Sunday) of week W (5 = last) of month M }
      FirstWeekday := (DaysFromCivil(Year, M, 1) + 4) mod 7;   { 0 = Sunday }
      if FirstWeekday < 0 then
        Inc(FirstWeekday, 7);
      DaysInMonth := MonthDays[IsLeap(Year)][M];
      MonthDay := ((D - FirstWeekday) mod 7 + 7) mod 7 + 1;
      MonthDay := MonthDay + (W - 1) * 7;
      if MonthDay > DaysInMonth then
        Dec(MonthDay, 7);
      Result := DaysFromCivil(Year, M, MonthDay) * 86400 + Time;
    end;
  end;
end;

function TZoneData.RuleInfo(UTCSeconds: Int64): TZoneInfo;
var
  Y, Mo, Dd: Integer;
  StartT, EndT: Int64;
  InDst: Boolean;
begin
  if RuleIsFixed then
  begin
    Result.UTCOffset := StdOffset;
    Result.DSTOffset := 0;
    Result.Abbreviation := StdAbbr;
    Exit;
  end;
  { the year of the instant in UTC, as zoneinfo uses }
  CivilFromDays(FloorDiv(UTCSeconds, 86400), Y, Mo, Dd);
  StartT := RuleEpoch(StartRule.Kind, StartRule.M, StartRule.W, StartRule.D, StartRule.Time, Y) - StdOffset;
  EndT := RuleEpoch(EndRule.Kind, EndRule.M, EndRule.W, EndRule.D, EndRule.Time, Y) - DstOffsetRule;
  if StartT < EndT then
    InDst := (StartT <= UTCSeconds) and (UTCSeconds < EndT)
  else
    InDst := not ((EndT <= UTCSeconds) and (UTCSeconds < StartT));
  if InDst then
  begin
    Result.UTCOffset := DstOffsetRule;
    Result.DSTOffset := DstOffsetRule - StdOffset;
    Result.Abbreviation := DstAbbr;
  end
  else
  begin
    Result.UTCOffset := StdOffset;
    Result.DSTOffset := 0;
    Result.Abbreviation := StdAbbr;
  end;
end;

function TZoneData.RuleInfoLocal(LocalSeconds: Int64; Fold: Integer): TZoneInfo;
var
  Y, Mo, Dd: Integer;
  StartT, EndT, DstDiff: Int64;
  InDst: Boolean;
begin
  if RuleIsFixed then
    Exit(RuleInfo(0));
  CivilFromDays(FloorDiv(LocalSeconds, 86400), Y, Mo, Dd);
  StartT := RuleEpoch(StartRule.Kind, StartRule.M, StartRule.W, StartRule.D, StartRule.Time, Y);
  EndT := RuleEpoch(EndRule.Kind, EndRule.M, EndRule.W, EndRule.D, EndRule.Time, Y);
  DstDiff := DstOffsetRule - StdOffset;
  if (Fold = 1) = (DstDiff >= 0) then
    Dec(EndT, DstDiff)
  else
    Inc(StartT, DstDiff);
  if StartT < EndT then
    InDst := (StartT <= LocalSeconds) and (LocalSeconds < EndT)
  else
    InDst := not ((EndT <= LocalSeconds) and (LocalSeconds < StartT));
  if InDst then
  begin
    Result.UTCOffset := DstOffsetRule;
    Result.DSTOffset := DstDiff;
    Result.Abbreviation := DstAbbr;
  end
  else
  begin
    Result.UTCOffset := StdOffset;
    Result.DSTOffset := 0;
    Result.Abbreviation := StdAbbr;
  end;
end;

{ zoneinfo's _find_trans }
function TZoneData.InfoAtLocal(LocalSeconds: Int64; Fold: Integer): TZoneInfo;
var
  Lo, Hi, Mid, N: Integer;
  LT: array of Int64;
begin
  LT := TransLocal[Fold];
  N := Length(LT);
  if (N > 0) and (LocalSeconds < LT[0]) then
    Exit(TypeInfo(BeforeType));
  if (N = 0) or (LocalSeconds > LT[N - 1]) then
  begin
    if HasRule then
      Exit(RuleInfoLocal(LocalSeconds, Fold));
    if N > 0 then
      Exit(TypeInfo(TransIdx[N - 1]));
    Exit(TypeInfo(High(UtcOff)));
  end;
  Lo := 0;
  Hi := N - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if LT[Mid] <= LocalSeconds then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := TypeInfo(TransIdx[Lo]);
end;

function TZoneData.InfoAt(UTCSeconds: Int64): TZoneInfo;
var
  Lo, Hi, Mid, N: Integer;
begin
  N := Length(Trans);
  if (N >= 1) and (UTCSeconds < Trans[0]) then
    Exit(TypeInfo(BeforeType));
  if ((N = 0) or (UTCSeconds > Trans[N - 1])) and HasRule then
    Exit(RuleInfo(UTCSeconds));
  if N = 0 then
    Exit(TypeInfo(0));
  if UTCSeconds > Trans[N - 1] then
    Exit(TypeInfo(TransIdx[N - 1]));
  { the last transition at or before the instant }
  Lo := 0;
  Hi := N - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if Trans[Mid] <= UTCSeconds then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := TypeInfo(TransIdx[Lo]);
end;

{ ---- TTimeZone ---- }

function TTimeZone.IsUTC: Boolean;
begin
  Result := FData = nil;
end;

function TTimeZone.InfoAt(UTCSeconds: Int64): TZoneInfo;
begin
  if FData = nil then
  begin
    Result.UTCOffset := 0;
    Result.DSTOffset := 0;
    Result.Abbreviation := 'UTC';
  end
  else
    Result := FData.InfoAt(UTCSeconds);
end;

function TTimeZone.InfoAt(UTC: TDateTime): TZoneInfo;
begin
  Result := InfoAt(UnixSeconds(UTC));
end;

function TTimeZone.InfoAtLocal(LocalSeconds: Int64; Fold: Integer): TZoneInfo;
begin
  if FData = nil then
    Result := InfoAt(0)
  else
    Result := FData.InfoAtLocal(LocalSeconds, Fold);
end;

function TTimeZone.ToLocal(UTC: TDateTime): TDateTime;
begin
  Result := IncSecond(UTC, InfoAt(UTC).UTCOffset);
end;

{ ---- zone files ---- }

function ZoneInfoPath: string;
begin
  EnterCriticalSection(Lock);
  try
    Result := ZonePath;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

procedure SetZoneInfoPath(const Path: string);
begin
  EnterCriticalSection(Lock);
  try
    ZonePath := ExcludeTrailingPathDelimiter(Path);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

{ A zone name as zoneinfo accepts it: relative, without '..' parts. }
function ValidZoneName(const Name: string): Boolean;
var
  Part: string;
begin
  Result := (Name <> '') and (Name[1] <> '/') and (Pos(#0, Name) = 0);
  if Result then
    for Part in Name.Split(['/']) do
      if (Part = '') or (Part = '.') or (Part = '..') then
        Exit(False);
end;

function GetTimeZone(const Name: string): TTimeZone;
var
  I: Integer;
  FileName: string;
  Bytes: TBytes;
  F: TFileStream;
  Z: TZoneData;
begin
  Result := Default(TTimeZone);
  if Name = '' then
  begin
    Result.FName := 'UTC';
    Exit;
  end;
  if not ValidZoneName(Name) then
    raise EUnknownTimeZoneError.CreateFmt('Unknown timezone %s', [Name]);
  Result.FName := Name;
  EnterCriticalSection(Lock);
  try
    if Zones.Find(Name, I) then
    begin
      Result.FData := TZoneData(Zones.Objects[I]);
      Exit;
    end;
    FileName := ZonePath + '/' + Name;
    if not FileExists(FileName) or DirectoryExists(FileName) then
      raise EUnknownTimeZoneError.CreateFmt('Unknown timezone %s', [Name]);
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, F.Size);
      if Length(Bytes) > 0 then
        F.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      F.Free;
    end;
    try
      Z := LoadZone(Bytes);
    except
      on E: Exception do
        raise EUnknownTimeZoneError.CreateFmt('Unknown timezone %s (%s)', [Name, E.Message]);
    end;
    Zones.AddObject(Name, Z);
    Result.FData := Z;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function ReadFirstLine(const FileName: string): string;
var
  L: TStringList;
begin
  Result := '';
  if not FileExists(FileName) then
    Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    if L.Count > 0 then
      Result := Trim(L[0]);
  finally
    L.Free;
  end;
end;

function LocalTimeZoneName: string;
var
  TZ, Target, Line: string;
  P: Integer;
  L: TStringList;
  FileName: string;
begin
  { as babel.localtime on Unix: TZ; /etc/localtime's link target (after
    /zoneinfo/); /etc/timezone; ZONE= in /etc/sysconfig/clock or
    /etc/conf.d/clock; else UTC (where Babel raises LookupError) }
  TZ := GetEnvironmentVariable('TZ');
  if TZ <> '' then
  begin
    if TZ[1] = ':' then
      Delete(TZ, 1, 1);
    if ValidZoneName(TZ) then
      Exit(TZ);
  end;
  Target := fpReadLink('/etc/localtime');
  P := Pos('/zoneinfo/', Target);
  if P > 0 then
  begin
    Result := Copy(Target, P + Length('/zoneinfo/'), MaxInt);
    while (Result <> '') and (Result[1] = '/') do
      Delete(Result, 1, 1);
    if ValidZoneName(Result) and FileExists(ZoneInfoPath + '/' + Result) then
      Exit;
  end;
  Result := ReadFirstLine('/etc/timezone');
  if Result <> '' then
  begin
    P := Pos(' ', Result);
    if P > 0 then
      Result := Copy(Result, 1, P - 1);
    P := Pos('#', Result);
    if P > 0 then
      Result := Copy(Result, 1, P - 1);
    if ValidZoneName(Result) then
      Exit;
  end;
  for FileName in ['/etc/sysconfig/clock', '/etc/conf.d/clock'] do
    if FileExists(FileName) then
    begin
      L := TStringList.Create;
      try
        L.LoadFromFile(FileName);
        for Line in L do
        begin
          P := Pos('ZONE', Line);
          if (P > 0) and (Pos('"', Line) > P) then
          begin
            Result := Copy(Line, Pos('"', Line) + 1, MaxInt);
            P := Pos('"', Result);
            if P > 0 then
              Result := StringReplace(Copy(Result, 1, P - 1), ' ', '_', [rfReplaceAll]);
            if ValidZoneName(Result) then
              Exit;
          end;
        end;
      finally
        L.Free;
      end;
    end;
  Result := 'UTC';
end;

procedure FreeZones;
var
  I: Integer;
begin
  for I := 0 to Zones.Count - 1 do
    Zones.Objects[I].Free;
  Zones.Free;
end;

initialization
  InitCriticalSection(Lock);
  Zones := TStringList.Create;
  Zones.Sorted := True;
  Zones.CaseSensitive := True;
  ZonePath := GetEnvironmentVariable('TZDIR');
  if ZonePath = '' then
    ZonePath := '/usr/share/zoneinfo';
finalization
  FreeZones;
  DoneCriticalSection(Lock);
end.
