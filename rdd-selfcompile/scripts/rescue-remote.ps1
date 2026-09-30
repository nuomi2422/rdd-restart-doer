# rescue-remote.ps1 -- Remote-access memory rescue switch.
# Goal: free RAM on this low-RAM box so the user (joining remotely from school) can connect.
# ASCII-only (PS5.1). Default = REPORT ONLY. Use -Apply to actually kill; -CloseBrowsers also closes msedge.
# Never touches OpenCode itself (killing it would kill the agent).
param(
  [switch]$Apply,
  [switch]$CloseBrowsers
)
function MemInfo {
  $os = Get-CimInstance Win32_OperatingSystem
  $total = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
  $free = [math]::Round($os.FreePhysicalMemory/1MB,1)
  "PHYS total=${total}GB free=${free}GB"
}
Write-Output (MemInfo)
Write-Output "--- top memory consumers ---"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 12 @{n='MB';e={[int]($_.WorkingSet64/1MB)}},ProcessName | Format-Table -AutoSize

# Targets (by process name), excluding OpenCode:
#   java/javaw with game dir  -> Minecraft (modpack)
#   msedgewebview2            -> ChatGPT desktop / Edge WebView helpers
#   msedge                    -> Edge browser (only with -CloseBrowsers)
$killed = @()
if ($Apply) {
  # 1) Minecraft (modpack) java
  $mc = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object { $_.CommandLine -like '*The Best of Twilight Forest*' -and $_.CommandLine -notlike '*soul-core-bridge*' }
  foreach ($p in $mc) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; $killed += "MC-java:$($p.ProcessId)" }
  # 2) msedgewebview2 (WebView helpers)
  Get-Process msedgewebview2 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; $killed += "webview:$($_.Id)" }
  # 3) browsers (opt-in)
  if ($CloseBrowsers) {
    Get-Process msedge -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; $killed += "msedge:$($_.Id)" }
  }
  Start-Sleep -Seconds 4
  Write-Output ("KILLED: " + ($killed -join ", "))
  Write-Output (MemInfo)
} else {
  Write-Output ""
  Write-Output "REPORT ONLY. To free memory run:  powershell -File rescue-remote.ps1 -Apply [-CloseBrowsers]"
  Write-Output "Targets: Minecraft(modpack java) + msedgewebview2 [ + msedge with -CloseBrowsers ]. OpenCode is never touched."
}
