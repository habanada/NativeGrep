{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.TwoWay;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TTwoWaySearcher = class(TSinglePatternSearcher)
  private
    FSuffix: NativeUInt;
    FPeriod: NativeUInt;
    FPeriodic: Boolean;
    procedure BuildFactorization;
    function EqualPatternRanges(LeftOffset, RightOffset, Count: NativeUInt): Boolean;
  protected
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; override;
  public
    constructor Create(const Pattern: TBytes); overload;
    constructor Create(const Pattern: string); overload;
  end;

implementation

function MaxNativeUInt(A, B: NativeUInt): NativeUInt;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

constructor TTwoWaySearcher.Create(const Pattern: TBytes);
begin
  inherited Create(Pattern);
  BuildFactorization;
end;

constructor TTwoWaySearcher.Create(const Pattern: string);
begin
  inherited Create(Pattern);
  BuildFactorization;
end;

function TTwoWaySearcher.EqualPatternRanges(LeftOffset, RightOffset, Count: NativeUInt): Boolean;
var
  I: NativeUInt;
begin
  if Count = 0 then
    Exit(True);
  for I := 0 to Count - 1 do
    if PatternBytes[LeftOffset + I] <> PatternBytes[RightOffset + I] then
      Exit(False);
  Result := True;
end;

procedure TTwoWaySearcher.BuildFactorization;
var
  MaxSuffix, MaxSuffixRev: NativeInt;
  J, K, Period, FirstPeriod, PatternLength: NativeUInt;
  A, B: Byte;
begin
  PatternLength := Length(PatternBytes);
  MaxSuffix := -1;
  J := 0;
  K := 1;
  Period := 1;
  while J + K < PatternLength do
  begin
    A := PatternBytes[J + K];
    B := PatternBytes[NativeUInt(MaxSuffix + NativeInt(K))];
    if A < B then
    begin
      Inc(J, K);
      K := 1;
      Period := NativeUInt(NativeInt(J) - MaxSuffix);
    end
    else if A = B then
    begin
      if K <> Period then
        Inc(K)
      else
      begin
        Inc(J, Period);
        K := 1;
      end;
    end
    else
    begin
      MaxSuffix := NativeInt(J);
      Inc(J);
      K := 1;
      Period := 1;
    end;
  end;
  FirstPeriod := Period;
  MaxSuffixRev := -1;
  J := 0;
  K := 1;
  Period := 1;
  while J + K < PatternLength do
  begin
    A := PatternBytes[J + K];
    B := PatternBytes[NativeUInt(MaxSuffixRev + NativeInt(K))];
    if B < A then
    begin
      Inc(J, K);
      K := 1;
      Period := NativeUInt(NativeInt(J) - MaxSuffixRev);
    end
    else if A = B then
    begin
      if K <> Period then
        Inc(K)
      else
      begin
        Inc(J, Period);
        K := 1;
      end;
    end
    else
    begin
      MaxSuffixRev := NativeInt(J);
      Inc(J);
      K := 1;
      Period := 1;
    end;
  end;
  if MaxSuffixRev < MaxSuffix then
  begin
    FSuffix := NativeUInt(MaxSuffix + 1);
    FPeriod := FirstPeriod;
  end
  else
  begin
    FSuffix := NativeUInt(MaxSuffixRev + 1);
    FPeriod := Period;
  end;
  FPeriodic := (FSuffix = 0) or ((FPeriod + FSuffix <= PatternLength) and EqualPatternRanges(0, FPeriod, FSuffix));
end;

function TTwoWaySearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  PatternLength, Position, I, Memory, Shift: NativeUInt;
  LeftIndex: NativeInt;
begin
  Result := TPatternMatch.NotFound;
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset > BufferSize) or (PatternLength > BufferSize - StartOffset) then
    Exit;
  Position := StartOffset;
  if FPeriodic then
  begin
    Memory := 0;
    while Position <= BufferSize - PatternLength do
    begin
      I := MaxNativeUInt(FSuffix, Memory);
      while (I < PatternLength) and (PatternBytes[I] = Buffer[Position + I]) do
        Inc(I);
      if I >= PatternLength then
      begin
        LeftIndex := NativeInt(FSuffix) - 1;
        while (LeftIndex >= NativeInt(Memory)) and (PatternBytes[LeftIndex] = Buffer[Position + NativeUInt(LeftIndex)]) do
          Dec(LeftIndex);
        if LeftIndex < NativeInt(Memory) then
        begin
          Result.Offset := Position;
          Result.MatchLength := PatternLength;
          Result.PatternIndex := 0;
          Result.Distance := 0;
          Result.MatchUnit := muByte;
          Exit;
        end;
        Shift := FPeriod;
        Memory := PatternLength - FPeriod;
      end
      else
      begin
        Shift := I - FSuffix + 1;
        Memory := 0;
      end;
      if Position > High(NativeUInt) - Shift then
        Exit;
      Inc(Position, Shift);
    end;
  end
  else
  begin
    Shift := MaxNativeUInt(FSuffix, PatternLength - FSuffix) + 1;
    while Position <= BufferSize - PatternLength do
    begin
      I := FSuffix;
      while (I < PatternLength) and (PatternBytes[I] = Buffer[Position + I]) do
        Inc(I);
      if I >= PatternLength then
      begin
        LeftIndex := NativeInt(FSuffix) - 1;
        while (LeftIndex >= 0) and (PatternBytes[LeftIndex] = Buffer[Position + NativeUInt(LeftIndex)]) do
          Dec(LeftIndex);
        if LeftIndex < 0 then
        begin
          Result.Offset := Position;
          Result.MatchLength := PatternLength;
          Result.PatternIndex := 0;
          Result.Distance := 0;
          Result.MatchUnit := muByte;
          Exit;
        end;
        if Position > High(NativeUInt) - Shift then
          Exit;
        Inc(Position, Shift);
      end
      else
      begin
        I := I - FSuffix + 1;
        if Position > High(NativeUInt) - I then
          Exit;
        Inc(Position, I);
      end;
    end;
  end;
end;

end.
