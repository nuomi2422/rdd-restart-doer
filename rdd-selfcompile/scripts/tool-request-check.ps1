# tool-request-check.ps1 -- what tools the model ACTUALLY received, from the request journal.
#
# Why (2026-11-05): until today I judged whitelist changes by waiting for the AI to call a tool
# and then guessing. The context journal stores the full llm_request (data.request.tools), so the
# effect is directly observable: count them and diff against the executor whitelist.
#
# ASCII only (PowerShell 5.1 reads UTF-8 without BOM as GBK).
#
# Usage:
#   powershell -NoProfile -File scripts/tool-request-check.ps1
#   powershell -NoProfile -File scripts/tool-request-check.ps1 -Journal <path> -Top 20

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [string]$Journal = '',
    [int]$Top = 20
)

$ErrorActionPreference = 'Stop'
if (-not $Journal) { $Journal = Join-Path $GameDir 'config/numen/monitor/context.jsonl' }
if (-not (Test-Path $Journal)) { Write-Output ("no journal: " + $Journal); exit 0 }

$last = $null
Get-Content $Journal -Encoding UTF8 | ForEach-Object {
    $line = $_
    if ($line -notmatch '"type":"llm_request"') { return }
    try { $o = $line | ConvertFrom-Json } catch { return }
    $last = $o
}
if (-not $last) { Write-Output 'no llm_request yet'; exit 0 }

$tools = @($last.data.request.tools | ForEach-Object { $_.function.name })
Write-Output ("last llm_request at " + $last.timestamp + "  tools=" + $tools.Count)

$cfgPath = Join-Path $GameDir 'config/numen/tool-visibility.json'
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $wl = @($cfg.executor.tools)
    $inRequestNotWhitelist = @($tools | Where-Object { $wl -notcontains $_ })
    $inWhitelistNotRequest = @($wl | Where-Object { $tools -notcontains $_ })
    Write-Output ("whitelist=" + $wl.Count + "  not-in-whitelist-but-sent=" + $inRequestNotWhitelist.Count + "  whitelisted-but-missing=" + $inWhitelistNotRequest.Count)
    if ($inRequestNotWhitelist.Count -gt 0) {
        Write-Output '--- sent although not whitelisted (RESIDENT tools are expected here) ---'
        $inRequestNotWhitelist | Sort-Object | ForEach-Object { Write-Output ("  " + $_) }
    }
    if ($inWhitelistNotRequest.Count -gt 0) {
        Write-Output '--- whitelisted but NOT sent (config drift, or tool not registered) ---'
        $inWhitelistNotRequest | Sort-Object | ForEach-Object { Write-Output ("  " + $_) }
    }
}
Write-Output '--- tools in request (first N) ---'
$tools | Sort-Object | Select-Object -First $Top | ForEach-Object { Write-Output ("  " + $_) }
