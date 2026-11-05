# archive-monitor.ps1 -- copy the monitor journal somewhere rotation cannot eat it.
#
# Why: RddMonitor rotates rdd.jsonl at 16 MB and keeps only 5 archives. One evening of test
# runs already used 76% of that window, so the evidence we cite in reports (e.g. the
# condition_evaluated lines) would be rotated away long before anyone reads the report.
# This copies the current journal into monitor/evidence with a timestamp, outside the
# rotation prefix, so it is not deleted by the rdd-*.jsonl cleanup.
#
# ASCII only: PowerShell 5.1 reads UTF-8 without BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts\archive-monitor.ps1
#   powershell -NoProfile -File scripts\archive-monitor.ps1 -GameDir "D:/rdd/mc/Some Instance" -Keep 20

param(
    [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
    [int]$Keep = 20
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $GameDir 'config/numen/monitor/rdd.jsonl'
if (-not (Test-Path $src)) { Write-Output "no journal: $src"; exit 0 }

$dir = Join-Path $GameDir 'config/numen/monitor/evidence'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$dst = Join-Path $dir ("evidence-rdd-" + $stamp + ".jsonl")
Copy-Item $src $dst -Force

$bytes = (Get-Item $dst).Length
$lines = (Get-Content $dst -Encoding UTF8 | Measure-Object -Line).Lines
Write-Output ("archived=" + $dst)
Write-Output ("bytes=" + $bytes + " lines=" + $lines)

# keep newest N evidence files
$old = Get-ChildItem $dir -Filter 'evidence-rdd-*.jsonl' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep
foreach ($f in $old) { Remove-Item $f.FullName -Force }
if ($old) { Write-Output ("pruned=" + $old.Count) }
