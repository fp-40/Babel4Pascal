{ babel.support - Format, the formatting functions bound to a locale, a
  time zone and a numbering system, as Python Babel's
  babel.support.Format.

  var F: TFormat;
  F := TFormat.Create('es_PE', 'America/Lima');
  F.Date(D) gives '13 oct 2026'; F.Currency(1234.5, 'PEN') gives
  'S/ 1,234.50'.

  Not ported from babel.support: LazyProxy (deferred evaluation of Python
  objects) and the gettext translation classes (NullTranslations,
  Translations), out of Babel4Pascal's scope.

  Threading: a TFormat is a value; its methods only read shared data. }
unit babel.support;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  babel.decimal, babel.core;

type
  TFormat = record
    Locale: TLocale;
    TimeZone: string;          { for DateTime and Time; '' = UTC }
    NumberingSystem: string;   { 'latn' (default), 'default' or a system }
    class function Create(const ALocale: TLocale; const ATimeZone: string = '';
      const ANumberingSystem: string = 'latn'): TFormat; static;
    { FormatDate: the date as it is, without a zone. }
    function Date(D: TDateTime; const Format: string = 'medium'): string;
    { FormatDateAndTime and FormatTime of a UTC value, in TimeZone. }
    function DateTime(UTC: TDateTime; const Format: string = 'medium'): string;
    function Time(UTC: TDateTime; const Format: string = 'medium'): string;
    function Timedelta(Seconds: Int64; const Granularity: string = 'second';
      Threshold: Double = 0.85; const Format: string = 'long'; AddDirection: Boolean = False): string;
    function Number(const N: TDecimal): string;
    function Decimal(const N: TDecimal; const Format: string = ''): string;
    function CompactDecimal(const N: TDecimal; const FormatType: string = 'short';
      FractionDigits: Integer = 0): string;
    function Currency(const N: TDecimal; const CurrencyCode: string): string;
    function CompactCurrency(const N: TDecimal; const CurrencyCode: string;
      const FormatType: string = 'short'; FractionDigits: Integer = 0): string;
    function Percent(const N: TDecimal; const Format: string = ''): string;
    function Scientific(const N: TDecimal): string;
  end;

implementation

uses
  babel.numbers, babel.dates;

class function TFormat.Create(const ALocale: TLocale; const ATimeZone: string;
  const ANumberingSystem: string): TFormat;
begin
  Result := Default(TFormat);
  Result.Locale := ALocale;
  Result.TimeZone := ATimeZone;
  Result.NumberingSystem := ANumberingSystem;
end;

{ The dates take the numbering system too (Babel's dates have none: with
  the default 'latn' the results are Babel's). }
function TFormat.Date(D: TDateTime; const Format: string): string;
begin
  Result := FormatDate(D, Locale, DateTimeOptions.WithFormat(Format).WithNumberingSystem(NumberingSystem));
end;

function TFormat.DateTime(UTC: TDateTime; const Format: string): string;
begin
  Result := FormatDateAndTime(UTC, Locale, DateTimeOptions.WithFormat(Format).WithTimeZone(TimeZone)
    .WithNumberingSystem(NumberingSystem));
end;

function TFormat.Time(UTC: TDateTime; const Format: string): string;
begin
  Result := FormatTime(UTC, Locale, DateTimeOptions.WithFormat(Format).WithTimeZone(TimeZone)
    .WithNumberingSystem(NumberingSystem));
end;

function TFormat.Timedelta(Seconds: Int64; const Granularity: string; Threshold: Double;
  const Format: string; AddDirection: Boolean): string;
begin
  Result := FormatTimedelta(Seconds, Locale, TimedeltaOptions.WithGranularity(Granularity)
    .WithThreshold(Threshold).WithFormat(Format).WithAddDirection(AddDirection)
    .WithNumberingSystem(NumberingSystem));
end;

function TFormat.Number(const N: TDecimal): string;
begin
  Result := FormatDecimal(N, Locale, NumberOptions.WithNumberingSystem(NumberingSystem));
end;

function TFormat.Decimal(const N: TDecimal; const Format: string): string;
begin
  Result := FormatDecimal(N, Locale, NumberOptions.WithFormat(Format).WithNumberingSystem(NumberingSystem));
end;

function TFormat.CompactDecimal(const N: TDecimal; const FormatType: string; FractionDigits: Integer): string;
begin
  Result := FormatCompactDecimal(N, Locale, CompactOptions.WithFormatType(FormatType)
    .WithFractionDigits(FractionDigits).WithNumberingSystem(NumberingSystem));
end;

function TFormat.Currency(const N: TDecimal; const CurrencyCode: string): string;
begin
  Result := FormatCurrency(N, CurrencyCode, Locale, CurrencyOptions.WithNumberingSystem(NumberingSystem));
end;

function TFormat.CompactCurrency(const N: TDecimal; const CurrencyCode, FormatType: string;
  FractionDigits: Integer): string;
begin
  Result := FormatCompactCurrency(N, CurrencyCode, Locale, CompactOptions.WithFormatType(FormatType)
    .WithFractionDigits(FractionDigits).WithNumberingSystem(NumberingSystem));
end;

function TFormat.Percent(const N: TDecimal; const Format: string): string;
begin
  Result := FormatPercent(N, Locale, NumberOptions.WithFormat(Format).WithNumberingSystem(NumberingSystem));
end;

function TFormat.Scientific(const N: TDecimal): string;
begin
  Result := FormatScientific(N, Locale, NumberOptions.WithNumberingSystem(NumberingSystem));
end;

end.
