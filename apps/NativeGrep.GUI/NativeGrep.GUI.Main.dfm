object frmNativeGrep: TfrmNativeGrep
  Left = 0
  Top = 0
  Caption = 'NativeGrep'
  ClientHeight = 730
  ClientWidth = 1200
  Color = clWindow
  Constraints.MinHeight = 600
  Constraints.MinWidth = 920
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  TextHeight = 15
  object MainTabs: TThemedTabControl
    Left = 0
    Top = 0
    Width = 1200
    Height = 730
    ActivePage = RunTab
    Align = alClient
    StyleMode = stCompact
    CloseButtonMode = tcbmNone
    TabHeaderHorizontalPadding = 12
    TabHeaderHeight = 30
    TabOrder = 0
    object RunTab: TTabSheet
      Caption = 'Run Search'
      object FSearchHeader: TThemedPanel
        Left = 0
        Top = 0
        Width = 1192
        Height = 145
        ShowBorder = False
        CornerRadius = 0
        Align = alTop
        object FolderLabel: TThemedLabel
          Left = 15
          Top = 12
          Width = 66
          Height = 19
          AutoSize = False
          Caption = 'Folder'
          Layout = tlCenter
        end
        object PatternLabel: TThemedLabel
          Left = 15
          Top = 46
          Width = 66
          Height = 19
          AutoSize = False
          Caption = 'Find'
          Layout = tlCenter
        end
        object IncludeLabel: TThemedLabel
          Left = 15
          Top = 80
          Width = 66
          Height = 19
          AutoSize = False
          Caption = 'Files'
          Layout = tlCenter
        end
        object ReplaceLabel: TThemedLabel
          Left = 15
          Top = 117
          Width = 66
          Height = 19
          AutoSize = False
          Caption = 'Replace'
          Layout = tlCenter
        end
        object FFolderEdit: TThemedTextBox
          Left = 82
          Top = 6
          Width = 992
          Height = 29
          StyleMode = stCompact
          PlaceholderText = 'Search in folder...'
          Anchors = [akLeft, akTop, akRight]
        end
        object FPatternEdit: TThemedTextBox
          Left = 82
          Top = 39
          Width = 992
          Height = 29
          StyleMode = stCompact
          PlaceholderText = 'Text or regular expression (Enter to search)'
          Anchors = [akLeft, akTop, akRight]
          ShowClearButton = True
          OnEnterPressed = RunClick
          Text = 'TODO|FIXME'
        end
        object FIncludeEdit: TThemedTextBox
          Left = 82
          Top = 75
          Width = 677
          Height = 29
          StyleMode = stCompact
          PlaceholderText = '*.pas;*.cs;*.txt'
          Anchors = [akLeft, akTop, akRight]
          Text = '*.pas;*.dpr;*.dfm;*.cs;*.js;*.ts;*.txt;*.md;*.json;*.xml;*.log'
        end
        object FReplaceEdit: TThemedTextBox
          Left = 82
          Top = 110
          Width = 858
          Height = 29
          StyleMode = stCompact
          PlaceholderText = 'Replacement text (empty = delete matches)'
          Anchors = [akLeft, akTop, akRight]
        end
        object FBrowseButton: TThemedButton
          Left = 1087
          Top = 6
          Width = 87
          Height = 29
          Caption = 'Browse...'
          StyleMode = stCompact
          OnClick = BrowseClick
          ButtonStyle = tbstOutline
          Anchors = [akTop, akRight]
        end
        object FRunButton: TThemedButton
          Left = 1087
          Top = 39
          Width = 87
          Height = 29
          Caption = 'Search'
          StyleMode = stCompact
          OnClick = RunClick
          ButtonKind = tbkPrimary
          Anchors = [akTop, akRight]
        end
        object FReplaceSelectedButton: TThemedButton
          Left = 952
          Top = 110
          Width = 127
          Height = 29
          Caption = 'Replace selected'
          StyleMode = stCompact
          OnClick = ReplaceSelectedClick
          Enabled = False
          ButtonStyle = tbstOutline
          Anchors = [akTop, akRight]
        end
        object FReplaceAllButton: TThemedButton
          Left = 1087
          Top = 110
          Width = 87
          Height = 29
          Caption = 'Replace all'
          StyleMode = stCompact
          OnClick = ReplaceAllClick
          Enabled = False
          ButtonStyle = tbstOutline
          Anchors = [akTop, akRight]
        end
        object FRegexToggle: TThemedToggleBox
          Left = 773
          Top = 75
          Width = 108
          Height = 27
          StyleMode = stCompact
          Caption = 'Regex'
          Checked = True
          Anchors = [akTop, akRight]
        end
        object FCaseToggle: TThemedToggleBox
          Left = 891
          Top = 75
          Width = 138
          Height = 27
          StyleMode = stCompact
          Caption = 'Ignore case'
          Anchors = [akTop, akRight]
        end
        object FRecursiveCheck: TThemedCheckBox
          Left = 1039
          Top = 75
          Width = 128
          Height = 27
          StyleMode = stCompact
          Caption = 'Subfolders'
          Checked = True
          Anchors = [akTop, akRight]
        end
      end
      object FStatusPanel: TThemedPanel
        Left = 0
        Top = 669
        Width = 1192
        Height = 25
        ShowBorder = False
        CornerRadius = 0
        Align = alBottom
        object FStatus: TThemedLabel
          Left = 10
          Top = 4
          Width = 720
          Height = 18
          AutoSize = False
          Caption = 'Ready  |  F5 to search'
          Layout = tlCenter
          Anchors = [akLeft, akTop, akRight]
        end
        object FEngineLabel: TThemedLabel
          Left = 922
          Top = 4
          Width = 260
          Height = 18
          AutoSize = False
          Caption = 'NATIVEPATTERN3  /  PCRE2'
          Layout = tlCenter
          Alignment = taRightJustify
          UseMutedForeColor = True
          Anchors = [akTop, akRight]
        end
      end
      object FSplitOutput: TThemedSplitContainer
        Left = 0
        Top = 145
        Width = 1192
        Height = 524
        Align = alClient
        Orientation = tsoHorizontal
        SplitterWidth = 5
        SplitterDistance = 350
        Panel1MinSize = 170
        Panel2MinSize = 120
        object WorkspaceHost: TPanel
          Left = 0
          Top = 0
          Width = 1192
          Height = 350
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = False
          TabOrder = 0
          object FSplitWorkspace: TThemedSplitContainer
            Left = 0
            Top = 0
            Width = 1192
            Height = 350
            Align = alClient
            Orientation = tsoVertical
            SplitterWidth = 5
            SplitterDistance = 640
            Panel1MinSize = 300
            Panel2MinSize = 210
            object ResultsHost: TPanel
              Left = 0
              Top = 0
              Width = 640
              Height = 350
              BevelOuter = bvNone
              Caption = ''
              ParentBackground = False
              TabOrder = 0
              object ResultsHeader: TThemedPanel
                Left = 0
                Top = 0
                Width = 640
                Height = 27
                ShowBorder = False
                CornerRadius = 0
                Align = alTop
                object ResultsHeaderLabel: TThemedLabel
                  Left = 13
                  Top = 4
                  Width = 145
                  Height = 20
                  AutoSize = False
                  Caption = 'RESULTS'
                  Layout = tlCenter
                  Font.Style = [fsBold]
                end
                object FResultCount: TThemedLabel
                  Left = 526
                  Top = 0
                  Width = 114
                  Height = 27
                  AutoSize = False
                  Caption = '0 matches'
                  Layout = tlCenter
                  Align = alRight
                  Alignment = taRightJustify
                  UseMutedForeColor = True
                end
              end
              object FList: TThemedVirtualList
                Left = 0
                Top = 27
                Width = 640
                Height = 323
                Align = alClient
                StyleMode = stCompact
                EmptyText = 'No results  -  Enter a pattern and press F5'
                SelectionMode = vlsmMulti
                RowHeight = 23
                ShowRowDetails = True
                DetailsHeight = 92
                ShowSubtitles = False
                ShowDetails = False
                Columns = <
                  item
                    HeaderText = 'FILE'
                    Width = 285
                    Tag = 0
                    Sortable = False
                  end
                  item
                    HeaderText = 'LINE'
                    Width = 62
                    Tag = 1
                    Sortable = False
                  end
                  item
                    HeaderText = 'COL'
                    Width = 54
                    Tag = 2
                    Sortable = False
                  end
                  item
                    HeaderText = 'OFFSET'
                    Width = 100
                    Tag = 3
                    Sortable = False
                  end
                  item
                    HeaderText = 'BYTES'
                    Width = 59
                    Tag = 4
                    Sortable = False
                  end
                  item
                    HeaderText = 'STATE'
                    Width = 85
                    Tag = 5
                    Sortable = False
                  end>
              end
            end
            object ViewerHost: TPanel
              Left = 645
              Top = 0
              Width = 547
              Height = 350
              BevelOuter = bvNone
              Caption = ''
              ParentBackground = False
              TabOrder = 1
              object ViewerHeader: TThemedPanel
                Left = 0
                Top = 0
                Width = 547
                Height = 27
                ShowBorder = False
                CornerRadius = 0
                Align = alTop
                object ViewerHeaderLabel: TThemedLabel
                  Left = 13
                  Top = 4
                  Width = 145
                  Height = 20
                  AutoSize = False
                  Caption = 'VIEWER'
                  Layout = tlCenter
                  Font.Style = [fsBold]
                end
                object FPreviewTitle: TThemedLabel
                  Left = 97
                  Top = 5
                  Width = 440
                  Height = 18
                  AutoSize = False
                  Caption = 'Select a match'
                  Layout = tlCenter
                  UseMutedForeColor = True
                  Anchors = [akLeft, akTop, akRight]
                end
              end
              object FViewerTabs: TThemedTabControl
                Left = 0
                Top = 27
                Width = 547
                Height = 323
                Align = alClient
                ActivePage = FCodeTab
                StyleMode = stCompact
                TabHeaderHeight = 29
                CloseButtonMode = tcbmNone
                object FCodeTab: TTabSheet
                  Caption = 'Code Editor'
                  object FPreview: TThemedCodeEditor
                    Left = 0
                    Top = 0
                    Width = 539
                    Height = 286
                    Align = alClient
                    ReadOnly = True
                    Font.Name = 'Consolas'
                    Font.Height = -13
                    Options.ShowLineNumbers = True
                    Options.ShowBookmarks = True
                    Options.ShowSearchMatches = True
                    Options.ShowOverviewRuler = True
                    Options.WordWrap = False
                    Options.AutoShowCompletion = False
                    Options.EnableLargeFileMode = True
                    Text = 'Select a result to view the source file.'
                  end
                end
                object FHexTab: TTabSheet
                  Caption = 'Hex Viewer'
                  ImageIndex = 1
                  object FHex: TThemedHexEditor
                    Left = 0
                    Top = 0
                    Width = 539
                    Height = 286
                    Align = alClient
                    Font.Name = 'Consolas'
                    Font.Height = -13
                  end
                end
              end
            end
          end
        end
        object OutputHost: TPanel
          Left = 0
          Top = 355
          Width = 1192
          Height = 169
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = False
          TabOrder = 1
          object OutputHeader: TThemedPanel
            Left = 0
            Top = 0
            Width = 1192
            Height = 27
            ShowBorder = False
            CornerRadius = 0
            Align = alTop
            object OutputHeaderLabel: TThemedLabel
              Left = 13
              Top = 4
              Width = 145
              Height = 20
              AutoSize = False
              Caption = 'OUTPUT'
              Layout = tlCenter
              Font.Style = [fsBold]
            end
            object ClearOutputButton: TThemedButton
              Left = 1120
              Top = 0
              Width = 72
              Height = 27
              Caption = 'Clear'
              StyleMode = stCompact
              OnClick = ClearOutputClick
              ButtonStyle = tbstGhost
              Align = alRight
            end
            object SaveLogButton: TThemedButton
              Left = 1038
              Top = 0
              Width = 82
              Height = 27
              Caption = 'Save log'
              StyleMode = stCompact
              OnClick = SaveLogClick
              ButtonStyle = tbstGhost
              Align = alRight
            end
          end
          object FOutput: TThemedLogViewer
            Left = 0
            Top = 27
            Width = 1192
            Height = 142
            Align = alClient
            StyleMode = stCompact
            ShowToolbar = False
            ShowStatusBar = False
            ShowLineNumbers = False
            FollowTail = True
            MaxLines = 10000
          end
        end
      end
    end
    object OptionsTab: TTabSheet
      Caption = 'Options'
      ImageIndex = 1
      object OptionsSurface: TThemedPanel
        Left = 0
        Top = 0
        Width = 1192
        Height = 694
        ShowBorder = False
        CornerRadius = 0
        Align = alClient
        object AppearanceHeader: TThemedPanel
          Left = 16
          Top = 16
          Width = 1160
          Height = 28
          ShowBorder = False
          CornerRadius = 0
          Anchors = [akLeft, akTop, akRight]
          object AppearanceHeaderLabel: TThemedLabel
            Left = 12
            Top = 4
            Width = 300
            Height = 19
            AutoSize = False
            Caption = 'APPEARANCE'
            Layout = tlCenter
          end
        end
        object EngineHeader: TThemedPanel
          Left = 16
          Top = 130
          Width = 1160
          Height = 28
          ShowBorder = False
          CornerRadius = 0
          Anchors = [akLeft, akTop, akRight]
          object EngineHeaderLabel: TThemedLabel
            Left = 12
            Top = 4
            Width = 300
            Height = 19
            AutoSize = False
            Caption = 'SEARCH ENGINE'
            Layout = tlCenter
          end
        end
        object LimitsHeader: TThemedPanel
          Left = 16
          Top = 298
          Width = 1160
          Height = 28
          ShowBorder = False
          CornerRadius = 0
          Anchors = [akLeft, akTop, akRight]
          object LimitsHeaderLabel: TThemedLabel
            Left = 12
            Top = 4
            Width = 300
            Height = 19
            AutoSize = False
            Caption = 'RUNTIME / LIMITS'
            Layout = tlCenter
          end
        end
        object ThemeLabel: TThemedLabel
          Left = 25
          Top = 59
          Width = 136
          Height = 19
          AutoSize = False
          Caption = 'Theme'
          Layout = tlCenter
        end
        object FThemeCombo: TThemedComboBox
          Left = 190
          Top = 54
          Width = 310
          Height = 28
        end
        object ThemeInfo: TThemedLabel
          Left = 190
          Top = 88
          Width = 460
          Height = 19
          AutoSize = False
          Caption = 'Visual appearance of the entire workbench'
          Layout = tlCenter
          UseMutedForeColor = True
        end
        object WorkersLabel: TThemedLabel
          Left = 25
          Top = 173
          Width = 136
          Height = 19
          AutoSize = False
          Caption = 'Workers'
          Layout = tlCenter
        end
        object FWorkerCombo: TThemedComboBox
          Left = 190
          Top = 168
          Width = 168
          Height = 28
          Items.Strings = (
            'Auto'
            '1'
            '2'
            '4'
            '8')
          ItemIndex = 0
        end
        object FInvalidUtfCheck: TThemedCheckBox
          Left = 190
          Top = 210
          Width = 510
          Height = 27
          StyleMode = stCompact
          Caption = 'Tolerate invalid UTF-8 in regex searches'
          Checked = True
        end
        object FHiddenCheck: TThemedCheckBox
          Left = 190
          Top = 241
          Width = 510
          Height = 27
          StyleMode = stCompact
          Caption = 'Include hidden files'
        end
        object RegexLimitLabel: TThemedLabel
          Left = 25
          Top = 341
          Width = 136
          Height = 19
          AutoSize = False
          Caption = 'Regex file limit'
          Layout = tlCenter
        end
        object RegexLimitInfo: TThemedLabel
          Left = 190
          Top = 341
          Width = 450
          Height = 19
          AutoSize = False
          Caption = '64 MiB per file'
          Layout = tlCenter
          UseMutedForeColor = True
        end
        object RegexBackendLabel: TThemedLabel
          Left = 25
          Top = 372
          Width = 136
          Height = 19
          AutoSize = False
          Caption = 'Regex backend'
          Layout = tlCenter
        end
        object RegexBackendInfo: TThemedLabel
          Left = 190
          Top = 372
          Width = 680
          Height = 19
          AutoSize = False
          Caption = 'PCRE2 requires a Win64 pcre2-8.dll beside NativeGrepGUI.exe'
          Layout = tlCenter
          UseMutedForeColor = True
        end
        object PreferencesLabel: TThemedLabel
          Left = 25
          Top = 403
          Width = 136
          Height = 19
          AutoSize = False
          Caption = 'Preferences'
          Layout = tlCenter
        end
        object PreferencesInfo: TThemedLabel
          Left = 190
          Top = 403
          Width = 550
          Height = 19
          AutoSize = False
          Caption = '%APPDATA%\NativeGrep\GUI.ini'
          Layout = tlCenter
          UseMutedForeColor = True
        end
      end
    end
  end
end
