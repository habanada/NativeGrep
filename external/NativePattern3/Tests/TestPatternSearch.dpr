program TestPatternSearch;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  NativePattern,
  NativePattern.Core,
  NativePattern.BoyerMooreHorspool,
  NativePattern.Bitap,
  NativePattern.Sbndm,
  NativePattern.RabinKarp,
  NativePattern.Levenshtein,
  NativePattern.Myers,
  NativePattern.TwoWay,
  NativePattern.Avx2,
  NativePattern.AhoCorasick,
  NativePattern.CommentzWalter;

function BytesOf(const Values: array of Byte): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I] := Values[I];
end;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
  Writeln(Name + ' OK');
end;

procedure TestBmh;
var
  S: TBoyerMooreHorspoolSearcher;
  Data: TBytes;
  M: TPatternMatch;
  A: TPatternMatches;
begin
  Data := BytesOf([$00, $11, $22, $33, $11, $22, $33]);
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([$11, $22]));
  try
    M := S.FindFirst(Data);
    Check(M.Found and (M.Offset = 1), 'BMH FindFirst');
    A := S.FindAll(Data);
    Check((Length(A) = 2) and (A[0].Offset = 1) and (A[1].Offset = 4), 'BMH FindAll');
  finally
    S.Free;
  end;
end;

procedure TestBitap;
var
  S: TBitapSearcher;
  M: TPatternMatch;
  Data: TBytes;
begin
  Data := BytesOf([$90, $48, $8B, $19, $4F, $90]);
  S := TPatternSearch.CompileSignature('48 8B ?? 4?');
  try
    M := S.FindFirst(Data);
    Check(M.Found and (M.Offset = 1), 'Bitap masked');
  finally
    S.Free;
  end;
end;


procedure TestSbndm;
var
  S: TSbndmSearcher;
  G: TSinglePatternSearcher;
  M: TPatternMatch;
  A: TPatternMatches;
  Data: TBytes;
begin
  Data := BytesOf([$61, $61, $61, $61, $61]);
  S := TSbndmSearcher.Create(BytesOf([$61, $61, $61]));
  try
    A := S.FindAll(Data);
    Check((Length(A) = 3) and (A[0].Offset = 0) and (A[1].Offset = 1) and (A[2].Offset = 2), 'SBNDM overlaps');
  finally
    S.Free;
  end;
  G := TPatternSearch.CompileMaskedSignature('48 8B ?? 4?', msaSbndm);
  try
    M := G.FindFirst(BytesOf([$90, $48, $8B, $19, $4F, $90]));
    Check(M.Found and (M.Offset = 1) and (M.MatchLength = 4), 'SBNDM masked');
  finally
    G.Free;
  end;
  S := TSbndmSearcher.Create('Welt');
  try
    M := S.FindFirst('Hallo Welt Welt');
    Check(M.Found and (M.Offset = 6) and (M.MatchLength = 4) and (M.MatchUnit = muChar), 'SBNDM string');
  finally
    S.Free;
  end;
end;

procedure TestMyers;
var
  S: TMyersSearcher;
  M: TPatternMatch;
  TextPattern, TextValue: string;
begin
  S := TMyersSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('x'), Ord('a'), Ord('x'), Ord('c'), Ord('z')]));
    Check(M.Found and (M.Offset = 2) and (M.MatchLength = 3) and (M.Distance = 1), 'Myers substitution');
    M := S.FindFirst(BytesOf([Ord('x'), Ord('x'), Ord('a'), Ord('b'), Ord('x'), Ord('c'), Ord('z')]));
    Check(M.Found and (M.Offset = 2) and (M.MatchLength = 4) and (M.Distance = 1), 'Myers insertion');
    M := S.FindFirst(BytesOf([Ord('x'), Ord('x'), Ord('a'), Ord('c'), Ord('z')]));
    Check(M.Found and (M.Offset = 2) and (M.MatchLength = 2) and (M.Distance = 1), 'Myers deletion');
    M := S.FindFirst(BytesOf([Ord('a'), Ord('b'), Ord('c'), Ord('x'), Ord('x'), Ord('a'), Ord('b'), Ord('c')]), 4);
    Check(M.Found and (M.Offset = 5) and (M.Distance = 0), 'Myers StartOffset');
  finally
    S.Free;
  end;
  TextPattern := Char($0100) + 'BC';
  TextValue := 'xx' + Char($0100) + 'XCyy';
  S := TMyersSearcher.Create(TextPattern, 1);
  try
    M := S.FindFirst(TextValue);
    Check(M.Found and (M.Offset = 2) and (M.MatchLength = 3) and (M.Distance = 1) and (M.MatchUnit = muChar), 'Myers Unicode string');
  finally
    S.Free;
  end;
end;

procedure TestMyersStream;
var
  S: TMyersSearcher;
  Stream: TMemoryStream;
  Data: TBytes;
  M: TPatternMatch;
begin
  SetLength(Data, 65542);
  FillChar(Data[0], Length(Data), 0);
  Data[65534] := Ord('A');
  Data[65535] := Ord('B');
  Data[65536] := Ord('X');
  Data[65537] := Ord('C');
  Data[65538] := Ord('D');
  Stream := TMemoryStream.Create;
  S := TMyersSearcher.Create(BytesOf([Ord('A'), Ord('B'), Ord('C'), Ord('D')]), 1);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    Check(M.Found and (M.Offset = 65534) and (M.MatchLength = 5) and (M.Distance = 1) and (Stream.Position = 0), 'Myers stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;


procedure TestFuzzyStreamImprovement;
var
  Myers: TMyersSearcher;
  Levenshtein: TLevenshteinSearcher;
  Stream: TMemoryStream;
  Data: TBytes;
  M: TPatternMatch;
begin
  SetLength(Data, 65540);
  FillChar(Data[0], Length(Data), 0);
  Data[65533] := Ord('A');
  Data[65534] := Ord('B');
  Data[65535] := Ord('C');
  Data[65536] := Ord('D');
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Myers := TMyersSearcher.Create(BytesOf([Ord('A'), Ord('B'), Ord('C'), Ord('D')]), 1);
    try
      Stream.Position := 0;
      M := Myers.FindFirst(Stream);
      Check(M.Found and (M.Offset = 65533) and (M.MatchLength = 4) and (M.Distance = 0) and (Stream.Position = 0), 'Myers stream improvement');
    finally
      Myers.Free;
    end;
    Levenshtein := TLevenshteinSearcher.Create(BytesOf([Ord('A'), Ord('B'), Ord('C'), Ord('D')]), 1);
    try
      Stream.Position := 0;
      M := Levenshtein.FindFirst(Stream);
      Check(M.Found and (M.Offset = 65533) and (M.MatchLength = 4) and (M.Distance = 0) and (Stream.Position = 0), 'Levenshtein stream improvement');
    finally
      Levenshtein.Free;
    end;
  finally
    Stream.Free;
  end;
end;


procedure TestBitWordBoundary;
var
  Pattern, Data: TBytes;
  I: Integer;
  S1: TSbndmSearcher;
  S2: TMyersSearcher;
  M: TPatternMatch;
begin
  SetLength(Pattern, 64);
  SetLength(Data, 68);
  FillChar(Data[0], Length(Data), $FF);
  for I := 0 to 63 do
  begin
    Pattern[I] := Byte(I);
    Data[I + 2] := Byte(I);
  end;
  S1 := TSbndmSearcher.Create(Pattern);
  try
    M := S1.FindFirst(Data);
    Check(M.Found and (M.Offset = 2) and (M.MatchLength = 64), 'SBNDM 64-byte boundary');
  finally
    S1.Free;
  end;
  S2 := TMyersSearcher.Create(Pattern, 0);
  try
    M := S2.FindFirst(Data);
    Check(M.Found and (M.Offset = 2) and (M.MatchLength = 64) and (M.Distance = 0), 'Myers 64-byte boundary');
  finally
    S2.Free;
  end;
end;

procedure TestFacadeExtensions;
var
  M: TPatternMatch;
  Pattern: TBytePattern;
begin
  M := TPatternSearch.FindFirst(BytesOf([0, 1, 2, 3, 4]), BytesOf([2, 3]), saSbndm);
  Check(M.Found and (M.Offset = 2), 'Facade SBNDM');
  M := TPatternSearch.FindFirst(BytesOf([Ord('a'), Ord('x'), Ord('c')]), BytesOf([Ord('a'), Ord('b'), Ord('c')]), saMyers, 1);
  Check(M.Found and (M.Offset = 0) and (M.Distance = 1), 'Facade Myers');
  Pattern := TBytePattern.Parse('4? ?? 6F');
  M := TPatternSearch.FindFirst(BytesOf([$10, $4A, $55, $6F]), Pattern, msaSbndm);
  Check(M.Found and (M.Offset = 1), 'Facade masked SBNDM');
end;

procedure TestTwoWay;
var
  S: TTwoWaySearcher;
  M: TPatternMatch;
  A: TPatternMatches;
  Pattern, Data: TBytes;
  I: Integer;
begin
  S := TTwoWaySearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('a'), Ord('b'), Ord('a')]));
  try
    A := S.FindAll(BytesOf([Ord('x'), Ord('a'), Ord('b'), Ord('a'), Ord('b'), Ord('a'), Ord('b'), Ord('a')]));
    Check((Length(A) = 2) and (A[0].Offset = 1) and (A[1].Offset = 3), 'Two-Way periodic overlaps');
  finally
    S.Free;
  end;
  SetLength(Pattern, 300);
  SetLength(Data, 640);
  FillChar(Data[0], Length(Data), $A5);
  for I := 0 to High(Pattern) do
    Pattern[I] := Byte((I * 37 + 11) and $FF);
  Move(Pattern[0], Data[271], Length(Pattern));
  S := TTwoWaySearcher.Create(Pattern);
  try
    M := S.FindFirst(Data);
    Check(M.Found and (M.Offset = 271) and (M.MatchLength = 300), 'Two-Way long pattern');
  finally
    S.Free;
  end;
end;

procedure TestCommentzWalter;
var
  S: TCommentzWalterSearcher;
  M: TPatternMatch;
  A: TPatternMatches;
  Stream: TMemoryStream;
  Data: TBytes;
begin
  S := TCommentzWalterSearcher.Create([BytesOf([Ord('h'), Ord('e')]), BytesOf([Ord('s'), Ord('h'), Ord('e')]), BytesOf([Ord('h'), Ord('e'), Ord('r'), Ord('s')]), BytesOf([Ord('e'), Ord('r'), Ord('s')])]);
  try
    A := S.FindAll(BytesOf([Ord('u'), Ord('s'), Ord('h'), Ord('e'), Ord('r'), Ord('s')]));
    Check((Length(A) = 4) and (A[0].Offset = 1) and (A[0].PatternIndex = 1) and (A[1].Offset = 2) and (A[2].Offset = 2) and (A[3].Offset = 3), 'Commentz-Walter FindAll');
    M := S.FindFirst(BytesOf([Ord('x'), Ord('x'), Ord('u'), Ord('s'), Ord('h'), Ord('e'), Ord('r'), Ord('s')]), 3);
    Check(M.Found and (M.Offset = 3) and (M.PatternIndex = 1), 'Commentz-Walter StartOffset');
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(['eins', 'zwei', 'drei', 'vier']);
  try
    M := S.FindFirst('xxdrei vier');
    Check(M.Found and (M.Offset = 2) and (M.PatternIndex = 2) and (M.MatchUnit = muChar), 'Commentz-Walter string');
  finally
    S.Free;
  end;
  SetLength(Data, 65544);
  FillChar(Data[0], Length(Data), 0);
  Data[65534] := $DE;
  Data[65535] := $AD;
  Data[65536] := $BE;
  Data[65537] := $EF;
  Stream := TMemoryStream.Create;
  S := TCommentzWalterSearcher.Create([BytesOf([$AA, $BB, $CC, $DD]), BytesOf([$DE, $AD, $BE, $EF]), BytesOf([$10, $20, $30, $40]), BytesOf([$01, $02, $03, $04])]);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    Check(M.Found and (M.Offset = 65534) and (M.PatternIndex = 1) and (Stream.Position = 0), 'Commentz-Walter stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TestDispatcher;
var
  S: TSinglePatternSearcher;
  M: TMultiPatternSearcher;
  Pattern: TBytes;
begin
  SetLength(Pattern, 300);
  FillChar(Pattern[0], Length(Pattern), $5A);
  S := TPatternSearch.Compile(Pattern);
  try
    Check(S is TTwoWaySearcher, 'Dispatcher long exact');
  finally
    S.Free;
  end;
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saAuto, 1);
  try
    Check(S is TMyersSearcher, 'Dispatcher fuzzy short');
  finally
    S.Free;
  end;
  M := TPatternSearch.CompileMany([BytesOf([1, 2, 3, 4]), BytesOf([2, 3, 4, 5]), BytesOf([3, 4, 5, 6]), BytesOf([4, 5, 6, 7])]);
  try
    Check(M is TCommentzWalterSearcher, 'Dispatcher multi-pattern');
  finally
    M.Free;
  end;
  if TAvx2Searcher.Available then
  begin
    S := TPatternSearch.Compile(BytesOf([$DE, $AD, $BE, $EF]));
    try
      Check(S is TAvx2Searcher, 'Dispatcher AVX2');
    finally
      S.Free;
    end;
  end;
end;

procedure TestAvx2;
var
  S: TAvx2Searcher;
  M: TPatternMatch;
  Data: TBytes;
begin
  if not TAvx2Searcher.Available then
    Exit;
  Data := BytesOf([$00, $11, $22, $DE, $AD, $BE, $EF, $33]);
  S := TAvx2Searcher.Create(BytesOf([$DE, $AD, $BE, $EF]));
  try
    M := S.FindFirst(Data);
    Check(M.Found and (M.Offset = 3), 'AVX2 exact');
  finally
    S.Free;
  end;
end;

procedure TestRabinKarp;
var
  S: TRabinKarpSearcher;
  M: TPatternMatch;
begin
  S := TRabinKarpSearcher.Create(BytesOf([1, 2, 3, 4]));
  try
    M := S.FindFirst(BytesOf([9, 8, 1, 2, 3, 4, 7]));
    Check(M.Found and (M.Offset = 2), 'Rabin-Karp');
  finally
    S.Free;
  end;
end;

procedure TestLevenshtein;
var
  S: TLevenshteinSearcher;
  M: TPatternMatch;
begin
  S := TLevenshteinSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('x'), Ord('a'), Ord('x'), Ord('c'), Ord('z')]));
    Check(M.Found and (M.Offset = 2) and (M.Distance = 1), 'Levenshtein bytes');
  finally
    S.Free;
  end;
  S := TLevenshteinSearcher.Create('Hallo', 1);
  try
    M := S.FindFirst('xxHulloyy');
    Check(M.Found and (M.Offset = 2) and (M.Distance = 1) and (M.MatchUnit = muChar), 'Levenshtein string');
  finally
    S.Free;
  end;
end;

procedure TestString;
var
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
begin
  S := TBoyerMooreHorspoolSearcher.Create('Welt');
  try
    M := S.FindFirst('Hallo Welt Welt');
    Check(M.Found and (M.Offset = 6) and (M.MatchLength = 4) and (M.MatchUnit = muChar), 'String search');
  finally
    S.Free;
  end;
end;

procedure TestAho;
var
  S: TAhoCorasickSearcher;
  M: TPatternMatch;
  A: TPatternMatches;
begin
  S := TAhoCorasickSearcher.Create(['he', 'she', 'hers']);
  try
    M := S.FindFirst('ushers');
    Check(M.Found and (M.Offset = 1) and (M.PatternIndex = 1), 'Aho-Corasick FindFirst');
    A := S.FindAll('ushers');
    Check(Length(A) >= 3, 'Aho-Corasick FindAll');
  finally
    S.Free;
  end;
end;

procedure TestStream;
var
  S: TBoyerMooreHorspoolSearcher;
  Stream: TMemoryStream;
  Data, Pattern: TBytes;
  M: TPatternMatch;
begin
  SetLength(Data, 65540);
  FillChar(Data[0], Length(Data), 0);
  Pattern := BytesOf([$DE, $AD, $BE, $EF]);
  Move(Pattern[0], Data[65534], Length(Pattern));
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    Check(M.Found and (M.Offset = 65534) and (Stream.Position = 0), 'Stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TestList;
var
  S: TBoyerMooreHorspoolSearcher;
  List: TList<Byte>;
  M: TPatternMatch;
begin
  List := TList<Byte>.Create;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([2, 3]));
  try
    List.Add(1);
    List.Add(2);
    List.Add(3);
    List.Add(4);
    M := S.FindFirst(List);
    Check(M.Found and (M.Offset = 1), 'TList<Byte>');
  finally
    S.Free;
    List.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TestBmh;
    TestBitap;
    TestSbndm;
    TestBitWordBoundary;
    TestFacadeExtensions;
    TestTwoWay;
    TestCommentzWalter;
    TestDispatcher;
    TestAvx2;
    TestRabinKarp;
    TestLevenshtein;
    TestMyers;
    TestMyersStream;
    TestFuzzyStreamImprovement;
    TestString;
    TestAho;
    TestStream;
    TestList;
    Writeln('ALL PATTERN TESTS OK');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
