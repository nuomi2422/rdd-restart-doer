# verify-batch.ps1 -- one row per 2026-11-05 change: did the log show it (and did it drop)?
#
# Why: nine fixes were written in one stretch; eyeballing them one at a time is how 'fixed' and
# 'not observed' get confused. Each row prints OBSERVED / NOT OBSERVED / NO DATA, never 'PASS'.
#
# ASCII only (PowerShell 5.1 reads UTF-8 without BOM as GBK).
#
# Usage:
#   powershell -NoProfile -File scripts/verify-batch.ps1
#   powershell -NoProfile -File scripts/verify-batch.ps1 -Since 2026-11-05T07:30

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [string]$Since = ''
)

$ErrorActionPreference = 'Stop'
$mon = Join-Path $GameDir 'config/numen/monitor'
if (-not (Test-Path $mon)) { Write-Output ('no monitor dir: ' + $mon); exit 0 }
if (-not $Since) { $Since = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('yyyy-MM-ddTHH:mm') }

function Read-All([string]$cur, [string]$pat) {
    $lines = @()
    $p = Join-Path $mon $cur
    if (Test-Path $p) { $lines += @(Get-Content $p -Encoding UTF8) }
    Get-ChildItem $mon -Filter $pat -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
        $lines += @(Get-Content $_.FullName -Encoding UTF8)
    }
    return $lines
}

$rdd = Read-All 'rdd.jsonl' 'rdd-*.jsonl'
$ctx = Read-All 'context.jsonl' 'context-*.jsonl'

$stalled = 0; $sleepDefers = 0
foreach ($l in $rdd) {
    if (-not $l.Trim()) { continue }
    try { $o = $l | ConvertFrom-Json } catch { continue }
    if (([string]$o.timestamp) -lt $Since) { continue }
    if ($o.type -eq 'situation_event' -and $o.data.kind -eq 'stalled') { $stalled++ }
    if ($o.type -eq 'side_task_deferred' -and $o.data.typeId -eq 'sleep' -and $o.data.reason -eq 'mid_operation') { $sleepDefers++ }
}

# tool-message text is only searchable through the conversation journal
$texts = @()
foreach ($l in $ctx) {
    if ($l -notmatch '"llm_request"') { continue }
    try { $o = $l | ConvertFrom-Json } catch { continue }
    if (([string]$o.timestamp) -lt $Since) { continue }
    foreach ($m in @($o.data.request.messages)) {
        if ($m.role -ne 'tool') { continue }
        if ($m.content -is [string]) { $texts += $m.content }
    }
}

function Seen([string]$needle) {
    foreach ($t in $texts) { if ($t.Contains($needle)) { return $true } }
    return $false
}

Write-Output ('window since ' + $Since + ' UTC; tool messages=' + $texts.Count)
Write-Output ('1 goto block+coords rejection      : ' + $(if (Seen 'block means') { 'STILL PRESENT' } else { 'none in window' }))
Write-Output ('2 interact "stand at" hint         : ' + $(if (Seen 'Nearest spot that can see it') { 'OBSERVED' } else { 'NOT OBSERVED' }))
Write-Output ('3 sleep "nearest bed is at"         : ' + $(if (Seen 'The nearest bed is at') { 'OBSERVED' } else { 'NOT OBSERVED' }))
Write-Output ('4 container stale="true" attr       : ' + $(if (Seen 'stale="true"') { 'OBSERVED' } else { 'NOT OBSERVED' }))
Write-Output ('8 find_tools family hint            : ' + $(if (Seen ([string]::new([char[]]@(0x73b0,0x6709,0x5de5,0x5177,0x65cf)))) { 'OBSERVED' } else { 'NOT OBSERVED' }))
Write-Output ('9 decline retry hint                : ' + $(if (Seen 'call decline_side again without') { 'OBSERVED' } else { 'NOT OBSERVED' }))
Write-Output ('6 sleep/mid_operation defers        : ' + $sleepDefers + '   (before fix: 11 per 50s when busy at night)')
Write-Output ('7 stalled events                    : ' + $stalled + '   (0 while idle; >0 expected only with active work)')
