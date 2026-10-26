unit NativeGrep.FileMonitor;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  Winapi.Windows;

type
  TGrepFileState = (gfsCurrent, gfsChanged, gfsDeleted, gfsUnknown);

  TGrepFileStamp = record
    FileSize: Int64;
    WriteTime: TFileTime;
    VolumeSerial: DWORD;
    FileIndexHigh: DWORD;
    FileIndexLow: DWORD;
    Valid: Boolean;
  end;

  TGrepFileChange = record
    Path: string;
    State: TGrepFileState;
  end;

  TGrepFileMonitor = class;

  TGrepFileMonitorWorker = class(TThread)
  private
    FMonitor: TGrepFileMonitor;
    FDirectory: THandle;
    FRoot: string;
    FRecursive: Boolean;
    FReady: TEvent;
    FArmed: Boolean;
    procedure ProcessBuffer(const Buffer: TBytes; Count: DWORD);
  protected
    procedure Execute; override;
  public
    constructor Create(AMonitor: TGrepFileMonitor; ADirectory: THandle; const ARoot: string; ARecursive: Boolean);
    destructor Destroy; override;
    function WaitUntilReady: Boolean;
  end;

  TGrepTrackedFile = class
    Stamp: TGrepFileStamp;
    State: TGrepFileState;
  end;

  TGrepFileMonitor = class
  private
    FGuard: TCriticalSection;
    FTracked: TObjectDictionary<string, TGrepTrackedFile>;
    FPending: TList<TGrepFileChange>;
    FWorker: TGrepFileMonitorWorker;
    FHealthy: Boolean;
    procedure SetState(const Path: string; Entry: TGrepTrackedFile; State: TGrepFileState);
    procedure Changed(const Path: string; Action: DWORD);
    procedure LostNotifications;
  public
    constructor Create;
    destructor Destroy; override;
    class function Capture(const Path: string; out Stamp: TGrepFileStamp): TGrepFileState; static;
    procedure Start(const Root: string; Recursive: Boolean);
    procedure Stop;
    procedure Clear;
    procedure Track(const Path: string; const Stamp: TGrepFileStamp);
    function TrackCurrent(const Path: string): TGrepFileState;
    function Recheck(const Path: string): TGrepFileState;
    procedure RecheckAll;
    function StateOf(const Path: string): TGrepFileState;
    function Drain: TArray<TGrepFileChange>;
  end;

implementation

uses
  System.Generics.Defaults, NativeGrep.Paths;

type
  PNotifyEntry = ^TNotifyEntry;
  TNotifyEntry = record
    NextEntryOffset: DWORD;
    Action: DWORD;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;

function NormalPath(const Path: string): string;
begin
  Result := ExpandFileName(Path);
end;

function EqualStamp(const A, B: TGrepFileStamp): Boolean;
begin
  Result := A.Valid and B.Valid and (A.FileSize = B.FileSize) and
    (A.WriteTime.dwLowDateTime = B.WriteTime.dwLowDateTime) and
    (A.WriteTime.dwHighDateTime = B.WriteTime.dwHighDateTime) and
    (A.VolumeSerial = B.VolumeSerial) and (A.FileIndexHigh = B.FileIndexHigh) and
    (A.FileIndexLow = B.FileIndexLow);
end;

constructor TGrepFileMonitorWorker.Create(AMonitor: TGrepFileMonitor; ADirectory: THandle; const ARoot: string; ARecursive: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FMonitor := AMonitor;
  FDirectory := ADirectory;
  FRoot := IncludeTrailingPathDelimiter(ARoot);
  FRecursive := ARecursive;
  FReady := TEvent.Create(nil, True, False, '');
end;

destructor TGrepFileMonitorWorker.Destroy;
begin
  FReady.Free;
  if FDirectory <> INVALID_HANDLE_VALUE then CloseHandle(FDirectory);
  inherited;
end;

function TGrepFileMonitorWorker.WaitUntilReady: Boolean;
begin
  Result := (FReady.WaitFor(5000) = wrSignaled) and FArmed;
end;

procedure TGrepFileMonitorWorker.ProcessBuffer(const Buffer: TBytes; Count: DWORD);
var
  Offset: DWORD;
  Entry: PNotifyEntry;
  Name: string;
begin
  Offset := 0;
  while Offset < Count do
  begin
    if Count - Offset < 12 then
    begin
      FMonitor.LostNotifications;
      Exit;
    end;
    Entry := PNotifyEntry(@Buffer[Offset]);
    if (Entry^.FileNameLength mod SizeOf(WideChar) <> 0) or
      (Entry^.FileNameLength > Count - Offset - 12) or
      ((Entry^.NextEntryOffset <> 0) and ((Entry^.NextEntryOffset < 12) or (Entry^.NextEntryOffset > Count - Offset))) then
    begin
      FMonitor.LostNotifications;
      Exit;
    end;
    SetString(Name, PWideChar(@Entry^.FileName[0]), Entry^.FileNameLength div SizeOf(WideChar));
    FMonitor.Changed(NormalPath(FRoot + Name), Entry^.Action);
    if Entry^.NextEntryOffset = 0 then Break;
    Inc(Offset, Entry^.NextEntryOffset);
  end;
end;

procedure TGrepFileMonitorWorker.Execute;
var
  Buffer: TBytes;
  Overlap: TOverlapped;
  EventHandle: THandle;
  Bytes: DWORD;
  WaitResult: DWORD;
  Pending: Boolean;
  ErrorCode: DWORD;
begin
  SetLength(Buffer, 32768);
  EventHandle := CreateEvent(nil, True, False, nil);
  if EventHandle = 0 then
  begin
    FMonitor.LostNotifications;
    FReady.SetEvent;
    Exit;
  end;
  try
    try
      while not Terminated do
      begin
        Overlap := Default(TOverlapped);
        Overlap.hEvent := EventHandle;
        ResetEvent(EventHandle);
        Bytes := 0;
        Pending := ReadDirectoryChangesW(FDirectory, @Buffer[0], DWORD(Length(Buffer)), BOOL(Ord(FRecursive)),
          FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_SIZE or
          FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_CREATION, @Bytes, @Overlap, nil);
        if not Pending then
        begin
          ErrorCode := GetLastError;
          if ErrorCode <> ERROR_IO_PENDING then
          begin
            if not Terminated then FMonitor.LostNotifications;
            FReady.SetEvent;
            Break;
          end;
        end;
        if not FArmed then
        begin
          FArmed := True;
          FReady.SetEvent;
        end;
        repeat
          WaitResult := WaitForSingleObject(EventHandle, 250);
        until (WaitResult <> WAIT_TIMEOUT) or Terminated;
        if Terminated then
        begin
          CancelIoEx(FDirectory, @Overlap);
          WaitForSingleObject(EventHandle, INFINITE);
          Break;
        end;
        if WaitResult <> WAIT_OBJECT_0 then
        begin
          FMonitor.LostNotifications;
          Break;
        end;
        if not GetOverlappedResult(FDirectory, Overlap, Bytes, False) then
        begin
          ErrorCode := GetLastError;
          if (ErrorCode <> ERROR_OPERATION_ABORTED) and not Terminated then FMonitor.LostNotifications;
          Break;
        end;
        if Bytes = 0 then FMonitor.LostNotifications
        else ProcessBuffer(Buffer, Bytes);
      end;
    except
      on E: Exception do FMonitor.LostNotifications;
    end;
  finally
    FReady.SetEvent;
    CloseHandle(EventHandle);
  end;
end;

constructor TGrepFileMonitor.Create;
begin
  inherited;
  FGuard := TCriticalSection.Create;
  FTracked := TObjectDictionary<string, TGrepTrackedFile>.Create([doOwnsValues], TIStringComparer.Ordinal);
  FPending := TList<TGrepFileChange>.Create;
end;

destructor TGrepFileMonitor.Destroy;
begin
  Stop;
  FPending.Free;
  FTracked.Free;
  FGuard.Free;
  inherited;
end;

class function TGrepFileMonitor.Capture(const Path: string; out Stamp: TGrepFileStamp): TGrepFileState;
var
  Handle: THandle;
  Info: TByHandleFileInformation;
  ErrorCode: DWORD;
begin
  Stamp := Default(TGrepFileStamp);
  Handle := CreateFile(PChar(GrepWindowsPath(NormalPath(Path))), FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then
  begin
    ErrorCode := GetLastError;
    if (ErrorCode = ERROR_FILE_NOT_FOUND) or (ErrorCode = ERROR_PATH_NOT_FOUND) then Exit(gfsDeleted);
    Exit(gfsUnknown);
  end;
  try
    if not GetFileInformationByHandle(Handle, Info) then Exit(gfsUnknown);
    if (Info.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then Exit(gfsUnknown);
    Stamp.FileSize := (Int64(Info.nFileSizeHigh) shl 32) or Info.nFileSizeLow;
    Stamp.WriteTime := Info.ftLastWriteTime;
    Stamp.VolumeSerial := Info.dwVolumeSerialNumber;
    Stamp.FileIndexHigh := Info.nFileIndexHigh;
    Stamp.FileIndexLow := Info.nFileIndexLow;
    Stamp.Valid := True;
    Result := gfsCurrent;
  finally
    CloseHandle(Handle);
  end;
end;

procedure TGrepFileMonitor.Start(const Root: string; Recursive: Boolean);
var
  DirectoryHandle: THandle;
  FullRoot: string;
begin
  Stop;
  Clear;
  FullRoot := NormalPath(Root);
  DirectoryHandle := CreateFile(PChar(GrepWindowsPath(FullRoot)), FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
  if DirectoryHandle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    FWorker := TGrepFileMonitorWorker.Create(Self, DirectoryHandle, FullRoot, Recursive);
  except
    CloseHandle(DirectoryHandle);
    raise;
  end;
  FGuard.Enter;
  try
    FHealthy := True;
  finally
    FGuard.Leave;
  end;
  try
    FWorker.Start;
    if not FWorker.WaitUntilReady then raise EInvalidOpException.Create('Cannot start file change monitoring');
  except
    Stop;
    raise;
  end;
end;

procedure TGrepFileMonitor.Stop;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  LostNotifications;
end;

procedure TGrepFileMonitor.Clear;
begin
  FGuard.Enter;
  try
    FTracked.Clear;
    FPending.Clear;
  finally
    FGuard.Leave;
  end;
end;

procedure TGrepFileMonitor.SetState(const Path: string; Entry: TGrepTrackedFile; State: TGrepFileState);
var
  Item: TGrepFileChange;
begin
  if (Entry.State = State) or (State = gfsCurrent) or
    ((Entry.State <> gfsCurrent) and (State = gfsChanged)) then Exit;
  Entry.State := State;
  Item.Path := Path;
  Item.State := State;
  FPending.Add(Item);
end;

procedure TGrepFileMonitor.Changed(const Path: string; Action: DWORD);
var
  Entry: TGrepTrackedFile;
  Pair: TPair<string, TGrepTrackedFile>;
  Prefix: string;
begin
  FGuard.Enter;
  try
    if FTracked.TryGetValue(Path, Entry) then SetState(Path, Entry, gfsChanged);
    if (Action = FILE_ACTION_REMOVED) or (Action = FILE_ACTION_RENAMED_OLD_NAME) or
      (Action = FILE_ACTION_RENAMED_NEW_NAME) then
    begin
      Prefix := IncludeTrailingPathDelimiter(Path);
      for Pair in FTracked do
        if (Length(Pair.Key) > Length(Prefix)) and SameText(Copy(Pair.Key, 1, Length(Prefix)), Prefix) then
          SetState(Pair.Key, Pair.Value, gfsChanged);
    end;
  finally
    FGuard.Leave;
  end;
end;

procedure TGrepFileMonitor.LostNotifications;
var
  Pair: TPair<string, TGrepTrackedFile>;
begin
  FGuard.Enter;
  try
    FHealthy := False;
    for Pair in FTracked do SetState(Pair.Key, Pair.Value, gfsUnknown);
  finally
    FGuard.Leave;
  end;
end;

procedure TGrepFileMonitor.Track(const Path: string; const Stamp: TGrepFileStamp);
var
  Entry: TGrepTrackedFile;
  FullPath: string;
begin
  FullPath := NormalPath(Path);
  FGuard.Enter;
  try
    if FTracked.ContainsKey(FullPath) then Exit;
    Entry := TGrepTrackedFile.Create;
    Entry.Stamp := Stamp;
    if Stamp.Valid and FHealthy then Entry.State := gfsCurrent else Entry.State := gfsUnknown;
    FTracked.Add(FullPath, Entry);
    if Entry.State <> gfsCurrent then SetState(FullPath, Entry, gfsUnknown);
  finally
    FGuard.Leave;
  end;
end;

function TGrepFileMonitor.TrackCurrent(const Path: string): TGrepFileState;
var
  Stamp: TGrepFileStamp;
  Entry: TGrepTrackedFile;
  FullPath: string;
begin
  FullPath := NormalPath(Path);
  FGuard.Enter;
  try
    if FTracked.TryGetValue(FullPath, Entry) then Exit(Entry.State);
  finally
    FGuard.Leave;
  end;
  Result := Capture(FullPath, Stamp);
  Track(FullPath, Stamp);
  if Result = gfsDeleted then
  begin
    FGuard.Enter;
    try
      SetState(FullPath, FTracked[FullPath], gfsDeleted);
    finally
      FGuard.Leave;
    end;
  end;
  Result := StateOf(Path);
end;

function TGrepFileMonitor.Recheck(const Path: string): TGrepFileState;
var
  Stamp: TGrepFileStamp;
  CurrentState, NewState: TGrepFileState;
  Entry: TGrepTrackedFile;
  FullPath: string;
begin
  FullPath := NormalPath(Path);
  CurrentState := Capture(FullPath, Stamp);
  FGuard.Enter;
  try
    if not FTracked.TryGetValue(FullPath, Entry) then Exit(gfsUnknown);
    if not FHealthy then NewState := gfsUnknown
    else if CurrentState <> gfsCurrent then NewState := CurrentState
    else if EqualStamp(Entry.Stamp, Stamp) then NewState := gfsCurrent
    else NewState := gfsChanged;
    SetState(FullPath, Entry, NewState);
    Result := Entry.State;
  finally
    FGuard.Leave;
  end;
end;

procedure TGrepFileMonitor.RecheckAll;
var
  Paths: TArray<string>;
  Pair: TPair<string, TGrepTrackedFile>;
  I: Integer;
begin
  FGuard.Enter;
  try
    SetLength(Paths, FTracked.Count);
    I := 0;
    for Pair in FTracked do
    begin
      Paths[I] := Pair.Key;
      Inc(I);
    end;
  finally
    FGuard.Leave;
  end;
  for I := 0 to High(Paths) do Recheck(Paths[I]);
end;

function TGrepFileMonitor.StateOf(const Path: string): TGrepFileState;
var
  Entry: TGrepTrackedFile;
begin
  Result := gfsUnknown;
  FGuard.Enter;
  try
    if FTracked.TryGetValue(NormalPath(Path), Entry) then Result := Entry.State;
  finally
    FGuard.Leave;
  end;
end;

function TGrepFileMonitor.Drain: TArray<TGrepFileChange>;
begin
  FGuard.Enter;
  try
    Result := FPending.ToArray;
    FPending.Clear;
  finally
    FGuard.Leave;
  end;
end;

end.
