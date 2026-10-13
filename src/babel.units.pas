{ babel.units - measurement units ('12 kilometers', '3 km/h').

  FormatUnit(12, 'length-kilometer', 'en') gives '12 kilometers';
  FormatUnit(12, 'kilometer', 'es', UnitOptions.WithLength('short'))
  gives '12 km'; FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'en')
  gives '150 kilometers per hour'.

  A unit is CLDR's id with its category ('length-kilometer') or the end of
  one made of whole components ('kilometer', 'kilometer-per-hour'): the
  shortest id equal to it or ending with '-' and it is taken; a fragment
  that ends two ids of that length ('mass': earth-mass, solar-mass) is
  ambiguous and matches none. Lengths: 'long' (default), 'short',
  'narrow'; any other raises EBabelValueError. A value already formatted
  goes to FormatUnitText and FormatCompoundUnitText (TDecimal converts
  from strings, so an overload taking a string would be ambiguous); such
  a value is used as given, also '1' in a denominator.

  The plural form is that of the number as shown ('1.0' shows '1': '1
  meter'); a missing plural form takes the 'other' pattern; what the long
  and narrow lengths lack comes from the short one (CLDR's root
  aliases).

  Threading: everything here only reads shared data. }
unit babel.units;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  babel.errors, babel.decimal, babel.core;

type
  EUnknownUnitError = class(EBabelValueError);   { a unit the locale does not have }

  TUnitOptions = record
    Length: string;           { 'long' (default), 'short' or 'narrow' }
    Format: string;           { the number pattern; '' = the locale's }
    NumberingSystem: string;  { 'latn' (default), 'default' or a system }
    function WithLength(const Value: string): TUnitOptions;
    function WithFormat(const Value: string): TUnitOptions;
    function WithNumberingSystem(const Value: string): TUnitOptions;
  end;

function UnitOptions: TUnitOptions;

{ The unit's display name ('kilometers', 'km'); '' when the locale has
  none. Raises EUnknownUnitError for an unknown unit. }
function GetUnitName(const MeasurementUnit: string; const Locale: TLocale;
  const Length: string = 'long'): string;
{ The qualified id of a unit ('length-kilometer' for 'kilometer'); '' when
  unknown or ambiguous. }
function FindUnitPattern(const UnitId: string; const Locale: TLocale): string;

function FormatUnit(const Value: TDecimal; const MeasurementUnit: string;
  const Locale: TLocale): string; overload;
function FormatUnit(const Value: TDecimal; const MeasurementUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string; overload;
{ A value already formatted, taken as singular ('one'). }
function FormatUnitText(const FormattedValue, MeasurementUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string;

{ Numerator per denominator ('150 kilometers per hour', '12 kg/m'): the
  compound unit when the locale has one (kilometer-per-hour) and the
  denominator is 1, else the locale's per pattern. A unit may be '' (a
  bare number). }
function FormatCompoundUnit(const NumeratorValue: TDecimal; const NumeratorUnit: string;
  const DenominatorValue: TDecimal; const DenominatorUnit: string;
  const Locale: TLocale): string; overload;
function FormatCompoundUnit(const NumeratorValue: TDecimal; const NumeratorUnit: string;
  const DenominatorValue: TDecimal; const DenominatorUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string; overload;
{ The same with both values already formatted. }
function FormatCompoundUnitText(const NumeratorValue, NumeratorUnit, DenominatorValue,
  DenominatorUnit: string; const Locale: TLocale; const Options: TUnitOptions): string;

implementation

uses
  SysUtils, babel.localedata, babel.strutils, babel.numbers;

function UnitOptions: TUnitOptions;
begin
  Result := Default(TUnitOptions);
  Result.Length := 'long';
  Result.NumberingSystem := 'latn';
end;

function TUnitOptions.WithLength(const Value: string): TUnitOptions;
begin
  Result := Self;
  Result.Length := Value;
end;

function TUnitOptions.WithFormat(const Value: string): TUnitOptions;
begin
  Result := Self;
  Result.Format := Value;
end;

function TUnitOptions.WithNumberingSystem(const Value: string): TUnitOptions;
begin
  Result := Self;
  Result.NumberingSystem := Value;
end;

function NeedKey(const Locale: TLocale; const Key: string): TCLDRValue;
begin
  Result := Locale.Data.Get(Key);
  if Result = nil then
    raise EBabelKeyError.Create(Key);
end;

function UnitPatterns(const Locale: TLocale): TCLDRValue;
begin
  Result := NeedKey(Locale, 'unit_patterns');
end;

function FindUnitPattern(const UnitId: string; const Locale: TLocale): string;
var
  Patterns: TCLDRValue;
  I, Best: Integer;
  Key, Suffix: string;
  Tie: Boolean;
begin
  Patterns := UnitPatterns(Locale);
  if (UnitId = '') or Patterns.Has(UnitId) then
  begin
    if UnitId = '' then
      Exit('');
    Exit(UnitId);
  end;
  { the shortest id that ends with '-' + UnitId; none when two have that
    length }
  Suffix := '-' + UnitId;
  Result := '';
  Best := MaxInt;
  Tie := False;
  for I := 0 to Patterns.Count - 1 do
  begin
    Key := Patterns.Keys(I).AsString;
    if (System.Length(Key) > System.Length(Suffix)) and
       (Copy(Key, System.Length(Key) - System.Length(Suffix) + 1, MaxInt) = Suffix) then
    begin
      if System.Length(Key) < Best then
      begin
        Result := Key;
        Best := System.Length(Key);
        Tie := False;
      end
      else if System.Length(Key) = Best then
        Tie := True;
    end;
  end;
  if Tie then
    Result := '';
end;

(* The lengths to look a unit's data up in: the one asked for, then
  short, which CLDR's root aliases long and narrow to (de's long g-force
  is its short 'G'). *)
function LengthChain(const Length: string): TStringArray;
begin
  if Length = 'short' then
    Result := ['short']
  else
    Result := [Length, 'short'];
end;

procedure CheckLength(const Length: string);
begin
  if (Length <> 'long') and (Length <> 'short') and (Length <> 'narrow') then
    raise EBabelValueError.CreateFmt('Invalid unit length ''%s'' (long, short or narrow)', [Length]);
end;

(* The unit's entry Key (a plural form, 'per') in the first length of the
  chain that has it; '' when none has. *)
function UnitEntry(const Locale: TLocale; const QUnit, Length, Key: string): string;
var
  L: string;
  V: TCLDRValue;
begin
  V := UnitPatterns(Locale).Get(QUnit);
  if V <> nil then
    for L in LengthChain(Length) do
      if (V.Get(L) <> nil) and V.Get(L).Has(Key) then
        Exit(V.Get(L).Str(Key));
  Result := '';
end;

function UnknownUnit(const MeasurementUnit: string; const Locale: TLocale): EUnknownUnitError;
begin
  Result := EUnknownUnitError.CreateFmt('%s is not a known unit in %s', [MeasurementUnit, Locale.ToString]);
end;

function GetUnitName(const MeasurementUnit: string; const Locale: TLocale; const Length: string): string;
var
  QUnit, L: string;
  Names: TCLDRValue;
begin
  CheckLength(Length);
  QUnit := FindUnitPattern(MeasurementUnit, Locale);
  if QUnit = '' then
    raise UnknownUnit(MeasurementUnit, Locale);
  Names := NeedKey(Locale, 'unit_display_names').Get(QUnit);
  Result := '';
  if Names <> nil then
    for L in LengthChain(Length) do
      if Names.Has(L) then
        Exit(Names.Str(L));
end;

{ format_unit with the value formatted and its plural form. }
function ApplyUnit(const FormattedValue, PluralForm, MeasurementUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string;
var
  QUnit, Name, Pattern: string;
begin
  CheckLength(Options.Length);
  QUnit := FindUnitPattern(MeasurementUnit, Locale);
  if QUnit = '' then
    raise UnknownUnit(MeasurementUnit, Locale);
  { the plural form's pattern, else the 'other' one (CLDR's fallback for
    a missing plural form) }
  Pattern := UnitEntry(Locale, QUnit, Options.Length, PluralForm);
  if Pattern = '' then
    Pattern := UnitEntry(Locale, QUnit, Options.Length, 'other');
  if Pattern <> '' then
    Exit(FormatPlaceholders(Pattern, [FormattedValue]));
  Name := GetUnitName(MeasurementUnit, Locale, Options.Length);
  if Name = '' then
    Name := MeasurementUnit;
  Result := FormattedValue + ' ' + Name;
end;

function NumberOptionsOf(const Options: TUnitOptions): TNumberOptions;
begin
  Result := NumberOptions.WithFormat(Options.Format).WithNumberingSystem(Options.NumberingSystem);
end;

function FormatUnit(const Value: TDecimal; const MeasurementUnit: string; const Locale: TLocale): string;
begin
  Result := FormatUnit(Value, MeasurementUnit, Locale, UnitOptions);
end;

function FormatUnit(const Value: TDecimal; const MeasurementUnit: string; const Locale: TLocale;
  const Options: TUnitOptions): string;
var
  Formatted: string;
  Shown: TDecimal;
begin
  CheckLength(Options.Length);
  if FindUnitPattern(MeasurementUnit, Locale) = '' then
    raise UnknownUnit(MeasurementUnit, Locale);
  { the plural form of the number as shown ('1.0' is shown '1': '1
    meter') }
  Formatted := FormatDecimalShown(Value, Locale, NumberOptionsOf(Options), Shown);
  Result := ApplyUnit(Formatted, Locale.PluralForm.Evaluate(Shown), MeasurementUnit, Locale, Options);
end;

function FormatUnitText(const FormattedValue, MeasurementUnit: string; const Locale: TLocale;
  const Options: TUnitOptions): string;
begin
  Result := ApplyUnit(FormattedValue, 'one', MeasurementUnit, Locale, Options);
end;

{ The compound unit of the two units ('speed-kilometer-per-hour'); ''
  when the locale has none. }
function FindCompoundUnit(const NumeratorUnit, DenominatorUnit: string; const Locale: TLocale): string;
var
  N, D: string;
begin
  N := FindUnitPattern(NumeratorUnit, Locale);
  D := FindUnitPattern(DenominatorUnit, Locale);
  if (N = '') or (D = '') then
    Exit('');
  N := Copy(N, Pos('-', N) + 1, MaxInt);
  D := Copy(D, Pos('-', D) + 1, MaxInt);
  Result := FindUnitPattern(N + '-per-' + D, Locale);
end;

type
  { a value of format_compound_unit: a number or preformatted text }
  TQuantity = record
    IsText: Boolean;
    Text: string;
    Number: TDecimal;
  end;

function IsOne(const Q: TQuantity): Boolean;
begin
  Result := not Q.IsText and Q.Number.IsFinite and (Q.Number.CompareInt(1) = 0);
end;

function CompoundUnit(const Num: TQuantity; const NumeratorUnit: string; const Den: TQuantity;
  const DenominatorUnit: string; const Locale: TLocale; const Options: TUnitOptions): string;
var
  Compound, FormattedNumerator, FormattedDenominator, DUnit, PerPattern, L: string;
  V: TCLDRValue;
begin
  CheckLength(Options.Length);
  if (NumeratorUnit <> '') and (DenominatorUnit <> '') and IsOne(Den) then
  begin
    Compound := FindCompoundUnit(NumeratorUnit, DenominatorUnit, Locale);
    if Compound <> '' then
    begin
      if Num.IsText then
        Exit(FormatUnitText(Num.Text, Compound, Locale, Options));
      Exit(FormatUnit(Num.Number, Compound, Locale, Options));
    end;
  end;

  if Num.IsText then
    FormattedNumerator := Num.Text
  else if NumeratorUnit <> '' then
    FormattedNumerator := FormatUnit(Num.Number, NumeratorUnit, Locale, Options)
  else
    FormattedNumerator := FormatDecimal(Num.Number, Locale, NumberOptionsOf(Options));

  if Den.IsText then
    FormattedDenominator := Den.Text
  else if DenominatorUnit <> '' then
  begin
    if IsOne(Den) then
    begin
      (* CLDR's perUnitPattern ('{0}/h') when the denominator is 1; else
        the unit without its number (TR35's per-unit algorithm, 3.2:
        ' second' stripped) *)
      DUnit := FindUnitPattern(DenominatorUnit, Locale);
      if DUnit = '' then
        raise UnknownUnit(DenominatorUnit, Locale);
      PerPattern := UnitEntry(Locale, DUnit, Options.Length, 'per');
      if PerPattern <> '' then
        Exit(FormatPlaceholders(PerPattern, [FormattedNumerator]));
      FormattedDenominator := StripWhiteSpace(FormatUnitText('', DUnit, Locale, Options));
    end
    else
      FormattedDenominator := StripWhiteSpace(FormatUnit(Den.Number, DenominatorUnit, Locale, Options));
  end
  else
    FormattedDenominator := FormatDecimal(Den.Number, Locale, NumberOptionsOf(Options));

  PerPattern := '{0}/{1}';
  V := NeedKey(Locale, 'compound_unit_patterns').Get('per');
  if V <> nil then
    for L in LengthChain(Options.Length) do
      if (V.Get(L) <> nil) and V.Get(L).Has('compound') then
      begin
        PerPattern := V.Get(L).Str('compound');
        Break;
      end;
  Result := FormatPlaceholders(PerPattern, [FormattedNumerator, FormattedDenominator]);
end;

function Quantity(const N: TDecimal): TQuantity;
begin
  Result := Default(TQuantity);
  Result.Number := N;
end;

function TextQuantity(const S: string): TQuantity;
begin
  Result := Default(TQuantity);
  Result.IsText := True;
  Result.Text := S;
end;

function FormatCompoundUnit(const NumeratorValue: TDecimal; const NumeratorUnit: string;
  const DenominatorValue: TDecimal; const DenominatorUnit: string; const Locale: TLocale): string;
begin
  Result := FormatCompoundUnit(NumeratorValue, NumeratorUnit, DenominatorValue, DenominatorUnit,
    Locale, UnitOptions);
end;

function FormatCompoundUnit(const NumeratorValue: TDecimal; const NumeratorUnit: string;
  const DenominatorValue: TDecimal; const DenominatorUnit: string; const Locale: TLocale;
  const Options: TUnitOptions): string;
begin
  Result := CompoundUnit(Quantity(NumeratorValue), NumeratorUnit, Quantity(DenominatorValue),
    DenominatorUnit, Locale, Options);
end;

function FormatCompoundUnitText(const NumeratorValue, NumeratorUnit, DenominatorValue,
  DenominatorUnit: string; const Locale: TLocale; const Options: TUnitOptions): string;
begin
  Result := CompoundUnit(TextQuantity(NumeratorValue), NumeratorUnit, TextQuantity(DenominatorValue),
    DenominatorUnit, Locale, Options);
end;

end.
