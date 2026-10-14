{ cldr.etree - the XML files of the CLDR release as a tree of elements
  with the semantics of Python's xml.etree.ElementTree (with its default
  parser, expat):

  - an element has a text (the character data before its first child)
    and a tail (the character data after its end tag, up to the next tag);
    either is absent (HasText, HasTail False) when there is no character
    data at all;
  - comments and processing instructions are left out, and the character
    data around a comment joins;
  - the document type declaration is skipped: no external DTD is read, so
    no attribute gets a default value from it;
  - attribute values are normalized (tab, newline and carriage return
    become spaces), line ends become newlines, and the predefined entities
    and character references are replaced.

  FindAll, Find and FindText take the paths of ElementPath that the
  generator uses: tags or '*' separated by '/', a leading '.', and '//'
  (every descendant). The XML is UTF-8; the strings are UTF-8. }
unit cldr.etree;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, cldr.pystr;

type
  TXElem = class;
  TXElemArray = array of TXElem;

  TXElem = class
  public
    Tag: string;
    AttrNames, AttrValues: array of string;
    AttrCount: Integer;
    Text, Tail: string;
    HasText, HasTail: Boolean;
    Children: TXElemArray;
    ChildCount: Integer;
    { The parent element in the file (unchanged when the element is
      removed from it); nil for the root. }
    Parent: TXElem;
    function HasAttr(const Name: string): Boolean;
    function TryAttr(const Name: string; out Value: string): Boolean;
    { The value of an attribute that must be present (raises otherwise). }
    function Attr(const Name: string): string;
    function AttrDef(const Name, Default: string): string;
    { The elements a path selects, in document order. }
    function FindAll(const Path: string): TXElemArray;
    { The first element a path selects, or nil. }
    function Find(const Path: string): TXElem;
    { findtext: False when the path selects nothing; else Value is the
      text of the first element selected ('' when it has none). }
    function FindText(const Path: string; out Value: string): Boolean;
    { iter(): the element and its descendants, in document order. }
    function Iter: TXElemArray;
    function IndexOfChild(E: TXElem): Integer;
    { remove(): raises when E is not a child. }
    procedure RemoveChild(E: TXElem);
    procedure AddChild(E: TXElem);
  end;

  TXDoc = class
  private
    FAll: TFPList;
    procedure Parse(const S: string; const FileName: string);
  public
    Root: TXElem;
    constructor LoadFromFile(const FileName: string);
    destructor Destroy; override;
  end;

  EXmlError = class(Exception);

function ReadFileBytes(const FileName: string): string;

implementation

function ReadFileBytes(const FileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if Length(Result) > 0 then
      F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

{ TXElem }

function TXElem.HasAttr(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to AttrCount - 1 do
    if AttrNames[I] = Name then
      Exit(True);
  Result := False;
end;

function TXElem.TryAttr(const Name: string; out Value: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to AttrCount - 1 do
    if AttrNames[I] = Name then
    begin
      Value := AttrValues[I];
      Exit(True);
    end;
  Value := '';
  Result := False;
end;

function TXElem.Attr(const Name: string): string;
begin
  if not TryAttr(Name, Result) then
    raise EXmlError.CreateFmt('<%s> has no attribute %s', [Tag, Name]);
end;

function TXElem.AttrDef(const Name, Default: string): string;
begin
  if not TryAttr(Name, Result) then
    Result := Default;
end;

procedure AddTo(var A: TXElemArray; var N: Integer; E: TXElem); inline;
begin
  if N = Length(A) then
    SetLength(A, N * 2 + 4);
  A[N] := E;
  Inc(N);
end;

procedure CollectDescendants(E: TXElem; const Tag: string; var A: TXElemArray;
  var N: Integer);
var
  I: Integer;
  C: TXElem;
begin
  for I := 0 to E.ChildCount - 1 do
  begin
    C := E.Children[I];
    if (Tag = '*') or (C.Tag = Tag) then
      AddTo(A, N, C);
    CollectDescendants(C, Tag, A, N);
  end;
end;

function TXElem.FindAll(const Path: string): TXElemArray;
var
  Steps: TStringArray;
  Ctx, Next: TXElemArray;
  NCtx, NNext, I, J, K: Integer;
  Step: string;
  E: TXElem;
begin
  Steps := PySplitSep(Path, '/');
  SetLength(Ctx, 1);
  Ctx[0] := Self;
  NCtx := 1;
  I := 0;
  while I < Length(Steps) do
  begin
    Step := Steps[I];
    if Step = '.' then
    begin
      Inc(I);
      Continue;
    end;
    Next := nil;
    NNext := 0;
    if Step = '' then
    begin
      // '//': the next step selects among every descendant
      Inc(I);
      if I >= Length(Steps) then
        raise EXmlError.CreateFmt('bad path %s', [Path]);
      for J := 0 to NCtx - 1 do
        CollectDescendants(Ctx[J], Steps[I], Next, NNext);
    end
    else
      for J := 0 to NCtx - 1 do
      begin
        E := Ctx[J];
        for K := 0 to E.ChildCount - 1 do
          if (Step = '*') or (E.Children[K].Tag = Step) then
            AddTo(Next, NNext, E.Children[K]);
      end;
    Ctx := Next;
    NCtx := NNext;
    Inc(I);
  end;
  SetLength(Ctx, NCtx);
  Result := Ctx;
end;

function TXElem.Find(const Path: string): TXElem;
var
  A: TXElemArray;
begin
  A := FindAll(Path);
  if Length(A) > 0 then
    Result := A[0]
  else
    Result := nil;
end;

function TXElem.FindText(const Path: string; out Value: string): Boolean;
var
  E: TXElem;
begin
  E := Find(Path);
  Result := E <> nil;
  if Result then
    Value := E.Text
  else
    Value := '';
end;

procedure CollectIter(E: TXElem; var A: TXElemArray; var N: Integer);
var
  I: Integer;
begin
  AddTo(A, N, E);
  for I := 0 to E.ChildCount - 1 do
    CollectIter(E.Children[I], A, N);
end;

function TXElem.Iter: TXElemArray;
var
  N: Integer;
begin
  Result := nil;
  N := 0;
  CollectIter(Self, Result, N);
  SetLength(Result, N);
end;

function TXElem.IndexOfChild(E: TXElem): Integer;
var
  I: Integer;
begin
  for I := 0 to ChildCount - 1 do
    if Children[I] = E then
      Exit(I);
  Result := -1;
end;

procedure TXElem.RemoveChild(E: TXElem);
var
  I, J: Integer;
begin
  I := IndexOfChild(E);
  if I < 0 then
    raise EXmlError.CreateFmt('<%s> is not a child of <%s>', [E.Tag, Tag]);
  for J := I to ChildCount - 2 do
    Children[J] := Children[J + 1];
  Dec(ChildCount);
  Children[ChildCount] := nil;
end;

procedure TXElem.AddChild(E: TXElem);
begin
  AddTo(Children, ChildCount, E);
end;

{ TXDoc }

constructor TXDoc.LoadFromFile(const FileName: string);
begin
  FAll := TFPList.Create;
  Parse(ReadFileBytes(FileName), FileName);
end;

destructor TXDoc.Destroy;
var
  I: Integer;
begin
  if FAll <> nil then
    for I := 0 to FAll.Count - 1 do
      TObject(FAll[I]).Free;
  FAll.Free;
  inherited Destroy;
end;

procedure TXDoc.Parse(const S: string; const FileName: string);
var
  P, Len: Integer;
  Stack: TXElemArray;
  Depth: Integer;
  Data: string;
  Last: TXElem;
  LastIsTail: Boolean;

  procedure Fail(const Msg: string);
  begin
    raise EXmlError.CreateFmt('%s: %s (at byte %d)', [FileName, Msg, P]);
  end;

  { The character data collected since the last tag goes to the text of
    the element last opened, or to the tail of the element last closed. }
  procedure Flush;
  begin
    if Data = '' then
      Exit;
    if Last <> nil then
      if LastIsTail then
      begin
        Last.Tail := Data;
        Last.HasTail := True;
      end
      else
      begin
        Last.Text := Data;
        Last.HasText := True;
      end;
    Data := '';
  end;

  function StartsAt(const Lit: string): Boolean;
  begin
    Result := (P + Length(Lit) - 1 <= Len) and
      (CompareByte(S[P], Lit[1], Length(Lit)) = 0);
  end;

  procedure SkipPast(const Lit: string);
  var
    Q: Integer;
  begin
    Q := Pos(Lit, S, P);
    if Q = 0 then
      Fail('unterminated markup');
    P := Q + Length(Lit);
  end;

  { An entity or character reference at S[P] ('&'); P moves past it. }
  function Reference: string;
  var
    Q: Integer;
    Name: string;
    CP: Cardinal;
  begin
    Q := P + 1;
    while (Q <= Len) and (S[Q] <> ';') do
      Inc(Q);
    if Q > Len then
      Fail('unterminated reference');
    Name := Copy(S, P + 1, Q - P - 1);
    P := Q + 1;
    if Name = 'amp' then Result := '&'
    else if Name = 'lt' then Result := '<'
    else if Name = 'gt' then Result := '>'
    else if Name = 'quot' then Result := '"'
    else if Name = 'apos' then Result := ''''
    else if (Length(Name) > 2) and (Name[1] = '#') and (Name[2] = 'x') then
    begin
      CP := StrToInt('$' + Copy(Name, 3, MaxInt));
      Result := CodePointToUTF8(CP);
    end
    else if (Length(Name) > 1) and (Name[1] = '#') then
    begin
      CP := StrToInt(Copy(Name, 2, MaxInt));
      Result := CodePointToUTF8(CP);
    end
    else
      Fail('undefined entity &' + Name + ';');
  end;

  { Character data up to the next '<'. }
  procedure CharData;
  var
    Start: Integer;
  begin
    Start := P;
    while (P <= Len) and (S[P] <> '<') do
    begin
      case S[P] of
        '&':
          begin
            Data := Data + Copy(S, Start, P - Start) + Reference;
            Start := P;
          end;
        #13:
          begin
            Data := Data + Copy(S, Start, P - Start) + #10;
            Inc(P);
            if (P <= Len) and (S[P] = #10) then
              Inc(P);
            Start := P;
          end;
      else
        Inc(P);
      end;
    end;
    Data := Data + Copy(S, Start, P - Start);
  end;

  function IsNameEnd(C: Char): Boolean; inline;
  begin
    Result := C in [' ', #9, #10, #13, '/', '>', '='];
  end;

  procedure SkipSpace;
  begin
    while (P <= Len) and (S[P] in [' ', #9, #10, #13]) do
      Inc(P);
  end;

  function AttrValue: string;
  var
    Quote: Char;
    Start: Integer;
  begin
    Quote := S[P];
    if not (Quote in ['"', '''']) then
      Fail('expected a quoted attribute value');
    Inc(P);
    Result := '';
    Start := P;
    while (P <= Len) and (S[P] <> Quote) do
      case S[P] of
        '&':
          begin
            Result := Result + Copy(S, Start, P - Start) + Reference;
            Start := P;
          end;
        #13:
          begin
            Result := Result + Copy(S, Start, P - Start) + ' ';
            Inc(P);
            if (P <= Len) and (S[P] = #10) then
              Inc(P);
            Start := P;
          end;
        #9, #10:
          begin
            Result := Result + Copy(S, Start, P - Start) + ' ';
            Inc(P);
            Start := P;
          end;
      else
        Inc(P);
      end;
    if P > Len then
      Fail('unterminated attribute value');
    Result := Result + Copy(S, Start, P - Start);
    Inc(P);
  end;

  procedure StartTag;
  var
    Start: Integer;
    E: TXElem;
    Name: string;
  begin
    Flush;
    Inc(P); // '<'
    Start := P;
    while (P <= Len) and not IsNameEnd(S[P]) do
      Inc(P);
    E := TXElem.Create;
    FAll.Add(E);
    E.Tag := Copy(S, Start, P - Start);
    if Depth > 0 then
    begin
      E.Parent := Stack[Depth - 1];
      E.Parent.AddChild(E);
    end
    else if Root = nil then
      Root := E
    else
      Fail('a second root element');
    while True do
    begin
      SkipSpace;
      if P > Len then
        Fail('unterminated start tag');
      if S[P] = '/' then
      begin
        Inc(P);
        if (P > Len) or (S[P] <> '>') then
          Fail('expected >');
        Inc(P);
        // an empty element: opened and closed
        Last := E;
        LastIsTail := True;
        Exit;
      end;
      if S[P] = '>' then
      begin
        Inc(P);
        if Depth = Length(Stack) then
          SetLength(Stack, Depth * 2 + 8);
        Stack[Depth] := E;
        Inc(Depth);
        Last := E;
        LastIsTail := False;
        Exit;
      end;
      Start := P;
      while (P <= Len) and not IsNameEnd(S[P]) do
        Inc(P);
      Name := Copy(S, Start, P - Start);
      if Name = '' then
        Fail('expected an attribute name');
      SkipSpace;
      if (P > Len) or (S[P] <> '=') then
        Fail('expected =');
      Inc(P);
      SkipSpace;
      if E.AttrCount = Length(E.AttrNames) then
      begin
        SetLength(E.AttrNames, E.AttrCount * 2 + 2);
        SetLength(E.AttrValues, E.AttrCount * 2 + 2);
      end;
      E.AttrNames[E.AttrCount] := Name;
      E.AttrValues[E.AttrCount] := AttrValue;
      Inc(E.AttrCount);
    end;
  end;

  procedure EndTag;
  var
    Start: Integer;
    Name: string;
  begin
    Flush;
    Inc(P, 2); // '</'
    Start := P;
    while (P <= Len) and not IsNameEnd(S[P]) do
      Inc(P);
    Name := Copy(S, Start, P - Start);
    SkipSpace;
    if (P > Len) or (S[P] <> '>') then
      Fail('expected >');
    Inc(P);
    if (Depth = 0) or (Stack[Depth - 1].Tag <> Name) then
      Fail('mismatched end tag </' + Name + '>');
    Dec(Depth);
    Last := Stack[Depth];
    LastIsTail := True;
  end;

  procedure Doctype;
  var
    InSubset: Boolean;
    Quote: Char;
  begin
    InSubset := False;
    Quote := #0;
    Inc(P, 9);
    while P <= Len do
    begin
      if Quote <> #0 then
      begin
        if S[P] = Quote then
          Quote := #0;
      end
      else
        case S[P] of
          '"', '''': Quote := S[P];
          '[': InSubset := True;
          ']': InSubset := False;
          '>':
            if not InSubset then
            begin
              Inc(P);
              Exit;
            end;
        end;
      Inc(P);
    end;
    Fail('unterminated document type declaration');
  end;

  procedure CData;
  var
    Q: Integer;
  begin
    Inc(P, 9);
    Q := Pos(']]>', S, P);
    if Q = 0 then
      Fail('unterminated CDATA section');
    Data := Data + StringReplace(StringReplace(Copy(S, P, Q - P), #13#10, #10,
      [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    P := Q + 3;
  end;

begin
  Len := Length(S);
  P := 1;
  if StartsAt(#$EF#$BB#$BF) then
    Inc(P, 3);
  Depth := 0;
  Data := '';
  Last := nil;
  LastIsTail := False;
  Root := nil;
  while P <= Len do
  begin
    if S[P] <> '<' then
      CharData
    else if StartsAt('<?') then
      SkipPast('?>')
    else if StartsAt('<!--') then
      SkipPast('-->')
    else if StartsAt('<![CDATA[') then
      CData
    else if StartsAt('<!DOCTYPE') then
      Doctype
    else if StartsAt('</') then
      EndTag
    else
      StartTag;
  end;
  Flush;
  if (Root = nil) or (Depth <> 0) then
    Fail('incomplete document');
end;

end.
