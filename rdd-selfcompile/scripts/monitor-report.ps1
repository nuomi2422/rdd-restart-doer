# monitor-report.ps1 -- size and content summary of config/numen/monitor/rdd.jsonl
#
# Why: a single 12-minute test run produced ~10 MB of monitor events, and the one line that
# matters (condition_evaluated) was buried. This prints bytes-per-type so "is the monitor
# healthy?" is answerable without opening a 10 MB file in an editor.
#
# ASCII only: PowerShell 5.1 reads UTF-8 without BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts\monitor-report.ps1
#   powershell -NoProfile -File scripts\monitor-report.ps1 -GameDir "D:/rdd/mc/Some Instance"

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [string]$Type = 'condition_evaluated'
)

$ErrorActionPreference = 'Stop'
$file = Join-Path $GameDir 'config/numen/monitor/rdd.jsonl'
if (-not (Test-Path $file)) { Write-Output "no monitor file: $file"; exit 0 }

$total = (Get-Item $file).Length
$stats = @{}
$matched = @()
Get-Content $file -Encoding UTF8 | ForEach-Object {
    $line = $_
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    try { $o = $line | ConvertFrom-Json } catch { return }
    $t = if ($o.type) { [string]$o.type } else { '?' }
    if (-not $stats.ContainsKey($t)) { $stats[$t] = @{ n = 0; bytes = 0 } }
    $stats[$t].n++
    $stats[$t].bytes += $line.Length
    if ($t -eq $Type) { $matched += $o }
}

Write-Output ("file=" + $file)
Write-Output ("bytes=" + $total + " lines=" + (($stats.Values | ForEach-Object { $_.n } | Measure-Object -Sum).Sum))
Write-Output ''
Write-Output 'type                             count      bytes   bytes/event'
$stats.GetEnumerator() | Sort-Object { $_.Value.bytes } -Descending | ForEach-Object {
    $avg = if ($_.Value.n -gt 0) { [int]($_.Value.bytes / $_.Value.n) } else { 0 }
    Write-Output (("{0,-30} {1,7} {2,10} {3,12}" -f $_.Key, $_.Value.n, $_.Value.bytes, $avg))
}

if ($matched.Count -gt 0) {
    Write-Output ''
    Write-Output ("--- " + $Type + " (" + $matched.Count + ") ---")
    $matched | Select-Object -Last 10 | ForEach-Object {
        Write-Output ([string]$_.timestamp + '  ' + [string]$_.data.verdict + '  ' + [string]$_.data.reason)
    }
}

# Rotation headroom: RddMonitor rotates at 16 MB and keeps 5 archives (~96 MB bounded).
$limit = 16 * 1024 * 1024
Write-Output ''
Write-Output ("rotation: " + [int]($total * 100 / $limit) + "% of 16 MB")
