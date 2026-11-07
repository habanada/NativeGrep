unit NativeGrep.Types;

interface

uses
  System.SysUtils;

type
  TGrepMode = (gmLiteralText, gmLiteralBytes, gmMaskedHex, gmMultiText, gmMultiBytes, gmFuzzyText, gmFuzzyBytes, gmRegexText);
  TGrepEncoding = (geUtf8, geUtf16LE, geUtf16BE, geAuto);
  TGrepTextPositions = (gtpAuto, gtpNone);
  TGrepBinaryPolicy = (gbAuto, gbText, gbRaw);

  TGrepQuery = record
    Mode: TGrepMode;
    Text: string;
    Bytes: TBytes;
    HexSignature: string;
    TextPatterns: TArray<string>;
    BytePatterns: TArray<TBytes>;
    MaxDistance: Integer;
    CaseInsensitiveAscii: Boolean;
    UnicodeCaseFold: Boolean;
    UnicodeNormalizeNfd: Boolean;
    FuzzyCodePoints: Boolean;
    Encoding: TGrepEncoding;
    RegexAllowInvalidUtf8: Boolean;
  end;

  // Inclusive bounds by default. Disabled bounds impose no restriction.
  TGrepFilterRange = record
    HasMinimum: Boolean;
    HasMaximum: Boolean;
    Minimum: Int64;
    Maximum: Int64;
    MinimumExclusive: Boolean;
    MaximumExclusive: Boolean;
  end;

  TGrepOptions = record
    Roots: TArray<string>;
    Includes: TArray<string>;
    Excludes: TArray<string>;
    Recursive: Boolean;
    IncludeHidden: Boolean;
    MaxWorkers: Integer;
    BufferSize: Integer;
    WorkQueueCapacity: Integer;
    ResultQueueCapacity: Integer;
    MaxFileSize: Int64;
    FileSizeFilter: TGrepFilterRange;
    // UTC Windows FILETIME ticks (100 ns since 1601-01-01).
    CreatedTimeFilter: TGrepFilterRange;
    ModifiedTimeFilter: TGrepFilterRange;
    AccessedTimeFilter: TGrepFilterRange;
    MaxMatchesPerFile: Int64;
    MaxResultsTotal: Int64;
    TextPositions: TGrepTextPositions;
    BinaryPolicy: TGrepBinaryPolicy;
    Profile: Boolean;
    SortResults: Boolean;
    RegexMaxBytes: Int64;
    RegexMatchLimit: Cardinal;
    RegexDepthLimit: Cardinal;
  end;

  TGrepRequest = record
    Query: TGrepQuery;
    Options: TGrepOptions;
  end;

  TGrepCapture = record
    Index: Integer;
    Matched: Boolean;
    ByteOffset: Int64;
    ByteLength: NativeUInt;
  end;

  TGrepMatch = record
    SourcePath: string;
    ByteOffset: Int64;
    ByteLength: NativeUInt;
    Line: Int64;
    Column: Int64;
    PatternIndex: Integer;
    Distance: Integer;
    Captures: TArray<TGrepCapture>;
  end;

  TGrepStatistics = record
    FilesEnumerated: Int64;
    FilesScanned: Int64;
    BytesScanned: Int64;
    Matches: Int64;
    Errors: Int64;
    ElapsedMs: UInt64;
    WorkerCount: Integer;
    BinaryRawSources: Int64;
    ProfileEnabled: Boolean;
    DiscoveryWallUs: Int64;
    DiscoveryEnqueueUs: Int64;
    CompileWorkerUs: Int64;
    FileOpenWorkerUs: Int64;
    BufferSetupWorkerUs: Int64;
    BufferAllocations: Int64;
    FileReadWorkerUs: Int64;
    MatchWorkerUs: Int64;
    TextPositionWorkerUs: Int64;
    ResultEnqueueWorkerUs: Int64;
    FileScanWorkerUs: Int64;
    WorkQueueWaitWorkerUs: Int64;
    SinkDispatchUs: Int64;
  end;

  IGrepResultSink = interface
    ['{537C6679-8911-4353-A7FC-357B42E79BD2}']
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
  end;

  IGrepCancellation = interface
    ['{B6780824-6E0B-407E-BE10-E48754B67625}']
    function IsCancellationRequested: Boolean;
  end;

  TGrepCancellationToken = class(TInterfacedObject, IGrepCancellation)
  private
    FCancelled: Integer;
  public
    procedure Cancel;
    function IsCancellationRequested: Boolean;
  end;

implementation

uses
  System.SyncObjs;

procedure TGrepCancellationToken.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TGrepCancellationToken.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

end.
