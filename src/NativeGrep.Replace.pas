unit NativeGrep.Replace;

interface

uses
  System.SysUtils, NativeGrep.Types;

type
  TGrepReplaceStatistics = record
    FilesTotal: Integer;
    FilesProcessed: Integer;
    FilesChanged: Integer;
    MatchesTotal: Integer;
    MatchesReplaced: Integer;
    MatchesSkipped: Integer;
    BackupsCreated: Integer;
    Errors: Integer;
    Cancelled: Boolean;
    Failed: Boolean;
  end;

  TGrepBeforeReplaceEvent = procedure(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean) of object;
  TGrepAfterReplaceEvent = procedure(Sender: TObject; const Match: TGrepMatch; const BackupPath: string) of object;
  TGrepReplaceProgressEvent = procedure(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics) of object;
  TGrepReplaceCompletedEvent = procedure(Sender: TObject; const Statistics: TGrepReplaceStatistics) of object;
  TGrepReplaceErrorEvent = procedure(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean) of object;

  TGrepReplacer = class
  private
    FCancelled: Integer;
    FRunning: Integer;
    FOnBeforeReplace: TGrepBeforeReplaceEvent;
    FOnAfterReplace: TGrepAfterReplaceEvent;
    FOnProgress: TGrepReplaceProgressEvent;
    FOnCompleted: TGrepReplaceCompletedEvent;
    FOnAllReplaced: TGrepReplaceCompletedEvent;
    FOnError: TGrepReplaceErrorEvent;
    function IsCancelled(const Cancellation: IGrepCancellation): Boolean;
    function ExecuteInternal(const Request: TGrepRequest; const Matches: TArray<TGrepMatch>; const ReplacementText: string; const ReplacementBytes: TBytes; TextReplacement: Boolean; const Cancellation: IGrepCancellation): TGrepReplaceStatistics;
  public
    procedure Cancel;
    function ReplaceText(const Request: TGrepRequest; const Matches: TArray<TGrepMatch>; const Replacement: string; const Cancellation: IGrepCancellation = nil): TGrepReplaceStatistics;
    function ReplaceBytes(const Request: TGrepRequest; const Matches: TArray<TGrepMatch>; const Replacement: TBytes; const Cancellation: IGrepCancellation = nil): TGrepReplaceStatistics;
    property OnBeforeReplace: TGrepBeforeReplaceEvent read FOnBeforeReplace write FOnBeforeReplace;
    property OnAfterReplace: TGrepAfterReplaceEvent read FOnAfterReplace write FOnAfterReplace;
    property OnProgress: TGrepReplaceProgressEvent read FOnProgress write FOnProgress;
    property OnCompleted: TGrepReplaceCompletedEvent read FOnCompleted write FOnCompleted;
    property OnAllReplaced: TGrepReplaceCompletedEvent read FOnAllReplaced write FOnAllReplaced;
    property OnError: TGrepReplaceErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.SyncObjs,
  Winapi.Windows, NativeGrep.Engine, NativeGrep.Paths;

type
  TReplaceCancellation = class(TInterfacedObject, IGrepCancellation)
  private
    FOwner: TGrepReplacer;
    FExternal: IGrepCancellation;
  public
    constructor Create(Owner: TGrepReplacer; const External: IGrepCancellation);
    function IsCancellationRequested: Boolean;
  end;

  TReplaceValidationSink = class(TInterfacedObject, IGrepResultSink)
  private
    FExpected: TArray<TGrepMatch>;
    FSeen: TArray<Boolean>;
  public
    constructor Create(const Matches: TArray<TGrepMatch>);
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
    procedure CheckComplete;
  end;

function ReplaceFileAtomic(OriginalPath, TemporaryPath, BackupPath: PChar; Flags: DWORD; Exclude, Reserved: Pointer): BOOL; stdcall; external 'kernel32.dll' name 'ReplaceFileW';

function CompareMatches(const A, B: TGrepMatch): Integer;
begin
  Result := CompareText(A.SourcePath, B.SourcePath);
  if Result <> 0 then Exit;
  if A.ByteOffset < B.ByteOffset then Exit(-1);
  if A.ByteOffset > B.ByteOffset then Exit(1);
  if A.ByteLength < B.ByteLength then Exit(-1);
  if A.ByteLength > B.ByteLength then Exit(1);
  if A.PatternIndex < B.PatternIndex then Exit(-1);
  if A.PatternIndex > B.PatternIndex then Exit(1);
  Result := 0;
end;

constructor TReplaceCancellation.Create(Owner: TGrepReplacer; const External: IGrepCancellation);
begin
  inherited Create;
  FOwner := Owner;
  FExternal := External;
end;

function TReplaceCancellation.IsCancellationRequested: Boolean;
begin
  Result := FOwner.IsCancelled(FExternal);
end;

constructor TReplaceValidationSink.Create(const Matches: TArray<TGrepMatch>);
begin
  inherited Create;
  FExpected := Copy(Matches);
  SetLength(FSeen, Length(Matches));
end;

procedure TReplaceValidationSink.MatchFound(const Match: TGrepMatch);
var
  L, H, M, I: Integer;
begin
  L := 0;
  H := Length(FExpected);
  while L < H do
  begin
    M := L + (H - L) div 2;
    if CompareMatches(FExpected[M], Match) < 0 then L := M + 1 else H := M;
  end;
  I := L;
  while (I < Length(FExpected)) and (CompareMatches(FExpected[I], Match) = 0) do
  begin
    if (FExpected[I].Distance = Match.Distance) and not FSeen[I] then
    begin
      FSeen[I] := True;
      Break;
    end;
    Inc(I);
  end;
end;

procedure TReplaceValidationSink.ScanError(const SourcePath, ErrorText: string);
begin
  raise EInvalidOpException.Create(SourcePath + ': ' + ErrorText);
end;

procedure TReplaceValidationSink.CheckComplete;
var
  I: Integer;
begin
  for I := 0 to High(FSeen) do
    if not FSeen[I] then raise EInvalidOpException.CreateFmt('Search result is no longer valid at byte offset %d', [FExpected[I].ByteOffset]);
end;

function NewTemporaryPath(const Path: string): string;
var
  Id: TGUID;
begin
  if CreateGUID(Id) <> 0 then raise EInvalidOpException.Create('Cannot create temporary file name');
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(Path)) + '.nativegrep-' + GUIDToString(Id) + '.tmp';
end;

function CreateBackup(const Path: string): string;
var
  Index: Integer;
  Candidate: string;
  ErrorCode: DWORD;
begin
  Index := 1;
  while True do
  begin
    if Index = 1 then Candidate := Path + '.bak' else Candidate := Path + '.bak' + IntToStr(Index);
    if Winapi.Windows.GetFileAttributes(PChar(GrepWindowsPath(Candidate))) <> INVALID_FILE_ATTRIBUTES then
    begin
      if Index = MaxInt then raise EInvalidOpException.Create('Backup suffix exhausted');
      Inc(Index);
      Continue;
    end;
    if Winapi.Windows.CopyFile(PChar(GrepWindowsPath(Path)), PChar(GrepWindowsPath(Candidate)), True) then Exit(Candidate);
    ErrorCode := GetLastError;
    if (ErrorCode <> ERROR_FILE_EXISTS) and (ErrorCode <> ERROR_ALREADY_EXISTS) then
      RaiseLastOSError(ErrorCode);
    if Index = MaxInt then raise EInvalidOpException.Create('Backup suffix exhausted');
    Inc(Index);
  end;
end;

procedure CopyBytes(Source, Target: TStream; Count: Int64; const Cancellation: IGrepCancellation);
var
  Buffer: array[0..65535] of Byte;
  N: Integer;
begin
  while Count > 0 do
  begin
    if Cancellation.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
    N := SizeOf(Buffer);
    if Count < N then N := Integer(Count);
    Source.ReadBuffer(Buffer, N);
    Target.WriteBuffer(Buffer, N);
    Dec(Count, N);
  end;
end;

function EncodeReplacement(const Text: string; Encoding: TGrepEncoding; Stream: TStream): TBytes;
var
  B: array[0..1] of Byte;
  Count: Integer;
begin
  if Encoding = geAuto then
  begin
    Encoding := geUtf8;
    Stream.Position := 0;
    Count := Stream.Read(B, SizeOf(B));
    if Count = 2 then
    begin
      if (B[0] = $FF) and (B[1] = $FE) then Encoding := geUtf16LE
      else if (B[0] = $FE) and (B[1] = $FF) then Encoding := geUtf16BE;
    end;
  end;
  case Encoding of
    geUtf8: Result := TEncoding.UTF8.GetBytes(Text);
    geUtf16LE: Result := TEncoding.Unicode.GetBytes(Text);
    geUtf16BE: Result := TEncoding.BigEndianUnicode.GetBytes(Text);
  else
    raise EArgumentOutOfRangeException.Create('Unsupported replacement encoding');
  end;
  Stream.Position := 0;
end;

procedure ValidateMatches(const Request: TGrepRequest; const Path: string; Stream: TStream; const Matches: TArray<TGrepMatch>; const Cancellation: IGrepCancellation);
var
  CheckRequest: TGrepRequest;
  Validator: TReplaceValidationSink;
  Sink: IGrepResultSink;
begin
  CheckRequest := Request;
  CheckRequest.Options.SortResults := False;
  CheckRequest.Options.MaxResultsTotal := 0;
  CheckRequest.Options.MaxMatchesPerFile := 0;
  Validator := TReplaceValidationSink.Create(Matches);
  Sink := Validator;
  Stream.Position := 0;
  TNativeGrep.SearchStream(CheckRequest, Path, Stream, Sink, Cancellation);
  if Cancellation.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
  Validator.CheckComplete;
  Stream.Position := 0;
end;

procedure WriteReplacementFile(Source, Target: TStream; const Matches: TArray<TGrepMatch>; const Replacement: TBytes; const Cancellation: IGrepCancellation);
var
  I: Integer;
  PreviousEnd, Offset, MatchEnd: Int64;
begin
  PreviousEnd := 0;
  for I := 0 to High(Matches) do
  begin
    if Cancellation.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
    Offset := Matches[I].ByteOffset;
    if (Offset < 0) or (Offset > Source.Size) then
      raise EInvalidOpException.CreateFmt('Invalid replacement range at offset %d', [Offset]);
    if UInt64(Matches[I].ByteLength) > UInt64(Source.Size - Offset) then
      raise EInvalidOpException.CreateFmt('Invalid replacement length at offset %d', [Offset]);
    MatchEnd := Offset + Int64(Matches[I].ByteLength);
    if (Offset < PreviousEnd) or ((I > 0) and (Offset = Matches[I - 1].ByteOffset)) then
      raise EInvalidOpException.CreateFmt('Overlapping replacement ranges at offset %d', [Offset]);
    CopyBytes(Source, Target, Offset - PreviousEnd, Cancellation);
    Source.Position := MatchEnd;
    if Length(Replacement) > 0 then Target.WriteBuffer(Replacement[0], Length(Replacement));
    PreviousEnd := MatchEnd;
  end;
  CopyBytes(Source, Target, Source.Size - PreviousEnd, Cancellation);
end;

procedure TGrepReplacer.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TGrepReplacer.IsCancelled(const Cancellation: IGrepCancellation): Boolean;
begin
  Result := (TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0) or
    ((Cancellation <> nil) and Cancellation.IsCancellationRequested);
end;

function TGrepReplacer.ReplaceText(const Request: TGrepRequest; const Matches: TArray<TGrepMatch>; const Replacement: string; const Cancellation: IGrepCancellation): TGrepReplaceStatistics;
begin
  if not (Request.Query.Mode in [gmLiteralText, gmMultiText, gmFuzzyText, gmRegexText]) then
    raise EArgumentException.Create('ReplaceText requires a text search mode');
  Result := ExecuteInternal(Request, Matches, Replacement, nil, True, Cancellation);
end;

function TGrepReplacer.ReplaceBytes(const Request: TGrepRequest; const Matches: TArray<TGrepMatch>; const Replacement: TBytes; const Cancellation: IGrepCancellation): TGrepReplaceStatistics;
begin
  if not (Request.Query.Mode in [gmLiteralBytes, gmMultiBytes, gmMaskedHex, gmFuzzyBytes]) then
    raise EArgumentException.Create('ReplaceBytes requires a byte search mode');
  Result := ExecuteInternal(Request, Matches, '', Replacement, False, Cancellation);
end;

function TGrepReplacer.ExecuteInternal(const Request: TGrepRequest; const Matches: TArray<TGrepMatch>; const ReplacementText: string; const ReplacementBytes: TBytes; TextReplacement: Boolean; const Cancellation: IGrepCancellation): TGrepReplaceStatistics;
var
  Sorted, Chosen: TArray<TGrepMatch>;
  I, J, K, Index, FileCount: Integer;
  Attr, ErrorCode, RestoreError: DWORD;
  Path, TempPath, BackupPath: string;
  Source: TFileStream;
  Target: TFileStream;
  Bytes: TBytes;
  Token: IGrepCancellation;
  Skip, Stop, ContinueProcessing: Boolean;
  Completed: Boolean;
begin
  if TInterlocked.CompareExchange(FRunning, 1, 0) <> 0 then raise EInvalidOpException.Create('Replace is already running');
  TInterlocked.Exchange(FCancelled, 0);
  Result := Default(TGrepReplaceStatistics);
  try
    try
      Sorted := Copy(Matches);
      TArray.Sort<TGrepMatch>(Sorted, TComparer<TGrepMatch>.Construct(
        function(const A, B: TGrepMatch): Integer
        begin
          Result := CompareMatches(A, B);
        end));
      Result.MatchesTotal := Length(Sorted);
      FileCount := 0;
      for I := 0 to High(Sorted) do
      begin
        if I = 0 then Inc(FileCount)
        else if CompareText(Sorted[I].SourcePath, Sorted[I - 1].SourcePath) <> 0 then Inc(FileCount);
      end;
      Result.FilesTotal := FileCount;
      Token := TReplaceCancellation.Create(Self, Cancellation);
      I := 0;
      while I < Length(Sorted) do
      begin
        if Token.IsCancellationRequested then Break;
        J := I + 1;
        while (J < Length(Sorted)) and (CompareText(Sorted[I].SourcePath, Sorted[J].SourcePath) = 0) do Inc(J);
        Path := Sorted[I].SourcePath;
        try
          if Path = '' then raise EArgumentException.Create('Replacement source path must not be empty');
          Path := ExpandFileName(Path);
          Attr := Winapi.Windows.GetFileAttributes(PChar(GrepWindowsPath(Path)));
          if Attr = INVALID_FILE_ATTRIBUTES then RaiseLastOSError;
          if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then raise EInvalidOpException.Create('Cannot replace a directory');
          if (Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then raise EInvalidOpException.Create('Cannot replace a reparse point');
          SetLength(Chosen, J - I);
          Index := 0;
          for K := I to J - 1 do
          begin
            if Token.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
            Skip := False;
            Stop := False;
            if Assigned(FOnBeforeReplace) then FOnBeforeReplace(Self, Sorted[K], Skip, Stop);
            if Stop then Cancel;
            if Token.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
            if Skip then Inc(Result.MatchesSkipped)
            else
            begin
              Chosen[Index] := Sorted[K];
              Inc(Index);
            end;
          end;
          SetLength(Chosen, Index);
          if Index > 0 then
          begin
            for K := 1 to High(Chosen) do
              if (Chosen[K].ByteOffset < 0) or (Chosen[K - 1].ByteOffset < 0) or
                (Chosen[K].ByteOffset <= Chosen[K - 1].ByteOffset) or
                (UInt64(Chosen[K].ByteOffset) - UInt64(Chosen[K - 1].ByteOffset) < UInt64(Chosen[K - 1].ByteLength)) then
                raise EInvalidOpException.CreateFmt('Overlapping replacements at byte offset %d', [Chosen[K].ByteOffset]);
            TempPath := '';
            BackupPath := '';
            try
              Source := TFileStream.Create(GrepWindowsPath(Path), fmOpenRead or fmShareDenyWrite);
              try
                ValidateMatches(Request, Sorted[I].SourcePath, Source, Chosen, Token);
                if TextReplacement then Bytes := EncodeReplacement(ReplacementText, Request.Query.Encoding, Source)
                else Bytes := Copy(ReplacementBytes);
                TempPath := NewTemporaryPath(Path);
                Target := TFileStream.Create(GrepWindowsPath(TempPath), fmCreate);
                try
                  Source.Position := 0;
                  WriteReplacementFile(Source, Target, Chosen, Bytes, Token);
                finally
                  Target.Free;
                end;
                if Token.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
                BackupPath := CreateBackup(Path);
                Inc(Result.BackupsCreated);
              finally
                Source.Free;
              end;
              if Token.IsCancellationRequested then raise EAbort.Create('Replace cancelled');
              if not ReplaceFileAtomic(PChar(GrepWindowsPath(Path)), PChar(GrepWindowsPath(TempPath)), nil, 0, nil, nil) then
              begin
                ErrorCode := GetLastError;
                if not FileExists(GrepWindowsPath(Path)) then
                begin
                  if not Winapi.Windows.CopyFile(PChar(GrepWindowsPath(BackupPath)), PChar(GrepWindowsPath(Path)), True) then
                  begin
                    RestoreError := GetLastError;
                    raise EInvalidOpException.CreateFmt('ReplaceFileW failed (%d); backup recovery failed (%d): %s', [ErrorCode, RestoreError, BackupPath]);
                  end;
                end;
                RaiseLastOSError(ErrorCode);
              end;
              Inc(Result.FilesChanged);
              Inc(Result.MatchesReplaced, Length(Chosen));
              for K := 0 to High(Chosen) do
                if Assigned(FOnAfterReplace) then FOnAfterReplace(Self, Chosen[K], BackupPath);
            finally
              if (TempPath <> '') and FileExists(GrepWindowsPath(TempPath)) then Winapi.Windows.DeleteFile(PChar(GrepWindowsPath(TempPath)));
            end;
          end;
        except
          on E: EAbort do
          begin
            if Token.IsCancellationRequested then Break;
            raise;
          end;
          on E: Exception do
          begin
            Inc(Result.Errors);
            Result.Failed := True;
            ContinueProcessing := False;
            if Assigned(FOnError) then FOnError(Self, Path, E.ClassName + ': ' + E.Message, ContinueProcessing);
            if not ContinueProcessing then raise;
          end;
        end;
        Inc(Result.FilesProcessed);
        if Assigned(FOnProgress) then FOnProgress(Self, Path, Result);
        I := J;
      end;
      Result.Cancelled := Token.IsCancellationRequested;
      Completed := not Result.Cancelled and not Result.Failed and (Result.MatchesReplaced + Result.MatchesSkipped = Result.MatchesTotal);
      if Completed and (Result.MatchesSkipped = 0) and Assigned(FOnAllReplaced) then FOnAllReplaced(Self, Result);
    except
      on E: Exception do
      begin
        Result.Failed := True;
        raise;
      end;
    end;
  finally
    Result.Cancelled := IsCancelled(Cancellation);
    if Assigned(FOnCompleted) then
      try
        FOnCompleted(Self, Result);
      finally
        TInterlocked.Exchange(FRunning, 0);
      end
    else TInterlocked.Exchange(FRunning, 0);
  end;
end;

end.
