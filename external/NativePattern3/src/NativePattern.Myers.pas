{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.Myers;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  NativePattern.Core;

type
  TMyersSearcher = class(TSinglePatternSearcher)
  private
    FByteMasks: array[Byte] of UInt64;
    FCharMasks: TDictionary<Char, UInt64>;
    FMaxDistance: Integer;
    FPatternLength: Integer;
    FHighestBit: UInt64;
    procedure BuildByteMasks;
    procedure BuildCharMasks;
    function GetCharMask(C: Char): UInt64;
    function SearchBytes(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
    function SearchText(const Text: string; StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
  protected
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; override;
    function DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer = 0): TPatternMatches; override;
    function StreamOverlap: NativeUInt; override;
    function CanStopStreamAfterFirst: Boolean; override;
  public
    constructor Create(const Pattern: TBytes; MaxDistance: Integer); overload;
    constructor Create(const Pattern: string; MaxDistance: Integer); overload;
    destructor Destroy; override;
    function FindFirst(const Text: string; StartOffset: NativeUInt = 0): TPatternMatch; overload; override;
    function FindAll(const Text: string; StartOffset: NativeUInt = 0): TPatternMatches; overload; override;
    property MaxDistance: Integer read FMaxDistance;
  end;

implementation

function AddUInt64Wrap(A, B: UInt64): UInt64;
var
  LowSum, HighSum: UInt64;
begin
  LowSum := UInt64(Cardinal(A and $FFFFFFFF)) + UInt64(Cardinal(B and $FFFFFFFF));
  HighSum := UInt64(Cardinal(A shr 32)) + UInt64(Cardinal(B shr 32)) + (LowSum shr 32);
  Result := (UInt64(Cardinal(HighSum and $FFFFFFFF)) shl 32) or UInt64(Cardinal(LowSum and $FFFFFFFF));
end;

procedure AppendMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  N: Integer;
begin
  N := Length(Matches);
  SetLength(Matches, N + 1);
  Matches[N] := Match;
end;

constructor TMyersSearcher.Create(const Pattern: TBytes; MaxDistance: Integer);
begin
  if Length(Pattern) = 0 then
    raise EArgumentException.Create('Pattern must not be empty');
  if Length(Pattern) > 64 then
    raise EArgumentOutOfRangeException.Create('Myers pattern length must be between 1 and 64 bytes');
  if (MaxDistance < 0) or (MaxDistance >= Length(Pattern)) then
    raise EArgumentOutOfRangeException.Create('Maximum distance must be between 0 and pattern length - 1');
  inherited Create(Pattern);
  FMaxDistance := MaxDistance;
  FPatternLength := Length(Pattern);
  FHighestBit := UInt64(1) shl (FPatternLength - 1);
  BuildByteMasks;
end;

constructor TMyersSearcher.Create(const Pattern: string; MaxDistance: Integer);
begin
  if Pattern = '' then
    raise EArgumentException.Create('Pattern must not be empty');
  if Length(Pattern) > 64 then
    raise EArgumentOutOfRangeException.Create('Myers string pattern must not exceed 64 UTF-16 code units');
  if (MaxDistance < 0) or (MaxDistance >= Length(Pattern)) then
    raise EArgumentOutOfRangeException.Create('Maximum distance must be between 0 and pattern length - 1');
  inherited Create(Pattern);
  FMaxDistance := MaxDistance;
  FPatternLength := Length(Pattern);
  FHighestBit := UInt64(1) shl (FPatternLength - 1);
  FCharMasks := TDictionary<Char, UInt64>.Create;
  BuildCharMasks;
end;

destructor TMyersSearcher.Destroy;
begin
  FCharMasks.Free;
  inherited;
end;

procedure TMyersSearcher.BuildByteMasks;
var
  I: Integer;
begin
  FillChar(FByteMasks, SizeOf(FByteMasks), 0);
  for I := 0 to FPatternLength - 1 do
    FByteMasks[PatternBytes[I]] := FByteMasks[PatternBytes[I]] or (UInt64(1) shl I);
end;

procedure TMyersSearcher.BuildCharMasks;
var
  I: Integer;
  C: Char;
  Mask: UInt64;
begin
  for I := 1 to FPatternLength do
  begin
    C := TextPattern[I];
    if not FCharMasks.TryGetValue(C, Mask) then
      Mask := 0;
    FCharMasks.AddOrSetValue(C, Mask or (UInt64(1) shl (I - 1)));
  end;
end;

function TMyersSearcher.GetCharMask(C: Char): UInt64;
begin
  if not FCharMasks.TryGetValue(C, Result) then
    Result := 0;
end;

function TMyersSearcher.SearchBytes(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  Start, Remaining: NativeUInt;
  J, MinLength, MaxLength, MaxCount, Score, BestDistance, BestLength: Integer;
  Pv, Mv, Eq, Xv, Xh, Ph, Mh: UInt64;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if TextMode then
    raise EInvalidOpException.Create('Byte search requires a byte pattern');
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit;
  MinLength := FPatternLength - FMaxDistance;
  if MinLength < 1 then
    MinLength := 1;
  MaxLength := FPatternLength + FMaxDistance;
  Start := StartOffset;
  while Start < BufferSize do
  begin
    Remaining := BufferSize - Start;
    if Remaining < NativeUInt(MinLength) then
      Break;
    MaxCount := MaxLength;
    if Remaining < NativeUInt(MaxCount) then
      MaxCount := Integer(Remaining);
    Pv := High(UInt64);
    Mv := 0;
    Score := FPatternLength;
    BestDistance := FMaxDistance + 1;
    BestLength := 0;
    for J := 1 to MaxCount do
    begin
      Eq := FByteMasks[Buffer[Start + NativeUInt(J - 1)]];
      Xv := Eq or Mv;
      Xh := (AddUInt64Wrap(Eq and Pv, Pv) xor Pv) or Eq;
      Ph := Mv or not (Xh or Pv);
      Mh := Pv and Xh;
      if (Ph and FHighestBit) <> 0 then
        Inc(Score)
      else if (Mh and FHighestBit) <> 0 then
        Dec(Score);
      Ph := (Ph shl 1) or UInt64(1);
      Mh := Mh shl 1;
      Pv := Mh or not (Xv or Ph);
      Mv := Ph and Xv;
      if J >= MinLength then
        if (Score < BestDistance) or ((Score = BestDistance) and ((BestLength = 0) or (J < BestLength))) then
        begin
          BestDistance := Score;
          BestLength := J;
        end;
    end;
    if BestDistance <= FMaxDistance then
    begin
      Match.Offset := Int64(Start);
      Match.MatchLength := BestLength;
      Match.PatternIndex := 0;
      Match.Distance := BestDistance;
      Match.MatchUnit := muByte;
      AppendMatch(Result, Match);
      if (MaxMatches > 0) and (Length(Result) >= MaxMatches) then
        Break;
    end;
    Inc(Start);
  end;
end;

function TMyersSearcher.SearchText(const Text: string; StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  Start, Remaining, J, MinLength, MaxLength, MaxCount, Score, BestDistance, BestLength: Integer;
  Pv, Mv, Eq, Xv, Xh, Ph, Mh: UInt64;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if not TextMode then
    raise EInvalidOpException.Create('String search requires a string pattern');
  if (Text = '') or (StartOffset >= NativeUInt(Length(Text))) then
    Exit;
  MinLength := FPatternLength - FMaxDistance;
  if MinLength < 1 then
    MinLength := 1;
  MaxLength := FPatternLength + FMaxDistance;
  Start := Integer(StartOffset) + 1;
  while Start <= Length(Text) do
  begin
    Remaining := Length(Text) - Start + 1;
    if Remaining < MinLength then
      Break;
    MaxCount := MaxLength;
    if Remaining < MaxCount then
      MaxCount := Remaining;
    Pv := High(UInt64);
    Mv := 0;
    Score := FPatternLength;
    BestDistance := FMaxDistance + 1;
    BestLength := 0;
    for J := 1 to MaxCount do
    begin
      Eq := GetCharMask(Text[Start + J - 1]);
      Xv := Eq or Mv;
      Xh := (AddUInt64Wrap(Eq and Pv, Pv) xor Pv) or Eq;
      Ph := Mv or not (Xh or Pv);
      Mh := Pv and Xh;
      if (Ph and FHighestBit) <> 0 then
        Inc(Score)
      else if (Mh and FHighestBit) <> 0 then
        Dec(Score);
      Ph := (Ph shl 1) or UInt64(1);
      Mh := Mh shl 1;
      Pv := Mh or not (Xv or Ph);
      Mv := Ph and Xv;
      if J >= MinLength then
        if (Score < BestDistance) or ((Score = BestDistance) and ((BestLength = 0) or (J < BestLength))) then
        begin
          BestDistance := Score;
          BestLength := J;
        end;
    end;
    if BestDistance <= FMaxDistance then
    begin
      Match.Offset := Start - 1;
      Match.MatchLength := BestLength;
      Match.PatternIndex := 0;
      Match.Distance := BestDistance;
      Match.MatchUnit := muChar;
      AppendMatch(Result, Match);
      if (MaxMatches > 0) and (Length(Result) >= MaxMatches) then
        Break;
    end;
    Inc(Start);
  end;
end;

function TMyersSearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := SearchBytes(Buffer, BufferSize, StartOffset, 1);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TMyersSearcher.CanStopStreamAfterFirst: Boolean;
begin
  Result := False;
end;

function TMyersSearcher.DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
begin
  Result := SearchBytes(Buffer, BufferSize, StartOffset, MaxMatches);
end;

function TMyersSearcher.StreamOverlap: NativeUInt;
begin
  Result := NativeUInt(FPatternLength + FMaxDistance - 1);
end;

function TMyersSearcher.FindFirst(const Text: string; StartOffset: NativeUInt): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := SearchText(Text, StartOffset, 1);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TMyersSearcher.FindAll(const Text: string; StartOffset: NativeUInt): TPatternMatches;
begin
  Result := SearchText(Text, StartOffset, 0);
end;

end.
