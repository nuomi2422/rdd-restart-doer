# companion-calls.ps1 -- who called what, from monitor/tools.jsonl.
#
# Why (2026-11-05): twice in one night I read tool-call stats without splitting
# mcp-* (external monitoring) from the companion's own calls, and drew a wrong
# conclusion from it (a window change was reverted because of that). This script makes
# the split the default so it cannot be forgotten.
#
# ASCII only: PowerShell 5.1 reads UTF-8 without BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts/companion-calls.ps1
#   powershell -NoProfile -File scripts/companion-calls.ps1 -Since 2026-11-05T04:00 -Top 20
#   powershell -NoProfile -File scripts/companion-calls.ps1 -Tool world_state -Full

param(
    [string]$Journal = 'D:/rdd/mc/The Best of Twilight Forest/config/numen/monitor/tools.jsonl',
    [string]$Since = '',
    [string]$Tool = '',
    [int]$Top = 15,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Journal)) { Write-Output ("no journal: " + $Journal); exit 0 }

$companion = @{}
$mcp = @{}
$total = 0
$companionTotal = 0
$mcpTotal = 0
Get-Content $Journal -Encoding UTF8 | ForEach-Object {
    $line = $_
    if ($line -notmatch '"type":"tool_call"') { return }
    try { $o = $line | ConvertFrom-Json } catch { return }
    $ts = [string]$o.timestamp
    if ($Since -and ($ts -lt $Since)) { return }
    $name = [string]$o.data.tool
    if ($Tool -and ($name -ne $Tool)) { return }
    $total++
    $id = [string]$o.data.tool_call_id
    if ($id.StartsWith('mcp-')) {
        $mcpTotal++
        if (-not $mcp.ContainsKey($name)) { $mcp[$name] = 0 }
        $mcp[$name]++
    } else {
        $companionTotal++
        if (-not $companion.ContainsKey($name)) { $companion[$name] = 0 }
        $companion[$name]++
    }
}

Write-Output ("tool_call total=" + $total + "  companion=" + $companionTotal + "  mcp=" + $mcpTotal)
Write-Output ''
Write-Output "--- companion (non mcp-*) ---"
$companion.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object {
    Write-Output ("  {0,-30} {1}" -f $_.Key, $_.Value)
}
if ($Full) {
    Write-Output ''
    Write-Output "--- companion (all) ---"
    $companion.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        Write-Output ("  {0,-30} {1}" -f $_.Key, $_.Value)
    }
}
Write-Output ''
Write-Output "--- mcp (external) top ---"
$mcp.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object {
    Write-Output ("  {0,-30} {1}" -f $_.Key, $_.Value)
}
