{ babel.errors - the exception classes shared by the units of Babel4Pascal.

  EBabelError is the base class. Its subclasses tell the failures apart:
  EBabelValueError for a malformed argument (an identifier, a number, a
  pattern), EBabelTypeError for an argument of the wrong kind or a missing
  one, EBabelKeyError for data the locale does not have, EBabelOverflowError
  for a value out of range, EBabelIndexError for an index out of range,
  EBabelNotImplementedError for an unsupported case, EBabelDecimalError for
  a failed decimal operation. Units add their own subclasses
  (EUnknownLocaleError in babel.core, EPluralRuleError in babel.plural). }
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
  { A failed decimal operation (invalid operation, division by zero,
    overflow), as quantizing a number to more than 28 digits. }
  EBabelDecimalError = class(EBabelError);

implementation

end.
