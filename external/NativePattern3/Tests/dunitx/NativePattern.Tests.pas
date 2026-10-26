unit NativePattern.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  NativePattern,
  NativePattern.Core,
  NativePattern.BoyerMooreHorspool,
  NativePattern.Bitap,
  NativePattern.Sbndm,
  NativePattern.RabinKarp,
  NativePattern.TwoWay,
  NativePattern.Levenshtein,
  NativePattern.Myers,
  NativePattern.AhoCorasick,
  NativePattern.CommentzWalter,
  NativePattern.Avx2;

type
  {$M+}

  [TestFixture]
  TPatternCoreTests = class
  public
    [Test] procedure NotFoundContract;
    [Test] procedure ParseExactAndWildcards;
    [Test] procedure ParseSingleWildcard;
    [Test] procedure ParseRejectsIncompleteHexByte;
    [Test] procedure ParseRejectsLongToken;
    [Test] procedure MaskedRejectsLengthMismatch;
    [Test] procedure BytePatternIsImmutableFromReturnedArrays;
    [Test] procedure SearcherPatternIsImmutableFromReturnedArray;
    [Test] procedure EmptyPatternRejected;
    [Test] procedure EmptySignatureRejected;
    [Test] procedure BytePatternCopiesInputArrays;
    [Test] procedure SearcherCopiesInputPattern;
    [Test] procedure MaskedEmptyPatternRejected;
    [Test] procedure ExactPatternContract;
    [Test] procedure ExactRejectsEmptyPattern;
    [Test] procedure ParseAcceptsSeparatorsAndLowercase;
    [Test] procedure ParseRejectsInvalidHexCharacters;
  end;

  [TestFixture]
  TPatternExactTests = class
  public
    [Test] procedure ExactAlgorithmsReturnExpectedOffsets;
    [Test] procedure ExactAlgorithmsFindOverlaps;
    [Test] procedure ExactAlgorithmsRespectStartOffset;
    [Test] procedure ExactAlgorithmsHandleSingleByte;
    [Test] procedure ExactAlgorithmsHandlePatternLongerThanData;
    [Test] procedure ExactAlgorithmsHandleEndBoundary;
    [Test] procedure BitAlgorithmsHandle64BytePattern;
    [Test] procedure BitAlgorithmsReject65BytePattern;
    [Test] procedure TwoWayHandlesLongPeriodicPattern;
    [Test] procedure StringOffsetsAreUtf16CodeUnits;
    [Test] procedure PointerInputReturnsExpectedOffset;
    [Test] procedure ListInputReturnsExpectedOffsets;
    [Test] procedure EmptyDataReturnsNoMatch;
    [Test] procedure StartOffsetAtEndReturnsNoMatch;
    [Test] procedure EmbeddedNullStringIsSearchable;
    [Test] procedure SurrogatePairUsesUtf16Units;
    [Test] procedure PointerFindAllReturnsExpectedOffsets;
    [Test] procedure NilPointerReturnsNoMatch;
    [Test] procedure NilListReturnsNoMatch;
    [Test] procedure ByteSearcherRejectsStringInput;
  end;

  [TestFixture]
  TPatternMaskedTests = class
  public
    [Test] procedure BitapMaskedExpectedMatches;
    [Test] procedure SbndmMaskedExpectedMatches;
    [Test] procedure NibbleMasksExpectedMatches;
    [Test] procedure AllWildcardExpectedMatches;
    [Test] procedure MaskIgnoresUnmaskedPatternBits;
    [Test] procedure ArbitraryBitMaskExpectedMatches;
    [Test] procedure CompileSignatureExpectedMatches;
    [Test] procedure CompileMaskedSignatureExpectedMatches;
  end;

  [TestFixture]
  TPatternFuzzyTests = class
  public
    [Test] procedure LevenshteinSubstitution;
    [Test] procedure LevenshteinInsertionAndDeletion;
    [Test] procedure MyersSubstitution;
    [Test] procedure MyersInsertion;
    [Test] procedure MyersDeletion;
    [Test] procedure FuzzyFindAllExpectedMatches;
    [Test] procedure FuzzyEveryStartUsesBestLocalAlignment;
    [Test] procedure FuzzyStartOffset;
    [Test] procedure MyersRejectsPatternOver64;
    [Test] procedure FuzzyRejectsDistanceAtLeastPatternLength;
    [Test] procedure FuzzyStringExpectedMatch;
    [Test] procedure ZeroDistanceMatchesExactSemantics;
  end;

  [TestFixture]
  TPatternMultiTests = class
  public
    [Test] procedure AhoExpectedClassicMatches;
    [Test] procedure CommentzWalterExpectedClassicMatches;
    [Test] procedure MultiDuplicatePatternsRemainDistinct;
    [Test] procedure MultiFindFirstTieUsesLowestPatternIndex;
    [Test] procedure MultiPrefixSuffixPatterns;
    [Test] procedure MultiStartOffset;
    [Test] procedure MultiStringExpectedMatches;
    [Test] procedure MultiEmptySetRejected;
    [Test] procedure MultiCopiesInputPatterns;
    [Test] procedure MultiPatternCount;
    [Test] procedure MultiRejectsEmptyBytePattern;
    [Test] procedure MultiRejectsEmptyStringPattern;
    [Test] procedure MultiPointerAndListInputs;
    [Test] procedure MultiByteSearcherRejectsStringInput;
  end;

  [TestFixture]
  TPatternStreamTests = class
  public
    [Test] procedure ExactCrossesChunkBoundary;
    [Test] procedure MaskedCrossesChunkBoundary;
    [Test] procedure MyersCrossesChunkBoundary;
    [Test] procedure FuzzyStreamImprovesBoundaryCandidate;
    [Test] procedure FuzzyFindAllRemainsSortedAcrossBoundary;
    [Test] procedure AhoCrossesChunkBoundary;
    [Test] procedure CommentzWalterCrossesChunkBoundary;
    [Test] procedure PreservePositionTrueRestoresPosition;
    [Test] procedure PreservePositionFalseAdvancesPosition;
    [Test] procedure SearchStartsAtCurrentStreamPosition;
    [Test] procedure FindAllBoundaryMatchIsNotDuplicated;
    [Test] procedure EmptyStreamReturnsNoMatch;
    [Test] procedure NilStreamReturnsNoMatch;
  end;

  [TestFixture]
  TPatternFacadeTests = class
  public
    [Test] procedure AutoShortExactReturnsExpectedMatch;
    [Test] procedure AutoLongExactUsesPatternHeuristic;
    [Test] procedure AutoExactThresholds;
    [Test] procedure AutoShortFuzzyUsesMyers;
    [Test] procedure AutoLongFuzzyUsesLevenshtein;
    [Test] procedure AutoMultiSelectsAhoForSmallSet;
    [Test] procedure AutoMultiSelectsCommentzWalterForLargerSet;
    [Test] procedure ExplicitAlgorithmsRemainSelectable;
    [Test] procedure Avx2MatchesScalarWhenAvailable;
    [Test] procedure NegativeDistanceIsRejected;
    [Test] procedure ExactAlgorithmRejectsFuzzyDistance;
    [Test] procedure FacadeExactStringOverloads;
    [Test] procedure FacadeExactStreamOverloads;
    [Test] procedure FacadeExactListOverloads;
    [Test] procedure FacadeMaskedDataOverloads;
    [Test] procedure FacadeMaskedStreamAndListOverloads;
  end;

implementation

function BytesOf(const Values: array of Byte): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I] := Values[I];
end;

function RepeatByte(Value: Byte; Count: Integer): TBytes;
begin
  SetLength(Result, Count);
  if Count > 0 then
    FillChar(Result[0], Count, Value);
end;

procedure AssertMatch(const Match: TPatternMatch; ExpectedOffset: Int64; ExpectedLength: NativeUInt; ExpectedPatternIndex, ExpectedDistance: Integer; ExpectedUnit: TPatternMatchUnit; const Name: string);
begin
  Assert.IsTrue(Match.Found, Name + ': expected a match');
  Assert.IsTrue(Match.Offset = ExpectedOffset, Format('%s: expected offset %d, actual %d', [Name, ExpectedOffset, Match.Offset]));
  Assert.IsTrue(Match.MatchLength = ExpectedLength, Format('%s: expected length %d, actual %d', [Name, ExpectedLength, Match.MatchLength]));
  Assert.IsTrue(Match.PatternIndex = ExpectedPatternIndex, Format('%s: expected pattern index %d, actual %d', [Name, ExpectedPatternIndex, Match.PatternIndex]));
  Assert.IsTrue(Match.Distance = ExpectedDistance, Format('%s: expected distance %d, actual %d', [Name, ExpectedDistance, Match.Distance]));
  Assert.IsTrue(Match.MatchUnit = ExpectedUnit, Name + ': unexpected match unit');
end;

procedure AssertNotFound(const Match: TPatternMatch; const Name: string);
begin
  Assert.IsFalse(Match.Found, Name + ': expected no match');
  Assert.IsTrue(Match.Offset = -1, Name + ': expected offset -1');
  Assert.IsTrue(Match.MatchLength = 0, Name + ': expected length 0');
  Assert.IsTrue(Match.PatternIndex = -1, Name + ': expected pattern index -1');
  Assert.IsTrue(Match.Distance = -1, Name + ': expected distance -1');
end;

procedure AssertOffsets(const Matches: TPatternMatches; const Expected: array of Int64; const Name: string);
var
  I: Integer;
begin
  Assert.IsTrue(Length(Matches) = Length(Expected), Format('%s: expected %d matches, actual %d', [Name, Length(Expected), Length(Matches)]));
  for I := 0 to High(Expected) do
    Assert.IsTrue(Matches[I].Offset = Expected[I], Format('%s: match %d expected offset %d, actual %d', [Name, I, Expected[I], Matches[I].Offset]));
end;

procedure AssertMulti(const Matches: TPatternMatches; const ExpectedOffsets: array of Int64; const ExpectedPatternIndexes: array of Integer; const Name: string);
var
  I: Integer;
begin
  Assert.IsTrue(Length(ExpectedOffsets) = Length(ExpectedPatternIndexes), Name + ': invalid expected arrays');
  Assert.IsTrue(Length(Matches) = Length(ExpectedOffsets), Format('%s: expected %d matches, actual %d', [Name, Length(ExpectedOffsets), Length(Matches)]));
  for I := 0 to High(ExpectedOffsets) do
  begin
    Assert.IsTrue(Matches[I].Offset = ExpectedOffsets[I], Format('%s: match %d expected offset %d, actual %d', [Name, I, ExpectedOffsets[I], Matches[I].Offset]));
    Assert.IsTrue(Matches[I].PatternIndex = ExpectedPatternIndexes[I], Format('%s: match %d expected pattern %d, actual %d', [Name, I, ExpectedPatternIndexes[I], Matches[I].PatternIndex]));
  end;
end;

procedure CheckExactSearcher(Searcher: TSinglePatternSearcher; const Data: TBytes; const ExpectedOffsets: array of Int64; StartOffset: NativeUInt; const Name: string);
var
  Matches: TPatternMatches;
  First: TPatternMatch;
begin
  try
    Matches := Searcher.FindAll(Data, StartOffset);
    AssertOffsets(Matches, ExpectedOffsets, Name + ' FindAll');
    First := Searcher.FindFirst(Data, StartOffset);
    if Length(ExpectedOffsets) = 0 then
      AssertNotFound(First, Name + ' FindFirst')
    else
      Assert.IsTrue(First.Offset = ExpectedOffsets[0], Format('%s FindFirst: expected offset %d, actual %d', [Name, ExpectedOffsets[0], First.Offset]));
  finally
    Searcher.Free;
  end;
end;

procedure TPatternCoreTests.EmptyPatternRejected;
var
  Raised: Boolean;
  Empty: TBytes;
begin
  SetLength(Empty, 0);
  Raised := False;
  try
    TBoyerMooreHorspoolSearcher.Create(Empty).Free;
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Empty search pattern must be rejected');
end;

procedure TPatternCoreTests.EmptySignatureRejected;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TBytePattern.Parse('   ');
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Empty signature must be rejected');
end;


procedure TPatternCoreTests.BytePatternCopiesInputArrays;
var
  B, M, OutB, OutM: TBytes;
  P: TBytePattern;
begin
  B := BytesOf([$12, $34]);
  M := BytesOf([$F0, $0F]);
  P := TBytePattern.Masked(B, M);
  B[0] := $FF;
  M[0] := $00;
  OutB := P.Bytes;
  OutM := P.Masks;
  Assert.IsTrue((OutB[0] = $12) and (OutM[0] = $F0), 'TBytePattern must copy input arrays');
end;

procedure TPatternCoreTests.SearcherCopiesInputPattern;
var
  P: TBytes;
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
begin
  P := BytesOf([1, 2, 3]);
  S := TBoyerMooreHorspoolSearcher.Create(P);
  try
    P[0] := 9;
    M := S.FindFirst(BytesOf([0, 1, 2, 3, 4]));
    AssertMatch(M, 1, 3, 0, 0, muByte, 'Searcher copies input');
  finally
    S.Free;
  end;
end;

procedure TPatternCoreTests.MaskedEmptyPatternRejected;
var
  Raised: Boolean;
  B: TBytes;
begin
  SetLength(B, 0);
  Raised := False;
  try
    TBytePattern.Masked(B, B);
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Empty masked pattern must be rejected');
end;

procedure TPatternCoreTests.NotFoundContract;
var
  M: TPatternMatch;
begin
  M := TPatternMatch.NotFound;
  AssertNotFound(M, 'NotFound');
  Assert.IsTrue(M.MatchUnit = muByte, 'NotFound unit');
end;

procedure TPatternCoreTests.ParseExactAndWildcards;
var
  P: TBytePattern;
  B, M: TBytes;
begin
  P := TBytePattern.Parse('48 8b ?? ?F 4?');
  B := P.Bytes;
  M := P.Masks;
  Assert.IsTrue(Length(B) = 5, 'Parsed byte count');
  Assert.IsTrue((B[0] = $48) and (B[1] = $8B) and (B[2] = $00) and (B[3] = $0F) and (B[4] = $40), 'Parsed byte values');
  Assert.IsTrue((M[0] = $FF) and (M[1] = $FF) and (M[2] = $00) and (M[3] = $0F) and (M[4] = $F0), 'Parsed masks');
  Assert.IsFalse(P.IsExact, 'Parsed wildcard pattern must not be exact');
end;

procedure TPatternCoreTests.ParseSingleWildcard;
var
  P: TBytePattern;
  B, M: TBytes;
begin
  P := TBytePattern.Parse('?');
  B := P.Bytes;
  M := P.Masks;
  Assert.IsTrue((Length(B) = 1) and (B[0] = 0), 'Single wildcard bytes');
  Assert.IsTrue((Length(M) = 1) and (M[0] = 0), 'Single wildcard mask');
end;

procedure TPatternCoreTests.ParseRejectsIncompleteHexByte;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TBytePattern.Parse('A');
  except
    on E: EConvertError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Incomplete hex byte must raise EConvertError');
end;

procedure TPatternCoreTests.ParseRejectsLongToken;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TBytePattern.Parse('ABC');
  except
    on E: EConvertError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Long token must raise EConvertError');
end;

procedure TPatternCoreTests.MaskedRejectsLengthMismatch;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TBytePattern.Masked(BytesOf([1, 2]), BytesOf([$FF]));
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Mask length mismatch must raise EArgumentException');
end;

procedure TPatternCoreTests.BytePatternIsImmutableFromReturnedArrays;
var
  P: TBytePattern;
  A, B: TBytes;
begin
  P := TBytePattern.Masked(BytesOf([$12, $34]), BytesOf([$F0, $0F]));
  A := P.Bytes;
  A[0] := $FF;
  B := P.Bytes;
  Assert.IsTrue(B[0] = $12, 'Returned Bytes array must not mutate pattern');
  A := P.Masks;
  A[0] := 0;
  B := P.Masks;
  Assert.IsTrue(B[0] = $F0, 'Returned Masks array must not mutate pattern');
end;

procedure TPatternCoreTests.SearcherPatternIsImmutableFromReturnedArray;
var
  S: TBoyerMooreHorspoolSearcher;
  A: TBytes;
  M: TPatternMatch;
begin
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2, 3]));
  try
    A := S.Pattern;
    A[0] := 9;
    M := S.FindFirst(BytesOf([0, 1, 2, 3, 4]));
    AssertMatch(M, 1, 3, 0, 0, muByte, 'Searcher immutable pattern');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.ExactAlgorithmsReturnExpectedOffsets;
var
  Data, Pattern: TBytes;
begin
  Data := BytesOf([9, 1, 2, 3, 1, 2, 3, 8]);
  Pattern := BytesOf([1, 2, 3]);
  CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, [1, 4], 0, 'BMH');
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [1, 4], 0, 'Bitap');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [1, 4], 0, 'SBNDM');
  CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, [1, 4], 0, 'Rabin-Karp');
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [1, 4], 0, 'Two-Way');
end;

procedure TPatternExactTests.ExactAlgorithmsFindOverlaps;
var
  Data, Pattern: TBytes;
begin
  Data := BytesOf([1, 1, 1, 1, 1]);
  Pattern := BytesOf([1, 1, 1]);
  CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, [0, 1, 2], 0, 'BMH overlap');
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [0, 1, 2], 0, 'Bitap overlap');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [0, 1, 2], 0, 'SBNDM overlap');
  CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, [0, 1, 2], 0, 'Rabin-Karp overlap');
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [0, 1, 2], 0, 'Two-Way overlap');
end;

procedure TPatternExactTests.ExactAlgorithmsRespectStartOffset;
var
  Data, Pattern: TBytes;
begin
  Data := BytesOf([1, 2, 1, 2, 1, 2]);
  Pattern := BytesOf([1, 2]);
  CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, [2, 4], 2, 'BMH StartOffset');
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [2, 4], 2, 'Bitap StartOffset');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [2, 4], 2, 'SBNDM StartOffset');
  CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, [2, 4], 2, 'Rabin-Karp StartOffset');
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [2, 4], 2, 'Two-Way StartOffset');
end;

procedure TPatternExactTests.ExactAlgorithmsHandleSingleByte;
var
  Data, Pattern: TBytes;
begin
  Data := BytesOf([$AA, $10, $AA, $AA]);
  Pattern := BytesOf([$AA]);
  CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, [0, 2, 3], 0, 'BMH one byte');
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [0, 2, 3], 0, 'Bitap one byte');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [0, 2, 3], 0, 'SBNDM one byte');
  CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, [0, 2, 3], 0, 'Rabin-Karp one byte');
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [0, 2, 3], 0, 'Two-Way one byte');
end;

procedure TPatternExactTests.ExactAlgorithmsHandlePatternLongerThanData;
var
  Data, Pattern: TBytes;
begin
  Data := BytesOf([1, 2]);
  Pattern := BytesOf([1, 2, 3]);
  CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, [], 0, 'BMH long pattern');
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [], 0, 'Bitap long pattern');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [], 0, 'SBNDM long pattern');
  CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, [], 0, 'Rabin-Karp long pattern');
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [], 0, 'Two-Way long pattern');
end;

procedure TPatternExactTests.ExactAlgorithmsHandleEndBoundary;
var
  Data, Pattern: TBytes;
begin
  Data := BytesOf([9, 8, 7, 1, 2, 3]);
  Pattern := BytesOf([1, 2, 3]);
  CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, [3], 0, 'BMH end boundary');
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [3], 0, 'Bitap end boundary');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [3], 0, 'SBNDM end boundary');
  CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, [3], 0, 'Rabin-Karp end boundary');
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [3], 0, 'Two-Way end boundary');
end;

procedure TPatternExactTests.BitAlgorithmsHandle64BytePattern;
var
  Pattern, Data: TBytes;
  I: Integer;
begin
  SetLength(Pattern, 64);
  SetLength(Data, 140);
  for I := 0 to High(Pattern) do
    Pattern[I] := Byte((I * 29 + 7) and $FF);
  FillChar(Data[0], Length(Data), $CC);
  Move(Pattern[0], Data[63], Length(Pattern));
  CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, [63], 0, 'Bitap 64');
  CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, [63], 0, 'SBNDM 64');
end;

procedure TPatternExactTests.BitAlgorithmsReject65BytePattern;
var
  P: TBytes;
  Raised: Boolean;
begin
  P := RepeatByte($5A, 65);
  Raised := False;
  try
    TBitapSearcher.Create(P).Free;
  except
    on E: EArgumentOutOfRangeException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Bitap must reject 65-byte patterns');
  Raised := False;
  try
    TSbndmSearcher.Create(P).Free;
  except
    on E: EArgumentOutOfRangeException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'SBNDM must reject 65-byte patterns');
end;

procedure TPatternExactTests.TwoWayHandlesLongPeriodicPattern;
var
  Pattern, Data: TBytes;
  I: Integer;
begin
  SetLength(Pattern, 300);
  SetLength(Data, 800);
  for I := 0 to High(Pattern) do
    Pattern[I] := Byte(I and 1);
  FillChar(Data[0], Length(Data), $7F);
  Move(Pattern[0], Data[311], Length(Pattern));
  CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, [311], 0, 'Two-Way periodic 300');
end;

procedure TPatternExactTests.StringOffsetsAreUtf16CodeUnits;
var
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
  Text, Pattern: string;
begin
  Text := 'A' + #$D83D#$DE00 + 'B' + #$D83D#$DE00 + 'C';
  Pattern := #$D83D#$DE00 + 'B';
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try
    M := S.FindFirst(Text);
    AssertMatch(M, 1, 3, 0, 0, muChar, 'UTF-16 string');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.PointerInputReturnsExpectedOffset;
var
  Data: TBytes;
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
begin
  Data := BytesOf([9, 8, 7, 6, 5]);
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([7, 6]));
  try
    M := S.FindFirst(@Data[0], Length(Data));
    AssertMatch(M, 2, 2, 0, 0, muByte, 'Pointer input');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.ListInputReturnsExpectedOffsets;
var
  L: TList<Byte>;
  S: TBoyerMooreHorspoolSearcher;
  A: TPatternMatches;
begin
  L := TList<Byte>.Create;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2]));
  try
    L.Add(1);
    L.Add(2);
    L.Add(0);
    L.Add(1);
    L.Add(2);
    A := S.FindAll(L);
    AssertOffsets(A, [0, 3], 'List input');
  finally
    S.Free;
    L.Free;
  end;
end;


procedure TPatternExactTests.EmptyDataReturnsNoMatch;
var
  D: TBytes;
  S: TBoyerMooreHorspoolSearcher;
begin
  SetLength(D, 0);
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1]));
  try
    AssertNotFound(S.FindFirst(D), 'Empty data');
    Assert.IsTrue(Length(S.FindAll(D)) = 0, 'Empty data FindAll');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.StartOffsetAtEndReturnsNoMatch;
var
  D: TBytes;
  Matches: TPatternMatches;
  S: TBoyerMooreHorspoolSearcher;
begin
  D := BytesOf([1, 2, 3]);
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([3]));
  try
    AssertNotFound(S.FindFirst(D, Length(D)), 'StartOffset at end');
    SetLength(Matches, 1);
    Matches := S.FindAll(D, Length(D));
    Assert.IsTrue(Length(Matches) = 0, 'StartOffset at end FindAll');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.EmbeddedNullStringIsSearchable;
var
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
  Text, Pattern: string;
begin
  Text := 'A' + #0 + 'BC' + #0 + 'D';
  Pattern := 'BC' + #0;
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try
    M := S.FindFirst(Text);
    AssertMatch(M, 2, 3, 0, 0, muChar, 'Embedded null string');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.SurrogatePairUsesUtf16Units;
var
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
  Text, Pattern: string;
begin
  Pattern := #$D83D#$DE00;
  Text := 'A' + Pattern + 'B';
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try
    M := S.FindFirst(Text);
    AssertMatch(M, 1, 2, 0, 0, muChar, 'UTF16 surrogate units');
  finally
    S.Free;
  end;
end;

procedure TPatternMaskedTests.BitapMaskedExpectedMatches;
var
  S: TBitapSearcher;
  P: TBytePattern;
begin
  P := TBytePattern.Parse('48 8B ?? 4?');
  S := TBitapSearcher.Create(P);
  CheckExactSearcher(S, BytesOf([$48, $8B, $10, $4F, $00, $48, $8B, $FF, $40]), [0, 5], 0, 'Bitap masked');
end;

procedure TPatternMaskedTests.SbndmMaskedExpectedMatches;
var
  S: TSbndmSearcher;
  P: TBytePattern;
begin
  P := TBytePattern.Parse('48 8B ?? 4?');
  S := TSbndmSearcher.Create(P);
  CheckExactSearcher(S, BytesOf([$48, $8B, $10, $4F, $00, $48, $8B, $FF, $40]), [0, 5], 0, 'SBNDM masked');
end;

procedure TPatternMaskedTests.NibbleMasksExpectedMatches;
var
  P: TBytePattern;
  A, B: TPatternMatches;
  Bitap: TBitapSearcher;
  Sbndm: TSbndmSearcher;
  Data: TBytes;
begin
  P := TBytePattern.Parse('?F F?');
  Data := BytesOf([$1F, $FA, $2F, $F0, $FF, $FF]);
  Bitap := TBitapSearcher.Create(P);
  Sbndm := TSbndmSearcher.Create(P);
  try
    A := Bitap.FindAll(Data);
    B := Sbndm.FindAll(Data);
    AssertOffsets(A, [0, 2, 4], 'Bitap nibble');
    AssertOffsets(B, [0, 2, 4], 'SBNDM nibble');
  finally
    Sbndm.Free;
    Bitap.Free;
  end;
end;

procedure TPatternMaskedTests.AllWildcardExpectedMatches;
var
  P: TBytePattern;
  S: TSinglePatternSearcher;
begin
  P := TBytePattern.Parse('?? ??');
  S := TBitapSearcher.Create(P);
  CheckExactSearcher(S, BytesOf([1, 2, 3, 4]), [0, 1, 2], 0, 'Bitap wildcard');
  S := TSbndmSearcher.Create(P);
  CheckExactSearcher(S, BytesOf([1, 2, 3, 4]), [0, 1, 2], 0, 'SBNDM wildcard');
end;

procedure TPatternMaskedTests.MaskIgnoresUnmaskedPatternBits;
var
  P: TBytePattern;
  M: TPatternMatch;
begin
  P := TBytePattern.Masked(BytesOf([$AF, $B7]), BytesOf([$F0, $0F]));
  M := TPatternSearch.FindFirst(BytesOf([$A1, $27]), P, msaSbndm);
  AssertMatch(M, 0, 2, 0, 0, muByte, 'Masked ignored bits');
end;


procedure TPatternMaskedTests.ArbitraryBitMaskExpectedMatches;
var
  P: TBytePattern;
  A: TPatternMatches;
begin
  P := TBytePattern.Masked(BytesOf([$A5]), BytesOf([$3C]));
  A := TPatternSearch.FindAll(BytesOf([$A5, $A6, $65, $25, $81]), P, msaBitap);
  AssertOffsets(A, [0, 1, 2, 3], 'Arbitrary mask Bitap');
  A := TPatternSearch.FindAll(BytesOf([$A5, $A6, $65, $25, $81]), P, msaSbndm);
  AssertOffsets(A, [0, 1, 2, 3], 'Arbitrary mask SBNDM');
end;

procedure TPatternFuzzyTests.LevenshteinSubstitution;
var
  S: TLevenshteinSearcher;
  M: TPatternMatch;
begin
  S := TLevenshteinSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('a'), Ord('x'), Ord('c'), Ord('z')]));
    AssertMatch(M, 1, 3, 0, 1, muByte, 'Levenshtein substitution');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.LevenshteinInsertionAndDeletion;
var
  S: TLevenshteinSearcher;
  M: TPatternMatch;
begin
  S := TLevenshteinSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('a'), Ord('X'), Ord('b'), Ord('c'), Ord('z')]));
    AssertMatch(M, 1, 4, 0, 1, muByte, 'Levenshtein insertion');
    M := S.FindFirst(BytesOf([Ord('x'), Ord('a'), Ord('c'), Ord('z')]));
    AssertMatch(M, 1, 2, 0, 1, muByte, 'Levenshtein deletion');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.MyersSubstitution;
var
  S: TMyersSearcher;
  M: TPatternMatch;
begin
  S := TMyersSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('a'), Ord('x'), Ord('c'), Ord('z')]));
    AssertMatch(M, 1, 3, 0, 1, muByte, 'Myers substitution');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.MyersInsertion;
var
  S: TMyersSearcher;
  M: TPatternMatch;
begin
  S := TMyersSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('a'), Ord('X'), Ord('b'), Ord('c'), Ord('z')]));
    AssertMatch(M, 1, 4, 0, 1, muByte, 'Myers insertion');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.MyersDeletion;
var
  S: TMyersSearcher;
  M: TPatternMatch;
begin
  S := TMyersSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    M := S.FindFirst(BytesOf([Ord('x'), Ord('a'), Ord('c'), Ord('z')]));
    AssertMatch(M, 1, 2, 0, 1, muByte, 'Myers deletion');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.FuzzyFindAllExpectedMatches;
var
  S: TMyersSearcher;
  A: TPatternMatches;
begin
  S := TMyersSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    A := S.FindAll(BytesOf([Ord('a'), Ord('b'), Ord('c'), Ord('x'), Ord('a'), Ord('x'), Ord('c')]));
    Assert.IsTrue(Length(A) = 3, Format('Fuzzy FindAll expected 3 matches, actual %d', [Length(A)]));
    AssertMatch(A[0], 0, 3, 0, 0, muByte, 'Fuzzy FindAll first');
    AssertMatch(A[1], 1, 2, 0, 1, muByte, 'Fuzzy FindAll second');
    AssertMatch(A[2], 4, 3, 0, 1, muByte, 'Fuzzy FindAll third');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.FuzzyEveryStartUsesBestLocalAlignment;
var
  Data, Pattern: TBytes;
  A: TPatternMatches;
  L: TLevenshteinSearcher;
  M: TMyersSearcher;

  procedure Check(const Matches: TPatternMatches; const Name: string);
  const
    ExpectedOffsets: array[0..8] of Int64 = (1, 2, 3, 4, 5, 6, 7, 8, 9);
    ExpectedLengths: array[0..8] of NativeUInt = (3, 2, 1, 1, 5, 4, 3, 2, 1);
    ExpectedDistances: array[0..8] of Integer = (2, 2, 2, 2, 2, 1, 0, 1, 2);
  var
    I: Integer;
  begin
    Assert.IsTrue(Length(Matches) = Length(ExpectedOffsets), Format('%s: expected %d matches, actual %d', [Name, Length(ExpectedOffsets), Length(Matches)]));
    for I := 0 to High(ExpectedOffsets) do
      AssertMatch(Matches[I], ExpectedOffsets[I], ExpectedLengths[I], 0, ExpectedDistances[I], muByte, Name + ' ' + IntToStr(I));
  end;
begin
  Data := BytesOf([0, 4, 3, 2, 2, 3, 4, 0, 1, 2]);
  Pattern := BytesOf([0, 1, 2]);
  L := TLevenshteinSearcher.Create(Pattern, 2);
  try
    A := L.FindAll(Data, 1);
    Check(A, 'Levenshtein local alignment');
  finally
    L.Free;
  end;
  M := TMyersSearcher.Create(Pattern, 2);
  try
    A := M.FindAll(Data, 1);
    Check(A, 'Myers local alignment');
  finally
    M.Free;
  end;
end;

procedure TPatternFuzzyTests.FuzzyStartOffset;
var
  S: TMyersSearcher;
  M: TPatternMatch;
begin
  S := TMyersSearcher.Create(BytesOf([1, 2, 3]), 1);
  try
    M := S.FindFirst(BytesOf([1, 2, 3, 9, 1, 2, 4]), 4);
   AssertMatch(M, 4, 2, 0, 1, muByte, 'Fuzzy StartOffset');
  finally
    S.Free;
  end;
end;

procedure TPatternFuzzyTests.MyersRejectsPatternOver64;
var
  Pattern: TBytes;
  Raised: Boolean;
begin
  SetLength(Pattern, 65);
  Raised := False;
  try
    TMyersSearcher.Create(Pattern, 1).Free;
  except
    on E: EArgumentOutOfRangeException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Myers must reject 65-byte pattern');
end;

procedure TPatternFuzzyTests.FuzzyRejectsDistanceAtLeastPatternLength;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TLevenshteinSearcher.Create(BytesOf([1, 2, 3]), 3).Free;
  except
    on E: EArgumentOutOfRangeException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Levenshtein must reject distance >= pattern length');
  Raised := False;
  try
    TMyersSearcher.Create(BytesOf([1, 2, 3]), 3).Free;
  except
    on E: EArgumentOutOfRangeException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Myers must reject distance >= pattern length');
end;

procedure TPatternFuzzyTests.FuzzyStringExpectedMatch;
var
  S: TMyersSearcher;
  M: TPatternMatch;
begin
  S := TMyersSearcher.Create('Hallo', 1);
  try
    M := S.FindFirst('xxHulloyy');
    AssertMatch(M, 2, 5, 0, 1, muChar, 'Myers string');
  finally
    S.Free;
  end;
end;


procedure TPatternFuzzyTests.ZeroDistanceMatchesExactSemantics;
var
  Data, Pattern: TBytes;
  A, B: TPatternMatches;
  L: TLevenshteinSearcher;
  M: TMyersSearcher;
begin
  Data := BytesOf([1, 2, 3, 1, 2, 3, 4]);
  Pattern := BytesOf([1, 2, 3]);
  L := TLevenshteinSearcher.Create(Pattern, 0);
  M := TMyersSearcher.Create(Pattern, 0);
  try
    A := L.FindAll(Data);
    B := M.FindAll(Data);
    AssertOffsets(A, [0, 3], 'Levenshtein distance zero');
    AssertOffsets(B, [0, 3], 'Myers distance zero');
  finally
    M.Free;
    L.Free;
  end;
end;

procedure TPatternMultiTests.AhoExpectedClassicMatches;
var
  S: TAhoCorasickSearcher;
  A: TPatternMatches;
begin
  S := TAhoCorasickSearcher.Create(['he', 'she', 'hers', 'his']);
  try
    A := S.FindAll('ushers');
    AssertMulti(A, [1, 2, 2], [1, 0, 2], 'Aho classic');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.CommentzWalterExpectedClassicMatches;
var
  S: TCommentzWalterSearcher;
  A: TPatternMatches;
begin
  S := TCommentzWalterSearcher.Create(['he', 'she', 'hers', 'his']);
  try
    A := S.FindAll('ushers');
    AssertMulti(A, [1, 2, 2], [1, 0, 2], 'Commentz-Walter classic');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.MultiDuplicatePatternsRemainDistinct;
var
  Patterns: TArray<TBytes>;
  A: TPatternMatches;
  S: TMultiPatternSearcher;
begin
  SetLength(Patterns, 3);
  Patterns[0] := BytesOf([1, 2]);
  Patterns[1] := BytesOf([1, 2]);
  Patterns[2] := BytesOf([2]);
  S := TAhoCorasickSearcher.Create(Patterns);
  try
    A := S.FindAll(BytesOf([1, 2]));
    AssertMulti(A, [0, 0, 1], [0, 1, 2], 'Aho duplicate patterns');
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(Patterns);
  try
    A := S.FindAll(BytesOf([1, 2]));
    AssertMulti(A, [0, 0, 1], [0, 1, 2], 'CW duplicate patterns');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.MultiFindFirstTieUsesLowestPatternIndex;
var
  Patterns: TArray<TBytes>;
  A: TMultiPatternSearcher;
  M: TPatternMatch;
begin
  SetLength(Patterns, 2);
  Patterns[0] := BytesOf([1, 2]);
  Patterns[1] := BytesOf([1, 2, 3]);
  A := TAhoCorasickSearcher.Create(Patterns);
  try
    M := A.FindFirst(BytesOf([1, 2, 3]));
    AssertMatch(M, 0, 2, 0, 0, muByte, 'Aho FindFirst tie');
  finally
    A.Free;
  end;
  A := TCommentzWalterSearcher.Create(Patterns);
  try
    M := A.FindFirst(BytesOf([1, 2, 3]));
    AssertMatch(M, 0, 2, 0, 0, muByte, 'CW FindFirst tie');
  finally
    A.Free;
  end;
end;

procedure TPatternMultiTests.MultiPrefixSuffixPatterns;
var
  S: TMultiPatternSearcher;
  Patterns: TArray<TBytes>;
  A: TPatternMatches;
begin
  SetLength(Patterns, 4);
  Patterns[0] := BytesOf([1]);
  Patterns[1] := BytesOf([1, 2]);
  Patterns[2] := BytesOf([2]);
  Patterns[3] := BytesOf([1, 2, 3]);
  S := TAhoCorasickSearcher.Create(Patterns);
  try
    A := S.FindAll(BytesOf([1, 2, 3]));
    AssertMulti(A, [0, 0, 0, 1], [0, 1, 3, 2], 'Aho prefix suffix');
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(Patterns);
  try
    A := S.FindAll(BytesOf([1, 2, 3]));
    AssertMulti(A, [0, 0, 0, 1], [0, 1, 3, 2], 'CW prefix suffix');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.MultiStartOffset;
var
  S: TMultiPatternSearcher;
  Patterns: TArray<TBytes>;
  A: TPatternMatches;
  M: TPatternMatch;
begin
  SetLength(Patterns, 2);
  Patterns[0] := BytesOf([1, 2]);
  Patterns[1] := BytesOf([2, 3]);
  S := TAhoCorasickSearcher.Create(Patterns);
  try
    M := S.FindFirst(BytesOf([1, 2, 3, 1, 2]), 2);
    AssertMatch(M, 3, 2, 0, 0, muByte, 'Aho StartOffset');
    SetLength(A, 1);
    A := S.FindAll(BytesOf([1, 2, 3]), 3);
    Assert.IsTrue(Length(A) = 0, 'Aho StartOffset at end FindAll');
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(Patterns);
  try
    M := S.FindFirst(BytesOf([1, 2, 3, 1, 2]), 2);
    AssertMatch(M, 3, 2, 0, 0, muByte, 'CW StartOffset');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.MultiStringExpectedMatches;
var
  S: TMultiPatternSearcher;
  A: TPatternMatches;
begin
  S := TAhoCorasickSearcher.Create(['eins', 'zwei', 'drei']);
  try
    A := S.FindAll('drei eins zwei');
    AssertMulti(A, [0, 5, 10], [2, 0, 1], 'Aho string');
    Assert.IsTrue((A[0].MatchUnit = muChar) and (A[1].MatchUnit = muChar) and (A[2].MatchUnit = muChar), 'Aho string units');
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(['eins', 'zwei', 'drei']);
  try
    A := S.FindAll('drei eins zwei');
    AssertMulti(A, [0, 5, 10], [2, 0, 1], 'CW string');
  finally
    S.Free;
  end;
end;


procedure TPatternMultiTests.MultiEmptySetRejected;
var
  P: TArray<TBytes>;
  Raised: Boolean;
begin
  SetLength(P, 0);
  Raised := False;
  try
    TPatternSearch.CompileMany(P).Free;
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Empty multi-pattern set must be rejected');
end;

procedure TPatternMultiTests.MultiCopiesInputPatterns;
var
  P: TArray<TBytes>;
  S: TMultiPatternSearcher;
  M: TPatternMatch;
begin
  SetLength(P, 1);
  P[0] := BytesOf([1, 2, 3]);
  S := TAhoCorasickSearcher.Create(P);
  try
    P[0][0] := 9;
    M := S.FindFirst(BytesOf([0, 1, 2, 3, 4]));
    AssertMatch(M, 1, 3, 0, 0, muByte, 'Aho copies input');
  finally
    S.Free;
  end;
  P[0] := BytesOf([1, 2, 3]);
  S := TCommentzWalterSearcher.Create(P);
  try
    P[0][0] := 9;
    M := S.FindFirst(BytesOf([0, 1, 2, 3, 4]));
    AssertMatch(M, 1, 3, 0, 0, muByte, 'CW copies input');
  finally
    S.Free;
  end;
end;

procedure PrepareBoundaryData(out Data: TBytes; const Pattern: TBytes; Offset: Integer);
begin
  SetLength(Data, 65536 + Length(Pattern) + 8);
  FillChar(Data[0], Length(Data), $CC);
  Move(Pattern[0], Data[Offset], Length(Pattern));
end;

procedure TPatternStreamTests.ExactCrossesChunkBoundary;
var
  Data, Pattern: TBytes;
  Stream: TMemoryStream;
  S: TBoyerMooreHorspoolSearcher;
  M: TPatternMatch;
begin
  Pattern := BytesOf([$DE, $AD, $BE, $EF]);
  PrepareBoundaryData(Data, Pattern, 65534);
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    AssertMatch(M, 65534, 4, 0, 0, muByte, 'Exact stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.MaskedCrossesChunkBoundary;
var
  Data: TBytes;
  Stream: TMemoryStream;
  S: TSbndmSearcher;
  M: TPatternMatch;
  P: TBytePattern;
begin
  P := TBytePattern.Parse('DE A? ?? EF');
  Data := RepeatByte($CC, 65548);
  Data[65534] := $DE;
  Data[65535] := $AF;
  Data[65536] := $11;
  Data[65537] := $EF;
  Stream := TMemoryStream.Create;
  S := TSbndmSearcher.Create(P);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    AssertMatch(M, 65534, 4, 0, 0, muByte, 'Masked stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.MyersCrossesChunkBoundary;
var
  Data: TBytes;
  Stream: TMemoryStream;
  S: TMyersSearcher;
  M: TPatternMatch;
begin
  Data := RepeatByte(0, 65550);
  Data[65534] := Ord('a');
  Data[65535] := Ord('X');
  Data[65536] := Ord('b');
  Data[65537] := Ord('c');
  Stream := TMemoryStream.Create;
  S := TMyersSearcher.Create(BytesOf([Ord('a'), Ord('b'), Ord('c')]), 1);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    AssertMatch(M, 65534, 4, 0, 1, muByte, 'Myers stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.FuzzyStreamImprovesBoundaryCandidate;
var
  Data: TBytes;
  Stream: TMemoryStream;
  S: TSinglePatternSearcher;
  Matches: TPatternMatches;
  Pattern: TBytes;
  I: Integer;
  Found: Boolean;
begin
  Data := RepeatByte(0, 65548);
  Data[65534] := Ord('a');
  Data[65535] := Ord('b');
  Data[65536] := Ord('c');
  Pattern := BytesOf([Ord('a'), Ord('b'), Ord('c')]);
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(Data[0], Length(Data));

    Stream.Position := 0;
    S := TLevenshteinSearcher.Create(Pattern, 1);
    try
      Matches := S.FindAll(Stream, True);
      Found := False;
      for I := 0 to High(Matches) do
        if Matches[I].Offset = 65534 then
        begin
          AssertMatch(Matches[I], 65534, 3, 0, 0, muByte, 'Levenshtein improved stream match');
          Found := True;
          Break;
        end;
      Assert.IsTrue(Found, 'Levenshtein improved stream match not found');
    finally
      S.Free;
    end;

    Stream.Position := 0;
    S := TMyersSearcher.Create(Pattern, 1);
    try
      Matches := S.FindAll(Stream, True);
      Found := False;
      for I := 0 to High(Matches) do
        if Matches[I].Offset = 65534 then
        begin
          AssertMatch(Matches[I], 65534, 3, 0, 0, muByte, 'Myers improved stream match');
          Found := True;
          Break;
        end;
      Assert.IsTrue(Found, 'Myers improved stream match not found');
    finally
      S.Free;
    end;
  finally
    Stream.Free;
  end;
end;
procedure TPatternStreamTests.FuzzyFindAllRemainsSortedAcrossBoundary;
var
  Data, Pattern: TBytes;
  Stream: TMemoryStream;
  S: TSinglePatternSearcher;
  A: TPatternMatches;

  procedure CheckResult(const Name: string);
  begin
    Assert.IsTrue(Length(A) >= 3, Name + ': expected at least three matches');
    AssertMatch(A[0], 65532, 5, 0, 1, muByte, Name + ' first');
    AssertMatch(A[1], 65533, 4, 0, 0, muByte, Name + ' second');
    AssertMatch(A[2], 65534, 3, 0, 1, muByte, Name + ' third');
  end;

begin
  Data := RepeatByte(0, 65548);
  Data[65532] := Ord('X');
  Data[65533] := Ord('A');
  Data[65534] := Ord('B');
  Data[65535] := Ord('C');
  Data[65536] := Ord('D');
  Pattern := BytesOf([Ord('A'), Ord('B'), Ord('C'), Ord('D')]);
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    S := TLevenshteinSearcher.Create(Pattern, 1);
    try
      A := S.FindAll(Stream, True);
      CheckResult('Levenshtein sorted stream');
    finally
      S.Free;
    end;
    Stream.Position := 0;
    S := TMyersSearcher.Create(Pattern, 1);
    try
      A := S.FindAll(Stream, True);
      CheckResult('Myers sorted stream');
    finally
      S.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.AhoCrossesChunkBoundary;
var
  Data, Pattern: TBytes;
  Patterns: TArray<TBytes>;
  Stream: TMemoryStream;
  S: TAhoCorasickSearcher;
  M: TPatternMatch;
begin
  Pattern := BytesOf([$DE, $AD, $BE, $EF]);
  PrepareBoundaryData(Data, Pattern, 65534);
  SetLength(Patterns, 2);
  Patterns[0] := BytesOf([$11, $22]);
  Patterns[1] := Pattern;
  Stream := TMemoryStream.Create;
  S := TAhoCorasickSearcher.Create(Patterns);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    AssertMatch(M, 65534, 4, 1, 0, muByte, 'Aho stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.CommentzWalterCrossesChunkBoundary;
var
  Data, Pattern: TBytes;
  Patterns: TArray<TBytes>;
  Stream: TMemoryStream;
  S: TCommentzWalterSearcher;
  M: TPatternMatch;
begin
  Pattern := BytesOf([$DE, $AD, $BE, $EF]);
  PrepareBoundaryData(Data, Pattern, 65534);
  SetLength(Patterns, 4);
  Patterns[0] := BytesOf([$11, $22, $33, $44]);
  Patterns[1] := Pattern;
  Patterns[2] := BytesOf([$10, $20, $30, $40]);
  Patterns[3] := BytesOf([$01, $02, $03, $04]);
  Stream := TMemoryStream.Create;
  S := TCommentzWalterSearcher.Create(Patterns);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := S.FindFirst(Stream);
    AssertMatch(M, 65534, 4, 1, 0, muByte, 'CW stream boundary');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.PreservePositionTrueRestoresPosition;
var
  Stream: TMemoryStream;
  S: TBoyerMooreHorspoolSearcher;
  Data: TBytes;
begin
  Data := BytesOf([0, 0, 1, 2, 3, 0]);
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2, 3]));
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 1;
    S.FindFirst(Stream, True);
    Assert.IsTrue(Stream.Position = 1, Format('PreservePosition expected 1, actual %d', [Stream.Position]));
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.PreservePositionFalseAdvancesPosition;
var
  Stream: TMemoryStream;
  S: TBoyerMooreHorspoolSearcher;
  Data: TBytes;
begin
  Data := BytesOf([0, 0, 1, 2, 3, 0]);
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2, 3]));
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 1;
    S.FindFirst(Stream, False);
    Assert.IsTrue(Stream.Position = Stream.Size, Format('Non-preserved stream expected position %d, actual %d', [Stream.Size, Stream.Position]));
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.SearchStartsAtCurrentStreamPosition;
var
  Stream: TMemoryStream;
  S: TBoyerMooreHorspoolSearcher;
  Data: TBytes;
  M: TPatternMatch;
begin
  Data := BytesOf([1, 2, 3, 0, 1, 2, 3]);
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2, 3]));
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 3;
    M := S.FindFirst(Stream, True);
    AssertMatch(M, 4, 3, 0, 0, muByte, 'Stream current position');
    Assert.IsTrue(Stream.Position = 3, 'Stream current position restored');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.FindAllBoundaryMatchIsNotDuplicated;
var
  Data, Pattern: TBytes;
  Stream: TMemoryStream;
  S: TBoyerMooreHorspoolSearcher;
  A: TPatternMatches;
begin
  Pattern := BytesOf([$DE, $AD, $BE, $EF]);
  PrepareBoundaryData(Data, Pattern, 65534);
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    A := S.FindAll(Stream);
    Assert.IsTrue(Length(A) = 1, Format('Boundary FindAll expected 1 match, actual %d', [Length(A)]));
    AssertMatch(A[0], 65534, 4, 0, 0, muByte, 'Boundary FindAll');
  finally
    S.Free;
    Stream.Free;
  end;
end;


procedure TPatternStreamTests.EmptyStreamReturnsNoMatch;
var
  S: TBoyerMooreHorspoolSearcher;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1]));
  try
    AssertNotFound(S.FindFirst(Stream), 'Empty stream');
    Assert.IsTrue(Length(S.FindAll(Stream)) = 0, 'Empty stream FindAll');
  finally
    S.Free;
    Stream.Free;
  end;
end;

procedure TPatternStreamTests.NilStreamReturnsNoMatch;
var
  S: TBoyerMooreHorspoolSearcher;
begin
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1]));
  try
    AssertNotFound(S.FindFirst(TStream(nil)), 'Nil stream');
    Assert.IsTrue(Length(S.FindAll(TStream(nil))) = 0, 'Nil stream FindAll');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.AutoShortExactReturnsExpectedMatch;
var
  M: TPatternMatch;
begin
  M := TPatternSearch.FindFirst(BytesOf([0, 1, 2, 3, 4]), BytesOf([2, 3]));
  AssertMatch(M, 2, 2, 0, 0, muByte, 'Auto short exact');
end;

procedure TPatternFacadeTests.AutoExactThresholds;
var
  P: TBytes;
  S: TSinglePatternSearcher;
begin
  P := RepeatByte($5A, 32);
  S := TPatternSearch.Compile(P);
  try
    if TAvx2Searcher.Available then
      Assert.IsTrue(S is TAvx2Searcher, 'Auto 32 expected AVX2')
    else
      Assert.IsTrue(S is TSbndmSearcher, 'Auto 32 expected SBNDM fallback');
  finally
    S.Free;
  end;
  P := RepeatByte($5A, 64);
  S := TPatternSearch.Compile(P);
  try Assert.IsTrue(S is TSbndmSearcher, 'Auto 64 expected SBNDM'); finally S.Free; end;
  P := RepeatByte($5A, 65);
  S := TPatternSearch.Compile(P);
  try Assert.IsTrue(S is TBoyerMooreHorspoolSearcher, 'Auto 65 expected BMH'); finally S.Free; end;
  P := RepeatByte($5A, 256);
  S := TPatternSearch.Compile(P);
  try Assert.IsTrue(S is TBoyerMooreHorspoolSearcher, 'Auto 256 expected BMH'); finally S.Free; end;
end;

procedure TPatternFacadeTests.AutoLongExactUsesPatternHeuristic;
var
  I: Integer;
  P: TBytes;
  S: TSinglePatternSearcher;
begin
  SetLength(P, 300);
  for I := 0 to High(P) do
    P[I] := Byte(I);
  S := TPatternSearch.Compile(P);
  try
    if TAvx2Searcher.Available then
      Assert.IsTrue(S is TAvx2Searcher, 'Auto long high-entropy expected AVX2')
    else
      Assert.IsTrue(S is TBoyerMooreHorspoolSearcher, 'Auto long high-entropy expected BMH fallback');
  finally
    S.Free;
  end;
  P := RepeatByte($5A, 300);
  S := TPatternSearch.Compile(P);
  try
    Assert.IsTrue(S is TBoyerMooreHorspoolSearcher, 'Auto long repetitive expected BMH');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.AutoShortFuzzyUsesMyers;
var
  S: TSinglePatternSearcher;
begin
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saAuto, 1);
  try
    Assert.IsTrue(S is TMyersSearcher, 'Auto short fuzzy expected Myers');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.AutoLongFuzzyUsesLevenshtein;
var
  P: TBytes;
  S: TSinglePatternSearcher;
begin
  P := RepeatByte(1, 65);
  S := TPatternSearch.Compile(P, saAuto, 1);
  try
    Assert.IsTrue(S is TLevenshteinSearcher, 'Auto long fuzzy expected Levenshtein');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.AutoMultiSelectsAhoForSmallSet;
var
  S: TMultiPatternSearcher;
  P: TArray<TBytes>;
begin
  SetLength(P, 3);
  P[0] := BytesOf([1, 2]);
  P[1] := BytesOf([2, 3]);
  P[2] := BytesOf([3, 4]);
  S := TPatternSearch.CompileMany(P);
  try
    Assert.IsTrue(S is TAhoCorasickSearcher, 'Auto small multi expected Aho-Corasick');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.AutoMultiSelectsCommentzWalterForLargerSet;
var
  S: TMultiPatternSearcher;
  P: TArray<TBytes>;
begin
  SetLength(P, 4);
  P[0] := BytesOf([1, 2, 3, 4]);
  P[1] := BytesOf([2, 3, 4, 5]);
  P[2] := BytesOf([3, 4, 5, 6]);
  P[3] := BytesOf([4, 5, 6, 7]);
  S := TPatternSearch.CompileMany(P);
  try
    Assert.IsTrue(S is TCommentzWalterSearcher, 'Auto larger multi expected Commentz-Walter');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.ExplicitAlgorithmsRemainSelectable;
var
  S: TSinglePatternSearcher;
begin
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saBoyerMooreHorspool);
  try Assert.IsTrue(S is TBoyerMooreHorspoolSearcher, 'Explicit BMH'); finally S.Free; end;
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saRabinKarp);
  try Assert.IsTrue(S is TRabinKarpSearcher, 'Explicit Rabin-Karp'); finally S.Free; end;
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saTwoWay);
  try Assert.IsTrue(S is TTwoWaySearcher, 'Explicit Two-Way'); finally S.Free; end;
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saBitap);
  try Assert.IsTrue(S is TBitapSearcher, 'Explicit Bitap'); finally S.Free; end;
  S := TPatternSearch.Compile(BytesOf([1, 2, 3]), saSbndm);
  try Assert.IsTrue(S is TSbndmSearcher, 'Explicit SBNDM'); finally S.Free; end;
end;

procedure TPatternFacadeTests.Avx2MatchesScalarWhenAvailable;
var
  A, B: TPatternMatch;
  Data, Pattern: TBytes;
begin
  if not TAvx2Searcher.Available then
  begin
    Assert.IsTrue(True, 'AVX2 unavailable');
    Exit;
  end;
  Data := BytesOf([$00, $10, $DE, $AD, $BE, $EF, $20]);
  Pattern := BytesOf([$DE, $AD, $BE, $EF]);
  A := TPatternSearch.FindFirst(Data, Pattern, saAvx2);
  B := TPatternSearch.FindFirst(Data, Pattern, saBoyerMooreHorspool);
  Assert.IsTrue(A.Offset = B.Offset, Format('AVX2 expected scalar offset %d, actual %d', [B.Offset, A.Offset]));
end;


procedure TPatternFacadeTests.NegativeDistanceIsRejected;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TPatternSearch.Compile(BytesOf([1, 2, 3]), saAuto, -1).Free;
  except
    on E: EArgumentOutOfRangeException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Negative distance must be rejected');
end;

procedure TPatternFacadeTests.ExactAlgorithmRejectsFuzzyDistance;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TPatternSearch.Compile(BytesOf([1, 2, 3]), saBoyerMooreHorspool, 1).Free;
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Exact algorithm must reject nonzero MaxDistance');
end;


procedure TPatternCoreTests.ExactPatternContract;
var
  P: TBytePattern;
  B, M: TBytes;
begin
  P := TBytePattern.Exact(BytesOf([$12, $34, $56]));
  B := P.Bytes;
  M := P.Masks;
  Assert.IsTrue(P.GetLength = 3, 'Exact pattern length');
  Assert.IsTrue(P.IsExact, 'Exact pattern must be exact');
  Assert.IsTrue((Length(B) = 3) and (B[0] = $12) and (B[1] = $34) and (B[2] = $56), 'Exact pattern bytes');
  Assert.IsTrue((Length(M) = 3) and (M[0] = $FF) and (M[1] = $FF) and (M[2] = $FF), 'Exact pattern masks');
end;

procedure TPatternCoreTests.ExactRejectsEmptyPattern;
var
  Empty: TBytes;
  Raised: Boolean;
begin
  SetLength(Empty, 0);
  Raised := False;
  try
    TBytePattern.Exact(Empty);
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Exact empty pattern must be rejected');
end;

procedure TPatternCoreTests.ParseAcceptsSeparatorsAndLowercase;
var
  P: TBytePattern;
  B, M: TBytes;
begin
  P := TBytePattern.Parse('48,8b ' + #9 + '0a' + #13#10 + 'ff');
  B := P.Bytes;
  M := P.Masks;
  Assert.IsTrue(P.GetLength = 4, 'Separator pattern length');
  Assert.IsTrue(P.IsExact, 'Separator pattern must be exact');
  Assert.IsTrue((B[0] = $48) and (B[1] = $8B) and (B[2] = $0A) and (B[3] = $FF), 'Separator pattern bytes');
  Assert.IsTrue((M[0] = $FF) and (M[1] = $FF) and (M[2] = $FF) and (M[3] = $FF), 'Separator pattern masks');
end;

procedure TPatternCoreTests.ParseRejectsInvalidHexCharacters;
var
  RaisedHigh, RaisedLow: Boolean;
begin
  RaisedHigh := False;
  try
    TBytePattern.Parse('G0');
  except
    on E: EConvertError do
      RaisedHigh := True;
  end;
  RaisedLow := False;
  try
    TBytePattern.Parse('0G');
  except
    on E: EConvertError do
      RaisedLow := True;
  end;
  Assert.IsTrue(RaisedHigh, 'Invalid high nibble must raise EConvertError');
  Assert.IsTrue(RaisedLow, 'Invalid low nibble must raise EConvertError');
end;

procedure TPatternExactTests.PointerFindAllReturnsExpectedOffsets;
var
  Data: TBytes;
  S: TBoyerMooreHorspoolSearcher;
  A: TPatternMatches;
begin
  Data := BytesOf([9, 1, 2, 1, 2, 8]);
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2]));
  try
    A := S.FindAll(@Data[0], Length(Data));
    AssertOffsets(A, [1, 3], 'Pointer FindAll');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.NilPointerReturnsNoMatch;
var
  S: TBoyerMooreHorspoolSearcher;
begin
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2]));
  try
    AssertNotFound(S.FindFirst(Pointer(nil), 8), 'Nil pointer FindFirst');
    Assert.IsTrue(Length(S.FindAll(Pointer(nil), 8)) = 0, 'Nil pointer FindAll');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.NilListReturnsNoMatch;
var
  S: TBoyerMooreHorspoolSearcher;
  L: TList<Byte>;
begin
  L := nil;
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2]));
  try
    AssertNotFound(S.FindFirst(L), 'Nil list FindFirst');
    Assert.IsTrue(Length(S.FindAll(L)) = 0, 'Nil list FindAll');
  finally
    S.Free;
  end;
end;

procedure TPatternExactTests.ByteSearcherRejectsStringInput;
var
  S: TBoyerMooreHorspoolSearcher;
  RaisedFirst, RaisedAll: Boolean;
begin
  S := TBoyerMooreHorspoolSearcher.Create(BytesOf([1, 2]));
  try
    RaisedFirst := False;
    try
      S.FindFirst('abc');
    except
      on E: EInvalidOpException do
        RaisedFirst := True;
    end;
    RaisedAll := False;
    try
      S.FindAll('abc');
    except
      on E: EInvalidOpException do
        RaisedAll := True;
    end;
    Assert.IsTrue(RaisedFirst, 'Byte searcher string FindFirst must be rejected');
    Assert.IsTrue(RaisedAll, 'Byte searcher string FindAll must be rejected');
  finally
    S.Free;
  end;
end;

procedure TPatternMaskedTests.CompileSignatureExpectedMatches;
var
  S: TBitapSearcher;
  A: TPatternMatches;
begin
  S := TPatternSearch.CompileSignature('DE AD ?? EF');
  try
    A := S.FindAll(BytesOf([$00, $DE, $AD, $11, $EF, $00, $DE, $AD, $22, $EF]));
    AssertOffsets(A, [1, 6], 'CompileSignature');
  finally
    S.Free;
  end;
end;

procedure TPatternMaskedTests.CompileMaskedSignatureExpectedMatches;
var
  S: TSinglePatternSearcher;
  A: TPatternMatches;
begin
  S := TPatternSearch.CompileMaskedSignature('DE AD ?? EF', msaSbndm);
  try
    A := S.FindAll(BytesOf([$00, $DE, $AD, $11, $EF, $00, $DE, $AD, $22, $EF]));
    AssertOffsets(A, [1, 6], 'CompileMaskedSignature');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.MultiPatternCount;
var
  S: TMultiPatternSearcher;
begin
  S := TPatternSearch.CompileMany(['one', 'two', 'three'], maAhoCorasick);
  try
    Assert.IsTrue(S.PatternCount = 3, 'Aho pattern count');
  finally
    S.Free;
  end;
  S := TPatternSearch.CompileMany(['one', 'two', 'three'], maCommentzWalter);
  try
    Assert.IsTrue(S.PatternCount = 3, 'Commentz-Walter pattern count');
  finally
    S.Free;
  end;
end;

procedure TPatternMultiTests.MultiRejectsEmptyBytePattern;
var
  P: TArray<TBytes>;
  Raised: Boolean;
begin
  SetLength(P, 2);
  P[0] := BytesOf([1, 2]);
  SetLength(P[1], 0);
  Raised := False;
  try
    TPatternSearch.CompileMany(P).Free;
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Empty byte pattern in multi set must be rejected');
end;

procedure TPatternMultiTests.MultiRejectsEmptyStringPattern;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TPatternSearch.CompileMany(['one', '']).Free;
  except
    on E: EArgumentException do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'Empty string pattern in multi set must be rejected');
end;

procedure TPatternMultiTests.MultiPointerAndListInputs;
var
  P: TArray<TBytes>;
  Data: TBytes;
  S: TMultiPatternSearcher;
  L: TList<Byte>;
  M: TPatternMatch;
  A: TPatternMatches;
  I: Integer;
begin
  SetLength(P, 2);
  P[0] := BytesOf([1, 2]);
  P[1] := BytesOf([2, 3]);
  Data := BytesOf([9, 1, 2, 3, 8]);
  L := TList<Byte>.Create;
  try
    for I := 0 to High(Data) do
      L.Add(Data[I]);
    S := TAhoCorasickSearcher.Create(P);
    try
      M := S.FindFirst(@Data[0], Length(Data));
      AssertMatch(M, 1, 2, 0, 0, muByte, 'Aho pointer');
      A := S.FindAll(L);
      AssertMulti(A, [1, 2], [0, 1], 'Aho list');
    finally
      S.Free;
    end;
    S := TCommentzWalterSearcher.Create(P);
    try
      M := S.FindFirst(@Data[0], Length(Data));
      AssertMatch(M, 1, 2, 0, 0, muByte, 'CW pointer');
      A := S.FindAll(L);
      AssertMulti(A, [1, 2], [0, 1], 'CW list');
    finally
      S.Free;
    end;
  finally
    L.Free;
  end;
end;

procedure TPatternMultiTests.MultiByteSearcherRejectsStringInput;
var
  P: TArray<TBytes>;
  S: TMultiPatternSearcher;
  RaisedAho, RaisedCw: Boolean;
begin
  SetLength(P, 2);
  P[0] := BytesOf([1, 2]);
  P[1] := BytesOf([2, 3]);
  S := TAhoCorasickSearcher.Create(P);
  try
    RaisedAho := False;
    try
      S.FindFirst('abc');
    except
      on E: EInvalidOpException do
        RaisedAho := True;
    end;
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(P);
  try
    RaisedCw := False;
    try
      S.FindAll('abc');
    except
      on E: EInvalidOpException do
        RaisedCw := True;
    end;
  finally
    S.Free;
  end;
  Assert.IsTrue(RaisedAho, 'Aho byte searcher string input must be rejected');
  Assert.IsTrue(RaisedCw, 'Commentz-Walter byte searcher string input must be rejected');
end;

procedure TPatternFacadeTests.FacadeExactStringOverloads;
var
  M: TPatternMatch;
  A: TPatternMatches;
begin
  M := TPatternSearch.FindFirst('xxabcabc', 'abc');
  AssertMatch(M, 2, 3, 0, 0, muChar, 'Facade string FindFirst');
  A := TPatternSearch.FindAll('xxabcabc', 'abc');
  AssertOffsets(A, [2, 5], 'Facade string FindAll');
  Assert.IsTrue((A[0].MatchUnit = muChar) and (A[1].MatchUnit = muChar), 'Facade string units');
end;

procedure TPatternFacadeTests.FacadeExactStreamOverloads;
var
  Data, Pattern: TBytes;
  S: TMemoryStream;
  M: TPatternMatch;
  A: TPatternMatches;
begin
  Data := BytesOf([9, 1, 2, 1, 2, 8]);
  Pattern := BytesOf([1, 2]);
  S := TMemoryStream.Create;
  try
    S.WriteBuffer(Data[0], Length(Data));
    S.Position := 0;
    M := TPatternSearch.FindFirst(S, Pattern);
    AssertMatch(M, 1, 2, 0, 0, muByte, 'Facade stream FindFirst');
    Assert.IsTrue(S.Position = 0, 'Facade stream FindFirst must preserve position');
    A := TPatternSearch.FindAll(S, Pattern);
    AssertOffsets(A, [1, 3], 'Facade stream FindAll');
    Assert.IsTrue(S.Position = 0, 'Facade stream FindAll must preserve position');
  finally
    S.Free;
  end;
end;

procedure TPatternFacadeTests.FacadeExactListOverloads;
var
  Data, Pattern: TBytes;
  L: TList<Byte>;
  M: TPatternMatch;
  A: TPatternMatches;
  I: Integer;
begin
  Data := BytesOf([9, 1, 2, 1, 2, 8]);
  Pattern := BytesOf([1, 2]);
  L := TList<Byte>.Create;
  try
    for I := 0 to High(Data) do
      L.Add(Data[I]);
    M := TPatternSearch.FindFirst(L, Pattern);
    AssertMatch(M, 1, 2, 0, 0, muByte, 'Facade list FindFirst');
    A := TPatternSearch.FindAll(L, Pattern);
    AssertOffsets(A, [1, 3], 'Facade list FindAll');
  finally
    L.Free;
  end;
end;

procedure TPatternFacadeTests.FacadeMaskedDataOverloads;
var
  Data: TBytes;
  P: TBytePattern;
  M: TPatternMatch;
  A: TPatternMatches;
begin
  Data := BytesOf([$00, $DE, $AD, $11, $EF, $00, $DE, $AD, $22, $EF]);
  P := TBytePattern.Parse('DE AD ?? EF');
  M := TPatternSearch.FindFirst(Data, P);
  AssertMatch(M, 1, 4, 0, 0, muByte, 'Facade masked data FindFirst');
  A := TPatternSearch.FindAll(Data, P);
  AssertOffsets(A, [1, 6], 'Facade masked data FindAll');
end;

procedure TPatternFacadeTests.FacadeMaskedStreamAndListOverloads;
var
  Data: TBytes;
  P: TBytePattern;
  S: TMemoryStream;
  L: TList<Byte>;
  M: TPatternMatch;
  A: TPatternMatches;
  I: Integer;
begin
  Data := BytesOf([$00, $DE, $AD, $11, $EF, $00, $DE, $AD, $22, $EF]);
  P := TBytePattern.Parse('DE AD ?? EF');
  S := TMemoryStream.Create;
  L := TList<Byte>.Create;
  try
    S.WriteBuffer(Data[0], Length(Data));
    S.Position := 0;
    for I := 0 to High(Data) do
      L.Add(Data[I]);
    M := TPatternSearch.FindFirst(S, P, msaSbndm);
    AssertMatch(M, 1, 4, 0, 0, muByte, 'Facade masked stream FindFirst');
    Assert.IsTrue(S.Position = 0, 'Facade masked stream must preserve position');
    A := TPatternSearch.FindAll(L, P, msaSbndm);
    AssertOffsets(A, [1, 6], 'Facade masked list FindAll');
  finally
    L.Free;
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPatternCoreTests);
  TDUnitX.RegisterTestFixture(TPatternExactTests);
  TDUnitX.RegisterTestFixture(TPatternMaskedTests);
  TDUnitX.RegisterTestFixture(TPatternFuzzyTests);
  TDUnitX.RegisterTestFixture(TPatternMultiTests);
  TDUnitX.RegisterTestFixture(TPatternStreamTests);
  TDUnitX.RegisterTestFixture(TPatternFacadeTests);

end.
