<#
    pet-launch.ps1 — 桌宠启动器（防重复 + 状态汇报）

    为什么单独一个 ps1：
      .bat 里写 PowerShell 的引号地狱很难维护，而且 .bat 内容必须纯 ASCII
      （cmd 遇到多字节字符会字节偏移错位、吃掉后续行首字符）。
      所以判断逻辑放这里，.bat 只做一行转发。

    用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File pet-launch.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File pet-launch.ps1 -Stop
      powershell -NoProfile -ExecutionPolicy Bypass -File pet-launch.ps1 -Size 260

    退出码：0 = 成功（已启动 或 本来就在跑）｜ 1 = 失败
#>
[CmdletBinding()]
param(
    [switch]$Stop,
    [int]$Size = 200
)

$ErrorActionPreference = 'Stop'

$PetScript = Join-Path $PSScriptRoot 'start-pet.ps1'
if (-not (Test-Path -LiteralPath $PetScript)) {
    Write-Host "[X] 桌宠脚本不见了：$PetScript" -ForegroundColor Red
    exit 1
}

function Get-PetProcess {
    <# 匹配所有正在跑 start-pet.ps1 的 powershell 进程（排除自己和父进程） #>
    $self = $PID
    $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$self" -ErrorAction SilentlyContinue).ParentProcessId
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $self -and
            $_.ProcessId -ne $parent -and
            $_.CommandLine -and
            $_.CommandLine -match 'start-pet\.ps1'
        }
}

$existing = @(Get-PetProcess)

# ── 停止模式 ────────────────────────────────────────────────
if ($Stop) {
    if ($existing.Count -eq 0) {
        Write-Host '桌宠本来就没在跑。' -ForegroundColor Yellow
        exit 0
    }
    foreach ($p in $existing) {
        Write-Host "  结束 pid=$($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 800
    $left = @(Get-PetProcess)
    if ($left.Count -eq 0) {
        Write-Host '[OK] 桌宠已关。' -ForegroundColor Green
        exit 0
    }
    Write-Host "[X] 还剩 $($left.Count) 个没关掉：$(($left.ProcessId) -join ',')" -ForegroundColor Red
    exit 1
}

# ── 启动模式 ────────────────────────────────────────────────
if ($existing.Count -gt 0) {
    # 已经在跑就别再起一个 —— 双击两次会叠出两只桌宠
    Write-Host '桌宠已在运行，不重复启动。' -ForegroundColor Yellow
    foreach ($p in $existing) { Write-Host "   pid=$($p.ProcessId)" }
    Write-Host ''
    Write-Host '   点桌宠 = 看阶段/轮次/门禁    右键 = 换图/退出'
    Write-Host '   要关掉？运行 stop-stager-pet.bat'
    exit 0
}

$psExe = (Get-Process -Id $PID).Path
# ★ 关键：Start-Process -ArgumentList 不会给含空格的路径自动加引号。
#   "E:\restart developing doer\..." 会被从第一个空格处截断 -> 桌宠静默起不来。
#   所以这里手工把路径和所有可能含空格的参数包上引号。
$argLine = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Size {1}' -f $PetScript, $Size
Write-Host "  启动: $psExe $argLine"
$child = Start-Process -FilePath $psExe -ArgumentList $argLine -PassThru -WindowStyle Minimized

# WPF 起来要加载 9 张图 + 建窗，多给点时间
$ok = $false
foreach ($ms in @(800, 1200, 1500, 2000)) {
    Start-Sleep -Milliseconds $ms
    if (@(Get-PetProcess).Count -gt 0) { $ok = $true; break }
}
$check = @(Get-PetProcess)
if ($ok) {
    Write-Host "[OK] 桌宠已起  pid=$($check[0].ProcessId)  size=$Size" -ForegroundColor Green
    Write-Host '   点它看阶段/轮次/门禁，右键退出。'
    exit 0
}
Write-Host "[X] 起了但没检测到（child pid=$($child.Id) alive=$(-not $child.HasExited)）。" -ForegroundColor Red
if ($child.HasExited) { Write-Host "   子进程已退出，退出码 = $($child.ExitCode)" -ForegroundColor Red }
exit 1
