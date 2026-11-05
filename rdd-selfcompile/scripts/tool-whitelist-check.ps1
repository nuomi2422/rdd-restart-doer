# tool-whitelist-check.ps1 -- tools that exist in source vs the executor whitelist.
#
# Why (2026-11-05): world_state was implemented, tested, deployed -- and called ZERO times,
# because it was never added to the executor whitelist. The same happened on 2026-10-31 with
# experience_learn / experience_publish (a whole day of zero learning).
#
# ASCII only: PowerShell 5.1 reads UTF-8 without BOM as GBK; non-ASCII comments can break parsing.
#
# Usage:
#   powershell -NoProfile -File scripts/tool-whitelist-check.ps1 -WriteBaseline
#   powershell -NoProfile -File scripts/tool-whitelist-check.ps1 -MissingOnly

param(
    [string]$Repo = 'D:/rdd/workspace/minecraft-numen',
    [string]$Config = 'D:/rdd/mc/The Best of Twilight Forest/config/numen/tool-visibility.json',
    [string]$Baseline = 'D:/rdd/workspace/rdd-selfcompile/scripts/tool-baseline.txt',
    [switch]$WriteBaseline,
    [switch]$MissingOnly
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Config)) { Write-Output "no visibility config: $Config (executor sees ALL tools)"; exit 0 }

$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$executor = @($cfg.executor.tools)
$external = @($cfg.external.tools)

$pattern = 'name\(\)\s*\{\s*return\s+"([a-zA-Z0-9_]+)"'
$codeTools = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem $Repo -Recurse -Filter '*.java' | Where-Object { $_.FullName -notmatch '\\build\\' } | ForEach-Object {
    $text = Get-Content $_.FullName -Raw -Encoding UTF8
    if ($text -notmatch 'implements\s+NumenTool') { return }
    foreach ($m in [regex]::Matches($text, $pattern)) { [void]$codeTools.Add($m.Groups[1].Value) }
}

if ($WriteBaseline) {
    $dir = Split-Path $Baseline -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $codeTools | Sort-Object | Set-Content $Baseline -Encoding UTF8
    Write-Output ("baseline written: " + $Baseline + " (" + $codeTools.Count + " tools)")
    exit 0
}

if (Test-Path $Baseline) {
    $baseLines = @(Get-Content $Baseline -Encoding UTF8 | ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } | Where-Object { $_ -ne '' })
    $newOnes = @($codeTools | Where-Object { $baseLines -notcontains $_ } | Sort-Object)
    Write-Output ("new tools since baseline: " + $newOnes.Count)
    foreach ($t in $newOnes) {
        if ($executor -contains $t) { $state = 'in executor whitelist' }
        elseif ($external -contains $t) { $state = 'external only' }
        else { $state = 'NOT IN ANY WHITELIST' }
        Write-Output ("  " + $t + "  -> " + $state)
    }
}

$missing = @($codeTools | Where-Object { $executor -notcontains $_ } | Sort-Object)
Write-Output ("source tools=" + $codeTools.Count + " executor whitelist=" + $executor.Count + " not-in-whitelist=" + $missing.Count)
if (-not $MissingOnly) {
    Write-Output ''
    Write-Output '--- in source but NOT in executor whitelist (companion cannot call these) ---'
    $missing | ForEach-Object { Write-Output ("  " + $_) }
}
if ($missing.Count -gt 0) { exit 1 } else { exit 0 }
