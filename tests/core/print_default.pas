{ print_default - prints DefaultLocale(Category) and TLocale.Default's
  identifier (or the error class) for tests/python/check_default_locale.py,
  which runs it with different environment variables.

  Usage: print_default [CATEGORY] }
program print_default;

{$mode objfpc}{$H+}

uses
  SysUtils, babel.errors, babel.core, babel.cldr_all;

var
  Category: string;
begin
  Category := ParamStr(1);
  WriteLn(DefaultLocale(Category));
  try
    WriteLn(TLocale.Default(Category).ToString);
  except
    on E: EUnknownLocaleError do WriteLn('UnknownLocaleError');
    on E: EBabelTypeError do WriteLn('TypeError');
    on E: EBabelValueError do WriteLn('ValueError');
  end;
end.
