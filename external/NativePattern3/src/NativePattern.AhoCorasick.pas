{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.AhoCorasick;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  NativePattern.Core;

type
  TAhoNode = record
    Next: array[Byte] of Integer;
    Failure: Integer;
    Outputs: TArray<Integer>;
  end;

  TAhoCorasickSearcher = class(TMultiPatternSearcher)
  private
    FNodes: TArray<TAhoNode>;
    FPatterns: TArray<TBytes>;
    FPatternLengths: TArray<NativeUInt>;
    FTextPatternLengths: TArray<NativeUInt>;
    FTextMode: Boolean;
    FMaxPatternLength: NativeUInt;
    function AddNode: Integer;
    procedure AddOutput(NodeIndex, PatternIndex: Integer);
    procedure AddFailureOutputs(NodeIndex, FailureIndex: Integer);
    procedure BuildTrie;
    procedure BuildFailures;
    function FindFirstBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
    function FindAllBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatches;
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
  AHO_STREAM_CHUNK_SIZE = 65536;

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

constructor TAhoCorasickSearcher.Create(const Patterns: array of TBytes);
var
  I: Integer;
begin
  inherited Create;
  if Length(Patterns) = 0 then
    raise EArgumentException.Create('At least one pattern is required');
  FTextMode := False;
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
    if FPatternLengths[I] > FMaxPatternLength then
      FMaxPatternLength := FPatternLengths[I];
  end;
  BuildTrie;
  BuildFailures;
end;

constructor TAhoCorasickSearcher.Create(const Patterns: array of string);
var
  I: Integer;
begin
  inherited Create;
  if Length(Patterns) = 0 then
    raise EArgumentException.Create('At least one pattern is required');
  FTextMode := True;
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
    if FPatternLengths[I] > FMaxPatternLength then
      FMaxPatternLength := FPatternLengths[I];
  end;
  BuildTrie;
  BuildFailures;
end;

function TAhoCorasickSearcher.AddNode: Integer;
var
  I: Integer;
begin
  Result := Length(FNodes);
  SetLength(FNodes, Result + 1);
  FNodes[Result].Failure := 0;
  SetLength(FNodes[Result].Outputs, 0);
  for I := 0 to 255 do
    FNodes[Result].Next[Byte(I)] := -1;
end;

procedure TAhoCorasickSearcher.AddOutput(NodeIndex, PatternIndex: Integer);
var
  N: Integer;
begin
  N := Length(FNodes[NodeIndex].Outputs);
  SetLength(FNodes[NodeIndex].Outputs, N + 1);
  FNodes[NodeIndex].Outputs[N] := PatternIndex;
end;

procedure TAhoCorasickSearcher.AddFailureOutputs(NodeIndex, FailureIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FNodes[FailureIndex].Outputs) do
    AddOutput(NodeIndex, FNodes[FailureIndex].Outputs[I]);
end;

procedure TAhoCorasickSearcher.BuildTrie;
var
  PatternIndex, I, State, NextState: Integer;
  B: Byte;
begin
  SetLength(FNodes, 0);
  AddNode;
  for PatternIndex := 0 to High(FPatterns) do
  begin
    State := 0;
    for I := 0 to High(FPatterns[PatternIndex]) do
    begin
      B := FPatterns[PatternIndex][I];
      NextState := FNodes[State].Next[B];
      if NextState < 0 then
      begin
        NextState := AddNode;
        FNodes[State].Next[B] := NextState;
      end;
      State := NextState;
    end;
    AddOutput(State, PatternIndex);
  end;
end;

procedure TAhoCorasickSearcher.BuildFailures;
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
      if NextState < 0 then
        FNodes[0].Next[B] := 0
      else if NextState <> 0 then
      begin
        FNodes[NextState].Failure := 0;
        Queue.Enqueue(NextState);
      end;
    end;
    while Queue.Count > 0 do
    begin
      State := Queue.Dequeue;
      FailureState := FNodes[State].Failure;
      for Value := 0 to 255 do
      begin
        B := Byte(Value);
        NextState := FNodes[State].Next[B];
        if NextState >= 0 then
        begin
          FNodes[NextState].Failure := FNodes[FailureState].Next[B];
          AddFailureOutputs(NextState, FNodes[NextState].Failure);
          Queue.Enqueue(NextState);
        end
        else
          FNodes[State].Next[B] := FNodes[FailureState].Next[B];
      end;
    end;
  finally
    Queue.Free;
  end;
end;

function TAhoCorasickSearcher.FindFirstBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  State, OutputIndex, PatternIndex: Integer;
  Position, MatchOffset, StopAfter: NativeUInt;
  Match: TPatternMatch;
  HaveBest: Boolean;
begin
  Result := TPatternMatch.NotFound;
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit;
  State := 0;
  Position := StartOffset;
  HaveBest := False;
  StopAfter := High(NativeUInt);
  while Position < BufferSize do
  begin
    State := FNodes[State].Next[Buffer[Position]];
    for OutputIndex := 0 to High(FNodes[State].Outputs) do
    begin
      PatternIndex := FNodes[State].Outputs[OutputIndex];
      if FPatternLengths[PatternIndex] > Position - StartOffset + 1 then
        Continue;
      MatchOffset := Position + 1 - FPatternLengths[PatternIndex];
      if not HaveBest then
      begin
        Match.Offset := MatchOffset;
        Match.MatchLength := FPatternLengths[PatternIndex];
        Match.PatternIndex := PatternIndex;
        Match.Distance := 0;
        Match.MatchUnit := muByte;
        Result := Match;
        HaveBest := True;
        if MatchOffset <= High(NativeUInt) - FMaxPatternLength then
          StopAfter := MatchOffset + FMaxPatternLength - 1;
      end
      else if (MatchOffset < NativeUInt(Result.Offset)) or ((MatchOffset = NativeUInt(Result.Offset)) and (PatternIndex < Result.PatternIndex)) then
      begin
        Match.Offset := MatchOffset;
        Match.MatchLength := FPatternLengths[PatternIndex];
        Match.PatternIndex := PatternIndex;
        Match.Distance := 0;
        Match.MatchUnit := muByte;
        Result := Match;
        if MatchOffset <= High(NativeUInt) - FMaxPatternLength then
          StopAfter := MatchOffset + FMaxPatternLength - 1;
      end;
    end;
    if HaveBest and (Position >= StopAfter) then
      Break;
    Inc(Position);
  end;
end;

function TAhoCorasickSearcher.FindAllBuffer(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatches;
var
  State, OutputIndex, PatternIndex: Integer;
  Position: NativeUInt;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit;
  State := 0;
  Position := StartOffset;
  while Position < BufferSize do
  begin
    State := FNodes[State].Next[Buffer[Position]];
    for OutputIndex := 0 to High(FNodes[State].Outputs) do
    begin
      PatternIndex := FNodes[State].Outputs[OutputIndex];
      if FPatternLengths[PatternIndex] > Position - StartOffset + 1 then
        Continue;
      Match.Offset := Position + 1 - FPatternLengths[PatternIndex];
      Match.MatchLength := FPatternLengths[PatternIndex];
      Match.PatternIndex := PatternIndex;
      Match.Distance := 0;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
    end;
    Inc(Position);
  end;
  SortMatches(Result);
end;

function TAhoCorasickSearcher.FindFirst(Buffer: Pointer; BufferSize, StartOffset: NativeUInt): TPatternMatch;
begin
  Result := FindFirstBuffer(PByte(Buffer), BufferSize, StartOffset);
end;

function TAhoCorasickSearcher.FindFirst(const Data: TBytes; StartOffset: NativeUInt): TPatternMatch;
begin
  if (Length(Data) = 0) or (StartOffset >= NativeUInt(Length(Data))) then
    Exit(TPatternMatch.NotFound);
  Result := FindFirstBuffer(@Data[0], Length(Data), StartOffset);
end;

function TAhoCorasickSearcher.FindFirst(const Text: string; StartOffset: NativeUInt): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := FindAll(Text, StartOffset);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TAhoCorasickSearcher.FindFirst(Stream: TStream; PreservePosition: Boolean): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := FindAll(Stream, PreservePosition);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TAhoCorasickSearcher.FindFirst(List: TList<Byte>; StartOffset: NativeUInt): TPatternMatch;
var
  Data: TBytes;
begin
  if List = nil then
    Exit(TPatternMatch.NotFound);
  Data := List.ToArray;
  Result := FindFirst(Data, StartOffset);
end;

function TAhoCorasickSearcher.FindAll(Buffer: Pointer; BufferSize, StartOffset: NativeUInt): TPatternMatches;
begin
  Result := FindAllBuffer(PByte(Buffer), BufferSize, StartOffset);
end;

function TAhoCorasickSearcher.FindAll(const Data: TBytes; StartOffset: NativeUInt): TPatternMatches;
begin
  SetLength(Result, 0);
  if (Length(Data) = 0) or (StartOffset >= NativeUInt(Length(Data))) then
    Exit;
  Result := FindAllBuffer(@Data[0], Length(Data), StartOffset);
end;

function TAhoCorasickSearcher.FindAll(const Text: string; StartOffset: NativeUInt): TPatternMatches;
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
      AppendMatch(Result, Match);
    end;
end;

function TAhoCorasickSearcher.FindAll(Stream: TStream; PreservePosition: Boolean): TPatternMatches;
var
  SavedPosition, BaseOffset: Int64;
  Buffer: TBytes;
  ReadCount, State, OutputIndex, PatternIndex: Integer;
  I: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if Stream = nil then
    Exit;
  SavedPosition := Stream.Position;
  BaseOffset := SavedPosition;
  State := 0;
  SetLength(Buffer, AHO_STREAM_CHUNK_SIZE);
  try
    repeat
      ReadCount := Stream.Read(Buffer[0], Length(Buffer));
      if ReadCount <= 0 then
        Break;
      for I := 0 to ReadCount - 1 do
      begin
        State := FNodes[State].Next[Buffer[I]];
        for OutputIndex := 0 to High(FNodes[State].Outputs) do
        begin
          PatternIndex := FNodes[State].Outputs[OutputIndex];
          Match.Offset := BaseOffset + I - Int64(FPatternLengths[PatternIndex]) + 1;
          if Match.Offset < SavedPosition then
            Continue;
          Match.MatchLength := FPatternLengths[PatternIndex];
          Match.PatternIndex := PatternIndex;
          Match.Distance := 0;
          Match.MatchUnit := muByte;
          AppendMatch(Result, Match);
        end;
      end;
      Inc(BaseOffset, ReadCount);
    until False;
  finally
    if PreservePosition then
      Stream.Position := SavedPosition;
  end;
  SortMatches(Result);
end;

function TAhoCorasickSearcher.FindAll(List: TList<Byte>; StartOffset: NativeUInt): TPatternMatches;
var
  Data: TBytes;
begin
  SetLength(Result, 0);
  if List = nil then
    Exit;
  Data := List.ToArray;
  Result := FindAll(Data, StartOffset);
end;

function TAhoCorasickSearcher.PatternCount: Integer;
begin
  Result := Length(FPatterns);
end;

end.
