# NativeGrep Replace: safety and regression tests

## Running the tests

Run replacement tests against disposable files. Build `tests/NativeGrep.Tests.dproj` for Win64 Debug and Release, run the automated suite, then check the GUI and filesystem cases below.

The stress suite lives in `tests/NativeGrep.Replace.StressTests.pas` and is called from `NativeGrep.Tests.dpr` after the existing replace tests. It generates all test files in the temp test directory created by the existing test host program. A fixed random seed makes test data reproducible. Regex cases require `pcre2-8.dll` beside the test EXE; see [regex setup](regex.md).

## Automated coverage

| Category | Evidence |
|---|---|
| Randomized byte replacements | 96 deterministic test files, varying replacement lengths including deletion, compared against an independent reference function, match count, byte-for-byte backup comparison, deliberately reversed match order |
| Randomized UTF-8 replacements | 64 deterministic text files with optional BOM, emoji/surrogate pairs, combining characters, and mixed line endings; replacement lengths from 0 to 200 characters; control output via `StringReplace` and byte comparison |
| Streaming/chunk boundaries | 4 MiB of input data with matches at offset 0, 4094, 65535, 1048575, 2097151, and end-of-file; full result and backup comparison |
| Backup name conflicts | existing `.bak` and `.bak3` are left untouched, an existing `.bak2` directory is not overwritten, the new backup becomes `.bak4` |
| Unicode and deletion | UTF-8 BOM is preserved, Unicode replacement and mixed newlines stay byte-exact; full match removal with empty replacement text |
| Cancellation and skip | cancellation via `OnBeforeReplace`, full skip, a pre-cancelled external token, cancellation via `OnProgress` after the first file commit |
| Event contract | call counts and fixed order of Before, After, Progress, AllReplaced, and Completed; missing `AllReplaced` on cancel, skip, and error |
| Exception after commit | `OnAfterReplace` throws after a successful file swap: `OnCompleted` reports the error while the changed file and backup stay visible and consistent |
| Reentrancy | a nested `Replace` call on the same instance is rejected; a subsequent regular call still works |
| Invalid results | duplicate matches, invalid byte offset, a different query against the same matches are all rejected without file/backup changes |
| Filesystem errors | an exclusively locked file blocks replace; after release, the same instance can be reused. A file deleted between search and replace stays deleted |
| Filenames and empty selection | a Unicode filename is replaced and backed up correctly; an empty match selection changes no file |
| Temp files | no `.nativegrep-*.tmp` files remain in the test directory after any test group |

The existing tests in `NativeGrep.Replace.Tests.pas` remain, covering `.bak` through `.bak3`, UTF-16LE/BE, regex, overlap, and `OnError` with continuation.

## Coverage limits

1. **A file changes after the last validation scan:** the existing `TGrepMatch` API carries no file fingerprint. The implementation re-checks the selected matches, not a full file snapshot; a change elsewhere can go unnoticed. The window between closing the read stream and `ReplaceFileW` is not transactionally protected either.
2. **Power loss, process termination, or disk failure during `CopyFile`/`ReplaceFileW`:** these require an isolated VM with controlled fault injection.
3. **NTFS ACLs, alternate data streams, hardlinks, read-only/hidden/system attributes, locked files, and network drives:** verify separately on target filesystems. Byte-identical file content does not guarantee identical metadata.
4. **Cancellation during a multi-second copy operation:** tests check cancellation before commit and between file commits, but not every possible interleaving within I/O syscalls.
5. **Unicode and regex edge cases:** regex capture references such as `$1` are treated as literal replacement text. A zero-length regex test exists in the current test module; Unicode fuzzing across all PCRE2 options is not covered.
6. **Concurrent external writes and GUI interaction:** switching viewer/file handles, multi-selection, a cancel dialog, a second concurrent replace start, and closing the GUI during the worker, as a separate UI test.
7. **Very large files and bulk searches:** a load test well beyond 4 MiB with many thousands of matches; log free disk space and peak RAM.

## Manual checks

1. Create three disposable files with different encodings (UTF-8 without BOM, UTF-8 with BOM, UTF-16LE) in a dedicated test folder.
2. Run a search, select a subset of matches with Ctrl/Shift, and replace only those. Compare content and `.bak` byte-for-byte against the original copy.
3. Run another search and use `Replace all`. `.bak2` and, if applicable, `.bak3` must be newly created without altering the older backups.
4. Cancel a run over at least three files after the first changed file. Verify every completed commit has exactly one backup and every not-yet-processed file is still byte-identical.
5. Search for a match, then modify the file before replacing, so the match no longer sits at its original position. Replace must reject the file and must not create a backup.
6. Re-search a restored state through the GUI to rule out stale offsets. Check viewer file handles and file locks.
7. Use a separate comparison script to cross-check hash values of the backups against the previously saved originals for every changed file.

## Build and result capture

Project: `tests/NativeGrep.Tests.dproj` as **Debug / Win64**, then run `NativeGrep.Tests.exe`. Expected additional completion line:

```text
NativeGrep Replace stress: 160 randomized cases and destructive-path tests PASS
```

Followed, on success, by `NativeGrep tests: PASS`.
