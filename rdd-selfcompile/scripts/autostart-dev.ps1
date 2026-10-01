# =====================================================================
# autostart-dev.ps1  —  开发环境开机自启动（opencode / 浏览器 / 监测台）
# 用法：由 Startup 的 rdd-autostart.bat 调用，也可手动执行。
# 幂等：已在跑的不重复起（按端口/进程判断）。
#
# ★ 2026-10-01 用户批准：watchdog（every-10min-drive）改为【默认不启动】。
#   原因：它每 600s 往 opencode 窗口注入一段文字，会插进用户正在打的字里
#   （用户两次被它截断消息）。措辞已经改中性了，但它仍然打断输入 —— 打扰是硬伤。
#   要开就显式加 -WithWatchdog；不用改任何代码，取消勾选即可。
# =====================================================================
[CmdletBinding()]
param(
    [switch]$WithWatchdog,    # ★ 只有显式加这个才起 watchdog（2026-10-01 起默认不起）
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
# ★ 2026-10-01 起默认【不启动】。它会往 opencode 窗口注入文字、插进用户正在打的字里。
#    要开： autostart-dev.ps1 -WithWatchdog
try {
    if (-not $WithWatchdog) {
        Say "[watchdog] 默认不启动（2026-10-01 起；要开加 -WithWatchdog）"
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

# --- 3b. W 层浏览器（带 CDP 9223 的 Edge，GLM/Kimi 网页外脑的载体） ---
# 【2026-09-28 补】此前这里只起 AI Bridge 的 Chrome，唯独没起 W 层这个带调试端口的 Edge。
# 后果:w-brain-drive.js 连不上 9223 → GLM/Kimi 全部不可用 → 自动模式"没有多模型"。
# 但 [agents] 文档一直写着"自动模式用 W 层(GLM/Kimi)"，工具都在，只是载体从没被拉起。
# 幂等:按 9223 是否监听判断。
try {
    if ($NoBrowser) {
        Say "[w-layer] 按参数跳过"
    } elseif (Port-InUse 9223) {
        Say "[w-layer] CDP Edge(9223) 已在跑，跳过"
    } else {
        $wOpen = Join-Path $PSScriptRoot 'w-open-browser.ps1'
        if (-not (Test-Path -LiteralPath $wOpen)) {
            Say "[w-layer] 未找到 w-open-browser.ps1"
        } else {
            Start-Process -WindowStyle Hidden powershell -ArgumentList @(
                '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$wOpen`"",'-Port','9223')
            Say "[w-layer] 已启动 CDP Edge(9223)；首次需人工登录 GLM/Kimi，之后 profile 复用"
        }
    }
} catch { Say "[w-layer] 启动失败: $($_.Exception.Message)" }

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
