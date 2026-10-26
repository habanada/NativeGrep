unit NativeGrep.Replace.Tests;

interface

procedure RunReplaceTests(const Dir: string);

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  NativeGrep.Types, NativeGrep.Api, NativeGrep.Replace;

type
  TReplaceCollectSink = class(TInterfacedObject, IGrepResultSink)
  private
    FMatches: TList<TGrepMatch>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
    property Matches: TList<TGrepMatch> read FMatches;
  end;

  TReplaceEventProbe = class
  public
    BeforeCount: Integer;
    AfterCount: Integer;
    ProgressCount: Integer;
    CompletedCount: Integer;
    AllReplacedCount: Integer;
    SkipAfterFirst: Boolean;
    CancelBefore: Boolean;
    CancelAfterProgress: Boolean;
    LastBackup: string;
    ErrorCount: Integer;
    ContinueAfterError: Boolean;
    LastStatistics: TGrepReplaceStatistics;
    procedure BeforeReplace(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean);
    procedure AfterReplace(Sender: TObject; const Match: TGrepMatch; const BackupPath: string);
    procedure Progress(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics);
    procedure Completed(Sender: TObject; const Statistics: TGrepReplaceStatistics);
    procedure AllReplaced(Sender: TObject; const Statistics: TGrepReplaceStatistics);
    procedure Error(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean);
  end;

constructor TReplaceCollectSink.Create;
begin
  inherited Create;
  FMatches := TList<TGrepMatch>.Create;
end;

destructor TReplaceCollectSink.Destroy;
begin
  FMatches.Free;
  inherited;
end;

procedure TReplaceCollectSink.MatchFound(const Match: TGrepMatch);
begin
  FMatches.Add(Match);
end;

procedure TReplaceCollectSink.ScanError(const SourcePath, ErrorText: string);
begin
  raise Exception.Create(SourcePath + ': ' + ErrorText);
end;

procedure TReplaceEventProbe.BeforeReplace(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean);
begin
  Inc(BeforeCount);
  Skip := SkipAfterFirst and (BeforeCount > 1);
  Cancel := CancelBefore;
end;

procedure TReplaceEventProbe.AfterReplace(Sender: TObject; const Match: TGrepMatch; const BackupPath: string);
begin
  Inc(AfterCount);
  LastBackup := BackupPath;
end;

procedure TReplaceEventProbe.Progress(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics);
begin
  Inc(ProgressCount);
  if CancelAfterProgress then TGrepReplacer(Sender).Cancel;
end;

procedure TReplaceEventProbe.Completed(Sender: TObject; const Statistics: TGrepReplaceStatistics);
begin
  Inc(CompletedCount);
  LastStatistics := Statistics;
end;

procedure TReplaceEventProbe.AllReplaced(Sender: TObject; const Statistics: TGrepReplaceStatistics);
begin
  Inc(AllReplacedCount);
end;

procedure TReplaceEventProbe.Error(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean);
begin
  Inc(ErrorCount);
  ContinueProcessing := ContinueAfterError;
end;

procedure Require(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: ' + Name);
end;

procedure RequireCount(Actual, Expected: Int64; const Name: string);
begin
  if Actual <> Expected then raise Exception.CreateFmt('FAIL: %s, expected %d, actual %d', [Name, Expected, Actual]);
end;

function RequestFor(const Path, Pattern: string): TGrepRequest;
begin
  Result := Default(TGrepRequest);
  Result.Query.Mode := gmLiteralText;
  Result.Query.Text := Pattern;
  Result.Query.Encoding := geUtf8;
  Result.Options.Roots := [Path];
  Result.Options.MaxWorkers := 1;
  Result.Options.BufferSize := 4096;
end;

function SearchMatches(const Request: TGrepRequest): TArray<TGrepMatch>;
var
  Collector: TReplaceCollectSink;
  Sink: IGrepResultSink;
begin
  Collector := TReplaceCollectSink.Create;
  Sink := Collector;
  TNativeGrep.Search(Request, Sink);
  Result := Collector.Matches.ToArray;
end;

procedure SaveUtf8(const Path, Text: string);
begin
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
end;

function LoadUtf8(const Path: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(Path));
end;

procedure SetProbe(Replacer: TGrepReplacer; Probe: TReplaceEventProbe);
begin
  Replacer.OnBeforeReplace := Probe.BeforeReplace;
  Replacer.OnAfterReplace := Probe.AfterReplace;
  Replacer.OnProgress := Probe.Progress;
  Replacer.OnCompleted := Probe.Completed;
  Replacer.OnAllReplaced := Probe.AllReplaced;
  Replacer.OnError := Probe.Error;
end;

procedure TestBackups(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TReplaceEventProbe;
  Stats: TGrepReplaceStatistics;
begin
  Path := TPath.Combine(Dir, 'replace-backups.txt');
  SaveUtf8(Path, 'TODO TODO');
  Replacer := TGrepReplacer.Create;
  Probe := TReplaceEventProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Request := RequestFor(Path, 'TODO');
    Matches := SearchMatches(Request);
    RequireCount(Length(Matches), 2, 'replace initial hits');
    Stats := Replacer.ReplaceText(Request, Matches, 'X');
    RequireCount(Stats.MatchesReplaced, 2, 'replace first count');
    RequireCount(Stats.BackupsCreated, 1, 'replace first backup');
    Require(LoadUtf8(Path) = 'X X', 'replace initial contents');
    Require(LoadUtf8(Path + '.bak') = 'TODO TODO', 'replace original backup');
    RequireCount(Probe.BeforeCount, 2, 'replace before events');
    RequireCount(Probe.AfterCount, 2, 'replace after events');
    RequireCount(Probe.CompletedCount, 1, 'replace completion event');
    RequireCount(Probe.AllReplacedCount, 1, 'replace all event');
    Require(Probe.LastBackup = Path + '.bak', 'replace event backup name');
    Request.Query.Text := 'X';
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), 'Y');
    RequireCount(Stats.MatchesReplaced, 2, 'replace second count');
    Require(LoadUtf8(Path + '.bak2') = 'X X', 'replace second backup');
    Require(LoadUtf8(Path + '.bak') = 'TODO TODO', 'replace existing backup intact');
    Request.Query.Text := 'Y';
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), 'Z');
    RequireCount(Stats.BackupsCreated, 1, 'replace third backup count');
    Require(LoadUtf8(Path + '.bak3') = 'Y Y', 'replace third backup');
    Require(LoadUtf8(Path) = 'Z Z', 'replace third contents');
  finally
    Replacer.Free;
    Probe.Free;
  end;
end;

procedure TestSkipAndCancel(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Replacer: TGrepReplacer;
  Probe: TReplaceEventProbe;
  Stats: TGrepReplaceStatistics;
begin
  Path := TPath.Combine(Dir, 'replace-skip.txt');
  SaveUtf8(Path, 'TODO TODO');
  Request := RequestFor(Path, 'TODO');
  Replacer := TGrepReplacer.Create;
  Probe := TReplaceEventProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Probe.SkipAfterFirst := True;
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), 'X');
    RequireCount(Stats.MatchesReplaced, 1, 'replace skip match count');
    RequireCount(Stats.MatchesSkipped, 1, 'replace skipped match count');
    Require(LoadUtf8(Path) = 'X TODO', 'replace skip contents');
    RequireCount(Probe.AllReplacedCount, 0, 'replace skip all event absent');
    Probe.SkipAfterFirst := False;
    Probe.CancelBefore := True;
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), 'Y');
    Require(Stats.Cancelled, 'replace cancel status');
    RequireCount(Stats.MatchesReplaced, 0, 'replace cancel match count');
    Require(LoadUtf8(Path) = 'X TODO', 'replace cancel retains data');
    Require(not FileExists(Path + '.bak2'), 'replace cancel no backup');
    RequireCount(Probe.CompletedCount, 2, 'replace cancelled completion');
  finally
    Replacer.Free;
    Probe.Free;
  end;
end;

procedure TestStaleAndOverlap(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Raised: Boolean;
begin
  Replacer := TGrepReplacer.Create;
  try
    Path := TPath.Combine(Dir, 'replace-stale.txt');
    SaveUtf8(Path, 'TODO');
    Request := RequestFor(Path, 'TODO');
    Matches := SearchMatches(Request);
    SaveUtf8(Path, 'DONE');
    Raised := False;
    try
      Replacer.ReplaceText(Request, Matches, 'X');
    except
      on E: EInvalidOpException do Raised := True;
    end;
    Require(Raised, 'replace stale rejected');
    Require(LoadUtf8(Path) = 'DONE', 'replace stale data unchanged');
    Require(not FileExists(Path + '.bak'), 'replace stale no backup');
    Path := TPath.Combine(Dir, 'replace-overlap.txt');
    SaveUtf8(Path, 'ABABA');
    Request := RequestFor(Path, 'ABA');
    Matches := SearchMatches(Request);
    RequireCount(Length(Matches), 2, 'replace overlap initial matches');
    Raised := False;
    try
      Replacer.ReplaceText(Request, Matches, 'X');
    except
      on E: EInvalidOpException do Raised := True;
    end;
    Require(Raised, 'replace overlap rejected');
    Require(LoadUtf8(Path) = 'ABABA', 'replace overlap unchanged');
    Require(not FileExists(Path + '.bak'), 'replace overlap no backup');
  finally
    Replacer.Free;
  end;
end;

procedure TestUtf16AndBytes(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Replacer: TGrepReplacer;
  Data: TBytes;
  Stats: TGrepReplaceStatistics;
begin
  Replacer := TGrepReplacer.Create;
  try
    Path := TPath.Combine(Dir, 'replace-utf16.txt');
    Data := TEncoding.Unicode.GetBytes(#$FEFF + 'x TODO y');
    TFile.WriteAllBytes(Path, Data);
    Request := RequestFor(Path, 'TODO');
    Request.Query.Encoding := geAuto;
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), #$00E4);
    RequireCount(Stats.MatchesReplaced, 1, 'replace utf16 count');
    Data := TFile.ReadAllBytes(Path);
    Require((Length(Data) >= 2) and (Data[0] = $FF) and (Data[1] = $FE), 'replace utf16 bom retained');
    Require(TEncoding.Unicode.GetString(Data, 2, Length(Data) - 2) = 'x ' + #$00E4 + ' y', 'replace utf16 text');
    Path := TPath.Combine(Dir, 'replace-utf16be.txt');
    Data := TEncoding.BigEndianUnicode.GetBytes(#$FEFF + 'x TODO y');
    TFile.WriteAllBytes(Path, Data);
    Request := RequestFor(Path, 'TODO');
    Request.Query.Encoding := geAuto;
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), #$00E4);
    RequireCount(Stats.MatchesReplaced, 1, 'replace utf16be count');
    Data := TFile.ReadAllBytes(Path);
    Require((Length(Data) >= 2) and (Data[0] = $FE) and (Data[1] = $FF), 'replace utf16be bom retained');
    Require(TEncoding.BigEndianUnicode.GetString(Data, 2, Length(Data) - 2) = 'x ' + #$00E4 + ' y', 'replace utf16be text');
    Path := TPath.Combine(Dir, 'replace-bytes.bin');
    TFile.WriteAllBytes(Path, [$00, $FF, $00, $FF, $41]);
    Request := RequestFor(Path, '');
    Request.Query.Mode := gmLiteralBytes;
    Request.Query.Bytes := [$00, $FF];
    Stats := Replacer.ReplaceBytes(Request, SearchMatches(Request), [$AB]);
    RequireCount(Stats.MatchesReplaced, 2, 'replace bytes count');
    Data := TFile.ReadAllBytes(Path);
    Require((Length(Data) = 3) and (Data[0] = $AB) and (Data[1] = $AB) and (Data[2] = $41), 'replace binary contents');
  finally
    Replacer.Free;
  end;
end;

procedure TestProgressCancel(const Dir: string);
var
  First, Second: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TReplaceEventProbe;
  Stats: TGrepReplaceStatistics;
  OtherMatches: TArray<TGrepMatch>;
  I, Start: Integer;
begin
  First := TPath.Combine(Dir, 'replace-progress-a.txt');
  Second := TPath.Combine(Dir, 'replace-progress-b.txt');
  SaveUtf8(First, 'TODO');
  SaveUtf8(Second, 'TODO');
  Request := RequestFor(First, 'TODO');
  Matches := SearchMatches(Request);
  Request.Options.Roots := [Second];
  OtherMatches := SearchMatches(Request);
  Start := Length(Matches);
  SetLength(Matches, Start + Length(OtherMatches));
  for I := 0 to High(OtherMatches) do Matches[Start + I] := OtherMatches[I];
  Replacer := TGrepReplacer.Create;
  Probe := TReplaceEventProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Probe.CancelAfterProgress := True;
    Stats := Replacer.ReplaceText(Request, Matches, 'X');
    Require(Stats.Cancelled, 'replace progress cancellation');
    RequireCount(Stats.MatchesReplaced, 1, 'replace progress one file changed');
    Require(LoadUtf8(First) = 'X', 'replace progress first changed');
    Require(LoadUtf8(Second) = 'TODO', 'replace progress second intact');
    RequireCount(Probe.CompletedCount, 1, 'replace progress completed event');
    RequireCount(Probe.AllReplacedCount, 0, 'replace progress all event absent');
  finally
    Replacer.Free;
    Probe.Free;
  end;
end;

procedure TestErrorContinue(const Dir: string);
var
  First, Second: string;
  Request: TGrepRequest;
  Matches, Other: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TReplaceEventProbe;
  Stats: TGrepReplaceStatistics;
begin
  First := TPath.Combine(Dir, 'replace-error-a.txt');
  Second := TPath.Combine(Dir, 'replace-error-b.txt');
  SaveUtf8(First, 'TODO');
  SaveUtf8(Second, 'TODO');
  Request := RequestFor(First, 'TODO');
  Matches := SearchMatches(Request);
  Request.Options.Roots := [Second];
  Other := SearchMatches(Request);
  SetLength(Matches, Length(Matches) + Length(Other));
  Matches[High(Matches)] := Other[0];
  SaveUtf8(First, 'DONE');
  Replacer := TGrepReplacer.Create;
  Probe := TReplaceEventProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Probe.ContinueAfterError := True;
    Stats := Replacer.ReplaceText(Request, Matches, 'X');
    RequireCount(Stats.Errors, 1, 'replace continued errors');
    Require(Stats.Failed and not Stats.Cancelled, 'replace continued failed status');
    RequireCount(Stats.MatchesReplaced, 1, 'replace continued match count');
    RequireCount(Probe.ErrorCount, 1, 'replace error event');
    RequireCount(Probe.CompletedCount, 1, 'replace error completed event');
    RequireCount(Probe.AllReplacedCount, 0, 'replace error no all event');
    Require(LoadUtf8(First) = 'DONE', 'replace error first intact');
    Require(LoadUtf8(Second) = 'X', 'replace error second committed');
    Require(not FileExists(First + '.bak'), 'replace error no failed backup');
    Require(FileExists(Second + '.bak'), 'replace error second backup');
  finally
    Replacer.Free;
    Probe.Free;
  end;
end;

procedure TestRegexReplacement(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
begin
  if not FileExists(ExtractFilePath(ParamStr(0)) + 'pcre2-8.dll') then Exit;
  Replacer := TGrepReplacer.Create;
  try
    Path := TPath.Combine(Dir, 'replace-regex.txt');
    SaveUtf8(Path, 'A1 A2');
    Request := RequestFor(Path, 'A[0-9]');
    Request.Query.Mode := gmRegexText;
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), 'X');
    RequireCount(Stats.MatchesReplaced, 2, 'replace regex matches');
    Require(LoadUtf8(Path) = 'X X', 'replace regex contents');
    Path := TPath.Combine(Dir, 'replace-regex-empty.txt');
    SaveUtf8(Path, 'bb');
    Request := RequestFor(Path, 'a*');
    Request.Query.Mode := gmRegexText;
    Stats := Replacer.ReplaceText(Request, SearchMatches(Request), 'X');
    RequireCount(Stats.MatchesReplaced, 3, 'replace regex empty matches');
    Require(LoadUtf8(Path) = 'XbXbX', 'replace regex empty contents');
  finally
    Replacer.Free;
  end;
end;

procedure RunReplaceTests(const Dir: string);
begin
  TestBackups(Dir);
  TestSkipAndCancel(Dir);
  TestStaleAndOverlap(Dir);
  TestUtf16AndBytes(Dir);
  TestProgressCancel(Dir);
  TestErrorContinue(Dir);
  TestRegexReplacement(Dir);
end;

end.
