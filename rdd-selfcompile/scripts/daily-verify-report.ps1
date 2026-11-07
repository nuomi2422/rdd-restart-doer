param(
  [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
  [string]$Jar = 'D:/rdd/mc/The Best of Twilight Forest/mods/numen-plugin-rdd-1.21.1-0.1.3-dev.jar'
)
$ErrorActionPreference = 'Stop'
$log = Get-ChildItem (Join-Path $GameDir 'logs') -Filter 'rdd-launch*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$mon = Join-Path $GameDir 'config/numen/monitor/rdd.jsonl'
Write-Output ('jar=' + (Get-FileHash $Jar -Algorithm SHA256).Hash.Substring(0,16))
if ($log) {
  Write-Output ('launch=' + $log.Name)
  Get-Content $log.FullName -Encoding UTF8 | Select-String -Pattern 'daily spec register|recurring create|daily evaluate|All dimensions are saved|stale embedded' | Select-Object -Last 20 | ForEach-Object { $_.Line }
}
if (Test-Path $mon) {
  Write-Output '--- side_task events (last 24h) ---'
  Select-String -Path $mon -Pattern 'side_task_(due|created|activated|skipped|completed|cancelled|resumed_mainline)' | Select-Object -Last 20 | ForEach-Object { $_.Line }
}
