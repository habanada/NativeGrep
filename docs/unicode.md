# NativeGrep - Unicode contract (opt-in)

Unicode 15.1 tables, built for Delphi 12/Win64.

## Calls

```powershell
npgrep "STRASSE" "E:\Projects" -r --include "*.txt" --ignore-case=unicode --encoding auto
npgrep "cafe" "E:\Projects" -r --include "*.txt" --normalize=nfd
npgrep "cafe" "E:\Projects" -r --include "*.txt" --fuzzy 1 --fuzzy-unit codepoints
npgrep "strasse" "E:\Projects" -r --ignore-case=unicode --fuzzy 1 --fuzzy-unit codepoints
```

| `TGrepQuery` field | Default | Behavior |
|---|---|---|
| `UnicodeCaseFold` | `False` | Full, locale-independent Unicode 15.1 case folding, combined with NFD |
| `UnicodeNormalizeNfd` | `False` | Canonical decomposition with canonical ordering of combining characters |
| `FuzzyCodePoints` | `False` | Levenshtein distance over normalized Unicode scalars instead of UTF-8 bytes |

The existing byte search and `CaseInsensitiveAscii` still use the regular NativePattern path. The Unicode mode uses a **separate text-matching implementation**, because folding/normalization can change character length while source bytes must still map back correctly. For exact Unicode search, this path uses a KMP state per pattern; for Unicode fuzzy search, bounded Levenshtein windows. NativePattern is **not** the actual search routine in these two opt-in paths. Regex uses PCRE2; the remaining search modes use NativePattern.

## Semantics and memory limits

- Encodings: UTF-8, UTF-16LE, UTF-16BE; `geAuto` detects BOMs, otherwise UTF-8. The Unicode paths decode **strictly**. Invalid UTF-8 sequences, bad surrogates, or truncated characters raise an encoding error, reported per source via `ScanError` during a file scan.
- Full Unicode case folding is independent of regional rules; in particular, German eszett folds with `ss`, and final sigma folds with regular sigma. This is not a culture-specific Turkish-I comparison. NFD is canonical, not NFKD (compatibility characters stay distinguishable).
- The canonical match value can consist of multiple Unicode scalars. `TGrepMatch.ByteOffset` (0-based) and `ByteLength` denote a **contiguous original byte range**. When combining characters are reordered, the range can also include intermediate bytes whose normal-form portion does not fully belong to the match. Match length is therefore **not** the length of the normalized pattern.
- `Line` is 1-based. `Column` counts UTF-16 code units, like the existing scanner. With `gtpNone` or `gbRaw`, both are 0; the original byte range is preserved.
- Exact Unicode patterns: up to 8192 normalized codepoints per pattern. Unicode fuzzy: up to 256 normalized codepoints and distance 0-8, smaller than the pattern length. Overlapping matches are allowed. A source byte offset is emitted at most once per pattern.
- Fuzzy search compares every possible normalized start position and picks the smallest Levenshtein distance, breaking ties by the shortest normalized match length. Runtime grows with pattern and distance window size and is not comparable to the SIMD byte path.
- Per worker: a reused raw-byte read buffer of 64 KiB, an 8192-codepoint maximum exact KMP history, or a 264-codepoint fuzzy window; canonical combining sequences are capped at 4096 scalars. Exceeding this limit ends the source with an error instead of silently producing wrong results.
- The original stream remains owned by the caller. Non-seekable streams are supported. Byte offsets for `SearchStream` are relative to the **current stream read start**, not to the absolute position of a stream that was already positioned beforehand.
- Because of normalization, matches within a combining-character segment can have a different source byte-offset order than the normalized search order. A globally deterministic sort order is explicitly **not** part of this path (see `--sort` in `docs/api.md` for byte-level ordering, which applies independently).

## API, errors, and concurrency

`TNativeGrep.Search`, `SearchStream`, and `SearchBytes` keep their signatures. The three boolean fields are opt-in on `TGrepQuery`. Old record defaults are unchanged. An already-compiled consumer application must be recompiled after changes to the record; there is **no binary-stable DLL ABI**. The library is still consumed as units.

Each worker builds its own Unicode matcher; no mutable-state matcher is shared in parallel. The global result sink is still called exclusively by the calling dispatcher thread during a file scan. For `SearchStream`/`SearchBytes`, the sink call happens synchronously on the calling thread. Cancellation and `MaxMatchesPerFile` still apply per file, `MaxResultsTotal` globally.

## Testing and profiling

- Delphi 12 DCC64 Debug and Release; the Unicode units and CLI flags build cleanly.
- `NativeGrep.Tests.exe` passes, and the separate NativePattern suite still passes.
- Identical byte offsets and matches per file with 1 and 4 workers, including UTF-8/UTF-16 and mixed-BOM files.
- Randomized differential tests for mapping/case-folding/NFD against an independent Unicode 15.1 reference, plus synthetic multi-million-character inputs, cancellation, error paths, and peak memory.
- Profiling of the Unicode pipeline measured separately from byte-oriented throughput tests. The existing microsecond profiling sub-fields do not fully cover the Unicode path: `FileScanWorkerUs` stays meaningful, `FileReadWorkerUs` captures the stream-read calls, but `MatchWorkerUs` does not separately measure the integrated Unicode decode/match path and can read 0.

See the [search modes](search-modes.md), [regex](regex.md), [API](api.md), and [GUI](../apps/NativeGrep.GUI/README.md) guides for the other search paths and interfaces.
