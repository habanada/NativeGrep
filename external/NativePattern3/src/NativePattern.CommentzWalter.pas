{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.CommentzWalter;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  NativePattern.Core;

type
  TCommentzWalterNode = record
    Next: array[Byte] of Integer;
    Failure: Integer;
    Parent: Integer;
    Depth: NativeUInt;
    Shift1: NativeUInt;
    Shift2: NativeUInt;
    Outputs: TArray<Integer>;
  end;

  TCommentzWalterSearcher = class(TMultiPatternSearcher)
  private
    FNodes: TArray<TCommentzWalterNode>;
    FPatterns: TArray<TBytes>;
    FPatternLengths: TArray<NativeUInt>;
    FTextPatternLengths: TArray<NativeUInt>;
    FCharShift: array[Byte] of NativeUInt;
    FTextMode: Boolean;
    FMinPatternLength: NativeUInt;
    FMaxPatternLength: NativeUInt;
    function AddNode(Parent: Integer; Depth: NativeUInt): Integer;
    procedure AddOutput(NodeIndex, PatternIndex: Integer);
    procedure BuildTrie;
    procedure BuildFailures;
    procedure BuildShifts;
    function FindAllBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatches;
    function FindFirstBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
  public
    constructor Create(const Patterns: array of TBytes); overload;
    constructor Create(const Patterns: array of string); overload;
    function FindFirst(Buffer: Pointer; BufferSize: NativeUInt; StartOffset: NativeUInt = 0): TPatternMatch; overload; override;
    function FindFirst(const Data: TBytes; StartOffset: NativeUInt = 0): TPatternMatch; overload; override;
    function FindFirst(const Text: string; StartOffset: NativeUInt = 0): TPatternMatch; overload; override;
    function FindFirst(Stream: TStream; PreservePosition: Boolean = True): TPatternMatch; overload; override;
    function FindFirst(List: TList<Byte>; StartOffset: NativeUInt = 0): TPatternMatch; overload; override;
    function FindAll(Buffer: Pointer; BufferSize: NativeUInt; StartOffset: NativeUInt = 0): TPatternMatches; overload; override;
    function FindAll(const Data: TBytes; StartOffset: NativeUInt = 0): TPatternMatches; overload; override;
    function FindAll(const Text: string; StartOffset: NativeUInt = 0): TPatternMatches; overload; override;
    function FindAll(Stream: TStream; PreservePosition: Boolean = True): TPatternMatches; overload; override;
    function FindAll(List: TList<Byte>; StartOffset: NativeUInt = 0): TPatternMatches; overload; override;
    function PatternCount: Integer; override;
  end;

implementation

const
  CW_STREAM_CHUNK_SIZE = 65536;

function MinNativeUInt(A, B: NativeUInt): NativeUInt;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

function MaxNativeUInt(A, B: NativeUInt): NativeUInt;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

procedure AppendMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  N: Integer;
begin
  N := Length(Matches);
  SetLength(Matches, N + 1);
  Matches[N] := Match;
end;

procedure AddUniqueMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  I, J, N: Integer;
begin
  I := High(Matches);
  while I >= 0 do
  begin
    if (Matches[I].Offset = Match.Offset) and (Matches[I].PatternIndex = Match.PatternIndex) then
      Exit;
    if (Matches[I].Offset < Match.Offset) or ((Matches[I].Offset = Match.Offset) and (Matches[I].PatternIndex < Match.PatternIndex)) then
      Break;
    Dec(I);
  end;
  N := Length(Matches);
  SetLength(Matches, N + 1);
  for J := N downto I + 2 do
    Matches[J] := Matches[J - 1];
  Matches[I + 1] := Match;
end;

function CompareMatches(const A, B: TPatternMatch): Integer;
begin
  if A.Offset < B.Offset then
    Exit(-1);
  if A.Offset > B.Offset then
    Exit(1);
  if A.Distance < B.Distance then
    Exit(-1);
  if A.Distance > B.Distance then
    Exit(1);
  if A.PatternIndex < B.PatternIndex then
    Exit(-1);
  if A.PatternIndex > B.PatternIndex then
    Exit(1);
  if A.MatchLength < B.MatchLength then
    Exit(-1);
  if A.MatchLength > B.MatchLength then
    Exit(1);
  Result := 0;
end;

procedure QuickSortMatches(var Matches: TPatternMatches; Left, Right: Integer);
var
  I, J: Integer;
  Pivot, Temp: TPatternMatch;
begin
  I := Left;
  J := Right;
  Pivot := Matches[Left + (Right - Left) div 2];
  repeat
    while CompareMatches(Matches[I], Pivot) < 0 do
      Inc(I);
    while CompareMatches(Matches[J], Pivot) > 0 do
      Dec(J);
    if I <= J then
    begin
      Temp := Matches[I];
      Matches[I] := Matches[J];
      Matches[J] := Temp;
      Inc(I);
      Dec(J);
    end;
  until I > J;
  if Left < J then
    QuickSortMatches(Matches, Left, J);
  if I < Right then
    QuickSortMatches(Matches, I, Right);
end;

procedure SortMatches(var Matches: TPatternMatches);
begin
  if Length(Matches) > 1 then
    QuickSortMatches(Matches, 0, High(Matches));
end;

function StringBytes(const Value: string): TBytes;
var
  ByteLength: NativeUInt;
begin
  ByteLength := NativeUInt(Length(Value)) * SizeOf(Char);
  SetLength(Result, ByteLength);
  if ByteLength > 0 then
    Move(PChar(Value)^, Result[0], ByteLength);
end;

constructor TCommentzWalterSearcher.Create(const Patterns: array of TBytes);
var
  I: Integer;
begin
  inherited Create;
  if Length(Patterns) = 0 then
    raise EArgumentException.Create('At least one pattern is required');
  FTextMode := False;
  FMinPatternLength := High(NativeUInt);
  FMaxPatternLength := 0;
  SetLength(FPatterns, Length(Patterns));
  SetLength(FPatternLengths, Length(Patterns));
  SetLength(FTextPatternLengths, 0);
  for I := 0 to High(Patterns) do
  begin
    if Length(Patterns[I]) = 0 then
      raise EArgumentException.CreateFmt('Pattern %d must not be empty', [I]);
    FPatterns[I] := Copy(Patterns[I]);
    FPatternLengths[I] := Length(Patterns[I]);
    FMinPatternLength := MinNativeUInt(FMinPatternLength, FPatternLengths[I]);
    FMaxPatternLength := MaxNativeUInt(FMaxPatternLength, FPatternLengths[I]);
  end;
  BuildTrie;
  BuildFailures;
  BuildShifts;
end;

constructor TCommentzWalterSearcher.Create(const Patterns: array of string);
var
  I: Integer;
begin
  inherited Create;
  if Length(Patterns) = 0 then
    raise EArgumentException.Create('At least one pattern is required');
  FTextMode := True;
  FMinPatternLength := High(NativeUInt);
  FMaxPatternLength := 0;
  SetLength(FPatterns, Length(Patterns));
  SetLength(FPatternLengths, Length(Patterns));
  SetLength(FTextPatternLengths, Length(Patterns));
  for I := 0 to High(Patterns) do
  begin
    if Patterns[I] = '' then
      raise EArgumentException.CreateFmt('Pattern %d must not be empty', [I]);
    FPatterns[I] := StringBytes(Patterns[I]);
    FPatternLengths[I] := Length(FPatterns[I]);
    FTextPatternLengths[I] := Length(Patterns[I]);
    FMinPatternLength := MinNativeUInt(FMinPatternLength, FPatternLengths[I]);
    FMaxPatternLength := MaxNativeUInt(FMaxPatternLength, FPatternLengths[I]);
  end;
  BuildTrie;
  BuildFailures;
  BuildShifts;
end;

function TCommentzWalterSearcher.AddNode(Parent: Integer; Depth: NativeUInt): Integer;
var
  I: Integer;
begin
  Result := Length(FNodes);
  SetLength(FNodes, Result + 1);
  FNodes[Result].Failure := 0;
  FNodes[Result].Parent := Parent;
  FNodes[Result].Depth := Depth;
  FNodes[Result].Shift1 := FMinPatternLength;
  FNodes[Result].Shift2 := FMinPatternLength;
  SetLength(FNodes[Result].Outputs, 0);
  for I := 0 to 255 do
    FNodes[Result].Next[Byte(I)] := -1;
end;

procedure TCommentzWalterSearcher.AddOutput(NodeIndex, PatternIndex: Integer);
var
  N: Integer;
begin
  N := Length(FNodes[NodeIndex].Outputs);
  SetLength(FNodes[NodeIndex].Outputs, N + 1);
  FNodes[NodeIndex].Outputs[N] := PatternIndex;
end;

procedure TCommentzWalterSearcher.BuildTrie;
var
  I, PatternIndex, State, NextState, Value: Integer;
  B: Byte;
begin
  SetLength(FNodes, 0);
  AddNode(-1, 0);
  for Value := 0 to 255 do
    FCharShift[Byte(Value)] := FMinPatternLength + 1;
  for PatternIndex := 0 to High(FPatterns) do
  begin
    State := 0;
    for I := High(FPatterns[PatternIndex]) downto 0 do
    begin
      B := FPatterns[PatternIndex][I];
      NextState := FNodes[State].Next[B];
      if NextState < 0 then
      begin
        NextState := AddNode(State, FNodes[State].Depth + 1);
        FNodes[State].Next[B] := NextState;
        if FNodes[NextState].Depth < FCharShift[B] then
          FCharShift[B] := FNodes[NextState].Depth;
      end;
      State := NextState;
    end;
    AddOutput(State, PatternIndex);
  end;
end;

procedure TCommentzWalterSearcher.BuildFailures;
var
  Queue: TQueue<Integer>;
  State, NextState, FailureState, Value: Integer;
  B: Byte;
begin
  Queue := TQueue<Integer>.Create;
  try
    for Value := 0 to 255 do
    begin
      B := Byte(Value);
      NextState := FNodes[0].Next[B];
      if NextState >= 0 then
      begin
        FNodes[NextState].Failure := 0;
        Queue.Enqueue(NextState);
      end;
    end;
    while Queue.Count > 0 do
    begin
      State := Queue.Dequeue;
      for Value := 0 to 255 do
      begin
        B := Byte(Value);
        NextState := FNodes[State].Next[B];
        if NextState < 0 then
          Continue;
        FailureState := FNodes[State].Failure;
        while (FailureState <> 0) and (FNodes[FailureState].Next[B] < 0) do
          FailureState := FNodes[FailureState].Failure;
        if FNodes[FailureState].Next[B] >= 0 then
          FailureState := FNodes[FailureState].Next[B]
        else
          FailureState := 0;
        FNodes[NextState].Failure := FailureState;
        Queue.Enqueue(NextState);
      end;
    end;
  finally
    Queue.Free;
  end;
end;

procedure TCommentzWalterSearcher.BuildShifts;
var
  DirectTerminalShift: TArray<NativeUInt>;
  U, F: Integer;
  Diff: NativeUInt;
begin
  SetLength(DirectTerminalShift, Length(FNodes));
  for U := 0 to High(FNodes) do
  begin
    FNodes[U].Shift1 := FMinPatternLength;
    FNodes[U].Shift2 := FMinPatternLength;
    DirectTerminalShift[U] := FMinPatternLength;
  end;
  FNodes[0].Shift1 := 1;
  FNodes[0].Shift2 := FMinPatternLength;
  for U := 1 to High(FNodes) do
  begin
    F := FNodes[U].Failure;
    while F <> 0 do
    begin
      Diff := FNodes[U].Depth - FNodes[F].Depth;
      if Diff < FNodes[F].Shift1 then
        FNodes[F].Shift1 := Diff;
      if (Length(FNodes[U].Outputs) > 0) and (Diff < DirectTerminalShift[F]) then
        DirectTerminalShift[F] := Diff;
      F := FNodes[F].Failure;
    end;
  end;
  for U := 1 to High(FNodes) do
    FNodes[U].Shift2 := MinNativeUInt(DirectTerminalShift[U], FNodes[FNodes[U].Parent].Shift2);
end;

function TCommentzWalterSearcher.FindAllBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatches;
var
  K, J, Shift, CharCandidate: NativeUInt;
  State, NextState, OutputIndex, PatternIndex: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if (Buffer = nil) or (StartOffset >= BufferSize) or (FMinPatternLength > BufferSize - StartOffset) then
    Exit;
  K := StartOffset + FMinPatternLength - 1;
  while K < BufferSize do
  begin
    State := 0;
    J := 0;
    while (J <= K - StartOffset) do
    begin
      NextState := FNodes[State].Next[Buffer[K - J]];
      if NextState < 0 then
        Break;
      State := NextState;
      Inc(J);
      for OutputIndex := 0 to High(FNodes[State].Outputs) do
      begin
        PatternIndex := FNodes[State].Outputs[OutputIndex];
        if FPatternLengths[PatternIndex] > J then
          Continue;
       Match.Offset := K + 1 - FPatternLengths[PatternIndex];
        if Match.Offset < Int64(StartOffset) then
          Continue;
        Match.MatchLength := FPatternLengths[PatternIndex];
        Match.PatternIndex := PatternIndex;
        Match.Distance := 0;
        Match.MatchUnit := muByte;
        AppendMatch(Result, Match);
      end;
    end;
    if (J > K - StartOffset) then
      Shift := 1
    else
    begin
      CharCandidate := FCharShift[Buffer[K - J]];
      if CharCandidate > J + 1 then
        CharCandidate := CharCandidate - J - 1
      else
        CharCandidate := 1;
      Shift := MaxNativeUInt(FNodes[State].Shift1, CharCandidate);
      Shift := MinNativeUInt(Shift, FNodes[State].Shift2);
      if Shift = 0 then
        Shift := 1;
    end;
    if K > High(NativeUInt) - Shift then
      Break;
    Inc(K, Shift);
  end;
  SortMatches(Result);
end;

function TCommentzWalterSearcher.FindFirstBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  K, J, Shift, CharCandidate, StopAfter: NativeUInt;
  State, NextState, OutputIndex, PatternIndex: Integer;
  Match: TPatternMatch;
  HaveBest: Boolean;
begin
  Result := TPatternMatch.NotFound;
  if (Buffer = nil) or (StartOffset >= BufferSize) or (FMinPatternLength > BufferSize - StartOffset) then
    Exit;
  K := StartOffset + FMinPatternLength - 1;
  StopAfter := High(NativeUInt);
  HaveBest := False;
  while K < BufferSize do
  begin
    State := 0;
    J := 0;
    while J <= K - StartOffset do
    begin
      NextState := FNodes[State].Next[Buffer[K - J]];
      if NextState < 0 then
        Break;
      State := NextState;
      Inc(J);
      for OutputIndex := 0 to High(FNodes[State].Outputs) do
      begin
        PatternIndex := FNodes[State].Outputs[OutputIndex];
        if FPatternLengths[PatternIndex] > J then
          Continue;
        Match.Offset := K + 1 - FPatternLengths[PatternIndex];
        if Match.Offset < Int64(StartOffset) then
          Continue;
        Match.MatchLength := FPatternLengths[PatternIndex];
        Match.PatternIndex := PatternIndex;
        Match.Distance := 0;
        Match.MatchUnit := muByte;
        if (not HaveBest) or (Match.Offset < Result.Offset) or ((Match.Offset = Result.Offset) and (PatternIndex < Result.PatternIndex)) then
        begin
          Result := Match;
          HaveBest := True;
          if NativeUInt(Match.Offset) <= High(NativeUInt) - FMaxPatternLength + 1 then
            StopAfter := NativeUInt(Match.Offset) + FMaxPatternLength - 1;
        end;
      end;
    end;
    if HaveBest and (K >= StopAfter) then
      Break;
    if J > K - StartOffset then
      Shift := 1
    else
    begin
      CharCandidate := FCharShift[Buffer[K - J]];
      if CharCandidate > J + 1 then
        CharCandidate := CharCandidate - J - 1
      else
        CharCandidate := 1;
      Shift := MaxNativeUInt(FNodes[State].Shift1, CharCandidate);
      Shift := MinNativeUInt(Shift, FNodes[State].Shift2);
      if Shift = 0 then
        Shift := 1;
    end;
    if K > High(NativeUInt) - Shift then
      Break;
    Inc(K, Shift);
  end;
end;

function TCommentzWalterSearcher.FindFirst(Buffer: Pointer; BufferSize, StartOffset: NativeUInt): TPatternMatch;
begin
  Result := FindFirstBuffer(PByte(Buffer), BufferSize, StartOffset);
end;

function TCommentzWalterSearcher.FindFirst(const Data: TBytes; StartOffset: NativeUInt): TPatternMatch;
begin
  if (Length(Data) = 0) or (StartOffset >= NativeUInt(Length(Data))) then
    Exit(TPatternMatch.NotFound);
  Result := FindFirstBuffer(@Data[0], Length(Data), StartOffset);
end;

function TCommentzWalterSearcher.FindFirst(const Text: string; StartOffset: NativeUInt): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := FindAll(Text, StartOffset);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TCommentzWalterSearcher.FindFirst(Stream: TStream; PreservePosition: Boolean): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := FindAll(Stream, PreservePosition);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TCommentzWalterSearcher.FindFirst(List: TList<Byte>; StartOffset: NativeUInt): TPatternMatch;
var
  Data: TBytes;
begin
  if List = nil then
    Exit(TPatternMatch.NotFound);
  Data := List.ToArray;
  Result := FindFirst(Data, StartOffset);
end;

function TCommentzWalterSearcher.FindAll(Buffer: Pointer; BufferSize, StartOffset: NativeUInt): TPatternMatches;
begin
  Result := FindAllBuffer(PByte(Buffer), BufferSize, StartOffset);
end;

function TCommentzWalterSearcher.FindAll(const Data: TBytes; StartOffset: NativeUInt): TPatternMatches;
begin
  SetLength(Result, 0);
  if (Length(Data) = 0) or (StartOffset >= NativeUInt(Length(Data))) then
    Exit;
  Result := FindAllBuffer(@Data[0], Length(Data), StartOffset);
end;

function TCommentzWalterSearcher.FindAll(const Text: string; StartOffset: NativeUInt): TPatternMatches;
var
  ByteMatches: TPatternMatches;
  Match: TPatternMatch;
  I: Integer;
  ByteSize, ByteStart: NativeUInt;
begin
  SetLength(Result, 0);
  if not FTextMode then
    raise EInvalidOpException.Create('String search requires string patterns');
  if (Text = '') or (StartOffset >= NativeUInt(Length(Text))) then
    Exit;
  ByteSize := NativeUInt(Length(Text)) * SizeOf(Char);
  ByteStart := StartOffset * SizeOf(Char);
  ByteMatches := FindAllBuffer(PByte(PChar(Text)), ByteSize, ByteStart);
  for I := 0 to High(ByteMatches) do
    if (ByteMatches[I].Offset mod SizeOf(Char)) = 0 then
    begin
      Match := ByteMatches[I];
      Match.Offset := Match.Offset div SizeOf(Char);
      Match.MatchLength := FTextPatternLengths[Match.PatternIndex];
      Match.MatchUnit := muChar;
      AddUniqueMatch(Result, Match);
    end;
  SortMatches(Result);
end;

function TCommentzWalterSearcher.FindAll(Stream: TStream; PreservePosition: Boolean): TPatternMatches;
var
  SavedPosition, ReadStart, BlockBase: Int64;
  Carry, ReadBuffer, Block: TBytes;
  ReadCount, CarryCount, I: Integer;
  LocalMatches: TPatternMatches;
  Match: TPatternMatch;
  KeepCount: NativeUInt;
begin
  SetLength(Result, 0);
  if Stream = nil then
    Exit;
  SavedPosition := Stream.Position;
  try
    ReadStart := Stream.Position;
    SetLength(Carry, 0);
    SetLength(ReadBuffer, CW_STREAM_CHUNK_SIZE);
    repeat
      ReadCount := Stream.Read(ReadBuffer[0], Length(ReadBuffer));
      if ReadCount <= 0 then
        Break;
      CarryCount := Length(Carry);
      SetLength(Block, CarryCount + ReadCount);
      if CarryCount > 0 then
        Move(Carry[0], Block[0], CarryCount);
      Move(ReadBuffer[0], Block[CarryCount], ReadCount);
      BlockBase := ReadStart - CarryCount;
      LocalMatches := FindAllBuffer(@Block[0], Length(Block), 0);
      for I := 0 to High(LocalMatches) do
      begin
        if (CarryCount > 0) and (LocalMatches[I].Offset + Int64(LocalMatches[I].MatchLength) <= CarryCount) then
          Continue;
        Match := LocalMatches[I];
        Match.Offset := BlockBase + Match.Offset;
        AddUniqueMatch(Result, Match);
      end;
      Inc(ReadStart, ReadCount);
      if FMaxPatternLength > 1 then
        KeepCount := FMaxPatternLength - 1
      else
        KeepCount := 0;
      if KeepCount > NativeUInt(Length(Block)) then
        KeepCount := Length(Block);
      SetLength(Carry, KeepCount);
      if KeepCount > 0 then
        Move(Block[Length(Block) - Integer(KeepCount)], Carry[0], KeepCount);
    until False;
  finally
    if PreservePosition then
      Stream.Position := SavedPosition;
  end;
  SortMatches(Result);
end;

function TCommentzWalterSearcher.FindAll(List: TList<Byte>; StartOffset: NativeUInt): TPatternMatches;
var
  Data: TBytes;
begin
  SetLength(Result, 0);
  if List = nil then
    Exit;
  Data := List.ToArray;
  Result := FindAll(Data, StartOffset);
end;

function TCommentzWalterSearcher.PatternCount: Integer;
begin
  Result := Length(FPatterns);
end;

end.
