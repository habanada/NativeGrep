unit NativeGrep.Engine;

interface

uses
  System.SysUtils, System.Classes, NativeGrep.Types;

type
  TNativeGrep = class sealed
  public
    class function Search(const Request: TGrepRequest; const Sink: IGrepResultSink; const Cancellation: IGrepCancellation = nil): TGrepStatistics; static;
    class function SearchStream(const Request: TGrepRequest; const SourceName: string; Stream: TStream; const Sink: IGrepResultSink; const Cancellation: IGrepCancellation = nil): TGrepStatistics; static;
    class function SearchBytes(const Request: TGrepRequest; const SourceName: string; const Data: TBytes; const Sink: IGrepResultSink; const Cancellation: IGrepCancellation = nil): TGrepStatistics; static;
  end;

implementation

uses
  System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, NativeGrep.Matcher,
  NativeGrep.Queue, NativeGrep.Files, NativeGrep.Scanner, NativeGrep.Timing, NativeGrep.Sort;

type
  TGrepEventKind = (geMatch, geError);

  TGrepEvent = record
    Kind: TGrepEventKind;
    Match: TGrepMatch;
    Path: string;
    ErrorText: string;
  end;

  TGrepContext = class
  private
    FRequest: TGrepRequest;
    FExternalCancellation: IGrepCancellation;
    FCancelCheck: TFunc<Boolean>;
    FWorkQueue: TBoundedQueue<string>;
    FResultQueue: TBoundedQueue<TGrepEvent>;
    FActiveWorkers: Integer;
    FCancelled: Integer;
    FFatalFailure: Integer;
    FFatalMessage: string;
    FFilesEnumerated: Int64;
    FFilesScanned: Int64;
    FBytesScanned: Int64;
    FBinaryRawSources: Int64;
    FDiscoveryTicks: Int64;
    FDiscoveryEnqueueTicks: Int64;
    FCompileTicks: Int64;
    FFileOpenTicks: Int64;
    FBufferSetupTicks: Int64;
    FBufferAllocations: Int64;
    FFileReadTicks: Int64;
    FMatchTicks: Int64;
    FPositionTicks: Int64;
    FEnqueueTicks: Int64;
    FFileScanTicks: Int64;
    FWorkWaitTicks: Int64;
    function Cancelled: Boolean;
    procedure Cancel;
    procedure SendError(const Path, ErrorText: string);
    procedure Produce;
    procedure Work;
  public
    constructor Create(const Request: TGrepRequest; const Cancellation: IGrepCancellation);
    destructor Destroy; override;
    function Execute(const Sink: IGrepResultSink): TGrepStatistics;
    function ExecuteStream(const Stream: TStream; const SourceName: string; const Sink: IGrepResultSink): TGrepStatistics;
  end;

function ResolveWorkers(const Requested: Integer): Integer;
var
  Info: TSystemInfo;
begin
  if Requested > 0 then Exit(Requested);
  GetSystemInfo(Info);
  Result := Integer(Info.dwNumberOfProcessors);
  if Result < 1 then Result := 1;
  if Result > 8 then Result := 8;
end;

constructor TGrepContext.Create(const Request: TGrepRequest; const Cancellation: IGrepCancellation);
var
  S: string;
  Matcher: TGrepMatcher;
  I: Integer;
begin
  inherited Create;
  FRequest := Request;
  FRequest.Options.Roots := Copy(Request.Options.Roots);
  FRequest.Options.Includes := Copy(Request.Options.Includes);
  FRequest.Options.Excludes := Copy(Request.Options.Excludes);
  FRequest.Query.Bytes := Copy(Request.Query.Bytes);
  FRequest.Query.TextPatterns := Copy(Request.Query.TextPatterns);
  SetLength(FRequest.Query.BytePatterns, Length(Request.Query.BytePatterns));
  for I := 0 to High(FRequest.Query.BytePatterns) do FRequest.Query.BytePatterns[I] := Copy(Request.Query.BytePatterns[I]);
  FExternalCancellation := Cancellation;
  FCancelCheck := function: Boolean
    begin
      Result := Cancelled;
    end;
  if Length(FRequest.Options.Roots) = 0 then
    raise EArgumentException.Create('At least one root path is required');
  for S in FRequest.Options.Roots do
    if S = '' then raise EArgumentException.Create('Root path must not be empty');
  if (FRequest.Options.MaxWorkers < 0) or (FRequest.Options.MaxWorkers > 64) then
    raise EArgumentOutOfRangeException.Create('MaxWorkers must be between 0 and 64');
  if FRequest.Options.BufferSize = 0 then FRequest.Options.BufferSize := 1024 * 1024;
  if (FRequest.Options.BufferSize < 4096) or (FRequest.Options.BufferSize > 16 * 1024 * 1024) then
    raise EArgumentOutOfRangeException.Create('BufferSize must be between 4096 and 16777216');
  if (FRequest.Options.RegexMaxBytes < 0) or (FRequest.Options.RegexMaxBytes > 1024 * 1024 * 1024) then
    raise EArgumentOutOfRangeException.Create('RegexMaxBytes must be between 0 and 1 GiB');
  if FRequest.Options.RegexMaxBytes = 0 then FRequest.Options.RegexMaxBytes := 64 * 1024 * 1024;
  if FRequest.Options.RegexMatchLimit = 0 then FRequest.Options.RegexMatchLimit := 1000000;
  if FRequest.Options.RegexDepthLimit = 0 then FRequest.Options.RegexDepthLimit := 1000;
  if (FRequest.Options.MaxMatchesPerFile < 0) or (FRequest.Options.MaxResultsTotal < 0) or (FRequest.Options.MaxFileSize < 0) then
    raise EArgumentOutOfRangeException.Create('Result and file size limits must not be negative');
  Matcher := TGrepMatcher.Create(FRequest.Query);
  try
    if Matcher.WindowLength > 4 * 1024 * 1024 then raise EArgumentOutOfRangeException.Create('Pattern window exceeds 4 MiB');
  finally
    Matcher.Free;
  end;
  FRequest.Options.MaxWorkers := ResolveWorkers(FRequest.Options.MaxWorkers);
  if FRequest.Options.WorkQueueCapacity = 0 then FRequest.Options.WorkQueueCapacity := FRequest.Options.MaxWorkers * 4;
  if FRequest.Options.ResultQueueCapacity = 0 then FRequest.Options.ResultQueueCapacity := 1024;
  if (FRequest.Options.WorkQueueCapacity < 1) or (FRequest.Options.WorkQueueCapacity > 65536) then
    raise EArgumentOutOfRangeException.Create('Invalid work queue capacity');
  if (FRequest.Options.ResultQueueCapacity < 1) or (FRequest.Options.ResultQueueCapacity > 65536) then
    raise EArgumentOutOfRangeException.Create('Invalid result queue capacity');
  FWorkQueue := TBoundedQueue<string>.Create(FRequest.Options.WorkQueueCapacity);
  FResultQueue := TBoundedQueue<TGrepEvent>.Create(FRequest.Options.ResultQueueCapacity);
end;

destructor TGrepContext.Destroy;
begin
  FResultQueue.Free;
  FWorkQueue.Free;
  inherited;
end;

function TGrepContext.Cancelled: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0) or
    ((FExternalCancellation <> nil) and FExternalCancellation.IsCancellationRequested);
end;

procedure TGrepContext.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
  FWorkQueue.Close;
  FResultQueue.Close;
end;

procedure TGrepContext.SendError(const Path, ErrorText: string);
var
  Event: TGrepEvent;
begin
  Event := Default(TGrepEvent);
  Event.Kind := geError;
  Event.Path := Path;
  Event.ErrorText := ErrorText;
  FResultQueue.Enqueue(Event, FCancelCheck);
end;

procedure TGrepContext.Produce;
var
  Stamp, EnqueueStamp: Int64;
begin
  if FRequest.Options.Profile then Stamp := GrepTimestamp;
  try
    try
      TGrepFileEnumerator.Execute(FRequest.Options, FCancelCheck,
        procedure(Path: string)
        begin
          if FRequest.Options.Profile then EnqueueStamp := GrepTimestamp;
          try
            if FWorkQueue.Enqueue(Path, FCancelCheck) then TInterlocked.Increment(FFilesEnumerated);
          finally
            if FRequest.Options.Profile then TInterlocked.Add(FDiscoveryEnqueueTicks, GrepTimestamp - EnqueueStamp);
          end;
        end,
        procedure(Path, ErrorText: string)
        begin
          SendError(Path, ErrorText);
        end);
    except
      on E: Exception do
      begin
        if TInterlocked.CompareExchange(FFatalFailure, 1, 0) = 0 then FFatalMessage := 'File discovery: ' + E.ClassName + ': ' + E.Message;
        Cancel;
      end;
    end;
  finally
    if FRequest.Options.Profile then FDiscoveryTicks := GrepTimestamp - Stamp;
    FWorkQueue.Close;
  end;
end;

procedure TGrepContext.Work;
var
  Matcher: TGrepMatcher;
  Buffer: TBytes;
  Event: TGrepEvent;
  Path: string;
  BytesRead: Int64;
  Timing: TGrepScanTiming;
  Stamp: Int64;
  HasPath: Boolean;
begin
  Matcher := nil;
  try
    try
      if FRequest.Options.Profile then Stamp := GrepTimestamp;
      try
        Matcher := TGrepMatcher.Create(FRequest.Query);
      finally
        if FRequest.Options.Profile then TInterlocked.Add(FCompileTicks, GrepTimestamp - Stamp);
      end;
      while True do
      begin
        if FRequest.Options.Profile then Stamp := GrepTimestamp;
        HasPath := FWorkQueue.Dequeue(Path, FCancelCheck);
        if FRequest.Options.Profile then TInterlocked.Add(FWorkWaitTicks, GrepTimestamp - Stamp);
        if not HasPath or Cancelled then Break;
        BytesRead := 0;
        Timing := Default(TGrepScanTiming);
        TInterlocked.Increment(FFilesScanned);
        if FRequest.Options.Profile then Stamp := GrepTimestamp;
        try
          try
            TGrepFileScanner.Scan(Path, Matcher, FRequest.Options, FCancelCheck,
              procedure(Match: TGrepMatch)
              begin
                Event := Default(TGrepEvent);
                Event.Kind := geMatch;
                Event.Match := Match;
                FResultQueue.Enqueue(Event, FCancelCheck);
              end, BytesRead, Timing, Buffer);
          finally
            TInterlocked.Add(FBytesScanned, BytesRead);
            if Timing.BinaryRaw then TInterlocked.Increment(FBinaryRawSources);
            if FRequest.Options.Profile then
            begin
              TInterlocked.Add(FFileScanTicks, GrepTimestamp - Stamp);
              TInterlocked.Add(FFileOpenTicks, Timing.OpenTicks);
              TInterlocked.Add(FBufferSetupTicks, Timing.BufferSetupTicks);
              TInterlocked.Add(FBufferAllocations, Timing.BufferAllocations);
              TInterlocked.Add(FFileReadTicks, Timing.ReadTicks);
              TInterlocked.Add(FMatchTicks, Timing.MatchTicks);
              TInterlocked.Add(FPositionTicks, Timing.PositionTicks);
              TInterlocked.Add(FEnqueueTicks, Timing.EnqueueTicks);
            end;
          end;
        except
          on E: Exception do SendError(Path, E.ClassName + ': ' + E.Message);
        end;
      end;
    except
      on E: Exception do
      begin
        if TInterlocked.CompareExchange(FFatalFailure, 1, 0) = 0 then FFatalMessage := 'Worker: ' + E.ClassName + ': ' + E.Message;
        Cancel;
      end;
    end;
  finally
    Matcher.Free;
    if TInterlocked.Decrement(FActiveWorkers) = 0 then FResultQueue.Close;
  end;
end;

function TGrepContext.Execute(const Sink: IGrepResultSink): TGrepStatistics;
var
  Producer: TThread;
  Sorter: TGrepMatchSorter;
  Workers: TArray<TThread>;
  StartedWorkers, I: Integer;
  Event: TGrepEvent;
  TickStart: UInt64;
  Frequency, SinkTicks, Stamp: Int64;
  ProducerStarted: Boolean;
  SortedDelivered: Int64;
begin
  Result := Default(TGrepStatistics);
  SortedDelivered := 0;
  TickStart := GetTickCount64;
  SinkTicks := 0;
  Frequency := 0;
  if FRequest.Options.Profile and not QueryPerformanceFrequency(Frequency) then
    raise EInvalidOpException.Create('High resolution performance counter unavailable');
  Producer := nil;
  Sorter := nil;
  StartedWorkers := 0;
  ProducerStarted := False;
  SetLength(Workers, FRequest.Options.MaxWorkers);
  try
    try
      if FRequest.Options.SortResults then Sorter := TGrepMatchSorter.Create(FCancelCheck);
    for I := 0 to High(Workers) do
    begin
      Workers[I] := TThread.CreateAnonymousThread(
        procedure
        begin
          Work;
        end);
      Workers[I].FreeOnTerminate := False;
    end;
    Producer := TThread.CreateAnonymousThread(
      procedure
      begin
        Produce;
      end);
    Producer.FreeOnTerminate := False;
    FActiveWorkers := Length(Workers);
    for I := 0 to High(Workers) do
    begin
      Workers[I].Start;
      Inc(StartedWorkers);
    end;
    Producer.Start;
    ProducerStarted := True;
    while FResultQueue.Dequeue(Event, FCancelCheck) do
    begin
      if Event.Kind = geError then
      begin
        Inc(Result.Errors);
        if FRequest.Options.Profile then Stamp := GrepTimestamp;
        try
          Sink.ScanError(Event.Path, Event.ErrorText);
        finally
          if FRequest.Options.Profile then Inc(SinkTicks, GrepTimestamp - Stamp);
        end;
      end
      else if Sorter <> nil then Sorter.Add(Event.Match)
      else
      begin
        Inc(Result.Matches);
        if FRequest.Options.Profile then Stamp := GrepTimestamp;
        try
          Sink.MatchFound(Event.Match);
        finally
          if FRequest.Options.Profile then Inc(SinkTicks, GrepTimestamp - Stamp);
        end;
        if (FRequest.Options.MaxResultsTotal > 0) and (Result.Matches >= FRequest.Options.MaxResultsTotal) then
        begin
          Cancel;
          Break;
        end;
      end;
    end;
    if (Sorter <> nil) and not Cancelled then
      Sorter.Drain(
        function(const Match: TGrepMatch): Boolean
        begin
          Inc(SortedDelivered);
          if FRequest.Options.Profile then Stamp := GrepTimestamp;
          try
            Sink.MatchFound(Match);
          finally
            if FRequest.Options.Profile then Inc(SinkTicks, GrepTimestamp - Stamp);
          end;
          Result := (FRequest.Options.MaxResultsTotal = 0) or (SortedDelivered < FRequest.Options.MaxResultsTotal);
        end, FCancelCheck);
    if Sorter <> nil then Result.Matches := SortedDelivered;
    except
      on E: EAbort do
        if not Cancelled then raise;
    end;
  finally
    Cancel;
    if Producer <> nil then
    begin
      if ProducerStarted then Producer.WaitFor;
      Producer.Free;
    end;
    for I := 0 to High(Workers) do
      if Workers[I] <> nil then
      begin
        if I < StartedWorkers then Workers[I].WaitFor;
        Workers[I].Free;
      end;
    Sorter.Free;
    Result.FilesEnumerated := FFilesEnumerated;
    Result.FilesScanned := FFilesScanned;
    Result.BytesScanned := FBytesScanned;
    Result.BinaryRawSources := FBinaryRawSources;
    Result.WorkerCount := FRequest.Options.MaxWorkers;
    Result.ElapsedMs := GetTickCount64 - TickStart;
    Result.ProfileEnabled := FRequest.Options.Profile;
    if FRequest.Options.Profile then
    begin
      Result.DiscoveryWallUs := GrepToMicroseconds(FDiscoveryTicks, Frequency);
      Result.DiscoveryEnqueueUs := GrepToMicroseconds(FDiscoveryEnqueueTicks, Frequency);
      Result.CompileWorkerUs := GrepToMicroseconds(FCompileTicks, Frequency);
      Result.FileOpenWorkerUs := GrepToMicroseconds(FFileOpenTicks, Frequency);
      Result.BufferSetupWorkerUs := GrepToMicroseconds(FBufferSetupTicks, Frequency);
      Result.BufferAllocations := FBufferAllocations;
      Result.FileReadWorkerUs := GrepToMicroseconds(FFileReadTicks, Frequency);
      Result.MatchWorkerUs := GrepToMicroseconds(FMatchTicks, Frequency);
      Result.TextPositionWorkerUs := GrepToMicroseconds(FPositionTicks, Frequency);
      Result.ResultEnqueueWorkerUs := GrepToMicroseconds(FEnqueueTicks, Frequency);
      Result.FileScanWorkerUs := GrepToMicroseconds(FFileScanTicks, Frequency);
      Result.WorkQueueWaitWorkerUs := GrepToMicroseconds(FWorkWaitTicks, Frequency);
      Result.SinkDispatchUs := GrepToMicroseconds(SinkTicks, Frequency);
    end;
  end;
  if FFatalFailure <> 0 then raise EInvalidOpException.Create(FFatalMessage);
end;

function TGrepContext.ExecuteStream(const Stream: TStream; const SourceName: string; const Sink: IGrepResultSink): TGrepStatistics;
var
  Matcher: TGrepMatcher;
  Sorter: TGrepMatchSorter;
  Buffer: TBytes;
  BytesRead: Int64;
  Timing: TGrepScanTiming;
  StartTick: UInt64;
  Frequency: Int64;
  Count: Int64;
  Path: string;
begin
  if Stream = nil then raise EArgumentNilException.Create('Stream');
  if Sink = nil then raise EArgumentNilException.Create('Sink');
  Result := Default(TGrepStatistics);
  Result.FilesEnumerated := 1;
  Result.FilesScanned := 1;
  Result.WorkerCount := 1;
  Result.ProfileEnabled := FRequest.Options.Profile;
  Path := SourceName;
  if Path = '' then Path := '<stream>';
  StartTick := GetTickCount64;
  Frequency := 0;
  if FRequest.Options.Profile and not QueryPerformanceFrequency(Frequency) then
    raise EInvalidOpException.Create('High resolution performance counter unavailable');
  BytesRead := 0;
  Count := 0;
  Timing := Default(TGrepScanTiming);
  Matcher := TGrepMatcher.Create(FRequest.Query);
  Sorter := nil;
  try
    try
      if FRequest.Options.SortResults then Sorter := TGrepMatchSorter.Create(FCancelCheck);
    TGrepFileScanner.ScanStream(Path, Stream, Matcher, FRequest.Options, FCancelCheck,
      procedure(Match: TGrepMatch)
      begin
        if Cancelled then Exit;
        if Sorter <> nil then Sorter.Add(Match)
        else
        begin
          Inc(Count);
          Sink.MatchFound(Match);
          if (FRequest.Options.MaxResultsTotal > 0) and (Count >= FRequest.Options.MaxResultsTotal) then
            TInterlocked.Exchange(FCancelled, 1);
        end;
      end, BytesRead, Timing, Buffer);
    if (Sorter <> nil) and not Cancelled then
      Sorter.Drain(
        function(const Match: TGrepMatch): Boolean
        begin
          Inc(Count);
          Sink.MatchFound(Match);
          Result := (FRequest.Options.MaxResultsTotal = 0) or (Count < FRequest.Options.MaxResultsTotal);
        end, FCancelCheck);
    except
      on E: EAbort do
        if not Cancelled then raise;
    end;
  finally
    Sorter.Free;
    Matcher.Free;
    Result.Matches := Count;
    Result.BytesScanned := BytesRead;
    if Timing.BinaryRaw then Result.BinaryRawSources := 1;
    Result.ElapsedMs := GetTickCount64 - StartTick;
    if FRequest.Options.Profile then
    begin
      Result.BufferAllocations := Timing.BufferAllocations;
      Result.BufferSetupWorkerUs := GrepToMicroseconds(Timing.BufferSetupTicks, Frequency);
      Result.FileReadWorkerUs := GrepToMicroseconds(Timing.ReadTicks, Frequency);
      Result.MatchWorkerUs := GrepToMicroseconds(Timing.MatchTicks, Frequency);
      Result.TextPositionWorkerUs := GrepToMicroseconds(Timing.PositionTicks, Frequency);
      Result.ResultEnqueueWorkerUs := GrepToMicroseconds(Timing.EnqueueTicks, Frequency);
    end;
  end;
end;

class function TNativeGrep.Search(const Request: TGrepRequest; const Sink: IGrepResultSink; const Cancellation: IGrepCancellation): TGrepStatistics;
var
  Context: TGrepContext;
begin
  if Sink = nil then raise EArgumentNilException.Create('Sink');
  Context := TGrepContext.Create(Request, Cancellation);
  try
    Result := Context.Execute(Sink);
  finally
    Context.Free;
  end;
end;

class function TNativeGrep.SearchStream(const Request: TGrepRequest; const SourceName: string; Stream: TStream; const Sink: IGrepResultSink; const Cancellation: IGrepCancellation): TGrepStatistics;
var
  Context: TGrepContext;
  CopyRequest: TGrepRequest;
begin
  if Stream = nil then raise EArgumentNilException.Create('Stream');
  CopyRequest := Request;
  if Length(CopyRequest.Options.Roots) = 0 then CopyRequest.Options.Roots := ['.'];
  Context := TGrepContext.Create(CopyRequest, Cancellation);
  try
    Result := Context.ExecuteStream(Stream, SourceName, Sink);
  finally
    Context.Free;
  end;
end;

class function TNativeGrep.SearchBytes(const Request: TGrepRequest; const SourceName: string; const Data: TBytes; const Sink: IGrepResultSink; const Cancellation: IGrepCancellation): TGrepStatistics;
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create(Data);
  try
    Result := SearchStream(Request, SourceName, Stream, Sink, Cancellation);
  finally
    Stream.Free;
  end;
end;

end.
