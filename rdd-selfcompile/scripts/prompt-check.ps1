# prompt-check.ps1 -- what the model ACTUALLY saw: tools, skills and prompt blocks.
#
# Why (2026-11-05): both "is this tool available" and "is this skill visible" questions were
# answered by guessing (or by waiting for a call). The context journal stores the complete
# llm_request, so both lists can be read directly. This script prints them.
#
# ASCII only (PowerShell 5.1 reads UTF-8 without BOM as GBK).
#
# Usage:
#   powershell -NoProfile -File scripts/prompt-check.ps1
#   powershell -NoProfile -File scripts/prompt-check.ps1 -Journal <path> -Skills

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [string]$Journal = '',
    [switch]$Skills
)

$ErrorActionPreference = 'Stop'
if (-not $Journal) { $Journal = Join-Path $GameDir 'config/numen/monitor/context.jsonl' }
if (-not (Test-Path $Journal)) { Write-Output ("no journal: " + $Journal); exit 0 }

# 2026-11-05: context.jsonl rotates at 16 MB (context-<millis>.jsonl). Reading only the live
# file reports "no llm_request yet" right after a rotation -- the same one-file-myopia that
# already produced three wrong conclusions tonight. Merge the archives, keep the newest request.
$dir = Split-Path $Journal -Parent
$archives = @(Get-ChildItem $dir -Filter 'context-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
$lines = @()
$lines += @(Get-Content $Journal -Encoding UTF8)
foreach ($a in $archives) { $lines += @(Get-Content $a.FullName -Encoding UTF8) }

$last = $null
$lines | ForEach-Object {
    $line = $_
    if ($line -notmatch '"type":"llm_request"') { return }
    try { $o = $line | ConvertFrom-Json } catch { return }
    if (-not $last -or ([string]$o.timestamp) -gt ([string]$last.timestamp)) { $last = $o }
}
if (-not $last) { Write-Output 'no llm_request yet'; exit 0 }

$req = $last.data.request
$tools = @($req.tools)
$msgs = @($req.messages)
$sys = ($msgs | Where-Object { $_.role -eq 'system' } | ForEach-Object { $_.content }) -join "
"

Write-Output ("last llm_request at " + $last.timestamp + "  model=" + $req.model)
Write-Output ("messages=" + $msgs.Count + "  tools=" + $tools.Count + "  system_chars=" + $sys.Length)

foreach ($block in @('<env>', '<available_skills>', '<deferred_tools>', '<tools>', '<persona>')) {
    Write-Output ("  " + $block.PadRight(20) + $(if ($sys.Contains($block)) { 'present' } else { 'absent' }))
}

$skillNames = @()
foreach ($m in [regex]::Matches($sys, '<name>([^<]+)</name>')) { $skillNames += $m.Groups[1].Value }
Write-Output ("skills=" + $skillNames.Count)
if ($Skills -or $skillNames.Count -le 30) {
    $skillNames | Sort-Object | ForEach-Object { Write-Output ("  " + $_) }
}
