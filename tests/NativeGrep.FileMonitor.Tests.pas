unit NativeGrep.FileMonitor.Tests;

interface

procedure RunFileMonitorTests(const Dir: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  NativeGrep.FileMonitor;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FILE MONITOR FAIL: ' + Name);
end;

procedure WriteFile(const Path, Value: string);
begin
  TFile.WriteAllText(Path, Value, TEncoding.UTF8);
end;

function WaitState(Monitor: TGrepFileMonitor; const Path: string; Expected: TGrepFileState; TimeoutMs: Cardinal): Boolean;
var
  Started: UInt64;
begin
  Started := GetTickCount64;
  repeat
    if Monitor.StateOf(Path) = Expected then Exit(True);
    Sleep(20);
  until GetTickCount64 - Started >= TimeoutMs;
  Result := Monitor.StateOf(Path) = Expected;
end;

procedure RunFileMonitorTests(const Dir: string);
var
  Root, SubDir, A, B, LogPath, OldPath, NewPath: string;
  Monitor: TGrepFileMonitor;
  Stamp: TGrepFileStamp;
  Updates: TArray<TGrepFileChange>;
  I, UpdatedCount: Integer;
begin
  Root := IncludeTrailingPathDelimiter(Dir) + 'monitor';
  SubDir := Root + '\nested';
  ForceDirectories(SubDir);
  A := Root + '\source.txt';
  B := SubDir + '\deep.txt';
  LogPath := Root + '\active.log';
  OldPath := Root + '\old.txt';
  NewPath := Root + '\new.txt';
  WriteFile(A, 'alpha');
  WriteFile(B, 'bravo');
  WriteFile(LogPath, '0');
  WriteFile(OldPath, 'old');
  Monitor := TGrepFileMonitor.Create;
  try
    Monitor.Start(Root, True);
    Check(Monitor.TrackCurrent(A) = gfsCurrent, 'initial current');
    Check(Monitor.TrackCurrent(B) = gfsCurrent, 'recursive tracked');
    Check(Monitor.TrackCurrent(LogPath) = gfsCurrent, 'log initial current');
    Check(Monitor.TrackCurrent(OldPath) = gfsCurrent, 'rename initial current');
    Check(Monitor.TrackCurrent(A) = gfsCurrent, 'duplicate track preserves baseline');
    Check(TGrepFileMonitor.Capture(A, Stamp) = gfsCurrent, 'capture succeeds');
    Check(Stamp.Valid, 'capture stamp valid');
    Sleep(200);
    WriteFile(A, 'alpha changed');
    Check(WaitState(Monitor, A, gfsChanged, 4000), 'watcher receives changed file');
    Check(Monitor.Recheck(A) = gfsChanged, 'changed state latched');
    WriteFile(A, 'alpha');
    Check(Monitor.Recheck(A) = gfsChanged, 'reverted content cannot clear changed state');
    for I := 1 to 100 do WriteFile(LogPath, IntToStr(I));
    Check(WaitState(Monitor, LogPath, gfsChanged, 4000), 'high-frequency log writes');
    Updates := Monitor.Drain;
    UpdatedCount := 0;
    for I := 0 to High(Updates) do
      if SameText(Updates[I].Path, LogPath) then Inc(UpdatedCount);
    Check(UpdatedCount = 1, 'log change notification coalesced');
    Check(Length(Monitor.Drain) = 0, 'drain empties queue');
    Winapi.Windows.DeleteFile(PChar(B));
    Check(Monitor.Recheck(B) = gfsDeleted, 'deleted file detection');
    Check(Winapi.Windows.MoveFile(PChar(OldPath), PChar(NewPath)), 'rename setup');
    Check(Monitor.Recheck(OldPath) = gfsDeleted, 'renamed original missing');
    Check(Monitor.StateOf(A) = gfsChanged, 'other file remains latched');
    Monitor.Stop;
    Check(Monitor.StateOf(A) = gfsUnknown, 'stopped monitor invalidates tracked files');
    Check(Monitor.StateOf(LogPath) = gfsUnknown, 'stopped monitor invalidates log');
    Check(Monitor.Recheck(A) = gfsUnknown, 'unknown monitor cannot claim current');
    Monitor.Start(Root, True);
    Check(Monitor.TrackCurrent(A) = gfsCurrent, 'new session resets baseline');
    Check(Monitor.TrackCurrent(LogPath) = gfsCurrent, 'new session resets log');
    WriteFile(A, 'different length');
    Check(Monitor.Recheck(A) = gfsChanged, 'explicit replacement precheck');
    Monitor.Clear;
    Check(Monitor.StateOf(A) = gfsUnknown, 'clear removes tracked state');
    Check(Length(Monitor.Drain) = 0, 'clear removes pending notifications');
  finally
    Monitor.Free;
  end;
  Writeln('NativeGrep file monitor tests: PASS');
end;

end.
