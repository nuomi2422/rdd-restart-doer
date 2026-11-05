# toggle-tool-visibility.ps1 -- add/remove one tool from an executor/external whitelist.
#
# Why (2026-11-05): world_state shipped, passed tests, was deployed -- and the companion
# never called it, because it was not in the executor whitelist. Toggling that list by hand
# is exactly the kind of edit that gets half-done; this makes it one command with a backup.
#
# ASCII only: PowerShell 5.1 reads UTF-8 without BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts/toggle-tool-visibility.ps1 -Tool world_state -Side executor -WhatIfOnly
#   powershell -NoProfile -File scripts/toggle-tool-visibility.ps1 -Tool world_state -Side executor -Add
#   powershell -NoProfile -File scripts/toggle-tool-visibility.ps1 -Tool world_state -Side executor -Remove

param(
    [Parameter(Mandatory=$true)][string]$Tool,
    [ValidateSet('executor','external')][string]$Side = 'executor',
    [switch]$Add,
    [switch]$Remove,
    [switch]$WhatIfOnly,
    [string]$Config = 'D:/rdd/mc/The Best of Twilight Forest/config/numen/tool-visibility.json'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Config)) { Write-Output ("missing config: " + $Config); exit 2 }
if (-not $Add -and -not $Remove) { $WhatIfOnly = $true }

$raw = [System.IO.File]::ReadAllText($Config, [System.Text.Encoding]::UTF8)
$cfg = $raw | ConvertFrom-Json
$list = @($cfg.$Side.tools)
$has = $list -contains $Tool
Write-Output ("side=" + $Side + " tool=" + $Tool + " present=" + $has + " count=" + $list.Count)

if ($WhatIfOnly) {
    if ($Add -and -not $has) { Write-Output "would ADD" }
    elseif ($Remove -and $has) { Write-Output "would REMOVE" }
    else { Write-Output "no change needed" }
    exit 0
}

if ($Add -and -not $has) { $list += $Tool }
elseif ($Remove -and $has) { $list = @($list | Where-Object { $_ -ne $Tool }) }
else { Write-Output "no change needed"; exit 0 }

$cfg.$Side.tools = $list
$backup = $Config + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item $Config $backup -Force
$json = $cfg | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($Config, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("updated; backup=" + $backup + " new count=" + $list.Count)
