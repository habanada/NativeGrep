program npgrep;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, System.JSON, Winapi.Windows,
  NativeGrep.Types, NativeGrep.Api, NativeGrep.Context;

type
  TConsoleSink = class(TInterfacedObject, IGrepResultSink)
  private
    FQuery: TGrepQuery;
    FQuiet: Boolean;
    FJsonl: Boolean;
    FCountOnly: Boolean;
    FFilesOnly: Boolean;
    FShowLines: Boolean;
    FBefore: Integer;
    FAfter: Integer;
    FCounts: TDictionary<string, Int64>;
  public
    constructor Create(const Query: TGrepQuery; Quiet, Jsonl, CountOnly, FilesOnly: Boolean; ShowLines: Boolean; BeforeCount, AfterCount: Integer);
    destructor Destroy; override;
    procedure Finish;
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
  end;

  TConsoleCancellation = class(TInterfacedObject, IGrepCancellation)
  public
    function IsCancellationRequested: Boolean;
  end;

var
  Interrupted: Integer;

function ControlHandler(Code: DWORD): BOOL; stdcall;
begin
  Result := (Code = CTRL_C_EVENT) or (Code = CTRL_BREAK_EVENT);
  if Result then TInterlocked.Exchange(Interrupted, 1);
end;

function TConsoleCancellation.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(Interrupted, 0, 0) <> 0;
end;

procedure WriteUtf8(Handle: THandle; const Value: string);
var
  Buffer: TBytes;
  Offset, Written, Count: DWORD;
begin
  Buffer := TEncoding.UTF8.GetBytes(Value);
  Offset := 0;
  while Offset < DWORD(Length(Buffer)) do
  begin
    Count := DWORD(Length(Buffer)) - Offset;
    if not WriteFile(Handle, Buffer[Offset], Count, Written, nil) then
      raise EOSError.Create(SysErrorMessage(GetLastError));
    if Written = 0 then raise EWriteError.Create('Output stream closed');
    Inc(Offset, Written);
  end;
end;

procedure StdOut(const Value: string);
begin
  WriteUtf8(GetStdHandle(STD_OUTPUT_HANDLE), Value + #10);
end;

procedure StdErr(const Value: string);
begin
  WriteUtf8(GetStdHandle(STD_ERROR_HANDLE), Value + #10);
end;

function JsonString(const Value: string): string;
var
  J: TJSONString;
begin
  J := TJSONString.Create(Value);
  try
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

constructor TConsoleSink.Create(const Query: TGrepQuery; Quiet, Jsonl, CountOnly, FilesOnly: Boolean; ShowLines: Boolean; BeforeCount, AfterCount: Integer);
begin
  inherited Create;
  FQuery := Query;
  FQuiet := Quiet;
  FJsonl := Jsonl;
  FCountOnly := CountOnly;
  FFilesOnly := FilesOnly;
  FShowLines := ShowLines;
  FBefore := BeforeCount;
  FAfter := AfterCount;
  FCounts := TDictionary<string, Int64>.Create;
end;

destructor TConsoleSink.Destroy;
begin
  FCounts.Free;
  inherited;
end;

procedure TConsoleSink.Finish;
var
  Paths: TArray<string>;
  Path: string;
  I: Integer;
  N: Int64;
begin
  if FQuiet or not (FCountOnly or FFilesOnly) then Exit;
  SetLength(Paths, FCounts.Count);
  I := 0;
  for Path in FCounts.Keys do
  begin
    Paths[I] := Path;
    Inc(I);
  end;
  TArray.Sort<string>(Paths);
  for Path in Paths do
  begin
    N := FCounts[Path];
    if FJsonl then StdOut('{"type":"count","path":' + JsonString(Path) + ',"count":' + IntToStr(N) + '}')
    else if FCountOnly then StdOut(Path + ':' + IntToStr(N))
    else StdOut(Path);
  end;
end;

function SafeLineText(const Value: string): string;
var
  I, B: Integer;
begin
  Result := '';
  for I := 1 to Length(Value) do
  begin
    B := Ord(Value[I]);
    if B = 9 then Result := Result + '\t'
    else if (B < 32) or (B = 127) then Result := Result + '\x' + IntToHex(B, 2)
    else Result := Result + Value[I];
  end;
end;

procedure TConsoleSink.MatchFound(const Match: TGrepMatch);
var
  S, TextValue, ContextJson: string;
  N: Int64;
  Lines: TArray<TGrepContextLine>;
  L: TGrepContextLine;
  Capture: TGrepCapture;
  CaptureJson: string;
  HasContext: Boolean;
  Marker: Char;
begin
  if FCountOnly or FFilesOnly then
  begin
    if not FCounts.TryGetValue(Match.SourcePath, N) then N := 0;
    FCounts.AddOrSetValue(Match.SourcePath, N + 1);
    Exit;
  end;
  if FQuiet then Exit;
  HasContext := False;
  if FShowLines and (Match.Line > 0) then
  begin
    try
      Lines := TGrepContextReader.ReadFile(Match, FQuery.Encoding, FBefore, FAfter);
      HasContext := True;
    except
      on E: Exception do StdErr('npgrep: context ' + Match.SourcePath + ': ' + E.ClassName + ': ' + E.Message);
    end;
  end;
  if FJsonl then
  begin
    S := '{"type":"match","path":' + JsonString(Match.SourcePath) + ',"offset":' + IntToStr(Match.ByteOffset) +
      ',"length":' + UIntToStr(Match.ByteLength) + ',"line":' + IntToStr(Match.Line) +
      ',"column":' + IntToStr(Match.Column) + ',"patternIndex":' + IntToStr(Match.PatternIndex) +
      ',"distance":' + IntToStr(Match.Distance) + '}';
    if FQuery.Mode = gmRegexText then
    begin
      CaptureJson := '';
      for Capture in Match.Captures do
      begin
        if CaptureJson <> '' then CaptureJson := CaptureJson + ',';
        CaptureJson := CaptureJson + '{"index":' + IntToStr(Capture.Index) + ',"matched":' +
          LowerCase(BoolToStr(Capture.Matched, True)) + ',"offset":' + IntToStr(Capture.ByteOffset) +
          ',"length":' + UIntToStr(Capture.ByteLength) + '}';
      end;
      SetLength(S, Length(S) - 1);
      S := S + ',"captures":[' + CaptureJson + ']}';
    end;
    if HasContext then
    begin
      ContextJson := '';
      for L in Lines do
      begin
        if ContextJson <> '' then ContextJson := ContextJson + ',';
        ContextJson := ContextJson + '{"line":' + IntToStr(L.Line) + ',"text":' + JsonString(L.Text) +
          ',"match":' + LowerCase(BoolToStr(L.IsMatch, True)) + ',"truncated":' + LowerCase(BoolToStr(L.Truncated, True)) + '}';
      end;
      SetLength(S, Length(S) - 1);
      S := S + ',"context":[' + ContextJson + ']}';
    end;
    StdOut(S);
    Exit;
  end;
  if HasContext then
  begin
    for L in Lines do
    begin
      if L.IsMatch then Marker := ':' else Marker := '-';
      StdOut(Match.SourcePath + Marker + IntToStr(L.Line) + Marker + SafeLineText(L.Text));
    end;
    Exit;
  end;
  if (FQuery.Mode = gmRegexText) and (Match.Line <> 0) then
    S := Match.SourcePath + ':' + IntToStr(Match.Line) + ':' + IntToStr(Match.Column) + ':@0x' +
      IntToHex(Match.ByteOffset, 1) + ':' + UIntToStr(Match.ByteLength)
  else if (FQuery.Mode in [gmLiteralText, gmMultiText, gmFuzzyText]) and (Match.Line <> 0) then
  begin
    if FQuery.Mode = gmMultiText then TextValue := FQuery.TextPatterns[Match.PatternIndex]
    else TextValue := FQuery.Text;
    TextValue := StringReplace(TextValue, #13, '\r', [rfReplaceAll]);
    TextValue := StringReplace(TextValue, #10, '\n', [rfReplaceAll]);
    S := Match.SourcePath + ':' + IntToStr(Match.Line) + ':' + IntToStr(Match.Column) + ':' + TextValue;
    if FQuery.Mode = gmFuzzyText then S := S + ' [distance=' + IntToStr(Match.Distance) + ']';
  end
  else
    S := Match.SourcePath + ':@0x' + IntToHex(Match.ByteOffset, 1) + ':' + UIntToStr(Match.ByteLength);
  StdOut(S);
end;

procedure TConsoleSink.ScanError(const SourcePath, ErrorText: string);
begin
  if FJsonl and not FQuiet then StdOut('{"type":"error","path":' + JsonString(SourcePath) + ',"message":' + JsonString(ErrorText) + '}')
  else StdErr('npgrep: ' + SourcePath + ': ' + ErrorText);
end;

procedure AddString(var Values: TArray<string>; const Value: string);
var
  N: Integer;
begin
  N := Length(Values);
  SetLength(Values, N + 1);
  Values[N] := Value;
end;

procedure Help;
begin
  StdOut('NativeGrep CLI - native Delphi file search');
  StdOut('Usage: npgrep [options] PATTERN [FILE_OR_DIRECTORY ...]');
  StdOut('       npgrep -e PATTERN -e PATTERN [PATH ...]');
  StdOut('       npgrep --hex "48 8B ?? ?? 48 85 C0" [PATH ...]');
  StdOut('Options:');
  StdOut('  -r, --recursive          Search directories recursively');
  StdOut('  -e, --pattern TEXT       Repeated literal text pattern');
  StdOut('  --fuzzy N               Maximum Levenshtein distance');
  StdOut('  --regex                 Use PCRE2 regular expressions (requires pcre2-8.dll)');
  StdOut('  --regex-invalid-utf     Search valid UTF-8 regions despite invalid input bytes');
  StdOut('  --regex-max-mib N       Max bytes per regex source (default 64 MiB, max 1024)');
  StdOut('  --regex-match-limit N   PCRE2 backtracking limit (default 1000000)');
  StdOut('  --regex-depth-limit N   PCRE2 depth limit (default 1000)');
  StdOut('  --fuzzy-unit codepoints Unicode scalar distance (<=8 edits, <=256 scalars)');
  StdOut('  --ignore-case=unicode   Full Unicode case folding with NFD');
  StdOut('  --normalize=nfd         Canonical decomposition with byte mapping');
  StdOut('  --encoding NAME         auto, utf8, utf16le, utf16be');
  StdOut('  -i, --ignore-case=ascii ASCII-only insensitive matching');
  StdOut('  --hex SIGNATURE         Masked hex search');
  StdOut('  --stdin                  Search standard input instead of files');
  StdOut('  --binary=auto|text|raw   UTF-8 binary detection, forced text, or raw offsets');
  StdOut('  --threads N              Workers: 0=auto, 1..64');
  StdOut('  --buffer-kib N           Read buffer in KiB (4..16384)');
  StdOut('  --include MASK           Filename or relative-path glob; repeatable');
  StdOut('  --exclude MASK           Filename or relative-path glob; repeatable');
  StdOut('  --hidden                 Include hidden/system entries');
  StdOut('  --max-count N            Maximum matches per file');
  StdOut('  --max-results N          Maximum total matches');
  StdOut('  --max-file-size N        Maximum file length in bytes');
  StdOut('  --line-text              Print the original matching line');
  StdOut('  -A N, -B N, -C N        Lines after, before, or around each match (0..32)');
  StdOut('  --count                  Counts for matched files');
  StdOut('  --files-with-matches     Output names of matched files');
  StdOut('  --jsonl                  Structured match/error events');
  StdOut('  --sort                   Sort matches by path, byte offset and pattern');
  StdOut('  --stats                  Print counters to stderr');
  StdOut('  --profile                Detailed microsecond timings');
  StdOut('  --quiet                  Suppress matches');
  StdOut('  -h, --help               Show help');
  StdOut('Path glob: * and ? match a name; ** matches multiple directory levels.');
  StdOut('Auto encoding recognizes UTF-16LE/BE BOM; otherwise uses UTF-8.');
  StdOut('Context is per match, may repeat overlapping lines, and is file-only.');
  StdOut('Context reads bounded windows and abbreviates exceptionally long lines.');
  StdOut('Sorted matches use temporary disk runs; errors are reported immediately.');
  StdOut('--sort remains active with --quiet and --count; it can require extra disk space.');
  StdOut('--max-results with --sort limits sorted output after scanning all files.');
  StdOut('Text searches are literal unless --regex is selected.');
  StdOut('Regex accepts UTF-8 sources, including BOM. UTF-16 regex is not yet supported.');
  StdOut('--regex-invalid-utf keeps valid UTF-8 segments; positions are byte-only for malformed sources.');
  StdOut('Regex can span lines; file size is explicitly limited in regex mode.');
  StdOut('Default fuzzy distance counts UTF-8 bytes; --fuzzy-unit codepoints counts scalars.');
  StdOut('Unicode folding and NFD use Unicode 15.1; source offsets stay in original bytes.');
  StdOut('Exit codes: 0=matches, 1=no matches, 2=error, 130=Ctrl+C.');
end;

function NextArg(var Index: Integer; const OptionName: string): string;
begin
  if Index >= ParamCount then raise EArgumentException.Create(OptionName + ' requires a value');
  Inc(Index);
  Result := ParamStr(Index);
end;

function ReadNonnegative(const Value, Name: string): Int64;
begin
  if not TryStrToInt64(Value, Result) or (Result < 0) then
    raise EArgumentException.Create('Invalid nonnegative value for ' + Name + ': ' + Value);
end;

function Run: Integer;
var
  Request: TGrepRequest;
  Sink: IGrepResultSink;
  ConsoleSink: TConsoleSink;
  CancelToken: IGrepCancellation;
  Stats: TGrepStatistics;
  Input: THandleStream;
  I, Distance, BeforeCount, AfterCount: Integer;
  Arg, Value: string;
  Patterns: TArray<string>;
  HasPattern, ShowStats, Quiet, StdinMode, Jsonl, CountOnly, FilesOnly, HexMode, AfterDoubleDash, EncodingSpecified, ShowLines, RegexMode: Boolean;
  N: Int64;
begin
  Request := Default(TGrepRequest);
  Request.Query.Mode := gmLiteralText;
  Request.Query.Encoding := geAuto;
  ShowStats := False;
  Quiet := False;
  StdinMode := False;
  Jsonl := False;
  CountOnly := False;
  FilesOnly := False;
  HexMode := False;
  RegexMode := False;
  HasPattern := False;
  AfterDoubleDash := False;
  EncodingSpecified := False;
  Distance := -1;
  BeforeCount := 0;
  AfterCount := 0;
  ShowLines := False;
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if not AfterDoubleDash and (Arg = '--') then AfterDoubleDash := True
    else if not AfterDoubleDash and ((Arg = '-h') or (Arg = '--help')) then
    begin
      Help;
      Exit(0);
    end
    else if not AfterDoubleDash and ((Arg = '-r') or (Arg = '--recursive')) then Request.Options.Recursive := True
    else if not AfterDoubleDash and (Arg = '--hidden') then Request.Options.IncludeHidden := True
    else if not AfterDoubleDash and (Arg = '--stats') then ShowStats := True
    else if not AfterDoubleDash and (Arg = '--quiet') then Quiet := True
    else if not AfterDoubleDash and (Arg = '--profile') then
    begin
      ShowStats := True;
      Request.Options.Profile := True;
    end
    else if not AfterDoubleDash and (Arg = '--line-text') then ShowLines := True
    else if not AfterDoubleDash and ((Arg = '-A') or (Arg = '-B') or (Arg = '-C')) then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if N > 32 then raise EArgumentException.Create('Context line count must be between 0 and 32');
      ShowLines := True;
      if Arg = '-A' then AfterCount := Integer(N)
      else if Arg = '-B' then BeforeCount := Integer(N)
      else
      begin
        BeforeCount := Integer(N);
        AfterCount := Integer(N);
      end;
    end
    else if not AfterDoubleDash and (Arg = '--stdin') then StdinMode := True
    else if not AfterDoubleDash and (Arg = '--regex') then RegexMode := True
    else if not AfterDoubleDash and (Arg = '--regex-invalid-utf') then Request.Query.RegexAllowInvalidUtf8 := True
    else if not AfterDoubleDash and (Arg = '--regex-max-mib') then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if (N < 1) or (N > 1024) then raise EArgumentException.Create('--regex-max-mib must be 1..1024');
      Request.Options.RegexMaxBytes := N * 1024 * 1024;
    end
    else if not AfterDoubleDash and (Arg = '--regex-match-limit') then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if (N < 1) or (N > High(Cardinal)) then raise EArgumentException.Create('--regex-match-limit must be 1..4294967295');
      Request.Options.RegexMatchLimit := Cardinal(N);
    end
    else if not AfterDoubleDash and (Arg = '--regex-depth-limit') then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if (N < 1) or (N > High(Cardinal)) then raise EArgumentException.Create('--regex-depth-limit must be 1..4294967295');
      Request.Options.RegexDepthLimit := Cardinal(N);
    end
    else if not AfterDoubleDash and (Copy(Arg, 1, 9) = '--binary=') then
    begin
      Value := LowerCase(Copy(Arg, 10, MaxInt));
      if Value = 'auto' then Request.Options.BinaryPolicy := gbAuto
      else if Value = 'text' then Request.Options.BinaryPolicy := gbText
      else if Value = 'raw' then Request.Options.BinaryPolicy := gbRaw
      else raise EArgumentException.Create('Unknown binary policy: ' + Value);
    end
    else if not AfterDoubleDash and (Arg = '--jsonl') then Jsonl := True
    else if not AfterDoubleDash and (Arg = '--sort') then Request.Options.SortResults := True
    else if not AfterDoubleDash and (Arg = '--count') then CountOnly := True
    else if not AfterDoubleDash and (Arg = '--files-with-matches') then FilesOnly := True
    else if not AfterDoubleDash and ((Arg = '-i') or (Arg = '--ignore-case=ascii')) then Request.Query.CaseInsensitiveAscii := True
    else if not AfterDoubleDash and (Arg = '--ignore-case=unicode') then Request.Query.UnicodeCaseFold := True
    else if not AfterDoubleDash and (Arg = '--normalize=nfd') then Request.Query.UnicodeNormalizeNfd := True
    else if not AfterDoubleDash and (Arg = '--fuzzy-unit') then
    begin
      Value := LowerCase(NextArg(I, Arg));
      if Value = 'codepoints' then Request.Query.FuzzyCodePoints := True
      else if Value = 'bytes' then Request.Query.FuzzyCodePoints := False
      else raise EArgumentException.Create('Unknown fuzzy distance unit: ' + Value);
    end
    else if not AfterDoubleDash and ((Arg = '-e') or (Arg = '--pattern')) then
    begin
      if HexMode then raise EArgumentException.Create('Text and hex patterns cannot be combined');
      AddString(Patterns, NextArg(I, Arg));
      HasPattern := True;
    end
    else if not AfterDoubleDash and (Arg = '--fuzzy') then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if N > 4096 then raise EArgumentException.Create('Fuzzy distance must be <=4096');
      Distance := Integer(N);
    end
    else if not AfterDoubleDash and (Arg = '--encoding') then
    begin
      EncodingSpecified := True;
      Value := LowerCase(NextArg(I, Arg));
      if Value = 'auto' then Request.Query.Encoding := geAuto
      else if Value = 'utf8' then Request.Query.Encoding := geUtf8
      else if Value = 'utf16le' then Request.Query.Encoding := geUtf16LE
      else if Value = 'utf16be' then Request.Query.Encoding := geUtf16BE
      else raise EArgumentException.Create('Unknown encoding: ' + Value);
    end
    else if not AfterDoubleDash and (Arg = '--threads') then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if N > 64 then raise EArgumentException.Create('Threads must be in range 0..64');
      Request.Options.MaxWorkers := Integer(N);
    end
    else if not AfterDoubleDash and (Arg = '--buffer-kib') then
    begin
      N := ReadNonnegative(NextArg(I, Arg), Arg);
      if (N < 4) or (N > 16384) then raise EArgumentException.Create('Buffer must be in range 4..16384 KiB');
      Request.Options.BufferSize := Integer(N) * 1024;
    end
    else if not AfterDoubleDash and (Arg = '--include') then AddString(Request.Options.Includes, NextArg(I, Arg))
    else if not AfterDoubleDash and (Arg = '--exclude') then AddString(Request.Options.Excludes, NextArg(I, Arg))
    else if not AfterDoubleDash and (Arg = '--max-count') then Request.Options.MaxMatchesPerFile := ReadNonnegative(NextArg(I, Arg), Arg)
    else if not AfterDoubleDash and (Arg = '--max-results') then Request.Options.MaxResultsTotal := ReadNonnegative(NextArg(I, Arg), Arg)
    else if not AfterDoubleDash and (Arg = '--max-file-size') then Request.Options.MaxFileSize := ReadNonnegative(NextArg(I, Arg), Arg)
    else if not AfterDoubleDash and (Arg = '--hex') then
    begin
      if HasPattern then raise EArgumentException.Create('Text and hex patterns cannot be combined');
      Request.Query.Mode := gmMaskedHex;
      Request.Query.HexSignature := NextArg(I, Arg);
      HasPattern := True;
      HexMode := True;
    end
    else if not AfterDoubleDash and (Length(Arg) > 0) and (Arg[1] = '-') then
      raise EArgumentException.Create('Unknown option: ' + Arg)
    else if not HasPattern then
    begin
      AddString(Patterns, Arg);
      HasPattern := True;
    end
    else AddString(Request.Options.Roots, Arg);
    Inc(I);
  end;
  if not HasPattern then raise EArgumentException.Create('Pattern is required; use --help');
  if Request.Query.RegexAllowInvalidUtf8 and not RegexMode then
    raise EArgumentException.Create('--regex-invalid-utf requires --regex');
  if CountOnly and FilesOnly then raise EArgumentException.Create('--count and --files-with-matches are mutually exclusive');
  if RegexMode then
  begin
    if HexMode or (Distance >= 0) or (Length(Patterns) <> 1) then
      raise EArgumentException.Create('--regex requires exactly one text pattern without --hex or --fuzzy');
    if Request.Query.CaseInsensitiveAscii then
      raise EArgumentException.Create('Use --ignore-case=unicode for regex searches');
    if Request.Query.UnicodeNormalizeNfd or Request.Query.FuzzyCodePoints then
      raise EArgumentException.Create('NFD and fuzzy options are not supported with regex');
    if not (Request.Query.Encoding in [geAuto, geUtf8]) then
      raise EArgumentException.Create('Regex currently supports UTF-8 only');
    Request.Query.Mode := gmRegexText;
    Request.Query.Text := Patterns[0];
  end
  else if HexMode then
  begin
    Request.Query.Encoding := geUtf8;
    if Distance >= 0 then raise EArgumentException.Create('Fuzzy hex search is not supported');
    if Request.Query.CaseInsensitiveAscii then raise EArgumentException.Create('ASCII casefold is not valid for masked hex');
  end
  else
  begin
    if Length(Patterns) > 1 then
    begin
      if Distance >= 0 then raise EArgumentException.Create('Fuzzy multi-pattern search is not supported');
      Request.Query.Mode := gmMultiText;
      Request.Query.TextPatterns := Patterns;
    end
    else
    begin
      Request.Query.Text := Patterns[0];
      if Distance >= 0 then
      begin
        Request.Query.Mode := gmFuzzyText;
        Request.Query.MaxDistance := Distance;
        if (Request.Query.Encoding = geAuto) and not Request.Query.FuzzyCodePoints then
        begin
          if EncodingSpecified then raise EArgumentException.Create('Fuzzy text requires --encoding utf8');
          Request.Query.Encoding := geUtf8;
        end;
      end;
    end;
  end;
  if Request.Query.FuzzyCodePoints and (Distance < 0) then
    raise EArgumentException.Create('--fuzzy-unit codepoints requires --fuzzy');
  if Quiet or CountOnly or FilesOnly then
  begin
    Request.Options.TextPositions := gtpNone;
  end;
  if ShowLines and StdinMode then raise EArgumentException.Create('Context output is not available for --stdin');
  if ShowLines and (CountOnly or FilesOnly) then raise EArgumentException.Create('Context output cannot be combined with --count or --files-with-matches');
  if ShowLines and HexMode then raise EArgumentException.Create('Context output is only available for text patterns');
  if StdinMode and (Length(Request.Options.Roots) > 0) then raise EArgumentException.Create('--stdin cannot be combined with paths');
  if not StdinMode and (Length(Request.Options.Roots) = 0) then AddString(Request.Options.Roots, '.');
  SetConsoleOutputCP(CP_UTF8);
  ConsoleSink := TConsoleSink.Create(Request.Query, Quiet, Jsonl, CountOnly, FilesOnly, ShowLines, BeforeCount, AfterCount);
  Sink := ConsoleSink;
  CancelToken := TConsoleCancellation.Create;
  SetConsoleCtrlHandler(@ControlHandler, True);
  try
    if StdinMode then
    begin
      Input := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
      try
        Stats := TNativeGrep.SearchStream(Request, '<stdin>', Input, Sink, CancelToken);
      finally
        Input.Free;
      end;
    end
    else Stats := TNativeGrep.Search(Request, Sink, CancelToken);
    ConsoleSink.Finish;
  finally
    SetConsoleCtrlHandler(@ControlHandler, False);
  end;
  if ShowStats then StdErr(Format('files=%d/%d bytes=%d matches=%d errors=%d workers=%d elapsed_ms=%d',
    [Stats.FilesScanned, Stats.FilesEnumerated, Stats.BytesScanned, Stats.Matches, Stats.Errors, Stats.WorkerCount, Stats.ElapsedMs]));
  if Stats.ProfileEnabled then
    StdErr(Format('profile_us discovery_wall=%d discovery_enqueue=%d compile_workers=%d file_open_workers=%d buffer_setup_workers=%d buffer_allocations=%d file_read_workers=%d matching_workers=%d text_position_workers=%d result_enqueue_workers=%d file_scan_workers=%d work_queue_wait_workers=%d sink_dispatch=%d binary_raw_sources=%d',
      [Stats.DiscoveryWallUs, Stats.DiscoveryEnqueueUs, Stats.CompileWorkerUs, Stats.FileOpenWorkerUs, Stats.BufferSetupWorkerUs, Stats.BufferAllocations, Stats.FileReadWorkerUs, Stats.MatchWorkerUs,
       Stats.TextPositionWorkerUs, Stats.ResultEnqueueWorkerUs, Stats.FileScanWorkerUs, Stats.WorkQueueWaitWorkerUs, Stats.SinkDispatchUs, Stats.BinaryRawSources]));
  if TInterlocked.CompareExchange(Interrupted, 0, 0) <> 0 then Exit(130);
  if Stats.Errors > 0 then Exit(2);
  if Stats.Matches > 0 then Exit(0);
  Result := 1;
end;

begin
  try
    System.ExitCode := Run;
  except
    on E: Exception do
    begin
      try
        StdErr('npgrep: ' + E.ClassName + ': ' + E.Message);
      except
      end;
      System.ExitCode := 2;
    end;
  end;
end.
