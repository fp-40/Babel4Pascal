{ test_roundtrip - formats numbers and parses them back, in every linked
  locale, with the Latin digits and with the locale's own numbering
  system: ParseDecimal(FormatDecimal(X)) must equal X, and ParseNumber
  must give back an integer. The numbers are formatted with all their
  digits (DecimalQuantization off), with and without grouping.

  Usage: test_roundtrip   (exit status 1 when a case fails) }
program test_roundtrip;

{$mode objfpc}{$H+}

uses
  SysUtils, babel.decimal, babel.localedata, babel.core, babel.numbers, babel.cldr_all;

const
  Numbers: array[0..15] of string = ('0', '1', '-1', '7', '-12.5', '1234', '-1234.5', '12345.678',
    '1000000', '-9876543.21', '0.001', '-0.5', '123456789012345678901234567890.123456789',
    '1E+6', '42.0', '-100000');
  Systems: array[0..1] of string = ('latn', 'default');

var
  Locales: TStringArray;
  L, N, NS, Text, Back: string;
  Opts: TNumberOptions;
  Grouping: Boolean;
  Total, Failures: Integer;
  X, Y: TDecimal;
  I64: Int64;

procedure Fail(const Msg: string);
begin
  Inc(Failures);
  if Failures <= 30 then
    WriteLn('FAIL ', Msg);
end;

begin
  Total := 0;
  Failures := 0;
  Locales := LocaleIdentifiers;
  for L in Locales do
    for NS in Systems do
      for Grouping in [True, False] do
        for N in Numbers do
        begin
          Inc(Total);
          X := TDecimal.Parse(N);
          Opts := NumberOptions.WithDecimalQuantization(False).WithGroupSeparator(Grouping)
            .WithNumberingSystem(NS);
          Text := '';
          try
            Text := FormatDecimal(X, L, Opts);
            Y := ParseDecimal(Text, L, ParseOptions.WithNumberingSystem(NS));
            if Y.Compare(X) <> 0 then
              Fail(Format('%s %s: %s -> %s -> %s', [L, NS, N, Text, Y.ToString]));
            if X.IsIntegral and X.TryToInt64(I64) then
            begin
              Inc(Total);
              if ParseNumber(Text, L, ParseOptions.WithNumberingSystem(NS)) <> I64 then
                Fail(Format('%s %s: ParseNumber(%s) <> %s', [L, NS, Text, N]));
            end;
            if Grouping then
            begin
              { the strict parser accepts what FormatDecimal writes }
              Inc(Total);
              Back := ParseDecimal(Text, L, ParseOptions.WithNumberingSystem(NS).WithStrict(True)).ToString;
              if TDecimal.Parse(Back).Compare(X) <> 0 then
                Fail(Format('%s %s strict: %s -> %s', [L, NS, Text, Back]));
            end;
          except
            on E: Exception do
              Fail(Format('%s %s: %s -> %s: %s %s', [L, NS, N, Text, E.ClassName, E.Message]));
          end;
        end;
  WriteLn(Total, ' round trips, ', Failures, ' failed');
  if Failures > 0 then
    Halt(1);
end.
