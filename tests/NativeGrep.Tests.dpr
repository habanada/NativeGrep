program NativeGrepTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  NativeGrep.Types, NativeGrep.Api, NativeGrep.Paths, NativeGrep.Context, NativeGrep.Sort, NativeGrep.UnicodeTables, NativeGrep.Replace.Tests, NativeGrep.Replace.StressTests, NativeGrep.FileMonitor.Tests;

type
  TCollectSink = class(TInterfacedObject, IGrepResultSink)
  private
    FMatches: TList<TGrepMatch>;
    FErrors: TStringList;
    FToken: TGrepCancellationToken;
    FCancelAfter: Integer;
  public
    constructor Create(Token: TGrepCancellationToken = nil; CancelAfter: Integer = 0);
    destructor Destroy; override;
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
    function Keys: TArray<string>;
    property Matches: TList<TGrepMatch> read FMatches;
    property Errors: TStringList read FErrors;
  end;

type
  TThrowSink = class(TInterfacedObject, IGrepResultSink)
  public
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
  end;

  TSlowByteStream = class(TBytesStream)
  public
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

procedure TThrowSink.MatchFound(const Match: TGrepMatch);
begin
  raise EInvalidOpException.Create('Intentional result sink failure');
end;

procedure TThrowSink.ScanError(const SourcePath, ErrorText: string);
begin
  raise EInvalidOpException.Create('Intentional error sink failure');
end;

function TSlowByteStream.Read(var Buffer; Count: Longint): Longint;
begin
  if Count > 1 then Count := 1;
  Result := inherited Read(Buffer, Count);
end;

constructor TCollectSink.Create(Token: TGrepCancellationToken; CancelAfter: Integer);
begin
  inherited Create;
  FMatches := TList<TGrepMatch>.Create;
  FErrors := TStringList.Create;
  FToken := Token;
  FCancelAfter := CancelAfter;
end;

destructor TCollectSink.Destroy;
begin
  FErrors.Free;
  FMatches.Free;
  inherited;
end;

procedure TCollectSink.MatchFound(const Match: TGrepMatch);
begin
  FMatches.Add(Match);
  if (FCancelAfter > 0) and (FMatches.Count >= FCancelAfter) and (FToken <> nil) then FToken.Cancel;
end;

procedure TCollectSink.ScanError(const SourcePath, ErrorText: string);
begin
  FErrors.Add(SourcePath + ': ' + ErrorText);
end;

function TCollectSink.Keys: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FMatches.Count);
  for I := 0 to FMatches.Count - 1 do
    Result[I] := FMatches[I].SourcePath + '|' + IntToStr(FMatches[I].ByteOffset) + '|' + IntToStr(FMatches[I].ByteLength);
  TArray.Sort<string>(Result);
end;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: ' + Name);
end;

procedure CheckEqual(Actual, Expected: Int64; const Name: string);
begin
  if Actual <> Expected then raise Exception.CreateFmt('FAIL: %s actual=%d expected=%d', [Name, Actual, Expected]);
end;

procedure WriteFileBytes(const Path: string; const Data: TBytes);
var
  S: TFileStream;
begin
  S := TFileStream.Create(Path, fmCreate);
  try
    if Length(Data) > 0 then S.WriteBuffer(Data[0], Length(Data));
  finally
    S.Free;
  end;
end;

function NewRequest(const Path: string; Workers: Integer): TGrepRequest;
begin
  Result := Default(TGrepRequest);
  SetLength(Result.Options.Roots, 1);
  Result.Options.Roots[0] := Path;
  Result.Options.MaxWorkers := Workers;
  Result.Options.BufferSize := 4096;
  Result.Options.WorkQueueCapacity := 2;
  Result.Options.ResultQueueCapacity := 3;
  Result.Options.Recursive := True;
  Result.Query.Mode := gmLiteralText;
  Result.Query.Text := 'ABA';
end;

procedure BoundaryTest(const Dir: string);
var
  Req: TGrepRequest;
  Data: TBytes;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  I, J: Integer;
  Expected: array[0..5] of Int64;
begin
  SetLength(Data, 9000);
  for I := 0 to High(Data) do Data[I] := Ord('Z');
  for J := 0 to 2 do
  begin
    case J of
      0: I := 0;
      1: I := 4094;
    else
      I := 8190;
    end;
    Data[I] := Ord('A');
    Data[I + 1] := Ord('B');
    Data[I + 2] := Ord('A');
    Data[I + 3] := Ord('B');
    Data[I + 4] := Ord('A');
  end;
  Expected[0] := 0;
  Expected[1] := 2;
  Expected[2] := 4094;
  Expected[3] := 4096;
  Expected[4] := 8190;
  Expected[5] := 8192;
  WriteFileBytes(Dir + '\boundary.bin', Data);
  Req := NewRequest(Dir + '\boundary.bin', 1);
  Req.Query.Mode := gmLiteralBytes;
  Req.Query.Bytes := TEncoding.ASCII.GetBytes('ABA');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 6, 'boundary match count');
  CheckEqual(Stats.Errors, 0, 'boundary errors');
  for I := 0 to 5 do CheckEqual(S.Matches[I].ByteOffset, Expected[I], 'boundary offset ' + IntToStr(I));
  Sink := nil;
end;

procedure TextPositionTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Data: TBytes;
  Stats: TGrepStatistics;
begin
  Data := TEncoding.UTF8.GetBytes(#$00C4 + #13#10 + 'X' + #$D83D#$DE00 + 'Z');
  WriteFileBytes(Dir + '\unicode.txt', Data);
  Req := NewRequest(Dir + '\unicode.txt', 2);
  Req.Query.Text := 'Z';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'unicode count');
  CheckEqual(S.Matches[0].ByteOffset, 9, 'unicode byte offset');
  CheckEqual(S.Matches[0].Line, 2, 'unicode line');
  CheckEqual(S.Matches[0].Column, 4, 'unicode utf16 column');
  SetLength(Data, 4098);
  FillChar(Data[0], Length(Data), Ord('a'));
  Data[4095] := 13;
  Data[4096] := 10;
  Data[4097] := Ord('B');
  WriteFileBytes(Dir + '\crlf.txt', Data);
  Req := NewRequest(Dir + '\crlf.txt', 1);
  Req.Query.Text := 'B';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'crlf count');
  CheckEqual(S.Matches[0].Line, 2, 'crlf line');
  CheckEqual(S.Matches[0].Column, 1, 'crlf column');
  Sink := nil;
end;

procedure CheckReferenceTextPosition(const Data: TBytes; MatchOffset: Integer; ActualLine, ActualColumn: Int64; const Name: string);
var
  I, LineStart: Integer;
  ExpectedLine, ExpectedColumn: Int64;
begin
  LineStart := 0;
  if (Length(Data) >= 3) and (Data[0] = $EF) and (Data[1] = $BB) and (Data[2] = $BF) then LineStart := 3;
  ExpectedLine := 1;
  for I := LineStart to MatchOffset - 1 do
  begin
    if Data[I] = 13 then
    begin
      Inc(ExpectedLine);
      LineStart := I + 1;
    end
    else if Data[I] = 10 then
    begin
      if (I = 0) or (Data[I - 1] <> 13) then Inc(ExpectedLine);
      LineStart := I + 1;
    end;
  end;
  ExpectedColumn := Length(TEncoding.UTF8.GetString(Data, LineStart, MatchOffset - LineStart)) + 1;
  CheckEqual(ActualLine, ExpectedLine, Name + ' line');
  CheckEqual(ActualColumn, ExpectedColumn, Name + ' column');
end;

procedure TextPositionFastPathTest(const Dir: string);
const
  MatchPositions: array[0..7] of Integer = (3, 4000, 4097, 8189, 8193, 32768, 40965, 49000);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Data: TBytes;
  Stats: TGrepStatistics;
  I: Integer;
begin
  SetLength(Data, 49175);
  for I := 0 to High(Data) do Data[I] := Ord('a');
  Data[0] := $EF;
  Data[1] := $BB;
  Data[2] := $BF;
  Data[4095] := 13;
  Data[4096] := 10;
  Data[8191] := 13;
  Data[8192] := 10;
  Data[12347] := 10;
  Data[24000] := 13;
  Data[20479] := $F0;
  Data[20480] := $9F;
  Data[20481] := $98;
  Data[20482] := $80;
  Data[32765] := $C3;
  Data[32766] := $84;
  Data[40958] := $F0;
  Data[40959] := $9F;
  Data[40960] := $98;
  Data[40961] := $80;
  for I := Low(MatchPositions) to High(MatchPositions) do Data[MatchPositions[I]] := Ord('Z');
  WriteFileBytes(Dir + '\text-fast-path.txt', Data);
  Req := NewRequest(Dir + '\text-fast-path.txt', 1);
  Req.Query.Text := 'Z';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, Length(MatchPositions), 'fast path matches');
  for I := Low(MatchPositions) to High(MatchPositions) do
  begin
    CheckEqual(S.Matches[I].ByteOffset, MatchPositions[I], 'fast path byte offset ' + IntToStr(I));
    CheckReferenceTextPosition(Data, MatchPositions[I], S.Matches[I].Line, S.Matches[I].Column, 'fast path position ' + IntToStr(I));
  end;
  Sink := nil;
  Req.Options.MaxWorkers := 4;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, Length(MatchPositions), 'fast path four worker matches');
  for I := Low(MatchPositions) to High(MatchPositions) do
  begin
    CheckEqual(S.Matches[I].ByteOffset, MatchPositions[I], 'fast path four worker byte offset ' + IntToStr(I));
    CheckReferenceTextPosition(Data, MatchPositions[I], S.Matches[I].Line, S.Matches[I].Column, 'fast path four worker position ' + IntToStr(I));
  end;
  Sink := nil;
end;

procedure MaskedTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
begin
  WriteFileBytes(Dir + '\hex.bin', TEncoding.ASCII.GetBytes('ABCAXCABC'));
  Req := NewRequest(Dir + '\hex.bin', 4);
  Req.Query.Mode := gmMaskedHex;
  Req.Query.HexSignature := '41 ?? 43';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 3, 'masked count');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'masked first');
  CheckEqual(S.Matches[1].ByteOffset, 3, 'masked second');
  CheckEqual(S.Matches[2].ByteOffset, 6, 'masked third');
  Sink := nil;
end;


procedure LongPatternTest(const Dir: string);
var
  Req: TGrepRequest;
  Data, Pattern: TBytes;
  Sink: IGrepResultSink;
  S: TCollectSink;
  Stats: TGrepStatistics;
  I: Integer;
begin
  SetLength(Data, 13000);
  SetLength(Pattern, 6000);
  for I := 0 to High(Data) do Data[I] := Ord('Z');
  for I := 0 to High(Pattern) do
  begin
    Pattern[I] := Ord('A');
    Data[I + 3000] := Ord('A');
  end;
  WriteFileBytes(Dir + '\long-pattern.bin', Data);
  Req := NewRequest(Dir + '\long-pattern.bin', 2);
  Req.Query.Mode := gmLiteralBytes;
  Req.Query.Bytes := Pattern;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'long pattern count');
  CheckEqual(S.Matches[0].ByteOffset, 3000, 'long pattern offset');
  Sink := nil;
end;

procedure BomAndQueueTest(const Dir: string);
var
  Req: TGrepRequest;
  Data: TBytes;
  Sink: IGrepResultSink;
  S: TCollectSink;
  Stats: TGrepStatistics;
  I: Integer;
begin
  SetLength(Data, 7);
  Data[0] := $EF;
  Data[1] := $BB;
  Data[2] := $BF;
  Data[3] := Ord('A');
  Data[4] := 13;
  Data[5] := 10;
  Data[6] := Ord('A');
  WriteFileBytes(Dir + '\bom.txt', Data);
  Req := NewRequest(Dir + '\bom.txt', 1);
  Req.Query.Text := 'A';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 2, 'bom count');
  CheckEqual(S.Matches[0].ByteOffset, 3, 'bom byte offset');
  CheckEqual(S.Matches[0].Line, 1, 'bom line');
  CheckEqual(S.Matches[0].Column, 1, 'bom column');
  CheckEqual(S.Matches[1].Line, 2, 'bom new line');
  CheckEqual(S.Matches[1].Column, 1, 'bom new column');
  SetLength(Data, 32768);
  for I := 0 to High(Data) do Data[I] := Ord('A');
  WriteFileBytes(Dir + '\dense.bin', Data);
  Req := NewRequest(Dir + '\dense.bin', 4);
  Req.Query.Mode := gmLiteralBytes;
  SetLength(Req.Query.Bytes, 1);
  Req.Query.Bytes[0] := Ord('A');
  Req.Options.ResultQueueCapacity := 1;
  Req.Options.MaxResultsTotal := 10;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 10, 'full queue and limit');
  Sink := nil;
end;

procedure ParallelTest(const Dir: string);
var
  Req: TGrepRequest;
  S1, S4: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  K1, K4: TArray<string>;
  I: Integer;
begin
  for I := 0 to 39 do WriteFileBytes(Dir + '\parallel_' + IntToStr(I) + '.dat', TEncoding.ASCII.GetBytes('ABA-ABA'));
  Req := NewRequest(Dir, 1);
  SetLength(Req.Options.Includes, 1);
  Req.Options.Includes[0] := 'parallel_*.dat';
  S1 := TCollectSink.Create;
  Sink := S1;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 80, 'single worker count');
  CheckEqual(Stats.FilesScanned, 40, 'single worker files');
  K1 := S1.Keys;
  Req.Options.MaxWorkers := 4;
  S4 := TCollectSink.Create;
  Sink := S4;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 80, '4 worker count');
  K4 := S4.Keys;
  CheckEqual(Length(K1), Length(K4), 'same count across workers');
  for I := 0 to High(K1) do Check(K1[I] = K4[I], 'same hits across workers ' + IntToStr(I));
  Req.Options.MaxMatchesPerFile := 1;
  S4 := TCollectSink.Create;
  Sink := S4;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 40, 'per-file limit');
  Req.Options.MaxMatchesPerFile := 0;
  Req.Options.MaxResultsTotal := 5;
  S4 := TCollectSink.Create;
  Sink := S4;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 5, 'global limit');
  Sink := nil;
end;

procedure WorkerBufferReuseTest(const Dir: string);
var
  Req: TGrepRequest;
  S1, S4: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  K1, K4: TArray<string>;
  I: Integer;
  Content: string;
begin
  for I := 0 to 59 do
  begin
    case I mod 4 of
      0: Content := 'ABA';
      1: Content := 'AB';
      2: Content := '';
    else
      Content := 'XABA';
    end;
    WriteFileBytes(Dir + '\reuse_' + IntToStr(I) + '.dat', TEncoding.ASCII.GetBytes(Content));
  end;
  Req := NewRequest(Dir, 1);
  Req.Options.Profile := True;
  SetLength(Req.Options.Includes, 1);
  Req.Options.Includes[0] := 'reuse_*.dat';
  S1 := TCollectSink.Create;
  Sink := S1;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.FilesScanned, 60, 'buffer reuse one worker files');
  CheckEqual(Stats.Matches, 30, 'buffer reuse one worker matches');
  CheckEqual(Stats.BufferAllocations, 1, 'buffer reuse one allocation');
  K1 := S1.Keys;
  Sink := nil;
  Req.Options.MaxWorkers := 4;
  S4 := TCollectSink.Create;
  Sink := S4;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.FilesScanned, 60, 'buffer reuse four workers files');
  CheckEqual(Stats.Matches, 30, 'buffer reuse four workers matches');
  Check((Stats.BufferAllocations >= 1) and (Stats.BufferAllocations <= 4), 'buffer reuse four worker allocation bound');
  K4 := S4.Keys;
  CheckEqual(Length(K1), Length(K4), 'buffer reuse parity count');
  for I := 0 to High(K1) do Check(K1[I] = K4[I], 'buffer reuse parity ' + IntToStr(I));
  Sink := nil;
end;

procedure ProfilingTest(const Dir: string);
var
  Req: TGrepRequest;
  Sink: IGrepResultSink;
  S: TCollectSink;
  Plain, Profiled: TGrepStatistics;
begin
  Req := NewRequest(Dir, 4);
  SetLength(Req.Options.Includes, 1);
  Req.Options.Includes[0] := 'parallel_*.dat';
  S := TCollectSink.Create;
  Sink := S;
  Plain := TNativeGrep.Search(Req, Sink);
  Check(not Plain.ProfileEnabled, 'profiling disabled by default');
  CheckEqual(Plain.DiscoveryWallUs, 0, 'no discovery timings without profile');
  CheckEqual(Plain.MatchWorkerUs, 0, 'no matcher timings without profile');
  Sink := nil;
  Req.Options.Profile := True;
  S := TCollectSink.Create;
  Sink := S;
  Profiled := TNativeGrep.Search(Req, Sink);
  Check(Profiled.ProfileEnabled, 'profiling enabled');
  CheckEqual(Profiled.Matches, Plain.Matches, 'profile match parity');
  CheckEqual(Profiled.FilesScanned, Plain.FilesScanned, 'profile file parity');
  CheckEqual(Profiled.BytesScanned, Plain.BytesScanned, 'profile bytes parity');
  CheckEqual(Profiled.Errors, Plain.Errors, 'profile error parity');
  Check(Profiled.DiscoveryWallUs >= 0, 'discovery time nonnegative');
  Check(Profiled.DiscoveryEnqueueUs >= 0, 'discovery enqueue time nonnegative');
  Check(Profiled.DiscoveryWallUs >= Profiled.DiscoveryEnqueueUs, 'discovery enqueue contained in wall time');
  Check(Profiled.CompileWorkerUs >= 0, 'compile time nonnegative');
  Check(Profiled.FileOpenWorkerUs >= 0, 'file open time nonnegative');
  Check(Profiled.BufferSetupWorkerUs >= 0, 'buffer setup time nonnegative');
  Check((Profiled.BufferAllocations >= 1) and (Profiled.BufferAllocations <= Profiled.WorkerCount), 'buffer allocations bounded by worker count');
  Check(Profiled.FileReadWorkerUs >= 0, 'read time nonnegative');
  Check(Profiled.MatchWorkerUs >= 0, 'match time nonnegative');
  Check(Profiled.TextPositionWorkerUs >= 0, 'text position time nonnegative');
  Check(Profiled.ResultEnqueueWorkerUs >= 0, 'enqueue time nonnegative');
  Check(Profiled.FileScanWorkerUs >= 0, 'scan time nonnegative');
  Check(Profiled.WorkQueueWaitWorkerUs >= 0, 'queue wait time nonnegative');
  Check(Profiled.SinkDispatchUs >= 0, 'sink time nonnegative');
  CheckEqual(Profiled.Matches, 80, 'buffer reuse keeps all matches');
  Sink := nil;
  Req := NewRequest(Dir + '\dense.bin', 4);
  Req.Query.Mode := gmLiteralBytes;
  Req.Query.Bytes := TEncoding.ASCII.GetBytes('A');
  Req.Options.ResultQueueCapacity := 1;
  Req.Options.MaxResultsTotal := 10;
  Req.Options.Profile := True;
  S := TCollectSink.Create;
  Sink := S;
  Profiled := TNativeGrep.Search(Req, Sink);
  CheckEqual(Profiled.Matches, 10, 'profile full queue and result limit');
  CheckEqual(Profiled.Errors, 0, 'profile queue errors');
  Sink := nil;
  Req := NewRequest(Dir + '\missing-directory', 2);
  Req.Options.Profile := True;
  S := TCollectSink.Create;
  Sink := S;
  Profiled := TNativeGrep.Search(Req, Sink);
  Check(Profiled.ProfileEnabled, 'profile missing directory enabled');
  CheckEqual(Profiled.Errors, 1, 'profile missing directory errors');
  CheckEqual(S.Errors.Count, 1, 'profile missing directory error event');
  Sink := nil;
end;

procedure CancellationTest(const Dir: string);
var
  Req: TGrepRequest;
  Token: TGrepCancellationToken;
  Cancel: IGrepCancellation;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
begin
  Req := NewRequest(Dir, 4);
  SetLength(Req.Options.Includes, 1);
  Req.Options.Includes[0] := 'parallel_*.dat';
  Token := TGrepCancellationToken.Create;
  Cancel := Token;
  S := TCollectSink.Create(Token, 3);
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink, Cancel);
  CheckEqual(Stats.Matches, 3, 'cancel from sink');
  Sink := nil;
  Cancel := nil;
end;

procedure ErrorTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
begin
  Req := NewRequest(Dir + '\missing-directory', 2);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Errors, 1, 'missing path error');
  CheckEqual(S.Errors.Count, 1, 'missing path event');
  Sink := nil;
end;

procedure MultiPatternTest(const Dir: string);
var
  Req: TGrepRequest;
  Data: TBytes;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  I, J: Integer;
  HasZero, HasTwo: Boolean;
begin
  SetLength(Data, 8200);
  for I := 0 to High(Data) do Data[I] := Ord('x');
  Data[4094] := Ord('A');
  Data[4095] := Ord('B');
  Data[4096] := Ord('A');
  Data[4097] := Ord('B');
  Data[4098] := Ord('A');
  WriteFileBytes(Dir + '\new-multi.dat', Data);
  Req := NewRequest(Dir + '\new-multi.dat', 4);
  Req.Query.Mode := gmMultiText;
  Req.Query.TextPatterns := ['ABA', 'BA', 'ABA'];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 6, 'multi all same-offset matches');
  HasZero := False;
  HasTwo := False;
  for J := 0 to S.Matches.Count - 1 do
  begin
    I := Integer(S.Matches[J].ByteOffset);
    if I = 4094 then
    begin
      if S.Matches[J].PatternIndex = 0 then HasZero := True;
      if S.Matches[J].PatternIndex = 2 then HasTwo := True;
    end;
  end;
  Check(HasZero and HasTwo, 'multi duplicate patterns at same offset');
  Sink := nil;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'memory', Data, Sink);
  CheckEqual(Stats.Matches, 6, 'multi memory parity');
  Sink := nil;
end;

procedure FuzzyTest(const Dir: string);
var
  Req: TGrepRequest;
  Data: TBytes;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  I: Integer;
  HaveExpected: Boolean;
begin
  SetLength(Data, 8500);
  for I := 0 to High(Data) do Data[I] := Ord('X');
  Data[4094] := Ord('A');
  Data[4095] := Ord('B');
  Data[4096] := Ord('X');
  Data[4097] := Ord('D');
  Data[4098] := Ord('E');
  WriteFileBytes(Dir + '\new-fuzzy.dat', Data);
  Req := NewRequest(Dir + '\new-fuzzy.dat', 1);
  Req.Query.Mode := gmFuzzyBytes;
  Req.Query.Bytes := TEncoding.ASCII.GetBytes('ABCDE');
  Req.Query.MaxDistance := 1;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  HaveExpected := False;
  for I := 0 to S.Matches.Count - 1 do
    if (S.Matches[I].ByteOffset = 4094) and (S.Matches[I].Distance = 1) then HaveExpected := True;
  Check(HaveExpected, 'fuzzy crosses chunk with one substitution');
  Sink := nil;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'memory', Data, Sink);
  HaveExpected := False;
  for I := 0 to S.Matches.Count - 1 do
    if (S.Matches[I].ByteOffset = 4094) and (S.Matches[I].Distance = 1) then HaveExpected := True;
  Check(HaveExpected, 'fuzzy bytes parity');
  Sink := nil;
end;

procedure EncodingAndStreamTest(const Dir: string);
var
  Req: TGrepRequest;
  Data: TBytes;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  Stream: TBytesStream;
begin
  Data := [$FF, $FE, $58, $00, $0D, $00, $0A, $00, $3D, $D8, $00, $DE, $5A, $00];
  WriteFileBytes(Dir + '\new-utf16le.dat', Data);
  Req := NewRequest(Dir + '\new-utf16le.dat', 2);
  Req.Query.Encoding := geUtf16LE;
  Req.Query.Text := 'Z';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'UTF16 LE count');
  CheckEqual(S.Matches[0].ByteOffset, 12, 'UTF16 LE byte offset');
  CheckEqual(S.Matches[0].Line, 2, 'UTF16 LE line');
  CheckEqual(S.Matches[0].Column, 3, 'UTF16 LE column');
  Sink := nil;
  Data := [$FE, $FF, $00, $58, $00, $0D, $00, $0A, $D8, $3D, $DE, $00, $00, $5A];
  Req.Query.Encoding := geUtf16BE;
  Stream := TBytesStream.Create(Data);
  try
    S := TCollectSink.Create;
    Sink := S;
    Stats := TNativeGrep.SearchStream(Req, 'utf16-be-stream', Stream, Sink);
    CheckEqual(Stats.Matches, 1, 'UTF16 BE stream count');
    CheckEqual(S.Matches[0].ByteOffset, 12, 'UTF16 BE offset');
    CheckEqual(S.Matches[0].Line, 2, 'UTF16 BE line');
    CheckEqual(S.Matches[0].Column, 3, 'UTF16 BE column');
    CheckEqual(Stream.Position, Length(Data), 'stream position after search');
    Sink := nil;
  finally
    Stream.Free;
  end;
  Data := [$EF, $BB, $BF, $41];
  Req.Query.Encoding := geUtf8;
  Req.Query.Text := 'A';
  Stream := TSlowByteStream.Create(Data);
  try
    S := TCollectSink.Create;
    Sink := S;
    Stats := TNativeGrep.SearchStream(Req, 'one-byte-stream', Stream, Sink);
    CheckEqual(Stats.Matches, 1, 'slow stream BOM match');
    CheckEqual(S.Matches[0].ByteOffset, 3, 'slow stream BOM byte offset');
    CheckEqual(S.Matches[0].Column, 1, 'slow stream BOM column');
    Sink := nil;
  finally
    Stream.Free;
  end;
  Req.Query.CaseInsensitiveAscii := True;
  Req.Query.Text := 'AbC';
  Data := TEncoding.UTF8.GetBytes('abc ABC');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'ascii-fold', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'ASCII-insensitive memory');
  CheckEqual(S.Matches[1].ByteOffset, 4, 'ASCII-insensitive second offset');
  Sink := nil;
  Req.Query.Encoding := geUtf16LE;
  Req.Query.Text := #$0141;
  Data := [$41, $01];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'utf16-nonascii', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'UTF16 nonascii preserved during ASCII folding');
  Sink := nil;
end;

procedure ScanPolicyTest(const Dir: string);
var
  Req: TGrepRequest;
  Data: TBytes;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  I: Integer;
begin
  Data := TEncoding.UTF8.GetBytes('head'#13#10'ABA-ABA'#10'ABA');
  Req := NewRequest(Dir + '\scanpolicy-text.txt', 4);
  Req.Options.Profile := True;
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 3, 'text policy match count');
  CheckEqual(S.Matches[0].ByteOffset, 6, 'text policy first byte');
  CheckEqual(S.Matches[1].ByteOffset, 10, 'text policy second byte');
  CheckEqual(S.Matches[2].ByteOffset, 14, 'text policy third byte');
  CheckEqual(S.Matches[0].Line, 2, 'text policy first line');
  CheckEqual(S.Matches[0].Column, 1, 'text policy first column');
  CheckEqual(S.Matches[1].Column, 5, 'text policy second column');
  CheckEqual(S.Matches[2].Line, 3, 'text policy third line');
  CheckEqual(S.Matches[2].Column, 1, 'text policy third column');
  CheckEqual(Stats.BinaryRawSources, 0, 'text policy not binary');
  Sink := nil;
  Req.Options.TextPositions := gtpNone;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 3, 'no position match parity');
  CheckEqual(Stats.TextPositionWorkerUs, 0, 'no position time zero');
  CheckEqual(Stats.BinaryRawSources, 0, 'no position raw source counter');
  for I := 0 to S.Matches.Count - 1 do
  begin
    CheckEqual(S.Matches[I].ByteOffset, 6 + I * 4, 'no position byte offset ' + IntToStr(I));
    CheckEqual(Int64(S.Matches[I].ByteLength), 3, 'no position match length');
    CheckEqual(S.Matches[I].Line, 0, 'no position line');
    CheckEqual(S.Matches[I].Column, 0, 'no position column');
  end;
  Sink := nil;
  Req.Options.TextPositions := gtpAuto;
  Req.Options.BinaryPolicy := gbRaw;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 3, 'forced raw match parity');
  CheckEqual(Stats.BinaryRawSources, 1, 'forced raw count');
  CheckEqual(Stats.TextPositionWorkerUs, 0, 'forced raw skips positions');
  CheckEqual(S.Matches[0].Line, 0, 'forced raw no line');
  Sink := nil;
  Data := TEncoding.ASCII.GetBytes('Q'#0'ABA'#13#10'ABA');
  Req := NewRequest(Dir + '\scanpolicy-binary.dat', 1);
  Req.Options.Profile := True;
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 2, 'binary auto preserves matches');
  CheckEqual(Stats.BinaryRawSources, 1, 'binary auto detected');
  CheckEqual(Stats.TextPositionWorkerUs, 0, 'binary auto skips positions');
  CheckEqual(S.Matches[0].ByteOffset, 2, 'binary auto first byte');
  CheckEqual(S.Matches[1].ByteOffset, 7, 'binary auto second byte');
  CheckEqual(S.Matches[0].Line, 0, 'binary auto no line');
  Sink := nil;
  Req.Options.BinaryPolicy := gbText;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 2, 'forced text match parity');
  CheckEqual(Stats.BinaryRawSources, 0, 'forced text not binary');
  CheckEqual(S.Matches[0].Line, 1, 'forced text first line');
  CheckEqual(S.Matches[0].Column, 3, 'forced text first column');
  CheckEqual(S.Matches[1].Line, 2, 'forced text second line');
  CheckEqual(S.Matches[1].Column, 1, 'forced text second column');
  Sink := nil;
  Req.Options.BinaryPolicy := gbAuto;
  Data := [$FF, Ord('A'), Ord('B'), Ord('A')];
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'invalid utf8 match preserved');
  CheckEqual(Stats.BinaryRawSources, 1, 'invalid utf8 detected');
  CheckEqual(S.Matches[0].ByteOffset, 1, 'invalid utf8 byte offset');
  CheckEqual(S.Matches[0].Column, 0, 'invalid utf8 no column');
  Sink := nil;
  Data := TEncoding.UTF8.GetBytes(#$D83D#$DE00 + #10 + 'ABA');
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'unicode text match');
  CheckEqual(Stats.BinaryRawSources, 0, 'unicode text not binary');
  CheckEqual(S.Matches[0].ByteOffset, 5, 'unicode text byte offset');
  CheckEqual(S.Matches[0].Line, 2, 'unicode text line');
  CheckEqual(S.Matches[0].Column, 1, 'unicode text column');
  Sink := nil;
  Data := [$FF, $FE, $41, $00, $0D, $00, $0A, $00, $41, $00];
  Req.Query.Encoding := geUtf16LE;
  Req.Query.Text := 'A';
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 2, 'utf16 detection excluded');
  CheckEqual(Stats.BinaryRawSources, 0, 'utf16 not binary');
  CheckEqual(S.Matches[0].ByteOffset, 2, 'utf16 first match');
  CheckEqual(S.Matches[0].Line, 1, 'utf16 first line');
  CheckEqual(S.Matches[0].Column, 1, 'utf16 first column');
  CheckEqual(S.Matches[1].ByteOffset, 8, 'utf16 second match');
  CheckEqual(S.Matches[1].Line, 2, 'utf16 second line');
  CheckEqual(S.Matches[1].Column, 1, 'utf16 second column');
  Sink := nil;
end;

procedure AutoEncodingTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  Stream: TSlowByteStream;
  Data: TBytes;
begin
  Req := NewRequest(Dir + '\auto-encoding.txt', 2);
  Req.Query.Encoding := geAuto;
  Req.Query.Text := 'Z';
  Data := [$EF, $BB, $BF, $41, $0D, $0A, $5A];
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'auto utf8 count');
  CheckEqual(S.Matches[0].ByteOffset, 6, 'auto utf8 offset');
  CheckEqual(S.Matches[0].Line, 2, 'auto utf8 line');
  CheckEqual(S.Matches[0].Column, 1, 'auto utf8 column');
  Sink := nil;
  Data := [$FF, $FE, $41, $00, $0D, $00, $0A, $00, $5A, $00];
  WriteFileBytes(Req.Options.Roots[0], Data);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 1, 'auto utf16le count');
  CheckEqual(S.Matches[0].ByteOffset, 8, 'auto utf16le offset');
  CheckEqual(S.Matches[0].Line, 2, 'auto utf16le line');
  CheckEqual(S.Matches[0].Column, 1, 'auto utf16le column');
  Sink := nil;
  Data := [$FE, $FF, $00, $41, $00, $0D, $00, $0A, $00, $5A];
  Stream := TSlowByteStream.Create(Data);
  try
    S := TCollectSink.Create;
    Sink := S;
    Stats := TNativeGrep.SearchStream(Req, 'auto-be-slow', Stream, Sink);
    CheckEqual(Stats.Matches, 1, 'auto utf16be slow count');
    CheckEqual(S.Matches[0].ByteOffset, 8, 'auto utf16be slow offset');
    CheckEqual(S.Matches[0].Line, 2, 'auto utf16be slow line');
    CheckEqual(S.Matches[0].Column, 1, 'auto utf16be slow column');
    Sink := nil;
  finally
    Stream.Free;
  end;
  Data := [$00, $5A, $00, $41];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'auto-no-bom', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'auto no bom utf8 single byte match');
  CheckEqual(S.Matches[0].ByteOffset, 1, 'auto no bom utf8 single byte offset');
  CheckEqual(Int64(S.Matches[0].ByteLength), 1, 'auto no bom utf8 single byte length');
  CheckEqual(Stats.BinaryRawSources, 1, 'auto no bom binary classification');
  Sink := nil;
  Req.Query.Text := 'ZA';
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'auto-no-bom-pair', Data, Sink);
  CheckEqual(Stats.Matches, 0, 'auto no bom defaults to utf8 not utf16be');
  Sink := nil;
  Req.Query.Encoding := geUtf16BE;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'explicit-utf16be-no-bom', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'explicit utf16be without bom count');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'explicit utf16be without bom offset');
  CheckEqual(Int64(S.Matches[0].ByteLength), 4, 'explicit utf16be without bom length');
  Sink := nil;
  Req.Query.Encoding := geAuto;
  Data := [$5A, $41];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'utf8-no-bom-pair', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'utf8 no bom pair count');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'utf8 no bom pair offset');
  CheckEqual(Int64(S.Matches[0].ByteLength), 2, 'utf8 no bom pair length');
  Sink := nil;
end;

procedure AutoMultiEncodingTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  Data: TBytes;
  Root: string;
begin
  Root := Dir + '\auto-mixed';
  ForceDirectories(Root);
  WriteFileBytes(Root + '\utf8.txt', [$EF, $BB, $BF, $41, $42, $41]);
  WriteFileBytes(Root + '\utf16le.txt', [$FF, $FE, $41, $00, $42, $00, $41, $00]);
  WriteFileBytes(Root + '\utf16be.txt', [$FE, $FF, $00, $41, $00, $42, $00, $41]);
  Req := NewRequest(Root, 4);
  Req.Query.Mode := gmMultiText;
  Req.Query.TextPatterns := ['AB', 'ABA'];
  Req.Query.Encoding := geAuto;
  Req.Options.Includes := ['*.txt'];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.FilesScanned, 3, 'auto multi files');
  CheckEqual(Stats.Matches, 6, 'auto multi same-offset matches');
  CheckEqual(Stats.Errors, 0, 'auto multi errors');
  Sink := nil;
end;
procedure RelativeGlobTest(const Dir: string);
var
  Root: string;
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  Data: TBytes;
begin
  Root := Dir + '\relglob';
  ForceDirectories(Root + '\src');
  ForceDirectories(Root + '\bin');
  ForceDirectories(Root + '\sub\src');
  Data := TEncoding.UTF8.GetBytes('ABA');
  WriteFileBytes(Root + '\src\one.pas', Data);
  WriteFileBytes(Root + '\bin\two.pas', Data);
  WriteFileBytes(Root + '\sub\src\three.pas', Data);
  WriteFileBytes(Root + '\four.txt', Data);
  Req := NewRequest(Root, 4);
  Req.Options.Includes := ['**\*.pas'];
  Req.Options.Excludes := ['**\bin\**'];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 2, 'path-glob matches');
  CheckEqual(Stats.FilesScanned, 2, 'path-glob scanned');
  CheckEqual(Stats.Errors, 0, 'path-glob errors');
  Sink := nil;
  Req.Options.Includes := ['*.pas'];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 2, 'filename globs backwards compatible');
  Sink := nil;
end;

procedure WindowsPathTest;
var
  Path: string;
begin
  Check(GrepWindowsPath('C:\short\file.txt') = 'C:\short\file.txt', 'short path unchanged');
  Path := 'C:\' + StringOfChar('x', 275) + '\file.txt';
  Check(GrepWindowsPath(Path) = '\\?\' + Path, 'long drive path prefix');
  Path := '\\server\share\' + StringOfChar('y', 275) + '\file.txt';
  Check(GrepWindowsPath(Path) = '\\?\UNC\' + Copy(Path, 3, MaxInt), 'long UNC path prefix');
end;

procedure ContextReadTest(const Dir: string);
var
  M: TGrepMatch;
  Lines: TArray<TGrepContextLine>;
  Data: TBytes;
  TextValue: string;
begin
  TextValue := 'alpha'#13#10'beta TODO gamma'#10'omega'#13'tail';
  WriteFileBytes(Dir + '\context-utf8.txt', TEncoding.UTF8.GetBytes(TextValue));
  M := Default(TGrepMatch);
  M.SourcePath := Dir + '\context-utf8.txt';
  M.ByteOffset := 12;
  M.Line := 2;
  Lines := TGrepContextReader.ReadFile(M, geAuto, 1, 1, 512);
  CheckEqual(Length(Lines), 3, 'context UTF8 line count');
  Check(Lines[0].Text = 'alpha', 'context UTF8 before');
  Check(Lines[1].Text = 'beta TODO gamma', 'context UTF8 matched line');
  Check(Lines[2].Text = 'omega', 'context UTF8 after');
  CheckEqual(Lines[0].Line, 1, 'context UTF8 first line');
  Check(Lines[1].IsMatch, 'context UTF8 flag');
  M.ByteOffset := 6;
  M.Line := 2;
  Lines := TGrepContextReader.ReadFile(M, geAuto, 1, 1, 512);
  Check(Lines[1].Text = 'beta TODO gamma', 'context CRLF LF belongs to next line');
  Data := [$FF, $FE, $61, $00, $0D, $00, $0A, $00, $42, $00, $0A, $00, $43, $00];
  WriteFileBytes(Dir + '\context-utf16.txt', Data);
  M.SourcePath := Dir + '\context-utf16.txt';
  M.ByteOffset := 8;
  M.Line := 2;
  Lines := TGrepContextReader.ReadFile(M, geAuto, 1, 1, 512);
  CheckEqual(Length(Lines), 3, 'context UTF16 line count');
  Check(Lines[0].Text = 'a', 'context UTF16 before');
  Check(Lines[1].Text = 'B', 'context UTF16 match');
  Check(Lines[2].Text = 'C', 'context UTF16 after');
  Data := [$FE, $FF, $00, $61, $00, $0D, $00, $0A, $00, $42, $00, $0A, $00, $43];
  WriteFileBytes(Dir + '\context-utf16be.txt', Data);
  M.SourcePath := Dir + '\context-utf16be.txt';
  M.ByteOffset := 8;
  Lines := TGrepContextReader.ReadFile(M, geAuto, 1, 1, 512);
  CheckEqual(Length(Lines), 3, 'context UTF16BE line count');
  Check(Lines[1].Text = 'B', 'context UTF16BE match');
  TextValue := StringOfChar('x', 6000) + 'TODO' + StringOfChar('y', 5000);
  WriteFileBytes(Dir + '\context-long.txt', TEncoding.UTF8.GetBytes(TextValue));
  M.SourcePath := Dir + '\context-long.txt';
  M.ByteOffset := 6000;
  M.Line := 1;
  Lines := TGrepContextReader.ReadFile(M, geAuto, 0, 0, 256);
  CheckEqual(Length(Lines), 1, 'context long line count');
  Check(Pos('TODO', Lines[0].Text) > 0, 'context long line keeps match');
  Check(Lines[0].Truncated, 'context long line truncation');
end;

procedure UnicodeCancellationTest(const Dir: string);
var
  Req: TGrepRequest;
  Token: TGrepCancellationToken;
  Cancellation: IGrepCancellation;
  Sink: IGrepResultSink;
  S: TCollectSink;
  Stats: TGrepStatistics;
  Data: TBytes;
begin
  Req := NewRequest(Dir, 1);
  Req.Query.Text := 'ss';
  Req.Query.UnicodeCaseFold := True;
  Data := TEncoding.UTF8.GetBytes(StringOfChar('ß', 256));
  Token := TGrepCancellationToken.Create;
  Cancellation := Token;
  S := TCollectSink.Create(Token, 1);
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'unicode-cancel', Data, Sink, Cancellation);
  CheckEqual(Stats.Matches, 1, 'Unicode cancellation match limit');
  Check(Cancellation.IsCancellationRequested, 'Unicode cancellation token set');
end;

procedure UnicodeErrorContractTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Data: TBytes;
  Raised: Boolean;
begin
  Req := NewRequest(Dir, 1);
  Req.Query.Text := 'AB';
  Req.Query.UnicodeCaseFold := True;
  Data := [$41, $C0, $42];
  S := TCollectSink.Create;
  Sink := S;
  Raised := False;
  try
    TNativeGrep.SearchBytes(Req, 'invalid-utf8', Data, Sink);
  except
    on E: EEncodingError do Raised := True;
  end;
  Check(Raised, 'Unicode strict UTF8 failure');
  Req.Query.CaseInsensitiveAscii := True;
  Raised := False;
  try
    TNativeGrep.SearchBytes(Req, 'invalid-policy', Data, Sink);
  except
    on E: EArgumentException do Raised := True;
  end;
  Check(Raised, 'Unicode and ASCII casefold conflicting');
end;

procedure UnicodeWorkerTest(const Dir: string);
var
  Root: string;
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  SingleKeys, ManyKeys: TArray<string>;
  Stats: TGrepStatistics;
  Data: TBytes;
  I: Integer;
begin
  Root := Dir + '\unicode-worker';
  ForceDirectories(Root);
  WriteFileBytes(Root + '\utf8.txt', TEncoding.UTF8.GetBytes('Straße STRASSE'));
  Data := [$FF, $FE, $53, 0, $54, 0, $52, 0, $41, 0, $53, 0, $53, 0, $45, 0];
  WriteFileBytes(Root + '\utf16le.txt', Data);
  Data := [$FE, $FF, 0, $53, 0, $54, 0, $52, 0, $41, 0, $53, 0, $53, 0, $45];
  WriteFileBytes(Root + '\utf16be.txt', Data);
  Req := NewRequest(Root, 1);
  Req.Query.Text := 'straße';
  Req.Query.Encoding := geAuto;
  Req.Query.UnicodeCaseFold := True;
  Req.Options.Includes := ['*.txt'];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 4, 'Unicode worker single count');
  CheckEqual(Stats.Errors, 0, 'Unicode worker single errors');
  SingleKeys := S.Keys;
  Sink := nil;
  Req.Options.MaxWorkers := 4;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.Search(Req, Sink);
  CheckEqual(Stats.Matches, 4, 'Unicode worker parallel count');
  CheckEqual(Stats.Errors, 0, 'Unicode worker parallel errors');
  ManyKeys := S.Keys;
  CheckEqual(Length(SingleKeys), Length(ManyKeys), 'Unicode worker key lengths');
  for I := 0 to High(SingleKeys) do Check(SingleKeys[I] = ManyKeys[I], 'Unicode worker deterministic content');
end;

procedure UnicodeNormalizationTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Data: TBytes;
  Stats: TGrepStatistics;
  Stream: TSlowByteStream;
  Scalars: TArray<Cardinal>;
begin
  Req := NewRequest(Dir, 1);
  Req.Query.Encoding := geUtf8;
  Req.Query.Text := 'STRASSE';
  Req.Query.UnicodeCaseFold := True;
  Data := TEncoding.UTF8.GetBytes('Straße STRASSE');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'fold', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'Unicode folding count');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode folded first offset');
  CheckEqual(S.Matches[0].ByteLength, 7, 'Unicode folded sharp s maps to two bytes');
  CheckEqual(S.Matches[1].ByteOffset, 8, 'Unicode folded second offset');
  Sink := nil;
  Req.Query.UnicodeCaseFold := False;
  Req.Query.UnicodeNormalizeNfd := True;
  Req.Query.Text := 'café';
  Data := TEncoding.UTF8.GetBytes('café cafe' + #$0301);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'decomposed', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'Unicode NFC/NFD equivalent count');
  CheckEqual(S.Matches[0].ByteLength, 5, 'Unicode composed byte length');
  CheckEqual(S.Matches[1].ByteOffset, 6, 'Unicode decomposed byte offset');
  CheckEqual(S.Matches[1].ByteLength, 6, 'Unicode decomposed byte length');
  Sink := nil;
  Req.Query.UnicodeNormalizeNfd := False;
  Req.Query.UnicodeCaseFold := True;
  Scalars := GrepUnicodeExpand($03A3, True, True);
  CheckEqual(Length(Scalars), 1, 'Unicode uppercase sigma fold length');
  CheckEqual(Scalars[0], $03C3, 'Unicode uppercase sigma fold scalar');
  Scalars := GrepUnicodeExpand($03C2, True, True);
  CheckEqual(Length(Scalars), 1, 'Unicode final sigma fold length');
  CheckEqual(Scalars[0], $03C3, 'Unicode final sigma fold scalar');
  Scalars := GrepUnicodeExpand($03C3, True, True);
  CheckEqual(Length(Scalars), 1, 'Unicode lowercase sigma fold length');
  CheckEqual(Scalars[0], $03C3, 'Unicode lowercase sigma fold scalar');
  Req.Query.Text := #$03C3;
  Data := [$CE, $A3];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'sigma-upper-only', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode uppercase sigma isolated');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode uppercase sigma isolated offset');
  Sink := nil;
  Data := [$CF, $82];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'sigma-final-only', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode final sigma isolated');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode final sigma isolated offset');
  Sink := nil;
  Data := [$CF, $83];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'sigma-lower-only', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode lowercase sigma isolated');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode lowercase sigma isolated offset');
  Sink := nil;
  Data := [$CE, $A3, $20, $CF, $82, $20, $CF, $83];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'sigma', Data, Sink);
  CheckEqual(Stats.Matches, 3, 'Unicode Greek sigma folding');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode uppercase sigma byte offset');
  CheckEqual(S.Matches[1].ByteOffset, 3, 'Unicode final sigma byte offset');
  CheckEqual(S.Matches[2].ByteOffset, 6, 'Unicode lowercase sigma byte offset');
  CheckEqual(S.Matches[0].ByteLength, 2, 'Unicode uppercase sigma byte length');
  CheckEqual(S.Matches[1].ByteLength, 2, 'Unicode final sigma byte length');
  CheckEqual(S.Matches[2].ByteLength, 2, 'Unicode lowercase sigma byte length');
  Sink := nil;
  Data := [$CE, $A3, $CF, $82, $CF, $83];
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'sigma-adjacent', Data, Sink);
  CheckEqual(Stats.Matches, 3, 'Unicode adjacent sigma folding');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode adjacent uppercase sigma offset');
  CheckEqual(S.Matches[1].ByteOffset, 2, 'Unicode adjacent final sigma offset');
  CheckEqual(S.Matches[2].ByteOffset, 4, 'Unicode adjacent lowercase sigma offset');
  Sink := nil;
  Req.Query.Text := 'a' + #$0315 + #$0300;
  Data := TEncoding.UTF8.GetBytes('a' + #$0300 + #$0315);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'reordered-marks', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode NFD canonical combining order');
  CheckEqual(S.Matches[0].ByteLength, 5, 'Unicode canonical source span');
  Sink := nil;
  Req.Query.Encoding := geAuto;
  Req.Query.Text := 'straße';
  Data := [$FF, $FE, $53, 0, $54, 0, $52, 0, $41, 0, $53, 0, $53, 0, $45, 0];
  Stream := TSlowByteStream.Create(Data);
  try
    S := TCollectSink.Create;
    Sink := S;
    Stats := TNativeGrep.SearchStream(Req, 'utf16le-slow', Stream, Sink);
    CheckEqual(Stats.Matches, 1, 'Unicode UTF16LE auto slow stream');
    CheckEqual(S.Matches[0].ByteOffset, 2, 'Unicode UTF16LE BOM offset');
    CheckEqual(S.Matches[0].ByteLength, 14, 'Unicode UTF16LE match size');
  finally
    Stream.Free;
  end;
  Sink := nil;
  Req.Query.Encoding := geUtf8;
  Req.Query.Text := #$D83D#$DE00;
  Req.Query.UnicodeCaseFold := True;
  Data := TEncoding.UTF8.GetBytes('A' + #$D83D#$DE00 + 'B');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'surrogate', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode supplementary match');
  CheckEqual(S.Matches[0].ByteOffset, 1, 'Unicode supplementary offset');
  CheckEqual(S.Matches[0].ByteLength, 4, 'Unicode supplementary bytes');
  CheckEqual(S.Matches[0].Column, 2, 'Unicode supplementary column');
end;

procedure UnicodeFuzzyTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Data: TBytes;
  Stats: TGrepStatistics;
  I: Integer;
begin
  Req := NewRequest(Dir, 4);
  Req.Query.Mode := gmFuzzyText;
  Req.Query.Encoding := geAuto;
  Req.Query.Text := 'café';
  Req.Query.MaxDistance := 1;
  Req.Query.FuzzyCodePoints := True;
  Data := TEncoding.UTF8.GetBytes('cafe');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'fuzzy-ascii', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode fuzzy distance one');
  CheckEqual(S.Matches[0].Distance, 1, 'Unicode fuzzy distance scalar');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode fuzzy tie byte offset');
  CheckEqual(S.Matches[0].ByteLength, 3, 'Unicode fuzzy tie prefers shortest span');
  Sink := nil;
  Data := TEncoding.UTF8.GetBytes('cax' + #$00E9);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'fuzzy-substitution', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode fuzzy unambiguous substitution count');
  CheckEqual(S.Matches[0].Distance, 1, 'Unicode fuzzy unambiguous substitution distance');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'Unicode fuzzy unambiguous substitution offset');
  CheckEqual(S.Matches[0].ByteLength, 5, 'Unicode fuzzy unambiguous substitution byte span');
  Sink := nil;
  Req.Query.UnicodeNormalizeNfd := True;
  Req.Query.Text := 'café';
  Data := TEncoding.UTF8.GetBytes('cafe' + #$0301);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'fuzzy-nfd', Data, Sink);
  Check(Stats.Matches > 0, 'Unicode fuzzy normalization');
  CheckEqual(S.Matches[0].Distance, 0, 'Unicode fuzzy normalized distance zero');
  Sink := nil;
  Req.Query.UnicodeNormalizeNfd := False;
  Req.Query.Text := 'A€B';
  Data := TEncoding.UTF8.GetBytes('AEB');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'fuzzy-multibyte', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode fuzzy multibyte is one substitution');
  CheckEqual(S.Matches[0].Distance, 1, 'Unicode fuzzy multibyte distance');
  Sink := nil;
  Req.Query.Mode := gmLiteralText;
  Req.Query.MaxDistance := 0;
  Req.Query.FuzzyCodePoints := False;
  Req.Query.UnicodeCaseFold := True;
  Req.Query.Text := 'ÄBC';
  Data := TEncoding.UTF8.GetBytes(StringOfChar('x', 4095) + 'äbc');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'unicode-boundary', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'Unicode chunk boundary exact');
  CheckEqual(S.Matches[0].ByteOffset, 4095, 'Unicode chunk boundary offset');
  Sink := nil;
  Req.Query.UnicodeCaseFold := False;
  Req.Query.UnicodeNormalizeNfd := True;
  Req.Query.Mode := gmMultiText;
  Req.Query.TextPatterns := ['e' + #$0301, 'café'];
  Data := TEncoding.UTF8.GetBytes('café');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'unicode-multi', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'Unicode multi-pattern');
  for I := 0 to S.Matches.Count - 1 do Check(S.Matches[I].ByteLength > 0, 'Unicode multi mapped length');
end;

procedure SortOrderTest(const Dir: string);
var
  Root: string;
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  I, Trial, Workers: Integer;
  Paths: array[0..2] of string;
begin
  Root := Dir + '\sort-order';
  ForceDirectories(Root);
  Paths[0] := Root + '\A.pas';
  Paths[1] := Root + '\b.pas';
  Paths[2] := Root + '\z.pas';
  WriteFileBytes(Paths[2], TEncoding.ASCII.GetBytes('ABABA'));
  WriteFileBytes(Paths[1], TEncoding.ASCII.GetBytes('ABABA'));
  WriteFileBytes(Paths[0], TEncoding.ASCII.GetBytes('ABABA'));
  for Trial := 0 to 1 do
  begin
    if Trial = 0 then Workers := 1 else Workers := 4;
    Req := NewRequest(Root, Workers);
    Req.Options.SortResults := True;
    S := TCollectSink.Create;
    Sink := S;
    Stats := TNativeGrep.Search(Req, Sink);
    CheckEqual(Stats.Matches, 6, 'sorted match count');
    CheckEqual(Stats.FilesScanned, 3, 'sorted scanned count');
    CheckEqual(Stats.Errors, 0, 'sorted errors');
    for I := 0 to 5 do
    begin
      Check(S.Matches[I].SourcePath = Paths[I div 2], 'sorted path ' + IntToStr(I));
      CheckEqual(S.Matches[I].ByteOffset, (I mod 2) * 2, 'sorted byte offset ' + IntToStr(I));
    end;
    Sink := nil;
    Req.Options.MaxResultsTotal := 3;
    S := TCollectSink.Create;
    Sink := S;
    Stats := TNativeGrep.Search(Req, Sink);
    CheckEqual(Stats.Matches, 3, 'sorted max-results count');
    CheckEqual(Stats.FilesScanned, 3, 'sorted max-results still scans files');
    Check(S.Matches[0].SourcePath = Paths[0], 'sorted max first path');
    Check(S.Matches[1].SourcePath = Paths[0], 'sorted max second path');
    Check(S.Matches[2].SourcePath = Paths[1], 'sorted max third path');
    Sink := nil;
  end;
end;

procedure SortDiskMergeTest;
var
  Sorter: TGrepMatchSorter;
  Match: TGrepMatch;
  I, Received: Integer;
  BeforeSum, AfterSum: Int64;
  LastPath: string;
  LastOffset: Int64;
  LastPattern: Integer;
  HavePrevious: Boolean;
begin
  Sorter := TGrepMatchSorter.Create;
  try
    BeforeSum := 0;
    AfterSum := 0;
    Received := 0;
    HavePrevious := False;
    for I := 0 to 9000 do
    begin
      Match := Default(TGrepMatch);
      if (I mod 3) = 0 then Match.SourcePath := 'a' else Match.SourcePath := 'z';
      Match.ByteOffset := (I * 37) mod 5003;
      Match.PatternIndex := I mod 3;
      Match.ByteLength := 3;
      Sorter.Add(Match);
      Inc(BeforeSum, Match.ByteOffset * 13 + Match.PatternIndex * 7 + Ord(Match.SourcePath[1]));
    end;
    Sorter.Drain(
      function(const Item: TGrepMatch): Boolean
      begin
        Inc(Received);
        Inc(AfterSum, Item.ByteOffset * 13 + Item.PatternIndex * 7 + Ord(Item.SourcePath[1]));
        if HavePrevious then
        begin
          Check(LastPath <= Item.SourcePath, 'disk sort paths');
          if LastPath = Item.SourcePath then
          begin
            Check(LastOffset <= Item.ByteOffset, 'disk sort offsets');
            if LastOffset = Item.ByteOffset then Check(LastPattern <= Item.PatternIndex, 'disk sort pattern');
          end;
        end;
        LastPath := Item.SourcePath;
        LastOffset := Item.ByteOffset;
        LastPattern := Item.PatternIndex;
        HavePrevious := True;
        Result := True;
      end,
      function: Boolean
      begin
        Result := False;
      end);
    CheckEqual(Received, 9001, 'disk sort count');
    CheckEqual(AfterSum, BeforeSum, 'disk sort checksum');
  finally
    Sorter.Free;
  end;
end;

procedure SortCancellationAndFailureTest(const Dir: string);
var
  Req: TGrepRequest;
  Token: TGrepCancellationToken;
  Cancellation: IGrepCancellation;
  Collector: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  Sorter: TGrepMatchSorter;
  Match: TGrepMatch;
  I, Checks: Integer;
  Raised: Boolean;
begin
  Req := NewRequest(Dir, 4);
  Req.Options.Includes := ['parallel_*.dat'];
  Req.Options.SortResults := True;
  Req.Options.ResultQueueCapacity := 1;
  Token := TGrepCancellationToken.Create;
  Cancellation := Token;
  Collector := TCollectSink.Create(Token, 2);
  Sink := Collector;
  Stats := TNativeGrep.Search(Req, Sink, Cancellation);
  CheckEqual(Stats.Matches, 2, 'sort output cancellation count');
  CheckEqual(Collector.Matches.Count, 2, 'sort output cancellation events');
  Check(Cancellation.IsCancellationRequested, 'sort output cancellation signaled');
  Sink := nil;
  Cancellation := nil;
  Req := NewRequest(Dir + '\dense.bin', 4);
  Req.Query.Mode := gmLiteralBytes;
  Req.Query.Bytes := TEncoding.ASCII.GetBytes('A');
  Req.Options.ResultQueueCapacity := 1;
  Sink := TThrowSink.Create;
  Raised := False;
  try
    TNativeGrep.Search(Req, Sink);
  except
    on E: EInvalidOpException do Raised := E.Message = 'Intentional result sink failure';
  end;
  Check(Raised, 'sink failure propagated after worker shutdown');
  Sink := nil;
  Checks := 0;
  Sorter := TGrepMatchSorter.Create(
    function: Boolean
    begin
      Inc(Checks);
      Result := Checks >= 4102;
    end);
  try
    Raised := False;
    Match := Default(TGrepMatch);
    Match.SourcePath := 'sort-cancel';
    Match.ByteLength := 1;
    try
      for I := 0 to 4095 do
      begin
        Match.ByteOffset := 4095 - I;
        Sorter.Add(Match);
      end;
    except
      on E: EAbort do Raised := E.Message = 'Sort cancelled';
    end;
    Check(Raised, 'sort merge observes cancellation');
    Check(Checks >= 4102, 'sort merge cancellation reached');
  finally
    Sorter.Free;
  end;
end;

procedure SortStreamTest;
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
begin
  Req := NewRequest('.', 4);
  Req.Options.SortResults := True;
  Req.Options.MaxResultsTotal := 2;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'sort-memory', TEncoding.UTF8.GetBytes('ABABABA'), Sink);
  CheckEqual(Stats.Matches, 2, 'sorted stream limit');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'sorted stream first');
  CheckEqual(S.Matches[1].ByteOffset, 2, 'sorted stream second');
  Sink := nil;
end;

procedure RegexIntegrationTest(const Dir: string);
var
  Req: TGrepRequest;
  S: TCollectSink;
  Sink: IGrepResultSink;
  Stats: TGrepStatistics;
  Data: TBytes;
  I: Integer;
  Missing: Boolean;
begin
  if not FileExists(ExtractFilePath(ParamStr(0)) + 'pcre2-8.dll') then
  begin
    Writeln('NativeGrep regex tests: SKIPPED (pcre2-8.dll missing)');
    Exit;
  end;
  Req := NewRequest(Dir, 4);
  Req.Query.Mode := gmRegexText;
  Req.Query.Text := 'GetCustomer\s*\(([0-9]+)\)';
  Req.Options.SortResults := True;
  Data := TEncoding.UTF8.GetBytes('GetCustomer(12)'#10'GetCustomer (345)'#10);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-memory', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'regex two matches');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'regex first offset');
  CheckEqual(S.Matches[1].ByteOffset, 16, 'regex second offset');
  CheckEqual(S.Matches[0].Line, 1, 'regex first line');
  CheckEqual(S.Matches[1].Line, 2, 'regex second line');
  CheckEqual(Length(S.Matches[0].Captures), 1, 'regex group count');
  CheckEqual(S.Matches[0].Captures[0].ByteOffset, 12, 'regex capture offset');
  CheckEqual(S.Matches[0].Captures[0].ByteLength, 2, 'regex capture length');
  Sink := nil;
  Req.Query.Text := '(a*)';
  Req.Options.SortResults := False;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'empty-match', TEncoding.UTF8.GetBytes('bb'), Sink);
  CheckEqual(Stats.Matches, 3, 'regex zero-length progress');
  Sink := nil;
  Req.Query.Text := 'ABC[0-9]';
  Req.Options.SortResults := True;
  Req.Options.RegexMaxBytes := 1;
  S := TCollectSink.Create;
  Sink := S;
  Missing := False;
  try
    TNativeGrep.SearchBytes(Req, 'size-limit', TEncoding.UTF8.GetBytes('ABC123'), Sink);
  except
    on E: EArgumentOutOfRangeException do Missing := True;
  end;
  Check(Missing, 'regex source limit is enforced');
  Sink := nil;
  Req.Options.RegexMaxBytes := 64 * 1024 * 1024;
  SetLength(Data, 50000);
  for I := 0 to High(Data) do Data[I] := Ord('B');
  Data[4095] := Ord('A');
  Data[4096] := Ord('B');
  Data[4097] := Ord('C');
  Data[4098] := Ord('1');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-boundary', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'regex cross-chunk match');
  CheckEqual(S.Matches[0].ByteOffset, 4095, 'regex cross-chunk offset');
  Sink := nil;
  Req.Query.Text := '(AB)';
  Req.Options.SortResults := True;
  SetLength(Data, 6000);
  for I := 0 to 2999 do
  begin
    Data[2 * I] := Ord('A');
    Data[2 * I + 1] := Ord('B');
  end;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-sorted-spill', Data, Sink);
  CheckEqual(Stats.Matches, 3000, 'regex sorted spill count');
  CheckEqual(S.Matches[2049].Captures[0].ByteOffset, 4098, 'regex capture survived external merge');
  Sink := nil;
  Req.Query.Text := 'hello';
  Req.Options.SortResults := False;
  Data := TEncoding.UTF8.GetBytes(#$FEFF'hello');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-bom', Data, Sink);
  CheckEqual(Stats.Matches, 1, 'regex utf8 bom match');
  CheckEqual(S.Matches[0].ByteOffset, 3, 'regex utf8 bom offset');
  Sink := nil;
  SetLength(Data, 3);
  Data[0] := $C0;
  Data[1] := $AF;
  Data[2] := Ord('x');
  S := TCollectSink.Create;
  Sink := S;
  Missing := False;
  try
    TNativeGrep.SearchBytes(Req, 'regex-bad-utf8', Data, Sink);
  except
    on E: EArgumentException do Missing := True;
  end;
  Check(Missing, 'regex strict utf8 validation with absent prefilter');
  Sink := nil;
  Req.Query.Text := 'TODO|FIXME';
  Req.Query.RegexAllowInvalidUtf8 := True;
  Data := TEncoding.ASCII.GetBytes('TODO'#10'XFIXME'#10'TODO');
  Data[5] := $FF;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-invalid-utf-tolerant', Data, Sink);
  CheckEqual(Stats.Matches, 3, 'regex invalid utf tolerant match count');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'regex invalid utf first offset');
  CheckEqual(S.Matches[1].ByteOffset, 6, 'regex invalid utf second offset');
  CheckEqual(S.Matches[2].ByteOffset, 12, 'regex invalid utf third offset');
  CheckEqual(S.Matches[0].Line, 0, 'regex invalid utf has no uncertain text position');
  Sink := nil;
  Req.Query.Text := 'A.B';
  Data[0] := Ord('A');
  Data[1] := $FF;
  Data[2] := Ord('B');
  SetLength(Data, 3);
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-invalid-utf-boundary', Data, Sink);
  CheckEqual(Stats.Matches, 0, 'regex invalid bytes cannot be crossed');
  Sink := nil;
  Req.Query.Text := 'TODO';
  Data := TEncoding.UTF8.GetBytes('TODO'#10'TODO');
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-valid-utf-tolerant', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'regex valid utf tolerant count');
  CheckEqual(S.Matches[1].Line, 2, 'regex valid utf tolerant keeps line positions');
  Sink := nil;
  Req.Query.Text := 'TODO[0-9]';
  Data := TEncoding.ASCII.GetBytes('TODO1'#10'X'#10'TODO2');
  Data[6] := $FF;
  S := TCollectSink.Create;
  Sink := S;
  Stats := TNativeGrep.SearchBytes(Req, 'regex-invalid-utf-prefilter', Data, Sink);
  CheckEqual(Stats.Matches, 2, 'regex invalid utf required prefix match count');
  CheckEqual(S.Matches[0].ByteOffset, 0, 'regex invalid utf required prefix first offset');
  CheckEqual(S.Matches[1].ByteOffset, 8, 'regex invalid utf required prefix second offset');
  Sink := nil;
end;

var
  Dir: string;
  Guid: TGUID;
begin
  ReportMemoryLeaksOnShutdown := True;
  CreateGUID(Guid);
  Dir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'NativeGrepTests_' + GUIDToString(Guid);
  ForceDirectories(Dir);
  try
    try
      BoundaryTest(Dir);
      TextPositionTest(Dir);
      TextPositionFastPathTest(Dir);
      MaskedTest(Dir);
      LongPatternTest(Dir);
      BomAndQueueTest(Dir);
      ParallelTest(Dir);
      WorkerBufferReuseTest(Dir);
      ProfilingTest(Dir);
      CancellationTest(Dir);
      ErrorTest(Dir);
      MultiPatternTest(Dir);
      FuzzyTest(Dir);
      EncodingAndStreamTest(Dir);
      ScanPolicyTest(Dir);
      AutoEncodingTest(Dir);
      AutoMultiEncodingTest(Dir);
      RelativeGlobTest(Dir);
      WindowsPathTest;
      ContextReadTest(Dir);
      UnicodeNormalizationTest(Dir);
      UnicodeFuzzyTest(Dir);
      UnicodeWorkerTest(Dir);
      UnicodeErrorContractTest(Dir);
      UnicodeCancellationTest(Dir);
      SortOrderTest(Dir);
      SortDiskMergeTest;
      SortStreamTest;
      SortCancellationAndFailureTest(Dir);
      RegexIntegrationTest(Dir);
      RunReplaceTests(Dir);
      RunReplaceStressTests(Dir);
      RunFileMonitorTests(Dir);
      Writeln('NativeGrep tests: PASS');
    finally
      TDirectory.Delete(Dir, True);
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
