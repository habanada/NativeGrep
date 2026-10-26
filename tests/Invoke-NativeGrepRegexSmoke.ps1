param([Parameter(Mandatory = $true)][string]$Exe)
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path -LiteralPath $Exe).Path
$dllPath = Join-Path (Split-Path -Parent $exePath) 'pcre2-8.dll'
if (-not (Test-Path -LiteralPath $dllPath)) { throw 'PCRE2 smoke tests require pcre2-8.dll beside the executable' }
$dir = Join-Path ([System.IO.Path]::GetTempPath()) ('NativeGrepRegex_' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($dir) | Out-Null
try {
    $source = Join-Path $dir 'regex.txt'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($source, "GetCustomer(12)`nGetCustomer (345)`n", $utf8)
    $output = @(& $exePath --regex 'GetCustomer\s*\(([0-9]+)\)' $dir -r --threads 4 --include '*.txt' --jsonl --sort)
    if ($LASTEXITCODE -ne 0) { throw 'Regex search returned nonzero exit code' }
    if ($output.Count -ne 2) { throw "Expected two regex events, got $($output.Count)" }
    $first = $output[0] | ConvertFrom-Json
    $second = $output[1] | ConvertFrom-Json
    if ($first.offset -ne 0 -or $first.captures[0].offset -ne 12 -or $first.captures[0].length -ne 2) { throw 'First capture offsets incorrect' }
    if ($second.offset -ne 16 -or $second.captures[0].length -ne 3) { throw 'Second capture offsets incorrect' }
    $null = & $exePath --regex '[' $dir -r --include '*.txt' 2>&1
    if ($LASTEXITCODE -ne 2) { throw 'Invalid regex should exit with code 2' }
    $large = Join-Path $dir 'large.txt'
    [System.IO.File]::WriteAllBytes($large, (New-Object byte[] (1048577)))
    $null = & $exePath --regex 'GetCustomer\d+' $large --regex-max-mib 1 --quiet 2>&1
    if ($LASTEXITCODE -ne 2) { throw 'Regex max source limit should yield a file error' }
    $invalid = Join-Path $dir 'invalid.dat'
    [System.IO.File]::WriteAllBytes($invalid, [byte[]](84,79,68,79,10,255,70,73,88,77,69,10,84,79,68,79))
    $null = & $exePath --regex 'TODO|FIXME' $invalid --quiet 2>&1
    if ($LASTEXITCODE -ne 2) { throw 'Strict regex on invalid UTF-8 must report an error' }
    $events = @(& $exePath --regex 'TODO|FIXME' $invalid --regex-invalid-utf --jsonl --sort)
    if ($LASTEXITCODE -ne 0) { throw 'Tolerant regex mode should search valid UTF-8 regions' }
    if ($events.Count -ne 3) { throw "Tolerant regex expected 3 events, got $($events.Count)" }
    $positions = @($events | ForEach-Object { $_ | ConvertFrom-Json })
    if ($positions[0].offset -ne 0 -or $positions[1].offset -ne 6 -or $positions[2].offset -ne 12) { throw 'Tolerant regex byte offsets are incorrect' }
    if ($positions[0].line -ne 0) { throw 'Malformed UTF-8 file must not expose uncertain text columns' }
    Write-Host 'NativeGrep regex smoke tests: PASS'
}
finally {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
}
