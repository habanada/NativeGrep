{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.Levenshtein;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TLevenshteinSearcher = class(TSinglePatternSearcher)
  private
    FMaxDistance: Integer;
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
    function FindFirst(const Text: string; StartOffset: NativeUInt = 0): TPatternMatch; overload; override;
    function FindAll(const Text: string; StartOffset: NativeUInt = 0): TPatternMatches; overload; override;
    property MaxDistance: Integer read FMaxDistance;
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

function Min3(A, B, C: Integer): Integer;
begin
  Result := A;
  if B < Result then
    Result := B;
  if C < Result then
    Result := C;
end;

constructor TLevenshteinSearcher.Create(const Pattern: TBytes; MaxDistance: Integer);
begin
  inherited Create(Pattern);
  if (MaxDistance < 0) or (MaxDistance >= Length(PatternBytes)) then
    raise EArgumentOutOfRangeException.Create('MaxDistance must be between 0 and pattern length - 1');
  FMaxDistance := MaxDistance;
end;

constructor TLevenshteinSearcher.Create(const Pattern: string; MaxDistance: Integer);
begin
  inherited Create(Pattern);
  if (MaxDistance < 0) or (MaxDistance >= Length(Pattern)) then
    raise EArgumentOutOfRangeException.Create('MaxDistance must be between 0 and pattern length - 1');
  FMaxDistance := MaxDistance;
end;

function TLevenshteinSearcher.StreamOverlap: NativeUInt;
begin
  Result := NativeUInt(Length(PatternBytes) + FMaxDistance - 1);
end;

function TLevenshteinSearcher.SearchBytes(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  Prev, Curr, Temp: TArray<Integer>;
  Start, Remaining: NativeUInt;
  I, J, M, MinLength, MaxLength, MaxCount, IMin, IMax, Cost, Distance, BestDistance, BestLength, Limit: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if TextMode then
    raise EInvalidOpException.Create('Byte search requires a byte pattern');
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit;
  M := Length(PatternBytes);
  MinLength := M - FMaxDistance;
  if MinLength < 1 then
    MinLength := 1;
  MaxLength := M + FMaxDistance;
  Limit := FMaxDistance + 1;
  SetLength(Prev, M + 1);
  SetLength(Curr, M + 1);
  Start := StartOffset;
  while Start < BufferSize do
  begin
    Remaining := BufferSize - Start;
    if Remaining < NativeUInt(MinLength) then
      Break;
    MaxCount := MaxLength;
    if Remaining < NativeUInt(MaxCount) then
      MaxCount := Integer(Remaining);
    for I := 0 to M do
      if I <= FMaxDistance then
        Prev[I] := I
      else
        Prev[I] := Limit;
    BestDistance := Limit;
    BestLength := 0;
    for J := 1 to MaxCount do
    begin
      for I := 0 to M do
        Curr[I] := Limit;
      if J <= FMaxDistance then
        Curr[0] := J;
      IMin := J - FMaxDistance;
      if IMin < 1 then
        IMin := 1;
      IMax := J + FMaxDistance;
      if IMax > M then
        IMax := M;
      for I := IMin to IMax do
      begin
        if PatternBytes[I - 1] = Buffer[Start + NativeUInt(J - 1)] then
          Cost := 0
        else
          Cost := 1;
        Distance := Min3(Prev[I] + 1, Curr[I - 1] + 1, Prev[I - 1] + Cost);
        if Distance > Limit then
          Distance := Limit;
        Curr[I] := Distance;
      end;
      if J >= MinLength then
      begin
        Distance := Curr[M];
        if (Distance < BestDistance) or ((Distance = BestDistance) and ((BestLength = 0) or (J < BestLength))) then
        begin
          BestDistance := Distance;
          BestLength := J;
        end;
      end;
      Temp := Prev;
      Prev := Curr;
      Curr := Temp;
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

function TLevenshteinSearcher.SearchText(const Text: string; StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  Prev, Curr, Temp: TArray<Integer>;
  Start, Remaining, I, J, M, MinLength, MaxLength, MaxCount, IMin, IMax, Cost, Distance, BestDistance, BestLength, Limit: Integer;
  Match: TPatternMatch;
begin
  SetLength(Result, 0);
  if not TextMode then
    raise EInvalidOpException.Create('String search requires a string pattern');
  if (Text = '') or (StartOffset >= NativeUInt(Length(Text))) then
    Exit;
  M := Length(TextPattern);
  MinLength := M - FMaxDistance;
  if MinLength < 1 then
    MinLength := 1;
  MaxLength := M + FMaxDistance;
  Limit := FMaxDistance + 1;
  SetLength(Prev, M + 1);
  SetLength(Curr, M + 1);
  Start := Integer(StartOffset) + 1;
  while Start <= Length(Text) do
  begin
    Remaining := Length(Text) - Start + 1;
    if Remaining < MinLength then
      Break;
    MaxCount := MaxLength;
    if Remaining < MaxCount then
      MaxCount := Remaining;
    for I := 0 to M do
      if I <= FMaxDistance then
        Prev[I] := I
      else
        Prev[I] := Limit;
    BestDistance := Limit;
    BestLength := 0;
    for J := 1 to MaxCount do
    begin
      for I := 0 to M do
        Curr[I] := Limit;
      if J <= FMaxDistance then
        Curr[0] := J;
      IMin := J - FMaxDistance;
      if IMin < 1 then
        IMin := 1;
      IMax := J + FMaxDistance;
      if IMax > M then
        IMax := M;
      for I := IMin to IMax do
      begin
        if TextPattern[I] = Text[Start + J - 1] then
          Cost := 0
        else
          Cost := 1;
        Distance := Min3(Prev[I] + 1, Curr[I - 1] + 1, Prev[I - 1] + Cost);
        if Distance > Limit then
          Distance := Limit;
        Curr[I] := Distance;
      end;
      if J >= MinLength then
      begin
        Distance := Curr[M];
        if (Distance < BestDistance) or ((Distance = BestDistance) and ((BestLength = 0) or (J < BestLength))) then
        begin
          BestDistance := Distance;
          BestLength := J;
        end;
      end;
      Temp := Prev;
      Prev := Curr;
      Curr := Temp;
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

function TLevenshteinSearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := SearchBytes(Buffer, BufferSize, StartOffset, 1);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TLevenshteinSearcher.CanStopStreamAfterFirst: Boolean;
begin
  Result := False;
end;

function TLevenshteinSearcher.DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
begin
  Result := SearchBytes(Buffer, BufferSize, StartOffset, MaxMatches);
end;

function TLevenshteinSearcher.FindFirst(const Text: string; StartOffset: NativeUInt): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := SearchText(Text, StartOffset, 1);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TLevenshteinSearcher.FindAll(const Text: string; StartOffset: NativeUInt): TPatternMatches;
begin
  Result := SearchText(Text, StartOffset, 0);
end;

end.
