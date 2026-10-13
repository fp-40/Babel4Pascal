{ babel.plural - CLDR plural rules.

  A plural rule maps a number to a plural category (zero, one, two, few,
  many, other): English has "1 file" (one) and "2 files" (other); Russian
  and Arabic have more categories. CLDR writes each category's condition
  in a small language over the operands of the number, such as
  'i = 1 and v = 0' (UTS #35, "Language Plural Rules"). A locale has a
  cardinal rule (TLocale.PluralForm) and an ordinal rule
  (TLocale.OrdinalForm, "1st, 2nd, 3rd").

  TPluralRule parses the conditions once and evaluates numbers against
  them:
  - the conditions are tried in alphabetical order of the category, and
    'other' is the answer when none holds;
  - the operands come from ExtractOperands: an Int64 is an integer; a
    Double is its shortest decimal (TDecimal.FromDouble), an integer when
    it is integral; a TDecimal keeps its digits, so '1.0' and '1' differ
    (v = 1 and v = 0);
  - the operands c and e are always 0 (compact exponents are not
    supported).

  Textual forms: Rules (the conditions in the old syntax), ToGettext and
  ToJavaScript.

  Threading: TPluralRule is a value; evaluating it changes nothing. }
unit babel.plural;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, babel.errors, babel.decimal;

type
  EPluralRuleError = class(EBabelError);   { a malformed rule }

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

  TPluralRule = record
  private
    FTags: array of string;      { in evaluation order (alphabetical) }
    FRoots: array of Integer;    { the root node of each tag's condition }
    FTree: IInterface;           { the parsed conditions (see the implementation) }
    function Eval(Node: Integer; const Ops: TPluralOperands): Boolean;
    function Num(Node: Integer; const Ops: TPluralOperands): TDecimal;
    function CompileRule(Node: Integer): string;
  public
    { A rule from Items, (category, condition) pairs in any
      order. Raises EBabelValueError for an unknown or repeated category
      and EPluralRuleError for a malformed condition. A condition that is
      only samples ('@integer ...') adds no rule. }
    class function Create(const Items: array of TPluralRuleItem): TPluralRule; static;
    { The same, from pairs given flat: ['one', 'n = 1', 'few', '...']. }
    class function CreatePairs(const Pairs: array of string): TPluralRule; static;
    { The rule that always answers 'other' (no conditions). }
    class function Empty: TPluralRule; static;

    { The category of the number. }
    function Evaluate(N: Int64): string; overload;
    function Evaluate(N: Double): string; overload;
    function Evaluate(const N: TDecimal): string; overload;
    function EvaluateOperands(const Ops: TPluralOperands): string;

    { The conditions in CLDR's syntax ('n = 1', 'n % 10 = 2..4 and n % 100
      != 12..14'), in evaluation order. }
    function Rules: TPluralRuleItems;
    { The categories that have a condition, sorted. }
    function Tags: TStringArray;
    { The gettext Plural-Forms header value, for the integer counts that
      format uses: 'nplurals=2; plural=(n == 1 ? 0 : 1);'. The forms are
      numbered in the order zero, one, two, few, many, other, among those
      the rule has. }
    function ToGettext: string;
    (* A JavaScript function of a number or a numeric string that returns
      its category: "(function(n) { ...; return ts == '' && i == 1 ? 'one'
      : 'other'; })". It reads the decimal text of the value (a string
      keeps its trailing zeros: '1.50' has two fraction digits); integer
      parts beyond 2^53 lose precision in JavaScript numbers. *)
    function ToJavaScript: string;
  end;

const
  PluralTags: array[0..5] of string = ('zero', 'one', 'two', 'few', 'many', 'other');

function ExtractOperands(N: Int64): TPluralOperands; overload;
function ExtractOperands(N: Double): TPluralOperands; overload;
function ExtractOperands(const N: TDecimal): TPluralOperands; overload;

implementation

uses
  Math;

type
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
  TPluralNodes = array of TPluralNode;

  { The parsed conditions of a rule, shared by its copies. }
  TPluralTree = class(TInterfacedObject)
    Nodes: TPluralNodes;
  end;

function NodesOf(const Tree: IInterface): TPluralNodes; inline;
begin
  if Tree = nil then
    Result := nil
  else
    Result := TPluralTree(Tree as TObject).Nodes;
end;

{ ---- operands ---- }

function DecimalOperands(const N: TDecimal): TPluralOperands;
var
  Trailing, NoTrailing: string;
  Count: Int64;
begin
  Result := Default(TPluralOperands);
  Result.N := N.Abs;
  Result.I := Result.N.Truncate;
  { the fraction digits: the last -exp coefficient digits, or all of
    them when there are fewer (so 0.05, whose coefficient is 5, has
    v = 1) }
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
  if IsNan(A) or IsInfinite(A) then
    raise EBabelValueError.Create('no plural category for NaN or infinity');
  if Frac(A) = 0 then
  begin
    { an integral double is the integer it reads as (1e25 is 10^25) }
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
  { the remainder keeps the sign of the dividend }
  Result := A.Abs.ModInt(System.Abs(B));
  if A.Negative then
    Result := TDecimal.Make(True, Result.Digits, Result.Exponent);
end;

{ ---- tokenizer and parser ---- }

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
  { the words, in the order they are tried: and, or, is, within, in,
    not, mod and the operands }
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
    { the word is consumed, then found not to be a variable }
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
  Nodes: TPluralNodes;
  Tree: TPluralTree;
begin
  Result := Default(TPluralRule);
  Nodes := nil;
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
    Base := Length(Nodes);
    for K := 0 to High(P.Nodes) do
    begin
      if P.Nodes[K].A >= 0 then Inc(P.Nodes[K].A, Base);
      if P.Nodes[K].B >= 0 then Inc(P.Nodes[K].B, Base);
    end;
    Nodes := Concat(Nodes, P.Nodes);
    SetLength(Result.FTags, Length(Result.FTags) + 1);
    Result.FTags[High(Result.FTags)] := Sorted[I].Tag;
    SetLength(Result.FRoots, Length(Result.FRoots) + 1);
    Result.FRoots[High(Result.FRoots)] := Root + Base;
  end;
  Tree := TPluralTree.Create;
  Tree.Nodes := Nodes;
  Result.FTree := Tree;
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
  with NodesOf(FTree)[Node] do
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
  with NodesOf(FTree)[Node] do
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

{ A condition in CLDR's syntax ('n % 10 = 2..4 and n % 100 != 12..14'). }
function TPluralRule.CompileRule(Node: Integer): string;
var
  Nodes: TPluralNodes;
begin
  Nodes := NodesOf(FTree);
  with Nodes[Node] do
    case Kind of
      pnValue: Result := IntToStr(Value);
      pnVar: Result := Name;
      pnMod: Result := CompileRule(A) + ' % ' + IntToStr(Value);
      pnIs: Result := CompileRule(A) + ' = ' + IntToStr(Value);
      pnIsNot: Result := CompileRule(A) + ' != ' + IntToStr(Value);
      pnIn: Result := CompileRule(A) + ' = ' + RangesText(Ranges);
      pnWithin: Result := CompileRule(A) + ' within ' + RangesText(Ranges);
      pnAnd: Result := CompileRule(A) + ' and ' + CompileRule(B);
      pnOr: Result := CompileRule(A) + ' or ' + CompileRule(B);
      pnNot:
        with Nodes[A] do
          if Kind = pnWithin then
            Result := CompileRule(A) + ' not within ' + RangesText(Ranges)
          else
            Result := CompileRule(A) + ' != ' + RangesText(Ranges);
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
    Result[I].Expr := CompileRule(FRoots[I]);
  end;
end;

{ ---- C (gettext) and JavaScript expressions ---- }

type
  { An expression being written: a constant (the operands that are always
    0 make many terms constant) or text with the precedence of its
    outermost operator. }
  TCExpr = record
    IsConst: Boolean;
    Value: Int64;              { constant: a number, or 0/1 for a condition }
    Text: string;
    Level: Integer;            { 1 ||, 2 &&, 3 comparison or !, 4 %, 5 operand }
    Fractional: Boolean;       { n in JavaScript: written as its integer part i,
                                 so a comparison also needs the fraction to be
                                 zero (ts == '') }
    Guard: Integer;            { 1: "ts == '' && Rest", -1: "ts != '' || Rest" }
    Rest: string;              { with a guard: the comparison of i }
    RestLevel: Integer;
  end;

  TExprWriter = record
    Nodes: TPluralNodes;
    JavaScript: Boolean;
    Used: set of Char;         { the operands the expression reads ('z': the
                                 fraction digits without trailing zeros) }
    NumericN: Boolean;         { write n as a number (for within) }
    function Number(Node: Integer): TCExpr;
    function Condition(Node: Integer): TCExpr;
    function WithinOperand(Node: Integer): TCExpr;
    function RangeTest(const X: TCExpr; Node: Integer; Integral, Negated: Boolean): TCExpr;
  end;

function ConstExpr(V: Int64): TCExpr;
begin
  Result := Default(TCExpr);
  Result.IsConst := True;
  Result.Value := V;
end;

function TextExpr(const Text: string; Level: Integer; Fractional: Boolean = False): TCExpr;
begin
  Result := Default(TCExpr);
  Result.Text := Text;
  Result.Level := Level;
  Result.Fractional := Fractional;
end;

{ "ts == '' && X" (Guard 1) or "ts != '' || X" (Guard -1). }
function Guarded(Guard: Integer; const X: string; XLevel: Integer): TCExpr;
begin
  if Guard > 0 then
  begin
    if XLevel < 2 then
      Result := TextExpr('ts == '''' && (' + X + ')', 2)
    else
      Result := TextExpr('ts == '''' && ' + X, 2);
  end
  else if XLevel < 1 then
    Result := TextExpr('ts != '''' || (' + X + ')', 1)
  else
    Result := TextExpr('ts != '''' || ' + X, 1);
  Result.Guard := Guard;
  Result.Rest := X;
  Result.RestLevel := XLevel;
end;

{ The text of E, in parentheses when its operator binds less than Level. }
function Wrap(const E: TCExpr; Level: Integer): string;
begin
  if E.IsConst then
    Result := IntToStr(E.Value)
  else if E.Level < Level then
    Result := '(' + E.Text + ')'
  else
    Result := E.Text;
end;

{ The comparison without its fraction test, for a conjunction. }
function Unguarded(const E: TCExpr): string;
begin
  if E.Guard <> 0 then
  begin
    if E.RestLevel < 2 then
      Result := '(' + E.Rest + ')'
    else
      Result := E.Rest;
  end
  else
    Result := Wrap(E, 2);
end;

function TExprWriter.Number(Node: Integer): TCExpr;
var
  X: TCExpr;
begin
  with Nodes[Node] do
    case Kind of
      pnValue: Result := ConstExpr(Value);
      pnVar:
        if Name in ['c', 'e'] then
          Result := ConstExpr(0)
        else if not JavaScript and (Name in ['v', 'w', 'f', 't']) then
          Result := ConstExpr(0)       { an integer count has no fraction digits }
        else if not JavaScript then
        begin
          Include(Used, 'n');          { n and i are the count }
          Result := TextExpr('n', 5);
        end
        else if (Name = 'n') and NumericN then
        begin
          Include(Used, 'N');
          Result := TextExpr('n', 5);
        end
        else if Name = 'n' then
        begin
          { exact for any number of digits: the integer part, and the
            fraction tested apart }
          Include(Used, 'i');
          Include(Used, 'z');
          Result := TextExpr('i', 5, True);
        end
        else
        begin
          Include(Used, Name);
          Result := TextExpr(Name, 5);
        end;
      pnMod:
        begin
          X := Number(A);
          if X.IsConst then
            Result := ConstExpr(X.Value mod Value)
          else
            Result := TextExpr(Wrap(X, 4) + ' % ' + IntToStr(Value), 4, X.Fractional);
        end;
    else
      raise EPluralRuleError.Create('not a numeric node');
    end;
end;

function Bool(B: Boolean): TCExpr;
begin
  Result := ConstExpr(Ord(B));
end;

{ X tested against the ranges of Node: in them, or with Negated not in
  them; Integral: the value must also be an integer ('=' and 'in'). }
function TExprWriter.RangeTest(const X: TCExpr; Node: Integer; Integral, Negated: Boolean): TCExpr;
var
  R: TPluralRange;
  Item, Joined, Op: string;
  Count, ItemLevel: Integer;
  Check: Boolean;
begin
  if X.IsConst then
  begin
    Result := Bool(False);
    for R in Nodes[Node].Ranges do
      if (X.Value >= R.Lo) and (X.Value <= R.Hi) then
        Result := Bool(True);
    if Negated then
      Result := Bool(Result.Value = 0);
    Exit;
  end;
  Check := X.Fractional;   { n as i: the fraction must be zero }
  if Negated then Op := ' && ' else Op := ' || ';
  Joined := '';
  Count := 0;
  ItemLevel := 3;
  for R in Nodes[Node].Ranges do
  begin
    if R.Lo = R.Hi then
    begin
      if Negated then
        Item := Wrap(X, 4) + ' != ' + IntToStr(R.Lo)
      else
        Item := Wrap(X, 4) + ' == ' + IntToStr(R.Lo);
      ItemLevel := 3;
    end
    else if not Negated then
    begin
      Item := Wrap(X, 4) + ' >= ' + IntToStr(R.Lo) + ' && ' + Wrap(X, 4) + ' <= ' + IntToStr(R.Hi);
      ItemLevel := 2;
    end
    else
    begin
      Item := Wrap(X, 4) + ' < ' + IntToStr(R.Lo) + ' || ' + Wrap(X, 4) + ' > ' + IntToStr(R.Hi);
      ItemLevel := 1;
    end;
    Inc(Count);
    if Count > 1 then
      Joined := Joined + Op;
    { an item joined to others keeps its own grouping }
    if (Length(Nodes[Node].Ranges) > 1) and (ItemLevel < 3) then
      Item := '(' + Item + ')';
    Joined := Joined + Item;
  end;
  if Count = 1 then
    Result := TextExpr(Joined, ItemLevel)
  else if Negated then
    Result := TextExpr(Joined, 2)
  else
    Result := TextExpr(Joined, 1);
  if Check then
    if Negated then
      Result := Guarded(-1, Result.Text, Result.Level)
    else
      Result := Guarded(1, Result.Text, Result.Level);
end;

{ The operand of 'within', which compares the value itself (2.5 is
  within 2..3). }
function TExprWriter.WithinOperand(Node: Integer): TCExpr;
begin
  NumericN := True;
  Result := Number(Node);
  NumericN := False;
end;

function TExprWriter.Condition(Node: Integer): TCExpr;
var
  L, R: TCExpr;
begin
  with Nodes[Node] do
    case Kind of
      pnIs, pnIsNot:
        begin
          L := Number(A);
          if L.IsConst then
            Result := Bool((L.Value = Value) = (Kind = pnIs))
          else if (Kind = pnIs) and L.Fractional then
            Result := Guarded(1, Wrap(L, 4) + ' == ' + IntToStr(Value), 3)
          else if Kind = pnIs then
            Result := TextExpr(Wrap(L, 4) + ' == ' + IntToStr(Value), 3)
          else if L.Fractional then
            Result := Guarded(-1, Wrap(L, 4) + ' != ' + IntToStr(Value), 3)
          else
            Result := TextExpr(Wrap(L, 4) + ' != ' + IntToStr(Value), 3);
        end;
      pnIn: Result := RangeTest(Number(A), Node, True, False);
      pnWithin: Result := RangeTest(WithinOperand(A), Node, False, False);
      pnNot:
        if Nodes[A].Kind = pnIn then
          Result := RangeTest(Number(Nodes[A].A), A, True, True)
        else if Nodes[A].Kind = pnWithin then
          Result := RangeTest(WithinOperand(Nodes[A].A), A, False, True)
        else
        begin
          L := Condition(A);
          if L.IsConst then
            Result := Bool(L.Value = 0)
          else
            Result := TextExpr('!(' + L.Text + ')', 3);
        end;
      pnAnd, pnOr:
        begin
          L := Condition(A);
          R := Condition(B);
          if Kind = pnAnd then
          begin
            if (L.IsConst and (L.Value = 0)) or (R.IsConst and (R.Value = 0)) then
              Result := Bool(False)
            else if L.IsConst then
              Result := R
            else if R.IsConst then
              Result := L
            else if (L.Guard > 0) or (R.Guard > 0) then
              { one test of the fraction for the whole conjunction: under
                ts == '' a negated test "ts != '' || X" is X }
              Result := Guarded(1, Unguarded(L) + ' && ' + Unguarded(R), 2)
            else
              Result := TextExpr(Wrap(L, 2) + ' && ' + Wrap(R, 2), 2);
          end
          else
          begin
            if (L.IsConst and (L.Value <> 0)) or (R.IsConst and (R.Value <> 0)) then
              Result := Bool(True)
            else if L.IsConst then
              Result := R
            else if R.IsConst then
              Result := L
            else
              Result := TextExpr(Wrap(L, 1) + ' || ' + Wrap(R, 1), 1);
          end;
        end;
    else
      raise EPluralRuleError.Create('not a condition node');
    end;
end;

function TPluralRule.ToGettext: string;
var
  Used: array of string;
  I, J: Integer;
  W: TExprWriter;
  C: TCExpr;
  Expr: string;
  Closed: Boolean;

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
  { the tags used and 'other', indexed in the order of PluralTags }
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
  W := Default(TExprWriter);
  W.Nodes := NodesOf(FTree);
  W.JavaScript := False;
  Expr := '';
  Closed := False;
  for I := 0 to High(FTags) do
  begin
    C := W.Condition(FRoots[I]);
    if C.IsConst and (C.Value = 0) then
      Continue;                  { never true for an integer count }
    if C.IsConst then
    begin
      Expr := Expr + IntToStr(Index(FTags[I]));
      Closed := True;
      Break;
    end;
    Expr := Expr + C.Text + ' ? ' + IntToStr(Index(FTags[I])) + ' : ';
  end;
  if not Closed then
    Expr := Expr + IntToStr(Index('other'));
  Result := 'nplurals=' + IntToStr(Length(Used)) + '; plural=(' + Expr + ');';
end;

function TPluralRule.ToJavaScript: string;
var
  I: Integer;
  W: TExprWriter;
  C: TCExpr;
  Expr, Vars: string;
  Closed: Boolean;

  procedure AddVar(const Decl: string);
  begin
    if Vars = '' then
      Vars := 'var ' + Decl
    else
      Vars := Vars + ', ' + Decl;
  end;

begin
  W := Default(TExprWriter);
  W.Nodes := NodesOf(FTree);
  W.JavaScript := True;
  Expr := '';
  Closed := False;
  for I := 0 to High(FTags) do
  begin
    C := W.Condition(FRoots[I]);
    if C.IsConst and (C.Value = 0) then
      Continue;
    if C.IsConst then
    begin
      Expr := Expr + '''' + FTags[I] + '''';
      Closed := True;
      Break;
    end;
    Expr := Expr + C.Text + ' ? ''' + FTags[I] + ''' : ';
  end;
  if not Closed then
    Expr := Expr + '''other''';
  { the operands from the decimal text of the number, sign dropped and
    exponent notation ('1E+3', '1e-7') written out }
  Vars := '';
  if W.Used * ['v', 'w', 'f', 't', 'z'] <> [] then
    AddVar('p = s.indexOf(''.''), fs = p < 0 ? '''' : s.slice(p + 1)');
  if W.Used * ['w', 't', 'z'] <> [] then
    AddVar('ts = fs.replace(/0+$/, '''')');
  if 'i' in W.Used then AddVar('i = parseInt(s, 10)');
  if 'v' in W.Used then AddVar('v = fs.length');
  if 'w' in W.Used then AddVar('w = ts.length');
  if 'f' in W.Used then AddVar('f = +fs || 0');
  if 't' in W.Used then AddVar('t = +ts || 0');
  Result := '(function(n) { ';
  if W.Used <> [] then
    Result := Result + 'var s = String(n).replace(/^[-+]/, ''''); ' +
      'if (/e/i.test(s)) s = Number(s).toFixed(20).replace(/\.?0+$/, ''''); ';
  if Vars <> '' then
    Result := Result + Vars + '; ';
  if 'N' in W.Used then
    Result := Result + 'n = +s; ';
  Result := Result + 'return ' + Expr + '; })';
end;

end.
