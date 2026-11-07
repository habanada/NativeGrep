param([Parameter(Mandatory = $true)][string]$Exe)
$ErrorActionPreference = 'Continue'
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$Root = Join-Path ([IO.Path]::GetTempPath()) ('NativeGrep_CliSmoke_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Root) | Out-Null
try {
    [IO.File]::WriteAllBytes((Join-Path $Root 'z.txt'), [Text.Encoding]::ASCII.GetBytes("TODO`nNOPE`nTODO"))
    [IO.File]::WriteAllBytes((Join-Path $Root 'a.txt'), [Text.Encoding]::ASCII.GetBytes('TODO'))
    $Utf16 = [Text.Encoding]::Unicode
    [IO.File]::WriteAllBytes((Join-Path $Root 'utf16.txt'), ($Utf16.GetPreamble() + $Utf16.GetBytes('TODO')))
    $Output = & $Exe --help 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (($Output | Out-String) -match 'Usage:')) { throw 'help exit/output failed' }
    $Output = & $Exe 'UNMATCHABLE_VALUE_2026' $Root --include '*.txt' --quiet 2>&1
    if ($LASTEXITCODE -ne 1) { throw 'no-match exit code must be 1' }
    $Output = & $Exe 'TODO' $Root --include '*.txt' -r --threads 1 --sort 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'sorted single-worker search failed' }
    $Single = @($Output | ForEach-Object { [string]$_ })
    $Output = & $Exe 'TODO' $Root --include '*.txt' -r --threads 4 --sort 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'sorted four-worker search failed' }
    $Parallel = @($Output | ForEach-Object { [string]$_ })
    if ([string]::Join("`n", $Single) -ne [string]::Join("`n", $Parallel)) { throw 'sorted output differs by worker count' }
    if ($Single.Count -ne 4) { throw "expected four sorted matches, got $($Single.Count)" }
    $Output = & $Exe 'TODO' $Root --include '*.txt' -r --threads 4 --sort --max-results 2 2>&1
    if ($LASTEXITCODE -ne 0 -or @($Output).Count -ne 2) { throw 'sorted global result limit failed' }
    $Output = & $Exe 'TODO' $Root --include '*.txt' -r --threads 4 --sort --quiet --max-results 2 --stats 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (($Output | Out-String) -match 'matches=2')) { throw 'quiet sorted result limit failed' }
    $Output = & $Exe 'TODO' $Root --include '*.txt' -r --jsonl 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'JSONL search failed' }
    foreach ($Line in $Output) {
        $Record = ([string]$Line) | ConvertFrom-Json
        if ($Record.type -ne 'match') { throw 'unexpected JSONL event' }
    }
    $Output = & $Exe 'TODO' (Join-Path $Root 'missing') --quiet 2>&1
    if ($LASTEXITCODE -ne 2) { throw 'missing root must return exit 2' }
    $Output = & $Exe --not-a-real-flag 2>&1
    if ($LASTEXITCODE -ne 2) { throw 'invalid argument must return exit 2' }
    $A = Join-Path $Root 'a.txt'
    [IO.File]::SetLastWriteTimeUtc($A, [datetime]::new(2026, 1, 15, 12, 0, 0, [DateTimeKind]::Utc))
    $Output = & $Exe 'TODO' $Root --file-size '4..4' --sort 2>&1
    if ($LASTEXITCODE -ne 0 -or @($Output).Count -ne 1 -or -not ([string]$Output -like '*a.txt:*')) { throw 'exact size range failed' }
    $Output = & $Exe 'TODO' $A --file-size '<4' 2>&1
    if ($LASTEXITCODE -ne 1) { throw 'strict maximum failed for explicit file' }
    $Output = & $Exe 'TODO' $A --file-size '>4' 2>&1
    if ($LASTEXITCODE -ne 1) { throw 'strict minimum failed for explicit file' }
    $Output = & $Exe 'TODO' $A --min-file-size '0.004KB' --max-file-size '4B' 2>&1
    if ($LASTEXITCODE -ne 0 -or @($Output).Count -ne 1) { throw 'inclusive size bounds and units failed' }
    $Output = & $Exe 'TODO' $A --modified-from '2026-01-15T13:00:00+01:00' --modified-to '2026-01-15T12:00:00Z' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'timestamp equality or timezone offset failed' }
    $Output = & $Exe 'TODO' $A --modified-from '2026-01-16T00:00:00Z' 2>&1
    if ($LASTEXITCODE -ne 1) { throw 'modified lower bound failed' }
    [IO.File]::SetLastWriteTime($A, [datetime]::new(2026, 1, 15, 23, 59, 59))
    $Output = & $Exe 'TODO' $A --modified-from '2026-01-15' --modified-to '2026-01-15' --file-size '=4' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'whole local day or combined metadata filters failed' }
    [IO.File]::SetLastWriteTimeUtc($A, [datetime]::UtcNow.AddHours(-2))
    $Output = & $Exe 'TODO' $A --modified-from 'now-1h' 2>&1
    if ($LASTEXITCODE -ne 1) { throw 'relative modified time failed' }
    foreach ($Arguments in @(
        @('--file-size', '8..4'),
        @('--file-size', '0.1B'),
        @('--file-size', '9223372036854775808'),
        @('--file-size', '>4', '--min-file-size', '1'),
        @('--min-file-size', '8', '--max-file-size', '4'),
        @('--modified-from', '2026-02-30'),
        @('--modified-from', '2026-02-01', '--modified-to', '2026-01-01'),
        @('--modified-from', 'now-1x')
    )) {
        $Output = & $Exe 'TODO' $A @Arguments 2>&1
        if ($LASTEXITCODE -ne 2) { throw "invalid filter must return exit 2: $Arguments" }
    }
    $Output = & $Exe 'TODO' --stdin --file-size '>4' 2>&1
    if ($LASTEXITCODE -ne 2 -or -not (($Output | Out-String) -match 'filters cannot be used with --stdin')) { throw 'metadata filters must be rejected for stdin' }
    Write-Output 'NativeGrep CLI smoke tests: PASS'
} finally {
    if (Test-Path -LiteralPath $Root) { [IO.Directory]::Delete($Root, $true) }
}
