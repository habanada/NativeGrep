unit NativeGrep.GUI.Main;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections, System.Types, Vcl.Graphics, Vcl.Forms, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.Dialogs, Vcl.FileCtrl,
  NimbusForms.Controls.TabControl, NimbusForms.Controls.SplitContainer,
  NimbusForms.Controls.VirtualList, NimbusForms.Controls.TextBox,
  NimbusForms.Controls.CodeEditor, NimbusForms.Controls.CodeEditor.Types,
  NimbusForms.HexEditor.Control, NimbusForms.HexEditor.FileDataSource,
  NimbusForms.Controls.LogViewer.Encoding, NimbusForms.Controls.LogViewer,
  NimbusForms.Controls.LogViewer.Types, NimbusForms.Controls.Types,
  NimbusForms.Controls.Button, NimbusForms.Controls.Panel,
  NimbusForms.Controls.ToggleBox, NimbusForms.Controls.CheckBox,
  NimbusForms.Controls.ComboBox, NimbusForms.Controls.ThemedLabel,
  NimbusForms.Rendering.Canvas, NimbusForms.Rendering.Types,
  NimbusForms.Menus.PopupMenu, Vcl.Menus, NativeGrep.Types, NativeGrep.Replace, NativeGrep.FileMonitor,
  NimbusForms.Controls.Base, NimbusForms.Controls.DatePicker, NativeGrep.ResultView;

type
  TResultEntry = record
    Match: TGrepMatch;
    Excerpt: string;
  end;

  ISearchSession = interface(IGrepResultSink)
    ['{60842C75-773E-4967-9115-CB4609CBF031}']
    procedure Complete(const AStats: TGrepStatistics; const AFailure: string);
    procedure Drain(out AMatches: TArray<TResultEntry>; out AErrors: TArray<string>;
      out ADone: Boolean; out AStats: TGrepStatistics; out AFailure: string);
  end;

  TSearchSession = class(TInterfacedObject, ISearchSession)
  private
    FGuard: TCriticalSection;
    FMatches: TList<TResultEntry>;
    FEncoding: TGrepEncoding;
    FErrors: TStringList;
    FMonitor: TGrepFileMonitor;
    FTracked: TDictionary<string, Boolean>;
    FDone: Boolean;
    FStats: TGrepStatistics;
    FFailure: string;
  public
    constructor Create(AMonitor: TGrepFileMonitor; AEncoding: TGrepEncoding);
    destructor Destroy; override;
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
    procedure Complete(const AStats: TGrepStatistics; const AFailure: string);
    procedure Drain(out AMatches: TArray<TResultEntry>; out AErrors: TArray<string>;
      out ADone: Boolean; out AStats: TGrepStatistics; out AFailure: string);
  end;

  TReplaceSession = class
  private
    FGuard: TCriticalSection;
    FMessages: TStringList;
    FStats: TGrepReplaceStatistics;
    FLastBackup: string;
    FDone: Boolean;
    FAllReplaced: Boolean;
    FFailure: string;
    FMonitor: TGrepFileMonitor;
    FChecked: TDictionary<string, Boolean>;
  public
    constructor Create(AMonitor: TGrepFileMonitor);
    destructor Destroy; override;
    procedure BeforeReplace(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean);
    procedure AfterReplace(Sender: TObject; const Match: TGrepMatch; const BackupPath: string);
    procedure Progress(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics);
    procedure Error(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean);
    procedure AllReplaced(Sender: TObject; const Statistics: TGrepReplaceStatistics);
    procedure Completed(Sender: TObject; const Statistics: TGrepReplaceStatistics);
    procedure Finish(const Failure: string);
    procedure Drain(out Messages: TArray<string>; out Stats: TGrepReplaceStatistics;
      out Done, AllDone: Boolean; out Failure: string);
  end;

  TfrmNativeGrep = class(TForm)
    MainTabs: TThemedTabControl;
    RunTab: TTabSheet;
    OptionsTab: TTabSheet;
    FiltersTab: TTabSheet;
    FiltersInfo: TThemedLabel;
    SizeFilterLabel: TThemedLabel;
    SizeToLabel: TThemedLabel;
    SizeUnitsInfo: TThemedLabel;
    TimeFromLabel: TThemedLabel;
    TimeToLabel: TThemedLabel;
    CreatedFilterLabel: TThemedLabel;
    ModifiedFilterLabel: TThemedLabel;
    AccessedFilterLabel: TThemedLabel;
    TimeFormatInfo: TThemedLabel;
    TimeRelativeInfo: TThemedLabel;
    TimePresetLabel: TThemedLabel;
    CalendarFilterLabel: TThemedLabel;
    ExcludeFilterLabel: TThemedLabel;
    ExcludeFilterInfo: TThemedLabel;
    FFilterCalendar: TThemedDatePicker;
    FCalendarMode: TThemedComboBox;
    ApplyCalendarButton: TThemedButton;
    FilterSurface: TThemedPanel;
    FFiltersEnabled: TThemedCheckBox;
    FSizeMode: TThemedComboBox;
    FSizeFirst: TThemedTextBox;
    FSizeSecond: TThemedTextBox;
    FCreatedFrom: TThemedTextBox;
    FCreatedTo: TThemedTextBox;
    FModifiedFrom: TThemedTextBox;
    FModifiedTo: TThemedTextBox;
    FAccessedFrom: TThemedTextBox;
    FAccessedTo: TThemedTextBox;
    FExcludeEdit: TThemedTextBox;
    FTimePreset: TThemedComboBox;
    FTimeTarget: TThemedComboBox;
    ApplyTimePresetButton: TThemedButton;
    ClearFiltersButton: TThemedButton;
    FSearchHeader: TThemedPanel;
    FolderLabel: TThemedLabel;
    PatternLabel: TThemedLabel;
    IncludeLabel: TThemedLabel;
    ReplaceLabel: TThemedLabel;
    FFolderEdit: TThemedTextBox;
    FPatternEdit: TThemedTextBox;
    FIncludeEdit: TThemedTextBox;
    FReplaceEdit: TThemedTextBox;
    FBrowseButton: TThemedButton;
    FRunButton: TThemedButton;
    FReplaceSelectedButton: TThemedButton;
    FReplaceAllButton: TThemedButton;
    FRegexToggle: TThemedToggleBox;
    FCaseToggle: TThemedToggleBox;
    FRecursiveCheck: TThemedCheckBox;
    FStatusPanel: TThemedPanel;
    FStatus: TThemedLabel;
    FEngineLabel: TThemedLabel;
    FSplitOutput: TThemedSplitContainer;
    FSplitWorkspace: TThemedSplitContainer;
    ResultsHeader: TThemedPanel;
    ResultsHeaderLabel: TThemedLabel;
    FResultCount: TThemedLabel;
    ResultTools: TThemedPanel;
    FResultFilter: TThemedTextBox;
    FGroupingCombo: TThemedComboBox;
    GroupingLabel: TThemedLabel;
    FList: TThemedVirtualList;
    ViewerHeader: TThemedPanel;
    ViewerHeaderLabel: TThemedLabel;
    FPreviewTitle: TThemedLabel;
    FViewerTabs: TThemedTabControl;
    FCodeTab: TTabSheet;
    FHexTab: TTabSheet;
    FPreview: TThemedCodeEditor;
    FHex: TThemedHexEditor;
    OutputHeader: TThemedPanel;
    OutputHeaderLabel: TThemedLabel;
    ClearOutputButton: TThemedButton;
    SaveLogButton: TThemedButton;
    FOutput: TThemedLogViewer;
    OptionsSurface: TThemedPanel;
    AppearanceHeader: TThemedPanel;
    AppearanceHeaderLabel: TThemedLabel;
    EngineHeader: TThemedPanel;
    EngineHeaderLabel: TThemedLabel;
    LimitsHeader: TThemedPanel;
    LimitsHeaderLabel: TThemedLabel;
    ThemeLabel: TThemedLabel;
    FThemeCombo: TThemedComboBox;
    ThemeInfo: TThemedLabel;
    WorkersLabel: TThemedLabel;
    FWorkerCombo: TThemedComboBox;
    FInvalidUtfCheck: TThemedCheckBox;
    FHiddenCheck: TThemedCheckBox;
    RegexLimitLabel: TThemedLabel;
    RegexLimitInfo: TThemedLabel;
    RegexBackendLabel: TThemedLabel;
    RegexBackendInfo: TThemedLabel;
    PreferencesLabel: TThemedLabel;
    PreferencesInfo: TThemedLabel;
    procedure ApplyCalendarClick(Sender: TObject);
    procedure CalendarModeChanged(Sender: TObject);
    procedure ApplyTimePresetClick(Sender: TObject);
    procedure ClearFiltersClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure ClearOutputClick(Sender: TObject);
    procedure ReplaceAllClick(Sender: TObject);
    procedure ReplaceSelectedClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure SaveLogClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FHexFile: string;
    FHexMarkedCount: Integer;
    FSelectedMatchIndex: Integer;
    FPreviewFile: string;
    FPreviewMarkedCount: Integer;
    FListMenu: TThemedPopupMenu;
    FCodeMenu: TThemedPopupMenu;
    FCodeCopySelection: TMenuItem;
    FCodeCopyAll: TMenuItem;
    FLogMenu: TThemedPopupMenu;
    FLogCopySelection: TMenuItem;
    FLogCopyAll: TMenuItem;
    FLogSave: TMenuItem;
    FMenuOpenExternal: TMenuItem;
    FMenuView: TMenuItem;
    FMenuCode: TMenuItem;
    FMenuHex: TMenuItem;
    FMenuFolder: TMenuItem;
    FMenuName: TMenuItem;
    FMenuDirectory: TMenuItem;
    FMenuPath: TMenuItem;
    FMenuProperties: TMenuItem;
    FResults: TList<TGrepMatch>;
    FResultExcerpts: TList<string>;
    FResultView: TGrepResultView;
    FUpdatingResults: Boolean;
    FResultViewDirty: Boolean;
    FResultViewTick: UInt64;
    FResultFilterTick: UInt64;
    FSession: ISearchSession;
    FReplaceSession: TReplaceSession;
    FFileMonitor: TGrepFileMonitor;
    FSearchRequest: TGrepRequest;
    FReplaceReady: Boolean;
    FReplacing: Boolean;
    FThread: TThread;
    FToken: IGrepCancellation;
    FCancelToken: TGrepCancellationToken;
    FTimer: TTimer;
    FScanning: Boolean;
    FDisplayedErrors: Integer;
    procedure InitializeWorkbench;
    procedure StartReplace(SelectedOnly: Boolean);
    procedure ReplaceTimerTick;
    procedure MonitorTimerTick;
    procedure SearchInputChanged(Sender: TObject);
    procedure UpdateFilterControls;
    procedure AddFileFilters(var Options: TGrepOptions);
    procedure UpdateReplaceActions;
    procedure ClearResultsAfterReplace;
    procedure ThemeChanged(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure ResultFilterChanged(Sender: TObject);
    procedure GroupingChanged(Sender: TObject);
    procedure RebuildResultView;
    procedure GetGroupText(Sender: TObject; ARowIndex: Integer;
      const AItem: TThemedVirtualListItemData; var AText: string);
    procedure GetItem(Sender: TObject; AIndex: Integer; var AItem: TThemedVirtualListItemData);
    procedure GetCellText(Sender: TObject; ARowIndex: Integer;
      AColumn: TThemedVirtualListColumn; var AText: string);
    procedure RenderDetails(Sender: TObject; const ACanvas: INimbusRenderCanvas;
      const ABounds: TRect; ARowIndex: Integer; const AItem: TThemedVirtualListItemData;
      const AState: TThemedVirtualListCellRenderState; var AHandled: Boolean);
    procedure SelectionChanged(Sender: TObject);
    procedure ItemDoubleClick(Sender: TObject; AIndex: Integer);
    procedure BuildListMenu;
    procedure BuildViewerMenus;
    procedure CodeMenuPopup(Sender: TObject);
    procedure CodeMenuClick(Sender: TObject);
    procedure LogMenuPopup(Sender: TObject);
    procedure LogMenuClick(Sender: TObject);
    procedure ListMenuPopup(Sender: TObject);
    procedure ListMenuClick(Sender: TObject);
    function SelectedSourcePath: string;
    procedure ViewerTabChanged(Sender: TObject);
    procedure ViewerTabShown(Sender: TObject);
    procedure LoadViewerMatch(ATab: TTabSheet);
    procedure LoadOptionalSkiaRenderer;
    procedure ShowMatch(const AMatch: TGrepMatch);
    procedure ShowCodeMatch(const AMatch: TGrepMatch);
    procedure ShowHexMatch(const AMatch: TGrepMatch);
    procedure RefreshPreviewHighlights;
    function TryEditorMatch(const AMatch: TGrepMatch; AStream: TStream;
      out AHit: TCodeSearchMatch): Boolean;
    procedure AddLog(const AText: string; ALevel: TNimbusLogLevel = nllInfo);
    procedure SetScanning(const AValue: Boolean);
    procedure ReadSettings;
    procedure WriteSettings;
    function SettingsPath: string;
    function BuildRequest: TGrepRequest;
  end;

var
  frmNativeGrep: TfrmNativeGrep;

implementation

{$R *.dfm}

uses
  System.IOUtils, System.IniFiles, System.Math, System.UITypes, System.Generics.Defaults, Winapi.ShellAPI,
  Vcl.Clipbrd, NimbusForms.Rendering.CodeEditor.DLL,
  NimbusForms.Controls.LogViewer.View,
  NimbusForms.Theming.Manager, NimbusForms.Theming.Presets, NimbusForms.Theming.Types,
  NativeGrep.Engine, NativeGrep.Filters, NativeGrep.Context;

type
  TNativeGrepLogViewMenuAccess = class(TCustomNimbusLogView)
  public
    property PopupMenu;
  end;

function NativeGrepLogView(AViewer: TThemedLogViewer): TCustomNimbusLogView;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to AViewer.ControlCount - 1 do
    if AViewer.Controls[I] is TCustomNimbusLogView then
      Exit(TCustomNimbusLogView(AViewer.Controls[I]));
end;

constructor TReplaceSession.Create(AMonitor: TGrepFileMonitor);
begin
  inherited Create;
  FMonitor := AMonitor;
  FGuard := TCriticalSection.Create;
  FChecked := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FMessages := TStringList.Create;
end;

procedure TReplaceSession.BeforeReplace(Sender: TObject; const Match: TGrepMatch; var Skip, Cancel: Boolean);
var
  LState: TGrepFileState;
begin
  if FChecked.ContainsKey(Match.SourcePath) then Exit;
  FChecked.Add(Match.SourcePath, True);
  LState := FMonitor.Recheck(Match.SourcePath);
  if LState <> gfsCurrent then
  begin
    Cancel := True;
    FGuard.Enter;
    try
      FMessages.Add('Replace cancelled: source file changed or monitoring is unavailable: ' + Match.SourcePath);
    finally
      FGuard.Leave;
    end;
  end;
end;

destructor TReplaceSession.Destroy;
begin
  FChecked.Free;
  FMessages.Free;
  FGuard.Free;
  inherited Destroy;
end;

procedure TReplaceSession.AfterReplace(Sender: TObject; const Match: TGrepMatch; const BackupPath: string);
begin
  FGuard.Enter;
  try
    if FLastBackup <> BackupPath then
    begin
      FLastBackup := BackupPath;
      FMessages.Add('Replaced: ' + Match.SourcePath + ' | backup: ' + BackupPath);
    end;
  finally
    FGuard.Leave;
  end;
end;

procedure TReplaceSession.Progress(Sender: TObject; const SourcePath: string; const Statistics: TGrepReplaceStatistics);
begin
  FGuard.Enter;
  try
    FStats := Statistics;
  finally
    FGuard.Leave;
  end;
end;

procedure TReplaceSession.Error(Sender: TObject; const SourcePath, ErrorText: string; var ContinueProcessing: Boolean);
begin
  FGuard.Enter;
  try
    FMessages.Add('Replace failed: ' + SourcePath + ': ' + ErrorText);
  finally
    FGuard.Leave;
  end;
end;

procedure TReplaceSession.AllReplaced(Sender: TObject; const Statistics: TGrepReplaceStatistics);
begin
  FGuard.Enter;
  try
    FAllReplaced := True;
  finally
    FGuard.Leave;
  end;
end;

procedure TReplaceSession.Completed(Sender: TObject; const Statistics: TGrepReplaceStatistics);
begin
  FGuard.Enter;
  try
    FStats := Statistics;
  finally
    FGuard.Leave;
  end;
end;

procedure TReplaceSession.Finish(const Failure: string);
begin
  FGuard.Enter;
  try
    FFailure := Failure;
    FDone := True;
  finally
    FGuard.Leave;
  end;
end;

procedure TReplaceSession.Drain(out Messages: TArray<string>; out Stats: TGrepReplaceStatistics;
  out Done, AllDone: Boolean; out Failure: string);
var
  I: Integer;
begin
  FGuard.Enter;
  try
    SetLength(Messages, FMessages.Count);
    for I := 0 to FMessages.Count - 1 do
      Messages[I] := FMessages[I];
    FMessages.Clear;
    Stats := FStats;
    Done := FDone;
    AllDone := FAllReplaced;
    Failure := FFailure;
  finally
    FGuard.Leave;
  end;
end;

constructor TSearchSession.Create(AMonitor: TGrepFileMonitor; AEncoding: TGrepEncoding);
begin
  inherited Create;
  FMonitor := AMonitor;
  FEncoding := AEncoding;
  FGuard := TCriticalSection.Create;
  FTracked := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FMatches := TList<TResultEntry>.Create;
  FErrors := TStringList.Create;
end;

destructor TSearchSession.Destroy;
begin
  FTracked.Free;
  FErrors.Free;
  FMatches.Free;
  FGuard.Free;
  inherited Destroy;
end;

procedure TSearchSession.MatchFound(const Match: TGrepMatch);
var
  Entry: TResultEntry;
  Lines: TArray<TGrepContextLine>;
begin
  Entry.Match := Match;
  if not FTracked.ContainsKey(Match.SourcePath) then
  begin
    FTracked.Add(Match.SourcePath, True);
    FMonitor.TrackCurrent(Match.SourcePath);
  end;
  if Match.Line > 0 then
  begin
    try
      Lines := TGrepContextReader.ReadFile(Match, FEncoding, 0, 0, 512);
      if Length(Lines) > 0 then Entry.Excerpt := Lines[0].Text;
    except
      on E: Exception do Entry.Excerpt := '[Preview unavailable]';
    end;
  end
  else Entry.Excerpt := '[Binary match]';
  FGuard.Enter;
  try
    FMatches.Add(Entry);
  finally
    FGuard.Leave;
  end;
end;

procedure TSearchSession.ScanError(const SourcePath, ErrorText: string);
begin
  FGuard.Enter;
  try
    FErrors.Add(SourcePath + ': ' + ErrorText);
  finally
    FGuard.Leave;
  end;
end;

procedure TSearchSession.Complete(const AStats: TGrepStatistics; const AFailure: string);
begin
  FGuard.Enter;
  try
    FStats := AStats;
    FFailure := AFailure;
    FDone := True;
  finally
    FGuard.Leave;
  end;
end;

procedure TSearchSession.Drain(out AMatches: TArray<TResultEntry>;
  out AErrors: TArray<string>; out ADone: Boolean;
  out AStats: TGrepStatistics; out AFailure: string);
var
  I: Integer;
begin
  FGuard.Enter;
  try
    AMatches := FMatches.ToArray;
    FMatches.Clear;
    SetLength(AErrors, FErrors.Count);
    for I := 0 to FErrors.Count - 1 do
      AErrors[I] := FErrors[I];
    FErrors.Clear;
    ADone := FDone;
    AStats := FStats;
    AFailure := FFailure;
  finally
    FGuard.Leave;
  end;
end;

procedure TfrmNativeGrep.FormCreate(Sender: TObject);
begin
  Caption := 'NativeGrep';
  FResults := TList<TGrepMatch>.Create;
  FResultExcerpts := TList<string>.Create;
  FResultView := TGrepResultView.Create;
  FFileMonitor := TGrepFileMonitor.Create;
  FSelectedMatchIndex := -1;
  InitializeWorkbench;
  BuildListMenu;
  BuildViewerMenus;
  MainTabs.SetTabClosable(RunTab, False);
  MainTabs.SetTabClosable(OptionsTab, False);
  MainTabs.SetTabClosable(FiltersTab, False);
  MainTabs.ActivePage := RunTab;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 80;
  FTimer.OnTimer := TimerTick;
  FFolderEdit.Text := TPath.GetDocumentsPath;
  ReadSettings;
  if FThemeCombo.ItemIndex < 0 then
    FThemeCombo.ItemIndex := FThemeCombo.Items.IndexOf('Dark Visual Studio');
  ThemeChanged(FThemeCombo);
  LoadOptionalSkiaRenderer;
  FStatus.Caption := 'Ready  |  F5 to search';
end;

procedure TfrmNativeGrep.FormDestroy(Sender: TObject);
begin
  if FTimer <> nil then FTimer.Enabled := False;
  if FCancelToken <> nil then
    FCancelToken.Cancel;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
    FThread := nil;
  end;
  FReplaceSession.Free;
  FFileMonitor.Free;
  WriteSettings;
  FSession := nil;
  FToken := nil;
  FCancelToken := nil;
  FResults.Free;
  FResultExcerpts.Free;
  FResultView.Free;
end;

procedure TfrmNativeGrep.InitializeWorkbench;
var
  LName: string;
begin
  for LName in TThemePresets.GetNames do
    FThemeCombo.Items.Add(LName);
  FThemeCombo.OnChange := ThemeChanged;
  FHex.Options.ReadOnly := True;
  FViewerTabs.SetTabClosable(FCodeTab, False);
  FViewerTabs.SetTabClosable(FHexTab, False);
  FViewerTabs.OnChange := ViewerTabChanged;
  FCodeTab.OnShow := ViewerTabShown;
  FHexTab.OnShow := ViewerTabShown;
  FList.OnGetItem := GetItem;
  FList.OnGetGroupText := GetGroupText;
  FResultFilter.OnChange := ResultFilterChanged;
  FGroupingCombo.OnChange := GroupingChanged;
  FList.OnGetCellText := GetCellText;
  FList.OnRenderRowDetails := RenderDetails;
  FList.OnSelectionChanged := SelectionChanged;
  FList.OnItemDoubleClick := ItemDoubleClick;
  FFolderEdit.OnChange := SearchInputChanged;
  FPatternEdit.OnChange := SearchInputChanged;
  FIncludeEdit.OnChange := SearchInputChanged;
  FRegexToggle.OnCheckedChanged := SearchInputChanged;
  FCaseToggle.OnCheckedChanged := SearchInputChanged;
  FRecursiveCheck.OnCheckedChanged := SearchInputChanged;
  FInvalidUtfCheck.OnCheckedChanged := SearchInputChanged;
  FHiddenCheck.OnCheckedChanged := SearchInputChanged;
  FFiltersEnabled.OnCheckedChanged := SearchInputChanged;
  FFilterCalendar.Value := Now;
  FSizeMode.OnChange := SearchInputChanged;
  FSizeFirst.OnChange := SearchInputChanged;
  FSizeSecond.OnChange := SearchInputChanged;
  FCreatedFrom.OnChange := SearchInputChanged;
  FCreatedTo.OnChange := SearchInputChanged;
  FModifiedFrom.OnChange := SearchInputChanged;
  FModifiedTo.OnChange := SearchInputChanged;
  FAccessedFrom.OnChange := SearchInputChanged;
  FAccessedTo.OnChange := SearchInputChanged;
  FExcludeEdit.OnChange := SearchInputChanged;
  UpdateFilterControls;
  UpdateReplaceActions;
end;

procedure TfrmNativeGrep.ClearOutputClick(Sender: TObject);
begin
  FOutput.Clear;
end;

procedure TfrmNativeGrep.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = Ord('F')) and (ssCtrl in Shift) and not (ssAlt in Shift) and not FReplacing then
  begin
    MainTabs.ActivePage := RunTab;
    FResultFilter.SetFocus;
    Key := 0;
  end
  else if (Key = VK_ESCAPE) and (FResultFilter.Text <> '') and
    ((ActiveControl = FResultFilter) or FResultFilter.ContainsControl(ActiveControl)) then
  begin
    FResultFilter.Text := '';
    Key := 0;
  end
  else if ((Key = VK_F5) or ((Key = VK_RETURN) and (ssCtrl in Shift))) and
    (not (ssAlt in Shift)) then
  begin
    RunClick(Self);
    Key := 0;
  end
  else if (Key = VK_ESCAPE) and FScanning then
  begin
    if FCancelToken <> nil then
      FCancelToken.Cancel;
    FStatus.Caption := 'Cancelling...';
    Key := 0;
  end;
end;

procedure TfrmNativeGrep.BrowseClick(Sender: TObject);
var
  LFolder: string;
begin
  LFolder := FFolderEdit.Text;
  if SelectDirectory('Search folder', '', LFolder) then
    FFolderEdit.Text := LFolder;
end;

function TfrmNativeGrep.BuildRequest: TGrepRequest;
var
  LItems: TStringList;
  I: Integer;
begin
  Result := Default(TGrepRequest);
  Result.Query.Text := Trim(FPatternEdit.Text);
  if FRegexToggle.Checked then
    Result.Query.Mode := gmRegexText
  else
    Result.Query.Mode := gmLiteralText;
  Result.Query.Encoding := geAuto;
  Result.Query.CaseInsensitiveAscii := FCaseToggle.Checked and not FRegexToggle.Checked;
  Result.Query.UnicodeCaseFold := FCaseToggle.Checked and FRegexToggle.Checked;
  Result.Query.RegexAllowInvalidUtf8 := FInvalidUtfCheck.Checked;
  Result.Options.Recursive := FRecursiveCheck.Checked;
  Result.Options.IncludeHidden := FHiddenCheck.Checked;
  Result.Options.Roots := TArray<string>.Create(Trim(FFolderEdit.Text));
  Result.Options.MaxWorkers := StrToIntDef(FWorkerCombo.Text, 0);
  Result.Options.BinaryPolicy := gbAuto;
  Result.Options.TextPositions := gtpAuto;
  Result.Options.MaxResultsTotal := 50000;
  Result.Options.RegexMaxBytes := 64 * 1024 * 1024;
  AddFileFilters(Result.Options);
  LItems := TStringList.Create;
  try
    LItems.StrictDelimiter := True;
    LItems.Delimiter := ';';
    LItems.DelimitedText := StringReplace(FIncludeEdit.Text, ',', ';', [rfReplaceAll]);
    for I := 0 to LItems.Count - 1 do
      if Trim(LItems[I]) <> '' then
      begin
        SetLength(Result.Options.Includes, Length(Result.Options.Includes) + 1);
        Result.Options.Includes[High(Result.Options.Includes)] := Trim(LItems[I]);
      end;
  finally
    LItems.Free;
  end;
end;

procedure TfrmNativeGrep.SetScanning(const AValue: Boolean);
begin
  FScanning := AValue;
  FilterSurface.Enabled := not FScanning;
  ResultTools.Enabled := not FReplacing;
  if FScanning then
    FRunButton.Caption := 'Cancel'
  else
    FRunButton.Caption := 'Search';
  FBrowseButton.Enabled := not FScanning;
  FPatternEdit.Enabled := not FScanning;
  FFolderEdit.Enabled := not FScanning;
  FIncludeEdit.Enabled := not FScanning;
  FRegexToggle.Enabled := not FScanning;
  FCaseToggle.Enabled := not FScanning;
  FRecursiveCheck.Enabled := not FScanning;
  FReplaceEdit.Enabled := not FScanning;
  FInvalidUtfCheck.Enabled := not FScanning;
  FHiddenCheck.Enabled := not FScanning;
  UpdateReplaceActions;
end;

procedure TfrmNativeGrep.RunClick(Sender: TObject);
var
  LRequest: TGrepRequest;
  LSession: ISearchSession;
  LToken: IGrepCancellation;
begin
  if FScanning then
  begin
    if FCancelToken <> nil then
      FCancelToken.Cancel;
    FStatus.Caption := 'Cancelling...';
    Exit;
  end;
  if Trim(FPatternEdit.Text) = '' then
  begin
    FPatternEdit.SetFocus;
    Exit;
  end;
  if not System.SysUtils.DirectoryExists(Trim(FFolderEdit.Text)) then
  begin
    MessageDlg('The selected folder does not exist.', mtWarning, [mbOK], 0);
    FFolderEdit.SetFocus;
    Exit;
  end;
  try
    LRequest := BuildRequest;
  except
    on E: EArgumentException do
    begin
      MainTabs.ActivePage := FiltersTab;
      MessageDlg('Invalid file filter: ' + E.Message, mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  FSearchRequest := LRequest;
  FReplaceReady := False;
  FSelectedMatchIndex := -1;
  FResults.Clear;
  FResultExcerpts.Clear;
  FResultView.Clear;
  FResultFilter.Text := '';
  FResultViewDirty := False;
  FList.ItemCount := 0;
  FList.RefreshData;
  FOutput.Clear;
  FPreviewFile := '';
  FPreviewMarkedCount := -1;
  FHexFile := '';
  FHexMarkedCount := -1;
  FHex.Clear;
  FPreview.ClearSearchMatches;
  FPreview.Bookmarks.Clear;
  FPreview.Text := 'Select a result to view the source file.';
  FDisplayedErrors := 0;
  FResultCount.Caption := '0 matches';
  FPreviewTitle.Caption := 'Select a match';
  UpdateReplaceActions;
  try
    FFileMonitor.Start(Trim(FFolderEdit.Text), FRecursiveCheck.Checked);
  except
    on E: Exception do
    begin
      FFileMonitor.Stop;
      AddLog('File monitoring unavailable: ' + E.Message, nllWarning);
    end;
  end;
  FSession := TSearchSession.Create(FFileMonitor, LRequest.Query.Encoding);
  FCancelToken := TGrepCancellationToken.Create;
  FToken := FCancelToken;
  LSession := FSession;
  LToken := FToken;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LStats: TGrepStatistics;
      LFailure: string;
      LSink: IGrepResultSink;
    begin
      LStats := Default(TGrepStatistics);
      LFailure := '';
      try
        LSink := LSession;
        LStats := TNativeGrep.Search(LRequest, LSink, LToken);
        FFileMonitor.RecheckAll;
      except
        on E: Exception do
          LFailure := E.ClassName + ': ' + E.Message;
      end;
      LSession.Complete(LStats, LFailure);
    end);
  FThread.FreeOnTerminate := False;
  SetScanning(True);
  FThread.Start;
  FStatus.Caption := 'Searching...';
  AddLog('Search started: ' + FFolderEdit.Text);
end;

procedure TfrmNativeGrep.SearchInputChanged(Sender: TObject);
begin
  FReplaceReady := False;
  UpdateFilterControls;
  UpdateReplaceActions;
end;

procedure TfrmNativeGrep.UpdateFilterControls;
var
  I: Integer;
  LActive: Boolean;
begin
  for I := 0 to FilterSurface.ControlCount - 1 do
    if (FilterSurface.Controls[I] <> FFiltersEnabled) and
      (FilterSurface.Controls[I] <> ClearFiltersButton) then
      FilterSurface.Controls[I].Enabled := FFiltersEnabled.Checked;
  FSizeFirst.Enabled := FFiltersEnabled.Checked and (FSizeMode.ItemIndex > 0);
  FSizeSecond.Enabled := FFiltersEnabled.Checked and (FSizeMode.ItemIndex = 6);
  LActive := FFiltersEnabled.Checked and ((FSizeMode.ItemIndex > 0) or
    (Trim(FCreatedFrom.Text) <> '') or (Trim(FCreatedTo.Text) <> '') or
    (Trim(FModifiedFrom.Text) <> '') or (Trim(FModifiedTo.Text) <> '') or
    (Trim(FAccessedFrom.Text) <> '') or (Trim(FAccessedTo.Text) <> '') or
    (Trim(FExcludeEdit.Text) <> ''));
  if LActive then FiltersTab.Caption := 'File filters (active)'
  else FiltersTab.Caption := 'File filters';
end;

procedure TfrmNativeGrep.AddFileFilters(var Options: TGrepOptions);
const
  Operators: array[1..5] of string = ('<', '<=', '>', '>=', '=');
var
  LExpression: string;
  LItems: TStringList;
  I: Integer;
begin
  if not FFiltersEnabled.Checked then Exit;
  if FSizeMode.ItemIndex > 0 then
  begin
    if FSizeMode.ItemIndex = 6 then LExpression := FSizeFirst.Text + '..' + FSizeSecond.Text
    else LExpression := Operators[FSizeMode.ItemIndex] + FSizeFirst.Text;
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange(LExpression);
  end;
  Options.CreatedTimeFilter := TGrepFileFilters.ParseTimeRange(FCreatedFrom.Text, FCreatedTo.Text);
  Options.ModifiedTimeFilter := TGrepFileFilters.ParseTimeRange(FModifiedFrom.Text, FModifiedTo.Text);
  Options.AccessedTimeFilter := TGrepFileFilters.ParseTimeRange(FAccessedFrom.Text, FAccessedTo.Text);
  LItems := TStringList.Create;
  try
    LItems.StrictDelimiter := True;
    LItems.Delimiter := ';';
    LItems.DelimitedText := FExcludeEdit.Text;
    for I := 0 to LItems.Count - 1 do
      if Trim(LItems[I]) <> '' then
      begin
        SetLength(Options.Excludes, Length(Options.Excludes) + 1);
        Options.Excludes[High(Options.Excludes)] := Trim(LItems[I]);
      end;
  finally
    LItems.Free;
  end;
  TGrepFileFilters.Validate(Options);
end;

procedure TfrmNativeGrep.ApplyTimePresetClick(Sender: TObject);
const
  FromValues: array[0..6] of string = ('today', 'yesterday', 'now-30m', 'now-1h', 'now-24h', 'now-7d', 'now-30d');
var
  LFrom, LTo: TThemedTextBox;
  LUpper: string;
begin
  if (FTimePreset.ItemIndex < 0) or (FTimePreset.ItemIndex > 6) then Exit;
  case FTimeTarget.ItemIndex of
    1: begin LFrom := FCreatedFrom; LTo := FCreatedTo; end;
    2: begin LFrom := FAccessedFrom; LTo := FAccessedTo; end;
  else LFrom := FModifiedFrom; LTo := FModifiedTo;
  end;
  if FTimePreset.ItemIndex <= 1 then LUpper := FromValues[FTimePreset.ItemIndex]
  else LUpper := 'now';
  LFrom.Text := FromValues[FTimePreset.ItemIndex];
  LTo.Text := LUpper;
  SearchInputChanged(Sender);
end;

procedure TfrmNativeGrep.ClearFiltersClick(Sender: TObject);
begin
  FSizeMode.ItemIndex := 0;
  FSizeFirst.Text := '';
  FSizeSecond.Text := '';
  FCreatedFrom.Text := '';
  FCreatedTo.Text := '';
  FModifiedFrom.Text := '';
  FModifiedTo.Text := '';
  FAccessedFrom.Text := '';
  FAccessedTo.Text := '';
  FExcludeEdit.Text := '';
  FFiltersEnabled.Checked := True;
  SearchInputChanged(Sender);
end;

procedure TfrmNativeGrep.CalendarModeChanged(Sender: TObject);
begin
  FFilterCalendar.ShowTime := FCalendarMode.ItemIndex >= 2;
end;

procedure TfrmNativeGrep.ApplyCalendarClick(Sender: TObject);
var
  LFrom, LTo, LTarget: TThemedTextBox;
  LValue: string;
begin
  case FTimeTarget.ItemIndex of
    1: begin LFrom := FCreatedFrom; LTo := FCreatedTo; end;
    2: begin LFrom := FAccessedFrom; LTo := FAccessedTo; end;
  else LFrom := FModifiedFrom; LTo := FModifiedTo;
  end;
  if Odd(FCalendarMode.ItemIndex) then LTarget := LTo else LTarget := LFrom;
  if FCalendarMode.ItemIndex >= 2 then LValue := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', FFilterCalendar.Value)
  else LValue := FormatDateTime('yyyy-mm-dd', FFilterCalendar.Value);
  LTarget.Text := LValue;
  SearchInputChanged(Sender);
end;

procedure TfrmNativeGrep.UpdateReplaceActions;
var
  LEnabled: Boolean;
begin
  if (FReplaceAllButton = nil) or (FReplaceSelectedButton = nil) then Exit;
  LEnabled := FReplaceReady and not FScanning and (FResultView <> nil) and (FResultView.Count > 0);
  FReplaceAllButton.Enabled := LEnabled;
  FReplaceSelectedButton.Enabled := LEnabled and (FList <> nil) and (FList.SelectedCount > 0);
end;

procedure TfrmNativeGrep.ReplaceSelectedClick(Sender: TObject);
begin
  StartReplace(True);
end;

procedure TfrmNativeGrep.ReplaceAllClick(Sender: TObject);
begin
  StartReplace(False);
end;

procedure TfrmNativeGrep.StartReplace(SelectedOnly: Boolean);
var
  LMatches: TArray<TGrepMatch>;
  LRequest: TGrepRequest;
  LReplacement, LPrompt: string;
  LSession: TReplaceSession;
  LToken: IGrepCancellation;
  LIndex, LCount, I: Integer;
  LIndices: TThemedVirtualListIndexArray;
  LPaths: TDictionary<string, Boolean>;
  LConflict: string;
begin
  if FScanning or not FReplaceReady or (FResults.Count = 0) then Exit;
  if FResultViewDirty then RebuildResultView;
  if SelectedOnly then
  begin
    LIndices := FList.SelectedIndices;
    if Length(LIndices) = 0 then Exit;
    SetLength(LMatches, Length(LIndices));
    for I := 0 to High(LIndices) do
    begin
      LIndex := FResultView.SourceIndex(LIndices[I]);
      if (LIndex < 0) or (LIndex >= FResults.Count) then Exit;
      LMatches[I] := FResults[LIndex];
    end;
  end
  else
  begin
    SetLength(LMatches, FResultView.Count);
    for I := 0 to FResultView.Count - 1 do
      LMatches[I] := FResults[FResultView.SourceIndex(I)];
  end;
  if Length(LMatches) = 0 then Exit;
  LPaths := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  try
    LConflict := '';
    for I := 0 to High(LMatches) do
      if not LPaths.ContainsKey(LMatches[I].SourcePath) then
      begin
        LPaths.Add(LMatches[I].SourcePath, True);
        if FFileMonitor.Recheck(LMatches[I].SourcePath) <> gfsCurrent then
        begin
          LConflict := LMatches[I].SourcePath;
          Break;
        end;
      end;
  finally
    LPaths.Free;
  end;
  if LConflict <> '' then
  begin
    MessageDlg('Replace blocked: a source file changed, was deleted, or cannot be verified.' + sLineBreak +
      LConflict + sLineBreak + 'Run the search again to refresh the results.', mtWarning, [mbOK], 0);
    FList.RefreshData;
    Exit;
  end;
  LCount := Length(LMatches);
  LReplacement := FReplaceEdit.Text;
  if SelectedOnly then
  begin
    if LCount = 1 then LPrompt := 'Replace the selected match?'
    else LPrompt := Format('Replace %d selected matches?', [LCount]);
  end
  else
    LPrompt := Format('Replace all %d visible matches (%d total search results)?', [LCount, FResults.Count]);
  LPrompt := LPrompt + sLineBreak +
    'Every changed file gets a new .bak, .bak2, .bak3 ... backup.' + sLineBreak +
    'Changes cannot be undone automatically.';
  if LReplacement = '' then
    LPrompt := LPrompt + sLineBreak + 'Replacement is empty: matching text will be deleted.';
  if FSearchRequest.Query.Mode = gmRegexText then
    LPrompt := LPrompt + sLineBreak + 'Regex replacement is literal: $1 is not expanded.';
  if MessageDlg(LPrompt, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  LRequest := FSearchRequest;
  FReplaceReady := False;
  FReplacing := True;
  FList.Enabled := False;
  FViewerTabs.Enabled := False;
  FHex.Clear;
  FHexFile := '';
  FHexMarkedCount := -1;
  FPreviewFile := '';
  FPreviewMarkedCount := -1;
  FPreview.ClearSearchMatches;
  FPreview.Bookmarks.Clear;
  FPreview.Text := 'Replacing...';
  FReplaceSession := TReplaceSession.Create(FFileMonitor);
  LSession := FReplaceSession;
  FCancelToken := TGrepCancellationToken.Create;
  FToken := FCancelToken;
  LToken := FToken;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LReplacer: TGrepReplacer;
      LFailure: string;
    begin
      LFailure := '';
      LReplacer := TGrepReplacer.Create;
      try
        LReplacer.OnBeforeReplace := LSession.BeforeReplace;
        LReplacer.OnAfterReplace := LSession.AfterReplace;
        LReplacer.OnProgress := LSession.Progress;
        LReplacer.OnError := LSession.Error;
        LReplacer.OnAllReplaced := LSession.AllReplaced;
        LReplacer.OnCompleted := LSession.Completed;
        try
          LReplacer.ReplaceText(LRequest, LMatches, LReplacement, LToken);
        except
          on E: Exception do LFailure := E.ClassName + ': ' + E.Message;
        end;
      finally
        LReplacer.Free;
        LSession.Finish(LFailure);
      end;
    end);
  FThread.FreeOnTerminate := False;
  SetScanning(True);
  FThread.Start;
  FStatus.Caption := Format('Replacing %d match(es)...', [LCount]);
  AddLog(Format('Replace started: %d match(es); original files backed up', [LCount]));
end;

procedure TfrmNativeGrep.ClearResultsAfterReplace;
begin
  FFileMonitor.Stop;
  FFileMonitor.Clear;
  FSelectedMatchIndex := -1;
  FResults.Clear;
  FResultExcerpts.Clear;
  FResultView.Clear;
  FResultViewDirty := False;
  FList.ItemCount := 0;
  FList.RefreshData;
  FResultCount.Caption := '0 matches';
  FPreviewTitle.Caption := 'Select a match';
  FPreview.Text := 'Run a new search to refresh match offsets.';
  FReplaceReady := False;
end;

procedure TfrmNativeGrep.ReplaceTimerTick;
var
  LMessages: TArray<string>;
  LStats: TGrepReplaceStatistics;
  LDone, LAllDone: Boolean;
  LFailure, LMessage: string;
begin
  if FReplaceSession = nil then Exit;
  FReplaceSession.Drain(LMessages, LStats, LDone, LAllDone, LFailure);
  for LMessage in LMessages do AddLog(LMessage);
  if not LDone then
  begin
    FStatus.Caption := Format('Replacing... %d/%d files | %d match(es)',
      [LStats.FilesProcessed, LStats.FilesTotal, LStats.MatchesReplaced]);
    Exit;
  end;
  if (FThread <> nil) and not FThread.Finished then Exit;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  if LFailure <> '' then AddLog(LFailure, nllError);
  if LStats.Cancelled then
    FStatus.Caption := Format('Replace cancelled: %d match(es) in %d file(s)',
      [LStats.MatchesReplaced, LStats.FilesChanged])
  else if LStats.Failed or (LFailure <> '') then
    FStatus.Caption := Format('Replace failed: %d match(es) in %d file(s)',
      [LStats.MatchesReplaced, LStats.FilesChanged])
  else
    FStatus.Caption := Format('Replaced %d match(es) in %d file(s) | %d backup(s)',
      [LStats.MatchesReplaced, LStats.FilesChanged, LStats.BackupsCreated]);
  AddLog(FStatus.Caption, nllInfo);
  if LAllDone then AddLog('All selected matches replaced', nllSuccess);
  ClearResultsAfterReplace;
  FList.Enabled := True;
  FViewerTabs.Enabled := True;
  FReplaceSession.Free;
  FReplaceSession := nil;
  FReplacing := False;
  FToken := nil;
  FCancelToken := nil;
  SetScanning(False);
end;

procedure TfrmNativeGrep.ThemeChanged(Sender: TObject);
begin
  if FThemeCombo.ItemIndex >= 0 then
  begin
    ThemeManager.SetThemeByName(FThemeCombo.Items[FThemeCombo.ItemIndex]);
  end;
end;

procedure TfrmNativeGrep.AddLog(const AText: string; ALevel: TNimbusLogLevel);
begin
  FOutput.AppendLog(AText, ALevel);
end;

procedure TfrmNativeGrep.MonitorTimerTick;
var
  LChanges: TArray<TGrepFileChange>;
  LChange: TGrepFileChange;
begin
  LChanges := FFileMonitor.Drain;
  for LChange in LChanges do
    if LChange.State = gfsChanged then FFileMonitor.Recheck(LChange.Path);
  if (Length(LChanges) > 0) and (FResults.Count > 0) and not FReplacing then FList.RefreshData;
end;

procedure TfrmNativeGrep.TimerTick(Sender: TObject);
var
  LMatches: TArray<TResultEntry>;
  LErrors: TArray<string>;
  LDone: Boolean;
  LStats: TGrepStatistics;
  LFailure: string;
  LEntry: TResultEntry;
  LError: string;
  LAdded: Integer;
begin
  MonitorTimerTick;
  if FReplacing then
  begin
    ReplaceTimerTick;
    Exit;
  end;
  if FResultViewDirty and (GetTickCount64 - FResultFilterTick >= 180) and
    (GetTickCount64 - FResultViewTick >= 300) then RebuildResultView;
  if FSession = nil then
    Exit;
  FSession.Drain(LMatches, LErrors, LDone, LStats, LFailure);
  LAdded := Length(LMatches);
  if LAdded <> 0 then
  begin
    FResults.Capacity := Max(FResults.Capacity, FResults.Count + LAdded);
    for LEntry in LMatches do
    begin
      FResults.Add(LEntry.Match);
      FResultExcerpts.Add(LEntry.Excerpt);
    end;
    FResultViewDirty := True;
  end;
  for LError in LErrors do
  begin
    Inc(FDisplayedErrors);
    AddLog(LError, nllError);
  end;
  if not LDone then
  begin
    FStatus.Caption := Format('Searching... %d matches  |  %d file errors', [FResults.Count, FDisplayedErrors]);
    Exit;
  end;
  if FResultViewDirty then RebuildResultView;
  if (FThread <> nil) and not FThread.Finished then
    Exit;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  MonitorTimerTick;
  if LFailure <> '' then
    AddLog(LFailure, nllFatal);
  AddLog(Format('files=%d/%d  bytes=%d  matches=%d  errors=%d  elapsed=%d ms',
    [LStats.FilesScanned, LStats.FilesEnumerated, LStats.BytesScanned,
    LStats.Matches, LStats.Errors, LStats.ElapsedMs]));
  if LFailure = '' then
    AddLog('Search completed', nllSuccess);
  if LFailure <> '' then
    FStatus.Caption := 'Search failed: ' + LFailure
  else
    FStatus.Caption := Format('%d matches  |  %d files  |  %d errors  |  %d ms',
      [FResults.Count, LStats.FilesScanned, LStats.Errors, LStats.ElapsedMs]);
  FReplaceReady := (LFailure = '') and (LStats.Errors = 0) and
    ((FToken = nil) or not FToken.IsCancellationRequested) and
    ((FSearchRequest.Options.MaxResultsTotal <= 0) or
    (LStats.Matches < FSearchRequest.Options.MaxResultsTotal));
  SetScanning(False);
  FSession := nil;
  FToken := nil;
  FCancelToken := nil;
end;

procedure TfrmNativeGrep.ResultFilterChanged(Sender: TObject);
begin
  FResultFilterTick := GetTickCount64;
  FResultViewDirty := True;
end;

procedure TfrmNativeGrep.GroupingChanged(Sender: TObject);
begin
  FResultViewDirty := True;
end;

procedure TfrmNativeGrep.RebuildResultView;
var
  Selected: TThemedVirtualListIndexArray;
  Focused, TopSource, I, Row, FocusRow: Integer;
  Grouping: TGrepResultGrouping;
begin
  if FUpdatingResults or (FResultView = nil) then Exit;
  Selected := FList.SelectedIndices;
  for I := 0 to High(Selected) do Selected[I] := FResultView.SourceIndex(Selected[I]);
  Focused := FResultView.SourceIndex(FList.SelectedIndex);
  TopSource := FResultView.SourceIndex(FList.TopIndex);
  Grouping := TGrepResultGrouping(EnsureRange(FGroupingCombo.ItemIndex, 0, 2));
  FUpdatingResults := True;
  FList.BeginUpdate;
  try
    FList.ClearSelection;
    FList.CollapseAllDetails;
    FList.ItemCount := 0;
    FResultView.Rebuild(FResults, FResultExcerpts, FResultFilter.Text, Grouping);
    FList.ShowGroupHeaders := Grouping <> grgNone;
    FList.ItemCount := FResultView.Count;
    FocusRow := FResultView.RowIndex(Focused);
    for I := 0 to High(Selected) do
    begin
      Row := FResultView.RowIndex(Selected[I]);
      if Row >= 0 then FList.Selected[Row] := True;
    end;
    if FocusRow >= 0 then
    begin
      FList.Selected[FocusRow] := False;
      FList.Selected[FocusRow] := True;
    end;
    Row := FResultView.RowIndex(TopSource);
    if Row >= 0 then FList.TopIndex := Row else FList.ScrollOffset := 0;
    FSelectedMatchIndex := FResultView.SourceIndex(FList.SelectedIndex);
    if (FSelectedMatchIndex < 0) and (Focused >= 0) then
    begin
      FPreviewFile := '';
      FHexFile := '';
      FPreview.ClearSearchMatches;
      FPreview.Bookmarks.Clear;
      FPreview.Text := 'Select a visible result to view the source file.';
      FHex.Clear;
      FPreviewTitle.Caption := 'Select a match';
    end;
    if Trim(FResultFilter.Text) = '' then
      FList.EmptyText := 'No results - Enter a pattern and press F5'
    else FList.EmptyText := 'No matching results - Clear the result filter to show all hits';
    FResultCount.Caption := Format('%d / %d matches', [FResultView.Count, FResults.Count]);
    FList.RefreshData;
    FResultViewDirty := False;
    FResultViewTick := GetTickCount64;
  finally
    FList.EndUpdate;
    FUpdatingResults := False;
  end;
  if (FSelectedMatchIndex >= 0) and (FSelectedMatchIndex <> Focused) then
    ShowMatch(FResults[FSelectedMatchIndex]);
  UpdateReplaceActions;
end;

procedure TfrmNativeGrep.GetGroupText(Sender: TObject; ARowIndex: Integer;
  const AItem: TThemedVirtualListItemData; var AText: string);
begin
  AText := FResultView.GroupText(ARowIndex);
end;

procedure TfrmNativeGrep.GetItem(Sender: TObject; AIndex: Integer;
  var AItem: TThemedVirtualListItemData);
var
  LMatch: TGrepMatch;
  LCapture: TGrepCapture;
  LDetails: TStringBuilder;
begin
  AItem := Default(TThemedVirtualListItemData);
  AItem.Enabled := True;
  AItem.ImageIndex := -1;
  AIndex := FResultView.SourceIndex(AIndex);
  if (AIndex < 0) or (AIndex >= FResults.Count) then
    Exit;
  LMatch := FResults[AIndex];
  AItem.Text := ExtractFileName(LMatch.SourcePath);
  AItem.Subtitle := LMatch.SourcePath;
  LDetails := TStringBuilder.Create;
  try
    LDetails.Append(LMatch.SourcePath).AppendLine;
    LDetails.Append(FResultExcerpts[AIndex]).AppendLine;
    LDetails.AppendFormat('Offset: %d  Bytes: %d  Pattern: %d',
      [LMatch.ByteOffset, Int64(LMatch.ByteLength), LMatch.PatternIndex]);
    if Length(LMatch.Captures) <> 0 then
    begin
      LDetails.AppendLine;
      for LCapture in LMatch.Captures do
        if LCapture.Matched then
          LDetails.AppendFormat('  Group %d: @%d (%d bytes)',
            [LCapture.Index, LCapture.ByteOffset, Int64(LCapture.ByteLength)]).AppendLine;
    end;
    if FFileMonitor.StateOf(LMatch.SourcePath) <> gfsCurrent then
      LDetails.AppendLine.Append('File changed or monitoring unavailable. Rescan before replacing.');
    AItem.DetailText := LDetails.ToString;
  finally
    LDetails.Free;
  end;
end;

procedure TfrmNativeGrep.GetCellText(Sender: TObject; ARowIndex: Integer;
  AColumn: TThemedVirtualListColumn; var AText: string);
var
  LMatch: TGrepMatch;
begin
  ARowIndex := FResultView.SourceIndex(ARowIndex);
  if (ARowIndex < 0) or (ARowIndex >= FResults.Count) then
    Exit;
  LMatch := FResults[ARowIndex];
  case AColumn.Tag of
    0: AText := ExtractFileName(LMatch.SourcePath);
    1: if LMatch.Line > 0 then AText := IntToStr(LMatch.Line) else AText := '-';
    2: if LMatch.Column > 0 then AText := IntToStr(LMatch.Column) else AText := '-';
    3: AText := Format('$%x', [LMatch.ByteOffset]);
    4: AText := UIntToStr(UInt64(LMatch.ByteLength));
    6: AText := FResultExcerpts[ARowIndex];
    5: case FFileMonitor.StateOf(LMatch.SourcePath) of
         gfsCurrent: AText := 'Watching';
         gfsChanged: AText := 'Changed';
         gfsDeleted: AText := 'Deleted';
       else AText := 'Unknown';
       end;
  end;
end;

procedure TfrmNativeGrep.RenderDetails(Sender: TObject;
  const ACanvas: INimbusRenderCanvas; const ABounds: TRect;
  ARowIndex: Integer; const AItem: TThemedVirtualListItemData;
  const AState: TThemedVirtualListCellRenderState; var AHandled: Boolean);
var
  LBounds: TRect;
begin
  LBounds := ABounds;
  InflateRect(LBounds, -12, -8);
  ACanvas.DrawText(AItem.DetailText, FList.Font,
    NimbusControlForeColor(ThemeManager.CurrentTheme), LBounds,
    [ntfWordWrap, ntfNoPrefix]);
  AHandled := True;
end;

procedure TfrmNativeGrep.SelectionChanged(Sender: TObject);
var
  LIndex: Integer;
begin
  if FUpdatingResults then Exit;
  LIndex := FResultView.SourceIndex(FList.SelectedIndex);
  if (LIndex >= 0) and (LIndex < FResults.Count) then
  begin
    FSelectedMatchIndex := LIndex;
    ShowMatch(FResults[LIndex]);
  end;
  UpdateReplaceActions;
end;

procedure TfrmNativeGrep.ItemDoubleClick(Sender: TObject; AIndex: Integer);
var
  LSource: Integer;
begin
  LSource := FResultView.SourceIndex(AIndex);
  if (LSource < 0) or (LSource >= FResults.Count) then Exit;
  if FFileMonitor.Recheck(FResults[LSource].SourcePath) <> gfsCurrent then
  begin
    FList.RefreshData;
    if not FScanning and (MessageDlg('This source file has changed or can no longer be verified.' +
      sLineBreak + 'Run the entire search again?', mtConfirmation, [mbYes, mbNo], 0) = mrYes) then RunClick(Self);
    Exit;
  end;
  FList.ToggleDetails(AIndex);
end;

procedure TfrmNativeGrep.BuildViewerMenus;
var
  LView: TCustomNimbusLogView;

  function AddEntry(AMenu: TThemedPopupMenu; const ACaption: string;
    ATag: Integer; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(AMenu);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AClick;
    AMenu.Items.Add(Result);
  end;

begin
  FCodeMenu := TThemedPopupMenu.Create(Self);
  FCodeMenu.OnPopup := CodeMenuPopup;
  FCodeCopySelection := AddEntry(FCodeMenu, 'Copy selection', 1, CodeMenuClick);
  FCodeCopyAll := AddEntry(FCodeMenu, 'Copy all text', 2, CodeMenuClick);
  AddEntry(FCodeMenu, '-', 0, nil);
  AddEntry(FCodeMenu, 'Select all', 3, CodeMenuClick);
  FPreview.PopupMenu := FCodeMenu;

  FLogMenu := TThemedPopupMenu.Create(Self);
  FLogMenu.OnPopup := LogMenuPopup;
  FLogCopySelection := AddEntry(FLogMenu, 'Copy selected line(s)', 1, LogMenuClick);
  FLogCopyAll := AddEntry(FLogMenu, 'Copy all lines', 2, LogMenuClick);
  AddEntry(FLogMenu, '-', 0, nil);
  AddEntry(FLogMenu, 'Select all lines', 3, LogMenuClick);
  AddEntry(FLogMenu, '-', 0, nil);
  FLogSave := AddEntry(FLogMenu, 'Save log as...', 4, LogMenuClick);
  AddEntry(FLogMenu, 'Clear log', 5, LogMenuClick);
  LView := NativeGrepLogView(FOutput);
  if LView <> nil then
    TNativeGrepLogViewMenuAccess(LView).PopupMenu := FLogMenu
  else
    AddLog('LogViewer context menu unavailable', nllWarning);
end;

procedure TfrmNativeGrep.CodeMenuPopup(Sender: TObject);
begin
  FCodeCopySelection.Enabled := FPreview.SelectionText <> '';
  FCodeCopyAll.Enabled := FPreview.Text <> '';
end;

procedure TfrmNativeGrep.CodeMenuClick(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    1: FPreview.Copy;
    2: Clipboard.AsText := StringReplace(FPreview.Text, #10, sLineBreak, [rfReplaceAll]);
    3: FPreview.SelectAll;
  end;
end;

procedure TfrmNativeGrep.LogMenuPopup(Sender: TObject);
var
  LView: TCustomNimbusLogView;
begin
  LView := NativeGrepLogView(FOutput);
  if LView = nil then
    FLogCopySelection.Enabled := False
  else
    FLogCopySelection.Enabled := LView.SelectionText <> '';
  FLogCopyAll.Enabled := FOutput.Model.Count > 0;
  FLogSave.Enabled := FOutput.Model.Count > 0;
end;

procedure TfrmNativeGrep.LogMenuClick(Sender: TObject);
var
  LBuilder: TStringBuilder;
  I: Integer;
begin
  case TMenuItem(Sender).Tag of
    1: FOutput.CopySelection;
    2:
      begin
        LBuilder := TStringBuilder.Create;
        try
          for I := 0 to FOutput.Model.Count - 1 do
          begin
            if I <> 0 then
              LBuilder.Append(sLineBreak);
            LBuilder.Append(FOutput.Model[I].Text);
          end;
          Clipboard.AsText := LBuilder.ToString;
        finally
          LBuilder.Free;
        end;
      end;
    3: FOutput.SelectAll;
    4: SaveLogClick(Sender);
    5: FOutput.Clear;
  end;
end;

procedure TfrmNativeGrep.SaveLogClick(Sender: TObject);
var
  LDialog: TSaveDialog;
begin
  if FOutput.Model.Count = 0 then
    Exit;
  LDialog := TSaveDialog.Create(Self);
  try
    LDialog.Title := 'Save NativeGrep log';
    LDialog.Filter := 'Log files (*.log)|*.log|Text files (*.txt)|*.txt|All files (*.*)|*.*';
    LDialog.DefaultExt := 'log';
    LDialog.FileName := 'NativeGrep-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.log';
    LDialog.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if LDialog.Execute then
      try
        FOutput.SaveFile(LDialog.FileName, nlfeUTF8, False);
        AddLog('Log saved: ' + LDialog.FileName, nllSuccess);
      except
        on E: Exception do
          AddLog('Saving log failed: ' + E.Message, nllError);
      end;
  finally
    LDialog.Free;
  end;
end;

procedure TfrmNativeGrep.BuildListMenu;
  function AddMenuItem(AParent: TMenuItem; const ACaption: string;
    ATag: Integer; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FListMenu);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AClick;
    if AParent <> nil then
      AParent.Add(Result)
    else
      FListMenu.Items.Add(Result);
  end;

begin
  FListMenu := TThemedPopupMenu.Create(Self);
  FListMenu.OnPopup := ListMenuPopup;
  FMenuOpenExternal := AddMenuItem(nil, 'Open file (external)', 1, ListMenuClick);
  FMenuView := AddMenuItem(nil, 'View internally', 2, ListMenuClick);
  FMenuCode := AddMenuItem(nil, 'View in Code Editor', 3, ListMenuClick);
  FMenuHex := AddMenuItem(nil, 'View in Hex Viewer', 4, ListMenuClick);
  AddMenuItem(nil, '-', 0, nil);
  FMenuFolder := AddMenuItem(nil, 'Open containing folder', 5, ListMenuClick);
  AddMenuItem(nil, '-', 0, nil);
  FMenuName := AddMenuItem(nil, 'Copy filename', 6, ListMenuClick);
  FMenuDirectory := AddMenuItem(nil, 'Copy folder', 7, ListMenuClick);
  FMenuPath := AddMenuItem(nil, 'Copy complete path', 8, ListMenuClick);
  AddMenuItem(nil, '-', 0, nil);
  FMenuProperties := AddMenuItem(nil, 'File properties', 9, ListMenuClick);
  FList.PopupMenu := FListMenu;
end;

function TfrmNativeGrep.SelectedSourcePath: string;
var
  LIndex: Integer;
begin
  Result := '';
  LIndex := FResultView.SourceIndex(FList.SelectedIndex);
  if (LIndex >= 0) and (LIndex < FResults.Count) then
    Result := FResults[LIndex].SourcePath;
end;

procedure TfrmNativeGrep.ListMenuPopup(Sender: TObject);
var
  LPath: string;
  LAvailable: Boolean;
begin
  LPath := SelectedSourcePath;
  LAvailable := (LPath <> '') and FileExists(LPath);
  FMenuOpenExternal.Enabled := LAvailable;
  FMenuView.Enabled := LAvailable;
  FMenuCode.Enabled := LAvailable;
  FMenuHex.Enabled := LAvailable;
  FMenuFolder.Enabled := LPath <> '';
  FMenuName.Enabled := LPath <> '';
  FMenuDirectory.Enabled := LPath <> '';
  FMenuPath.Enabled := LPath <> '';
  FMenuProperties.Enabled := LAvailable;
end;

procedure TfrmNativeGrep.ListMenuClick(Sender: TObject);
var
  LPath: string;
  LFolder: string;
  LInfo: TShellExecuteInfo;
  LIndex: Integer;
  LTag: Integer;
begin
  LPath := SelectedSourcePath;
  if LPath = '' then
    Exit;
  LTag := TMenuItem(Sender).Tag;
  LFolder := ExcludeTrailingPathDelimiter(ExtractFilePath(LPath));
  try
    case LTag of
      1:
        if FileExists(LPath) and (ShellExecute(Handle, 'open', PChar(LPath),
          nil, nil, SW_SHOWNORMAL) <= 32) then
          RaiseLastOSError;
      2, 3, 4:
        begin
          if not FileExists(LPath) then
            raise EFileNotFoundException.Create('File not found: ' + LPath);
          if LTag = 3 then
            FViewerTabs.ActivePage := FCodeTab
          else if LTag = 4 then
            FViewerTabs.ActivePage := FHexTab;
          LIndex := FResultView.SourceIndex(FList.SelectedIndex);
          if (LIndex >= 0) and (LIndex < FResults.Count) then
            ShowMatch(FResults[LIndex]);
        end;
      5:
        if ShellExecute(Handle, 'open', 'explorer.exe',
          PChar('/select,"' + LPath + '"'), nil, SW_SHOWNORMAL) <= 32 then
          RaiseLastOSError;
      6: Clipboard.AsText := ExtractFileName(LPath);
      7: Clipboard.AsText := LFolder;
      8: Clipboard.AsText := LPath;
      9:
        begin
          FillChar(LInfo, SizeOf(LInfo), 0);
          LInfo.cbSize := SizeOf(LInfo);
          LInfo.fMask := SEE_MASK_INVOKEIDLIST;
          LInfo.Wnd := Handle;
          LInfo.lpVerb := 'properties';
          LInfo.lpFile := PChar(LPath);
          LInfo.nShow := SW_SHOWNORMAL;
          if not ShellExecuteEx(@LInfo) then
            RaiseLastOSError;
        end;
    end;
  except
    on E: Exception do
      AddLog('File action failed: ' + E.Message, nllError);
  end;
end;

procedure TfrmNativeGrep.ViewerTabChanged(Sender: TObject);
begin
  LoadViewerMatch(FViewerTabs.ActivePage);
end;

procedure TfrmNativeGrep.ViewerTabShown(Sender: TObject);
begin
  if Sender is TTabSheet then
    LoadViewerMatch(TTabSheet(Sender));
end;

procedure TfrmNativeGrep.LoadViewerMatch(ATab: TTabSheet);
var
  LIndex: Integer;
  LMatch: TGrepMatch;
begin
  if (FList = nil) or (FResults = nil) then
    Exit;
  LIndex := FResultView.SourceIndex(FList.SelectedIndex);
  if (LIndex < 0) or (LIndex >= FResults.Count) then
    LIndex := FSelectedMatchIndex;
  if (LIndex < 0) or (LIndex >= FResults.Count) then
    Exit;
  FSelectedMatchIndex := LIndex;
  LMatch := FResults[LIndex];
  FPreviewTitle.Caption := ExtractFileName(LMatch.SourcePath);
  FPreviewTitle.Hint := LMatch.SourcePath;
  FPreviewTitle.ShowHint := True;
  if ATab = FHexTab then
    ShowHexMatch(LMatch)
  else if ATab = FCodeTab then
    ShowCodeMatch(LMatch);
end;

procedure TfrmNativeGrep.LoadOptionalSkiaRenderer;
var
  LPath: string;
begin
  LPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'NimbusCodeEditorSkia.dll');
  if not FileExists(LPath) then
    Exit;
  try
    FPreview.RenderBackend := TCodeEditorDLLBackend.Create(LPath);
    AddLog('CodeEditor: Skia renderer enabled', nllInfo);
  except
    on E: Exception do
      AddLog('CodeEditor: Skia unavailable; default renderer: ' + E.Message, nllWarning);
  end;
end;

procedure TfrmNativeGrep.ShowMatch(const AMatch: TGrepMatch);
begin
  FPreviewTitle.Caption := ExtractFileName(AMatch.SourcePath);
  FPreviewTitle.Hint := AMatch.SourcePath;
  FPreviewTitle.ShowHint := True;
  if FViewerTabs.ActivePage = FHexTab then
    ShowHexMatch(AMatch)
  else
    ShowCodeMatch(AMatch);
end;

procedure TfrmNativeGrep.ShowHexMatch(const AMatch: TGrepMatch);
const
  MaxBookmarks = 300;
var
  LResult: TGrepMatch;
  LCount: Integer;
  LOffset: Int64;
  LLength: Int64;
begin
  try
    if not SameText(FHexFile, AMatch.SourcePath) then
    begin
      FHexFile := '';
      FHexMarkedCount := -1;
      FHex.LoadFromDataSource(TFileHexDataSource.Create(AMatch.SourcePath));
      FHexFile := AMatch.SourcePath;
    end;
    if FHexMarkedCount <> FResults.Count then
    begin
      FHex.ClearBookmarks;
      LCount := 0;
      for LResult in FResults do
      begin
        if (LCount >= MaxBookmarks) then
          Break;
        if SameText(LResult.SourcePath, FHexFile) and
           (LResult.ByteOffset >= 0) and
           (LResult.ByteOffset < FHex.DataLength) and
           (not FHex.Bookmarks.Contains(LResult.ByteOffset)) then
        begin
          FHex.AddBookmark(LResult.ByteOffset,
            Format('Match at 0x%x', [LResult.ByteOffset]),
            ThemeColor(255, 88, 156, 240));
          Inc(LCount);
        end;
      end;
      FHexMarkedCount := FResults.Count;
    end;
    LOffset := AMatch.ByteOffset;
    if (LOffset < 0) or (LOffset > FHex.DataLength) then
      Exit;
    LLength := Int64(AMatch.ByteLength);
    if LLength > FHex.DataLength - LOffset then
      LLength := FHex.DataLength - LOffset;
    if LLength > 65536 then
      LLength := 65536;
    FHex.SelectRange(LOffset, LLength);
  except
    on E: Exception do
    begin
      FHexFile := '';
      FHexMarkedCount := -1;
      FHex.Clear;
      AddLog('HexViewer: ' + AMatch.SourcePath + ': ' + E.Message, nllWarning);
    end;
  end;
end;


function TfrmNativeGrep.TryEditorMatch(const AMatch: TGrepMatch;
  AStream: TStream; out AHit: TCodeSearchMatch): Boolean;
var
  LLine, LColumn, LOffset, LLength: Integer;
  LData: TBytes;
  LText: string;
  LStart: TCodeDocumentPosition;
  LRange: TCodeDocumentRange;
begin
  Result := False;
  AHit := Default(TCodeSearchMatch);
  if (AMatch.Line <= 0) or (AMatch.Line > FPreview.Document.LineCount) or
    (AMatch.Column <= 0) or (AMatch.Column > High(Integer)) or
    (AMatch.ByteLength = 0) or (AMatch.ByteLength > 16384) or
    (AMatch.ByteOffset < 0) or (AMatch.ByteOffset > AStream.Size) or
    (Int64(AMatch.ByteLength) > AStream.Size - AMatch.ByteOffset) then
    Exit;
  LLine := Integer(AMatch.Line - 1);
  LColumn := Integer(AMatch.Column - 1);
  if LColumn > Length(FPreview.Document.GetLineText(LLine)) then
    Exit;
  LLength := Integer(AMatch.ByteLength);
  SetLength(LData, LLength);
  AStream.Position := AMatch.ByteOffset;
  AStream.ReadBuffer(LData[0], LLength);
  LText := TNimbusLogTextCodec.Decode(LData, FPreview.Document.Encoding);
  LText := StringReplace(LText, #13#10, #10, [rfReplaceAll]);
  LText := StringReplace(LText, #13, #10, [rfReplaceAll]);
  LStart := TCodeDocumentPosition.Create(LLine, LColumn);
  LOffset := FPreview.Document.GetOffset(LStart);
  if Length(LText) > FPreview.Document.TextLength - LOffset then
    Exit;
  LRange := TCodeDocumentRange.Create(LStart,
    FPreview.Document.GetPosition(LOffset + Length(LText)));
  if FPreview.GetTextRange(LRange) <> LText then
    Exit;
  AHit.Range := LRange;
  AHit.Text := LText;
  Result := True;
end;

procedure TfrmNativeGrep.RefreshPreviewHighlights;
const
  MaxHighlights = 2000;
  MaxBookmarks = 300;
var
  LStream: TFileStream;
  LHit: TCodeSearchMatch;
  LBookmarks: TCodeBookmark;
  LHighlights: TList<TCodeSearchMatch>;
  LMatch: TGrepMatch;
  LMarks: Integer;
begin
  if FPreviewFile = '' then
    Exit;
  LHighlights := TList<TCodeSearchMatch>.Create;
  try
    FPreview.ClearSearchMatches;
    FPreview.Bookmarks.Clear;
    LMarks := 0;
    LStream := TFileStream.Create(FPreviewFile, fmOpenRead or fmShareDenyNone);
    try
      for LMatch in FResults do
      begin
        if not SameText(LMatch.SourcePath, FPreviewFile) then
          Continue;
        if (LMatch.Line > 0) and (LMatch.Line <= FPreview.Document.LineCount) and
          (LMarks < MaxBookmarks) and
          (FPreview.Bookmarks.FindAtLine(Integer(LMatch.Line - 1)) < 0) then
        begin
          LBookmarks := Default(TCodeBookmark);
          LBookmarks.LineIndex := Integer(LMatch.Line - 1);
          FPreview.Bookmarks.Add(LBookmarks);
          Inc(LMarks);
        end;
        if LHighlights.Count >= MaxHighlights then
          Continue;
        try
          if TryEditorMatch(LMatch, LStream, LHit) then
            LHighlights.Add(LHit);
        except
          on E: EConvertError do Continue;
          on E: EArgumentException do Continue;
        end;
      end;
      FPreview.SetSearchMatches(LHighlights.ToArray);
      FPreviewMarkedCount := FResults.Count;
    finally
      LStream.Free;
    end;
  finally
    LHighlights.Free;
  end;
end;

procedure TfrmNativeGrep.ShowCodeMatch(const AMatch: TGrepMatch);
const
  MaxPreviewBytes = 16 * 1024 * 1024;
var
  LStream: TFileStream;
  LHit: TCodeSearchMatch;
begin
  FPreviewTitle.Caption := ExtractFileName(AMatch.SourcePath);
  FPreviewTitle.Hint := AMatch.SourcePath;
  FPreviewTitle.ShowHint := True;
  try
    if not SameText(FPreviewFile, AMatch.SourcePath) then
    begin
      FPreviewFile := '';
      FPreviewMarkedCount := -1;
      FPreview.ClearSearchMatches;
      FPreview.Bookmarks.Clear;
      if TFile.GetSize(AMatch.SourcePath) > MaxPreviewBytes then
      begin
        FPreview.Text := 'Editor preview limited to 16 MiB per file.' + sLineBreak +
          'The file remains searchable by NativeGrep.';
        Exit;
      end;
      FPreview.LoadFromFile(AMatch.SourcePath);
      FPreviewFile := AMatch.SourcePath;
    end;
    if FPreviewMarkedCount <> FResults.Count then
      RefreshPreviewHighlights;
    LStream := TFileStream.Create(AMatch.SourcePath, fmOpenRead or fmShareDenyNone);
    try
      try
        if TryEditorMatch(AMatch, LStream, LHit) then
          FPreview.GoToRange(LHit.Range)
        else if (AMatch.Line > 0) and (AMatch.Line <= FPreview.Document.LineCount) then
          FPreview.GoToLine(Integer(AMatch.Line - 1));
      except
        on E: EConvertError do
          if (AMatch.Line > 0) and (AMatch.Line <= FPreview.Document.LineCount) then
            FPreview.GoToLine(Integer(AMatch.Line - 1));
      end;
    finally
      LStream.Free;
    end;
  except
    on E: Exception do
    begin
      FPreviewFile := '';
      FPreviewMarkedCount := -1;
      FPreview.ClearSearchMatches;
      FPreview.Bookmarks.Clear;
      FPreview.Text := E.ClassName + ': ' + E.Message;
      AddLog('Editor: ' + AMatch.SourcePath + ': ' + E.Message, nllWarning);
    end;
  end;
end;

function TfrmNativeGrep.SettingsPath: string;
var
  LRoot: string;
begin
  LRoot := GetEnvironmentVariable('APPDATA');
  if LRoot = '' then
    LRoot := TPath.GetHomePath;
  LRoot := TPath.Combine(LRoot, 'NativeGrep');
  System.SysUtils.ForceDirectories(LRoot);
  Result := TPath.Combine(LRoot, 'GUI.ini');
end;

procedure TfrmNativeGrep.ReadSettings;
var
  LIni: TIniFile;
  LIndex: Integer;
begin
  LIni := TIniFile.Create(SettingsPath);
  try
    LIndex := FThemeCombo.Items.IndexOf(LIni.ReadString('Appearance', 'Theme', 'Dark Visual Studio'));
    if LIndex >= 0 then
      FThemeCombo.ItemIndex := LIndex;
    LIndex := FWorkerCombo.Items.IndexOf(LIni.ReadString('Search', 'Workers', 'Auto'));
    if LIndex >= 0 then
      FWorkerCombo.ItemIndex := LIndex;
    FFolderEdit.Text := LIni.ReadString('Search', 'Folder', FFolderEdit.Text);
    FPatternEdit.Text := LIni.ReadString('Search', 'Pattern', FPatternEdit.Text);
    FIncludeEdit.Text := LIni.ReadString('Search', 'Include', FIncludeEdit.Text);
    FRegexToggle.Checked := LIni.ReadBool('Search', 'Regex', FRegexToggle.Checked);
    FCaseToggle.Checked := LIni.ReadBool('Search', 'IgnoreCase', FCaseToggle.Checked);
    FRecursiveCheck.Checked := LIni.ReadBool('Search', 'Recursive', FRecursiveCheck.Checked);
    FInvalidUtfCheck.Checked := LIni.ReadBool('Search', 'InvalidUtf8', FInvalidUtfCheck.Checked);
    FHiddenCheck.Checked := LIni.ReadBool('Search', 'Hidden', FHiddenCheck.Checked);
    FGroupingCombo.ItemIndex := EnsureRange(LIni.ReadInteger('Results', 'Grouping', 1), 0, 2);
    FResultViewDirty := True;
    FSizeFirst.Text := LIni.ReadString('Filters', 'SizeFirst', '');
    FSizeSecond.Text := LIni.ReadString('Filters', 'SizeSecond', '');
    FCreatedFrom.Text := LIni.ReadString('Filters', 'CreatedFrom', '');
    FCreatedTo.Text := LIni.ReadString('Filters', 'CreatedTo', '');
    FModifiedFrom.Text := LIni.ReadString('Filters', 'ModifiedFrom', '');
    FModifiedTo.Text := LIni.ReadString('Filters', 'ModifiedTo', '');
    FAccessedFrom.Text := LIni.ReadString('Filters', 'AccessedFrom', '');
    FAccessedTo.Text := LIni.ReadString('Filters', 'AccessedTo', '');
    FExcludeEdit.Text := LIni.ReadString('Filters', 'Exclude', '');
    FSizeMode.ItemIndex := EnsureRange(LIni.ReadInteger('Filters', 'SizeMode', 0), 0, 6);
    FFiltersEnabled.Checked := LIni.ReadBool('Filters', 'Enabled', True);
    UpdateFilterControls;
    Width := Max(920, LIni.ReadInteger('Window', 'Width', Width));
    Height := Max(660, LIni.ReadInteger('Window', 'Height', Height));
  finally
    LIni.Free;
  end;
end;

procedure TfrmNativeGrep.WriteSettings;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(SettingsPath);
  try
    LIni.WriteString('Appearance', 'Theme', FThemeCombo.Text);
    LIni.WriteString('Search', 'Workers', FWorkerCombo.Text);
    LIni.WriteString('Search', 'Folder', FFolderEdit.Text);
    LIni.WriteString('Search', 'Pattern', FPatternEdit.Text);
    LIni.WriteString('Search', 'Include', FIncludeEdit.Text);
    LIni.WriteBool('Search', 'Regex', FRegexToggle.Checked);
    LIni.WriteBool('Search', 'IgnoreCase', FCaseToggle.Checked);
    LIni.WriteBool('Search', 'Recursive', FRecursiveCheck.Checked);
    LIni.WriteBool('Search', 'InvalidUtf8', FInvalidUtfCheck.Checked);
    LIni.WriteBool('Search', 'Hidden', FHiddenCheck.Checked);
    LIni.WriteInteger('Results', 'Grouping', FGroupingCombo.ItemIndex);
    LIni.WriteString('Filters', 'SizeFirst', FSizeFirst.Text);
    LIni.WriteString('Filters', 'SizeSecond', FSizeSecond.Text);
    LIni.WriteString('Filters', 'CreatedFrom', FCreatedFrom.Text);
    LIni.WriteString('Filters', 'CreatedTo', FCreatedTo.Text);
    LIni.WriteString('Filters', 'ModifiedFrom', FModifiedFrom.Text);
    LIni.WriteString('Filters', 'ModifiedTo', FModifiedTo.Text);
    LIni.WriteString('Filters', 'AccessedFrom', FAccessedFrom.Text);
    LIni.WriteString('Filters', 'AccessedTo', FAccessedTo.Text);
    LIni.WriteString('Filters', 'Exclude', FExcludeEdit.Text);
    LIni.WriteInteger('Filters', 'SizeMode', FSizeMode.ItemIndex);
    LIni.WriteBool('Filters', 'Enabled', FFiltersEnabled.Checked);
    if WindowState = wsNormal then
    begin
      LIni.WriteInteger('Window', 'Width', Width);
      LIni.WriteInteger('Window', 'Height', Height);
    end;
  finally
    LIni.Free;
  end;
end;

initialization
  RegisterClasses([TThemedButton, TThemedCheckBox, TThemedCodeEditor,
    TThemedComboBox, TThemedHexEditor, TThemedLabel,
    TThemedLogViewer, TThemedPanel, TThemedSplitContainer,
    TThemedTextBox, TThemedToggleBox, TThemedVirtualList, TThemedDatePicker]);

end.
