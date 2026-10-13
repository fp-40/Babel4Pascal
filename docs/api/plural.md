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

`Rules` gives the conditions in CLDR's syntax (`=`, `!=`, `%`, ranges
`2..4` and lists `0,1`), in evaluation order (alphabetical by category).
A rule created from them is the same rule. `Tags` gives the categories
that have a condition, sorted.

```pascal
// TLocale('en').PluralForm.Rules
//   one: i = 1 and v = 0
// TLocale('ru').PluralForm.Rules
//   few: v = 0 and i % 10 = 2..4 and i % 100 != 12..14
//   many: v = 0 and i % 10 = 0 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 11..14
//   one: v = 0 and i % 10 = 1 and i % 100 != 11
string.Join(',', TLocale('pl').PluralForm.Tags);   // few,many,one
string.Join(',', TLocale('ar').PluralForm.Tags);   // few,many,one,two,zero
```

### ToGettext, ToJavaScript

```pascal
function ToGettext: string;
function ToJavaScript: string;
```

`ToGettext` gives the value of a gettext `Plural-Forms` header. That
format counts with integers, so the operands `n` and `i` are the count and
`v`, `w`, `f`, `t`, `c` and `e` are 0; the terms that are then constant
are left out. The forms are numbered in the order zero, one, two, few,
many, other, among the categories the rule has.

`ToJavaScript` gives the source of a JavaScript function that returns
the category of a number or a numeric string. It reads the decimal text
of the value, so a string keeps its fraction digits (`'1.50'` has
`v = 2`); exponent notation (`'1e3'`) is written out first. Integer parts
beyond 2^53 lose precision in JavaScript numbers.

```pascal
TLocale('en').PluralForm.ToGettext;
// nplurals=2; plural=(n == 1 ? 0 : 1);
TLocale('fr').PluralForm.ToGettext;
// nplurals=3; plural=(n != 0 && n % 1000000 == 0 ? 1 : n == 0 || n == 1 ? 0 : 2);
TLocale('ru').PluralForm.ToGettext;
// nplurals=4; plural=(n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) ? 1 : n % 10 == 0 || n % 10 >= 5 && n % 10 <= 9 || n % 100 >= 11 && n % 100 <= 14 ? 2 : n % 10 == 1 && n % 100 != 11 ? 0 : 3);

TLocale('en').PluralForm.ToJavaScript;
// (function(n) { var s = String(n).replace(/^[-+]/, ''); if (/e/i.test(s)) s = Number(s).toFixed(20).replace(/\.?0+$/, ''); var p = s.indexOf('.'), fs = p < 0 ? '' : s.slice(p + 1), i = parseInt(s, 10), v = fs.length; return i == 1 && v == 0 ? 'one' : 'other'; })

TPluralRule.CreatePairs(['one', 'n = 1', 'few', 'n = 2..4']).ToJavaScript;
// (function(n) { var s = String(n).replace(/^[-+]/, ''); if (/e/i.test(s)) s = Number(s).toFixed(20).replace(/\.?0+$/, ''); var p = s.indexOf('.'), fs = p < 0 ? '' : s.slice(p + 1), ts = fs.replace(/0+$/, ''), i = parseInt(s, 10); return ts == '' && i >= 2 && i <= 4 ? 'few' : ts == '' && i == 1 ? 'one' : 'other'; })
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
  trailing zeros (`'0.050'`: V = 3, W = 2, F = 50, T = 5; leading zeros
  of the fraction count as digits);
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
