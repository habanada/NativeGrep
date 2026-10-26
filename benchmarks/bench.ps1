param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [Parameter(Mandatory=$true)][string]$Root,
    [string]$Pattern = 'TODO',
    [string]$Include = '*.pas',
    [int[]]$Threads = @(1, 2, 4, 8),
    [ValidateRange(1,100)][int]$Repeats = 3,
    [ValidateRange(0,100)][int]$Warmups = 1,
    [string]$CsvPath = '.\nativegrep-benchmark.csv'
)
$ErrorActionPreference = 'Stop'

function Quote-Argument([string]$Value) {
    $result = '"'
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') { $slashes++; continue }
        if ($ch -eq '"') { $result += ('\' * ($slashes * 2 + 1)) + '"' }
        else { $result += ('\' * $slashes) + $ch }
        $slashes = 0
    }
    return $result + ('\' * ($slashes * 2)) + '"'
}

function Read-Metrics([string]$Line) {
    $values = @{}
    foreach ($part in ($Line -split '\s+')) {
        if ($part.Contains('=')) {
            $pair = $part -split '=', 2
            $values[$pair[0]] = $pair[1]
        }
    }
    return $values
}

function Invoke-Grep([int]$WorkerCount) {
    $arguments = @($Pattern, $Root, '-r', '--threads', [string]$WorkerCount, '--include', $Include, '--quiet', '--profile')
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = (Resolve-Path -LiteralPath $Exe).Path
    $start.Arguments = (($arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $diagnostics = $process.StandardError.ReadToEnd()
        $outputTask.GetAwaiter().GetResult() | Out-Null
        $process.WaitForExit()
        if ($process.ExitCode -gt 1) { throw "npgrep exited with $($process.ExitCode): $diagnostics" }
        $statsLine = @($diagnostics -split '[\r\n]+' | Where-Object { $_ -match '^files=' })
        $profileLine = @($diagnostics -split '[\r\n]+' | Where-Object { $_ -match '^profile_us ' })
        if (($statsLine.Count -ne 1) -or ($profileLine.Count -ne 1)) { throw "Missing stats or profile line: $diagnostics" }
        $stats = Read-Metrics $statsLine[0]
        $profile = Read-Metrics $profileLine[0]
        if ([long]$stats['errors'] -ne 0) { throw "Files with errors: $diagnostics" }
        return [pscustomobject]@{
            Workers = $WorkerCount
            ElapsedMs = [long]$stats['elapsed_ms']
            Files = $stats['files']
            Bytes = [long]$stats['bytes']
            Matches = [long]$stats['matches']
            MiBPerSecond = $(if ([long]$stats['elapsed_ms'] -gt 0) { [math]::Round(([long]$stats['bytes'] / 1048576.0) / ([long]$stats['elapsed_ms'] / 1000.0), 2) } else { 0 })
            DiscoveryWallUs = [long]$profile['discovery_wall']
            DiscoveryEnqueueUs = [long]$profile['discovery_enqueue']
            CompileWorkerUs = [long]$profile['compile_workers']
            FileOpenWorkerUs = [long]$profile['file_open_workers']
            BufferSetupWorkerUs = [long]$profile['buffer_setup_workers']
            BufferAllocations = [long]$profile['buffer_allocations']
            FileReadWorkerUs = [long]$profile['file_read_workers']
            MatchingWorkerUs = [long]$profile['matching_workers']
            TextPositionWorkerUs = [long]$profile['text_position_workers']
            EnqueueWorkerUs = [long]$profile['result_enqueue_workers']
            FileScanWorkerUs = [long]$profile['file_scan_workers']
            WorkQueueWaitWorkerUs = [long]$profile['work_queue_wait_workers']
            SinkDispatchUs = [long]$profile['sink_dispatch']
        }
    } finally {
        $process.Dispose()
    }
}

$rows = New-Object System.Collections.Generic.List[object]
$baseline = $null
foreach ($workerCount in $Threads) {
    if (($workerCount -lt 1) -or ($workerCount -gt 64)) { throw 'Threads must be between 1 and 64' }
    for ($i = 1; $i -le $Warmups; $i++) { [void](Invoke-Grep $workerCount) }
    for ($i = 1; $i -le $Repeats; $i++) {
        $result = Invoke-Grep $workerCount
        if ($null -eq $baseline) { $baseline = $result }
        if (($result.Files -ne $baseline.Files) -or ($result.Bytes -ne $baseline.Bytes) -or ($result.Matches -ne $baseline.Matches)) {
            throw "Inconsistent results for $workerCount workers, run $i"
        }
        $result | Add-Member -NotePropertyName Run -NotePropertyValue $i
        $rows.Add($result)
        Write-Host ("workers={0} run={1} elapsed_ms={2} MiB/s={3} read_us={4} match_us={5} sink_us={6} buffer_allocs={7}" -f $workerCount, $i, $result.ElapsedMs, $result.MiBPerSecond, $result.FileReadWorkerUs, $result.MatchingWorkerUs, $result.SinkDispatchUs, $result.BufferAllocations)
    }
}
$rows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
$rows | Group-Object Workers | ForEach-Object {
    $values = @($_.Group | Sort-Object ElapsedMs | Select-Object -ExpandProperty ElapsedMs)
    $count = $values.Count
    $median = if ($count % 2 -eq 0) { ($values[([int]($count / 2) - 1)] + $values[[int]($count / 2)]) / 2.0 } else { $values[[int][math]::Floor($count / 2)] }
    [pscustomobject]@{ Workers = [int]$_.Name; MedianMs = $median; Runs = $count }
} | Sort-Object Workers | Format-Table -AutoSize
Write-Host "CSV: $CsvPath"
