program TestPatternSearchStress;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
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

var
  GInitialSeed: UInt64 = $D1B54A32D192ED03;
  GRandState: UInt64 = $D1B54A32D192ED03;

function NextRand: UInt64;
begin
  GRandState := GRandState xor (GRandState shl 13);
  GRandState := GRandState xor (GRandState shr 7);
  GRandState := GRandState xor (GRandState shl 17);
  Result := GRandState;
end;

function RandInt(MaxExclusive: Integer): Integer;
begin
  if MaxExclusive <= 0 then
    Exit(0);
  Result := Integer(NextRand mod UInt64(MaxExclusive));
end;

procedure FillRandom(var Data: TBytes; AlphabetSize: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte(RandInt(AlphabetSize));
end;

procedure AppendMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  N: Integer;
begin
  N := Length(Matches);
  SetLength(Matches, N + 1);
  Matches[N] := Match;
end;

function CompareMatches(const A, B: TPatternMatch): Integer;
begin
  if A.Offset < B.Offset then Exit(-1);
  if A.Offset > B.Offset then Exit(1);
  if A.PatternIndex < B.PatternIndex then Exit(-1);
  if A.PatternIndex > B.PatternIndex then Exit(1);
  if A.Distance < B.Distance then Exit(-1);
  if A.Distance > B.Distance then Exit(1);
  if A.MatchLength < B.MatchLength then Exit(-1);
  if A.MatchLength > B.MatchLength then Exit(1);
  Result := 0;
end;

procedure SortMatches(var Matches: TPatternMatches);
var
  I, J: Integer;
  T: TPatternMatch;
begin
  for I := 1 to High(Matches) do
  begin
    T := Matches[I];
    J := I - 1;
    while (J >= 0) and (CompareMatches(Matches[J], T) > 0) do
    begin
      Matches[J + 1] := Matches[J];
      Dec(J);
    end;
    Matches[J + 1] := T;
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
  B, M: TBytes;
begin
  B := Pattern.Bytes;
  M := Pattern.Masks;
  if (Offset < 0) or (Length(B) = 0) or (Offset + Length(B) > Length(Data)) then
    Exit(False);
  for I := 0 to High(B) do
    if ((Data[Offset + I] xor B[I]) and M[I]) <> 0 then
      Exit(False);
  Result := True;
end;

function NaiveExact(const Data, Pattern: TBytes; StartOffset: Integer): TPatternMatches;
var
  I: Integer;
  M: TPatternMatch;
begin
  SetLength(Result, 0);
  if (StartOffset < 0) or (StartOffset >= Length(Data)) or (Length(Pattern) > Length(Data) - StartOffset) then
    Exit;
  for I := StartOffset to Length(Data) - Length(Pattern) do
    if ExactAt(Data, Pattern, I) then
    begin
      M.Offset := I;
      M.MatchLength := Length(Pattern);
      M.PatternIndex := 0;
      M.Distance := 0;
      M.MatchUnit := muByte;
      AppendMatch(Result, M);
    end;
end;

function NaiveMasked(const Data: TBytes; const Pattern: TBytePattern; StartOffset: Integer): TPatternMatches;
var
  I, PatternLength: Integer;
  M: TPatternMatch;
begin
  SetLength(Result, 0);
  PatternLength := Integer(Pattern.GetLength);
  if (StartOffset < 0) or (StartOffset >= Length(Data)) or (PatternLength > Length(Data) - StartOffset) then
    Exit;
  for I := StartOffset to Length(Data) - PatternLength do
    if MaskedAt(Data, Pattern, I) then
    begin
      M.Offset := I;
      M.MatchLength := PatternLength;
      M.PatternIndex := 0;
      M.Distance := 0;
      M.MatchUnit := muByte;
      AppendMatch(Result, M);
    end;
end;

function Min3(A, B, C: Integer): Integer;
begin
  Result := A;
  if B < Result then Result := B;
  if C < Result then Result := C;
end;

function EditDistance(const Pattern, Data: TBytes; Offset, Count: Integer): Integer;
var
  Prev, Curr, Temp: TArray<Integer>;
  I, J, Cost: Integer;
begin
  SetLength(Prev, Length(Pattern) + 1);
  SetLength(Curr, Length(Pattern) + 1);
  for I := 0 to Length(Pattern) do Prev[I] := I;
  for J := 1 to Count do
  begin
    Curr[0] := J;
    for I := 1 to Length(Pattern) do
    begin
      if Pattern[I - 1] = Data[Offset + J - 1] then Cost := 0 else Cost := 1;
      Curr[I] := Min3(Prev[I] + 1, Curr[I - 1] + 1, Prev[I - 1] + Cost);
    end;
    Temp := Prev;
    Prev := Curr;
    Curr := Temp;
  end;
  Result := Prev[Length(Pattern)];
end;

function NaiveFuzzy(const Data, Pattern: TBytes; MaxDistance, StartOffset: Integer): TPatternMatches;
var
  Offset, Count, MinLength, MaxLength, Distance, BestDistance, BestLength: Integer;
  M: TPatternMatch;
begin
  SetLength(Result, 0);
  MinLength := Length(Pattern) - MaxDistance;
  if MinLength < 1 then MinLength := 1;
  MaxLength := Length(Pattern) + MaxDistance;
  if StartOffset < 0 then StartOffset := 0;
  for Offset := StartOffset to High(Data) do
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
      M.Offset := Offset;
      M.MatchLength := BestLength;
      M.PatternIndex := 0;
      M.Distance := BestDistance;
      M.MatchUnit := muByte;
      AppendMatch(Result, M);
    end;
  end;
end;

function NaiveMulti(const Data: TBytes; const Patterns: array of TBytes; StartOffset: Integer): TPatternMatches;
var
  PatternIndex, Offset: Integer;
  M: TPatternMatch;
begin
  SetLength(Result, 0);
  for PatternIndex := 0 to High(Patterns) do
    if Length(Patterns[PatternIndex]) <= Length(Data) - StartOffset then
      for Offset := StartOffset to Length(Data) - Length(Patterns[PatternIndex]) do
        if ExactAt(Data, Patterns[PatternIndex], Offset) then
        begin
          M.Offset := Offset;
          M.MatchLength := Length(Patterns[PatternIndex]);
          M.PatternIndex := PatternIndex;
          M.Distance := 0;
          M.MatchUnit := muByte;
          AppendMatch(Result, M);
        end;
  SortMatches(Result);
end;

procedure CheckMatches(const Actual, Expected: TPatternMatches; const Name: string);
var
  I: Integer;
begin
  if Length(Actual) <> Length(Expected) then
    raise Exception.CreateFmt('%s count mismatch %d <> %d seed=%s state=%s', [Name, Length(Actual), Length(Expected), IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
  for I := 0 to High(Expected) do
    if (Actual[I].Offset <> Expected[I].Offset) or (Actual[I].MatchLength <> Expected[I].MatchLength) or (Actual[I].PatternIndex <> Expected[I].PatternIndex) or (Actual[I].Distance <> Expected[I].Distance) then
      raise Exception.CreateFmt('%s mismatch at %d seed=%s state=%s', [Name, I, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
end;

procedure CheckFirst(Searcher: TSinglePatternSearcher; const Data: TBytes; StartOffset: Integer; const Expected: TPatternMatches; const Name: string);
var
  M: TPatternMatch;
begin
  M := Searcher.FindFirst(Data, StartOffset);
  if Length(Expected) = 0 then
  begin
    if M.Found then
      raise Exception.CreateFmt('%s expected no first match seed=%s state=%s', [Name, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
  end
  else if (not M.Found) or (M.Offset <> Expected[0].Offset) or (M.MatchLength <> Expected[0].MatchLength) or (M.Distance <> Expected[0].Distance) then
    raise Exception.CreateFmt('%s first mismatch seed=%s state=%s', [Name, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
end;

procedure CheckMultiFirst(Searcher: TMultiPatternSearcher; const Data: TBytes; StartOffset: Integer; const Expected: TPatternMatches; const Name: string);
var
  M: TPatternMatch;
begin
  M := Searcher.FindFirst(Data, StartOffset);
  if Length(Expected) = 0 then
  begin
    if M.Found then
      raise Exception.CreateFmt('%s expected no first match seed=%s state=%s', [Name, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
  end
  else if (not M.Found) or (M.Offset <> Expected[0].Offset) or (M.MatchLength <> Expected[0].MatchLength) or (M.PatternIndex <> Expected[0].PatternIndex) then
    raise Exception.CreateFmt('%s first mismatch seed=%s state=%s', [Name, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
end;

procedure CheckSingle(Searcher: TSinglePatternSearcher; const Data: TBytes; StartOffset: Integer; const Expected: TPatternMatches; const Name: string);
var
  Actual: TPatternMatches;
begin
  try
    Actual := Searcher.FindAll(Data, StartOffset);
    CheckMatches(Actual, Expected, Name);
    CheckFirst(Searcher, Data, StartOffset, Expected, Name);
  finally
    Searcher.Free;
  end;
end;

procedure RunExact(Cases: Integer);
const
  Lengths: array[0..15] of Integer = (1, 2, 3, 7, 8, 15, 16, 31, 32, 63, 64, 65, 127, 255, 256, 257);
var
  CaseIndex, DataLength, PatternLength, StartOffset, InsertOffset, I, Alphabet: Integer;
  Data, Pattern: TBytes;
  Expected: TPatternMatches;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    if (CaseIndex mod 3) = 0 then PatternLength := Lengths[RandInt(Length(Lengths))] else PatternLength := 1 + RandInt(320);
    DataLength := 1 + RandInt(900);
    Alphabet := 2;
    if (CaseIndex and 1) <> 0 then Alphabet := 256;
    SetLength(Data, DataLength);
    SetLength(Pattern, PatternLength);
    FillRandom(Data, Alphabet);
    FillRandom(Pattern, Alphabet);
    if PatternLength <= DataLength then
    begin
      InsertOffset := RandInt(DataLength - PatternLength + 1);
      for I := 0 to PatternLength - 1 do Data[InsertOffset + I] := Pattern[I];
    end;
    StartOffset := RandInt(DataLength + 1);
    Expected := NaiveExact(Data, Pattern, StartOffset);
    CheckSingle(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, StartOffset, Expected, 'BMH stress');
    CheckSingle(TRabinKarpSearcher.Create(Pattern), Data, StartOffset, Expected, 'Rabin-Karp stress');
    CheckSingle(TTwoWaySearcher.Create(Pattern), Data, StartOffset, Expected, 'Two-Way stress');
    if PatternLength <= 64 then
    begin
      CheckSingle(TBitapSearcher.Create(Pattern), Data, StartOffset, Expected, 'Bitap stress');
      CheckSingle(TSbndmSearcher.Create(Pattern), Data, StartOffset, Expected, 'SBNDM stress');
    end;
    if TAvx2Searcher.Available then
      CheckSingle(TAvx2Searcher.Create(Pattern), Data, StartOffset, Expected, 'AVX2 stress');
    CheckSingle(TPatternSearch.Compile(Pattern), Data, StartOffset, Expected, 'Auto stress');
  end;
  Writeln('Exact stress OK: ', Cases);
end;

procedure RunMasked(Cases: Integer);
var
  CaseIndex, DataLength, PatternLength, StartOffset, I, MaskMode: Integer;
  Data, PatternBytes, Masks: TBytes;
  Pattern: TBytePattern;
  Expected: TPatternMatches;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    DataLength := 1 + RandInt(420);
    PatternLength := 1 + RandInt(64);
    SetLength(Data, DataLength);
    SetLength(PatternBytes, PatternLength);
    SetLength(Masks, PatternLength);
    FillRandom(Data, 256);
    FillRandom(PatternBytes, 256);
    for I := 0 to PatternLength - 1 do
    begin
      MaskMode := RandInt(6);
      case MaskMode of
        0: Masks[I] := $FF;
        1: Masks[I] := $F0;
        2: Masks[I] := $0F;
        3: Masks[I] := $00;
        4: Masks[I] := $3C;
      else
        Masks[I] := $C3;
      end;
    end;
    Pattern := TBytePattern.Masked(PatternBytes, Masks);
    StartOffset := RandInt(DataLength + 1);
    Expected := NaiveMasked(Data, Pattern, StartOffset);
    CheckSingle(TBitapSearcher.Create(Pattern), Data, StartOffset, Expected, 'Bitap masked stress');
    CheckSingle(TSbndmSearcher.Create(Pattern), Data, StartOffset, Expected, 'SBNDM masked stress');
  end;
  Writeln('Masked stress OK: ', Cases);
end;

procedure RunFuzzy(Cases: Integer);
var
  CaseIndex, DataLength, PatternLength, MaxDistance, StartOffset: Integer;
  Data, Pattern: TBytes;
  Expected, Actual: TPatternMatches;
  S: TSinglePatternSearcher;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    DataLength := 1 + RandInt(70);
    PatternLength := 1 + RandInt(24);
    SetLength(Data, DataLength);
    SetLength(Pattern, PatternLength);
    FillRandom(Data, 7);
    FillRandom(Pattern, 7);
    if PatternLength = 1 then MaxDistance := 0 else MaxDistance := RandInt(Min3(4, PatternLength, PatternLength));
    if MaxDistance >= PatternLength then MaxDistance := PatternLength - 1;
    StartOffset := RandInt(DataLength + 1);
    Expected := NaiveFuzzy(Data, Pattern, MaxDistance, StartOffset);
    S := TLevenshteinSearcher.Create(Pattern, MaxDistance);
    try
      Actual := S.FindAll(Data, StartOffset);
      CheckMatches(Actual, Expected, 'Levenshtein stress');
      CheckFirst(S, Data, StartOffset, Expected, 'Levenshtein stress');
    finally
      S.Free;
    end;
    S := TMyersSearcher.Create(Pattern, MaxDistance);
    try
      Actual := S.FindAll(Data, StartOffset);
      CheckMatches(Actual, Expected, 'Myers stress');
      CheckFirst(S, Data, StartOffset, Expected, 'Myers stress');
    finally
      S.Free;
    end;
  end;
  Writeln('Fuzzy stress OK: ', Cases);
end;

procedure RunMulti(Cases: Integer);
var
  CaseIndex, PatternIndex, PatternCount, PatternLength, DataLength, StartOffset: Integer;
  Data: TBytes;
  Patterns: TArray<TBytes>;
  Expected, Actual: TPatternMatches;
  S: TMultiPatternSearcher;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    DataLength := 20 + RandInt(260);
    PatternCount := 1 + RandInt(12);
    SetLength(Data, DataLength);
    FillRandom(Data, 8);
    SetLength(Patterns, PatternCount);
    for PatternIndex := 0 to PatternCount - 1 do
    begin
      PatternLength := 1 + RandInt(14);
      SetLength(Patterns[PatternIndex], PatternLength);
      FillRandom(Patterns[PatternIndex], 8);
      if (PatternIndex > 0) and ((CaseIndex + PatternIndex) mod 13 = 0) then
        Patterns[PatternIndex] := Copy(Patterns[0]);
    end;
    StartOffset := RandInt(DataLength + 1);
    Expected := NaiveMulti(Data, Patterns, StartOffset);
    S := TAhoCorasickSearcher.Create(Patterns);
    try
      Actual := S.FindAll(Data, StartOffset);
      CheckMatches(Actual, Expected, 'Aho stress');
      CheckMultiFirst(S, Data, StartOffset, Expected, 'Aho stress');
    finally
      S.Free;
    end;
    S := TCommentzWalterSearcher.Create(Patterns);
    try
      Actual := S.FindAll(Data, StartOffset);
      CheckMatches(Actual, Expected, 'Commentz-Walter stress');
      CheckMultiFirst(S, Data, StartOffset, Expected, 'Commentz-Walter stress');
    finally
      S.Free;
    end;
  end;
  Writeln('Multi stress OK: ', Cases);
end;

procedure CheckStreamSingle(Searcher: TSinglePatternSearcher; const Data: TBytes; ExpectedOffset: Int64; const Name: string);
var
  Stream: TMemoryStream;
  M: TPatternMatch;
begin
  Stream := TMemoryStream.Create;
  try
    if Length(Data) > 0 then
      Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    M := Searcher.FindFirst(Stream, True);
    if (not M.Found) or (M.Offset <> ExpectedOffset) or (Stream.Position <> 0) then
      raise Exception.CreateFmt('%s stream mismatch expected=%d actual=%d seed=%s state=%s', [Name, ExpectedOffset, M.Offset, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
  finally
    Searcher.Free;
    Stream.Free;
  end;
end;


procedure RunFuzzyStreamRegression;
var
  Data, Pattern: TBytes;
  Stream: TMemoryStream;
  S: TSinglePatternSearcher;
  A: TPatternMatches;

  procedure Check(const Name: string);
  begin
    if Length(A) < 3 then
      raise Exception.Create(Name + ' fuzzy stream regression expected at least three matches');
    if (A[0].Offset <> 65532) or (A[0].MatchLength <> 5) or (A[0].Distance <> 1) or
       (A[1].Offset <> 65533) or (A[1].MatchLength <> 4) or (A[1].Distance <> 0) or
       (A[2].Offset <> 65534) or (A[2].MatchLength <> 3) or (A[2].Distance <> 1) then
      raise Exception.CreateFmt('%s fuzzy stream regression mismatch seed=%s', [Name, IntToHex(GInitialSeed, 16)]);
  end;

begin
  SetLength(Data, 65548);
  FillChar(Data[0], Length(Data), 0);
  Data[65532] := Ord('X');
  Data[65533] := Ord('A');
  Data[65534] := Ord('B');
  Data[65535] := Ord('C');
  Data[65536] := Ord('D');
  Pattern := TBytes.Create(Ord('A'), Ord('B'), Ord('C'), Ord('D'));
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(Data[0], Length(Data));
    Stream.Position := 0;
    S := TLevenshteinSearcher.Create(Pattern, 1);
    try
      A := S.FindAll(Stream, True);
      Check('Levenshtein');
    finally
      S.Free;
    end;
    Stream.Position := 0;
    S := TMyersSearcher.Create(Pattern, 1);
    try
      A := S.FindAll(Stream, True);
      Check('Myers');
    finally
      S.Free;
    end;
  finally
    Stream.Free;
  end;
  Writeln('Fuzzy stream regression OK');
end;

procedure RunStreams(Cases: Integer);
var
  CaseIndex, PatternLength, Offset, I: Integer;
  Data, Pattern: TBytes;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    PatternLength := 8 + RandInt(89);
    SetLength(Pattern, PatternLength);
    FillRandom(Pattern, 256);
    SetLength(Data, 65664);
    FillChar(Data[0], Length(Data), $CC);
    Offset := 65520 + RandInt(40);
    if Offset + PatternLength > Length(Data) then Offset := Length(Data) - PatternLength;
    for I := 0 to PatternLength - 1 do Data[Offset + I] := Pattern[I];
    CheckStreamSingle(TBoyerMooreHorspoolSearcher.Create(Pattern), Data, Offset, 'BMH');
    CheckStreamSingle(TRabinKarpSearcher.Create(Pattern), Data, Offset, 'Rabin-Karp');
    CheckStreamSingle(TTwoWaySearcher.Create(Pattern), Data, Offset, 'Two-Way');
    if PatternLength <= 64 then
    begin
      CheckStreamSingle(TBitapSearcher.Create(Pattern), Data, Offset, 'Bitap');
      CheckStreamSingle(TSbndmSearcher.Create(Pattern), Data, Offset, 'SBNDM');
    end;
    if TAvx2Searcher.Available then
      CheckStreamSingle(TAvx2Searcher.Create(Pattern), Data, Offset, 'AVX2');
    CheckStreamSingle(TPatternSearch.Compile(Pattern), Data, Offset, 'Auto');
  end;
  Writeln('Stream stress OK: ', Cases);
end;

function RandomTestChar: Char;
begin
  case RandInt(10) of
    0: Result := #0;
    1: Result := 'A';
    2: Result := 'B';
    3: Result := #$00FF;
    4: Result := #$0100;
    5: Result := #$03A9;
    6: Result := #$20AC;
  else
    Result := Char(RandInt(128));
  end;
end;

procedure FillRandomString(var Value: string; Count: Integer);
var
  I: Integer;
begin
  SetLength(Value, Count);
  for I := 1 to Count do
    Value[I] := RandomTestChar;
end;

function StringExactAt(const Text, Pattern: string; Offset: Integer): Boolean;
var
  I: Integer;
begin
  if (Offset < 0) or (Pattern = '') or (Offset + Length(Pattern) > Length(Text)) then
    Exit(False);
  for I := 1 to Length(Pattern) do
    if Text[Offset + I] <> Pattern[I] then
      Exit(False);
  Result := True;
end;

function NaiveStringExact(const Text, Pattern: string; StartOffset: Integer): TPatternMatches;
var
  I: Integer;
  M: TPatternMatch;
begin
  SetLength(Result, 0);
  if (StartOffset < 0) or (StartOffset >= Length(Text)) or (Length(Pattern) > Length(Text) - StartOffset) then
    Exit;
  for I := StartOffset to Length(Text) - Length(Pattern) do
    if StringExactAt(Text, Pattern, I) then
    begin
      M.Offset := I;
      M.MatchLength := Length(Pattern);
      M.PatternIndex := 0;
      M.Distance := 0;
      M.MatchUnit := muChar;
      AppendMatch(Result, M);
    end;
end;

procedure CheckStringSingle(Searcher: TSinglePatternSearcher; const Text: string; StartOffset: Integer; const Expected: TPatternMatches; const Name: string);
var
  Actual: TPatternMatches;
  M: TPatternMatch;
begin
  try
    Actual := Searcher.FindAll(Text, StartOffset);
    CheckMatches(Actual, Expected, Name);
    M := Searcher.FindFirst(Text, StartOffset);
    if Length(Expected) = 0 then
    begin
      if M.Found then
        raise Exception.CreateFmt('%s expected no first string match seed=%s state=%s', [Name, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
    end
    else if (not M.Found) or (M.Offset <> Expected[0].Offset) or (M.MatchLength <> Expected[0].MatchLength) or (M.Distance <> Expected[0].Distance) or (M.MatchUnit <> muChar) then
      raise Exception.CreateFmt('%s first string mismatch seed=%s state=%s', [Name, IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
  finally
    Searcher.Free;
  end;
end;

procedure RunStringExact(Cases: Integer);
var
  CaseIndex, TextLength, PatternLength, StartOffset, InsertOffset, I: Integer;
  Text, Pattern: string;
  Expected: TPatternMatches;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    TextLength := 1 + RandInt(240);
    PatternLength := 1 + RandInt(80);
    FillRandomString(Text, TextLength);
    FillRandomString(Pattern, PatternLength);
    if PatternLength <= TextLength then
    begin
      InsertOffset := RandInt(TextLength - PatternLength + 1);
      for I := 1 to PatternLength do
        Text[InsertOffset + I] := Pattern[I];
    end;
    StartOffset := RandInt(TextLength + 1);
    Expected := NaiveStringExact(Text, Pattern, StartOffset);
    CheckStringSingle(TBoyerMooreHorspoolSearcher.Create(Pattern), Text, StartOffset, Expected, 'BMH string stress');
    CheckStringSingle(TRabinKarpSearcher.Create(Pattern), Text, StartOffset, Expected, 'Rabin-Karp string stress');
    CheckStringSingle(TTwoWaySearcher.Create(Pattern), Text, StartOffset, Expected, 'Two-Way string stress');
    if PatternLength <= 32 then
    begin
      CheckStringSingle(TBitapSearcher.Create(Pattern), Text, StartOffset, Expected, 'Bitap string stress');
      CheckStringSingle(TSbndmSearcher.Create(Pattern), Text, StartOffset, Expected, 'SBNDM string stress');
    end;
    CheckStringSingle(TPatternSearch.Compile(Pattern), Text, StartOffset, Expected, 'Auto string stress');
  end;
  Writeln('String exact stress OK: ', Cases);
end;

function EditDistanceText(const Pattern, Text: string; Offset, Count: Integer): Integer;
var
  Prev, Curr, Temp: TArray<Integer>;
  I, J, Cost: Integer;
begin
  SetLength(Prev, Length(Pattern) + 1);
  SetLength(Curr, Length(Pattern) + 1);
  for I := 0 to Length(Pattern) do Prev[I] := I;
  for J := 1 to Count do
  begin
    Curr[0] := J;
    for I := 1 to Length(Pattern) do
    begin
      if Pattern[I] = Text[Offset + J] then Cost := 0 else Cost := 1;
      Curr[I] := Min3(Prev[I] + 1, Curr[I - 1] + 1, Prev[I - 1] + Cost);
    end;
    Temp := Prev;
    Prev := Curr;
    Curr := Temp;
  end;
  Result := Prev[Length(Pattern)];
end;

function NaiveStringFuzzy(const Text, Pattern: string; MaxDistance, StartOffset: Integer): TPatternMatches;
var
  Offset, Count, MinLength, MaxLength, Distance, BestDistance, BestLength: Integer;
  M: TPatternMatch;
begin
  SetLength(Result, 0);
  MinLength := Length(Pattern) - MaxDistance;
  if MinLength < 1 then MinLength := 1;
  MaxLength := Length(Pattern) + MaxDistance;
  for Offset := StartOffset to Length(Text) - 1 do
  begin
    BestDistance := MaxDistance + 1;
    BestLength := 0;
    Count := MinLength;
    while (Count <= MaxLength) and (Offset + Count <= Length(Text)) do
    begin
      Distance := EditDistanceText(Pattern, Text, Offset, Count);
      if (Distance < BestDistance) or ((Distance = BestDistance) and ((BestLength = 0) or (Count < BestLength))) then
      begin
        BestDistance := Distance;
        BestLength := Count;
      end;
      Inc(Count);
    end;
    if BestDistance <= MaxDistance then
    begin
      M.Offset := Offset;
      M.MatchLength := BestLength;
      M.PatternIndex := 0;
      M.Distance := BestDistance;
      M.MatchUnit := muChar;
      AppendMatch(Result, M);
    end;
  end;
end;

procedure RunStringFuzzy(Cases: Integer);
var
  CaseIndex, TextLength, PatternLength, MaxDistance, StartOffset: Integer;
  Text, Pattern: string;
  Expected: TPatternMatches;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    TextLength := 1 + RandInt(55);
    PatternLength := 1 + RandInt(18);
    FillRandomString(Text, TextLength);
    FillRandomString(Pattern, PatternLength);
    if PatternLength = 1 then MaxDistance := 0 else MaxDistance := RandInt(Min3(4, PatternLength, PatternLength));
    StartOffset := RandInt(TextLength + 1);
    Expected := NaiveStringFuzzy(Text, Pattern, MaxDistance, StartOffset);
    CheckStringSingle(TLevenshteinSearcher.Create(Pattern, MaxDistance), Text, StartOffset, Expected, 'Levenshtein string fuzzy stress');
    CheckStringSingle(TMyersSearcher.Create(Pattern, MaxDistance), Text, StartOffset, Expected, 'Myers string fuzzy stress');
  end;
  Writeln('String fuzzy stress OK: ', Cases);
end;

procedure RunMaskedStreams(Cases: Integer);
var
  CaseIndex, PatternLength, Offset, I: Integer;
  Data, PatternBytes, Masks: TBytes;
  Pattern: TBytePattern;
begin
  for CaseIndex := 0 to Cases - 1 do
  begin
    PatternLength := 1 + RandInt(64);
    SetLength(PatternBytes, PatternLength);
    SetLength(Masks, PatternLength);
    for I := 0 to PatternLength - 1 do
    begin
      PatternBytes[I] := $A5;
      if (I and 1) = 0 then Masks[I] := $F0 else Masks[I] := $0F;
    end;
    Pattern := TBytePattern.Masked(PatternBytes, Masks);
    SetLength(Data, 65696);
    FillChar(Data[0], Length(Data), 0);
    Offset := 65520 + RandInt(48);
    if Offset + PatternLength > Length(Data) then Offset := Length(Data) - PatternLength;
    for I := 0 to PatternLength - 1 do Data[Offset + I] := PatternBytes[I];
    CheckStreamSingle(TBitapSearcher.Create(Pattern), Data, Offset, 'Bitap masked');
    CheckStreamSingle(TSbndmSearcher.Create(Pattern), Data, Offset, 'SBNDM masked');
  end;
  Writeln('Masked stream stress OK: ', Cases);
end;

procedure RunMultiStreams(Cases: Integer);
var
  CaseIndex, Offset, I: Integer;
  Data: TBytes;
  Patterns: TArray<TBytes>;
  Stream: TMemoryStream;
  S: TMultiPatternSearcher;
  M: TPatternMatch;
begin
  SetLength(Patterns, 2);
  Patterns[0] := TBytes.Create($11, $22, $33, $44, $55, $66, $77, $88);
  Patterns[1] := TBytes.Create($91, $82, $73, $64, $55, $46, $37, $28);
  for CaseIndex := 0 to Cases - 1 do
  begin
    SetLength(Data, 65696);
    FillChar(Data[0], Length(Data), $EE);
    Offset := 65524 + RandInt(36);
    for I := 0 to High(Patterns[1]) do Data[Offset + I] := Patterns[1][I];
    S := TAhoCorasickSearcher.Create(Patterns);
    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(Data[0], Length(Data));
      Stream.Position := 0;
      M := S.FindFirst(Stream, True);
      if (not M.Found) or (M.Offset <> Offset) or (M.PatternIndex <> 1) or (Stream.Position <> 0) then
        raise Exception.CreateFmt('Aho multi stream mismatch seed=%s state=%s', [IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
    finally
      Stream.Free;
      S.Free;
    end;
    S := TCommentzWalterSearcher.Create(Patterns);
    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(Data[0], Length(Data));
      Stream.Position := 0;
      M := S.FindFirst(Stream, True);
      if (not M.Found) or (M.Offset <> Offset) or (M.PatternIndex <> 1) or (Stream.Position <> 0) then
        raise Exception.CreateFmt('Commentz-Walter multi stream mismatch seed=%s state=%s', [IntToHex(GInitialSeed, 16), IntToHex(GRandState, 16)]);
    finally
      Stream.Free;
      S.Free;
    end;
  end;
  Writeln('Multi stream stress OK: ', Cases);
end;

function HasParam(const Value: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), Value) then
      Exit(True);
  Result := False;
end;

procedure ApplySeedParameter;
var
  I: Integer;
  P, V: string;
begin
  for I := 1 to ParamCount do
  begin
    P := ParamStr(I);
    if SameText(Copy(P, 1, 7), '--seed=') then
    begin
      V := Copy(P, 8, MaxInt);
      if V = '' then
        raise EArgumentException.Create('Seed value must not be empty');
      if (Length(V) > 1) and (V[1] = '0') and ((V[2] = 'x') or (V[2] = 'X')) then
        Delete(V, 1, 2);
      GInitialSeed := StrToUInt64('$' + V);
      if GInitialSeed = 0 then
        raise EArgumentOutOfRangeException.Create('Seed must not be zero');
      GRandState := GInitialSeed;
      Exit;
    end;
  end;
end;

var
  ExactCases, MaskedCases, FuzzyCases, MultiCases, StreamCases, StringCases, StringFuzzyCases, MaskedStreamCases, MultiStreamCases: Integer;
  Full: Boolean;
begin
  ReportMemoryLeaksOnShutdown := True;
  ApplySeedParameter;
  Full := HasParam('--full');
  if Full then
  begin
    ExactCases := 50000;
    MaskedCases := 30000;
    FuzzyCases := 8000;
    MultiCases := 15000;
    StreamCases := 2500;
    StringCases := 15000;
    StringFuzzyCases := 2500;
    MaskedStreamCases := 1200;
    MultiStreamCases := 1000;
  end
  else
  begin
    ExactCases := 10000;
    MaskedCases := 6000;
    FuzzyCases := 1500;
    MultiCases := 3000;
    StreamCases := 500;
    StringCases := 3000;
    StringFuzzyCases := 500;
    MaskedStreamCases := 250;
    MultiStreamCases := 200;
  end;
  Writeln('Pattern stress seed: ', IntToHex(GInitialSeed, 16));
  try
    RunExact(ExactCases);
    RunMasked(MaskedCases);
    RunFuzzy(FuzzyCases);
    RunMulti(MultiCases);
    RunStringExact(StringCases);
    RunStringFuzzy(StringFuzzyCases);
    RunFuzzyStreamRegression;
    RunStreams(StreamCases);
    RunMaskedStreams(MaskedStreamCases);
    RunMultiStreams(MultiStreamCases);
    Writeln('ALL PATTERN STRESS TESTS OK');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
