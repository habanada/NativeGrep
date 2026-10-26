# NativeGrep - Profiling and benchmarks

## CLI profiling

`--profile` enables high-resolution internal measurements via the Windows `QueryPerformanceCounter` and implies `--stats`. Without `--profile`, measurement is disabled. `--quiet` suppresses match lines while matching and sink callbacks stay active; omit `--quiet` for a benchmark that reflects real output.

```powershell
npgrep "TODO" "E:\Projects" -r --threads 4 --include "*.pas" --quiet --profile
```

The first stderr line stays unchanged (`files=... bytes=... matches=... errors=... workers=... elapsed_ms=...`). A second, machine-readable line is added (`profile_us ...`). All profiling values are in **microseconds**.

| Field | Meaning |
|---|---|
| `discovery_wall` | Producer runtime, including waiting on a full work queue |
| `discovery_enqueue` | Sum of producer calls enqueuing paths, including wait time on a full work queue; a subset of `discovery_wall` |
| `compile_workers` | Sum of matcher compile time across all workers |
| `file_open_workers` | Sum of file-open time, including failed opens |
| `buffer_setup_workers` | Sum of actual read-buffer setup time; only on size changes |
| `buffer_allocations` | Number of buffer allocations; at most once per worker for a fixed query and seekable files |
| `file_read_workers` | Sum of time actually spent in `Stream.Read` |
| `matching_workers` | Sum of NativePattern `FindFirst` call time |
| `text_position_workers` | Sum of UTF-8 line/column processing time |
| `result_enqueue_workers` | Sum of match-queue enqueue time, including backpressure |
| `file_scan_workers` | Sum of total per-file scan time, including reader, matcher, and other scanner work |
| `work_queue_wait_workers` | Sum of all workers' wait time for file paths (including waiting on the producer and completion) |
| `sink_dispatch` | Sum of all `MatchFound`/`ScanError` callbacks, including text formatting and output in the CLI sink |

**Important:** only `elapsed_ms` and `discovery_wall` are wall-clock times; the `*_workers` values are **summed across all workers** and can exceed real total runtime. Phases also run in parallel and must not be added up to reconstruct runtime. The producer value includes backpressure wait time, not exclusive enumeration CPU time. `file_read_workers` measures reader calls and is not equal to total I/O cost (open, filesystem cache, metadata). `sink_dispatch` measures callback time, not the dispatcher's wait for results.

The scanner uses one read buffer **per worker** per search session and recycles it across that worker's files. This reduces the number of 1 MiB buffer allocations from roughly `files` to at most `workers`, especially with many small files. `discovery_enqueue` is not pure blocking time: lock, queue, and callback costs are included. Subtracting `discovery_enqueue` from `discovery_wall` does not yield exact pure enumeration CPU time.

Measurement itself adds overhead; especially for patterns with very many matches, compare absolute runtime with and without `--profile`. `--quiet` still measures match generation, queueing, and callbacks, just without console output.

## Comparing worker counts

```powershell
.\benchmarks\bench.ps1 -Exe '.\bin\Win64\Release\npgrep.exe' -Root 'C:\Projects' -Pattern 'TODO' -Include '*.pas' -Repeats 5 -Warmups 1 -CsvPath '.\nativegrep-benchmark.csv'
```

The script runs measurements for 1/2/4/8 workers, verifies matches, bytes, file counts, and errors, computes the median runtime per worker count, and writes individual measurements for all phases to a CSV file. By default, results are not dominated by console output because of `--quiet`.

For reliable comparisons: **Win64 Release build**, identical search filters, separate measurements on SSD/HDD/network drives, multiple runs with warmup, the same output policy, and no concurrent builds in the test directory. A single large file keeps only one worker busy by design in the current architecture. Mark warm-cache/cold-cache runs separately; the script measures with warmup and does not force cache eviction.

## Result checks

- 1 vs. N workers: identical matches `(path, byte offset, length)` and identical file counts on the same dataset.
- Profiling on/off: identical search results, identical error/cancellation semantics.
- Chunk boundaries, overlapping matches, long patterns, UTF-8 line positions, result queue under load, and forced cancellation.
- Run the NativeGrep integration tests and the existing NativePattern tests under DCC64 Debug and Release.
- Collect measurements from successfully compiled and executed binaries; the source implementation alone is not a benchmark result.
