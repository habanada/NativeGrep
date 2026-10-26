unit NativeGrep.Scanner;

interface

uses
  System.SysUtils, System.Classes, NativeGrep.Types, NativeGrep.Matcher;

type
  TGrepScanTiming = record
    OpenTicks: Int64;
    BufferSetupTicks: Int64;
    BufferAllocations: Integer;
    BinaryRaw: Boolean;
    ReadTicks: Int64;
    MatchTicks: Int64;
    PositionTicks: Int64;
    EnqueueTicks: Int64;
  end;

  TGrepFileScanner = class sealed
  public
    class procedure Scan(const Path: string; Matcher: TGrepMatcher; const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead: Int64; var Timing: TGrepScanTiming; var Buffer: TBytes); static;
    class procedure ScanStream(const SourceName: string; Stream: TStream; Matcher: TGrepMatcher; const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead: Int64; var Timing: TGrepScanTiming; var Buffer: TBytes); static;
  end;

implementation

uses
  NativeGrep.Timing, NativeGrep.Paths, NativePattern.Core;

type
  TTextPosition = record
    Line: Int64;
    Column: Int64;
    Utf8Remaining: Integer;
    BomStage: Integer;
    PreviousCR: Boolean;
    HaveHalf: Boolean;
    HalfByte: Byte;
  end;

function HasByte(Value, RepeatedByte: UInt64): Boolean; inline;
var
  Bits: UInt64;
begin
  Bits := Value xor RepeatedByte;
  Bits := (Bits or (Bits shr 4)) and $0F0F0F0F0F0F0F0F;
  Bits := (Bits or (Bits shr 2)) and $0303030303030303;
  Bits := (Bits or (Bits shr 1)) and $0101010101010101;
  Result := Bits <> $0101010101010101;
end;

function LooksBinaryUtf8(const Buffer: TBytes; Count: Integer): Boolean;
var
  I, Remaining: Integer;
  B, MinNext, MaxNext: Byte;
begin
  Result := False;
  Remaining := 0;
  MinNext := $80;
  MaxNext := $BF;
  for I := 0 to Count - 1 do
  begin
    B := Buffer[I];
    if B = 0 then Exit(True);
    if Remaining > 0 then
    begin
      if (B < MinNext) or (B > MaxNext) then Exit(True);
      Dec(Remaining);
      MinNext := $80;
      MaxNext := $BF;
      Continue;
    end;
    if B < $80 then Continue;
    if (B >= $C2) and (B <= $DF) then Remaining := 1
    else if B = $E0 then
    begin
      Remaining := 2;
      MinNext := $A0;
    end
    else if (B >= $E1) and (B <= $EC) or (B >= $EE) and (B <= $EF) then Remaining := 2
    else if B = $ED then
    begin
      Remaining := 2;
      MaxNext := $9F;
    end
    else if B = $F0 then
    begin
      Remaining := 3;
      MinNext := $90;
    end
    else if (B >= $F1) and (B <= $F3) then Remaining := 3
    else if B = $F4 then
    begin
      Remaining := 3;
      MaxNext := $8F;
    end
    else Exit(True);
  end;
end;

procedure AdvanceCharacter(var Position: TTextPosition; Value: Word; IsBom: Boolean; Width: Integer);
begin
  if IsBom and (Value = $FEFF) then Exit;
  if Value = 13 then
  begin
    Inc(Position.Line);
    Position.Column := 1;
    Position.PreviousCR := True;
  end
  else if Value = 10 then
  begin
    if not Position.PreviousCR then Inc(Position.Line);
    Position.Column := 1;
    Position.PreviousCR := False;
  end
  else
  begin
    Position.PreviousCR := False;
    Inc(Position.Column, Width);
  end;
end;

procedure AdvanceUtf8Byte(var Position: TTextPosition; B: Byte);
begin
  if (B >= $80) and (B <= $BF) and (Position.Utf8Remaining > 0) then
  begin
    Dec(Position.Utf8Remaining);
    Position.PreviousCR := False;
    Exit;
  end;
  Position.Utf8Remaining := 0;
  if (B = 13) or (B = 10) then AdvanceCharacter(Position, B, False, 1)
  else
  begin
    if (B and $E0) = $C0 then Position.Utf8Remaining := 1
    else if (B and $F0) = $E0 then Position.Utf8Remaining := 2
    else if (B and $F8) = $F0 then Position.Utf8Remaining := 3;
    if Position.Utf8Remaining = 3 then AdvanceCharacter(Position, B, False, 2)
    else AdvanceCharacter(Position, B, False, 1);
  end;
end;

procedure AdvanceTextPosition(var Position: TTextPosition; const Buffer: TBytes; StartIndex, EndIndex: Integer; BaseOffset: Int64; Encoding: TGrepEncoding);
var
  I: Integer;
  B: Byte;
  EightBytes, W1, W2, W3: UInt64;
  W: Word;
  FirstAbsolute: Int64;
begin
  I := StartIndex;
  if Encoding <> geUtf8 then
  begin
    while I < EndIndex do
    begin
      B := Buffer[I];
      if not Position.HaveHalf then
      begin
        Position.HalfByte := B;
        Position.HaveHalf := True;
      end
      else
      begin
        if Encoding = geUtf16LE then W := Word(Position.HalfByte) or (Word(B) shl 8)
        else W := (Word(Position.HalfByte) shl 8) or B;
        FirstAbsolute := BaseOffset + I - 1;
        AdvanceCharacter(Position, W, FirstAbsolute = 0, 1);
        Position.HaveHalf := False;
      end;
      Inc(I);
    end;
    Exit;
  end;
  while I < EndIndex do
  begin
    B := Buffer[I];
    if Position.BomStage < 3 then
    begin
      if Position.BomStage = 0 then
      begin
        Position.BomStage := 3;
        if (BaseOffset + I = 0) and (B = $EF) then
        begin
          Position.BomStage := 1;
          Inc(I);
          Continue;
        end;
      end
      else if Position.BomStage = 1 then
      begin
        Position.BomStage := 3;
        if B = $BB then
        begin
          Position.BomStage := 2;
          Inc(I);
          Continue;
        end;
        AdvanceUtf8Byte(Position, $EF);
      end
      else if Position.BomStage = 2 then
      begin
        Position.BomStage := 3;
        if B = $BF then
        begin
          Inc(I);
          Continue;
        end;
        AdvanceUtf8Byte(Position, $EF);
        AdvanceUtf8Byte(Position, $BB);
      end;
    end;
    if (Position.Utf8Remaining = 0) and (I <= EndIndex - 32) then
    begin
      EightBytes := PUInt64(@Buffer[I])^;
      W1 := PUInt64(@Buffer[I + 8])^;
      W2 := PUInt64(@Buffer[I + 16])^;
      W3 := PUInt64(@Buffer[I + 24])^;
      if (((EightBytes or W1 or W2 or W3) and $8080808080808080) = 0) and
        not HasByte(EightBytes, $0D0D0D0D0D0D0D0D) and not HasByte(W1, $0D0D0D0D0D0D0D0D) and
        not HasByte(W2, $0D0D0D0D0D0D0D0D) and not HasByte(W3, $0D0D0D0D0D0D0D0D) and
        not HasByte(EightBytes, $0A0A0A0A0A0A0A0A) and not HasByte(W1, $0A0A0A0A0A0A0A0A) and
        not HasByte(W2, $0A0A0A0A0A0A0A0A) and not HasByte(W3, $0A0A0A0A0A0A0A0A) then
      begin
        Inc(Position.Column, 32);
        Position.PreviousCR := False;
        Inc(I, 32);
        Continue;
      end;
    end;
    if (Position.Utf8Remaining = 0) and (I <= EndIndex - 8) then
    begin
      EightBytes := PUInt64(@Buffer[I])^;
      if ((EightBytes and $8080808080808080) = 0) and not HasByte(EightBytes, $0D0D0D0D0D0D0D0D) and not HasByte(EightBytes, $0A0A0A0A0A0A0A0A) then
      begin
        Inc(Position.Column, 8);
        Position.PreviousCR := False;
        Inc(I, 8);
        Continue;
      end;
    end;
    AdvanceUtf8Byte(Position, B);
    Inc(I);
  end;
end;

class procedure TGrepFileScanner.ScanStream(const SourceName: string; Stream: TStream; Matcher: TGrepMatcher; const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead: Int64; var Timing: TGrepScanTiming; var Buffer: TBytes);
var
  Position: TTextPosition;
  Match: TPatternMatch;
  ActiveMatcher: TGrepMatcher;
  Detected: TGrepEncoding;
  OutMatch: TGrepMatch;
  BaseOffset, Emitted: Int64;
  Stored, ReadCount, ReadSize, Available, EmitLimit, Cursor, LocalOffset, Keep, Index, PatternLen, SampleCount: Integer;
  FinalChunk, TrackText, FirstChunk: Boolean;
  Stamp: Int64;

  procedure Emit(const Offset, LengthBytes, PatternIndex, Distance: Integer);
  begin
    OutMatch := Default(TGrepMatch);
    OutMatch.SourcePath := SourceName;
    OutMatch.ByteOffset := BaseOffset + Offset;
    OutMatch.ByteLength := LengthBytes;
    OutMatch.PatternIndex := PatternIndex;
    OutMatch.Distance := Distance;
    if TrackText then
    begin
      OutMatch.Line := Position.Line;
      OutMatch.Column := Position.Column;
    end;
    if Options.Profile then Stamp := GrepTimestamp;
    try
      OnMatch(OutMatch);
    finally
      if Options.Profile then Inc(Timing.EnqueueTicks, GrepTimestamp - Stamp);
    end;
    Inc(Emitted);
  end;

begin
  TrackText := (Matcher.Mode in [gmLiteralText, gmMultiText, gmFuzzyText]) and
    (Options.TextPositions <> gtpNone) and (Options.BinaryPolicy <> gbRaw);
  Timing.BinaryRaw := (Matcher.Mode in [gmLiteralText, gmMultiText, gmFuzzyText]) and
    (Options.TextPositions <> gtpNone) and (Options.BinaryPolicy = gbRaw);
  FirstChunk := True;
  FinalChunk := False;
  Stamp := 0;
  ActiveMatcher := Matcher;
  if Matcher.RegexPlan <> nil then
  begin
    Matcher.RegexPlan.ScanStream(SourceName, Stream, Options, IsCancelled, OnMatch, BytesRead,
      Timing.ReadTicks, Timing.MatchTicks, Timing.PositionTicks, Timing.EnqueueTicks, Timing.BufferAllocations, Buffer);
    Exit;
  end;
  if Matcher.UnicodePlan <> nil then
  begin
    if Length(Buffer) <> 65536 then
    begin
      if Options.Profile then Stamp := GrepTimestamp;
      try
        SetLength(Buffer, 65536);
        Inc(Timing.BufferAllocations);
      finally
        if Options.Profile then Inc(Timing.BufferSetupTicks, GrepTimestamp - Stamp);
      end;
    end;
    Matcher.UnicodePlan.ScanStream(SourceName, Stream, Options, IsCancelled, OnMatch, BytesRead, Timing.ReadTicks, Buffer);
    Exit;
  end;
  if (Length(Buffer) <> Options.BufferSize + Matcher.WindowLength - 1) then
  begin
    if Options.Profile then Stamp := GrepTimestamp;
    try
      SetLength(Buffer, Options.BufferSize + Matcher.WindowLength - 1);
      Inc(Timing.BufferAllocations);
    finally
      if Options.Profile then Inc(Timing.BufferSetupTicks, GrepTimestamp - Stamp);
    end;
  end;
  Position := Default(TTextPosition);
  Position.Line := 1;
  Position.Column := 1;
  BaseOffset := 0;
  Stored := 0;
  Emitted := 0;
  repeat
    if IsCancelled() then Break;
    if Options.Profile then Stamp := GrepTimestamp;
    try
      ReadSize := Options.BufferSize;
      if ReadSize > Length(Buffer) - Stored then ReadSize := Length(Buffer) - Stored;
      ReadCount := Stream.Read(Buffer[Stored], ReadSize);
    finally
      if Options.Profile then Inc(Timing.ReadTicks, GrepTimestamp - Stamp);
    end;
    Inc(BytesRead, ReadCount);
    Available := Stored + ReadCount;
    if FirstChunk and (Matcher.Encoding = geAuto) and (Available < 3) and (ReadCount > 0) then
    begin
      Stored := Available;
      Continue;
    end;
    if FirstChunk then
    begin
      FirstChunk := False;
      Detected := geUtf8;
      if (Matcher.Encoding = geAuto) and (Available >= 2) then
      begin
        if (Buffer[0] = $FF) and (Buffer[1] = $FE) then Detected := geUtf16LE
        else if (Buffer[0] = $FE) and (Buffer[1] = $FF) then Detected := geUtf16BE;
      end;
      ActiveMatcher := Matcher.ForEncoding(Detected);
      SampleCount := Available;
      if SampleCount > 8192 then SampleCount := 8192;
      if TrackText and (Options.BinaryPolicy = gbAuto) and (ActiveMatcher.Encoding = geUtf8) and
        LooksBinaryUtf8(Buffer, SampleCount) then
      begin
        TrackText := False;
        Timing.BinaryRaw := True;
      end;
    end;
    ActiveMatcher.Normalize(Buffer, 0, Available, BaseOffset);
    FinalChunk := ReadCount = 0;
    if Available = 0 then Break;
    if FinalChunk then EmitLimit := Available
    else EmitLimit := Available - ActiveMatcher.WindowLength + 1;
    if EmitLimit < 0 then EmitLimit := 0;
    Cursor := 0;
    LocalOffset := 0;
    while (LocalOffset < EmitLimit) and not IsCancelled() do
    begin
      if Options.Profile then Stamp := GrepTimestamp;
      try
        Match := ActiveMatcher.FindFirst(Buffer, Available, LocalOffset);
      finally
        if Options.Profile then Inc(Timing.MatchTicks, GrepTimestamp - Stamp);
      end;
      if not Match.Found or (Match.Offset >= EmitLimit) then Break;
      if (Match.Offset < LocalOffset) or (Match.MatchLength = 0) or (UInt64(Match.Offset) + Match.MatchLength > UInt64(Available)) then
        raise EInvalidOpException.Create('NativePattern returned an invalid match');
      if TrackText then
      begin
        if Options.Profile then Stamp := GrepTimestamp;
        AdvanceTextPosition(Position, Buffer, Cursor, Integer(Match.Offset), BaseOffset, ActiveMatcher.Encoding);
        if Options.Profile then Inc(Timing.PositionTicks, GrepTimestamp - Stamp);
      end;
      Cursor := Integer(Match.Offset);
      if ActiveMatcher.ValidTextOffset(BaseOffset + Match.Offset) then
      begin
        if ActiveMatcher.IsMulti then
        begin
          for Index := 0 to ActiveMatcher.MultiCount - 1 do
          begin
            if IsCancelled() then Break;
            if ActiveMatcher.MatchAt(Buffer, Available, Integer(Match.Offset), Index) then
            begin
              PatternLen := ActiveMatcher.PatternLength(Index);
              Emit(Integer(Match.Offset), PatternLen, Index, 0);
              if (Options.MaxMatchesPerFile > 0) and (Emitted >= Options.MaxMatchesPerFile) then Exit;
            end;
          end;
        end
        else
        begin
          Emit(Integer(Match.Offset), Integer(Match.MatchLength), Match.PatternIndex, Match.Distance);
          if (Options.MaxMatchesPerFile > 0) and (Emitted >= Options.MaxMatchesPerFile) then Exit;
        end;
      end;
      LocalOffset := Integer(Match.Offset) + 1;
    end;
    if TrackText then
    begin
      if Options.Profile then Stamp := GrepTimestamp;
      AdvanceTextPosition(Position, Buffer, Cursor, EmitLimit, BaseOffset, ActiveMatcher.Encoding);
      if Options.Profile then Inc(Timing.PositionTicks, GrepTimestamp - Stamp);
    end;
    Keep := Available - EmitLimit;
    if Keep > 0 then Move(Buffer[EmitLimit], Buffer[0], Keep);
    Stored := Keep;
    Inc(BaseOffset, EmitLimit);
  until FinalChunk;
end;

class procedure TGrepFileScanner.Scan(const Path: string; Matcher: TGrepMatcher; const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead: Int64; var Timing: TGrepScanTiming; var Buffer: TBytes);
var
  Stream: TFileStream;
  Stamp: Int64;
begin
  Stamp := 0;
  if Options.Profile then Stamp := GrepTimestamp;
  try
    Stream := TFileStream.Create(GrepWindowsPath(Path), fmOpenRead or fmShareDenyNone);
  finally
    if Options.Profile then Inc(Timing.OpenTicks, GrepTimestamp - Stamp);
  end;
  try
    TGrepFileScanner.ScanStream(Path, Stream, Matcher, Options, IsCancelled, OnMatch, BytesRead, Timing, Buffer);
  finally
    Stream.Free;
  end;
end;

end.
