{ babel.core - locales and their data.

  A locale identifier names a language and optionally a script, a
  territory, a variant and a modifier: 'es_PE', 'zh_Hant_TW',
  'ca_ES_VALENCIA', 'de_DE@euro'. TLocale holds those parts and the
  locale's CLDR data (babel.localedata), with accessors for its parts
  (Languages, Territories, Months, ...).

  TLocale is a record: it is copied like a string and needs no freeing.
  A string converts to a TLocale implicitly (TLocale.Parse), so the
  functions of this library take one TLocale parameter and accept
  'es_PE' as well.

  A locale exists when its data unit is linked into the program
  (babel.cldr_es_PE for es_PE; babel.cldr_all for every generated
  locale). TLocale.Parse finds the closest linked locale: the identifier
  as given, then with aliases replaced and likely subtags
  added ('zh_TW' is zh_Hant_TW; 'und_AT' is de_AT).

  A missing name is ''. Identifiers are parsed as ASCII. A locale made
  with TLocale.Create in a case other than its data's ('ES') loads that
  data.

  Threading: everything here only reads shared data; any thread may call
  it. DefaultLocale reads environment variables. }
unit babel.core;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors, babel.localedata, babel.plural;

type
  EUnknownLocaleError = class(EBabelError)
  public
    Identifier: string;
    constructor CreateFor(const AIdentifier: string);
  end;

  { The parts of an identifier ('' when absent), as parse_locale returns
    them. }
  TLocaleParts = record
    Language, Territory, Script, Variant, Modifier: string;
  end;

  TLocaleAlias = record
    Alias, Identifier: string;
  end;
  TLocaleAliases = array of TLocaleAlias;

  TLocale = record
  private
    FLanguage, FTerritory, FScript, FVariant, FModifier: string;
    FData: TCLDRValue;
    function Need(const Key: string): TCLDRValue;
    function WeekData(const Key: string): Integer;
  public
    { Locale(language, territory, script, variant, modifier). Raises
      EUnknownLocaleError when no data of the identifier (or of the
      identifier without its modifier) is linked. }
    class function Create(const Language: string; const Territory: string = '';
      const Script: string = ''; const Variant: string = '';
      const Modifier: string = ''): TLocale; static;
    { The locale of an identifier. Raises EBabelValueError for a malformed
      or empty identifier and EUnknownLocaleError when no linked locale matches. }
    class function Parse(const Identifier: string; const Sep: string = '_';
      ResolveLikelySubtags: Boolean = True): TLocale; static;
    { The locale named by the environment (DefaultLocale).
      Raises EBabelTypeError when the environment names none. }
    class function Default(const Category: string = ''): TLocale; overload; static;
    class function Default(const Category: string; const Aliases: TLocaleAliases): TLocale; overload; static;
    { The best match of Preferred in Available (NegotiateLocale); False
      when nothing matches. }
    class function Negotiate(const Preferred, Available: array of string;
      out Locale: TLocale; const Sep: string = '_'): Boolean; overload; static;
    class function Negotiate(const Preferred, Available: array of string;
      const Aliases: TLocaleAliases; out Locale: TLocale; const Sep: string = '_'): Boolean; overload; static;

    class operator :=(const Identifier: string): TLocale;
    class operator =(const A, B: TLocale): Boolean;

    property Language: string read FLanguage;
    property Territory: string read FTerritory;
    property Script: string read FScript;
    property Variant: string read FVariant;
    property Modifier: string read FModifier;
    { The identifier: 'zh_Hant_TW', 'de_DE@euro'. }
    function ToString: string;
    { A description of the parts: "Locale('de', territory='DE')". }
    function Repr: string;
    { The locale's data, merged with what it inherits. }
    property Data: TCLDRValue read FData;

    { Names, in this locale or in InLocale. }
    function GetDisplayName: string; overload;
    function GetDisplayName(const InLocale: TLocale): string; overload;
    function GetLanguageName: string; overload;
    function GetLanguageName(const InLocale: TLocale): string; overload;
    function GetTerritoryName: string; overload;
    function GetTerritoryName(const InLocale: TLocale): string; overload;
    function GetScriptName: string; overload;
    function GetScriptName(const InLocale: TLocale): string; overload;
    function DisplayName: string;
    function LanguageName: string;
    function TerritoryName: string;
    function ScriptName: string;
    { The display name in English (needs en linked). }
    function EnglishName: string;

    { Maps of names: code -> name. }
    function Languages: TCLDRValue;
    function Scripts: TCLDRValue;
    function Territories: TCLDRValue;
    function Variants: TCLDRValue;
    { Numbers }
    function Currencies: TCLDRValue;          { currency_names }
    function CurrencySymbols: TCLDRValue;
    function NumberSymbols: TCLDRValue;       { numbering system -> symbol -> text }
    function OtherNumberingSystems: TCLDRValue;
    function DefaultNumberingSystem: string;
    function DecimalFormats: TCLDRValue;      { patterns are strings }
    function CompactDecimalFormats: TCLDRValue;
    function CurrencyFormats: TCLDRValue;
    function CompactCurrencyFormats: TCLDRValue;
    function PercentFormats: TCLDRValue;
    function ScientificFormats: TCLDRValue;
    { Calendar }
    function Periods: TCLDRValue;             { day_periods/stand-alone/wide, or empty }
    function DayPeriods: TCLDRValue;
    function DayPeriodRules: TCLDRValue;      { or empty }
    function Days: TCLDRValue;
    function Months: TCLDRValue;
    function Quarters: TCLDRValue;
    function Eras: TCLDRValue;
    function TimeZones: TCLDRValue;
    function MetaZones: TCLDRValue;
    function ZoneFormats: TCLDRValue;
    function FirstWeekDay: Integer;           { 0 = Monday }
    function WeekendStart: Integer;
    function WeekendEnd: Integer;
    function MinWeekDays: Integer;
    function DateFormats: TCLDRValue;
    function TimeFormats: TCLDRValue;
    function DatetimeFormats: TCLDRValue;
    function DatetimeSkeletons: TCLDRValue;
    function IntervalFormats: TCLDRValue;
    { Plural rules (the rule that always answers 'other' when the locale
      has none). }
    function PluralForm: TPluralRule;
    function OrdinalForm: TPluralRule;
    { Other }
    function ListPatterns: TCLDRValue;
    function MeasurementSystems: TCLDRValue;
    function CharacterOrder: string;          { 'left-to-right', ... }
    function TextDirection: string;           { 'ltr', 'rtl', 'ttb' }
    function UnitDisplayNames: TCLDRValue;
  end;

{ Language-only identifiers browsers send, mapped
  to a full identifier ('en' -> 'en_US', 'no' -> 'nb_NO'). }
function LocaleAliases: TLocaleAliases;

{ The parts of an identifier. Raises EBabelValueError for a malformed
  identifier. }
function ParseLocale(const Identifier: string; const Sep: string = '_'): TLocaleParts;
{ The parts joined (language, script, territory,
  variant), then '@modifier'. }
function GetLocaleIdentifier(const Parts: TLocaleParts; const Sep: string = '_'): string;
{ The first of the variables Category (when given),
  LANGUAGE, LC_ALL, LC_CTYPE and LANG that names a locale; '' when none
  does. 'C' and 'POSIX' mean en_US_POSIX; Aliases (default LocaleAliases;
  pass an empty array for none) map a whole value. }
function DefaultLocale(const Category: string = ''): string; overload;
function DefaultLocale(const Categories: array of string; const Aliases: TLocaleAliases): string; overload;
{ The first preferred identifier found in Available
  (ignoring case), or its alias, or its language alone; '' when none. }
function NegotiateLocale(const Preferred, Available: array of string;
  const Sep: string = '_'): string; overload;
function NegotiateLocale(const Preferred, Available: array of string;
  const Aliases: TLocaleAliases; const Sep: string = '_'): string; overload;
{ The CLDR version of the data and a value of the global data, from
  babel.localedata. }
function GetCLDRVersion: string;
function GetGlobal(const Key: string): TCLDRValue;

implementation

uses
  babel.cldr_global;

const
  AliasTable: array[0..38] of TLocaleAlias = (
    (Alias: 'ar'; Identifier: 'ar_SY'), (Alias: 'bg'; Identifier: 'bg_BG'),
    (Alias: 'bs'; Identifier: 'bs_BA'), (Alias: 'ca'; Identifier: 'ca_ES'),
    (Alias: 'cs'; Identifier: 'cs_CZ'), (Alias: 'da'; Identifier: 'da_DK'),
    (Alias: 'de'; Identifier: 'de_DE'), (Alias: 'el'; Identifier: 'el_GR'),
    (Alias: 'en'; Identifier: 'en_US'), (Alias: 'es'; Identifier: 'es_ES'),
    (Alias: 'et'; Identifier: 'et_EE'), (Alias: 'fa'; Identifier: 'fa_IR'),
    (Alias: 'fi'; Identifier: 'fi_FI'), (Alias: 'fr'; Identifier: 'fr_FR'),
    (Alias: 'gl'; Identifier: 'gl_ES'), (Alias: 'he'; Identifier: 'he_IL'),
    (Alias: 'hu'; Identifier: 'hu_HU'), (Alias: 'id'; Identifier: 'id_ID'),
    (Alias: 'is'; Identifier: 'is_IS'), (Alias: 'it'; Identifier: 'it_IT'),
    (Alias: 'ja'; Identifier: 'ja_JP'), (Alias: 'km'; Identifier: 'km_KH'),
    (Alias: 'ko'; Identifier: 'ko_KR'), (Alias: 'lt'; Identifier: 'lt_LT'),
    (Alias: 'lv'; Identifier: 'lv_LV'), (Alias: 'mk'; Identifier: 'mk_MK'),
    (Alias: 'nl'; Identifier: 'nl_NL'), (Alias: 'nn'; Identifier: 'nn_NO'),
    (Alias: 'no'; Identifier: 'nb_NO'), (Alias: 'pl'; Identifier: 'pl_PL'),
    (Alias: 'pt'; Identifier: 'pt_PT'), (Alias: 'ro'; Identifier: 'ro_RO'),
    (Alias: 'ru'; Identifier: 'ru_RU'), (Alias: 'sk'; Identifier: 'sk_SK'),
    (Alias: 'sl'; Identifier: 'sl_SI'), (Alias: 'sv'; Identifier: 'sv_SE'),
    (Alias: 'th'; Identifier: 'th_TH'), (Alias: 'tr'; Identifier: 'tr_TR'),
    (Alias: 'uk'; Identifier: 'uk_UA'));

constructor EUnknownLocaleError.CreateFor(const AIdentifier: string);
begin
  inherited CreateFmt('unknown locale ''%s''', [AIdentifier]);
  Identifier := AIdentifier;
end;

function LocaleAliases: TLocaleAliases;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AliasTable));
  for I := 0 to High(AliasTable) do
    Result[I] := AliasTable[I];
end;

function FindAlias(const Aliases: TLocaleAliases; const Key: string; out Value: string): Boolean;
var
  A: TLocaleAlias;
begin
  for A in Aliases do
    if A.Alias = Key then
    begin
      Value := A.Identifier;
      Exit(True);
    end;
  Value := '';
  Result := False;
end;

function GetCLDRVersion: string;
begin
  Result := babel.localedata.GetCLDRVersion;
end;

function GetGlobal(const Key: string): TCLDRValue;
begin
  Result := babel.localedata.GetGlobal(Key);
end;

{ ---- identifiers ---- }

function IsAlpha(const S: string): Boolean;
var
  C: Char;
begin
  if S = '' then
    Exit(False);
  for C in S do
    if not (C in ['A'..'Z', 'a'..'z']) then
      Exit(False);
  Result := True;
end;

function IsDigits(const S: string): Boolean;
var
  C: Char;
begin
  if S = '' then
    Exit(False);
  for C in S do
    if not (C in ['0'..'9']) then
      Exit(False);
  Result := True;
end;

function TitleCase(const S: string): string;
begin
  Result := LowerCase(S);
  if Result <> '' then
    Result[1] := UpCase(Result[1]);
end;

function SplitBy(const S, Sep: string): TStringArray;
var
  P, Start: Integer;
begin
  Result := nil;
  if Sep = '' then
    raise EBabelValueError.Create('empty separator');
  Start := 1;
  repeat
    P := Pos(Sep, S, Start);
    SetLength(Result, Length(Result) + 1);
    if P = 0 then
      Result[High(Result)] := Copy(S, Start, MaxInt)
    else
    begin
      Result[High(Result)] := Copy(S, Start, P - Start);
      Start := P + Length(Sep);
    end;
  until P = 0;
end;

function ParseLocale(const Identifier: string; const Sep: string): TLocaleParts;
var
  Id: string;
  Parts: TStringArray;
  First, Last, P: Integer;
begin
  Result := Default(TLocaleParts);
  if Identifier = '' then
    raise EBabelValueError.Create('empty locale identifier');
  Id := Identifier;
  P := Pos('@', Id);
  if P > 0 then
  begin
    Result.Modifier := Copy(Id, P + 1, MaxInt);
    Id := Copy(Id, 1, P - 1);
  end;
  P := Pos('.', Id);
  if P > 0 then
    Id := Copy(Id, 1, P - 1);   { the charset: 'de_DE.UTF-8' }
  Parts := SplitBy(Id, Sep);
  First := 0;                  { parts[First..Last] remain }
  Last := High(Parts);
  Result.Language := LowerCase(Parts[First]);
  Inc(First);
  if not IsAlpha(Result.Language) then
    raise EBabelValueError.CreateFmt('expected only letters, got ''%s''', [Result.Language]);
  if (First <= Last) and (Length(Parts[First]) = 4) and IsAlpha(Parts[First]) then
  begin
    Result.Script := TitleCase(Parts[First]);
    Inc(First);
  end;
  if First <= Last then
  begin
    if (Length(Parts[First]) = 2) and IsAlpha(Parts[First]) then
    begin
      Result.Territory := UpperCase(Parts[First]);
      Inc(First);
    end
    else if (Length(Parts[First]) = 3) and IsDigits(Parts[First]) then
    begin
      Result.Territory := Parts[First];
      Inc(First);
    end;
  end;
  { the variant: tested on the first remaining part, taken from the last }
  if (First <= Last) and (
       ((Length(Parts[First]) = 4) and (Parts[First][1] in ['0'..'9'])) or
       ((Length(Parts[First]) >= 5) and (Parts[First][1] in ['A'..'Z', 'a'..'z']))) then
  begin
    Result.Variant := UpperCase(Parts[Last]);
    Dec(Last);
  end;
  if First <= Last then
    raise EBabelValueError.CreateFmt('''%s'' is not a valid locale identifier', [Id]);
end;

function GetLocaleIdentifier(const Parts: TLocaleParts; const Sep: string): string;
var
  S: string;
begin
  Result := '';
  for S in [Parts.Language, Parts.Script, Parts.Territory, Parts.Variant] do
    if S <> '' then
    begin
      if Result <> '' then
        Result := Result + Sep;
      Result := Result + S;
    end;
  if Parts.Modifier <> '' then
    Result := Result + '@' + Parts.Modifier;
end;

function DefaultLocale(const Category: string): string;
begin
  if Category = '' then
    Result := DefaultLocale([], LocaleAliases)
  else
    Result := DefaultLocale([Category], LocaleAliases);
end;

function DefaultLocale(const Categories: array of string; const Aliases: TLocaleAliases): string;
var
  Names: array of string;
  Name, Value, Mapped, Base: string;
  I: Integer;
begin
  Names := nil;
  for Name in Categories do
  begin
    SetLength(Names, Length(Names) + 1);
    Names[High(Names)] := Name;
  end;
  for Name in ['LANGUAGE', 'LC_ALL', 'LC_CTYPE', 'LANG'] do
  begin
    SetLength(Names, Length(Names) + 1);
    Names[High(Names)] := Name;
  end;
  for Name in Names do
  begin
    if Name = '' then
      Continue;
    Value := GetEnvironmentVariable(Name);
    if Value = '' then
      Continue;
    if (Name = 'LANGUAGE') and (Pos(':', Value) > 0) then
      Value := Copy(Value, 1, Pos(':', Value) - 1);
    Base := Value;
    I := Pos('.', Base);
    if I > 0 then
      Base := Copy(Base, 1, I - 1);
    if (Base = 'C') or (Base = 'POSIX') then
      Value := 'en_US_POSIX'
    else if FindAlias(Aliases, Value, Mapped) then
      Value := Mapped;
    try
      Exit(GetLocaleIdentifier(ParseLocale(Value)));
    except
      on EBabelValueError do ;
    end;
  end;
  Result := '';
end;

function NegotiateLocale(const Preferred, Available: array of string; const Sep: string): string;
begin
  Result := NegotiateLocale(Preferred, Available, LocaleAliases, Sep);
end;

function NegotiateLocale(const Preferred, Available: array of string;
  const Aliases: TLocaleAliases; const Sep: string): string;
var
  Avail: array of string;
  A, Loc, LL, Alias: string;
  Parts: TStringArray;

  function InAvail(const S: string): Boolean;
  var
    X: string;
  begin
    for X in Avail do
      if X = S then
        Exit(True);
    Result := False;
  end;

begin
  Avail := nil;
  for A in Available do
    if A <> '' then
    begin
      SetLength(Avail, Length(Avail) + 1);
      Avail[High(Avail)] := LowerCase(A);
    end;
  for Loc in Preferred do
  begin
    LL := LowerCase(Loc);
    if InAvail(LL) then
      Exit(Loc);
    if FindAlias(Aliases, LL, Alias) and (Alias <> '') then
    begin
      Alias := StringReplace(Alias, '_', Sep, [rfReplaceAll]);
      if InAvail(LowerCase(Alias)) then
        Exit(Alias);
    end;
    Parts := SplitBy(Loc, Sep);
    if (Length(Parts) > 1) and InAvail(LowerCase(Parts[0])) then
      Exit(Parts[0]);
  end;
  Result := '';
end;

{ ---- TLocale ---- }

{ An empty TLocale. Inside TLocale's methods the name Default means the
  method TLocale.Default, not the Default() intrinsic. }
function EmptyLocale: TLocale;
begin
  Result := Default(TLocale);
end;

class function TLocale.Create(const Language, Territory, Script, Variant,
  Modifier: string): TLocale;
var
  Parts: TLocaleParts;
  Id, DataId: string;
begin
  Result := EmptyLocale;
  Result.FLanguage := Language;
  Result.FTerritory := Territory;
  Result.FScript := Script;
  Result.FVariant := Variant;
  Result.FModifier := Modifier;
  Parts.Language := Language;
  Parts.Territory := Territory;
  Parts.Script := Script;
  Parts.Variant := Variant;
  Parts.Modifier := Modifier;
  Id := GetLocaleIdentifier(Parts);
  if LocaleDataExists(Id) then
    DataId := Id
  else
  begin
    DataId := Copy(Id, 1, Pos('@', Id + '@') - 1);
    if not LocaleDataExists(DataId) then
      raise EUnknownLocaleError.CreateFor(Id);
  end;
  Result.FData := LoadLocaleData(DataId);
end;

function TryCreate(const Language, Territory, Script, Variant, Modifier: string;
  out Locale: TLocale): Boolean;
begin
  try
    Locale := TLocale.Create(Language, Territory, Script, Variant, Modifier);
    Result := True;
  except
    on EUnknownLocaleError do
    begin
      Locale := Default(TLocale);
      Result := False;
    end;
  end;
end;

{ The locale of the parts, else of the language and territory alone. }
function TryCreateReducing(const P: TLocaleParts; out Locale: TLocale): Boolean;
begin
  Result := TryCreate(P.Language, P.Territory, P.Script, P.Variant, P.Modifier, Locale) or
    TryCreate(P.Language, P.Territory, '', '', '', Locale);
end;

function LookupStr(const Key, Name: string; out Value: string): Boolean;
var
  V: TCLDRValue;
begin
  V := GetGlobal(Key).Get(Name);
  Result := (V <> nil) and (V.Kind = ckString);
  if Result then
    Value := V.AsString
  else
    Value := '';
end;

class function TLocale.Parse(const Identifier: string; const Sep: string;
  ResolveLikelySubtags: Boolean): TLocale;
var
  Parts, Parts2: TLocaleParts;
  InputId, NewId, Likely, S: string;
  V: TCLDRValue;
begin
  if Identifier = '' then
    raise EBabelValueError.Create('Empty locale identifier value: ''''');
  Parts := ParseLocale(Identifier, Sep);
  InputId := GetLocaleIdentifier(Parts);
  if TryCreate(Parts.Language, Parts.Territory, Parts.Script, Parts.Variant,
    Parts.Modifier, Result) then
    Exit;
  if not ResolveLikelySubtags then
    raise EUnknownLocaleError.CreateFor(InputId);

  { Aliases (territory_aliases holds lists: the first replacement). }
  if LookupStr('language_aliases', Parts.Language, S) then
    Parts.Language := S;
  V := GetGlobal('territory_aliases').Get(Parts.Territory);
  if (V <> nil) and (V.Kind = ckList) and (V.Count > 0) then
    Parts.Territory := V.Items(0).AsString;
  if LookupStr('script_aliases', Parts.Script, S) then
    Parts.Script := S;
  if LookupStr('variant_aliases', Parts.Variant, S) then
    Parts.Variant := S;
  if Parts.Territory = 'ZZ' then
    Parts.Territory := '';
  if Parts.Script = 'Zzzz' then
    Parts.Script := '';

  NewId := GetLocaleIdentifier(Parts);
  if LookupStr('likely_subtags', NewId, Likely) then
    if TryCreateReducing(ParseLocale(Likely), Result) then
      Exit;
  if LookupStr('likely_subtags', Parts.Language, Likely) then
  begin
    Parts2 := ParseLocale(Likely);
    Parts2.Territory := Parts.Territory;
    if TryCreateReducing(Parts2, Result) then
      Exit;
  end;
  raise EUnknownLocaleError.CreateFor(InputId);
end;

class function TLocale.Default(const Category: string): TLocale;
var
  Id: string;
begin
  Id := DefaultLocale(Category);
  if Id = '' then
    raise EBabelTypeError.Create('Empty locale identifier value: None');
  Result := Parse(Id);
end;

class function TLocale.Default(const Category: string; const Aliases: TLocaleAliases): TLocale;
var
  Id: string;
begin
  if Category = '' then
    Id := DefaultLocale([], Aliases)
  else
    Id := DefaultLocale([Category], Aliases);
  if Id = '' then
    raise EBabelTypeError.Create('Empty locale identifier value: None');
  Result := Parse(Id);
end;

class function TLocale.Negotiate(const Preferred, Available: array of string;
  out Locale: TLocale; const Sep: string): Boolean;
begin
  Result := Negotiate(Preferred, Available, LocaleAliases, Locale, Sep);
end;

class function TLocale.Negotiate(const Preferred, Available: array of string;
  const Aliases: TLocaleAliases; out Locale: TLocale; const Sep: string): Boolean;
var
  Id: string;
begin
  Locale := EmptyLocale;
  Id := NegotiateLocale(Preferred, Available, Aliases, Sep);
  Result := Id <> '';
  if Result then
    Locale := Parse(Id, Sep);
end;

class operator TLocale.:=(const Identifier: string): TLocale;
begin
  Result := TLocale.Parse(Identifier);
end;

class operator TLocale.=(const A, B: TLocale): Boolean;
begin
  Result := (A.FLanguage = B.FLanguage) and (A.FTerritory = B.FTerritory) and
    (A.FScript = B.FScript) and (A.FVariant = B.FVariant) and (A.FModifier = B.FModifier);
end;

function TLocale.ToString: string;
var
  P: TLocaleParts;
begin
  P.Language := FLanguage;
  P.Territory := FTerritory;
  P.Script := FScript;
  P.Variant := FVariant;
  P.Modifier := FModifier;
  Result := GetLocaleIdentifier(P);
end;

function TLocale.Repr: string;
begin
  Result := 'Locale(''' + FLanguage + '''';
  if FTerritory <> '' then Result := Result + ', territory=''' + FTerritory + '''';
  if FScript <> '' then Result := Result + ', script=''' + FScript + '''';
  if FVariant <> '' then Result := Result + ', variant=''' + FVariant + '''';
  if FModifier <> '' then Result := Result + ', modifier=''' + FModifier + '''';
  Result := Result + ')';
end;

function TLocale.Need(const Key: string): TCLDRValue;
begin
  if FData = nil then
    raise EBabelError.Create('TLocale has no data (not made by Create or Parse)');
  Result := FData.Get(Key);
  if Result = nil then
    raise EBabelKeyError.CreateFmt('locale %s has no data ''%s''', [ToString, Key]);
end;

function TLocale.WeekData(const Key: string): Integer;
var
  V: TCLDRValue;
begin
  V := Need('week_data').Get(Key);
  if V = nil then
    raise EBabelKeyError.CreateFmt('locale %s has no week_data ''%s''', [ToString, Key]);
  Result := V.AsInteger;
end;

function TLocale.GetDisplayName: string;
begin
  Result := GetDisplayName(Self);
end;

function TLocale.GetDisplayName(const InLocale: TLocale): string;
var
  Details: string;

  procedure AddDetail(const S: string);
  begin
    if S = '' then
      Exit;
    if Details <> '' then
      Details := Details + ', ';
    Details := Details + S;
  end;

begin
  Result := InLocale.Languages.Str(FLanguage);
  if (Result <> '') and ((FTerritory <> '') or (FScript <> '') or (FVariant <> '')) then
  begin
    Details := '';
    if FScript <> '' then
      AddDetail(InLocale.Scripts.Str(FScript));
    if FTerritory <> '' then
      AddDetail(InLocale.Territories.Str(FTerritory));
    if FVariant <> '' then
      AddDetail(InLocale.Variants.Str(FVariant));
    if FModifier <> '' then
      AddDetail(FModifier);
    if Details <> '' then
      Result := Result + ' (' + Details + ')';
  end;
end;

function TLocale.GetLanguageName: string;
begin
  Result := GetLanguageName(Self);
end;

function TLocale.GetLanguageName(const InLocale: TLocale): string;
begin
  Result := InLocale.Languages.Str(FLanguage);
end;

function TLocale.GetTerritoryName: string;
begin
  Result := GetTerritoryName(Self);
end;

function TLocale.GetTerritoryName(const InLocale: TLocale): string;
begin
  Result := InLocale.Territories.Str(FTerritory);
end;

function TLocale.GetScriptName: string;
begin
  Result := GetScriptName(Self);
end;

function TLocale.GetScriptName(const InLocale: TLocale): string;
begin
  Result := InLocale.Scripts.Str(FScript);
end;

function TLocale.DisplayName: string;
begin
  Result := GetDisplayName(Self);
end;

function TLocale.LanguageName: string;
begin
  Result := GetLanguageName(Self);
end;

function TLocale.TerritoryName: string;
begin
  Result := GetTerritoryName(Self);
end;

function TLocale.ScriptName: string;
begin
  Result := GetScriptName(Self);
end;

function TLocale.EnglishName: string;
begin
  Result := GetDisplayName(TLocale.Create('en'));
end;

function TLocale.Languages: TCLDRValue; begin Result := Need('languages'); end;
function TLocale.Scripts: TCLDRValue; begin Result := Need('scripts'); end;
function TLocale.Territories: TCLDRValue; begin Result := Need('territories'); end;
function TLocale.Variants: TCLDRValue; begin Result := Need('variants'); end;
function TLocale.Currencies: TCLDRValue; begin Result := Need('currency_names'); end;
function TLocale.CurrencySymbols: TCLDRValue; begin Result := Need('currency_symbols'); end;
function TLocale.NumberSymbols: TCLDRValue; begin Result := Need('number_symbols'); end;
function TLocale.OtherNumberingSystems: TCLDRValue; begin Result := Need('numbering_systems'); end;
function TLocale.DefaultNumberingSystem: string; begin Result := Need('default_numbering_system').AsString; end;
function TLocale.DecimalFormats: TCLDRValue; begin Result := Need('decimal_formats'); end;
function TLocale.CompactDecimalFormats: TCLDRValue; begin Result := Need('compact_decimal_formats'); end;
function TLocale.CurrencyFormats: TCLDRValue; begin Result := Need('currency_formats'); end;
function TLocale.CompactCurrencyFormats: TCLDRValue; begin Result := Need('compact_currency_formats'); end;
function TLocale.PercentFormats: TCLDRValue; begin Result := Need('percent_formats'); end;
function TLocale.ScientificFormats: TCLDRValue; begin Result := Need('scientific_formats'); end;

function TLocale.Periods: TCLDRValue;
begin
  Result := Need('day_periods').Path(['stand-alone', 'wide']);
  if Result = nil then
    Result := EmptyCLDRMap;
end;

function TLocale.DayPeriods: TCLDRValue; begin Result := Need('day_periods'); end;

function TLocale.DayPeriodRules: TCLDRValue;
begin
  Result := FData.Get('day_period_rules');
  if Result = nil then
    Result := EmptyCLDRMap;
end;

function TLocale.Days: TCLDRValue; begin Result := Need('days'); end;
function TLocale.Months: TCLDRValue; begin Result := Need('months'); end;
function TLocale.Quarters: TCLDRValue; begin Result := Need('quarters'); end;
function TLocale.Eras: TCLDRValue; begin Result := Need('eras'); end;
function TLocale.TimeZones: TCLDRValue; begin Result := Need('time_zones'); end;
function TLocale.MetaZones: TCLDRValue; begin Result := Need('meta_zones'); end;
function TLocale.ZoneFormats: TCLDRValue; begin Result := Need('zone_formats'); end;
function TLocale.FirstWeekDay: Integer; begin Result := WeekData('first_day'); end;
function TLocale.WeekendStart: Integer; begin Result := WeekData('weekend_start'); end;
function TLocale.WeekendEnd: Integer; begin Result := WeekData('weekend_end'); end;
function TLocale.MinWeekDays: Integer; begin Result := WeekData('min_days'); end;
function TLocale.DateFormats: TCLDRValue; begin Result := Need('date_formats'); end;
function TLocale.TimeFormats: TCLDRValue; begin Result := Need('time_formats'); end;
function TLocale.DatetimeFormats: TCLDRValue; begin Result := Need('datetime_formats'); end;
function TLocale.DatetimeSkeletons: TCLDRValue; begin Result := Need('datetime_skeletons'); end;
function TLocale.IntervalFormats: TCLDRValue; begin Result := Need('interval_formats'); end;

function RuleFromData(V: TCLDRValue): TPluralRule;
var
  Items: array of TPluralRuleItem;
  I: Integer;
begin
  if V = nil then
    Exit(TPluralRule.Empty);
  Items := nil;
  SetLength(Items, V.Count);
  for I := 0 to V.Count - 1 do
  begin
    Items[I].Tag := V.Items(I).Items(0).AsString;
    Items[I].Expr := V.Items(I).Items(1).AsString;
  end;
  Result := TPluralRule.Create(Items);
end;

function TLocale.PluralForm: TPluralRule;
begin
  Result := RuleFromData(FData.Get('plural_form'));
end;

function TLocale.OrdinalForm: TPluralRule;
begin
  Result := RuleFromData(FData.Get('ordinal_form'));
end;

function TLocale.ListPatterns: TCLDRValue; begin Result := Need('list_patterns'); end;
function TLocale.MeasurementSystems: TCLDRValue; begin Result := Need('measurement_systems'); end;
function TLocale.CharacterOrder: string; begin Result := Need('character_order').AsString; end;

function TLocale.TextDirection: string;
var
  W: string;
begin
  Result := '';
  for W in SplitBy(CharacterOrder, '-') do
    if W <> '' then
      Result := Result + W[1];
end;

function TLocale.UnitDisplayNames: TCLDRValue; begin Result := Need('unit_display_names'); end;

end.
