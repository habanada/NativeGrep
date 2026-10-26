# NativeGrep - parallel native file search built on NativePattern

<p align="center">
  <img src="images/nativegrep.png" alt="NativeGrep mascot: a Viking helmet and axe" width="480">
</p>

NativeGrep is a standalone search library with no VCL dependency. The core search algorithms come from NativePattern; an opt-in Unicode path adds its own scalar exact/fuzzy matchers for byte-accurate normalization mapping. `npgrep.exe` is a CLI on top of the same public API. The [NimbusForms GUI](apps/NativeGrep.GUI/README.md) provides search, replace, result navigation, and code/hex previews.

NimbusForms is still in preview. A public preview release is planned for a later date; no release date has been announced.

Search runs **per file**: a producer enumerates files, 1 to 64 workers search different files in parallel, and a single dispatcher delivers matches to the `IGrepResultSink`.

## Features

- Literal text and byte search, multi-pattern search, masked hex signatures, fuzzy search (byte and text)
- Opt-in PCRE2-based regex search with capture groups
- UTF-8 / UTF-16LE / UTF-16BE encoding, with automatic BOM detection
- Opt-in full Unicode case folding, NFD normalization, and codepoint-based fuzzy search
- Line/column text positions, with configurable binary-vs-text handling
- Line context output (`--line-text`, `-A`, `-B`, `-C`)
- Optional deterministic, disk-backed result sorting across workers
- In-place replace (`TGrepReplacer`) with automatic backups and rollback-safe writes
- File-change monitoring so stale search results can be flagged in a GUI
- `Search`, `SearchStream`, and `SearchBytes` entry points for file, stream, and in-memory sources

## Project layout

```text
NativeGrep/
  src/                          library units
  apps/npgrep/                  Win64 console CLI
  apps/NativeGrep.GUI/          VCL GUI
  tests/                        integration-style console test suite
  benchmarks/                   benchmark script
  docs/                         API, semantics, and limits
  external/NativePattern3/src/  vendored NativePattern dependency (unmodified)
```

## Build

1. Open `apps/npgrep/npgrep.dproj` in RAD Studio 12 and select the **Windows 64-bit** platform.
2. Build the project. On success, the executable is at `bin/Win64/<Config>/npgrep.exe`.
3. Open `tests/NativeGrep.Tests.dproj`, build it for Win64, and run it.

Both project files use DCC unit search paths for `src` and `external/NativePattern3/src`. NativePattern itself is vendored unmodified.

## Runtime dependencies

| Feature | Requirement |
| --- | --- |
| Literal, byte, wildcard, multi-pattern, and fuzzy search | No PCRE2 DLL required |
| Regex search and regex-based replacement | Win64 `pcre2-8.dll` (PCRE2 10.x with Unicode support) beside the application EXE |
| GUI | NimbusForms units at build time; PCRE2 is required when Regex is enabled |
| Optional GUI Skia preview renderer | See the [GUI setup](apps/NativeGrep.GUI/README.md) |

Place `pcre2-8.dll` beside `npgrep.exe`, `NativeGrep.GUI.exe`, or the host EXE when using the library. Regex tests need it beside `NativeGrep.Tests.exe` as well. The loader uses the EXE directory, not the working directory or `PATH`.

Debug and Release have separate output directories. Supply the DLL in each directory you run, such as `bin/Win64/Debug` and `bin/Win64/Release`. Building the Delphi project does not copy this dependency. The repository does not include third-party DLL binaries. See the [regex guide](docs/regex.md) for setup and limits.

## Usage

```powershell
npgrep "GetCustomer" "C:\Projects" -r --threads 4 --include "*.pas"
npgrep "TODO" . -r --threads 1 --stats
npgrep --hex "48 8B ?? ?? 48 85 C0" "C:\Bins" -r --include "*.exe" --threads 8
npgrep "needle" . -r --threads 0 --buffer-kib 1024 --max-count 100 --max-results 2000
npgrep --help
```

`--threads 0` (default) picks the CPU count, capped at 8. `--threads 1` effectively disables parallelism but still uses the same pipeline. `--buffer-kib` defaults to 1024 KiB, allocated separately per worker. Internal queues are bounded (4 x worker count file paths by default, 1024 result events). `MaxWorkers` is capped at 64.

## How it works

- **Producer:** enumerates directories depth-first without following reparse points/junctions; filters by filename/relative-path globs, max file size; permission errors become events.
- **Worker:** owns its file stream, read buffer, and compiled matcher. NativePattern-based searches read files in blocks using 64-bit offsets. Regex buffers each source up to `RegexMaxBytes` (64 MiB by default).
- **Chunk boundaries:** the last `PatternLength - 1` bytes are retained across chunks. Every possible match start is attributed to exactly one block. Overlapping matches are preserved.
- **Result queue:** a worker blocks on a full queue (backpressure) and checks for cancellation periodically. The dispatcher calls `MatchFound`/`ScanError` sequentially, never from multiple workers in parallel.
- **Cancellation:** via `IGrepCancellation` or an internal result limit; no `Synchronize` dependency. An in-flight `Read`/matcher call is not preempted, only stopped after it returns.
- **Ordering:** within one file, matches are ordered by byte offset. Across files, order depends on the scheduler by default. `--sort` makes result order independent of worker count; sorting large result sets uses temporary disk space.

## Search modes

| Mode | Semantics |
|---|---|
| `gmLiteralText` | UTF-8-encoded literal, case-sensitive; absolute raw byte offsets plus UTF-8-based line and UTF-16 code-unit column |
| `gmLiteralBytes` | Exact byte sequence, no text decoding |
| `gmMultiText` / `gmMultiBytes` | Multiple literal patterns via NativePattern's Aho-Corasick/Commentz-Walter auto-dispatch |
| `gmFuzzyText` / `gmFuzzyBytes` | Levenshtein/Myers edit-distance search |
| `gmMaskedHex` | `??`/nibble-masked signature, currently up to 64 bytes (NativePattern Bitap) |
| `gmRegexText` | PCRE2-8 regular expressions (opt-in, see `docs/regex.md`) |

`TGrepMatch.ByteOffset` is 0-based. `Line` and `Column` are 1-based in text mode and 0 in binary mode. Columns count UTF-16 code units (e.g. an emoji counts as 2), not graphemes. The fast default UTF-8 path searches raw bytes. Full Unicode case folding, NFD normalization, and codepoint-based fuzzy search are separate, explicitly opt-in modes (`docs/unicode.md`). A UTF-8 BOM is ignored for column counting.

The text CLI prints the **matched literal text**, not the whole line, unless `--line-text`/`-A`/`-B`/`-C` is used. Binary matches print as `path:@0xOFFSET:BYTE_LENGTH`. Permission errors on individual files are not fatal to the rest of the scan but still produce CLI exit code 2.

## Encoding and paths

`--encoding auto` detects UTF-16LE (`FF FE`) or UTF-16BE (`FE FF`) from a file's preamble; otherwise UTF-8 is assumed. The CLI default is `auto`; the API record default stays `geUtf8` for compatibility. Auto-detection applies to literal and multi-text search; fuzzy search still requires an explicit UTF-8 byte pattern.

`--include`/`--exclude` patterns without a slash match the filename only; patterns with a slash match the relative path, including `**` across directory boundaries. Long absolute Windows/UNC paths are converted to extended-path form internally when needed; reported match paths remain exactly as supplied by the caller.

## Context lines

`--line-text`, `-A N`, `-B N`, and `-C N` (each 0..32) print the original line and optionally bounded neighboring lines, via the standalone `NativeGrep.Context` unit. Context is match-oriented: matches on the same or adjacent lines can produce overlapping context, with no grep-style global line grouping. JSONL output includes a `context` array (`line`, `text`, `match`, `truncated`) on the match object. Not available for `--stdin`, binary patterns, `--count`, or `--files-with-matches`.

## Deterministic result ordering

`--sort` orders matches by full source path (UTF-16 ordinal, case-sensitive), then 0-based byte offset, pattern index, distance, and match length. It is available via `TGrepOptions.SortResults` in the API and via `SearchStream`/`SearchBytes` as well. Sorting collects up to 2,048 matches per block in memory and spills larger result sets to temporary runs in the Windows temp directory, merged incrementally; the required disk space scales with result count. Results only appear once the scan completes; file errors are still delivered immediately rather than in path order. `--max-results N` bounds the **sorted** output to the first N matches, though all files are still scanned.

## Regex (opt-in)

Regex search uses the PCRE2 engine through NativeGrep's own Delphi adapter in `src/NativeGrep.Regex.pas`. The engine is loaded from an external `pcre2-8.dll` beside the executable. Non-regex search modes do not require this DLL. See the [regex guide](docs/regex.md) for installation, capture groups, size limits, and invalid-UTF-8 handling.

## Benchmark

```powershell
.\benchmarks\bench.ps1 -Exe '.\bin\Win64\Release\npgrep.exe' -Root 'C:\Projects' -Pattern 'TODO' -Include '*.pas' -Repeats 5 -Warmups 1 -CsvPath '.\nativegrep-benchmark.csv'
```

Runs the search across 1/2/4/8 workers, verifies matches/bytes/file counts/errors, reports the median runtime per worker count, and writes per-run measurements to CSV. See `docs/benchmarks.md` for the full profiling field reference.

## Documentation

| Topic | Guide |
| --- | --- |
| Public API and ownership | [API](docs/api.md) |
| Search modes, encodings, and source types | [Search modes](docs/search-modes.md) |
| Regex setup and limits | [Regex](docs/regex.md) |
| Unicode matching | [Unicode](docs/unicode.md) |
| Replacement and backups | [Replace API](docs/replace.md) |
| File-change tracking | [File monitor](docs/file-monitor.md) |
| Performance measurements | [Benchmarks](docs/benchmarks.md) |
| Build and test commands | [Testing](docs/testing.md) |
| Replacement test coverage | [Replace tests](docs/replace-testing.md) |
| GUI setup and controls | [GUI](apps/NativeGrep.GUI/README.md) |
