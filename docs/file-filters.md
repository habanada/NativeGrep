# File size and time filters

NativeGrep applies metadata filters during file discovery, before opening files for content search. CLI, GUI and library use the same rules. All active size, time, include and exclude conditions must match. Filters apply to both explicit file paths and files discovered in directories, including recursive searches.

## File size

`--min-file-size SIZE` sets an inclusive minimum. `--max-file-size SIZE` sets an inclusive maximum; its existing value `0` means unlimited. Combine them for a closed range.

`--file-size EXPR` provides strict comparisons, inclusive comparisons, exact sizes and closed ranges:

| Expression | Meaning |
|---|---|
| `<10MiB` | smaller than 10 MiB |
| `<=10MiB` | no larger than 10 MiB |
| `>1KB` | larger than 1,000 bytes |
| `>=1KiB` | at least 1,024 bytes |
| `=0` | empty files only |
| `=4KiB` or `4KiB` | exactly 4,096 bytes |
| `1MiB..20MiB` | between 1 and 20 MiB, including both limits |

Use `--file-size` once, or use `--min-file-size` and `--max-file-size`. Mixing these forms is rejected to prevent accidental replacement of conditions.

Sizes use Int64 byte counts. Bare numbers and `B` mean bytes; `KB`, `MB`, `GB` and `TB` use powers of 1,000; `KiB`, `MiB`, `GiB` and `TiB` use powers of 1,024. The shorthand suffixes `K`, `M`, `G` and `T` also use powers of 1,024. Units are case insensitive. A decimal point is accepted with up to six fractional digits, provided the result is an exact whole number of bytes. Negative values, overflow, unknown units and reversed ranges are rejected.

Quote expressions containing `<` or `>` so the shell does not interpret them as redirection.

```powershell
npgrep TODO C:\Projects -r --file-size ">1MiB"
npgrep TODO C:\Projects -r --file-size "<=20MiB"
npgrep TODO C:\Projects -r --min-file-size 1KiB --max-file-size 10MiB
npgrep TODO C:\Projects -r --file-size "1.5MiB..20MiB"
```

An empty file can pass discovery, but content searches still produce no matches for it.

## File times

Creation, modification and last access each have independent optional lower and upper bounds:

| File time | Lower bound | Upper bound |
|---|---|---|
| Creation | `--created-from` | `--created-to` |
| Modification | `--modified-from` | `--modified-to` |
| Last access | `--accessed-from` | `--accessed-to` |

Accepted values:

- `2026-11-07`: a local calendar date. A lower bound starts at midnight; an upper bound includes the entire day, up to but excluding the next local midnight.
- `2026-11-07T14:30:00` or `"2026-11-07 14:30:00"`: a local timestamp. Timestamp bounds are inclusive.
- `2026-11-07T13:30:00Z` or `2026-11-07T14:30:00+01:00`: a timestamp with an explicit timezone. Fractional seconds support up to seven digits, preserving 100 ns file time precision.
- `today` and `yesterday`: local calendar dates, with the same whole-day rules.
- `now`, `now-30m`, `now-24h`, `now-7d`: the current instant or an elapsed duration before it. Units are minutes, hours and days; a relative day is 24 hours.

Relative values are resolved when a request is built. Saved GUI expressions are resolved again for each search. Local calendar days follow the system timezone and its daylight saving rules. Prefer an explicit UTC offset for ambiguous times during a daylight saving transition.

```powershell
npgrep ERROR C:\Logs -r --modified-from now-24h --modified-to now
npgrep TODO C:\Projects -r --modified-from 2026-11-01 --modified-to 2026-11-07
npgrep TODO C:\Projects -r --created-from today --max-file-size 5MiB
```

Time filters use Windows filesystem metadata, rather than dates found in the file contents. Last access timestamps depend on the filesystem and Windows update policy; they can be delayed or disabled. Metadata is sampled during discovery, and a file may change before it is scanned. Filters select files for a search; replacement still uses the existing result and file-change checks.

## GUI

The **File filters** tab provides a size comparison selector, size value fields, separate From/To fields for all three file times, and exclude masks. The second size field is used for **Between (inclusive)**. A blank time field leaves that bound unrestricted.

Choose **Modified**, **Created** or **Last accessed** in the time helpers. Apply a relative template, or choose a value in the NimbusForms calendar and select **From date**, **To date**, **From date and time** or **To date and time** before applying it. Date/time mode enables the calendar's time selection. Applying a helper changes the corresponding bound fields; those fields define the filter.

**Apply file filters** temporarily disables the conditions while retaining their values. **Clear all filters** removes them. The tab caption shows when conditions are active. Preferences, including relative expressions, are saved with the other search settings. Invalid input is reported before a search starts.

## Library

`TGrepOptions.FileSizeFilter`, `CreatedTimeFilter`, `ModifiedTimeFilter` and `AccessedTimeFilter` are `TGrepFilterRange` records. `HasMinimum` and `HasMaximum` activate the bounds independently; `MinimumExclusive` and `MaximumExclusive` make an active bound strict. A default record imposes no restriction. Size values are bytes. Time values are UTC Windows FILETIME ticks, with 100 ns units since 1601-01-01.

`NativeGrep.Filters` exposes shared parsing and validation:

```pascal
Request.Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('1MiB..20MiB');
Request.Options.ModifiedTimeFilter := TGrepFileFilters.ParseTimeRange('now-7d', 'now');
Request.Options.CreatedTimeFilter := TGrepFileFilters.ParseTimeRange('', '2026-11-07');
TGrepFileFilters.Validate(Request.Options);
```

`UtcTicks` converts a UTC `TDateTime` into file time ticks. `Contains` tests a range without filesystem access. The existing `MaxFileSize` remains supported and intersects with `FileSizeFilter`; a positive legacy maximum can further restrict the range. A contradictory size or time range raises `EArgumentException` before worker threads start.

`SearchStream` and `SearchBytes`, including CLI `--stdin`, reject active size/time metadata filters because these sources have no filesystem metadata. Leave those filters at their defaults when searching streams or bytes.
