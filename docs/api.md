# NativeGrep - API and lifecycle

Public units: `NativeGrep.Types` for data types, `NativeGrep.Api` for `TNativeGrep.Search`, `SearchStream`, and `SearchBytes`.

```pascal
uses
  System.SysUtils, NativeGrep.Types, NativeGrep.Api;

type
  TDemoSink = class(TInterfacedObject, IGrepResultSink)
  public
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
  end;

procedure TDemoSink.MatchFound(const Match: TGrepMatch);
begin
  WriteLn(Match.SourcePath, ':', Match.ByteOffset);
end;

procedure TDemoSink.ScanError(const SourcePath, ErrorText: string);
begin
  WriteLn(SourcePath, ': ', ErrorText);
end;

var
  Request: TGrepRequest;
  Stats: TGrepStatistics;
  Sink: IGrepResultSink;
begin
  Request := Default(TGrepRequest);
  Request.Query.Mode := gmLiteralText;
  Request.Query.Text := 'SELECT';
  Request.Options.Roots := ['C:\Projects'];
  Request.Options.Recursive := True;
  Request.Options.MaxWorkers := 4;
  Request.Options.BufferSize := 1024 * 1024;
  Sink := TDemoSink.Create;
  Stats := TNativeGrep.Search(Request, Sink);
end;
```

Before the call, `Sink` must hold a concrete `IGrepResultSink` implementation. The library runs synchronously on the calling thread. An optional `IGrepCancellation` with `IsCancellationRequested` controls cancellation; `TGrepCancellationToken.Cancel` is thread-safe. A GUI should run `Search` on its own background task. The sink is invoked **on the thread that called `Search`**, sequentially. It must not touch the GUI directly from another thread, and should bound its own UI queue under high match rates.

## Configuration

| Property | Default | Meaning |
|---|---|---|
| `MaxWorkers` | `0` | automatic CPU count up to 8; explicit 1-64 |
| `BufferSize` | `0` | effectively 1 MiB; explicit 4 KiB to 16 MiB |
| `WorkQueueCapacity` | `0` | effectively 4 x worker count |
| `ResultQueueCapacity` | `0` | effectively 1024 events |
| `MaxMatchesPerFile` | `0` | unbounded per file |
| `MaxResultsTotal` | `0` | unbounded; without sorting, stops the scan early once reached, with sorting applies the limit only to final output |
| `MaxFileSize` | `0` | no size filter |
| `FileSizeFilter` | disabled bounds | byte range with optional inclusive/exclusive minimum and maximum |
| `CreatedTimeFilter`/`ModifiedTimeFilter`/`AccessedTimeFilter` | disabled bounds | independent UTC Windows FILETIME ranges |
| `Recursive` | `False` | direct children only, or all subdirectories |
| `IncludeHidden` | `False` | hidden/system entries are skipped by default |
| `Includes`/`Excludes` | empty | a pattern without a slash matches filenames; with a slash it matches relative paths, including `**` |

Note: recursive directory search holds up to 257 directory handles along the current recursion chain; beyond a depth of 256 a file-error event is emitted. Work/result queues and each worker's read buffer are bounded. The number of matches can still be unbounded **if the sink itself accumulates them fully**; the library does not retain them as a whole.

Size and time conditions are combined with include/exclude masks during file discovery. `MaxFileSize` intersects with the new size range. `NativeGrep.Filters` provides size and time parsing, validation and UTC conversion. Active size/time filters are rejected by `SearchStream` and `SearchBytes`. See [file filters](file-filters.md) for boundary rules and examples.

## Errors, cancellation, and synchronization

- A file open/read error is reported via `ScanError(Path, Message)`; other files keep scanning.
- Errors in producer/worker infrastructure abort the scan and raise an exception after the join.
- An exception from `Sink.MatchFound` or `Sink.ScanError` stops the pipeline; workers are joined before the exception propagates.
- `MaxResultsTotal` bounds delivered matches. Without sorting the scan stops early; with sorting, all matches are sorted first and then the first N are delivered.
- `FilesEnumerated`: files placed on the work queue. `FilesScanned`: file scans started, even if opening fails. `BytesScanned`: bytes actually read through file streams. `Matches`/`Errors`: events delivered to the sink.
- On cancellation, statistics only account for events delivered up to that point; any pending events are discarded.

## Thread safety

- `TNativeGrep.Search` is independent per call. Requests are copied on entry, including the dynamic byte and filter arrays.
- NativePattern searchers are **created per worker** and used exclusively by that worker.
- The result sink must not block waiting on the same search run; avoid deadlocks with recursion or a GUI dispatcher.
- An `IGrepCancellation` must itself be thread-safe. `TGrepCancellationToken` satisfies this.

## Opt-in profiling

With `Request.Options.Profile := True`, the engine collects detailed runtime phase timings via the high-resolution Windows performance counter. `TGrepStatistics.ProfileEnabled` marks the profiling fields as valid. `DiscoveryWallUs`, `CompileWorkerUs`, `FileOpenWorkerUs`, `FileReadWorkerUs`, `MatchWorkerUs`, `TextPositionWorkerUs`, `ResultEnqueueWorkerUs`, `FileScanWorkerUs`, `WorkQueueWaitWorkerUs`, and `SinkDispatchUs` are reported in microseconds.

Fields suffixed `Worker` are **sums across workers**, not wall time. `DiscoveryWallUs` includes producer backpressure; `SinkDispatchUs` measures only callback work. Without `Profile`, all these counters stay zero. Details in `docs/benchmarks.md`.

Extended search modes, encoding rules, and the stream/memory API are in `docs/search-modes.md`.

## Scan and binary policy

- `TGrepOptions.TextPositions = gtpAuto` is the default: text matches get line and column whenever the source is treated as text. `gtpNone` disables that computation (`Line=0`, `Column=0`) while leaving byte offset, length, pattern index, and distance unchanged. The CLI uses this automatically with `--quiet`, `--count`, and `--files-with-matches`.
- `TGrepOptions.BinaryPolicy = gbAuto` is the default for text patterns. The scanner checks up to 8192 bytes of the **first** stream read for null bytes and invalid UTF-8 sequences. If binary content is detected, matches are still reported, but without line/column position (`Line=0`, `Column=0`). This is a heuristic; binary content appearing later, or not detectable from the first block, can slip through. For short non-seekable reads, detection depends on the first block returned.
- `gbText` forces text-position computation despite detected binary content. `gbRaw` forces offset-only output. **Neither mode changes the match count.** The automatic heuristic is disabled for UTF-16LE/BE, where null bytes are normal; `gbRaw` remains explicitly selectable there.
- Byte, multi-byte, fuzzy-byte, and masked-hex queries always get raw byte offsets and no text position; these modes are not subject to UTF-8 binary detection.
- CLI: `--binary=auto`, `--binary=text`, `--binary=raw`. For text matches without line positions, the console prints `path:@0xOFFSET:LENGTH`; JSONL uses `line:0,column:0`.
- `TGrepStatistics.BinaryRawSources` counts text sources treated as raw bytes, whether automatically or explicitly, during the search; profiling output shows `binary_raw_sources`. With text positions disabled, the heuristic is skipped entirely to save time, and this counter stays zero.

## Automatic BOM detection and path globs

`TGrepQuery.Encoding := geAuto` builds UTF-8, UTF-16LE, and UTF-16BE variants of the same exact text matcher per worker. The concrete variant is chosen per file (or per stream) after reading the first up to three bytes. Files without a BOM are treated as UTF-8. Byte and fuzzy queries remain explicitly encoded; a default `TGrepQuery` record still defaults to `geUtf8` for API compatibility.

`TGrepOptions.Includes`/`Excludes`: a pattern without a slash is compared against the filename only; a pattern containing `\` or `/` is compared against the relative path within the search root. `**` can cross directory boundaries. Links/junctions are not followed during enumeration. The Windows reader also uses extended-path notation for long paths when opening files.

See `docs/unicode.md` for the opt-in Unicode text path. The default ASCII-insensitive and UTF-8 byte-fuzzy semantics remain unchanged. Context lines and optional global result-output sorting are available (see below).

## Line context and original lines

`NativeGrep.Context.TGrepContextReader.ReadFile` reads, for an already-reported `TGrepMatch` with `Line>0`, the original line and optionally up to 32 lines before and after. A match must belong to a seekable file. The file is reopened for context access; for files removed or changed since the scan, the context is not guaranteed to match exactly. The reader decodes UTF-8/UTF-16LE/UTF-16BE, detects UTF-16 BOMs under `geAuto`, strips BOMs from displayed text, and reads only bounded excerpts before and after the byte offset. Long lines are truncated and marked with `...`. The default `MaxLineChars` is 2048. The read method has no parallel execution of its own.

CLI: `--line-text` prints the original line; `-A N` / `-B N` / `-C N` print up to N following, preceding, or both-sides lines per **match**. This is deliberately **match-oriented**: with multiple matches on the same or adjacent lines, context lines can repeat; there is no grep-style global grouping. JSONL gets a `context` array on the match object with `line`, `text`, `match`, `truncated`. Without these flags, existing CLI output is unchanged. No context output for `--stdin`, binary patterns, `--count`, or `--files-with-matches`. For sources detected as binary without a text position, offset-only output remains. Context is opt-in, so the fast `--quiet` path incurs no extra file I/O.

## Unicode text path (opt-in)

The query fields `UnicodeCaseFold`, `UnicodeNormalizeNfd`, `FuzzyCodePoints`, and their hard limits are specified in `docs/unicode.md`. Default settings and existing Search/Stream/Bytes signatures are unchanged. Global result sorting is available via `TGrepOptions.SortResults`.

## Deterministic match ordering

`--sort` enables optional ordering of matches by full source path (UTF-16 ordinal comparison, case-sensitive), then 0-based byte offset, pattern index, distance, and match size. The library enables this with `TGrepOptions.SortResults := True`. Without the option, fast output follows worker completion order.

Sorting collects up to 2,048 matches per block in memory and spills larger result sets as temporary runs in the Windows temp directory. These runs are merged incrementally; required disk capacity can be significant for very large result sets. Missing disk space or a non-writable temp directory produces an error. Temp files are cleaned up on both the normal-completion and the error path.

Sorted matches only appear after the scan completes. File errors are still delivered immediately, not in path order. `--max-results N` bounds the **sorted output** to the first N matches, though workers still scan every file. External cancellation is checked regularly during the disk-backed merge phase too, and stops both merge and output. `--sort` is not silently disabled under `--quiet`, `--count`, or `--files-with-matches`; such combinations can still produce temp files even though the CLI prints no match lines. `SearchStream` and `SearchBytes` support the option as well.

Example: `npgrep "TODO" "E:\Projects" -r --include "*.pas" --threads 4 --sort`

## API contract and ownership

- `TNativeGrep.Search(Request, Sink, Cancellation)` is synchronous. File workers are started internally; all sink callbacks happen sequentially on the calling thread. Do not call GUI methods directly from callbacks unless `Search` was started on the GUI thread.
- `SearchStream` starts at the stream's **current** position, requires no seek support, and changes that position. The stream remains fully owned by the caller; NativeGrep neither closes nor destroys it. The given `SourceName` is a display name, not a file path for the scanner.
- `SearchBytes` reads an internally created memory-stream wrapper over the caller-supplied bytes. Ownership of the bytes stays with the caller.
- `IGrepResultSink` is held as an interface for the duration of the synchronous call and must remain valid until it returns. Exceptions from sink callbacks propagate after workers are stopped and joined.
- `TGrepCancellationToken.Cancel` can be called from any thread. On cancellation, already-queued matches may be discarded; this is not an error. `SearchStream` cannot be preempted from the outside while blocked inside a single `Stream.Read` call.
- With `SortResults=True`, match callbacks only happen after the scan; file-error callbacks remain immediate. Sorting can fail under limited temp disk space; this infrastructure error should not be interpreted as an ordinary file error.
- The on-disk sort format is an internal, version-bound format only, not a publicly stable data or interchange structure.
- `IGrepResultSink.ScanError` reports individual open/read/enumeration errors. When the CLI reports such errors it uses exit code 2, but may already have printed valid matches beforehand.

Build and CLI test commands are in the [testing guide](testing.md).

## Experimental regex API

`TGrepQuery.Mode := gmRegexText` activates PCRE2-8. Text is read from `TGrepQuery.Text`, match groups from `TGrepMatch.Captures`. `TGrepOptions.RegexMaxBytes`, `RegexMatchLimit`, and `RegexDepthLimit` bound execution. Regex requires Win64 `pcre2-8.dll` beside the host EXE, including each Debug or Release output directory used. Setup and limits are in the [regex guide](regex.md).
