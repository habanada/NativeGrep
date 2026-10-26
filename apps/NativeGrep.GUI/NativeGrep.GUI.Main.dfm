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
    DoubleBuffered = True
    ParentDoubleBuffered = False
    TabOrder = 0
    StyleElements = []
    StyleMode = stCompact
    CloseButtonMode = tcbmNone
    TabHeaderHorizontalPadding = 12
    TabHeaderHeight = 30
    object RunTab: TTabSheet
      Caption = 'Run Search'
      object FSearchHeader: TThemedPanel
        Left = 0
        Top = 0
        Width = 1200
        Height = 145
        Align = alTop
        ShowBorder = False
        TabOrder = 0
        DesignSize = (
          1200
          145)
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
          Height = 24
          StyleMode = stCompact
          Anchors = [akLeft, akTop, akRight]
          InnerPadding.Left = 6
          InnerPadding.Top = 5
          InnerPadding.Right = 6
          InnerPadding.Bottom = 5
          PlaceholderText = 'Search in folder...'
          TabOrder = 0
          Text = ''
        end
        object FPatternEdit: TThemedTextBox
          Left = 82
          Top = 39
          Width = 992
          Height = 24
          StyleMode = stCompact
          Anchors = [akLeft, akTop, akRight]
          InnerPadding.Left = 6
          InnerPadding.Top = 5
          InnerPadding.Right = 6
          InnerPadding.Bottom = 5
          PlaceholderText = 'Text or regular expression (Enter to search)'
          ShowClearButton = True
          TabOrder = 1
          Text = 'TODO|FIXME'
          OnEnterPressed = RunClick
        end
        object FIncludeEdit: TThemedTextBox
          Left = 82
          Top = 75
          Width = 677
          Height = 24
          StyleMode = stCompact
          Anchors = [akLeft, akTop, akRight]
          InnerPadding.Left = 6
          InnerPadding.Top = 5
          InnerPadding.Right = 6
          InnerPadding.Bottom = 5
          PlaceholderText = '*.pas;*.cs;*.txt'
          TabOrder = 2
          Text = '*.pas;*.dpr;*.dfm;*.cs;*.js;*.ts;*.txt;*.md;*.json;*.xml;*.log'
        end
        object FReplaceEdit: TThemedTextBox
          Left = 82
          Top = 110
          Width = 858
          Height = 24
          StyleMode = stCompact
          Anchors = [akLeft, akTop, akRight]
          InnerPadding.Left = 6
          InnerPadding.Top = 5
          InnerPadding.Right = 6
          InnerPadding.Bottom = 5
          PlaceholderText = 'Replacement text (empty = delete matches)'
          TabOrder = 3
          Text = ''
        end
        object FBrowseButton: TThemedButton
          Left = 1087
          Top = 6
          Width = 87
          Height = 29
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          ButtonStyle = tbstOutline
          ContentPadding.Left = 10
          ContentPadding.Top = 5
          ContentPadding.Right = 10
          ContentPadding.Bottom = 5
          Caption = 'Browse...'
          Constraints.MinHeight = 24
          Constraints.MinWidth = 24
          TabOrder = 4
          OnClick = BrowseClick
        end
        object FRunButton: TThemedButton
          Left = 1087
          Top = 39
          Width = 87
          Height = 29
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          ButtonKind = tbkPrimary
          ContentPadding.Left = 10
          ContentPadding.Top = 5
          ContentPadding.Right = 10
          ContentPadding.Bottom = 5
          Caption = 'Search'
          Constraints.MinHeight = 24
          Constraints.MinWidth = 24
          TabOrder = 5
          OnClick = RunClick
        end
        object FReplaceSelectedButton: TThemedButton
          Left = 952
          Top = 110
          Width = 127
          Height = 29
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          ButtonStyle = tbstOutline
          ContentPadding.Left = 10
          ContentPadding.Top = 5
          ContentPadding.Right = 10
          ContentPadding.Bottom = 5
          Caption = 'Replace selected'
          Constraints.MinHeight = 24
          Constraints.MinWidth = 24
          Enabled = False
          TabOrder = 6
          OnClick = ReplaceSelectedClick
        end
        object FReplaceAllButton: TThemedButton
          Left = 1087
          Top = 110
          Width = 87
          Height = 29
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          ButtonStyle = tbstOutline
          ContentPadding.Left = 10
          ContentPadding.Top = 5
          ContentPadding.Right = 10
          ContentPadding.Bottom = 5
          Caption = 'Replace all'
          Constraints.MinHeight = 24
          Constraints.MinWidth = 24
          Enabled = False
          TabOrder = 7
          OnClick = ReplaceAllClick
        end
        object FRegexToggle: TThemedToggleBox
          Left = 773
          Top = 75
          Width = 108
          Height = 27
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          Caption = 'Regex'
          Checked = True
          CheckedText = 'ON'
          OnText = 'ON'
          OffText = 'OFF'
          TabOrder = 8
          UncheckedText = 'OFF'
        end
        object FCaseToggle: TThemedToggleBox
          Left = 891
          Top = 75
          Width = 138
          Height = 27
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          Caption = 'Ignore case'
          CheckedText = 'ON'
          OnText = 'ON'
          OffText = 'OFF'
          TabOrder = 9
          UncheckedText = 'OFF'
        end
        object FRecursiveCheck: TThemedCheckBox
          Left = 1039
          Top = 75
          Width = 128
          Height = 27
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          Caption = 'Subfolders'
          Checked = True
          State = cbChecked
          TabOrder = 10
        end
      end
      object FStatusPanel: TThemedPanel
        Left = 0
        Top = 683
        Width = 1200
        Height = 25
        Align = alBottom
        ShowBorder = False
        TabOrder = 1
        DesignSize = (
          1200
          25)
        object FStatus: TThemedLabel
          Left = 10
          Top = 4
          Width = 720
          Height = 18
          Anchors = [akLeft, akTop, akRight]
          AutoSize = False
          Caption = 'Ready  |  F5 to search'
          Layout = tlCenter
        end
        object FEngineLabel: TThemedLabel
          Left = 922
          Top = 4
          Width = 260
          Height = 18
          Alignment = taRightJustify
          Anchors = [akTop, akRight]
          AutoSize = False
          Caption = 'NATIVEPATTERN3  /  PCRE2'
          Layout = tlCenter
          UseMutedForeColor = True
        end
      end
      object FSplitOutput: TThemedSplitContainer
        Left = 0
        Top = 145
        Width = 1200
        Height = 538
        Align = alClient
        Orientation = tsoHorizontal
        Panel1.Left = 0
        Panel1.Top = 0
        Panel1.Width = 1200
        Panel1.Height = 413
        Panel1.BevelOuter = bvNone
        Panel1.TabOrder = 2
        Panel2.Left = 0
        Panel2.Top = 418
        Panel2.Width = 1200
        Panel2.Height = 120
        Panel2.BevelOuter = bvNone
        Panel2.TabOrder = 3
        Panel1MinSize = 170
        Panel2MinSize = 120
        ShowHint = True
        SplitterDistance = 765
        SplitterWidth = 5
        TabOrder = 2
        object WorkspaceHost: TPanel
          Left = 0
          Top = 0
          Width = 1192
          Height = 350
          BevelOuter = bvNone
          ParentBackground = False
          TabOrder = 0
          object FSplitWorkspace: TThemedSplitContainer
            Left = 0
            Top = 0
            Width = 1192
            Height = 350
            Align = alClient
            Panel1.Left = 0
            Panel1.Top = 0
            Panel1.Width = 640
            Panel1.Height = 350
            Panel1.BevelOuter = bvNone
            Panel1.TabOrder = 2
            Panel2.Left = 645
            Panel2.Top = 0
            Panel2.Width = 547
            Panel2.Height = 350
            Panel2.BevelOuter = bvNone
            Panel2.TabOrder = 3
            Panel1MinSize = 300
            Panel2MinSize = 210
            ShowHint = True
            SplitterDistance = 640
            SplitterWidth = 5
            TabOrder = 0
            object ResultsHost: TPanel
              Left = 0
              Top = 0
              Width = 640
              Height = 350
              BevelOuter = bvNone
              ParentBackground = False
              TabOrder = 0
              object ResultsHeader: TThemedPanel
                Left = 0
                Top = 0
                Width = 640
                Height = 27
                Align = alTop
                ShowBorder = False
                TabOrder = 0
                object ResultsHeaderLabel: TThemedLabel
                  Left = 13
                  Top = 4
                  Width = 145
                  Height = 20
                  AutoSize = False
                  Caption = 'RESULTS'
                  Font.Charset = DEFAULT_CHARSET
                  Font.Color = clWindowText
                  Font.Height = -12
                  Font.Name = 'Segoe UI'
                  Font.Style = [fsBold]
                  Layout = tlCenter
                  ParentFont = False
                end
                object FResultCount: TThemedLabel
                  Left = 526
                  Top = 0
                  Width = 114
                  Height = 27
                  Align = alRight
                  Alignment = taRightJustify
                  AutoSize = False
                  Caption = '0 matches'
                  Layout = tlCenter
                  UseMutedForeColor = True
                end
              end
              object FList: TThemedVirtualList
                Left = 0
                Top = 27
                Width = 640
                Height = 323
                StyleMode = stCompact
                Align = alClient
                ParentColor = False
                TabOrder = 1
                Columns = <
                  item
                    HeaderText = 'FILE'
                    Width = 285
                    Sortable = False
                  end
                  item
                    HeaderText = 'LINE'
                    Width = 62
                    Sortable = False
                    Tag = 1
                  end
                  item
                    HeaderText = 'COL'
                    Width = 54
                    Sortable = False
                    Tag = 2
                  end
                  item
                    HeaderText = 'OFFSET'
                    Width = 100
                    Sortable = False
                    Tag = 3
                  end
                  item
                    HeaderText = 'BYTES'
                    Width = 59
                    Sortable = False
                    Tag = 4
                  end
                  item
                    HeaderText = 'STATE'
                    Width = 85
                    Sortable = False
                    Tag = 5
                  end>
                HeaderHeight = 22
                FilterHeight = 22
                ShowRowDetails = True
                DetailsHeight = 92
                GroupHeaderHeight = 20
                RowHeight = 23
                RowBadgeOptions.Anchor = vlibaCenterRight
                RowBadgeOptions.ClipMode = vlibcClipToTarget
                RowBadgeOptions.OffsetX = -8
                RowBadgeOptions.Scale = 1.000000000000000000
                RowBadgeOptions.Opacity = 1.000000000000000000
                RowBadgeOptions.DrawShadow = False
                CellBadgeOptions.Anchor = vlibaCenterRight
                CellBadgeOptions.ClipMode = vlibcClipToTarget
                CellBadgeOptions.OffsetX = -4
                CellBadgeOptions.Scale = 1.000000000000000000
                CellBadgeOptions.Opacity = 1.000000000000000000
                CellBadgeOptions.DrawShadow = False
                ItemHeight = 23
                ShowSubtitles = False
                ShowDetails = False
                EmptyText = 'No results  -  Enter a pattern and press F5'
              end
            end
            object ViewerHost: TPanel
              Left = 645
              Top = 0
              Width = 547
              Height = 350
              BevelOuter = bvNone
              ParentBackground = False
              TabOrder = 1
              object ViewerHeader: TThemedPanel
                Left = 0
                Top = 0
                Width = 547
                Height = 27
                Align = alTop
                ShowBorder = False
                TabOrder = 0
                DesignSize = (
                  547
                  27)
                object ViewerHeaderLabel: TThemedLabel
                  Left = 13
                  Top = 4
                  Width = 145
                  Height = 20
                  AutoSize = False
                  Caption = 'VIEWER'
                  Font.Charset = DEFAULT_CHARSET
                  Font.Color = clWindowText
                  Font.Height = -12
                  Font.Name = 'Segoe UI'
                  Font.Style = [fsBold]
                  Layout = tlCenter
                  ParentFont = False
                end
                object FPreviewTitle: TThemedLabel
                  Left = 97
                  Top = 5
                  Width = 440
                  Height = 18
                  Anchors = [akLeft, akTop, akRight]
                  AutoSize = False
                  Caption = 'Select a match'
                  Layout = tlCenter
                  UseMutedForeColor = True
                end
              end
              object FViewerTabs: TThemedTabControl
                Left = 0
                Top = 27
                Width = 547
                Height = 323
                ActivePage = FCodeTab
                Align = alClient
                DoubleBuffered = True
                ParentDoubleBuffered = False
                TabOrder = 1
                StyleElements = []
                StyleMode = stCompact
                CloseButtonMode = tcbmNone
                TabHeaderHeight = 29
                object FCodeTab: TTabSheet
                  Caption = 'Code Editor'
                  object FPreview: TThemedCodeEditor
                    Left = 0
                    Top = 0
                    Width = 547
                    Height = 302
                    Cursor = crIBeam
                    Align = alClient
                    Font.Charset = DEFAULT_CHARSET
                    Font.Color = clWindowText
                    Font.Height = -13
                    Font.Name = 'Consolas'
                    Font.Style = []
                    ParentFont = False
                    TabOrder = 0
                    Text = 'Select a result to view the source file.'
                    ReadOnly = True
                    Options.AutoShowCompletion = False
                    CommentStyles = <
                      item
                        Keyword = 'TODO'
                        ForeColor = 0
                        BackColor = 0
                        BorderColor = 0
                        FontStyle = [fsBold]
                        FontScale = 1.000000000000000000
                      end
                      item
                        Keyword = 'FIXME'
                        ForeColor = 0
                        BackColor = 0
                        BorderColor = 0
                        FontStyle = [fsBold]
                        FontScale = 1.000000000000000000
                      end
                      item
                        Keyword = 'WARNING'
                        ForeColor = 0
                        BackColor = 0
                        BorderColor = 0
                        FontStyle = [fsBold]
                        FontScale = 1.000000000000000000
                      end
                      item
                        Keyword = 'WARN'
                        ForeColor = 0
                        BackColor = 0
                        BorderColor = 0
                        FontStyle = [fsBold]
                        FontScale = 1.000000000000000000
                      end
                      item
                        Keyword = 'NOTE'
                        ForeColor = 0
                        BackColor = 0
                        BorderColor = 0
                        FontStyle = [fsBold]
                        FontScale = 1.000000000000000000
                      end
                      item
                        Keyword = 'HACK'
                        ForeColor = 0
                        BackColor = 0
                        BorderColor = 0
                        FontStyle = [fsBold]
                        FontScale = 1.000000000000000000
                      end>
                    LanguageName = 'csharp'
                  end
                end
                object FHexTab: TTabSheet
                  Caption = 'Hex Viewer'
                  ImageIndex = 1
                  object FHex: TThemedHexEditor
                    Left = 0
                    Top = 0
                    Width = 547
                    Height = 302
                    Align = alClient
                    Font.Charset = DEFAULT_CHARSET
                    Font.Color = clWindowText
                    Font.Height = -13
                    Font.Name = 'Consolas'
                    Font.Style = []
                    TabOrder = 0
                    ExplicitLeft = 3
                    ExplicitTop = -1
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
          ParentBackground = False
          TabOrder = 1
          object OutputHeader: TThemedPanel
            Left = 0
            Top = 0
            Width = 1192
            Height = 27
            Align = alTop
            ShowBorder = False
            TabOrder = 0
            object OutputHeaderLabel: TThemedLabel
              Left = 13
              Top = 4
              Width = 145
              Height = 20
              AutoSize = False
              Caption = 'OUTPUT'
              Font.Charset = DEFAULT_CHARSET
              Font.Color = clWindowText
              Font.Height = -12
              Font.Name = 'Segoe UI'
              Font.Style = [fsBold]
              Layout = tlCenter
              ParentFont = False
            end
            object ClearOutputButton: TThemedButton
              Left = 1120
              Top = 0
              Width = 72
              Height = 27
              StyleMode = stCompact
              Align = alRight
              ButtonStyle = tbstGhost
              ContentPadding.Left = 10
              ContentPadding.Top = 5
              ContentPadding.Right = 10
              ContentPadding.Bottom = 5
              Caption = 'Clear'
              Constraints.MinHeight = 24
              Constraints.MinWidth = 24
              TabOrder = 0
              OnClick = ClearOutputClick
            end
            object SaveLogButton: TThemedButton
              Left = 1038
              Top = 0
              Width = 82
              Height = 27
              StyleMode = stCompact
              Align = alRight
              ButtonStyle = tbstGhost
              ContentPadding.Left = 10
              ContentPadding.Top = 5
              ContentPadding.Right = 10
              ContentPadding.Bottom = 5
              Caption = 'Save log'
              Constraints.MinHeight = 24
              Constraints.MinWidth = 24
              TabOrder = 1
              OnClick = SaveLogClick
            end
          end
          object FOutput: TThemedLogViewer
            Left = 0
            Top = 27
            Width = 1192
            Height = 142
            Align = alClient
            StyleMode = stCompact
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -12
            Font.Name = 'Consolas'
            Font.Style = []
            ParentFont = False
            MaxLines = 10000
            ShowToolbar = False
            ShowStatusBar = False
            ShowLineNumbers = False
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
        Width = 1200
        Height = 708
        Align = alClient
        ShowBorder = False
        TabOrder = 0
        DesignSize = (
          1200
          708)
        object ThemeLabel: TThemedLabel
          Left = 25
          Top = 59
          Width = 136
          Height = 19
          AutoSize = False
          Caption = 'Theme'
          Layout = tlCenter
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
        object AppearanceHeader: TThemedPanel
          Left = 16
          Top = 16
          Width = 1160
          Height = 28
          Anchors = [akLeft, akTop, akRight]
          ShowBorder = False
          TabOrder = 0
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
          Anchors = [akLeft, akTop, akRight]
          ShowBorder = False
          TabOrder = 1
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
          Anchors = [akLeft, akTop, akRight]
          ShowBorder = False
          TabOrder = 2
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
        object FThemeCombo: TThemedComboBox
          Left = 190
          Top = 54
          Width = 310
          Height = 24
          TabOrder = 3
        end
        object FWorkerCombo: TThemedComboBox
          Left = 190
          Top = 168
          Width = 168
          Height = 24
          ItemIndex = 0
          TabOrder = 4
          Text = 'Auto'
          Items.Strings = (
            'Auto'
            '1'
            '2'
            '4'
            '8')
        end
        object FInvalidUtfCheck: TThemedCheckBox
          Left = 190
          Top = 210
          Width = 510
          Height = 27
          StyleMode = stCompact
          Caption = 'Tolerate invalid UTF-8 in regex searches'
          Checked = True
          State = cbChecked
          TabOrder = 5
        end
        object FHiddenCheck: TThemedCheckBox
          Left = 190
          Top = 241
          Width = 510
          Height = 27
          StyleMode = stCompact
          Caption = 'Include hidden files'
          TabOrder = 6
        end
      end
    end
  end
end
