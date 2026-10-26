{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.BoyerMooreHorspool;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TBoyerMooreHorspoolSearcher = class(TSinglePatternSearcher)
  private
    FShift: array[Byte] of NativeUInt;
    procedure BuildShiftTable;
  protected
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; override;
  public
    constructor Create(const Pattern: TBytes); overload;
    constructor Create(const Pattern: string); overload;
  end;

implementation

constructor TBoyerMooreHorspoolSearcher.Create(const Pattern: TBytes);
begin
  inherited Create(Pattern);
  BuildShiftTable;
end;

constructor TBoyerMooreHorspoolSearcher.Create(const Pattern: string);
begin
  inherited Create(Pattern);
  BuildShiftTable;
end;

procedure TBoyerMooreHorspoolSearcher.BuildShiftTable;
var
  I: Integer;
  PatternLength: NativeUInt;
begin
  PatternLength := Length(PatternBytes);
  for I := Low(FShift) to High(FShift) do
    FShift[I] := PatternLength;
  if PatternLength <= 1 then
    Exit;
  for I := 0 to Integer(PatternLength) - 2 do
    FShift[PatternBytes[I]] := PatternLength - NativeUInt(I) - 1;
end;

function TBoyerMooreHorspoolSearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  PatternLength, Position, Step: NativeUInt;
  I: NativeInt;
begin
  Result := TPatternMatch.NotFound;
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset > BufferSize) or (PatternLength > BufferSize - StartOffset) then
    Exit;
  Position := StartOffset;
  while Position <= BufferSize - PatternLength do
  begin
    I := NativeInt(PatternLength) - 1;
    while (I >= 0) and (Buffer[Position + NativeUInt(I)] = PatternBytes[I]) do
      Dec(I);
    if I < 0 then
    begin
      Result.Offset := Position;
      Result.MatchLength := PatternLength;
      Result.PatternIndex := 0;
      Result.Distance := 0;
      Result.MatchUnit := muByte;
      Exit;
    end;
    Step := FShift[Buffer[Position + PatternLength - 1]];
    if Step = 0 then
      Step := 1;
    if Position > High(NativeUInt) - Step then
      Exit;
    Inc(Position, Step);
  end;
end;

end.
