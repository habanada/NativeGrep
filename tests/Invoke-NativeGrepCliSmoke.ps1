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
    Write-Output 'NativeGrep CLI smoke tests: PASS'
} finally {
    if (Test-Path -LiteralPath $Root) { [IO.Directory]::Delete($Root, $true) }
}
