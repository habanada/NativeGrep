{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.Sbndm;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TSbndmSearcher = class(TSinglePatternSearcher)
  private
    FMatchMasks: array[Byte] of UInt64;
    FPatternMask: TBytes;
    procedure BuildMasks;
  protected
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; override;
    function DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer = 0): TPatternMatches; override;
  public
    constructor Create(const Pattern: TBytes); overload;
    constructor Create(const Pattern: string); overload;
    constructor Create(const Pattern: TBytePattern); overload;
  end;

implementation

procedure AppendMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  N: Integer;
begin
  N := Length(Matches);
  SetLength(Matches, N + 1);
  Matches[N] := Match;
end;

constructor TSbndmSearcher.Create(const Pattern: TBytes);
var
  I: Integer;
begin
  if Length(Pattern) > 64 then
    raise EArgumentOutOfRangeException.Create('SBNDM pattern length must be between 1 and 64 bytes');
  inherited Create(Pattern);
  SetLength(FPatternMask, Length(Pattern));
  for I := 0 to High(FPatternMask) do
    FPatternMask[I] := $FF;
  BuildMasks;
end;

constructor TSbndmSearcher.Create(const Pattern: string);
var
  I: Integer;
begin
  inherited Create(Pattern);
  if Length(PatternBytes) > 64 then
    raise EArgumentOutOfRangeException.Create('SBNDM string pattern must not exceed 32 UTF-16 code units');
  SetLength(FPatternMask, Length(PatternBytes));
  for I := 0 to High(FPatternMask) do
    FPatternMask[I] := $FF;
  BuildMasks;
end;

constructor TSbndmSearcher.Create(const Pattern: TBytePattern);
begin
  if Pattern.GetLength > 64 then
    raise EArgumentOutOfRangeException.Create('SBNDM pattern length must be between 1 and 64 bytes');
  inherited Create(Pattern.Bytes);
  FPatternMask := Copy(Pattern.Masks);
  BuildMasks;
end;

procedure TSbndmSearcher.BuildMasks;
var
  Value, I, PatternLength: Integer;
  Bit: UInt64;
begin
  for Value := 0 to 255 do
    FMatchMasks[Byte(Value)] := 0;
  PatternLength := Length(PatternBytes);
  for I := 0 to PatternLength - 1 do
  begin
    Bit := UInt64(1) shl (PatternLength - I - 1);
    for Value := 0 to 255 do
      if ((Byte(Value) xor PatternBytes[I]) and FPatternMask[I]) = 0 then
        FMatchMasks[Byte(Value)] := FMatchMasks[Byte(Value)] or Bit;
  end;
end;

function TSbndmSearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  D: UInt64;
  Position, PatternLength, J: NativeUInt;
begin
  Result := TPatternMatch.NotFound;
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset > BufferSize) or (PatternLength > BufferSize - StartOffset) then
    Exit;
  Position := StartOffset;
  while Position <= BufferSize - PatternLength do
  begin
    J := 1;
    D := FMatchMasks[Buffer[Position + PatternLength - 1]];
    while (D <> 0) and (J < PatternLength) do
    begin
      Inc(J);
      D := (D shl 1) and FMatchMasks[Buffer[Position + PatternLength - J]];
    end;
    if (J = PatternLength) and (D <> 0) then
    begin
      Result.Offset := Position;
      Result.MatchLength := PatternLength;
      Result.PatternIndex := 0;
      Result.Distance := 0;
      Result.MatchUnit := muByte;
      Exit;
    end;
    Inc(Position, PatternLength - J + 1);
  end;
end;

function TSbndmSearcher.DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  D: UInt64;
  Match: TPatternMatch;
  Position, PatternLength, J: NativeUInt;
begin
  SetLength(Result, 0);
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset > BufferSize) or (PatternLength > BufferSize - StartOffset) then
    Exit;
  Position := StartOffset;
  while Position <= BufferSize - PatternLength do
  begin
    J := 1;
    D := FMatchMasks[Buffer[Position + PatternLength - 1]];
    while (D <> 0) and (J < PatternLength) do
    begin
      Inc(J);
      D := (D shl 1) and FMatchMasks[Buffer[Position + PatternLength - J]];
    end;
    if (J = PatternLength) and (D <> 0) then
    begin
      Match.Offset := Position;
      Match.MatchLength := PatternLength;
      Match.PatternIndex := 0;
      Match.Distance := 0;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
      if (MaxMatches > 0) and (Length(Result) >= MaxMatches) then
        Break;
    end;
    Inc(Position, PatternLength - J + 1);
  end;
end;

end.
