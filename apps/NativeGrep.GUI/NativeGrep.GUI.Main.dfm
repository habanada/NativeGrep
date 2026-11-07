object frmNativeGrep: TfrmNativeGrep
  Left = 0
  Top = 0
  Caption = 'NativeGrep'
  ClientHeight = 730
  ClientWidth = 1200
  Color = clWindow
  Constraints.MinHeight = 660
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
          Width = 828
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
          Left = 922
          Top = 110
          Width = 137
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
          Left = 1067
          Top = 110
          Width = 107
          Height = 29
          StyleMode = stCompact
          Anchors = [akTop, akRight]
          ButtonStyle = tbstOutline
          ContentPadding.Left = 10
          ContentPadding.Top = 5
          ContentPadding.Right = 10
          ContentPadding.Bottom = 5
          Caption = 'Replace visible'
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
                  Left = 440
                  Top = 0
                  Width = 200
                  Height = 27
                  Align = alRight
                  Alignment = taRightJustify
                  AutoSize = False
                  Caption = '0 matches'
                  Layout = tlCenter
                  UseMutedForeColor = True
                end
              end
              object ResultTools: TThemedPanel
                Left = 0
                Top = 27
                Width = 640
                Height = 64
                Align = alTop
                ShowBorder = False
                TabOrder = 1
                DesignSize = (
                  640
                  64)
                object FResultFilter: TThemedTextBox
                  Left = 8
                  Top = 3
                  Width = 624
                  Height = 26
                  StyleMode = stCompact
                  Anchors = [akLeft, akTop, akRight]
                  PlaceholderText = 'Filter results: path, text, line or offset (Ctrl+F)'
                  ShowClearButton = True
                  TabOrder = 0
                end
                object GroupingLabel: TThemedLabel
                  Left = 8
                  Top = 36
                  Width = 60
                  Height = 22
                  AutoSize = False
                  Caption = 'Group by'
                  Layout = tlCenter
                end
                object FGroupingCombo: TThemedComboBox
                  Left = 74
                  Top = 34
                  Width = 200
                  Height = 26
                  ItemIndex = 1
                  Text = 'File'
                  Items.Strings = (
                    'No grouping'
                    'File'
                    'Folder')
                  TabOrder = 1
                end
              end
              object FList: TThemedVirtualList
                Left = 0
                Top = 91
                Width = 640
                Height = 259
                StyleMode = stCompact
                Align = alClient
                ParentColor = False
                TabOrder = 2
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
                  end
                  item
                    HeaderText = 'MATCH TEXT'
                    Width = 360
                    Sortable = False
                    Tag = 6
                  end>
                HeaderHeight = 22
                FilterHeight = 22
                ShowRowDetails = True
                ShowGroupHeaders = True
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
    object FiltersTab: TTabSheet
      Caption = 'File filters'
      object FilterSurface: TThemedPanel
        Align = alClient
        ShowBorder = False
        TabOrder = 0
        object FFiltersEnabled: TThemedCheckBox
          Left = 25
          Top = 16
          Width = 230
          Height = 27
          Caption = 'Apply file filters'
          Checked = True
          State = cbChecked
          TabOrder = 0
        end
        object FiltersInfo: TThemedLabel
          Left = 25
          Top = 49
          Width = 760
          Height = 22
          AutoSize = False
          Caption = 'All enabled conditions must match. Blank bounds are unlimited.'
          Layout = tlCenter
        end
        object SizeFilterLabel: TThemedLabel
          Left = 25
          Top = 87
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'File size'
          Layout = tlCenter
        end
        object FSizeMode: TThemedComboBox
          Left = 190
          Top = 84
          Width = 180
          Height = 26
          ItemIndex = 0
          Text = 'Any size'
          Items.Strings = (
            'Any size'
            'Smaller than'
            'At most'
            'Larger than'
            'At least'
            'Exactly'
            'Between (inclusive)')
          TabOrder = 1
        end
        object FSizeFirst: TThemedTextBox
          Left = 382
          Top = 84
          Width = 184
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'e.g. 1.5 MiB'
          ShowClearButton = True
          TabOrder = 2
        end
        object SizeToLabel: TThemedLabel
          Left = 575
          Top = 87
          Width = 25
          Height = 22
          AutoSize = False
          Caption = 'to'
          Layout = tlCenter
        end
        object FSizeSecond: TThemedTextBox
          Left = 610
          Top = 84
          Width = 184
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'e.g. 100 MiB'
          ShowClearButton = True
          TabOrder = 3
        end
        object SizeUnitsInfo: TThemedLabel
          Left = 190
          Top = 118
          Width = 760
          Height = 22
          AutoSize = False
          Caption = 'B, KB/MB/GB/TB = decimal; KiB/MiB/GiB/TiB = binary. Exactly 0 selects empty files.'
          Layout = tlCenter
        end
        object TimeFromLabel: TThemedLabel
          Left = 190
          Top = 159
          Width = 250
          Height = 22
          AutoSize = False
          Caption = 'From (inclusive)'
          Layout = tlCenter
        end
        object TimeToLabel: TThemedLabel
          Left = 502
          Top = 159
          Width = 350
          Height = 22
          AutoSize = False
          Caption = 'To (inclusive; dates include the whole day)'
          Layout = tlCenter
        end
        object CreatedFilterLabel: TThemedLabel
          Left = 25
          Top = 193
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'Created'
          Layout = tlCenter
        end
        object FCreatedFrom: TThemedTextBox
          Left = 190
          Top = 190
          Width = 300
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'YYYY-MM-DD or date and time'
          ShowClearButton = True
          TabOrder = 4
        end
        object FCreatedTo: TThemedTextBox
          Left = 502
          Top = 190
          Width = 300
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'Blank = no upper limit'
          ShowClearButton = True
          TabOrder = 5
        end
        object ModifiedFilterLabel: TThemedLabel
          Left = 25
          Top = 237
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'Modified'
          Layout = tlCenter
        end
        object FModifiedFrom: TThemedTextBox
          Left = 190
          Top = 234
          Width = 300
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'YYYY-MM-DD or date and time'
          ShowClearButton = True
          TabOrder = 6
        end
        object FModifiedTo: TThemedTextBox
          Left = 502
          Top = 234
          Width = 300
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'Blank = no upper limit'
          ShowClearButton = True
          TabOrder = 7
        end
        object AccessedFilterLabel: TThemedLabel
          Left = 25
          Top = 281
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'Last accessed'
          Layout = tlCenter
        end
        object FAccessedFrom: TThemedTextBox
          Left = 190
          Top = 278
          Width = 300
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'YYYY-MM-DD or date and time'
          ShowClearButton = True
          TabOrder = 8
        end
        object FAccessedTo: TThemedTextBox
          Left = 502
          Top = 278
          Width = 300
          Height = 26
          StyleMode = stCompact
          PlaceholderText = 'Blank = no upper limit'
          ShowClearButton = True
          TabOrder = 9
        end
        object TimeFormatInfo: TThemedLabel
          Left = 190
          Top = 319
          Width = 760
          Height = 22
          AutoSize = False
          Caption = 'Local time unless Z / UTC offset is given. Example: 2026-11-07T14:30:00+01:00'
          Layout = tlCenter
        end
        object TimeRelativeInfo: TThemedLabel
          Left = 190
          Top = 342
          Width = 760
          Height = 22
          AutoSize = False
          Caption = 'Also accepts today, yesterday, now, now-30m, now-24h and now-7d.'
          Layout = tlCenter
        end
        object TimePresetLabel: TThemedLabel
          Left = 25
          Top = 388
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'Time helpers'
          Layout = tlCenter
        end
        object FTimeTarget: TThemedComboBox
          Left = 190
          Top = 385
          Width = 145
          Height = 26
          ItemIndex = 0
          Text = 'Modified'
          Items.Strings = (
            'Modified'
            'Created'
            'Last accessed')
          TabOrder = 10
        end
        object FTimePreset: TThemedComboBox
          Left = 347
          Top = 385
          Width = 215
          Height = 26
          ItemIndex = 0
          Text = 'Today'
          Items.Strings = (
            'Today'
            'Yesterday'
            'Last 30 minutes'
            'Last hour'
            'Last 24 hours'
            'Last 7 days'
            'Last 30 days')
          TabOrder = 11
        end
        object ApplyTimePresetButton: TThemedButton
          Left = 574
          Top = 384
          Width = 160
          Height = 28
          StyleMode = stCompact
          Caption = 'Apply template'
          TabOrder = 12
          OnClick = ApplyTimePresetClick
        end
        object ExcludeFilterLabel: TThemedLabel
          Left = 25
          Top = 483
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'Exclude files'
          Layout = tlCenter
        end
        object FExcludeEdit: TThemedTextBox
          Left = 190
          Top = 480
          Width = 612
          Height = 26
          StyleMode = stCompact
          PlaceholderText = '*.bak;*.tmp;build/**'
          ShowClearButton = True
          TabOrder = 16
        end
        object ExcludeFilterInfo: TThemedLabel
          Left = 190
          Top = 515
          Width = 760
          Height = 22
          AutoSize = False
          Caption = 'Separate masks with semicolons. Use ** to match across subfolders.'
          Layout = tlCenter
        end
        object ClearFiltersButton: TThemedButton
          Left = 190
          Top = 552
          Width = 165
          Height = 28
          StyleMode = stCompact
          Caption = 'Clear all filters'
          TabOrder = 17
          OnClick = ClearFiltersClick
        end
        object CalendarFilterLabel: TThemedLabel
          Left = 25
          Top = 431
          Width = 150
          Height = 22
          AutoSize = False
          Caption = 'Calendar / time'
          Layout = tlCenter
        end
        object FFilterCalendar: TThemedDatePicker
          Left = 190
          Top = 428
          Width = 250
          Height = 28
          StyleMode = stCompact
          TabOrder = 13
        end
        object FCalendarMode: TThemedComboBox
          Left = 452
          Top = 428
          Width = 180
          Height = 26
          ItemIndex = 0
          Text = 'From date'
          Items.Strings = (
            'From date'
            'To date'
            'From date and time'
            'To date and time')
          TabOrder = 14
          OnChange = CalendarModeChanged
        end
        object ApplyCalendarButton: TThemedButton
          Left = 644
          Top = 428
          Width = 160
          Height = 28
          StyleMode = stCompact
          Caption = 'Use selected value'
          TabOrder = 15
          OnClick = ApplyCalendarClick
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
