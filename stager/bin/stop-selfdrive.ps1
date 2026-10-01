# 关掉 every-10min-drive（自活注入看门狗）
# 它有「复活」特性：kill 掉的同时会由 autostart 拉起新的，所以要 kill 两次。
$ErrorActionPreference = 'SilentlyContinue'
$all = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"
$victims = $all | Where-Object {
  $_.CommandLine -and
  $_.CommandLine -match 'every-10min-drive' -and
  $_.CommandLine -match '\-File'
}
if (@($victims).Count -eq 0) { Write-Output 'ALREADY-OFF'; exit 0 }

Write-Output ("FOUND " + @($victims).Count)
foreach ($v in $victims) {
  Write-Output ("  kill " + $v.ProcessId)
  Stop-Process -Id $v.ProcessId -Force
}
Start-Sleep -Milliseconds 1200
# 第二轮：抓刚才复活的那几个
$again = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'every-10min-drive' -and $_.CommandLine -match '\-File' }
foreach ($v in $again) {
  Write-Output ("  kill(2nd) " + $v.ProcessId)
  Stop-Process -Id $v.ProcessId -Force
}
Start-Sleep -Milliseconds 1200
$left = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'every-10min-drive' -and $_.CommandLine -match '\-File' }
if (@($left).Count -eq 0) { Write-Output 'OFF-CONFIRMED' }
else { $left | ForEach-Object { Write-Output ("  STILL-ON " + $_.ProcessId) } }