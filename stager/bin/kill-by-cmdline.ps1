# 按命令行关键字找并杀掉进程（wmic 在新版 Windows 已移除，改用 CIM）
param([Parameter(Mandatory=$true)][string]$Match, [switch]$Quiet)
$ErrorActionPreference = 'SilentlyContinue'
$n = 0
$procs = Get-CimInstance Win32_Process
foreach ($p in $procs) {
  if (-not $p.CommandLine) { continue }
  if ($p.CommandLine -match $Match) {
    $n++
    if (-not $Quiet) { Write-Output ("  kill " + $p.ProcessId + "  " + $p.Name) }
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }
}
if (-not $Quiet -and $n -eq 0) { Write-Output '  (none matched)' }
exit 0