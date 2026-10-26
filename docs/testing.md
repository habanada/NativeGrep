# NativeGrep - Building and testing

## Public contract

- `NativeGrep.Types`: search modes, options, byte-offset results, statistics, cancellation, and sink interface.
- `NativeGrep.Api`: `TNativeGrep.Search`, `SearchStream`, `SearchBytes` as the synchronous public facade.
- `SourcePath` is a display name; `ByteOffset` is 0-based, `Line`/`Column` are 1-based or 0 when not computed.
- The library calls sink methods only sequentially on the calling thread. No direct VCL dependency.
- `SearchStream` does **not** take ownership of the stream and starts at its current position. `SearchBytes` keeps no user buffer after returning.
- `MaxWorkers=0`: auto (capped at 8), explicit 1 to 64. Worker matchers are never shared between threads.
- `SortResults=False`: direct completion order. `SortResults=True`: defined path/byte-offset ordering, then the global result limit; may use temp files.

## Build and runtime checks

1. Build `apps/npgrep/npgrep.dproj` for Win64 **Debug**, no compiler errors.
2. Build `tests/NativeGrep.Tests.dproj` for Win64 **Debug**; `NativeGrep.Tests.exe` must print `PASS`.
3. Build the same projects for Win64 **Release** and re-run the tests.
4. Run `tests/Invoke-NativeGrepCliSmoke.ps1` against the built Release EXE.
5. Compare `--threads 1`, `4`, `8` against real directories; without `--sort` the match set must be identical, with `--sort` the match order must be identical.
6. Check cancellation under a full result queue, sort-merge cancellation, and an exception from a sink (dedicated Delphi tests).
7. Check the temp location: large sorted searches need enough space and write access; no leftover sort files after normal completion or on an error/cancel path.
8. Check missing/locked files: other files keep scanning, errors surface through the sink and CLI exit code 2.
9. For Unicode: test sigma, U+00DF (eszett), NFD, UTF-8/UTF-16 BOM, invalid sequences, and byte offsets across chunk boundaries.
10. Test a sparse file over 4 GiB and large real files for correct Int64 offsets on the target system. This run is separate from the regular quick test.
11. Measure Release performance with 1/2/4/8 workers against representative HDD/SSD data; never interpret cache-warm-only runs as raw disk throughput.

## CLI verification

```powershell
.\bin\Win64\Release\npgrep.exe --help
.\bin\Win64\Release\NativeGrep.Tests.exe
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-NativeGrepCliSmoke.ps1 -Exe .\bin\Win64\Release\npgrep.exe
```

`NativeGrep.Tests.exe` may land elsewhere depending on the project's output path; use its actual path in that case. CLI exit codes: 0 = matches found, 1 = no matches, 2 = error or invalid arguments, 130 = aborted via Ctrl+C.

## Regex tests

Place Win64 `pcre2-8.dll` beside each test or application EXE used by regex tests, including both Debug and Release builds. The DLL must provide PCRE2 10.x with Unicode support. Without it, regex integration cases are reported as skipped; a passing non-regex run does not verify regex behavior.

Run the additional regex smoke script against the Release CLI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-NativeGrepRegexSmoke.ps1 -Exe .\bin\Win64\Release\npgrep.exe
```

See [replacement tests](replace-testing.md) for backup, cancellation, and filesystem cases.
