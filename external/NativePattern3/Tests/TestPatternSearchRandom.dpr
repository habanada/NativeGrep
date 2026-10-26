program TestPatternSearchRandom;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
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
  NativePattern.CommentzWalter;

var
  GRandState: UInt64 = $7E3779B97F4A7C15;

function NextRand: UInt64;
begin
  GRandState := GRandState xor (GRandState shl 13);
  GRandState := GRandState xor (GRandState shr 7);
  GRandState := GRandState xor (GRandState shl 17);
  Result := GRandState;
end;

function RandInt(MaxExclusive: Integer): Integer;
begin
  Result := Integer(NextRand mod UInt64(MaxExclusive));
end;

procedure AppendMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  N: Integer;
begin
  N := Length(Matches);
  SetLength(Matches, N + 1);
  Matches[N] := Match;
end;

procedure SortMatches(var Matches: TPatternMatches);
var
  I, J: Integer;
  Temp: TPatternMatch;
begin
  for I := 1 to High(Matches) do
  begin
    Temp := Matches[I];
    J := I - 1;
    while (J >= 0) and ((Matches[J].Offset > Temp.Offset) or ((Matches[J].Offset = Temp.Offset) and (Matches[J].PatternIndex > Temp.PatternIndex))) do
    begin
      Matches[J + 1] := Matches[J];
      Dec(J);
    end;
    Matches[J + 1] := Temp;
  end;
end;

function ExactAt(const Data, Pattern: TBytes; Offset: Integer): Boolean;
var
  I: Integer;
begin
  if (Offset < 0) or (Length(Pattern) = 0) or (Offset + Length(Pattern) > Length(Data)) then
    Exit(False);
  for I := 0 to High(Pattern) do
    if Data[Offset + I] <> Pattern[I] then
      Exit(False);
  Result := True;
end;

function MaskedAt(const Data: TBytes; const Pattern: TBytePattern; Offset: Integer): Boolean;
var
  I: Integer;
  Bytes, Masks: TBytes;
begin
  Bytes := Pattern.Bytes;
  Masks := Pattern.Masks;
  if (Offset < 0) or (Length(Bytes) = 0) or (Length(Bytes) <> Length(Masks)) or (Offset + Length(Bytes) > Length(Data)) then
    Exit(False);
  for I := 0 to High(Bytes) do
    if ((Data[Offset + I] xor Bytes[I]) and Masks[I]) <> 0 then
      Exit(False);
  Result := True;
end;

function NaiveExact(const Data, Pattern: TBytes): TPatternMatches;
var
  I: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if Length(Pattern) > Length(Data) then
    Exit;
  for I := 0 to Length(Data) - Length(Pattern) do
    if ExactAt(Data, Pattern, I) then
    begin
      Match.Offset := I;
      Match.MatchLength := Length(Pattern);
      Match.PatternIndex := 0;
      Match.Distance := 0;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
    end;
end;

function NaiveMasked(const Data: TBytes; const Pattern: TBytePattern): TPatternMatches;
var
  I: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if Pattern.GetLength > NativeUInt(Length(Data)) then
    Exit;
  for I := 0 to Length(Data) - Integer(Pattern.GetLength) do
    if MaskedAt(Data, Pattern, I) then
    begin
      Match.Offset := I;
      Match.MatchLength := Pattern.GetLength;
      Match.PatternIndex := 0;
      Match.Distance := 0;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
    end;
end;

function NaiveMulti(const Data: TBytes; const Patterns: array of TBytes): TPatternMatches;
var
  PatternIndex, Offset: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  for PatternIndex := 0 to High(Patterns) do
    if Length(Patterns[PatternIndex]) <= Length(Data) then
      for Offset := 0 to Length(Data) - Length(Patterns[PatternIndex]) do
        if ExactAt(Data, Patterns[PatternIndex], Offset) then
        begin
          Match.Offset := Offset;
          Match.MatchLength := Length(Patterns[PatternIndex]);
          Match.PatternIndex := PatternIndex;
          Match.Distance := 0;
          Match.MatchUnit := muByte;
          AppendMatch(Result, Match);
        end;
  SortMatches(Result);
end;

procedure CheckMatches(const Actual, Expected: TPatternMatches; const Name: string);
var
  I: Integer;
begin
  if Length(Actual) <> Length(Expected) then
    raise Exception.CreateFmt('%s count mismatch: %d <> %d', [Name, Length(Actual), Length(Expected)]);
  for I := 0 to High(Expected) do
    if (Actual[I].Offset <> Expected[I].Offset) or (Actual[I].MatchLength <> Expected[I].MatchLength) or (Actual[I].PatternIndex <> Expected[I].PatternIndex) then
      raise Exception.CreateFmt('%s mismatch at %d', [Name, I]);
end;

procedure FillRandom(var Data: TBytes; AlphabetSize: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte(RandInt(AlphabetSize));
end;

procedure CheckExactSearcher(Searcher: TSinglePatternSearcher; const Data: TBytes; const Expected: TPatternMatches; const Name: string);
var
  Actual: TPatternMatches;
begin
  try
    Actual := Searcher.FindAll(Data);
    CheckMatches(Actual, Expected, Name);
  finally
    Searcher.Free;
  end;
end;

procedure TestExactRandom;
var
  CaseIndex, DataLength, PatternLength, InsertOffset, I: Integer;
  Data, Pattern: TBytes;
  Expected, Actual: TPatternMatches;
  Searcher: TSinglePatternSearcher;
begin
  for CaseIndex := 0 to 999 do
  begin
    DataLength := 1 + RandInt(420);
    PatternLength := 1 + RandInt(320);
    SetLength(Data, DataLength);
    SetLength(Pattern, PatternLength);
    FillRandom(Data, 8);
    FillRandom(Pattern, 8);
    if PatternLength <= DataLength then
    begin
      InsertOffset := RandInt(DataLength - PatternLength + 1);
      for I := 0 to PatternLength - 1 do
        Data[InsertOffset + I] := Pattern[I];
    end;
    Expected := NaiveExact(Data, Pattern);
    CheckExactSearcher(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, Expected, 'BMH random');
    CheckExactSearcher(TRabinKarpSearcher.Create(Pattern), Data, Expected, 'Rabin-Karp random');
    CheckExactSearcher(TTwoWaySearcher.Create(Pattern), Data, Expected, 'Two-Way random');
    if PatternLength <= 64 then
    begin
      CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, Expected, 'Bitap random');
      CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, Expected, 'SBNDM random');
    end;
    Searcher := TPatternSearch.Compile(Pattern);
    try
      Actual := Searcher.FindAll(Data);
      CheckMatches(Actual, Expected, 'Auto random');
    finally
      Searcher.Free;
    end;
  end;
  Writeln('Exact random OK');
end;

procedure TestMaskedRandom;
var
  CaseIndex, DataLength, PatternLength, I, Mode: Integer;
  Data, Bytes, Masks: TBytes;
  Pattern: TBytePattern;
  Expected: TPatternMatches;
begin
  for CaseIndex := 0 to 999 do
  begin
    DataLength := 1 + RandInt(260);
    PatternLength := 1 + RandInt(64);
    SetLength(Data, DataLength);
    SetLength(Bytes, PatternLength);
    SetLength(Masks, PatternLength);
    FillRandom(Data, 256);
    FillRandom(Bytes, 256);
    for I := 0 to PatternLength - 1 do
    begin
      Mode := RandInt(4);
      case Mode of
        0: Masks[I] := $FF;
        1: Masks[I] := $F0;
        2: Masks[I] := $0F;
      else
        Masks[I] := $00;
      end;
    end;
    Pattern := TBytePattern.Masked(Bytes, Masks);
    Expected := NaiveMasked(Data, Pattern);
    CheckExactSearcher(TBitapSearcher.Create(Pattern), Data, Expected, 'Bitap masked random');
    CheckExactSearcher(TSbndmSearcher.Create(Pattern), Data, Expected, 'SBNDM masked random');
  end;
  Writeln('Masked random OK');
end;

function Min3(A, B, C: Integer): Integer;
begin
  Result := A;
  if B < Result then
    Result := B;
  if C < Result then
    Result := C;
end;

function EditDistance(const Pattern, Data: TBytes; Offset, Count: Integer): Integer;
var
  Prev, Curr, Temp: TArray<Integer>;
  I, J, Cost: Integer;
begin
  SetLength(Prev, Length(Pattern) + 1);
  SetLength(Curr, Length(Pattern) + 1);
  for I := 0 to Length(Pattern) do
    Prev[I] := I;
  for J := 1 to Count do
  begin
    Curr[0] := J;
    for I := 1 to Length(Pattern) do
    begin
      if Pattern[I - 1] = Data[Offset + J - 1] then
        Cost := 0
      else
        Cost := 1;
      Curr[I] := Min3(Prev[I] + 1, Curr[I - 1] + 1, Prev[I - 1] + Cost);
    end;
    Temp := Prev;
    Prev := Curr;
    Curr := Temp;
  end;
  Result := Prev[Length(Pattern)];
end;

function NaiveFuzzy(const Data, Pattern: TBytes; MaxDistance: Integer): TPatternMatches;
var
  Offset, Count, MinLength, MaxLength, Distance, BestDistance, BestLength: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  MinLength := Length(Pattern) - MaxDistance;
  if MinLength < 1 then
    MinLength := 1;
  MaxLength := Length(Pattern) + MaxDistance;
  for Offset := 0 to High(Data) do
  begin
    BestDistance := MaxDistance + 1;
    BestLength := 0;
    Count := MinLength;
    while (Count <= MaxLength) and (Offset + Count <= Length(Data)) do
    begin
      Distance := EditDistance(Pattern, Data, Offset, Count);
      if (Distance < BestDistance) or ((Distance = BestDistance) and ((BestLength = 0) or (Count < BestLength))) then
      begin
        BestDistance := Distance;
        BestLength := Count;
      end;
      Inc(Count);
    end;
    if BestDistance <= MaxDistance then
    begin
      Match.Offset := Offset;
      Match.MatchLength := BestLength;
      Match.PatternIndex := 0;
      Match.Distance := BestDistance;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
    end;
  end;
end;

procedure CheckFuzzyMatches(const Actual, Expected: TPatternMatches; const Name: string);
var
  I: Integer;
begin
  if Length(Actual) <> Length(Expected) then
    raise Exception.CreateFmt('%s count mismatch: %d <> %d', [Name, Length(Actual), Length(Expected)]);
  for I := 0 to High(Expected) do
    if (Actual[I].Offset <> Expected[I].Offset) or (Actual[I].MatchLength <> Expected[I].MatchLength) or (Actual[I].Distance <> Expected[I].Distance) then
      raise Exception.CreateFmt('%s mismatch at %d', [Name, I]);
end;

procedure TestFuzzyRandom;
var
  CaseIndex, DataLength, PatternLength, MaxDistance: Integer;
  Data, Pattern: TBytes;
  Expected, Actual: TPatternMatches;
  Levenshtein: TLevenshteinSearcher;
  Myers: TMyersSearcher;
begin
  for CaseIndex := 0 to 399 do
  begin
    DataLength := 1 + RandInt(48);
    PatternLength := 1 + RandInt(16);
    SetLength(Data, DataLength);
    SetLength(Pattern, PatternLength);
    FillRandom(Data, 6);
    FillRandom(Pattern, 6);
    if PatternLength = 1 then
      MaxDistance := 0
    else
      MaxDistance := RandInt(Min3(4, PatternLength, PatternLength));
    if MaxDistance >= PatternLength then
      MaxDistance := PatternLength - 1;
    Expected := NaiveFuzzy(Data, Pattern, MaxDistance);
    Levenshtein := TLevenshteinSearcher.Create(Pattern, MaxDistance);
    try
      Actual := Levenshtein.FindAll(Data);
      CheckFuzzyMatches(Actual, Expected, 'Levenshtein random');
    finally
      Levenshtein.Free;
    end;
    Myers := TMyersSearcher.Create(Pattern, MaxDistance);
    try
      Actual := Myers.FindAll(Data);
      CheckFuzzyMatches(Actual, Expected, 'Myers random');
    finally
      Myers.Free;
    end;
  end;
  Writeln('Fuzzy random OK');
end;

procedure TestMultiRandom;
var
  CaseIndex, PatternIndex, PatternCount, PatternLength, DataLength: Integer;
  Data: TBytes;
  Patterns: TArray<TBytes>;
  Expected, Actual: TPatternMatches;
  Searcher: TMultiPatternSearcher;
begin
  for CaseIndex := 0 to 499 do
  begin
    DataLength := 40 + RandInt(180);
    PatternCount := 4 + RandInt(5);
    SetLength(Data, DataLength);
    FillRandom(Data, 6);
    SetLength(Patterns, PatternCount);
    for PatternIndex := 0 to PatternCount - 1 do
    begin
      PatternLength := 2 + RandInt(9);
      SetLength(Patterns[PatternIndex], PatternLength);
      FillRandom(Patterns[PatternIndex], 6);
    end;
    Expected := NaiveMulti(Data, Patterns);
    Searcher := TAhoCorasickSearcher.Create(Patterns);
    try
      Actual := Searcher.FindAll(Data);
      CheckMatches(Actual, Expected, 'Aho-Corasick random');
    finally
      Searcher.Free;
    end;
    Searcher := TCommentzWalterSearcher.Create(Patterns);
    try
      Actual := Searcher.FindAll(Data);
      CheckMatches(Actual, Expected, 'Commentz-Walter random');
    finally
      Searcher.Free;
    end;
  end;
  Writeln('Multi-pattern random OK');
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TestExactRandom;
    TestMaskedRandom;
    TestFuzzyRandom;
    TestMultiRandom;
    Writeln('ALL RANDOM PATTERN TESTS OK');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
