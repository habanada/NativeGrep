unit NativeGrep.Replace.StressTests;

interface

procedure RunReplaceStressTests(const Dir: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  NativeGrep.Types, NativeGrep.Api, NativeGrep.Replace;

type
  TStressSink = class(TInterfacedObject, IGrepResultSink)
  private
    FMatches: TList<TGrepMatch>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
    property Matches: TList<TGrepMatch> read FMatches;
  end;

  TStressProbe = class
  public
    BeforeCount: Integer;
    AfterCount: Integer;
    ProgressCount: Integer;
    CompletedCount: Integer;
    AllCount: Integer;
    ErrorCount: Integer;
    CancelBeforeAt: Integer;
    CancelOnProgress: Boolean;
    SkipAll: Boolean;
    RaiseAfter: Boolean;
    Reenter: Boolean;
    ReentryRejected: Boolean;
    ReentryRequest: TGrepRequest;
    ReentryMatches: TArray<TGrepMatch>;
    LastBackup: string;
    EventTrace: string;
    LastStatistics: TGrepReplaceStatistics;
    procedure BeforeReplace(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean);
    procedure AfterReplace(Sender: TObject; const Match: TGrepMatch; const BackupPath: string);
    procedure Progress(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics);
    procedure Completed(Sender: TObject; const Statistics: TGrepReplaceStatistics);
    procedure AllReplaced(Sender: TObject; const Statistics: TGrepReplaceStatistics);
    procedure Error(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean);
  end;

constructor TStressSink.Create;
begin
  inherited Create;
  FMatches := TList<TGrepMatch>.Create;
end;

destructor TStressSink.Destroy;
begin
  FMatches.Free;
  inherited;
end;

procedure TStressSink.MatchFound(const Match: TGrepMatch);
begin
  FMatches.Add(Match);
end;

procedure TStressSink.ScanError(const SourcePath, ErrorText: string);
begin
  raise EInvalidOpException.Create(SourcePath + ': ' + ErrorText);
end;

procedure TStressProbe.BeforeReplace(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean);
begin
  Inc(BeforeCount);
  EventTrace := EventTrace + 'B';
  Skip := SkipAll;
  Cancel := (CancelBeforeAt > 0) and (BeforeCount = CancelBeforeAt);
  if Reenter then
  begin
    Reenter := False;
    try
      TGrepReplacer(Sender).ReplaceText(ReentryRequest, ReentryMatches, 'nested');
    except
      on E: EInvalidOpException do ReentryRejected := True;
    end;
  end;
end;

procedure TStressProbe.AfterReplace(Sender: TObject; const Match: TGrepMatch; const BackupPath: string);
begin
  Inc(AfterCount);
  EventTrace := EventTrace + 'A';
  LastBackup := BackupPath;
  if RaiseAfter then raise EInvalidOpException.Create('Intentional OnAfterReplace failure');
end;

procedure TStressProbe.Progress(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics);
begin
  Inc(ProgressCount);
  EventTrace := EventTrace + 'P';
  if CancelOnProgress then TGrepReplacer(Sender).Cancel;
end;

procedure TStressProbe.Completed(Sender: TObject; const Statistics: TGrepReplaceStatistics);
begin
  Inc(CompletedCount);
  EventTrace := EventTrace + 'D';
  LastStatistics := Statistics;
end;

procedure TStressProbe.AllReplaced(Sender: TObject; const Statistics: TGrepReplaceStatistics);
begin
  Inc(AllCount);
  EventTrace := EventTrace + 'L';
end;

procedure TStressProbe.Error(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean);
begin
  Inc(ErrorCount);
  EventTrace := EventTrace + 'E';
end;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('REPLACE STRESS FAIL: ' + Name);
end;

procedure CheckCount(Actual, Expected: Int64; const Name: string);
begin
  if Actual <> Expected then raise Exception.CreateFmt('REPLACE STRESS FAIL: %s expected=%d actual=%d', [Name, Expected, Actual]);
end;

procedure CheckBytes(const Actual, Expected: TBytes; const Name: string);
var
  I: Integer;
begin
  CheckCount(Length(Actual), Length(Expected), Name + ' byte count');
  for I := 0 to High(Expected) do
    if Actual[I] <> Expected[I] then
      raise Exception.CreateFmt('REPLACE STRESS FAIL: %s byte %d expected=%d actual=%d', [Name, I, Expected[I], Actual[I]]);
end;

function RequestFor(const Path: string; const Pattern: string): TGrepRequest;
begin
  Result := Default(TGrepRequest);
  Result.Query.Mode := gmLiteralText;
  Result.Query.Text := Pattern;
  Result.Query.Encoding := geUtf8;
  Result.Options.Roots := [Path];
  Result.Options.MaxWorkers := 1;
  Result.Options.BufferSize := 4096;
end;

function FindMatches(const Request: TGrepRequest): TArray<TGrepMatch>;
var
  Collector: TStressSink;
  Sink: IGrepResultSink;
begin
  Collector := TStressSink.Create;
  Sink := Collector;
  TNativeGrep.Search(Request, Sink);
  Result := Collector.Matches.ToArray;
end;

procedure SetProbe(Replacer: TGrepReplacer; Probe: TStressProbe);
begin
  Replacer.OnBeforeReplace := Probe.BeforeReplace;
  Replacer.OnAfterReplace := Probe.AfterReplace;
  Replacer.OnProgress := Probe.Progress;
  Replacer.OnCompleted := Probe.Completed;
  Replacer.OnAllReplaced := Probe.AllReplaced;
  Replacer.OnError := Probe.Error;
end;

procedure WriteText(const Path, Text: string);
begin
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
end;

function ReadText(const Path: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(Path));
end;

procedure CheckNoTemporaryFiles(const Dir, Name: string);
begin
  CheckCount(Length(TDirectory.GetFiles(Dir, '.nativegrep-*.tmp', TSearchOption.soTopDirectoryOnly)), 0, Name + ' temporary files');
end;

function NextRandom(var State: Cardinal; MaxExclusive: Integer): Integer;
begin
  State := Cardinal((UInt64(State) * 1664525 + 1013904223) and $FFFFFFFF);
  Result := Integer(State mod Cardinal(MaxExclusive));
end;

function ReferenceReplace(const Source, Needle, Replacement: TBytes; out MatchCount: Integer): TBytes;
var
  Target: TMemoryStream;
  I, J: Integer;
  Found: Boolean;
begin
  Target := TMemoryStream.Create;
  try
    MatchCount := 0;
    I := 0;
    while I < Length(Source) do
    begin
      Found := (Length(Needle) > 0) and (Length(Needle) <= Length(Source) - I);
      if Found then
        for J := 0 to High(Needle) do
          if Source[I + J] <> Needle[J] then
          begin
            Found := False;
            Break;
          end;
      if Found then
      begin
        Inc(MatchCount);
        if Length(Replacement) > 0 then Target.WriteBuffer(Replacement[0], Length(Replacement));
        Inc(I, Length(Needle));
      end
      else
      begin
        Target.WriteBuffer(Source[I], 1);
        Inc(I);
      end;
    end;
    SetLength(Result, Integer(Target.Size));
    Target.Position := 0;
    if Length(Result) > 0 then Target.ReadBuffer(Result[0], Length(Result));
  finally
    Target.Free;
  end;
end;

procedure TestRandomBinary(const Dir: string);
const
  Cases = 96;
var
  State: Cardinal;
  Input, Needle, Replacement, Expected: TBytes;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
  Path: string;
  I, J, K, Count: Integer;
  M: TGrepMatch;
begin
  State := $8D37A1B5;
  Needle := [$EF, $00, $FE];
  Replacer := TGrepReplacer.Create;
  try
    for I := 1 to Cases do
    begin
      Path := TPath.Combine(Dir, 'replace-random-' + IntToStr(I) + '.bin');
      SetLength(Input, 100 + NextRandom(State, 1600));
      J := 0;
      while J < Length(Input) do
      begin
        if (Length(Input) - J >= 3) and (NextRandom(State, 9) = 0) then
        begin
          Input[J] := Needle[0];
          Input[J + 1] := Needle[1];
          Input[J + 2] := Needle[2];
          Inc(J, 3);
        end
        else
        begin
          Input[J] := Byte(NextRandom(State, 128));
          Inc(J);
        end;
      end;
      SetLength(Replacement, NextRandom(State, 12));
      for J := 0 to High(Replacement) do Replacement[J] := Byte($80 + NextRandom(State, 64));
      Expected := ReferenceReplace(Input, Needle, Replacement, Count);
      Check(Count > 0, 'randomized generator produced hits ' + IntToStr(I));
      TFile.WriteAllBytes(Path, Input);
      Request := RequestFor(Path, '');
      Request.Query.Mode := gmLiteralBytes;
      Request.Query.Bytes := Copy(Needle);
      Matches := FindMatches(Request);
      CheckCount(Length(Matches), Count, 'randomized search hits ' + IntToStr(I));
      for J := 0 to (Length(Matches) div 2) - 1 do
      begin
        K := High(Matches) - J;
        M := Matches[J];
        Matches[J] := Matches[K];
        Matches[K] := M;
      end;
      Stats := Replacer.ReplaceBytes(Request, Matches, Replacement);
      CheckCount(Stats.MatchesReplaced, Count, 'randomized replaced ' + IntToStr(I));
      CheckCount(Stats.BackupsCreated, 1, 'randomized backup count ' + IntToStr(I));
      Check(not Stats.Cancelled and not Stats.Failed, 'randomized status ' + IntToStr(I));
      CheckBytes(TFile.ReadAllBytes(Path), Expected, 'randomized result ' + IntToStr(I));
      CheckBytes(TFile.ReadAllBytes(Path + '.bak'), Input, 'randomized backup ' + IntToStr(I));
    end;
    CheckNoTemporaryFiles(Dir, 'randomized');
  finally
    Replacer.Free;
  end;
end;

procedure TestRandomUtf8(const Dir: string);
const
  Cases = 64;
var
  State: Cardinal;
  Path, InputText, ExpectedText, Replacement, Prefix: string;
  Input, Expected: TBytes;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
  I, J, Count: Integer;
begin
  State := $56E1C207;
  Replacer := TGrepReplacer.Create;
  try
    for I := 1 to Cases do
    begin
      Path := TPath.Combine(Dir, 'replace-random-text-' + IntToStr(I) + '.txt');
      InputText := 'TODO';
      Count := 1;
      for J := 1 to 180 do
      begin
        case NextRandom(State, 9) of
          0: begin InputText := InputText + 'TODO'; Inc(Count); end;
          1: InputText := InputText + #13#10;
          2: InputText := InputText + #10;
          3: InputText := InputText + #$00E4;
          4: InputText := InputText + #$D83D#$DE80;
          5: InputText := InputText + #$0301;
          6: InputText := InputText + 'a';
          7: InputText := InputText + 'Z';
        else
          InputText := InputText + ' ';
        end;
      end;
      case I mod 6 of
        0: Replacement := '';
        1: Replacement := #$00E4;
        2: Replacement := #$D83D#$DE80;
        3: Replacement := #13#10;
        4: Replacement := '$1';
      else
        Replacement := StringOfChar('X', 200);
      end;
      if I mod 3 = 0 then Prefix := #$FEFF else Prefix := '';
      Input := TEncoding.UTF8.GetBytes(Prefix + InputText);
      ExpectedText := StringReplace(InputText, 'TODO', Replacement, [rfReplaceAll]);
      Expected := TEncoding.UTF8.GetBytes(Prefix + ExpectedText);
      TFile.WriteAllBytes(Path, Input);
      Request := RequestFor(Path, 'TODO');
      Request.Query.Encoding := geAuto;
      Matches := FindMatches(Request);
      CheckCount(Length(Matches), Count, 'utf8 random search ' + IntToStr(I));
      Stats := Replacer.ReplaceText(Request, Matches, Replacement);
      CheckCount(Stats.MatchesReplaced, Count, 'utf8 random replace ' + IntToStr(I));
      CheckCount(Stats.BackupsCreated, 1, 'utf8 random backup count ' + IntToStr(I));
      CheckBytes(TFile.ReadAllBytes(Path), Expected, 'utf8 random output ' + IntToStr(I));
      CheckBytes(TFile.ReadAllBytes(Path + '.bak'), Input, 'utf8 random backup ' + IntToStr(I));
    end;
    CheckNoTemporaryFiles(Dir, 'utf8 random');
  finally
    Replacer.Free;
  end;
end;

procedure TestLargeBoundary(const Dir: string);
var
  Path: string;
  Input, Needle, Replacement, Expected: TBytes;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
  I, Count: Integer;
  Offsets: array[0..5] of Integer;
begin
  Path := TPath.Combine(Dir, 'replace-large-boundary.bin');
  Needle := [$FA, $01, $FB];
  Replacement := [$00, $FF, $10, $20, $30, $40, $50];
  SetLength(Input, 4 * 1024 * 1024 + 7);
  for I := 0 to High(Input) do Input[I] := $7A;
  Offsets[0] := 0;
  Offsets[1] := 4094;
  Offsets[2] := 65535;
  Offsets[3] := 1048575;
  Offsets[4] := Length(Input) - 3;
  Offsets[5] := 2097151;
  for I := 0 to High(Offsets) do Move(Needle[0], Input[Offsets[I]], Length(Needle));
  Expected := ReferenceReplace(Input, Needle, Replacement, Count);
  CheckCount(Count, Length(Offsets), 'large generated count');
  TFile.WriteAllBytes(Path, Input);
  Request := RequestFor(Path, '');
  Request.Query.Mode := gmLiteralBytes;
  Request.Query.Bytes := Copy(Needle);
  Matches := FindMatches(Request);
  CheckCount(Length(Matches), Count, 'large search matches');
  Replacer := TGrepReplacer.Create;
  try
    Stats := Replacer.ReplaceBytes(Request, Matches, Replacement);
    CheckCount(Stats.MatchesReplaced, Count, 'large replaced count');
    CheckBytes(TFile.ReadAllBytes(Path), Expected, 'large output');
    CheckBytes(TFile.ReadAllBytes(Path + '.bak'), Input, 'large backup');
    CheckNoTemporaryFiles(Dir, 'large');
  finally
    Replacer.Free;
  end;
end;

procedure TestUnicodeAndDeletion(const Dir: string);
var
  Path, Text, Replacement, Expected: string;
  Input, OutputBytes: TBytes;
  Request: TGrepRequest;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
  I: Integer;
begin
  Path := TPath.Combine(Dir, 'replace-utf8-bom.txt');
  Text := 'TODO' + #13#10 + #$D83D#$DE80 + ' TODO ' + #$0301 + #10 + 'TODO';
  Replacement := #$D83D#$DE80 + #$00E4 + #10;
  Expected := Replacement + #13#10 + #$D83D#$DE80 + ' ' + Replacement + ' ' + #$0301 + #10 + Replacement;
  Input := TEncoding.UTF8.GetBytes(#$FEFF + Text);
  TFile.WriteAllBytes(Path, Input);
  Request := RequestFor(Path, 'TODO');
  Request.Query.Encoding := geAuto;
  Replacer := TGrepReplacer.Create;
  try
    Stats := Replacer.ReplaceText(Request, FindMatches(Request), Replacement);
    CheckCount(Stats.MatchesReplaced, 3, 'utf8 unicode count');
    OutputBytes := TFile.ReadAllBytes(Path);
    Check(Length(OutputBytes) >= 3, 'utf8 output length');
    for I := 0 to 2 do Check(OutputBytes[I] = Input[I], 'utf8 bom byte ' + IntToStr(I));
    CheckBytes(OutputBytes, TEncoding.UTF8.GetBytes(#$FEFF + Expected), 'utf8 unicode output');
    CheckBytes(TFile.ReadAllBytes(Path + '.bak'), Input, 'utf8 unicode backup');
    Path := TPath.Combine(Dir, 'replace-deletion.txt');
    WriteText(Path, 'TODO' + #13#10 + 'TODO' + #10 + 'TODO');
    Request := RequestFor(Path, 'TODO');
    Stats := Replacer.ReplaceText(Request, FindMatches(Request), '');
    CheckCount(Stats.MatchesReplaced, 3, 'deletion count');
    Check(ReadText(Path) = #13#10 + #10, 'deletion preserves line endings');
    Check(ReadText(Path + '.bak') = 'TODO' + #13#10 + 'TODO' + #10 + 'TODO', 'deletion backup');
    CheckNoTemporaryFiles(Dir, 'unicode');
  finally
    Replacer.Free;
  end;
end;

procedure TestBackupCollision(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
begin
  Path := TPath.Combine(Dir, 'replace-backup-collision.txt');
  WriteText(Path, 'TODO');
  WriteText(Path + '.bak', 'existing-1');
  TDirectory.CreateDirectory(Path + '.bak2');
  WriteText(Path + '.bak3', 'existing-3');
  Request := RequestFor(Path, 'TODO');
  Replacer := TGrepReplacer.Create;
  try
    Stats := Replacer.ReplaceText(Request, FindMatches(Request), 'DONE');
    CheckCount(Stats.BackupsCreated, 1, 'collision backup count');
    Check(ReadText(Path) = 'DONE', 'collision replaced');
    Check(ReadText(Path + '.bak') = 'existing-1', 'collision previous backup preserved');
    Check(DirectoryExists(Path + '.bak2'), 'collision directory preserved');
    Check(ReadText(Path + '.bak3') = 'existing-3', 'collision third backup preserved');
    Check(ReadText(Path + '.bak4') = 'TODO', 'collision fourth backup exact');
    CheckNoTemporaryFiles(Dir, 'collision');
  finally
    Replacer.Free;
  end;
end;

procedure TestCancelSkipAndReentry(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TStressProbe;
  Stats: TGrepReplaceStatistics;
  Token: TGrepCancellationToken;
  Cancellation: IGrepCancellation;
begin
  Path := TPath.Combine(Dir, 'replace-stress-cancel.txt');
  WriteText(Path, 'TODO TODO TODO');
  Request := RequestFor(Path, 'TODO');
  Matches := FindMatches(Request);
  CheckCount(Length(Matches), 3, 'cancel source hits');
  Replacer := TGrepReplacer.Create;
  Probe := TStressProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Probe.CancelBeforeAt := 2;
    Stats := Replacer.ReplaceText(Request, Matches, 'DONE');
    Check(Stats.Cancelled and not Stats.Failed, 'cancel before flag');
    CheckCount(Stats.MatchesReplaced, 0, 'cancel before no commit');
    CheckCount(Probe.BeforeCount, 2, 'cancel before events');
    CheckCount(Probe.AfterCount, 0, 'cancel after events');
    CheckCount(Probe.CompletedCount, 1, 'cancel completion');
    CheckCount(Probe.AllCount, 0, 'cancel no all event');
    Check(ReadText(Path) = 'TODO TODO TODO', 'cancel leaves source');
    Check(not FileExists(Path + '.bak'), 'cancel leaves no backup');
    Check(Probe.EventTrace = 'BBD', 'cancel event sequence');
    Probe.EventTrace := '';
    Probe.CancelBeforeAt := 0;
    Probe.SkipAll := True;
    Stats := Replacer.ReplaceText(Request, Matches, 'DONE');
    CheckCount(Stats.MatchesSkipped, 3, 'skip all count');
    CheckCount(Stats.FilesProcessed, 1, 'skip all file processed');
    CheckCount(Stats.BackupsCreated, 0, 'skip all backups');
    CheckCount(Probe.ProgressCount, 1, 'skip progress');
    CheckCount(Probe.AllCount, 0, 'skip no all event');
    Check(ReadText(Path) = 'TODO TODO TODO', 'skip leaves source');
    Check(Probe.EventTrace = 'BBBPD', 'skip event sequence');
    Probe.EventTrace := '';
    Probe.SkipAll := False;
    Probe.Reenter := True;
    Probe.ReentryRequest := Request;
    Probe.ReentryMatches := Copy(Matches);
    Stats := Replacer.ReplaceText(Request, Matches, 'X');
    Check(Probe.ReentryRejected, 'nested replace rejected');
    CheckCount(Stats.MatchesReplaced, 3, 'post reentry replaced');
    Check(ReadText(Path) = 'X X X', 'post reentry contents');
    Check(ReadText(Path + '.bak') = 'TODO TODO TODO', 'post reentry backup');
    Check(Probe.EventTrace = 'BBBAAAPLD', 'successful event sequence');
    Probe.EventTrace := '';
    Path := TPath.Combine(Dir, 'replace-stress-precancel.txt');
    WriteText(Path, 'TODO');
    Request := RequestFor(Path, 'TODO');
    Token := TGrepCancellationToken.Create;
    Cancellation := Token;
    Token.Cancel;
    Stats := Replacer.ReplaceText(Request, FindMatches(Request), 'X', Cancellation);
    Check(Stats.Cancelled, 'external cancellation');
    CheckCount(Stats.MatchesReplaced, 0, 'external cancel no matches');
    Check(ReadText(Path) = 'TODO', 'external cancel source');
    Check(not FileExists(Path + '.bak'), 'external cancel no backup');
    CheckNoTemporaryFiles(Dir, 'cancel');
  finally
    Probe.Free;
    Replacer.Free;
  end;
end;

procedure TestProgressPartialCommit(const Dir: string);
var
  First, Second: string;
  Request: TGrepRequest;
  FirstMatches, SecondMatches, Combined: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TStressProbe;
  Stats: TGrepReplaceStatistics;
  I, N: Integer;
begin
  First := TPath.Combine(Dir, 'replace-partial-01.txt');
  Second := TPath.Combine(Dir, 'replace-partial-02.txt');
  WriteText(First, 'TODO');
  WriteText(Second, 'TODO');
  Request := RequestFor(First, 'TODO');
  FirstMatches := FindMatches(Request);
  Request.Options.Roots := [Second];
  SecondMatches := FindMatches(Request);
  N := Length(FirstMatches);
  SetLength(Combined, N + Length(SecondMatches));
  for I := 0 to High(FirstMatches) do Combined[I] := FirstMatches[I];
  for I := 0 to High(SecondMatches) do Combined[N + I] := SecondMatches[I];
  Replacer := TGrepReplacer.Create;
  Probe := TStressProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Probe.CancelOnProgress := True;
    Stats := Replacer.ReplaceText(Request, Combined, 'X');
    Check(Stats.Cancelled and not Stats.Failed, 'partial cancellation state');
    CheckCount(Stats.FilesChanged, 1, 'partial changed files');
    CheckCount(Stats.BackupsCreated, 1, 'partial backups');
    CheckCount(Stats.MatchesReplaced, 1, 'partial replaced');
    CheckCount(Probe.AfterCount, 1, 'partial after events');
    CheckCount(Probe.ProgressCount, 1, 'partial progress events');
    CheckCount(Probe.CompletedCount, 1, 'partial completed once');
    CheckCount(Probe.AllCount, 0, 'partial no all event');
    Check(ReadText(First) = 'X', 'partial first changed');
    Check(ReadText(First + '.bak') = 'TODO', 'partial first recoverable');
    Check(ReadText(Second) = 'TODO', 'partial second intact');
    Check(not FileExists(Second + '.bak'), 'partial second no backup');
    CheckNoTemporaryFiles(Dir, 'partial');
  finally
    Probe.Free;
    Replacer.Free;
  end;
end;

procedure TestPostCommitEventException(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Replacer: TGrepReplacer;
  Probe: TStressProbe;
  Raised: Boolean;
begin
  Path := TPath.Combine(Dir, 'replace-after-exception.txt');
  WriteText(Path, 'TODO TODO');
  Request := RequestFor(Path, 'TODO');
  Replacer := TGrepReplacer.Create;
  Probe := TStressProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Probe.RaiseAfter := True;
    Raised := False;
    try
      Replacer.ReplaceText(Request, FindMatches(Request), 'X');
    except
      on E: EInvalidOpException do Raised := True;
    end;
    Check(Raised, 'postcommit handler exception visible');
    CheckCount(Probe.AfterCount, 1, 'postcommit first event');
    CheckCount(Probe.CompletedCount, 1, 'postcommit completion');
    CheckCount(Probe.AllCount, 0, 'postcommit no all event');
    Check(Probe.LastStatistics.Failed, 'postcommit flagged failure');
    Check(Probe.EventTrace = 'BBAED', 'postcommit event sequence');
    CheckCount(Probe.LastStatistics.FilesChanged, 1, 'postcommit already changed');
    CheckCount(Probe.LastStatistics.MatchesReplaced, 2, 'postcommit already replaced');
    Check(ReadText(Path) = 'X X', 'postcommit changed file');
    Check(ReadText(Path + '.bak') = 'TODO TODO', 'postcommit restorable backup');
    CheckNoTemporaryFiles(Dir, 'postcommit');
  finally
    Probe.Free;
    Replacer.Free;
  end;
end;

procedure TestInvalidMatchProtection(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches, Duplicated: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TStressProbe;
  Raised: Boolean;
begin
  Path := TPath.Combine(Dir, 'replace-invalid-match.txt');
  WriteText(Path, 'TODO');
  Request := RequestFor(Path, 'TODO');
  Matches := FindMatches(Request);
  CheckCount(Length(Matches), 1, 'invalid match source');
  Replacer := TGrepReplacer.Create;
  Probe := TStressProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Duplicated := [Matches[0], Matches[0]];
    Raised := False;
    try
      Replacer.ReplaceText(Request, Duplicated, 'X');
    except
      on E: EInvalidOpException do Raised := True;
    end;
    Check(Raised, 'duplicate matches rejected');
    Check(ReadText(Path) = 'TODO', 'duplicate source intact');
    Check(not FileExists(Path + '.bak'), 'duplicate no backup');
    CheckCount(Probe.CompletedCount, 1, 'duplicate completion');
    Matches[0].ByteOffset := High(Int64);
    Raised := False;
    try
      Replacer.ReplaceText(Request, Matches, 'X');
    except
      on E: EInvalidOpException do Raised := True;
    end;
    Check(Raised, 'out of range rejected');
    Check(ReadText(Path) = 'TODO', 'out of range source intact');
    Check(not FileExists(Path + '.bak'), 'out of range no backup');
    Request.Query.Text := 'MISSING';
    Matches := FindMatches(Request);
    CheckCount(Length(Matches), 0, 'missing query has no matches');
    Request.Query.Text := 'TODO';
    Matches := FindMatches(Request);
    Request.Query.Text := 'OTHER';
    Raised := False;
    try
      Replacer.ReplaceText(Request, Matches, 'X');
    except
      on E: EInvalidOpException do Raised := True;
    end;
    Check(Raised, 'mismatched query rejected');
    Check(ReadText(Path) = 'TODO', 'mismatched query no source changes');
    Check(not FileExists(Path + '.bak'), 'mismatched query no backup');
    CheckNoTemporaryFiles(Dir, 'invalid');
  finally
    Probe.Free;
    Replacer.Free;
  end;
end;

procedure TestLockedFileAndRetry(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TStressProbe;
  Lock: TFileStream;
  Stats: TGrepReplaceStatistics;
  Raised: Boolean;
begin
  Path := TPath.Combine(Dir, 'replace-exclusive-lock.txt');
  WriteText(Path, 'TODO');
  Request := RequestFor(Path, 'TODO');
  Matches := FindMatches(Request);
  Replacer := TGrepReplacer.Create;
  Probe := TStressProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Lock := TFileStream.Create(Path, fmOpenReadWrite or fmShareExclusive);
    try
      Raised := False;
      try
        Replacer.ReplaceText(Request, Matches, 'X');
      except
        on E: Exception do Raised := True;
      end;
      Check(Raised, 'exclusive file lock prevents replacement');
      CheckCount(Probe.ErrorCount, 1, 'lock error event');
      CheckCount(Probe.CompletedCount, 1, 'lock completion event');
      Check(Probe.LastStatistics.Failed, 'lock failed status');
      Check(not FileExists(Path + '.bak'), 'lock no backup');
    finally
      Lock.Free;
    end;
    Check(ReadText(Path) = 'TODO', 'lock source unchanged');
    Stats := Replacer.ReplaceText(Request, Matches, 'X');
    CheckCount(Stats.MatchesReplaced, 1, 'retry after lock');
    CheckCount(Probe.CompletedCount, 2, 'retry completion event');
    CheckCount(Probe.AllCount, 1, 'retry all replaced event');
    Check(ReadText(Path) = 'X', 'retry output');
    Check(ReadText(Path + '.bak') = 'TODO', 'retry backup');
    CheckNoTemporaryFiles(Dir, 'lock');
  finally
    Probe.Free;
    Replacer.Free;
  end;
end;

procedure TestMissingFileAndUnicodePath(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Probe: TStressProbe;
  Stats: TGrepReplaceStatistics;
  Raised: Boolean;
begin
  Replacer := TGrepReplacer.Create;
  Probe := TStressProbe.Create;
  try
    SetProbe(Replacer, Probe);
    Path := TPath.Combine(Dir, 'replace-removed.txt');
    WriteText(Path, 'TODO');
    Request := RequestFor(Path, 'TODO');
    Matches := FindMatches(Request);
    TFile.Delete(Path);
    Raised := False;
    try
      Replacer.ReplaceText(Request, Matches, 'X');
    except
      on E: Exception do Raised := True;
    end;
    Check(Raised, 'removed source rejected');
    CheckCount(Probe.ErrorCount, 1, 'removed source error event');
    CheckCount(Probe.CompletedCount, 1, 'removed source completion');
    Check(not FileExists(Path) and not FileExists(Path + '.bak'), 'removed file not recreated');
    Path := TPath.Combine(Dir, 'replace-' + #$00E4 + '-' + #$4E2D + '.txt');
    WriteText(Path, 'TODO ' + #$00E4 + #$4E2D + ' TODO');
    Request := RequestFor(Path, 'TODO');
    Stats := Replacer.ReplaceText(Request, FindMatches(Request), #$00C4);
    CheckCount(Stats.MatchesReplaced, 2, 'unicode filename replacement');
    Check(ReadText(Path) = #$00C4 + ' ' + #$00E4 + #$4E2D + ' ' + #$00C4, 'unicode filename output');
    Check(ReadText(Path + '.bak') = 'TODO ' + #$00E4 + #$4E2D + ' TODO', 'unicode filename backup');
    CheckNoTemporaryFiles(Dir, 'missing and unicode path');
  finally
    Probe.Free;
    Replacer.Free;
  end;
end;

procedure TestEmptySelection(const Dir: string);
var
  Path: string;
  Request: TGrepRequest;
  Matches: TArray<TGrepMatch>;
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
begin
  Path := TPath.Combine(Dir, 'replace-empty-selection.txt');
  WriteText(Path, 'TODO');
  Request := RequestFor(Path, 'TODO');
  SetLength(Matches, 0);
  Replacer := TGrepReplacer.Create;
  try
    Stats := Replacer.ReplaceText(Request, Matches, 'X');
    CheckCount(Stats.MatchesTotal, 0, 'empty total');
    CheckCount(Stats.FilesChanged, 0, 'empty changed');
    CheckCount(Stats.BackupsCreated, 0, 'empty backups');
    Check(not Stats.Cancelled and not Stats.Failed, 'empty status');
    Check(ReadText(Path) = 'TODO', 'empty selection source unchanged');
    Check(not FileExists(Path + '.bak'), 'empty selection no backup');
    CheckNoTemporaryFiles(Dir, 'empty');
  finally
    Replacer.Free;
  end;
end;

procedure RunReplaceStressTests(const Dir: string);
begin
  TestRandomBinary(Dir);
  TestRandomUtf8(Dir);
  TestLargeBoundary(Dir);
  TestUnicodeAndDeletion(Dir);
  TestBackupCollision(Dir);
  TestCancelSkipAndReentry(Dir);
  TestProgressPartialCommit(Dir);
  TestPostCommitEventException(Dir);
  TestInvalidMatchProtection(Dir);
  TestLockedFileAndRetry(Dir);
  TestMissingFileAndUnicodePath(Dir);
  TestEmptySelection(Dir);
  Writeln('NativeGrep Replace stress: 160 randomized cases and destructive-path tests PASS');
end;

end.
