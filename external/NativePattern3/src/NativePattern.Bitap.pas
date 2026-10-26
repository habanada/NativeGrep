{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.Bitap;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TBitapSearcher = class(TSinglePatternSearcher)
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

constructor TBitapSearcher.Create(const Pattern: TBytes);
var
  I: Integer;
begin
  if Length(Pattern) > 64 then
    raise EArgumentOutOfRangeException.Create('Bitap pattern length must be between 1 and 64 bytes');
  inherited Create(Pattern);
  SetLength(FPatternMask, Length(Pattern));
  for I := 0 to High(FPatternMask) do
    FPatternMask[I] := $FF;
  BuildMasks;
end;

constructor TBitapSearcher.Create(const Pattern: string);
var
  I: Integer;
begin
  inherited Create(Pattern);
  if Length(PatternBytes) > 64 then
    raise EArgumentOutOfRangeException.Create('Bitap string pattern must not exceed 32 UTF-16 code units');
  SetLength(FPatternMask, Length(PatternBytes));
  for I := 0 to High(FPatternMask) do
    FPatternMask[I] := $FF;
  BuildMasks;
end;

constructor TBitapSearcher.Create(const Pattern: TBytePattern);
begin
  if Pattern.GetLength > 64 then
    raise EArgumentOutOfRangeException.Create('Bitap pattern length must be between 1 and 64 bytes');
  inherited Create(Pattern.Bytes);
  FPatternMask := Copy(Pattern.Masks);
  BuildMasks;
end;

procedure TBitapSearcher.BuildMasks;
var
  Value, I: Integer;
  Bit: UInt64;
begin
  for Value := 0 to 255 do
    FMatchMasks[Byte(Value)] := 0;
  for I := 0 to High(PatternBytes) do
  begin
    Bit := UInt64(1) shl I;
    for Value := 0 to 255 do
      if ((Byte(Value) xor PatternBytes[I]) and FPatternMask[I]) = 0 then
        FMatchMasks[Byte(Value)] := FMatchMasks[Byte(Value)] or Bit;
  end;
end;

function TBitapSearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  State, MatchBit: UInt64;
  I, PatternLength: NativeUInt;
begin
  Result := TPatternMatch.NotFound;
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset >= BufferSize) then
    Exit;
  State := 0;
  MatchBit := UInt64(1) shl (PatternLength - 1);
  I := StartOffset;
  while I < BufferSize do
  begin
    State := ((State shl 1) or 1) and FMatchMasks[Buffer[I]];
    if (State and MatchBit) <> 0 then
    begin
      Result.Offset := Int64(I + 1 - PatternLength);
      Result.MatchLength := PatternLength;
      Result.PatternIndex := 0;
      Result.Distance := 0;
      Result.MatchUnit := muByte;
      Exit;
    end;
    Inc(I);
  end;
end;

function TBitapSearcher.DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  State, MatchBit: UInt64;
  I, PatternLength: NativeUInt;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset >= BufferSize) then
    Exit;
  State := 0;
  MatchBit := UInt64(1) shl (PatternLength - 1);
  I := StartOffset;
  while I < BufferSize do
  begin
    State := ((State shl 1) or 1) and FMatchMasks[Buffer[I]];
    if (State and MatchBit) <> 0 then
    begin
      Match.Offset := Int64(I + 1 - PatternLength);
      Match.MatchLength := PatternLength;
      Match.PatternIndex := 0;
      Match.Distance := 0;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
      if (MaxMatches > 0) and (Length(Result) >= MaxMatches) then
        Exit;
    end;
    Inc(I);
  end;
end;

end.
