{ babel.errors - the exception classes shared by the units of Babel4Pascal.

  They mirror the Python exceptions Babel raises, so that a caller can tell
  the same failures apart: EBabelValueError where Babel raises ValueError
  (a malformed identifier or number), EBabelTypeError for TypeError,
  EBabelKeyError for KeyError (data that the locale does not have),
  EBabelOverflowError for OverflowError. Units
  add their own subclasses (EUnknownLocaleError in babel.core,
  EPluralRuleError in babel.plural). }
unit babel.errors;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  EBabelError = class(Exception);
  EBabelValueError = class(EBabelError);
  EBabelTypeError = class(EBabelError);
  EBabelKeyError = class(EBabelError);
  EBabelOverflowError = class(EBabelError);

implementation

end.
