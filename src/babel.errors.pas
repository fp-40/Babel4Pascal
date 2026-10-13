{ babel.errors - the exception classes shared by the units of Babel4Pascal.

  They mirror the Python exceptions Babel raises, so that a caller can tell
  the same failures apart: EBabelValueError where Babel raises ValueError
  (a malformed identifier or number), EBabelTypeError for TypeError,
  EBabelKeyError for KeyError (data that the locale does not have),
  EBabelOverflowError for OverflowError, EBabelIndexError for IndexError,
  EBabelDecimalError for the
  exceptions of Python's decimal module. Units
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
  EBabelIndexError = class(EBabelError);
  EBabelNotImplementedError = class(EBabelError);
  { Python's decimal.DecimalException (InvalidOperation, DivisionByZero,
    Overflow): the operations Babel does with Decimal fail with it, as
    quantizing a number with more than 28 digits. }
  EBabelDecimalError = class(EBabelError);

implementation

end.
