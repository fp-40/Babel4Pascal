# Pluralization Support

The unit `babel.plural` evaluates CLDR plural rules. A plural rule maps a
number to a plural category: `zero`, `one`, `two`, `few`, `many` or
`other`. English has "1 file" (`one`) and "2 files" (`other`); Russian,
Polish and Arabic have more categories. CLDR writes each category's
condition in a small language over the operands of the number, such as
`i = 1 and v = 0` (Unicode Technical Standard #35, "Language Plural
Rules").

In the example outputs, no-break spaces (U+00A0) and narrow no-break
spaces (U+202F) are shown as ordinary spaces.

Each locale has a cardinal rule (`TLocale.PluralForm`) and an ordinal
rule (`TLocale.OrdinalForm`, for "1st, 2nd, 3rd"):

```pascal
uses babel.core, babel.plural, babel.cldr_all;

TLocale('en').PluralForm.Evaluate(1);      // one
TLocale('en').PluralForm.Evaluate(2);      // other
TLocale('ru').PluralForm.Evaluate(3);      // few
TLocale('ru').PluralForm.Evaluate(5);      // many
TLocale('en').OrdinalForm.Evaluate(2);     // two
TLocale('en').OrdinalForm.Evaluate(3);     // few
```

`TPluralRule` is a value; evaluating it changes nothing, and any thread
may use it.

## TPluralRule

```pascal
type
  TPluralRule = record
  public
    class function Create(const Items: array of TPluralRuleItem): TPluralRule; static;
    class function CreatePairs(const Pairs: array of string): TPluralRule; static;
    class function Empty: TPluralRule; static;

    function Evaluate(N: Int64): string; overload;
    function Evaluate(N: Double): string; overload;
    function Evaluate(const N: TDecimal): string; overload;
    function EvaluateOperands(const Ops: TPluralOperands): string;

    function Rules: TPluralRuleItems;
    function Tags: TStringArray;
    function ToGettext: string;
    function ToJavaScript: string;
  end;
```

A plural rule: a condition per category. The conditions are parsed once,
when the rule is created.

### TPluralRule.Create, CreatePairs

```pascal
class function Create(const Items: array of TPluralRuleItem): TPluralRule; static;
class function CreatePairs(const Pairs: array of string): TPluralRule; static;
```

A rule from (category, condition) pairs in any order; `CreatePairs`
takes them flat: `['one', 'n = 1', 'few', 'n in 2..4']`. A condition may
carry samples (`'n = 1 @integer 1 @decimal 1.0'`); they are ignored, and
a condition that is only samples (`'@integer 1'`) adds no rule.

Raises `EBabelValueError` for an unknown or repeated category and
`EPluralRuleError` for a malformed condition.

```pascal
var
  R: TPluralRule;
begin
  R := TPluralRule.CreatePairs(['one', 'n = 1', 'few', 'n in 2..4']);
  WriteLn(R.Evaluate(1));   // one
  WriteLn(R.Evaluate(3));   // few
  WriteLn(R.Evaluate(7));   // other
end.

TPluralRule.CreatePairs(['one', 'n = ']);
// raises EPluralRuleError: expected 'value' but end of rule reached
TPluralRule.CreatePairs(['uno', 'n = 1']);
// raises EBabelValueError: unknown tag 'uno'
TPluralRule.CreatePairs(['one', 'n = 1', 'one', 'n = 2']);
// raises EBabelValueError: tag 'one' defined twice
```

### TPluralRule.Empty

```pascal
class function Empty: TPluralRule; static;
```

The rule without conditions: it answers `'other'` for every number.
`TLocale.PluralForm` returns it for a locale that has no rule.

### Evaluate, EvaluateOperands

```pascal
function Evaluate(N: Int64): string; overload;
function Evaluate(N: Double): string; overload;
function Evaluate(const N: TDecimal): string; overload;
function EvaluateOperands(const Ops: TPluralOperands): string;
```

The category of the number. The conditions are tried in alphabetical
order of the category; `'other'` is the answer when none holds.

The operands come from `ExtractOperands`: an `Int64` is an integer; a
`Double` is its shortest decimal, an integer when it is integral (1.0 is
1); a `TDecimal` keeps its digits, so `'1.0'` and `'1'` differ in their
visible fraction digits and may have different categories:

```pascal
var
  R: TPluralRule;
begin
  R := TLocale('en').PluralForm;
  R.Evaluate(1);                        // one
  R.Evaluate(1.0);                      // one
  R.Evaluate(TDecimal.Parse('1.0'));    // other (v = 1)
  R := TLocale('pl').PluralForm;
  R.Evaluate(2);                        // few
  R.Evaluate(5);                        // many
  R.Evaluate(22);                       // few
  R.Evaluate(1.5);                      // other
end.
```

### Rules, Tags

```pascal
function Rules: TPluralRuleItems;
function Tags: TStringArray;
```

`Rules` gives the conditions rewritten in the syntax of the older CLDR
releases (`in`, `not in`, `mod`), in evaluation order. `Tags` gives the
categories that have a condition, sorted.

```pascal
R := TLocale('en').PluralForm;
// R.Rules: one: i in 1 and v in 0
string.Join(',', TLocale('pl').PluralForm.Tags);   // few,many,one
string.Join(',', TLocale('ar').PluralForm.Tags);   // few,many,one,two,zero
```

### ToGettext, ToJavaScript

```pascal
function ToGettext: string;
function ToJavaScript: string;
```

The rule as a gettext `Plural-Forms` expression, and as the source of a
JavaScript function that returns the category of its argument.

```pascal
R := TLocale('en').PluralForm;
R.ToGettext;
// nplurals=2; plural=((((n == 1)) && ((0 == 0))) ? 0 : 1);

R := TPluralRule.CreatePairs(['one', 'n = 1', 'few', 'n in 2..4']);
R.ToJavaScript;
// (function(n) { return (parseInt(n, 10) == n && ((n >= 2 && n <= 4))) ? 'few' : (parseInt(n, 10) == n && ((n == 1))) ? 'one' : 'other'; })
```

## TPluralRuleItem

```pascal
type
  TPluralRuleItem = record
    Tag, Expr: string;
  end;
  TPluralRuleItems = array of TPluralRuleItem;
```

A category (`Tag`) and its condition (`Expr`), as `TPluralRule.Create`
takes them and `TPluralRule.Rules` returns them.

```pascal
var
  Items: array of TPluralRuleItem;
  R: TPluralRule;
begin
  SetLength(Items, 2);
  Items[0].Tag := 'one';  Items[0].Expr := 'i = 1 and v = 0';
  Items[1].Tag := 'many'; Items[1].Expr := 'e = 0 and i != 0 and i % 1000000 = 0 and v = 0';
  R := TPluralRule.Create(Items);
  R.Evaluate(1);         // one
  R.Evaluate(2000000);   // many
  R.Evaluate(7);         // other
end.
```

## TPluralOperands, ExtractOperands

```pascal
type
  TPluralOperands = record
    N, I, F, T: TDecimal;
    V, W, C, E: Integer;
  end;

function ExtractOperands(N: Int64): TPluralOperands; overload;
function ExtractOperands(N: Double): TPluralOperands; overload;
function ExtractOperands(const N: TDecimal): TPluralOperands; overload;
```

The operands of a number, as plural conditions use them:

- `N`: the absolute value;
- `I`: its integer digits;
- `V`, `W`: the number of visible fraction digits, with and without
  trailing zeros;
- `F`, `T`: those fraction digits as an integer, with and without
  trailing zeros;
- `C`, `E`: the compact decimal exponent; always 0, as compact exponents
  are not supported.

```pascal
O := ExtractOperands(TDecimal.Parse('1.50'));
// N = 1.50, I = 1, V = 2, W = 1, F = 50, T = 5
O := ExtractOperands(1.25);
// N = 1.25, I = 1, V = 2, W = 2, F = 25, T = 25
O := ExtractOperands(Int64(-15));
// N = 15, I = 15, V = 0
```

## Condition helpers

```pascal
type
  TPluralRange = record
    Lo, Hi: Int64;
  end;

function InRangeList(const Num: TDecimal; const Ranges: array of TPluralRange): Boolean;
function WithinRangeList(const Num: TDecimal; const Ranges: array of TPluralRange): Boolean;
function CldrModulo(const A: TDecimal; B: Int64): TDecimal;
```

The tests and the operation of the condition language:

- `InRangeList`: the `in` test (`n in 2..4, 7`): `Num` is an integer
  inside one of the ranges.
- `WithinRangeList`: the `within` test: `Num` lies inside one of the
  ranges, integer or not.
- `CldrModulo`: the `%` (`mod`) operation; the result has the sign of
  `A` (`-7 % 3` is `-1`).

The interface also declares `TPluralNodeKind` and `TPluralNode`, the
parsed form of a condition inside `TPluralRule`; programs do not use
them.

## PluralTags

```pascal
const
  PluralTags: array[0..5] of string = ('zero', 'one', 'two', 'few', 'many', 'other');
```

The plural categories, in CLDR's order.

## EPluralRuleError

```pascal
type
  EPluralRuleError = class(EBabelError);
```

Raised for a malformed condition.

[API Reference](index.md) · [Index](../index.md)
