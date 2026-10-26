unit NativeGrep.Unicode;

interface

uses
  System.SysUtils, System.Classes, NativeGrep.Types;

type
  TGrepUnicodeRune = record
    CodePoint: Cardinal;
    FirstByte: Int64;
    LastByte: Int64;
    Line: Int64;
    Column: Int64;
  end;

  TGrepUnicodePlan = class sealed
  private
    FPatterns: TArray<TArray<Cardinal>>;
    FPrefixes: TArray<TArray<Integer>>;
    FStates: TArray<Integer>;
    FLastStart: TArray<Int64>;
    FMaxPattern: Integer;
    FDistance: Integer;
    FFuzzy: Boolean;
    FFold: Boolean;
    FDecompose: Boolean;
    FEncoding: TGrepEncoding;
    class function TransformPattern(const Value: string; Fold, Decompose: Boolean): TArray<Cardinal>; static;
  public
    constructor Create(const Query: TGrepQuery);
    procedure ScanStream(const SourceName: string; Stream: TStream; const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead, ReadTicks: Int64; const Buffer: TBytes);
    property WindowLength: Integer read FMaxPattern;
  end;

implementation

uses
  NativeGrep.UnicodeTables, NativeGrep.Timing;

type
  TGrepUnicodeInput = class
  private
    FStream: TStream;
    FBuffer: TBytes;
    FProfile: Boolean;
    FReadTicks: Int64;
    FAvailable: Integer;
    FIndex: Integer;
    FInitial: array[0..2] of Byte;
    FInitialCount: Integer;
    FInitialIndex: Integer;
    FOffset: Int64;
    FBytesRead: Int64;
    FEncoding: TGrepEncoding;
    FLine: Int64;
    FColumn: Int64;
    FPreviousCR: Boolean;
    function ReadRaw(out Value: Byte): Boolean;
    function RequiredByte: Byte;
  public
    constructor Create(Stream: TStream; Encoding: TGrepEncoding; const Buffer: TBytes; Profile: Boolean);
    function ReadRune(out Rune: TGrepUnicodeRune): Boolean;
    property BytesRead: Int64 read FBytesRead;
    property ReadTicks: Int64 read FReadTicks;
  end;

constructor TGrepUnicodeInput.Create(Stream: TStream; Encoding: TGrepEncoding; const Buffer: TBytes; Profile: Boolean);
var B: Byte; Stamp: Int64; N: Integer;
begin
  inherited Create;
  if Length(Buffer) = 0 then raise EArgumentException.Create('Unicode read buffer must not be empty');
  FStream := Stream;
  FLine := 1;
  FColumn := 1;
  FBuffer := Buffer;
  FProfile := Profile;
  FEncoding := Encoding;
  Stamp := 0;
  while FInitialCount < 3 do
  begin
    if FProfile then Stamp := GrepTimestamp;
    try
      N := FStream.Read(B, 1);
    finally
      if FProfile then Inc(FReadTicks, GrepTimestamp - Stamp);
    end;
    if N = 0 then Break;
    FInitial[FInitialCount] := B;
    Inc(FInitialCount);
    Inc(FBytesRead);
  end;
  if Encoding = geAuto then
  begin
    FEncoding := geUtf8;
    if FInitialCount >= 2 then
    begin
      if (FInitial[0] = $FF) and (FInitial[1] = $FE) then FEncoding := geUtf16LE
      else if (FInitial[0] = $FE) and (FInitial[1] = $FF) then FEncoding := geUtf16BE;
    end;
  end;
  if (FEncoding = geUtf8) and (FInitialCount >= 3) and
    (FInitial[0] = $EF) and (FInitial[1] = $BB) and (FInitial[2] = $BF) then FInitialIndex := 3
  else if (FEncoding = geUtf16LE) and (FInitialCount >= 2) and
    (FInitial[0] = $FF) and (FInitial[1] = $FE) then FInitialIndex := 2
  else if (FEncoding = geUtf16BE) and (FInitialCount >= 2) and
    (FInitial[0] = $FE) and (FInitial[1] = $FF) then FInitialIndex := 2;
  FOffset := FInitialIndex;
end;

function TGrepUnicodeInput.ReadRaw(out Value: Byte): Boolean;
var Stamp: Int64;
begin
  Stamp := 0;
  if FInitialIndex < FInitialCount then
  begin
    Value := FInitial[FInitialIndex];
    Inc(FInitialIndex);
    Inc(FOffset);
    Exit(True);
  end;
  if FIndex = FAvailable then
  begin
    if FProfile then Stamp := GrepTimestamp;
    try
      FAvailable := FStream.Read(FBuffer[0], Length(FBuffer));
    finally
      if FProfile then Inc(FReadTicks, GrepTimestamp - Stamp);
    end;
    Inc(FBytesRead, FAvailable);
    FIndex := 0;
    if FAvailable = 0 then Exit(False);
  end;
  Value := FBuffer[FIndex];
  Inc(FIndex);
  Inc(FOffset);
  Result := True;
end;

function TGrepUnicodeInput.RequiredByte: Byte;
begin
  if not ReadRaw(Result) then raise EEncodingError.Create('Incomplete Unicode character at end of stream');
end;

function TGrepUnicodeInput.ReadRune(out Rune: TGrepUnicodeRune): Boolean;
var B, Next: Byte; Cp, Minimum: Cardinal; Remaining, I: Integer; UnitWord, LowWord: Word;
begin
  Rune := Default(TGrepUnicodeRune);
  Rune.FirstByte := FOffset;
  Result := ReadRaw(B);
  if not Result then Exit;
  if FEncoding = geUtf8 then
  begin
    Cp := B;
    Minimum := 0;
    if B < $80 then Remaining := 0
    else if (B >= $C2) and (B <= $DF) then begin Cp := B and $1F; Remaining := 1; Minimum := $80; end
    else if (B >= $E0) and (B <= $EF) then begin Cp := B and $0F; Remaining := 2; Minimum := $800; end
    else if (B >= $F0) and (B <= $F4) then begin Cp := B and $07; Remaining := 3; Minimum := $10000; end
    else raise EEncodingError.CreateFmt('Invalid UTF-8 byte at offset %d', [Rune.FirstByte]);
    for I := 1 to Remaining do
    begin
      Next := RequiredByte;
      if (Next and $C0) <> $80 then raise EEncodingError.CreateFmt('Invalid UTF-8 continuation at offset %d', [FOffset - 1]);
      Cp := (Cp shl 6) or (Next and $3F);
    end;
    if (Remaining > 0) and (Cp < Minimum) then raise EEncodingError.Create('Overlong UTF-8 sequence');
  end
  else
  begin
    Next := RequiredByte;
    if FEncoding = geUtf16LE then UnitWord := Word(B) or (Word(Next) shl 8)
    else UnitWord := (Word(B) shl 8) or Next;
    Cp := UnitWord;
    if (UnitWord >= $D800) and (UnitWord <= $DBFF) then
    begin
      B := RequiredByte;
      Next := RequiredByte;
      if FEncoding = geUtf16LE then LowWord := Word(B) or (Word(Next) shl 8)
      else LowWord := (Word(B) shl 8) or Next;
      if (LowWord < $DC00) or (LowWord > $DFFF) then raise EEncodingError.Create('Invalid UTF-16 surrogate pair');
      Cp := $10000 + (Cardinal(UnitWord - $D800) shl 10) + Cardinal(LowWord - $DC00);
    end
    else if (UnitWord >= $DC00) and (UnitWord <= $DFFF) then
      raise EEncodingError.Create('Unexpected UTF-16 low surrogate');
  end;
  if (Cp > $10FFFF) or ((Cp >= $D800) and (Cp <= $DFFF)) then raise EEncodingError.Create('Invalid Unicode scalar');
  Rune.CodePoint := Cp;
  Rune.LastByte := FOffset;
  Rune.Line := FLine;
  Rune.Column := FColumn;
  if Cp = 13 then
  begin
    Inc(FLine);
    FColumn := 1;
    FPreviousCR := True;
  end
  else if Cp = 10 then
  begin
    if not FPreviousCR then Inc(FLine);
    FColumn := 1;
    FPreviousCR := False;
  end
  else
  begin
    Inc(FColumn, 1 + Ord(Cp > $FFFF));
    FPreviousCR := False;
  end;
end;

class function TGrepUnicodePlan.TransformPattern(const Value: string; Fold, Decompose: Boolean): TArray<Cardinal>;
var
  I, J, Count, FirstCount: Integer;
  Cp: Cardinal;
  Values, First, Expanded: TArray<Cardinal>;

  procedure Append(var Target: TArray<Cardinal>; var TargetCount: Integer; Scalar: Cardinal);
  begin
    if TargetCount = Length(Target) then SetLength(Target, TargetCount * 2 + 8);
    Target[TargetCount] := Scalar;
    Inc(TargetCount);
  end;

  procedure OrderCanonical(var Target: TArray<Cardinal>; TargetCount: Integer);
  var X, Y, C, Starter: Integer; V: Cardinal;
  begin
    if not Decompose then Exit;
    Starter := 0;
    for X := 0 to TargetCount - 1 do
    begin
      C := GrepUnicodeCombiningClass(Target[X]);
      if C = 0 then Starter := X + 1
      else
      begin
        Y := X;
        while (Y > Starter) and (GrepUnicodeCombiningClass(Target[Y - 1]) > C) do
        begin
          V := Target[Y - 1];
          Target[Y - 1] := Target[Y];
          Target[Y] := V;
          Dec(Y);
        end;
      end;
    end;
  end;

begin
  SetLength(First, 0);
  FirstCount := 0;
  I := 1;
  while I <= Length(Value) do
  begin
    Cp := Ord(Value[I]);
    if (Cp >= $D800) and (Cp <= $DBFF) then
    begin
      if I = Length(Value) then raise EArgumentException.Create('Query has incomplete UTF-16 surrogate');
      if (Ord(Value[I + 1]) < $DC00) or (Ord(Value[I + 1]) > $DFFF) then
        raise EArgumentException.Create('Query has invalid UTF-16 surrogate');
      Cp := $10000 + ((Cp - $D800) shl 10) + Ord(Value[I + 1]) - $DC00;
      Inc(I);
    end
    else if (Cp >= $DC00) and (Cp <= $DFFF) then raise EArgumentException.Create('Query has unexpected UTF-16 low surrogate');
    if Decompose then Expanded := GrepUnicodeExpand(Cp, False, True)
    else begin SetLength(Expanded, 1); Expanded[0] := Cp; end;
    for J := 0 to High(Expanded) do Append(First, FirstCount, Expanded[J]);
    Inc(I);
  end;
  OrderCanonical(First, FirstCount);
  SetLength(Values, 0);
  Count := 0;
  for I := 0 to FirstCount - 1 do
  begin
    if Fold then Expanded := GrepUnicodeExpand(First[I], True, Decompose)
    else begin SetLength(Expanded, 1); Expanded[0] := First[I]; end;
    for J := 0 to High(Expanded) do Append(Values, Count, Expanded[J]);
  end;
  OrderCanonical(Values, Count);
  SetLength(Values, Count);
  Result := Values;
end;

constructor TGrepUnicodePlan.Create(const Query: TGrepQuery);
var I, J, K, N: Integer;
begin
  inherited Create;
  FEncoding := Query.Encoding;
  FFold := Query.UnicodeCaseFold;
  FDecompose := Query.UnicodeNormalizeNfd or FFold;
  FFuzzy := Query.Mode = gmFuzzyText;
  FDistance := Query.MaxDistance;
  if Query.Mode = gmMultiText then
  begin
    SetLength(FPatterns, Length(Query.TextPatterns));
    for I := 0 to High(FPatterns) do FPatterns[I] := TransformPattern(Query.TextPatterns[I], FFold, FDecompose);
  end
  else
  begin
    SetLength(FPatterns, 1);
    FPatterns[0] := TransformPattern(Query.Text, FFold, FDecompose);
  end;
  if FFuzzy and (FDistance > 8) then raise EArgumentOutOfRangeException.Create('Unicode fuzzy distance must be <= 8');
  SetLength(FPrefixes, Length(FPatterns));
  SetLength(FStates, Length(FPatterns));
  SetLength(FLastStart, Length(FPatterns));
  for I := 0 to High(FPatterns) do
  begin
    K := Length(FPatterns[I]);
    if K = 0 then raise EArgumentException.Create('Empty normalized pattern is not allowed');
    if K > FMaxPattern then FMaxPattern := K;
    if FFuzzy and ((K > 256) or (FDistance >= K)) then
      raise EArgumentOutOfRangeException.Create('Unicode fuzzy pattern must have 1..256 codepoints and distance < length');
    if K > 8192 then raise EArgumentOutOfRangeException.Create('Unicode pattern exceeds 8192 codepoints');
    SetLength(FPrefixes[I], K);
    J := 0;
    for N := 1 to K - 1 do
    begin
      while (J > 0) and (FPatterns[I][N] <> FPatterns[I][J]) do J := FPrefixes[I][J - 1];
      if FPatterns[I][N] = FPatterns[I][J] then Inc(J);
      FPrefixes[I][N] := J;
    end;
    FLastStart[I] := -1;
  end;
  if FFuzzy then Inc(FMaxPattern, FDistance);
end;

procedure TGrepUnicodePlan.ScanStream(const SourceName: string; Stream: TStream; const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead, ReadTicks: Int64; const Buffer: TBytes);
var
  Input: TGrepUnicodeInput;
  Rune, Current: TGrepUnicodeRune;
  Segment, Preliminary: TArray<TGrepUnicodeRune>;
  PreliminaryCount: Integer;
  SegmentCount, I, C, RingCount, RingSize, State, MinLen, BestLen, BestDistance, A, B, D: Integer;
  Expanded: TArray<Cardinal>;
  History, Ring: TArray<TGrepUnicodeRune>;
  Previous, Next: TArray<Integer>;
  Seen: Int64;
  Emitted: Int64;
  Stop, FuzzyPending: Boolean;
  PendingFirst, PendingLast: TGrepUnicodeRune;
  PendingDistance, PendingLength: Integer;

  procedure Publish(const StartRune, EndRune: TGrepUnicodeRune; PatternIndex, Distance: Integer);
  var M: TGrepMatch;
  begin
    if Stop or IsCancelled() then Exit;
    if StartRune.FirstByte = FLastStart[PatternIndex] then Exit;
    FLastStart[PatternIndex] := StartRune.FirstByte;
    M := Default(TGrepMatch);
    M.SourcePath := SourceName;
    M.ByteOffset := StartRune.FirstByte;
    M.ByteLength := EndRune.LastByte - StartRune.FirstByte;
    M.PatternIndex := PatternIndex;
    M.Distance := Distance;
    if (Options.TextPositions <> gtpNone) and (Options.BinaryPolicy <> gbRaw) then
    begin
      M.Line := StartRune.Line;
      M.Column := StartRune.Column;
    end;
    OnMatch(M);
    Inc(Emitted);
    if (Options.MaxMatchesPerFile > 0) and (Emitted >= Options.MaxMatchesPerFile) then Stop := True;
  end;

  procedure FlushFuzzy;
  begin
    if FuzzyPending then
    begin
      Publish(PendingFirst, PendingLast, 0, PendingDistance);
      FuzzyPending := False;
    end;
  end;

  procedure EvaluateFuzzy;
  var X, Y, Distance: Integer; First, Last: TGrepUnicodeRune;
  begin
    if FuzzyPending and (PendingFirst.FirstByte < Ring[0].FirstByte) then FlushFuzzy;
    BestDistance := FDistance + 1;
    BestLen := 0;
    for Y := 0 to Length(Previous) - 1 do Previous[Y] := Y;
    MinLen := Length(FPatterns[0]) - FDistance;
    for X := 1 to RingCount do
    begin
      Next[0] := X;
      for Y := 1 to Length(FPatterns[0]) do
      begin
        Distance := Ord(Ring[X - 1].CodePoint <> FPatterns[0][Y - 1]);
        A := Previous[Y] + 1;
        B := Next[Y - 1] + 1;
        D := Previous[Y - 1] + Distance;
        if B < A then A := B;
        if D < A then A := D;
        Next[Y] := A;
      end;
      if (X >= MinLen) and (Next[High(Next)] <= FDistance) and (Next[High(Next)] < BestDistance) then
      begin
        BestDistance := Next[High(Next)];
        BestLen := X;
      end;
      for Y := 0 to High(Previous) do Previous[Y] := Next[Y];
    end;
    if BestLen > 0 then
    begin
      First := Ring[0]; Last := Ring[BestLen - 1];
      for X := 1 to BestLen - 1 do
      begin
        if Ring[X].FirstByte < First.FirstByte then First := Ring[X];
        if Ring[X].LastByte > Last.LastByte then Last := Ring[X];
      end;
      if (not FuzzyPending) or (First.FirstByte <> PendingFirst.FirstByte) then
      begin
        FlushFuzzy;
        PendingFirst := First;
        PendingLast := Last;
        PendingDistance := BestDistance;
        PendingLength := BestLen;
        FuzzyPending := True;
      end
      else if (BestDistance < PendingDistance) or ((BestDistance = PendingDistance) and (BestLen < PendingLength)) then
      begin
        PendingLast := Last;
        PendingDistance := BestDistance;
        PendingLength := BestLen;
      end;
    end;
  end;

  procedure Feed(const Value: TGrepUnicodeRune);
  var X, Y: Integer; First, Last, HistoryRune: TGrepUnicodeRune;
  begin
    if Stop or IsCancelled() then Exit;
    if FFuzzy then
    begin
      Ring[RingCount] := Value;
      Inc(RingCount);
      if RingCount >= RingSize then
      begin
        EvaluateFuzzy;
        if RingCount > 1 then Move(Ring[1], Ring[0], (RingCount - 1) * SizeOf(TGrepUnicodeRune));
        Dec(RingCount);
      end;
      Exit;
    end;
    History[Integer(Seen mod FMaxPattern)] := Value;
    Inc(Seen);
    for X := 0 to High(FPatterns) do
    begin
      State := FStates[X];
      while (State > 0) and (FPatterns[X][State] <> Value.CodePoint) do State := FPrefixes[X][State - 1];
      if FPatterns[X][State] = Value.CodePoint then Inc(State);
      if State = Length(FPatterns[X]) then
      begin
        First := History[Integer((Seen - Length(FPatterns[X])) mod FMaxPattern)];
        Last := Value;
        for Y := 0 to Length(FPatterns[X]) - 1 do
        begin
          HistoryRune := History[Integer((Seen - Length(FPatterns[X]) + Y) mod FMaxPattern)];
          if HistoryRune.FirstByte < First.FirstByte then First := HistoryRune;
          if HistoryRune.LastByte > Last.LastByte then Last := HistoryRune;
        end;
        Publish(First, Last, X, 0);
        State := FPrefixes[X][State - 1];
      end;
      FStates[X] := State;
    end;
  end;

  procedure FlushSegment;
  var X: Integer;
  begin
    for X := 0 to SegmentCount - 1 do Feed(Segment[X]);
    SegmentCount := 0;
  end;

  procedure InsertSorted(var Target: TArray<TGrepUnicodeRune>; var Count: Integer; const Value: TGrepUnicodeRune; ClassValue: Integer);
  var AtIndex, X: Integer;
  begin
    if Count >= 4096 then raise EInvalidOpException.Create('Unicode combining sequence exceeds 4096 scalars');
    if Count = Length(Target) then SetLength(Target, Count * 2);
    AtIndex := Count;
    if ClassValue > 0 then
      while (AtIndex > 0) and (GrepUnicodeCombiningClass(Target[AtIndex - 1].CodePoint) > ClassValue) do Dec(AtIndex);
    for X := Count downto AtIndex + 1 do Target[X] := Target[X - 1];
    Target[AtIndex] := Value;
    Inc(Count);
  end;

  procedure AppendFinal(const Value: TGrepUnicodeRune);
  var ClassValue: Integer;
  begin
    ClassValue := GrepUnicodeCombiningClass(Value.CodePoint);
    if (ClassValue = 0) and (SegmentCount > 0) then FlushSegment;
    if not Stop then InsertSorted(Segment, SegmentCount, Value, ClassValue);
  end;

  procedure FoldPreliminary(const Value: TGrepUnicodeRune);
  var Scalars: TArray<Cardinal>; X: Integer; NewRune: TGrepUnicodeRune;
  begin
    if Stop or IsCancelled() then Exit;
    if Value.CodePoint < 128 then
    begin
      NewRune := Value;
      if FFold and (NewRune.CodePoint >= Ord('A')) and (NewRune.CodePoint <= Ord('Z')) then Inc(NewRune.CodePoint, 32);
      AppendFinal(NewRune);
      Exit;
    end;
    if FFold then Scalars := GrepUnicodeExpand(Value.CodePoint, True, True)
    else begin SetLength(Scalars, 1); Scalars[0] := Value.CodePoint; end;
    for X := 0 to High(Scalars) do
    begin
      NewRune := Value;
      NewRune.CodePoint := Scalars[X];
      AppendFinal(NewRune);
      if Stop or IsCancelled() then Break;
    end;
  end;

  procedure FlushPreliminary;
  var X: Integer;
  begin
    for X := 0 to PreliminaryCount - 1 do FoldPreliminary(Preliminary[X]);
    PreliminaryCount := 0;
  end;

begin
  Input := TGrepUnicodeInput.Create(Stream, FEncoding, Buffer, Options.Profile);
  try
    SetLength(Segment, 16);
    SetLength(History, FMaxPattern);
    RingSize := FMaxPattern;
    if FFuzzy then
    begin
      SetLength(Ring, RingSize);
      SetLength(Previous, Length(FPatterns[0]) + 1);
      SetLength(Next, Length(FPatterns[0]) + 1);
    end;
    for I := 0 to High(FStates) do
    begin
      FStates[I] := 0;
      FLastStart[I] := -1;
    end;
    Seen := 0;
    Emitted := 0;
    RingCount := 0;
    SegmentCount := 0;
    Stop := False;
    FuzzyPending := False;
    PreliminaryCount := 0;
    SetLength(Preliminary, 16);
    while not Stop and not IsCancelled() and Input.ReadRune(Rune) do
    begin
      if not FDecompose then
      begin
        Feed(Rune);
        Continue;
      end;
      if Rune.CodePoint < 128 then
      begin
        if PreliminaryCount > 0 then FlushPreliminary;
        if Stop then Break;
        Preliminary[0] := Rune;
        PreliminaryCount := 1;
        Continue;
      end;
      Expanded := GrepUnicodeExpand(Rune.CodePoint, False, True);
      for I := 0 to High(Expanded) do
      begin
        Current := Rune;
        Current.CodePoint := Expanded[I];
        C := GrepUnicodeCombiningClass(Current.CodePoint);
        if (C = 0) and (PreliminaryCount > 0) then FlushPreliminary;
        if Stop then Break;
        InsertSorted(Preliminary, PreliminaryCount, Current, C);
      end;
    end;
    if not Stop and not IsCancelled() then FlushPreliminary;
    if not Stop and not IsCancelled() then FlushSegment;
    if FFuzzy and not Stop and not IsCancelled() then
      while (RingCount >= Length(FPatterns[0]) - FDistance) and not Stop and not IsCancelled() do
      begin
        EvaluateFuzzy;
        if RingCount > 1 then Move(Ring[1], Ring[0], (RingCount - 1) * SizeOf(TGrepUnicodeRune));
        Dec(RingCount);
      end;
    if FFuzzy and not Stop and not IsCancelled() then FlushFuzzy;
  finally
    Inc(BytesRead, Input.BytesRead);
    Inc(ReadTicks, Input.ReadTicks);
    Input.Free;
  end;
end;

end.
