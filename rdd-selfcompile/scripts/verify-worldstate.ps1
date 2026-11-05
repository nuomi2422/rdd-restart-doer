# verify-worldstate.ps1 -- exercise world_state through the real MCP entry, save raw receipts.
#
# Why (2026-11-05): R1 acceptance asks for on-the-wire evidence that the PUBLISHED schema works
# (read with topic, read without topic, changes without topic, containers by coordinate).
# Doing that by hand means quoting JSON through PowerShell (which mangles it) and then
# copying receipts out of the chat. This script calls scripts/mcp-call.js with @file payloads
# and writes every raw answer to disk, so the audit can read files instead of a narrative.
#
# ASCII only (PowerShell 5.1 reads UTF-8 without BOM as GBK).
#
# Usage (game running, MCP on 8765):
#   powershell -NoProfile -File scripts/verify-worldstate.ps1 -Companion RDD
#   powershell -NoProfile -File scripts/verify-worldstate.ps1 -Container block:359,67,686

param(
    [string]$Companion = 'RDD',
    [string]$Container = '',
    [string]$OutDir = 'D:/rdd/tmp/worldstate-verify'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mcp = Join-Path $here 'mcp-call.js'
if (-not (Test-Path $mcp)) { Write-Output ('missing mcp-call.js at ' + $mcp); exit 2 }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

$cases = [ordered]@{
  'read-environment'   = '{"action":"read","topic":"environment"}'
  'read-no-topic'      = '{"action":"read"}'
  'changes-no-topic'   = '{"action":"changes"}'
}
if ($Container) {
  $cases['containers'] = '{"action":"read","topic":"containers","container":"' + $Container + '"}'
  $cases['containers-bad'] = '{"action":"read","topic":"containers","container":"block:0,0,0"}'
}

foreach ($name in $cases.Keys) {
    $argFile = Join-Path $OutDir ($stamp + '-' + $name + '.args.json')
    $outFile = Join-Path $OutDir ($stamp + '-' + $name + '.out.json')
    [System.IO.File]::WriteAllText($argFile, $cases[$name], (New-Object System.Text.UTF8Encoding($false)))
    # MCP down must not abort the run: the receipt file with the error text IS the evidence.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & node $mcp 'world_state' $Companion ('@' + $argFile) 2>&1 | Out-String }
    catch { $out = 'EXCEPTION: ' + $_.Exception.Message }
    $ErrorActionPreference = $prev
    if (-not $out) { $out = '(no output)' }
    [System.IO.File]::WriteAllText($outFile, $out, (New-Object System.Text.UTF8Encoding($false)))
    $first = ($out.Trim() -replace '\s+', ' ')
    if ($first.Length -gt 200) { $first = $first.Substring(0, 200) }
    Write-Output ($name.PadRight(18) + ' -> ' + $first)
}
Write-Output ('receipts saved under ' + $OutDir)
