# =====================================================================
# autostart-dev.ps1  —  开发环境开机自启动（opencode / 浏览器 / 监测台 / watchdog）
# 用法：由 Startup 的 rdd-autostart.bat 调用，也可手动执行。
# 幂等：已在跑的不重复起（按端口/进程判断）。
# =====================================================================
[CmdletBinding()]
param(
    [switch]$NoWatchdog,      # 跳过 watchdog（默认起）
    [switch]$NoBrowser        # 跳过浏览器（默认起）
)

$ErrorActionPreference = 'Continue'
$log = 'E:\restart developing doer\rdd-selfcompile\scripts\autostart-dev.log'
function Say($m) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

Say "=== autostart 开始 ==="

# --- 0. 常量 ---
$Repo       = 'E:\restart developing doer\minecraft-numen'
$MonitorSrv = 'E:\restart developing doer\rdd-monitor-publish-20260913\monitoring-station\server.mjs'
$MonitorDir = 'E:\.minecraft\versions\The Best of Twilight Forest\config\numen\monitor'
$Watchdog   = 'E:\restart developing doer\rdd-selfcompile\scripts\every-10min-drive.ps1'
$Chrome     = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$ChromeProf = 'C:\Users\lenovo\.config\ai-bridge\chrome-profile'
$OpencodeExe = 'D:\nodejs\cache\_npx\e2094862b59aac7b\node_modules\opencode-ai\bin\opencode.exe'

function Port-InUse([int]$p) {
    return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

# --- 1. 监测台 (8776) ---
try {
    if (Port-InUse 8776) {
        Say "[monitor] 8776 已在监听，跳过"
    } else {
        $env:NUMEN_MONITOR_DIR = $MonitorDir
        Start-Process -FilePath 'node' -ArgumentList "`"$MonitorSrv`"" -WorkingDirectory (Split-Path $MonitorSrv) -WindowStyle Minimized
        Say "[monitor] 已启动 node server.mjs (8776), dir=$MonitorDir"
    }
} catch { Say "[monitor] 启动失败: $($_.Exception.Message)" }

# --- 2. watchdog (every-10min-drive -Loop) ---
try {
    if ($NoWatchdog) {
        Say "[watchdog] 按参数跳过"
    } else {
        $exists = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                  Where-Object { $_.CommandLine -match 'every-10min-drive' }
        if ($exists) {
            Say "[watchdog] 已在跑 (pid $($exists.ProcessId -join ','))，跳过"
        } else {
            Start-Process -WindowStyle Hidden powershell -ArgumentList @(
                '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$Watchdog`"",'-Loop','-IntervalSec','600')
            Say "[watchdog] 已启动 every-10min-drive -Loop -IntervalSec 600"
        }
    }
} catch { Say "[watchdog] 启动失败: $($_.Exception.Message)" }

# --- 3. 浏览器（AI Bridge 专用 Chrome profile；无自动化参数） ---
try {
    if ($NoBrowser) {
        Say "[browser] 按参数跳过"
    } elseif (-not (Test-Path -LiteralPath $Chrome)) {
        Say "[browser] 未找到 Chrome: $Chrome"
    } else {
        $running = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -match [regex]::Escape($ChromeProf) }
        if ($running) {
            Say "[browser] Chrome(ai-bridge profile) 已在跑，跳过"
        } else {
            New-Item -ItemType Directory -Force -Path $ChromeProf | Out-Null
            Start-Process -FilePath $Chrome -ArgumentList @("--user-data-dir=$ChromeProf", 'https://chatgpt.com/')
            Say "[browser] 已启动 AI Bridge Chrome (profile=$ChromeProf)"
        }
    }
} catch { Say "[browser] 启动失败: $($_.Exception.Message)" }

# --- 4. opencode 窗口（新控制台窗口，工作目录=仓库） ---
try {
    if (-not (Test-Path -LiteralPath $OpencodeExe)) {
        Say "[opencode] 未找到 exe: $OpencodeExe"
    } else {
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', "`"`"$OpencodeExe`"`"") -WorkingDirectory $Repo
        Say "[opencode] 已在新窗口启动 opencode (dir=$Repo)"
    }
} catch { Say "[opencode] 启动失败: $($_.Exception.Message)" }

Say "=== autostart 完成 ==="
