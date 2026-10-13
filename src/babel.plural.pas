{ babel.plural - CLDR plural rules, as Python Babel's babel.plural.

  A plural rule maps a number to a plural category (zero, one, two, few,
  many, other): English has "1 file" (one) and "2 files" (other); Russian
  and Arabic have more categories. CLDR writes each category's condition
  in a small language over the operands of the number, such as
  'i = 1 and v = 0' (UTS #35, "Language Plural Rules"). A locale has a
  cardinal rule (TLocale.PluralForm) and an ordinal rule
  (TLocale.OrdinalForm, "1st, 2nd, 3rd").

  TPluralRule parses the conditions once and evaluates numbers against
  them, with Babel's semantics:
  - the conditions are tried in alphabetical order of the category, and
    'other' is the answer when none holds;
  - the operands come from ExtractOperands: an Int64 is an integer; a
    Double is turned into Decimal(str(x)) unless it is integral; a
    TDecimal keeps its digits, so '1.0' and '1' differ (v = 1 and v = 0);
  - the operands c and e are always 0 (Babel does not support them).

  The textual forms are Babel's: Rules (its PluralRule.rules), ToGettext
  and ToJavaScript. Babel's to_python (Python source) has no equivalent.

  Threading: TPluralRule is a value; evaluating it changes nothing. }
unit babel.plural;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors, babel.decimal;

type
  EPluralRuleError = class(EBabelError);   { Babel's RuleError }

  { The operands of a number for plural rules (UTS #35): N the absolute
    value; I its integer digits; V and W the number of visible fraction
    digits with and without trailing zeros; F and T those digits as an
    integer with and without trailing zeros; C and E always 0. }
  TPluralOperands = record
    N, I, F, T: TDecimal;
    V, W, C, E: Integer;
  end;

  TPluralRuleItem = record
    Tag, Expr: string;
  end;
  TPluralRuleItems = array of TPluralRuleItem;

  TPluralNodeKind = (pnValue, pnVar, pnMod, pnIs, pnIsNot, pnIn, pnWithin,
    pnAnd, pnOr, pnNot);

  TPluralRange = record
    Lo, Hi: Int64;
  end;

  TPluralNode = record
    Kind: TPluralNodeKind;
    Value: Int64;          { pnValue; pnMod: the divisor; pnIs/pnIsNot: the value }
    Name: Char;            { pnVar }
    A, B: Integer;         { children: pnMod A = variable; pnIs/pnIn A = expr;
                             pnAnd/pnOr A, B; pnNot A }
    Ranges: array of TPluralRange;   { pnIn, pnWithin }
  end;

  TPluralRule = record
  private
    FTags: array of string;      { in evaluation order (alphabetical) }
    FRoots: array of Integer;    { the root node of each tag's condition }
    FNodes: array of TPluralNode;
    function Eval(Node: Integer; const Ops: TPluralOperands): Boolean;
    function Num(Node: Integer; const Ops: TPluralOperands): TDecimal;
    function CompileUnicode(Node: Integer): string;
    function CompileGettext(Node: Integer; JavaScript: Boolean): string;
  public
    { PluralRule(rules): Items as (category, condition) pairs, in any
      order. Raises EBabelValueError for an unknown or repeated category
      and EPluralRuleError for a malformed condition. A condition that is
      only samples ('@integer ...') adds no rule. }
    class function Create(const Items: array of TPluralRuleItem): TPluralRule; static;
    { The same, from pairs given flat: ['one', 'n = 1', 'few', '...']. }
    class function CreatePairs(const Pairs: array of string): TPluralRule; static;
    { The rule that always answers 'other' (Babel's PluralRule of an empty
      dict). }
    class function Empty: TPluralRule; static;

    { The category of the number (calling the PluralRule in Babel). }
    function Evaluate(N: Int64): string; overload;
    function Evaluate(N: Double): string; overload;
    function Evaluate(const N: TDecimal): string; overload;
    function EvaluateOperands(const Ops: TPluralOperands): string;

    { The conditions, rewritten as Babel's PluralRule.rules does (old
      syntax: 'n is 1', 'n mod 10 in 2..4'), in evaluation order. }
    function Rules: TPluralRuleItems;
    { The categories that have a condition, sorted (PluralRule.tags). }
    function Tags: TStringArray;
    { Babel's to_gettext: 'nplurals=2; plural=((n == 1) ? 0 : 1);'. }
    function ToGettext: string;
    (* Babel's to_javascript: "(function(n) { return ... 'other'; })". *)
    function ToJavaScript: string;
  end;

const
  PluralTags: array[0..5] of string = ('zero', 'one', 'two', 'few', 'many', 'other');

function ExtractOperands(N: Int64): TPluralOperands; overload;
function ExtractOperands(N: Double): TPluralOperands; overload;
function ExtractOperands(const N: TDecimal): TPluralOperands; overload;

{ Babel's in_range_list, within_range_list and cldr_modulo. }
function InRangeList(const Num: TDecimal; const Ranges: array of TPluralRange): Boolean;
function WithinRangeList(const Num: TDecimal; const Ranges: array of TPluralRange): Boolean;
function CldrModulo(const A: TDecimal; B: Int64): TDecimal;

implementation

uses
  Math;

{ ---- operands ---- }

function DecimalOperands(const N: TDecimal): TPluralOperands;
var
  Trailing, NoTrailing: string;
  Count: Int64;
begin
  Result := Default(TPluralOperands);
  Result.N := N.Abs;
  Result.I := Result.N.Truncate;
  { Babel: fraction_digits = digits[exp:] if exp < 0: the last -exp
    coefficient digits, or all of them when there are fewer (so 0.05,
    whose coefficient is 5, has v = 1). }
  Trailing := '';
  if Result.N.Exponent < 0 then
  begin
    Count := -Result.N.Exponent;
    if Count >= Length(Result.N.Digits) then
      Trailing := Result.N.Digits
    else
      Trailing := Copy(Result.N.Digits, Length(Result.N.Digits) - Count + 1, Count);
  end;
  NoTrailing := Trailing;
  while (NoTrailing <> '') and (NoTrailing[Length(NoTrailing)] = '0') do
    SetLength(NoTrailing, Length(NoTrailing) - 1);
  Result.V := Length(Trailing);
  Result.W := Length(NoTrailing);
  Result.F := TDecimal.Make(False, Trailing, 0);
  Result.T := TDecimal.Make(False, NoTrailing, 0);
end;

function ExtractOperands(N: Int64): TPluralOperands;
begin
  Result := Default(TPluralOperands);
  Result.N := TDecimal.FromInt64(N).Abs;
  Result.I := Result.N;
  Result.F := TDecimal.FromInt64(0);
  Result.T := Result.F;
end;

function ExtractOperands(N: Double): TPluralOperands;
var
  A: Double;
begin
  A := System.Abs(N);
  if IsNan(A) then
    raise EBabelValueError.Create('cannot convert float NaN to integer');
  if IsInfinite(A) then
    raise EBabelOverflowError.Create('cannot convert float infinity to integer');
  if Frac(A) = 0 then
  begin
    { Babel: an integral float becomes int(n). }
    Result := Default(TPluralOperands);
    Result.N := TDecimal.FromDouble(A).Truncate;
    Result.I := Result.N;
    Result.F := TDecimal.FromInt64(0);
    Result.T := Result.F;
  end
  else
    Result := DecimalOperands(TDecimal.FromDouble(A));
end;

function ExtractOperands(const N: TDecimal): TPluralOperands;
begin
  Result := DecimalOperands(N);
end;

function WithinRangeList(const Num: TDecimal; const Ranges: array of TPluralRange): Boolean;
var
  R: TPluralRange;
begin
  for R in Ranges do
    if (Num.CompareInt(R.Lo) >= 0) and (Num.CompareInt(R.Hi) <= 0) then
      Exit(True);
  Result := False;
end;

function InRangeList(const Num: TDecimal; const Ranges: array of TPluralRange): Boolean;
begin
  Result := Num.IsIntegral and WithinRangeList(Num, Ranges);
end;

function CldrModulo(const A: TDecimal; B: Int64): TDecimal;
begin
  if B = 0 then
    raise EBabelValueError.Create('modulo by zero');
  { Python: the remainder keeps the sign of the dividend. }
  Result := A.Abs.ModInt(System.Abs(B));
  if A.Negative then
    Result := TDecimal.Make(True, Result.Digits, Result.Exponent);
end;

{ ---- tokenizer and parser (Babel's tokenize_rule and _Parser) ---- }

type
  TTokKind = (tkWord, tkValue, tkSymbol, tkEllipsis);
  TTok = record
    Kind: TTokKind;
    Text: string;
  end;
  TTokArray = array of TTok;

  TRuleParser = record
    Toks: TTokArray;
    Pos: Integer;               { next token }
    Nodes: array of TPluralNode;
    function AddNode(const N: TPluralNode): Integer;
    function Peek(Kind: TTokKind; const Text: string = ''): Boolean;
    function Skip(Kind: TTokKind; const Text: string = ''): Boolean;
    function Expect(Kind: TTokKind; const Term: string): string;
    function Condition: Integer;
    function AndCondition: Integer;
    function Relation: Integer;
    function NewfangledRelation(Left: Integer): Integer;
    function RangeList(Kind: TPluralNodeKind; Expr: Integer): Integer;
    function Expr: Integer;
    function Value: Int64;
  end;

function IsWordChar(C: Char): Boolean; inline;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

const
  { Babel's word alternatives, in the order the regular expression tries
    them: and|or|is|(?:with)?in|not|mod|[nivwftce]. }
  Words: array[0..14] of string = ('and', 'or', 'is', 'within', 'in', 'not', 'mod',
    'n', 'i', 'v', 'w', 'f', 't', 'c', 'e');
  Ellipsis = #$E2#$80#$A6;   { U+2026 in UTF-8 }

function Tokenize(const Rule: string): TTokArray;
var
  S, W: string;
  P, L, K: Integer;
  T: TTok;
  Found: Boolean;

  procedure Add(Kind: TTokKind; const Text: string);
  begin
    T.Kind := Kind;
    T.Text := Text;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := T;
  end;

begin
  Result := nil;
  S := Rule;
  K := Pos('@', S);
  if K > 0 then
    S := Copy(S, 1, K - 1);
  P := 1;
  L := Length(S);
  while P <= L do
  begin
    if S[P] in [' ', #9, #10, #11, #12, #13] then
    begin
      while (P <= L) and (S[P] in [' ', #9, #10, #11, #12, #13]) do
        Inc(P);
      Continue;
    end;
    { word, between word boundaries }
    Found := False;
    if IsWordChar(S[P]) and ((P = 1) or not IsWordChar(S[P - 1])) then
      for W in Words do
        if (Copy(S, P, Length(W)) = W) and
           ((P + Length(W) > L) or not IsWordChar(S[P + Length(W)])) then
        begin
          Add(tkWord, W);
          Inc(P, Length(W));
          Found := True;
          Break;
        end;
    if Found then
      Continue;
    if S[P] in ['0'..'9'] then
    begin
      K := P;
      while (P <= L) and (S[P] in ['0'..'9']) do
        Inc(P);
      Add(tkValue, Copy(S, K, P - K));
      Continue;
    end;
    if S[P] in ['%', ','] then
    begin
      Add(tkSymbol, S[P]);
      Inc(P);
      Continue;
    end;
    if Copy(S, P, 2) = '!=' then
    begin
      Add(tkSymbol, '!=');
      Inc(P, 2);
      Continue;
    end;
    if S[P] = '=' then
    begin
      Add(tkSymbol, '=');
      Inc(P);
      Continue;
    end;
    if Copy(S, P, 3) = '...' then
    begin
      Add(tkEllipsis, '...');
      Inc(P, 3);
      Continue;
    end;
    if Copy(S, P, 2) = '..' then
    begin
      Add(tkEllipsis, '..');
      Inc(P, 2);
      Continue;
    end;
    if Copy(S, P, 3) = Ellipsis then
    begin
      Add(tkEllipsis, Ellipsis);
      Inc(P, 3);
      Continue;
    end;
    raise EPluralRuleError.CreateFmt(
      'malformed CLDR pluralization rule.  Got unexpected ''%s''', [S[P]]);
  end;
end;

function TRuleParser.AddNode(const N: TPluralNode): Integer;
begin
  Result := Length(Nodes);
  SetLength(Nodes, Result + 1);
  Nodes[Result] := N;
end;

function TRuleParser.Peek(Kind: TTokKind; const Text: string): Boolean;
begin
  Result := (Pos < Length(Toks)) and (Toks[Pos].Kind = Kind) and
    ((Text = '') or (Toks[Pos].Text = Text));
end;

function TRuleParser.Skip(Kind: TTokKind; const Text: string): Boolean;
begin
  Result := Peek(Kind, Text);
  if Result then
    Inc(Pos);
end;

function TRuleParser.Expect(Kind: TTokKind; const Term: string): string;
begin
  if Peek(Kind) then
  begin
    Result := Toks[Pos].Text;
    Inc(Pos);
    Exit;
  end;
  if Pos >= Length(Toks) then
    raise EPluralRuleError.CreateFmt('expected %s but end of rule reached', [Term]);
  raise EPluralRuleError.CreateFmt('expected %s but got ''%s''', [Term, Toks[Pos].Text]);
end;

function MakeNode(Kind: TPluralNodeKind; A: Integer = -1; B: Integer = -1): TPluralNode;
begin
  Result := Default(TPluralNode);
  Result.Kind := Kind;
  Result.A := A;
  Result.B := B;
end;

function TRuleParser.Condition: Integer;
begin
  Result := AndCondition;
  while Skip(tkWord, 'or') do
    Result := AddNode(MakeNode(pnOr, Result, AndCondition));
end;

function TRuleParser.AndCondition: Integer;
begin
  Result := Relation;
  while Skip(tkWord, 'and') do
    Result := AddNode(MakeNode(pnAnd, Result, Relation));
end;

function TRuleParser.Relation: Integer;
var
  Left: Integer;
  Negated: Boolean;
  N: TPluralNode;
begin
  Left := Expr;
  if Skip(tkWord, 'is') then
  begin
    if Skip(tkWord, 'not') then
      N := MakeNode(pnIsNot, Left)
    else
      N := MakeNode(pnIs, Left);
    N.Value := Value;
    Exit(AddNode(N));
  end;
  Negated := Skip(tkWord, 'not');
  if Skip(tkWord, 'within') then
    Result := RangeList(pnWithin, Left)
  else if Skip(tkWord, 'in') then
    Result := RangeList(pnIn, Left)
  else
  begin
    if Negated then
      raise EPluralRuleError.Create('Cannot negate operator based rules.');
    Exit(NewfangledRelation(Left));
  end;
  if Negated then
    Result := AddNode(MakeNode(pnNot, Result));
end;

function TRuleParser.NewfangledRelation(Left: Integer): Integer;
var
  Negated: Boolean;
begin
  if Skip(tkSymbol, '=') then
    Negated := False
  else if Skip(tkSymbol, '!=') then
    Negated := True
  else
    raise EPluralRuleError.Create('Expected "=" or "!=" or legacy relation');
  Result := RangeList(pnIn, Left);
  if Negated then
    Result := AddNode(MakeNode(pnNot, Result));
end;

function TRuleParser.RangeList(Kind: TPluralNodeKind; Expr: Integer): Integer;
var
  N: TPluralNode;
  R: TPluralRange;
begin
  N := MakeNode(Kind, Expr);
  repeat
    R.Lo := Value;
    if Skip(tkEllipsis) then
      R.Hi := Value
    else
      R.Hi := R.Lo;
    SetLength(N.Ranges, Length(N.Ranges) + 1);
    N.Ranges[High(N.Ranges)] := R;
  until not Skip(tkSymbol, ',');
  Result := AddNode(N);
end;

function TRuleParser.Expr: Integer;
var
  N, M: TPluralNode;
  Name: string;
begin
  if not Peek(tkWord) or (Length(Toks[Pos].Text) <> 1) then
  begin
    { Babel: skip_token(word) then test it is a variable. }
    if Peek(tkWord) then
      Inc(Pos);
    raise EPluralRuleError.Create('Expected identifier variable');
  end;
  Name := Toks[Pos].Text;
  Inc(Pos);
  N := MakeNode(pnVar);
  N.Name := Name[1];
  Result := AddNode(N);
  if Skip(tkWord, 'mod') or Skip(tkSymbol, '%') then
  begin
    M := MakeNode(pnMod, Result);
    M.Value := Value;
    Result := AddNode(M);
  end;
end;

function TRuleParser.Value: Int64;
var
  S: string;
begin
  S := Expect(tkValue, '''value''');
  if not TryStrToInt64(S, Result) then
    raise EPluralRuleError.CreateFmt('value too large: %s', [S]);
end;

{ ---- TPluralRule ---- }

function IndexOfTag(const Tag: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(PluralTags) do
    if PluralTags[I] = Tag then
      Exit(I);
  Result := -1;
end;

class function TPluralRule.Create(const Items: array of TPluralRuleItem): TPluralRule;
var
  Sorted: array of TPluralRuleItem;
  I, J, Root, Base, K: Integer;
  T: TPluralRuleItem;
  P: TRuleParser;
begin
  Result := Default(TPluralRule);
  SetLength(Sorted, Length(Items));
  for I := 0 to High(Items) do
    Sorted[I] := Items[I];
  { sorted(rules): by tag, then by condition text }
  for I := 1 to High(Sorted) do
  begin
    T := Sorted[I];
    J := I - 1;
    while (J >= 0) and ((CompareStr(Sorted[J].Tag, T.Tag) > 0) or
      ((Sorted[J].Tag = T.Tag) and (CompareStr(Sorted[J].Expr, T.Expr) > 0))) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := T;
  end;
  for I := 0 to High(Sorted) do
  begin
    if IndexOfTag(Sorted[I].Tag) < 0 then
      raise EBabelValueError.CreateFmt('unknown tag ''%s''', [Sorted[I].Tag]);
    if (I > 0) and (Sorted[I - 1].Tag = Sorted[I].Tag) then
      raise EBabelValueError.CreateFmt('tag ''%s'' defined twice', [Sorted[I].Tag]);
    P := Default(TRuleParser);
    P.Toks := Tokenize(Sorted[I].Expr);
    if Length(P.Toks) = 0 then
      Continue;   { only samples: no rule }
    Root := P.Condition;
    if P.Pos < Length(P.Toks) then
      raise EPluralRuleError.CreateFmt('Expected end of rule, got ''%s''', [P.Toks[P.Pos].Text]);
    { Append this condition's nodes, shifting child indexes. }
    Base := Length(Result.FNodes);
    for K := 0 to High(P.Nodes) do
    begin
      if P.Nodes[K].A >= 0 then Inc(P.Nodes[K].A, Base);
      if P.Nodes[K].B >= 0 then Inc(P.Nodes[K].B, Base);
    end;
    Result.FNodes := Concat(Result.FNodes, P.Nodes);
    SetLength(Result.FTags, Length(Result.FTags) + 1);
    Result.FTags[High(Result.FTags)] := Sorted[I].Tag;
    SetLength(Result.FRoots, Length(Result.FRoots) + 1);
    Result.FRoots[High(Result.FRoots)] := Root + Base;
  end;
end;

class function TPluralRule.CreatePairs(const Pairs: array of string): TPluralRule;
var
  Items: array of TPluralRuleItem;
  I: Integer;
begin
  if Odd(Length(Pairs)) then
    raise EBabelValueError.Create('plural rule pairs: odd number of strings');
  SetLength(Items, Length(Pairs) div 2);
  for I := 0 to High(Items) do
  begin
    Items[I].Tag := Pairs[2 * I];
    Items[I].Expr := Pairs[2 * I + 1];
  end;
  Result := Create(Items);
end;

class function TPluralRule.Empty: TPluralRule;
begin
  Result := Default(TPluralRule);
end;

function TPluralRule.Num(Node: Integer; const Ops: TPluralOperands): TDecimal;
begin
  with FNodes[Node] do
    case Kind of
      pnValue: Result := TDecimal.FromInt64(Value);
      pnVar:
        case Name of
          'n': Result := Ops.N;
          'i': Result := Ops.I;
          'v': Result := TDecimal.FromInt64(Ops.V);
          'w': Result := TDecimal.FromInt64(Ops.W);
          'f': Result := Ops.F;
          't': Result := Ops.T;
          'c': Result := TDecimal.FromInt64(Ops.C);
        else
          Result := TDecimal.FromInt64(Ops.E);
        end;
      pnMod: Result := CldrModulo(Num(A, Ops), Value);
    else
      raise EPluralRuleError.Create('not a numeric node');
    end;
end;

function TPluralRule.Eval(Node: Integer; const Ops: TPluralOperands): Boolean;
begin
  with FNodes[Node] do
    case Kind of
      pnIs: Result := Num(A, Ops).CompareInt(Value) = 0;
      pnIsNot: Result := Num(A, Ops).CompareInt(Value) <> 0;
      pnIn: Result := InRangeList(Num(A, Ops), Ranges);
      pnWithin: Result := WithinRangeList(Num(A, Ops), Ranges);
      pnAnd: Result := Eval(A, Ops) and Eval(B, Ops);
      pnOr: Result := Eval(A, Ops) or Eval(B, Ops);
      pnNot: Result := not Eval(A, Ops);
    else
      raise EPluralRuleError.Create('not a condition node');
    end;
end;

function TPluralRule.EvaluateOperands(const Ops: TPluralOperands): string;
var
  I: Integer;
begin
  for I := 0 to High(FTags) do
    if Eval(FRoots[I], Ops) then
      Exit(FTags[I]);
  Result := 'other';
end;

function TPluralRule.Evaluate(N: Int64): string;
begin
  Result := EvaluateOperands(ExtractOperands(N));
end;

function TPluralRule.Evaluate(N: Double): string;
begin
  Result := EvaluateOperands(ExtractOperands(N));
end;

function TPluralRule.Evaluate(const N: TDecimal): string;
begin
  Result := EvaluateOperands(ExtractOperands(N));
end;

function TPluralRule.Tags: TStringArray;
var
  I, J: Integer;
  T: string;
begin
  Result := Copy(FTags);
  for I := 1 to High(Result) do
  begin
    T := Result[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(Result[J], T) > 0) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := T;
  end;
end;

function RangesText(const Ranges: array of TPluralRange): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Ranges) do
  begin
    if I > 0 then
      Result := Result + ',';
    if Ranges[I].Lo = Ranges[I].Hi then
      Result := Result + IntToStr(Ranges[I].Lo)
    else
      Result := Result + IntToStr(Ranges[I].Lo) + '..' + IntToStr(Ranges[I].Hi);
  end;
end;

{ Babel's _UnicodeCompiler. }
function TPluralRule.CompileUnicode(Node: Integer): string;
const
  Method: array[Boolean] of string = ('in', 'within');
begin
  with FNodes[Node] do
    case Kind of
      pnValue: Result := IntToStr(Value);
      pnVar: Result := Name;
      pnMod: Result := CompileUnicode(A) + ' mod ' + IntToStr(Value);
      pnIs: Result := CompileUnicode(A) + ' is ' + IntToStr(Value);
      pnIsNot: Result := CompileUnicode(A) + ' is not ' + IntToStr(Value);
      pnIn, pnWithin:
        Result := CompileUnicode(A) + ' ' + Method[Kind = pnWithin] + ' ' + RangesText(Ranges);
      pnAnd: Result := CompileUnicode(A) + ' and ' + CompileUnicode(B);
      pnOr: Result := CompileUnicode(A) + ' or ' + CompileUnicode(B);
      pnNot:
        with FNodes[A] do
          Result := CompileUnicode(A) + ' not ' + Method[Kind = pnWithin] + ' ' + RangesText(Ranges);
    end;
end;

{ Babel's _GettextCompiler and, with JavaScript, _JavaScriptCompiler. }
function TPluralRule.CompileGettext(Node: Integer; JavaScript: Boolean): string;
var
  E: string;
  I: Integer;
begin
  with FNodes[Node] do
    case Kind of
      pnValue: Result := IntToStr(Value);
      pnVar:
        case Name of
          'n', 'c', 'e': Result := Name;
          'i': if JavaScript then Result := 'parseInt(n, 10)' else Result := 'n';
        else
          Result := '0';   { v, w, f, t }
        end;
      pnMod: Result := '(' + CompileGettext(A, JavaScript) + ' % ' + IntToStr(Value) + ')';
      pnIs: Result := '(' + CompileGettext(A, JavaScript) + ' == ' + IntToStr(Value) + ')';
      pnIsNot: Result := '(' + CompileGettext(A, JavaScript) + ' != ' + IntToStr(Value) + ')';
      pnIn, pnWithin:
        begin
          E := CompileGettext(A, JavaScript);
          Result := '';
          for I := 0 to High(Ranges) do
          begin
            if I > 0 then
              Result := Result + ' || ';
            if Ranges[I].Lo = Ranges[I].Hi then
              Result := Result + '(' + E + ' == ' + IntToStr(Ranges[I].Lo) + ')'
            else
              Result := Result + '(' + E + ' >= ' + IntToStr(Ranges[I].Lo) + ' && ' +
                E + ' <= ' + IntToStr(Ranges[I].Hi) + ')';
          end;
          Result := '(' + Result + ')';
          if JavaScript and (Kind = pnIn) then
            Result := '(parseInt(' + E + ', 10) == ' + E + ' && ' + Result + ')';
        end;
      pnAnd: Result := '(' + CompileGettext(A, JavaScript) + ' && ' + CompileGettext(B, JavaScript) + ')';
      pnOr: Result := '(' + CompileGettext(A, JavaScript) + ' || ' + CompileGettext(B, JavaScript) + ')';
      pnNot: Result := '(!' + CompileGettext(A, JavaScript) + ')';
    end;
end;

function TPluralRule.Rules: TPluralRuleItems;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FTags));
  for I := 0 to High(FTags) do
  begin
    Result[I].Tag := FTags[I];
    Result[I].Expr := CompileUnicode(FRoots[I]);
  end;
end;

function TPluralRule.ToGettext: string;
var
  Used: array of string;
  I, J: Integer;

  function Index(const Tag: string): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Used) do
      if Used[K] = Tag then
        Exit(K);
    Result := -1;
  end;

begin
  { used_tags: the tags and 'other', indexed in the order of PluralTags }
  Used := nil;
  for I := 0 to High(PluralTags) do
    if PluralTags[I] = 'other' then
    begin
      SetLength(Used, Length(Used) + 1);
      Used[High(Used)] := 'other';
    end
    else
      for J := 0 to High(FTags) do
        if FTags[J] = PluralTags[I] then
        begin
          SetLength(Used, Length(Used) + 1);
          Used[High(Used)] := PluralTags[I];
          Break;
        end;
  Result := 'nplurals=' + IntToStr(Length(Used)) + '; plural=(';
  for I := 0 to High(FTags) do
    Result := Result + CompileGettext(FRoots[I], False) + ' ? ' + IntToStr(Index(FTags[I])) + ' : ';
  Result := Result + IntToStr(Index('other')) + ');';
end;

function TPluralRule.ToJavaScript: string;
var
  I: Integer;
begin
  Result := '(function(n) { return ';
  for I := 0 to High(FTags) do
    Result := Result + CompileGettext(FRoots[I], True) + ' ? ''' + FTags[I] + ''' : ';
  Result := Result + '''other''; })';
end;

end.
