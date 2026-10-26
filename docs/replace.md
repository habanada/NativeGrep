# NativeGrep: Replace API

`NativeGrep.Replace.TGrepReplacer` replaces selected `TGrepMatch` results **after** a search has completed. The class processes files synchronously on the calling thread and can be used from a GUI worker. Events run on the same thread and must be marshaled to the UI thread if needed.

## API

```pascal
uses
  NativeGrep.Types, NativeGrep.Api, NativeGrep.Replace;

var
  Replacer: TGrepReplacer;
  Stats: TGrepReplaceStatistics;
begin
  Replacer := TGrepReplacer.Create;
  try
    Stats := Replacer.ReplaceText(Request, Matches, 'NEW');
  finally
    Replacer.Free;
  end;
end;
```

`Matches` is a `TArray<TGrepMatch>` from the **same** `TGrepRequest.Query` passed to `ReplaceText`. `ReplaceBytes(Request, Matches, ReplacementBytes)` handles byte queries with a `TBytes` replacement. Both methods are synchronous and accept an external `IGrepCancellation` token. One call per replacer instance at a time; `Cancel` can be called from another thread.

**Supported search modes:** `ReplaceText` supports `gmLiteralText`, `gmMultiText`, `gmFuzzyText`, and `gmRegexText`; `ReplaceBytes` supports `gmLiteralBytes`, `gmMultiBytes`, `gmMaskedHex`, and `gmFuzzyBytes`. Text is encoded as UTF-8, UTF-16LE, or UTF-16BE per `Query.Encoding`. With `geAuto`, each file's BOM decides; without a UTF-16 BOM, UTF-8 is used. Unchanged file regions are copied byte-for-byte; BOM and line endings are not rewritten. Replacement data may be empty (deletion). Regex replacement treats `$1`, `${name}`, and similar capture references as literal text. Regex match validation requires `pcre2-8.dll` beside the host EXE; see [regex setup](regex.md).

## Events

| Event | Meaning |
|---|---|
| `OnBeforeReplace(Sender, Match, var Skip, var Cancel)` | Before changing one match. `Skip=True` skips only this match. `Cancel=True` ends the whole operation before the next commit. |
| `OnAfterReplace(Sender, Match, BackupPath)` | After a successful commit, **for each match actually replaced**; `BackupPath` names the backup created. |
| `OnProgress(Sender, SourcePath, Statistics)` | After finishing one file (including skipped files or a file where `OnError` chose to continue). |
| `OnError(Sender, SourcePath, ErrorText, var ContinueProcessing)` | By default the exception propagates. `ContinueProcessing=True` continues with the next file; an already-modified file is not rolled back. |
| `OnAllReplaced(Sender, Statistics)` | Only on fully successful processing, **without cancellation, error, or skipped matches**. |
| `OnCompleted(Sender, Statistics)` | Always fires at the end, including on cancellation or exception. Check `Failed`, `Cancelled`, and the counters. |

`TGrepReplaceStatistics` has `FilesTotal`, `FilesProcessed`, `FilesChanged`, `MatchesTotal`, `MatchesReplaced`, `MatchesSkipped`, `BackupsCreated`, `Errors`, `Cancelled`, and `Failed`. Events fire sequentially. `OnAfterReplace` is a **post-write notification**, not a veto; an error raised inside it cannot undo an already-successful file replace.

## Safe writing / backup

1. Sort matches by path and byte offset, group per file, and reject overlapping ranges.
2. Re-search every selected match **in the file, with the same query, right before writing**; missing matches block the write. This does not guarantee the file's original overall state, since `TGrepMatch` carries no snapshot hash.
3. Write the new content to a temporary file **in the same directory**; non-match regions are streamed through without loading complete source files into RAM.
4. Only after successful preparation, back up the entire original file with `CopyFileW(..., FailIfExists=True)`: first `file.bak`, then `file.bak2`, `file.bak3`, and so on if those already exist. Existing backups are never overwritten.
5. Swap the original file for the prepared one using Win32 `ReplaceFileW`. Each file has an independent commit; **there is no single transaction across multiple files**.

A failure to create the backup blocks the swap. If `ReplaceFileW` fails and the original path is missing, the code attempts to restore the original from the backup just created, without overwriting other files; the exception names any restore failure. If the swap fails, or the operation is cancelled after the backup, the newly created backup can remain even though the original file is unchanged. A leftover temp file is deleted on a best-effort basis. Reparse-point files and directories are rejected. File write permissions, file locks, and filesystem behavior can prevent the commit.

**File conflicts:** the re-search confirms the selected matches still fit the current file. It is not full protection against changes elsewhere in the file, or against an external write in the very short window between closing the source file and `ReplaceFileW`. The replacement API does not provide snapshot isolation.

**Partial search runs:** only the matches actually passed in are replaced. A previously cancelled or bounded search does not mean "all matches on disk." Before a GUI "Replace all" button, the GUI must ensure it passes a complete, intended selection.

## Tests / validation

The unit `tests/NativeGrep.Replace.Tests.pas` holds regression tests for `.bak`/`.bak2`/`.bak3`, existing backups, event order and counters, skip/cancel, missing matches, overlapping matches, UTF-16 BOM, binary replacements, and cancellation after the first file commit. `NativeGrep.Tests.dpr` calls `RunReplaceTests`.

See [replacement tests](replace-testing.md) for automated coverage and manual checks.
