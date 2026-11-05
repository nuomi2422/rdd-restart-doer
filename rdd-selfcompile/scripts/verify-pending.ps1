# verify-pending.ps1 -- turn the A-list of 进游戏验证/004 into an automatic verdict.
#
# Why (2026-11-05): after every run the same questions are asked by hand -- did the companion
# finally call world_state / learner_note, did condition_evaluated stop being all-MATCHED.
# Those are pure log queries, so they can be answered by a script instead of by memory.
#
# ASCII only (PowerShell 5.1 reads UTF-8 without BOM as GBK).
#
# Usage:
#   powershell -NoProfile -File scripts/verify-pending.ps1
#   powershell -NoProfile -File scripts/verify-pending.ps1 -Since 2026-11-05T05:00

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [string]$Since = ''
)

$ErrorActionPreference = 'Stop'
$mon = Join-Path $GameDir 'config/numen/monitor'
if (-not (Test-Path $mon)) { Write-Output ("no monitor dir: " + $mon); exit 0 }
# journal timestamps are UTC (Z); compare in the same frame or every row looks "old".
if (-not $Since) { $Since = (Get-Date).ToUniversalTime().AddMinutes(-120).ToString('yyyy-MM-ddTHH:mm') }
Write-Output ("window since " + $Since + " UTC (pass -Since in UTC to widen)")

function Read-Journal([string]$pattern, [string]$current) {
    $lines = @()
    $cur = Join-Path $mon $current
    if (Test-Path $cur) { $lines += @(Get-Content $cur -Encoding UTF8) }
    Get-ChildItem $mon -Filter $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
        $lines += @(Get-Content $_.FullName -Encoding UTF8)
    }
    return $lines
}

$tools = Read-Journal 'tools-*.jsonl' 'tools.jsonl'
$rdd = Read-Journal 'rdd-*.jsonl' 'rdd.jsonl'

function Count-CompanionTool([string]$name) {
    $n = 0
    foreach ($line in $tools) {
        if ($line -notmatch '"type":"tool_call"') { continue }
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if ([string]$o.data.tool -ne $name) { continue }
        if (([string]$o.data.tool_call_id).StartsWith('mcp-')) { continue }
        if ($Since -and ([string]$o.timestamp -lt $Since)) { continue }
        $n++
    }
    return $n
}

$ws = Count-CompanionTool 'world_state'
$ln = Count-CompanionTool 'learner_note'
Write-Output ('A1 world_state  companion calls=' + $ws + '  -> ' + $(if ($ws -gt 0) { 'PASS' } else { 'NOT OBSERVED' }))
Write-Output ('A2 learner_note companion calls=' + $ln + '  -> ' + $(if ($ln -gt 0) { 'PASS' } else { 'NOT OBSERVED' }))

$verdicts = @{}
foreach ($line in $rdd) {
    if ($line -notmatch '"condition_evaluated"') { continue }
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($Since -and ([string]$o.timestamp -lt $Since)) { continue }
    $v = [string]$o.data.verdict
    if (-not $verdicts.ContainsKey($v)) { $verdicts[$v] = 0 }
    $verdicts[$v]++
}
$parts = @()
foreach ($k in $verdicts.Keys) { $parts += ($k + '=' + $verdicts[$k]) }
$nonMatched = 0
foreach ($k in $verdicts.Keys) { if ($k -ne 'MATCHED') { $nonMatched += $verdicts[$k] } }
Write-Output ('A4 condition verdicts: ' + ($parts -join ', ') + '  -> ' + $(if ($verdicts.Count -eq 0) { 'NO DATA' } elseif ($nonMatched -gt 0) { 'PASS (has non-MATCHED)' } else { 'STILL ALL MATCHED' }))
