# File change monitoring

`NativeGrep.FileMonitor` is a standalone Windows-only library unit. It observes one directory root, optionally recursively, through `ReadDirectoryChangesW` with overlapped I/O. The monitor tracks only files explicitly registered through `TrackCurrent` or `Track`. One tracked file produces a status transition rather than a notification for every write. A log file receiving frequent writes therefore does not cause automatic rescans or repeated UI messages.

## File states

- `gfsCurrent`: no change detected since registration; this is not a cryptographic proof of unchanged content.
- `gfsChanged`: a relevant directory notification arrived, or size, last-write time or file identity differs from the registered snapshot.
- `gfsDeleted`: the source path was absent during explicit verification.
- `gfsUnknown`: monitoring failed, notifications were lost, the monitor stopped, or the metadata could not be verified.

Statuses remain stale until a new monitor session starts. `Drain` returns transitions for a UI thread to consume; callbacks never touch VCL controls. On notification-buffer overflow or watcher failure, every tracked file becomes `gfsUnknown`, rather than incorrectly returning to `gfsCurrent`.

## GUI behavior

The results list includes the `STATE` column (`Watching`, `Changed`, `Deleted`, `Unknown`). Double-clicking an outdated result offers to rerun the entire search. Searches never restart automatically. Replace checks source metadata before confirmation and once again per source file through `OnBeforeReplace`. If a conflict is found, Replace does not proceed to that file.

A file is registered on its first match, not at the instant the scanner opened it. Monitoring is started before the scan; after the scan a secondary metadata comparison runs in the search worker. This reduces, but cannot eliminate, race conditions around concurrent writes.

## Safety limitations

Monitoring and file metadata are hints, not a transaction guarantee. They cannot guarantee detection of edits with restored metadata, all notifications lost between file operations, or another writer changing a file after the last check and before `ReplaceFileW`. Existing match validation, temporary output files and `.bak` backups remain essential. Strict integrity requirements still need stronger conflict protection. Monitoring failures deliberately disable Replace until a new valid scan.

One directory root is monitored per session, reflecting the current GUI's single-folder search. The library can be used independently from the GUI. The tests exercise event delivery, rapid log writes, state latching, deletion, rename, metadata rechecks, monitor stop, and reset.
