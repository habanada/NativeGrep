# NativeGrep GUI - NimbusForms workbench

NativeGrepGUI is a Delphi 12 Win64 VCL frontend using the existing NativeGrep API directly. It uses the same search engine as the CLI.

NimbusForms is still in preview. A public preview release is planned for a later date; no release date has been announced.

## Layout

The fixed workbench controls are stored in `NativeGrep.GUI.Main.dfm`, including all main tabs, search inputs, file filters, split panes, viewers, output actions, and options. They can be edited in the Delphi form designer. Runtime initialization connects result providers, loads theme presets and saved settings, and creates context menus. Application panels use `TThemedPanel` so their backgrounds follow the same NimbusForms palette as the buttons.

- Compact Visual-Studio-inspired workbench with NimbusForms `Run Search`, `File filters` and `Options` tabs.
- File size comparisons (smaller, larger, inclusive limits, exact size and between), independent creation/modification/access time ranges, a NimbusForms date/time calendar, relative time templates and exclude masks. Filters can be disabled together, cleared, and saved with search settings. See [file filters](../../docs/file-filters.md) for units, boundary rules and examples.
- Compact NimbusForms search textboxes, primary Search button, file masks, regex/case toggles, and recursive checkbox.
- Nested themed split containers: results and a read-only NimbusForms CodeEditor above, diagnostic output below.
- VirtualList in compact mode, virtual result rows, expandable offset/capture metadata, and selection navigation into the CodeEditor, with syntax highlighting, line numbers, search-range highlights, and bookmarked result lines.
- Results can be grouped by file (default), grouped by folder, or shown in arrival order without grouping. Headers count visible matches. The grouping preference is saved.
- The result filter searches paths, cached match-line excerpts, line/column positions and decimal or hexadecimal byte offsets using a case-insensitive literal substring. Ctrl+F focuses the filter; Escape clears it when focused. Filtering also works while results arrive, and shows visible/total counts. A new search clears the result filter.
- The `MATCH TEXT` column shows a bounded excerpt of the line containing the start of the match, captured on the search thread. Excerpts are limited to 512 characters around the hit; filtering does not search omitted text or reread files. Binary matches and unreadable previews retain searchable paths and positions.
- Selection, previews and file actions follow the source match when grouping or filtering changes the row order. `Replace visible` replaces only visible matches; `Replace selected` uses selected visible rows. Both retain the existing source-change checks and confirmation dialog.
- Diagnostics use `TThemedLogViewer` from `NimbusForms.Controls.LogViewer`, built on `NimbusForms.Rendering.LogViewer`. Severity-aware messages, a 10,000-line cap, and a Clear action.
- Chrome and pane headers recolor when the NimbusForms theme changes. Theme presets and search settings persist in `%APPDATA%\NativeGrep\GUI.ini`.
- F5 or Ctrl+Enter starts a search; Esc requests cancellation. Enter in the search box starts a search.
- Search controls resize and reposition through DFM anchors when the window width changes; pane captions do not overlap source names. Options use full-width section headings with aligned label/control columns and muted explanations. The window minimum size is 920 x 660 to preserve the workbench split panes and file filter controls.

## Build

Install matching NimbusForms runtime and design-time packages for form-designer editing. Rebuild these packages after updating NimbusForms.

The project is `apps/NativeGrep.GUI/NativeGrep.GUI.dproj`. Build Win64 with Delphi 12. The executable is `bin/Win64/<Config>/NativeGrep.GUI.exe`. The supplied search paths expect NimbusForms beside NativeGrep as `../NimbusForms`, with its `NimbusForms.Controls/src`, `NimbusForms.Theming/src`, and `NimbusForms.HexEditor/src` units available.

## Runtime DLLs

Regex search and regex-based replacement require Win64 `pcre2-8.dll` (PCRE2 10.x with Unicode support) beside `NativeGrep.GUI.exe`. The same DLL is needed by the CLI beside `npgrep.exe`. Literal search works without it: turn off Regex in the search header.

Debug and Release are separate directories. A DLL in `bin/Win64/Debug` is not available to the EXE in `bin/Win64/Release`; copy it beside each EXE you run. The Delphi build does not deploy it automatically. See the [regex guide](../../docs/regex.md).

`NimbusCodeEditorSkia.dll` is optional and belongs beside the GUI EXE. Without it, the code editor uses its built-in renderer.

## Engine limits as seen from the GUI

Regex sources are limited to 64 MiB per file; UTF-16 regex is not supported. Searches run off the UI thread, emit batches through a synchronized session, and can be cancelled. The application retains at most 50,000 matches.

## CodeEditor preview

- Uses `TThemedCodeEditor` from `NimbusForms.Controls.CodeEditor`. Displays the whole source file read-only, with syntax coloring and a line-number gutter, loading complete source files with a separate 16 MiB GUI preview cap; files above that limit remain searchable in NativeGrep itself.
- All verified hits in the currently selected file are highlighted as ranges and overview-ruler markers; hit lines are additionally bookmarked. Up to 2,000 verified spans per open file are highlighted, and up to 300 distinct result lines get bookmarks. The currently selected match is highlighted even if it lies beyond that cap.
- Selecting a result navigates to the precise range; an unresolvable byte-to-text span navigates to the reported line if known. Original byte offsets are decoded and compared against the editor's text before highlighting, so uncertain encoding or a changed file does not produce a misleading range highlight.
- On startup, if Win64 `NimbusCodeEditorSkia.dll` exists next to `NativeGrep.GUI.exe`, the code editor uses it through `TCodeEditorDLLBackend`. If absent or initialization fails, the built-in renderer is used instead, with an explanation logged to the output pane. The Skia renderer DLL itself is not part of this project's source tree.

## Hex viewer and result context menu

- The preview pane uses NimbusForms `TThemedTabControl` with `Code Editor` and `Hex Viewer` tabs.
- The Hex Viewer uses `TThemedHexEditor` and a read-only `TFileHexDataSource`, reading arbitrary file sizes on demand. Results navigate directly to exact file-byte offsets and highlight selected spans, up to 64 KiB per span; up to 300 hit offsets are bookmarked.
- The result list uses `TThemedPopupMenu` from NimbusForms, with external opening, internal Code/Hex viewing, Explorer containing-folder selection, copy filename/folder/full path, and Windows file properties.
- HexEditor units are resolved through the configured NimbusForms/Delphi library path.

## Editor and log context menus

- Code Editor: copy selection, copy all text, select all, using NimbusForms' own clipboard implementation for selected text.
- LogViewer: right-click the inner log view for copy selected line(s), copy all lines, select all, save log as UTF-8, and clear. Copy all uses the full retained log model, including hidden/filtered lines, without overwriting the current selection. An additional Save log button is available in the Output header.
