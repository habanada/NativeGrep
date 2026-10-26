{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.RabinKarp;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TRabinKarpSearcher = class(TSinglePatternSearcher)
  private
    FPatternHash: UInt64;
    FHighestPower: UInt64;
    procedure BuildPatternHash;
    class function HashAppend(Hash: UInt64; Value: Byte): UInt64; static;
  protected
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; override;
  public
    constructor Create(const Pattern: TBytes); overload;
    constructor Create(const Pattern: string); overload;
  end;

implementation

const
  RK_BASE: UInt64 = 257;
  RK_MODULUS: UInt64 = 1000000007;

constructor TRabinKarpSearcher.Create(const Pattern: TBytes);
begin
  inherited Create(Pattern);
  BuildPatternHash;
end;

constructor TRabinKarpSearcher.Create(const Pattern: string);
begin
  inherited Create(Pattern);
  BuildPatternHash;
end;

class function TRabinKarpSearcher.HashAppend(Hash: UInt64; Value: Byte): UInt64;
begin
  Result := (Hash * RK_BASE + UInt64(Value) + 1) mod RK_MODULUS;
end;

procedure TRabinKarpSearcher.BuildPatternHash;
var
  I: Integer;
begin
  FPatternHash := 0;
  FHighestPower := 1;
  for I := 0 to High(PatternBytes) do
  begin
    FPatternHash := HashAppend(FPatternHash, PatternBytes[I]);
    if I < High(PatternBytes) then
      FHighestPower := (FHighestPower * RK_BASE) mod RK_MODULUS;
  end;
end;

function TRabinKarpSearcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  PatternLength, I, Position: NativeUInt;
  WindowHash, Removed: UInt64;
  Equal: Boolean;
  J: NativeUInt;
begin
  Result := TPatternMatch.NotFound;
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset > BufferSize) or (PatternLength > BufferSize - StartOffset) then
    Exit;
  WindowHash := 0;
  for I := 0 to PatternLength - 1 do
    WindowHash := HashAppend(WindowHash, Buffer[StartOffset + I]);
  Position := StartOffset;
  while True do
  begin
    if WindowHash = FPatternHash then
    begin
      Equal := True;
      J := 0;
      while J < PatternLength do
      begin
        if Buffer[Position + J] <> PatternBytes[J] then
        begin
          Equal := False;
          Break;
        end;
        Inc(J);
      end;
      if Equal then
      begin
        Result.Offset := Position;
        Result.MatchLength := PatternLength;
        Result.PatternIndex := 0;
        Result.Distance := 0;
        Result.MatchUnit := muByte;
        Exit;
      end;
    end;
    if Position >= BufferSize - PatternLength then
      Break;
    Removed := ((UInt64(Buffer[Position]) + 1) * FHighestPower) mod RK_MODULUS;
    if WindowHash < Removed then
      Inc(WindowHash, RK_MODULUS);
    Dec(WindowHash, Removed);
    WindowHash := HashAppend(WindowHash, Buffer[Position + PatternLength]);
    Inc(Position);
  end;
end;

end.
