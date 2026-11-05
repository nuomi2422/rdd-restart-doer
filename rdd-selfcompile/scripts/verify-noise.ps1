# verify-noise.ps1 -- check the two 2026-11-05 noise fixes from logs.
#
# A) progress:stalled must NOT be emitted while nothing is running (chain COMPLETED).
#    Before: 96 events, 88 at the same spot during idle.
# B) side_task_deferred for sleep/mid_operation must be rare (was 11 in 50 seconds).
#    Before: BUSY_RETRY_TICKS = 100 (5s); now 400 (20s).
#
# ASCII only (PowerShell 5.1 reads UTF-8 without BOM as GBK).
#
# Usage:
#   powershell -NoProfile -File scripts/verify-noise.ps1
#   powershell -NoProfile -File scripts/verify-noise.ps1 -Since 2026-11-05T06:30

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [string]$Since = ''
)

$ErrorActionPreference = 'Stop'
$mon = Join-Path $GameDir 'config/numen/monitor'
if (-not (Test-Path $mon)) { Write-Output ('no monitor dir: ' + $mon); exit 0 }
if (-not $Since) { $Since = (Get-Date).ToUniversalTime().AddMinutes(-60).ToString('yyyy-MM-ddTHH:mm') }
Write-Output ('window since ' + $Since + ' UTC (pass -Since in UTC to widen)')

$lines = @()
$cur = Join-Path $mon 'rdd.jsonl'
if (Test-Path $cur) { $lines += @(Get-Content $cur -Encoding UTF8) }
Get-ChildItem $mon -Filter 'rdd-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
    $lines += @(Get-Content $_.FullName -Encoding UTF8)
}

$stalled = 0
$completedStalled = 0
$sleepDefers = 0
foreach ($line in $lines) {
    if (-not $line.Trim()) { continue }
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if (([string]$o.timestamp) -lt $Since) { continue }
    if ($o.type -eq 'situation_event' -and $o.data.kind -eq 'stalled') {
        $stalled++
    }
    if ($o.type -eq 'side_task_deferred' -and $o.data.typeId -eq 'sleep') {
        if ([string]$o.data.reason -eq 'mid_operation') { $sleepDefers++ }
    }
}

Write-Output ('stalled events in window: ' + $stalled + '   (expected 0 while chain is COMPLETED; >0 only if work was active)')
Write-Output ('sleep/mid_operation defers in window: ' + $sleepDefers + '   (before fix: ~11 per 50 seconds)')
Write-Output ''
Write-Output 'For a real verdict also read primaryStatus from taskchain_snapshot in the same window.'
