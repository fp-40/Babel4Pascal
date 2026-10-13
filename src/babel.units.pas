{ babel.units - measurement units ('12 kilometers', '3 km/h'), as Python
  Babel's babel.units.

  FormatUnit(12, 'length-kilometer', 'en') gives '12 kilometers';
  FormatUnit(12, 'kilometer', 'es', UnitOptions.WithLength('short'))
  gives '12 km'; FormatCompoundUnit(150, 'kilometer', 1, 'hour', 'en')
  gives '150 kilometers per hour'.

  A unit is CLDR's id with its category ('length-kilometer') or the end of
  one ('kilometer'; the shortest id that ends with it is taken). Lengths:
  'long' (default), 'short', 'narrow'. Babel's preformatted values (a str
  given as the value) are FormatUnitText and FormatCompoundUnitText here,
  as TDecimal converts from strings.

  Threading: everything here only reads shared data. }
unit babel.units;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  babel.errors, babel.decimal, babel.core;

type
  EUnknownUnitError = class(EBabelValueError);   { Babel's UnknownUnitError }

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
  unknown. }
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
  SysUtils, babel.localedata, babel.pystr, babel.numbers;

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
  Key: string;
begin
  Patterns := UnitPatterns(Locale);
  if Patterns.Has(UnitId) then
    Exit(UnitId);
  { the shortest id ending with UnitId, the first of equal length (a
    stable sort by length, as Babel) }
  Result := '';
  Best := MaxInt;
  for I := 0 to Patterns.Count - 1 do
  begin
    Key := Patterns.Keys(I).AsString;
    if (System.Length(Key) < Best) and (System.Length(Key) >= System.Length(UnitId)) and
       (Copy(Key, System.Length(Key) - System.Length(UnitId) + 1, MaxInt) = UnitId) then
    begin
      Result := Key;
      Best := System.Length(Key);
    end;
  end;
end;

function UnknownUnit(const MeasurementUnit: string; const Locale: TLocale): EUnknownUnitError;
begin
  Result := EUnknownUnitError.CreateFmt('%s is not a known unit in %s', [MeasurementUnit, Locale.ToString]);
end;

function GetUnitName(const MeasurementUnit: string; const Locale: TLocale; const Length: string): string;
var
  QUnit: string;
  Names: TCLDRValue;
begin
  QUnit := FindUnitPattern(MeasurementUnit, Locale);
  if QUnit = '' then
    raise UnknownUnit(MeasurementUnit, Locale);
  Names := NeedKey(Locale, 'unit_display_names').Get(QUnit);
  if Names = nil then
    Exit('');
  Result := Names.Str(Length, '');
end;

{ format_unit with the value formatted and its plural form. }
function ApplyUnit(const FormattedValue, PluralForm, MeasurementUnit: string;
  const Locale: TLocale; const Options: TUnitOptions): string;
var
  QUnit, Name: string;
  Patterns: TCLDRValue;
begin
  QUnit := FindUnitPattern(MeasurementUnit, Locale);
  if QUnit = '' then
    raise UnknownUnit(MeasurementUnit, Locale);
  Patterns := UnitPatterns(Locale).Get(QUnit).Get(Options.Length);
  if (Patterns <> nil) and Patterns.Has(PluralForm) then
    Exit(PyFormat(Patterns.Str(PluralForm), [FormattedValue]));
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
begin
  if FindUnitPattern(MeasurementUnit, Locale) = '' then
    raise UnknownUnit(MeasurementUnit, Locale);
  Result := ApplyUnit(FormatDecimal(Value, Locale, NumberOptionsOf(Options)),
    Locale.PluralForm.Evaluate(Value), MeasurementUnit, Locale, Options);
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
  Compound, FormattedNumerator, FormattedDenominator, DUnit, PerPattern: string;
  V: TCLDRValue;
begin
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
      V := UnitPatterns(Locale).Get(DUnit);
      if V <> nil then
        V := V.Get(Options.Length);
      if V <> nil then
        V := V.Get('per');
      if (V <> nil) and (V.AsString <> '') then
        Exit(PyFormat(V.AsString, [FormattedNumerator]));
      FormattedDenominator := PyStrip(FormatUnitText('', DUnit, Locale, Options));
    end
    else
      FormattedDenominator := PyStrip(FormatUnit(Den.Number, DenominatorUnit, Locale, Options));
  end
  else
    FormattedDenominator := FormatDecimal(Den.Number, Locale, NumberOptionsOf(Options));

  PerPattern := '{0}/{1}';
  V := NeedKey(Locale, 'compound_unit_patterns').Get('per');
  if V <> nil then
    V := V.Get(Options.Length);
  if (V <> nil) and V.Has('compound') then
    PerPattern := V.Str('compound');
  Result := PyFormat(PerPattern, [FormattedNumerator, FormattedDenominator]);
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
