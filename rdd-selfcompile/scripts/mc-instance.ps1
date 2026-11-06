# mc-instance.ps1 — 同伴实例的"进程身份"单一真源
#
# 为什么存在（2026-09-30 实坑）：
#   调用方为了停掉旧实例，自己手写 `Where-Object { $_.CommandLine -like "*instances\test*" }`，
#   然后又用 `-Instance gpt` 启动 → **检查 test、启动 gpt**。
#   结果：gpt 已经在跑时命令仍去"启动 gpt"，launch-mc 的等待链（PID→端口→世界加载）
#   一直跑，表现为"游戏明明开着，命令还在跑很久"。
#
# 本模块把"这个实例的游戏进程长什么样"收成一处：
#   调用方只说实例名（gpt / test），不再自己拼路径或匹配字符串。
#   路径由 config.ps1 按 $Instance 解析，**检查与启动必然同源**。

# 该实例对应的游戏目录（gpt/test 各自的；不传实例时用默认 gpt）
. (Join-Path $PSScriptRoot 'mc-identity.ps1')

function Get-RddMcGameDir {
    param([string]$Instance)
    $env:RDD_SELF_COMPILE_INSTANCE = if ([string]::IsNullOrWhiteSpace($Instance)) { 'gpt' } else { $Instance }
    . (Join-Path $PSScriptRoot 'config.ps1')
    return $global:RDD_SC.MC_GAME_DIR
}

# 该实例是否已在运行（只认 java/javaw，且排除 soul-core-bridge 这类
# 命令行里也含存档目录的**非游戏**进程 —— 之前踩过：WineFox 因此永远被误报成"已在跑"）
function Get-RddMcProcess {
    param([string]$Instance)
    $dir = Get-RddMcGameDir $Instance
    if ([string]::IsNullOrWhiteSpace($dir)) { return @() }
    # 042 R0: identity is decided by mc-identity.ps1 only -- this function and
    # Get-RddMcState must never use two different matching algorithms.
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
    return @($procs | Where-Object { $_.CommandLine -and ((Get-RddMcCommandLineMatch $_.CommandLine $dir) -eq 'MATCH') })
}

function Get-RddMcState {
    param([string]$Instance)
    # 042 R0: only a SUCCESSFUL enumeration may yield STOPPED. Any query failure is UNKNOWN.
    try {
        $dir = Get-RddMcGameDir $Instance
    } catch {
        return 'UNKNOWN'
    }
    if ([string]::IsNullOrWhiteSpace($dir)) { return 'UNKNOWN' }

    # Step 1: is any java/javaw alive at all? Full enumeration, failure is NOT 'none alive'.
    $all = $null
    try { $all = @(Get-Process -ErrorAction Stop) } catch { return 'UNKNOWN' }
    $alive = @($all | Where-Object { Test-RddMcProcessName $_.ProcessName })
    if ($alive.Count -eq 0) { return 'STOPPED' }

    # Step 2: identifying which instance it is needs command lines; WMI is the only source.
    $procs = $null
    try { $procs = @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop) } catch { return 'UNKNOWN' }
    if ($procs.Count -eq 0) { return 'UNKNOWN' }   # Get-Process saw java, WMI did not: do not guess
    foreach ($p in $procs) { if (-not $p.CommandLine) { return 'UNKNOWN' } }

    # 042 R0: a process whose identity cannot be decided must not be read as "not ours".
    $matches = @($procs | ForEach-Object { Get-RddMcCommandLineMatch $_.CommandLine $dir })
    return (Get-RddMcStateFromMatches $matches)
}

# 兼容旧调用：只回答“确定在跑”
function Test-RddMcRunning {
    param([string]$Instance)
    return ((Get-RddMcState -Instance $Instance) -eq 'RUNNING')
}

function Invoke-RddExitAudit {
    # 2026-11-05：退游戏记账下沉到最底层停止函数；任何调用方（stop-rdd 或直接调本函数）都算一次退出。
    try { & node 'D:\rdd\harness\rdd-harness\bin\stage-card.js' exit } catch { }
    # 2026-11-06 user decision: no independent auditor; do not regenerate its lock.
}

function Stop-RddMcInstance {
    param([string]$Instance, [int]$TimeoutSec = 10)
    $state = Get-RddMcState -Instance $Instance
    if ($state -eq 'UNKNOWN') { return 'STOP_UNKNOWN: cannot verify target instance' }
    $procs = @(Get-RddMcProcess -Instance $Instance)
    if ($procs.Count -eq 0) { return "already down" }
    $ids = @($procs | ForEach-Object { $_.ProcessId })
    # 2026-11-03：原来直接 Stop-Process -Force = 硬杀，integrated server 来不及 save，
    # 实机出现"矿下 mine 11/11 回执，重启回旧位置/背包、计时器回退"的进度丢失。
    # 先请求窗口正常关闭（Minecraft 会保存世界再退出），超时才强制。
    $graceful = $false
    foreach ($id in $ids) {
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowHandle -ne 0) {
            $null = $proc.CloseMainWindow()
            $graceful = $true
        }
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-RddMcState -Instance $Instance) -eq 'STOPPED') {
            Invoke-RddExitAudit
            return ("{0} (pid {1})" -f ($(if ($graceful) { 'stopped-gracefully' } else { 'stopped' })), ($ids -join ','))
        }
        Start-Sleep -Milliseconds 500
    }
    # 窗口关不掉（无窗口/卡死）才硬杀；强制路径必须显式报告，不能再静默当正常退出。
    Stop-Process -Id $ids -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if ((Get-RddMcState -Instance $Instance) -eq 'STOPPED') { Invoke-RddExitAudit; return "stopped-forced (pid $($ids -join ','))" }
        Start-Sleep -Milliseconds 500
    }
    $final = Get-RddMcState -Instance $Instance
    return "STILL $final after ${TimeoutSec}s (pid $($ids -join ','))"
}

# 「确保它在跑」：已在跑就**直接返回**，绝不重复启动。
# 这是幂等的那一半 —— 光修检查路径不够，不幂等照样会重复启动。
function Ensure-RddMcRunning {
    param([string]$Instance, [string]$MutationId, [int]$AutoStopMinutes = 120)
    if (Test-RddMcRunning -Instance $Instance) {
        Write-Output "LAUNCH_SKIP_ALREADY_RUNNING ($Instance)"
        return $false
    }
    # 2026-09-30 修（连坑三次「游戏起不来」的真根因）：
    # 原来是 `$args = @('-Instance', $Instance, '-AutoStopMinutes', [string]$AutoStopMinutes)`
    # 然后 `& launch-mc.ps1 @args`。
    #
    # 两个错叠在一起：
    #  ① `$args` 是 PowerShell 函数内的**保留自动变量**，赋值不会让它变成普通变量；
    #  ② 更要命的是 **数组 splat（`@(...)`）是按位置传参的，不是按名字**。
    #     于是 `('-Instance','gpt','-AutoStopMinutes','40')` 被当成 4 个位置实参，
    #     绑定成 Instance='-Instance'、AutoStopMinutes='gpt'
    #     → ParameterArgumentTransformationError: 无法将"gpt"转换为 System.Int32。
    # 结果 launch-mc.ps1 收不到参数、**游戏从来没被启动过**，
    # 外面看只是"java 进程一直是 0"，极易误判成内存不足 / OOM（本轮就被这样带偏过）。
    #
    # 正确写法：**哈希表 splat** 才是按名字传参。
    $launchParams = @{ Instance = $Instance; AutoStopMinutes = $AutoStopMinutes }
    if ($MutationId) { $launchParams['MutationId'] = $MutationId }
    & (Join-Path $PSScriptRoot 'launch-mc.ps1') @launchParams
    return $true
}
