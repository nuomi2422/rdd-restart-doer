# presence-watchdog.ps1 -- Close Minecraft when the user goes silent (treated as offline).
# Rule (user 2026-10-02): default 120 (2 hours). The old 10-minute check is cancelled;
# MC is allowed to run its full 2-hour session even if the user is quiet.
# The agent refreshes presence-last-user.txt on every real user message. This watcher only frees RAM.
# ASCII-only (PS5.1).
# Usage: powershell -File presence-watchdog.ps1 [-StaleMinutes 120] [-IntervalSeconds 60] [-Loop] [-DryRun]
param(
  [int]$StaleMinutes = 120,
  [int]$IntervalSeconds = 60,
  [switch]$Loop,
  [switch]$DryRun
)
$ErrorActionPreference = 'Continue'
$Base = 'E:\restart developing doer\rdd-selfcompile\scripts'
$Presence = Join-Path $Base 'presence-last-user.txt'
$Log = Join-Path $Base 'presence-watchdog.log'
function Log($m) { $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"; Add-Content -LiteralPath $Log -Value $line -Encoding UTF8; Write-Output $line }
function CloseMc() {
  $mc = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object { $_.CommandLine -like '*The Best of Twilight Forest*' -and $_.CommandLine -notlike '*soul-core-bridge*' }
  foreach ($p in $mc) { try { (Get-Process -Id $p.ProcessId).CloseMainWindow() | Out-Null } catch {} }
  Start-Sleep -Seconds 20
  $still = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object { $_.CommandLine -like '*The Best of Twilight Forest*' -and $_.CommandLine -notlike '*soul-core-bridge*' }
  foreach ($p in $still) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
  return (@($mc).Count)
}
function CheckOnce() {
  if (-not (Test-Path -LiteralPath $Presence)) { Log "no presence file; skip"; return }
  $ts = $null
  try { $ts = [datetime]::Parse((Get-Content -LiteralPath $Presence -Raw).Trim()) } catch { Log "bad presence ts; skip"; return }
  $age = ((Get-Date) - $ts).TotalMinutes
  $mcRun = @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object { $_.CommandLine -like '*The Best of Twilight Forest*' -and $_.CommandLine -notlike '*soul-core-bridge*' }).Count
  if ($age -ge $StaleMinutes) {
    if ($mcRun -gt 0) { if ($DryRun) { Log ("stale {0:N1}min, MC running -> WOULD close (dryrun)" -f $age) } else { $n = CloseMc; Log ("stale {0:N1}min -> closed MC ({1})" -f $age, $n) } }
    else { Log ("stale {0:N1}min, MC not running" -f $age) }
  } else {
    Log ("user fresh ({0:N1}min); MC running={1}" -f $age, $mcRun)
  }
}
Log "START presence-watchdog stale=${StaleMinutes}min interval=${IntervalSeconds}s loop=$Loop"
if ($Loop) { while ($true) { try { CheckOnce } catch { Log ("ERR " + $_.Exception.Message) }; Start-Sleep -Seconds $IntervalSeconds } }
else { CheckOnce }
Log "STOP presence-watchdog"
