# NativeGrep - Search modes and source types

The search library has no VCL dependency. NativePattern-based search modes need no third-party DLL; regex requires `pcre2-8.dll` beside the host EXE. For `TNativeGrep.Search`, every worker gets its own matcher instance and a reusable read buffer. File and result queues are bounded. Output happens synchronously through the result sink, on the thread that called `Search`.

## Queries

| `TGrepQuery.Mode` | Input | Meaning |
|---|---|---|
| `gmLiteralText` | `Text` | Fixed string in the given file encoding |
| `gmLiteralBytes` | `Bytes` | Exact raw bytes |
| `gmMaskedHex` | `HexSignature` | Bitmasked signature, up to 64 bytes |
| `gmMultiText` | `TextPatterns` | Multiple literal strings, NativePattern Aho-Corasick/Commentz-Walter auto-dispatch |
| `gmMultiBytes` | `BytePatterns` | Multiple byte sequences, original index preserved |
| `gmFuzzyText` | `Text`, `MaxDistance` | Levenshtein/Myers over *UTF-8 bytes* |
| `gmFuzzyBytes` | `Bytes`, `MaxDistance` | Levenshtein/Myers over bytes |
| `gmRegexText` | `Text` | PCRE2 expression; requires `pcre2-8.dll` |

`MaxDistance` must be smaller than the encoded byte pattern length. Multiple matches from different patterns at the same byte position are all delivered; `PatternIndex` follows the order of the original pattern list. Overlapping matches are allowed. In multi-pattern modes, search uses the compiled NativePattern multi-searcher, and found start positions are verified against every pattern variant. The library additionally caps multi-pattern input at 1,024 entries and 32,768 encoded bytes total, since NativePattern builds internal trie structures per worker. Memory use stays bounded by file buffers, matcher instances, and bounded queues.

### Encoding and position

`TGrepQuery.Encoding`: `geUtf8` (API default), `geUtf16LE`, `geUtf16BE`, or `geAuto`. The CLI defaults to `geAuto`. For exact text and multi-text searches, `geAuto` selects UTF-16LE or UTF-16BE from a BOM and otherwise uses UTF-8. An explicit encoding fixes the pattern encoding. The BOM is excluded from line/column counting. Byte-based fuzzy text search requires an explicit encoding; the opt-in Unicode fuzzy path has its own [encoding rules](unicode.md).

The match position `ByteOffset` is 0-based and refers to original bytes. Line and column are 1-based; column counts Delphi UTF-16 code units. CRLF counts as one line break. `Line` and `Column` are only computed for text searches; otherwise both are 0. Ordinary literal matching operates on encoded bytes. Binary detection can suppress line/column output; strict decoding in the Unicode and regex paths follows their separate rules.

`CaseInsensitiveAscii := True` is explicitly **ASCII case folding only**. Non-ASCII Unicode is not normalized, and case there stays unchanged. UTF-16 byte positions are validated at even code-unit boundaries. ASCII case folding cannot be combined with masked-hex or fuzzy search.

## Other sources

- `TNativeGrep.Search(Request, Sink, Cancellation)`: file search with parallel workers.
- `TNativeGrep.SearchStream(Request, SourceName, Stream, Sink, Cancellation)`: processes bytes **from the stream's current position** sequentially. No `Position`, `Size`, or `Seek` operation is required. The caller keeps ownership of the stream; reported `ByteOffset` values are relative to the stream position *at the start of this search call*.
- `TNativeGrep.SearchBytes(Request, SourceName, Data, Sink, Cancellation)`: searches bytes already in memory.

Stream/bytes search starts no workers; sink calls are serial and synchronous. `MaxResultsTotal`, `MaxMatchesPerFile`, and cancellation still apply. `Roots` is ignored for these methods; file globs only apply to `Search`. A stream read-error exception propagates to the caller, as do sink exceptions; neither is automatically reclassified as a file-error event.

## CLI

```powershell
npgrep -e "TODO" -e "FIXME" E:\Projects -r --threads 4 --include "*.pas" --stats
npgrep "ABXDE" E:\Projects -r --fuzzy 1 --quiet --profile
npgrep "Z" . --encoding utf16le -r
npgrep "customer" . -r --ignore-case=ascii --count
npgrep "TODO" E:\Projects -r --jsonl
Get-Content -Raw .\app.log | npgrep "ERROR" --stdin
```

`--jsonl` emits match and error events. Matches with `--count`/`--files-with-matches` are aggregated and sorted only after the search completes; these output modes need memory proportional to the number of distinct result files, not to the number of matches. Under `--quiet`, even this output is suppressed. Without a result limit, stopping the scan via a callback is the sink's/cancellation token's responsibility.

## Regex and text output

Regex uses a separate PCRE2-backed matcher. It buffers each source up to the configured size limit rather than using the byte-pattern chunk search. See the [regex guide](regex.md) for encoding, capture groups, and limits. For non-regex text matches, the CLI prints the matched pattern text unless `--line-text`, `-A`, `-B`, or `-C` requests original source lines.
