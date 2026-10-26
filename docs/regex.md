# NativeGrep regex backend (experimental extension)

NativeGrep adds `gmRegexText` as a separate PCRE2-8 matcher. NativePattern remains responsible for all other search modes. For a regex with a provably required ASCII prefix (at least three characters, no top-level alternation, no quantifier that makes the prefix optional), the regex backend uses a NativePattern searcher for negative pre-filtering; PCRE2 always fully verifies matches. Patterns without a safe prefix go straight to PCRE2. The pre-filter is used only when the expression has a safe required prefix.

## Installation

Requires a Win64-matching `pcre2-8.dll` (PCRE2 10.x, Unicode support enabled). For security, the DLL is loaded only via a fully qualified path from the **calling EXE's directory**. For `npgrep.exe`, place the DLL next to `npgrep.exe`; when embedding NativeGrep as a library, place it next to the host application's EXE. The library deliberately ships no third-party DLL binary. Observe the license terms of the PCRE2 distribution used. Literal/multi/fuzzy/hex search need no PCRE2 DLL.

For the GUI, place the DLL beside `NativeGrep.GUI.exe`; Regex in the search header controls whether it is used. Regex-based replacement also needs PCRE2 to validate matches. With Regex disabled, literal GUI searches need no PCRE2 DLL.

Keep a copy beside each Debug or Release EXE you run. The loader does not use the current working directory or `PATH`, and building NativeGrep does not copy the DLL. Regex tests require a copy beside `NativeGrep.Tests.exe`.

## Example

```powershell
npgrep --regex "GetCustomer\s*\(([0-9]+)\)" E:\Projects -r --include "*.pas" --threads 4 --jsonl --sort
npgrep --regex "error.*timeout" . -r --ignore-case=unicode --regex-max-mib 128
npgrep --regex "TODO|FIXME" E:\Projects -r --include "*.pas" --sort --regex-invalid-utf
```

The public API sets `Query.Mode := gmRegexText` and `Query.Text` to the PCRE2 expression. `Query.UnicodeCaseFold := True` enables PCRE2 caseless matching (`UTF|UCP|CASELESS`). The Unicode 15.1 NFD transform of NativeGrep's own Unicode path is not part of PCRE2 search. `--ignore-case=ascii`, `--fuzzy`, and `--normalize=nfd` are not valid with regex.

Results include `TGrepMatch.ByteOffset`, `ByteLength`, `Line`, `Column`, and `Captures: TArray<TGrepCapture>`. Capture index is 1-based; `ByteOffset` is 0-based and absolute within the original stream. Unmatched groups have `Matched=False`. JSONL includes a `captures` array. Default console output for regex shows `path:line:column:@0xOFFSET:LENGTH` (not the regex expression as if it were matched text); `--line-text` prints the source line. `--sort` preserves groups through the disk-backed merge too. Groups are not automatically kept as an in-memory excerpt of the input.

## Limits and correctness boundaries

- PCRE2 processes the **entire data object as one contiguous buffer**, so arbitrary multi-line regex patterns and anchors are evaluated correctly within that source. Data is therefore buffered up to an explicit maximum per source. Default: **64 MiB**, adjustable up to 1024 MiB with `--regex-max-mib N`. Larger sources produce a visible file error rather than truncated or lost matches. `SearchStream` need not be seekable. This regex mode is **not** an arbitrarily large streaming regex scanner.
- By default, UTF-8 is strictly validated in PCRE2's UTF mode. A UTF-8 BOM is stripped for evaluation, but all reported match positions remain absolute byte offsets including the BOM. UTF-16LE/BE regex is currently rejected outright. With automatic encoding and no BOM, UTF-8 is assumed.
- With `--regex-invalid-utf` (API: `Query.RegexAllowInvalidUtf8 := True`), NativeGrep uses `PCRE2_MATCH_INVALID_UTF`. Valid UTF-8 regions are searched despite invalid bytes elsewhere. Invalid byte sequences form hard boundaries: no regex match may span them. Bytes are **not** decoded as ANSI or Windows-1252. For a file that is genuinely invalid, `Line` and `Column` are set to 0; original byte offsets, capture offsets, and match lengths are preserved. Fully valid UTF-8 still gets normal line positions. This mode requires a PCRE2 build with `PCRE2_MATCH_INVALID_UTF` support. Without explicitly opting in, validation stays strict.
- Zero-length matches follow PCRE2's `ANCHORED|NOTEMPTY_ATSTART` handling and continue at Unicode character boundaries. Matches do not overlap.
- Each worker owns its own PCRE2 code, match data, and match context  -  no shared PCRE2 matching object. Default limits `RegexMatchLimit = 1000000` and `RegexDepthLimit = 1000` can be set via the CLI, so pathological backtracking patterns fail with an error instead of hanging. Cancellation is checked between read and match calls but cannot interrupt a single in-flight PCRE2 call.
- Currently **exactly one regex pattern per request** is allowed; multiple `-e` with `--regex` are rejected with a clear argument error. Non-regex modes are unaffected.
- Regex uses Perl-compatible PCRE2 matching (non-overlapping), not NativePattern's literal overlap semantics.

## Testing

After a successful Delphi Win64 build, run `NativeGrep.Tests.exe`, `Invoke-NativeGrepCliSmoke.ps1`, and `Invoke-NativeGrepRegexSmoke.ps1 -Exe <path>`. Regex integration tests are **explicitly reported as SKIPPED** while `pcre2-8.dll` is missing next to the test executable; a bare `PASS` in that case does not certify the regex path.
