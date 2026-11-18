# 启动 Minecraft 并进入 gpt 存档
param(
    [string]$MutationId,
    [ValidateSet('test','gpt')][string]$Instance = $env:RDD_SELF_COMPILE_INSTANCE,
    # 默认 120（2 小时）—— 2026-10-02 用户定：「不要再加什么十分钟的检测，默认一律 2 小时」。
    # 旧的「用户在场 <=10 分钟/次」铁律作废；自动关只为防空转耗电，不是门禁。
    [int]$AutoStopMinutes = 120,
    [string]$Mode
)

# 2026-09-30 用户指示：默认 gpt（原来两处 fallback 都是 test，导致"默认跑错存档"）。
# ⚠️ 这里必须与 config.ps1 的 Select-RddSelfCompileInstance 保持一致 ——
#    两处不一致时本行会先把 env 写成 test，config 再读到非空 env 就跟着用 test，
#    改一处不改另一处 = 没改。
# 2026-11-11: bounded title-only test process, not a world or legacy launch.
if ((($Mode -ceq 'isolated-title' -and $Instance -ceq 'test') -or ($Mode -ceq 'original-title' -and $Instance -ceq 'gpt')) -and $PSBoundParameters.ContainsKey('Instance') -and -not $MutationId -and -not $PSBoundParameters.ContainsKey('AutoStopMinutes') -and $args.Count -eq 0) {
    $ErrorActionPreference='Stop'
    try {
        . "$PSScriptRoot\mc-identity.ps1"
        $root=if($Mode -ceq 'original-title'){'D:/rdd/mc/The Best of Twilight Forest'}else{'D:/rdd/workspace/rdd-selfcompile/instances/test'}
        $p=$root
        while($p){$item=Get-Item -LiteralPath $p -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'linked test root'};$p=Split-Path $p -Parent}
        # 2026-11-11: copied old live world explicitly permitted; title launch itself still never quick-plays.
        foreach($save in @($(if($Mode -cne 'original-title'){Get-ChildItem (Join-Path $root 'saves') -Force}))){
            if(-not $save.PSIsContainer -or $save.Name -cne 'live' -or ($save.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'unexpected test save scope'}
        }
        $server=Get-Content (Join-Path $root 'config/numen/mcp_server.json') -Raw | ConvertFrom-Json
        $clients=Get-Content (Join-Path $root 'config/numen/mcp_clients.json') -Raw | ConvertFrom-Json
        if(($server.enabled -ne $false -and -not ($server.host -ceq '127.0.0.1' -and $server.port -in @(8765,8766) -and (($Mode -ceq 'original-title' -and -not [string]::IsNullOrWhiteSpace($server.token)) -or $server.token.Length -ge 32))) -or $clients.enabled -ne $false){throw 'external tool clients must be disabled'}
        $before=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
        foreach($p in $before){if((Get-RddMcCommandLineMatch $p.CommandLine $root) -ne 'NO_MATCH'){throw 'existing or unknown test process'}}
        $out=Join-Path $root ('logs/title-launch-'+[guid]::NewGuid().ToString('N')+'.stdout.txt')
        $err=$out+'.stderr.txt'
        $launcher=Start-Process -FilePath 'D:/rdd/tools/node/node.exe' -ArgumentList @('D:/rdd/tools/mc-launch.mjs','--instance',('"'+$root+'"'),'--title-only','--java','D:/rdd/tools/jdk21/jdk-21.0.11+10/bin/javaw.exe','--version','neoforge-21.1.233','--mem','4G') -WorkingDirectory $root -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
        $null=$launcher.Handle # retain process handle before short-lived node exits
        if(-not $launcher.WaitForExit(30000)){throw 'launcher timeout'}
        $launcher.Refresh()
        $nativeExit=$launcher.ExitCode
        if($null -eq $nativeExit -or $nativeExit -ne 0){throw ('launcher exit '+$nativeExit+'; '+$err)}
        $rows=@(Get-Content $out | Where-Object {$_ -match '^\{.*"pid".*\}$'})
        if($rows.Count -ne 1){throw 'missing unique launcher PID'}
        $receipt=$rows[0]|ConvertFrom-Json
        if(-not $receipt.ok -or -not $receipt.pid){throw 'invalid launcher PID'}
        $java=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$receipt.pid) -ErrorAction Stop
        if(-not $java -or $java.Name -notin @('java.exe','javaw.exe') -or (Get-RddMcCommandLineMatch $java.CommandLine $root) -ne 'MATCH' -or $java.CommandLine -match 'quickPlay|--server|--world'){throw 'new Java identity unknown'}
        if(@($before|Where-Object {$_.ProcessId -eq $java.ProcessId}).Count){throw 'PID was already present'}
        $result=@{status='STARTED_TEST_TITLE';titleVerified=$false;instance='test';root=$root;pid=$java.ProcessId;creationTime=$java.CreationDate;gameDir=$root;launcherLog=$out;stderr=$err;gameLog=$receipt.log}
        $state=Join-Path $root 'logs/title-process.json'
        [IO.File]::WriteAllText($state,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        $result|ConvertTo-Json
        exit 0
    }catch{Write-Error ('TITLE_LAUNCH_FAILED: '+$_.Exception.Message);exit 2}
}
# All default/gpt/world launches remain frozen.
# 2026-11-11: one explicit, auditable bounded-live verification path (quick play into live).
# Default and every other mode still refuse; this is not a general launch release.
if ($Mode -cne 'bounded-live' -or $Instance -cne 'gpt') {
    Write-Output ("LAUNCH_REFUSED: incident-freeze: launch disabled pending commander batch")
    exit 2
}
Write-Output ("BOUNDED_LIVE: single-run stage-guard verification mode=$Mode instance=$Instance quickPlay=live")

$env:RDD_SELF_COMPILE_INSTANCE = if ($Instance) { $Instance } else { 'gpt' }
. "$PSScriptRoot\config.ps1"

# STAGE_CARD_BEGIN
# 2026-11-05: child output is redirected to launch logs, so print the existing card here.
# A successful print is output delivery only, not proof of reading or adoption.
$stageCard = Join-Path $PSScriptRoot "..\..\..\harness\rdd-harness\bin\stage-card.js"
try {
    if (-not (Test-Path -LiteralPath $stageCard)) { throw "stage-card script missing" }
    & node $stageCard enter
    if ($LASTEXITCODE -ne 0) { throw "stage-card exit=$LASTEXITCODE" }
} catch {
    Write-Warning ("STAGE_CARD_NOT_DELIVERED: " + $_.Exception.Message)
}
# STAGE_CARD_END

# 先检查是否已有游戏在跑
# 注意：server 目录名可能出现在非游戏进程里（如 WineFox soul-core-bridge 的
# --memory-root 就含 "The Best of Twilight Forest"），必须排除它们，否则永远误报
# "already running"，游戏永远拉不起来。
# 2026-09-30：判定收进 mc-instance.ps1（单一真源），并回显**实际检查的目录** ——
# 之前"检查 test 却启动 gpt"的错就是靠手写路径造成的，这里让路径只有一个来源。
$instanceDir = $global:RDD_SC.MC_GAME_DIR
. "$PSScriptRoot\mc-instance.ps1"
$state = Get-RddMcState -Instance $global:RDD_SC.SC_INSTANCE
Write-Output "LAUNCH_CHECK instance=$($global:RDD_SC.SC_INSTANCE) dir=$instanceDir state=$state"
if ($state -eq 'UNKNOWN') { Write-Output 'LAUNCH_REFUSED_UNKNOWN'; exit 6 }
if ($state -eq 'RUNNING') {
    $result = @{ success = $false; stage = "launch-mc"; error = "minecraft already running; refusing to start second instance" }
    if ($MutationId) {
        Write-ResultJson (Join-Path $global:RDD_SC.SC_MUTATIONS (Join-Path $MutationId "phase-launch.json")) $result
    }
    Write-Output "LAUNCH_SKIP_ALREADY_RUNNING"
    exit 2
}

# Pin this bounded launch to the approved 174 attempt08 deployment. The inventory
# digest is from 174-04bfe-post-install-verification.json (10 enabled JARs).
$approvedCommit = '04bfe4b245201683ae87165d67db70dac3423e56'
try {
    . "$PSScriptRoot\deploy-test-policy.ps1"  # Assert-RddOrdinaryPath; no deployment
    . "$PSScriptRoot\bounded-live-launch-policy.ps1"
    Assert-RddBoundedLiveLaunch -Instance $global:RDD_SC.SC_INSTANCE -GameDir $instanceDir `
        -Save $global:RDD_SC.MC_SAVE -LevelOverride $env:RDD_LEVEL -Batch $global:RDD_SC.MC_BAT `
        -ExpectedRoot 'D:/rdd/mc/The Best of Twilight Forest' `
        -BatchSha 'eb1f4a378cd78a76ff9a356db5eaeca3ebad7894a12b0bc017e1bd2a171a8494' `
        -ModsSha '8d7761d94e3ec03dd9516c80a57a8d8537c6c4b3eadd46169856ebbe36ae774a'
} catch {
    Write-Output ('LAUNCH_REFUSED: ' + $_.Exception.Message)
    exit 6
}
$env:RDD_LEVEL = $global:RDD_SC.MC_SAVE
Write-Output "LAUNCH_INPUTS_OK commit=$approvedCommit instance=$($global:RDD_SC.SC_INSTANCE) save=$env:RDD_LEVEL"

# 启动器 bat 以 `pause` 结尾（等人按键看"游戏已退出"），自动化下它会永远挂在
# cmd.exe 上不退出；若不重定向输出，它还会继承调用方的 stdout 管道 → 上层
# shell（AI 的 Bash 调用）永远等不到 EOF，表现为"游戏退了命令还卡着"。
# 修法：输出重定向到文件 + 隐藏控制台 + 记下 PID 供看门狗回收。
if (-not (Test-Path $global:RDD_SC.SC_MUTATIONS)) { New-Item -ItemType Directory -Path $global:RDD_SC.SC_MUTATIONS -Force | Out-Null }
$launchLog = Join-Path $global:RDD_SC.SC_MUTATIONS "launch-$($global:RDD_SC.SC_INSTANCE).log"
$launcher = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"' + $global:RDD_SC.MC_BAT + '"')) `
    -WorkingDirectory $global:RDD_SC.MC_GAME_DIR `
    -RedirectStandardOutput $launchLog `
    -RedirectStandardError "$launchLog.err" `
    -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3

# 2026-11-05: the launcher bat has its own guard (e.g. audit gate pending -> REFUSED).
# The old script printed LAUNCH_OK and wrote success=true without checking; now it waits
# up to 30s for "javaw exists" AND "latest.log advanced", otherwise NOT_STARTED + exit 7.
$launchStartedAt = Get-Date
$gameLog = Join-Path $global:RDD_SC.MC_GAME_DIR 'logs/latest.log'
$beforeLogTime = if (Test-Path $gameLog) { (Get-Item $gameLog).LastWriteTime } else { [datetime]::MinValue }
$launched = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $javaw = @(Get-Process javaw -ErrorAction SilentlyContinue).Count
    $logAdvanced = (Test-Path $gameLog) -and ((Get-Item $gameLog).LastWriteTime -gt $beforeLogTime)
    if ($javaw -gt 0 -and $logAdvanced) { $launched = $true; break }
}
if (-not $launched) {
    $errText = ''
    if (Test-Path "$launchLog.err") { $errText = (Get-Content "$launchLog.err" -Raw -ErrorAction SilentlyContinue) }
    Write-Output ("LAUNCH_NOT_STARTED after 30s; javaw=" + @(Get-Process javaw -ErrorAction SilentlyContinue).Count + " batErr=" + $errText.Trim())
    if ($MutationId) {
        $fail = @{ success = $false; stage = 'launch-mc'; state = 'NOT_STARTED'; instance = $global:RDD_SC.SC_INSTANCE
                   gameDir = $global:RDD_SC.MC_GAME_DIR; batErr = $errText.Trim(); checkedAt = (Get-Date).ToString('o') }
        Write-ResultJson (Join-Path $global:RDD_SC.SC_MUTATIONS (Join-Path $MutationId 'phase-launch.json')) $fail
    }
    exit 7
}

# 连带拉起看门狗：到点自动关闭游戏，防止 AI 崩溃/离线时空转耗电
$watchdog = $null
if ($AutoStopMinutes -gt 0) {
    $wdScript = Join-Path $PSScriptRoot 'mc-watchdog.ps1'
    $wdLog = Join-Path $global:RDD_SC.SC_MUTATIONS "watchdog-$($global:RDD_SC.SC_INSTANCE).log"
    $watchdog = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $wdScript + '"'),
        '-Instance', ($global:RDD_SC.SC_INSTANCE),
        '-GameDir', ('"' + $global:RDD_SC.MC_GAME_DIR + '"'),
        '-AutoStopMinutes', ([string]$AutoStopMinutes),
        '-LogPath', ('"' + $wdLog + '"'),
        '-LauncherPid', ([string]$launcher.Id)
    ) -RedirectStandardOutput "$wdLog.out" -RedirectStandardError "$wdLog.err" -WindowStyle Hidden -PassThru
}

$result = @{
    success = $true
    stage = "launch-mc"
    save = $global:RDD_SC.MC_SAVE
    instance = $global:RDD_SC.SC_INSTANCE
    gameDir = $global:RDD_SC.MC_GAME_DIR
    startedAt = (Get-Date).ToString("o")
    watchdog = if ($watchdog) { @{ pid = $watchdog.Id; autoStopMinutes = $AutoStopMinutes; log = (Join-Path $global:RDD_SC.SC_MUTATIONS "watchdog-$($global:RDD_SC.SC_INSTANCE).log") } } else { $null }
    launcher = @{ pid = $launcher.Id; log = $launchLog; errLog = "$launchLog.err"; note = "输出已重定向，脱离调用方管道；控制台已隐藏，游戏窗口照常显示" }
    note = "Minecraft launching into save '$($global:RDD_SC.MC_SAVE)'; wait for world load before MCP" + $(if ($watchdog) { "; auto-stop in ${AutoStopMinutes}min (watchdog pid $($watchdog.Id))" } else { "" })
    state = "LAUNCHED"
}
Write-Output "LAUNCH_OK"
# 只有带了 -MutationId 才写 phase-launch.json。
# 不带 MutationId 是"临时手动起一次"的常见用法，此时 Join-Path 会因空串抛
# ParameterBindingValidationException（刷一屏红字，还会盖住真正的错误）。
if ($MutationId) {
    Write-ResultJson (Join-Path $global:RDD_SC.SC_MUTATIONS (Join-Path $MutationId "phase-launch.json")) $result
}
exit 0
