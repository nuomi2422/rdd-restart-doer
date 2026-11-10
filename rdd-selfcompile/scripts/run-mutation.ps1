# Self-Compile 单轮闭环编排器
# 用法: .\scripts\run-mutation.ps1 [-Requirement "xxx"] [-SkipLaunch] [-SkipMcp]
param(
    [string]$Requirement = "示例：注册一个 selfcompile_probe 工具，只读返回同伴状态",
    # 默认 gpt（2026-09-30 用户指示；原来是 test，会让验证跑在错的存档上）
    [ValidateSet('test','gpt')][string]$Instance = 'gpt',
    [switch]$SkipLaunch,
    [switch]$SkipMcp,
    [string]$Module,
    [switch]$TestOnly,
    [string[]]$Tests = @(),
    [ValidateSet('test-only','full')][string]$Mode,
    [string]$SourceRoot,
    [string]$ExpectedCommit,
    [switch]$SettleRegression,
    [switch]$IdentityRegression,
    # 2026-10-02 用户定：默认 120（2 小时），旧的「10 分钟/次」限制作废。
    [int]$AutoStopMinutes = 120,
    # 采集 verify 要求的五件证据；不开则 verify 必然 UNVERIFIED。
    [switch]$CollectEvidence,
    [string]$EvidenceTool = "",
    # H4（2026-10-20 #087）：批次号，写进 deploy-ledger.jsonl。
    # 为什么要有它：sha 只说明「部署了哪份代码」，批次号才说明「这次部署属于哪个批次」，
    # 两者一起才能回答「G4a 的每次部署分别落在哪个 sha 上」。没传就留空，
    # deploy.ps1 会记 "-"（不许猜，猜出来的批次号比没有更坏）。
    [string]$BatchId = "",
    # 多轮模式（2026-10-20 用户要求）：本轮是第几轮 / 总共还要跑几轮。
    # -Rounds N 表示「本轮之后还要继续 N 轮」。每轮结束会打「该开审核了」的提示块，
    # 并把审核请求落盘到 report\review-requests\。不自动起子 agent（会绕开 goal/预算/权限），
    # 只做提示与记录，起不起由主 AI 决定。
    [int]$Round = 1,
    [int]$Rounds = 0
)

# Incident freeze: load the guard into an isolated module; functions must come from this file.
$guardPath = Join-Path $PSScriptRoot 'execution-guard.ps1'
if (-not (Test-Path -LiteralPath $guardPath -PathType Leaf)) { Write-Error 'RUN_REFUSED: guard-missing'; exit 2 }
try { $guardText = Get-Content -LiteralPath $guardPath -Raw -ErrorAction Stop } catch { Write-Error ("RUN_REFUSED: guard-load-failed: " + $_.Exception.Message); exit 2 }
if ([string]::IsNullOrWhiteSpace($guardText)) { Write-Error 'RUN_REFUSED: guard-empty'; exit 2 }
$parseTokens = $null; $parseErrors = $null
try { $guardAst = [System.Management.Automation.Language.Parser]::ParseInput($guardText, [ref]$parseTokens, [ref]$parseErrors) } catch { Write-Error ("RUN_REFUSED: guard-parse-failed: " + $_.Exception.Message); exit 2 }
if ($parseErrors -and $parseErrors.Count -gt 0) { Write-Error 'RUN_REFUSED: guard-parse-failed'; exit 2 }
$definedFunctions = @($guardAst.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } | ForEach-Object { $_.Name })
if ($definedFunctions -notcontains 'Resolve-RddRunMode' -or $definedFunctions -notcontains 'Test-RddTestSelection') { Write-Error 'RUN_REFUSED: guard-functions-missing'; exit 2 }
$guardModuleName = 'RddExecutionGuard_' + [guid]::NewGuid().ToString('N')
try {
    $guardModule = New-Module -Name $guardModuleName -ArgumentList $guardText -ScriptBlock {
        param($text)
        $ErrorActionPreference = 'Stop'
        . ([ScriptBlock]::Create($text))
        Export-ModuleMember -Function Resolve-RddRunMode, Test-RddTestSelection
    } -ErrorAction Stop
} catch { Write-Error ("RUN_REFUSED: guard-load-failed: " + $_.Exception.Message); exit 2 }
$resolveFn = $guardModule.ExportedFunctions['Resolve-RddRunMode']
$testFn = $guardModule.ExportedFunctions['Test-RddTestSelection']
if (-not $resolveFn -or -not $testFn) { Write-Error 'RUN_REFUSED: guard-functions-missing'; exit 2 }
try { $modeInfo = & $resolveFn -Mode $Mode -TestOnly:$TestOnly } catch { Write-Error ("RUN_REFUSED: guard-call-failed: " + $_.Exception.Message); exit 2 }
if ($null -eq $modeInfo -or $null -eq $modeInfo.ok -or $modeInfo.ok -isnot [bool]) { Write-Error 'RUN_REFUSED: guard-invalid-result'; exit 2 }
if ($modeInfo.ok -ne $true) { Write-Error ("RUN_REFUSED: " + $modeInfo.reason); exit 2 }
$effectiveMode = [string]$modeInfo.mode
if ($effectiveMode -ne 'test-only') { Write-Error 'RUN_REFUSED: incident-freeze: only test-only supported'; exit 2 }
$TestOnly = $true

if ($SettleRegression -and $IdentityRegression) { Write-Error 'SettleRegression conflicts with IdentityRegression'; exit 2 }
if ($SettleRegression) {
    if (-not $TestOnly -or $Tests.Count -gt 0) { Write-Error 'SettleRegression requires TestOnly and conflicts with Tests'; exit 2 }
    if ([string]::IsNullOrWhiteSpace($Module)) { $Module = 'plugins:rdd' }
    $Tests = @('com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest', 'com.dwinovo.numen.plugins.rdd.RddSettleStageFlagsTest')
}
if ($IdentityRegression) {
    # -File cannot pass a comma list as one array element, so named suites stay explicit.
    if (-not $TestOnly -or $Tests.Count -gt 0) { Write-Error 'IdentityRegression requires TestOnly and conflicts with Tests'; exit 2 }
    if ([string]::IsNullOrWhiteSpace($Module)) { $Module = 'api:common' }
    $Tests = @('com.dwinovo.numen.api.ServerIdentitySnapshotTest', 'com.dwinovo.numen.monitor.WorldContextStampTest')
}
if ($TestOnly -and ($CollectEvidence -or $SkipLaunch -or $SkipMcp -or $Rounds -ne 0 -or -not [string]::IsNullOrWhiteSpace($EvidenceTool))) {
    Write-Error 'TestOnly cannot be combined with launch, MCP, evidence, or multi-round options'; exit 2
}
if ($effectiveMode -ne 'test-only' -and $Tests.Count -gt 0) { Write-Error 'RUN_REFUSED: tests require test-only mode'; exit 2 }
if ($effectiveMode -ne 'test-only' -and (-not [string]::IsNullOrWhiteSpace($SourceRoot) -or -not [string]::IsNullOrWhiteSpace($ExpectedCommit))) { Write-Error 'RUN_REFUSED: SourceRoot/ExpectedCommit are TestOnly-only'; exit 2 }
try { $testsInfo = & $testFn -Tests $Tests } catch { Write-Error ("RUN_REFUSED: guard-call-failed: " + $_.Exception.Message); exit 2 }
if ($null -eq $testsInfo -or $null -eq $testsInfo.ok -or $testsInfo.ok -isnot [bool]) { Write-Error 'RUN_REFUSED: guard-invalid-result'; exit 2 }
if (-not $testsInfo.ok) { Write-Error ("RUN_REFUSED: " + $testsInfo.reason); exit 2 }


# 2026-11-11 R11: a lone expected commit must never silently select the main tree.
$hasSourceRoot = -not [string]::IsNullOrWhiteSpace($SourceRoot)
$hasExpectedCommit = -not [string]::IsNullOrWhiteSpace($ExpectedCommit)
if ($hasSourceRoot -xor $hasExpectedCommit) { Write-Error 'RUN_REFUSED: SourceRoot and ExpectedCommit must be provided together'; exit 2 }

$env:RDD_SELF_COMPILE_INSTANCE = $Instance
# Test mode resolves the module from the fixed allowlist inside build-jar. The env
# var feeds the "group:name" build path, and config.ps1 resolves it at load time —
# a top-level module such as world-state-core would throw before any test runs.
if (-not $TestOnly -and -not [string]::IsNullOrWhiteSpace($Module)) { $env:RDD_SELF_COMPILE_MODULE = $Module }
if (-not [string]::IsNullOrWhiteSpace($BatchId)) { $env:RDD_BATCH_ID = $BatchId }
# 收尾闸要读 node 的 UTF-8 输出。PS 5.1 默认按控制台代码页(GBK)解管道，
# 中文会变成「鈽?涓嬮潰」这种乱码（实测）。改一次输出编码，只影响本进程。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
. "$PSScriptRoot\config.ps1"

Write-Output "=== Self-Compile 单轮闭环 ==="
Write-Output "需求: $Requirement"
Write-Output "实例: $($global:RDD_SC.SC_INSTANCE) ($($global:RDD_SC.MC_GAME_DIR))"
Write-Output "构建模块: $($global:RDD_SC.PLUGIN_MODULE)"
if (-not [string]::IsNullOrWhiteSpace($BatchId)) { Write-Output "批次号: $BatchId（将写进 deploy-ledger.jsonl）" }

# 1. 创建 mutation 工作区
$id = & "$PSScriptRoot\new-mutation.ps1" -Requirement $Requirement -Instance $Instance
if ($LASTEXITCODE -ne 0) { Write-Error "new-mutation 失败"; exit 1 }
Write-Output "[1/6] mutation-id: $id"

# 2. 安全编译 + 打包
if ($TestOnly) {
    $buildOut = & "$PSScriptRoot\build-jar.ps1" -MutationId $id -ModuleOverride $Module -TestOnly -Tests $Tests -SourceRoot $SourceRoot -ExpectedCommit $ExpectedCommit
    $testExit = $LASTEXITCODE
    Write-Output "[test-only] $buildOut"
    if ($testExit -ne 0) { exit $testExit }
    # Explicitly return before deploy, launch, MCP, or verify.
    exit 0
}
$buildOut = & "$PSScriptRoot\build-jar.ps1" -MutationId $id -ModuleOverride $Module
if ($LASTEXITCODE -ne 0) { Write-Error "build-jar 失败: $buildOut"; exit 1 }
Write-Output "[2/6] $buildOut"

# 3. 部署实验
$deployOut = & "$PSScriptRoot\deploy.ps1" -MutationId $id
if ($LASTEXITCODE -ne 0) { Write-Error "deploy 失败: $deployOut"; exit 1 }
Write-Output "[3/6] $deployOut"

# 4. 启动 MC（默认执行，-SkipLaunch 跳过）
if (-not $SkipLaunch) {
    $launchOut = & "$PSScriptRoot\launch-mc.ps1" -MutationId $id -AutoStopMinutes $AutoStopMinutes
    Write-Output "[4/6] $launchOut"
    if ($LASTEXITCODE -eq 1) { Write-Error "launch-mc 失败"; exit 1 }
    # 等待游戏加载（给玩家/世界加载留时间）
    Write-Output "等待游戏加载存档 $($global:RDD_SC.MC_SAVE) ..."
    Start-Sleep -Seconds 40
} else {
    Write-Output "[4/6] 跳过启动（-SkipLaunch）"
}

# 5. MCP 驱动
if (-not $SkipMcp) {
    $mcpOut = & "$PSScriptRoot\mcp-drive.ps1" -MutationId $id
    Write-Output "[5/6] $mcpOut"
    if ($LASTEXITCODE -ne 0) { Write-Error "mcp-drive 失败"; exit 1 }
} else {
    Write-Output "[5/6] 跳过 MCP（-SkipMcp）"
}

# 5b. 采集验证证据（2026-09-29 补）
# verify.ps1 要求 evidence/*.json 五件才给 VERIFIED，但闭环里从来没人生产过它们，
# 于是所有 mutation 永远 UNVERIFIED（交接文档「验证节是空的」的真正根因）。
if ($CollectEvidence) {
    $evOut = & "$PSScriptRoot\collect-evidence.ps1" -MutationId $id -Instance $Instance -ToolName $EvidenceTool
    Write-Output "[5b/6] $evOut"
} else {
    Write-Output "[5b/6] 跳过证据采集（-CollectEvidence 开启；不采集则 verify 必为 UNVERIFIED）"
}

# 6. 验证
$verifyOut = & "$PSScriptRoot\verify.ps1" -MutationId $id
Write-Output "[6/6] $verifyOut"
$verifyFailed = ($LASTEXITCODE -ne 0)

# ── 7. 收尾闸（2026-10-20 用户指出：退游戏后必须写记录才能开下一轮）──
# 为什么加：AGENTS.md 写了「退游戏后 ①postflight ②回填验证卡 ③杂项记录加一行」，
# 但 run-mutation.ps1 到 [6/6] 就 exit 0 了 —— 纪律写在文档里，流程里没人执行。
# 用户原话：「这个东西没有绑定到退游戏 harness 流程里面，也就是说退游戏不是要求写记录吗？
#             然后才开始下一轮回」。
# 现在：闭环结束前强制跑 postflight；BLOCK>0 直接非零退出（下一轮不许开）。
#       Q13（验证卡）/Q14（证据坐标）的 WARN 会被打印出来催补。
# ★ 不因 verify 失败而跳过 —— verify 失败恰恰是最需要催写记录的时刻
#   （第一版写成 verify 失败就 exit 1，收尾闸永远跑不到，自测当场抓到）。
Write-Output ""
Write-Output "=== 收尾闸（退游戏后必做）==="
$gate = Join-Path "D:\rdd\harness\rdd-harness\bin" "harness-gate.js"
$gateBlocked = $false
if (-not (Test-Path $gate)) {
    Write-Warning "找不到 harness-gate.js（$gate）—— 收尾闸跳过，但这是环境问题，不是没债"
} else {
    $gateArgs = @($gate, "postflight", "--since", (Get-Date -Format 'yyyy-MM-dd'), "--keyword", $Module)
    # 注：harness-gate 目前没有 --batch 参数，别传不存在的开关（会被当成未知参数忽略或报错）
    $gateOut = & node @gateArgs 2>&1
    $gateOut | Select-Object -Last 12 | ForEach-Object { Write-Output "  $_" }
    $gateCode = $LASTEXITCODE
    if ($gateCode -eq 1) {
        $gateBlocked = $true
        Write-Output "  ✘ 收尾闸 BLOCK：退游戏后必做的记录/证据没做完，下一轮不许开。"
    } elseif ($gateCode -eq 3) {
        Write-Warning " 收尾闸环境错（exit 3，不是债）"
    } else {
        Write-Output "  VERDICT=PASS（记录/证据已收口）"
    }

    # 提醒写记录（机器判不了「记录写得好不好」，只能催）
    Write-Output ""
    Write-Output "  ⚠ 还要人工确认这三件（postflight 只能查机器项）："
    Write-Output "     ① 回填验证卡：结果/原因/复现（不许留 ⬜）"
    Write-Output "     ② 杂项记录\YYYY-MM.md 加一行 #NNN（三态 + 下一步）"
    Write-Output "     ③ 新坑写进 registry.timeLocks（智能性错误必填 guard）"
}

# ── 8. 多轮模式：本轮结束后提示下一轮 + 提示开审核（2026-10-20 用户要求）──
# 用户原话：「子agent审核可以加一个多轮开关后就可以提示审一下」
# 设计：-Rounds N 表示「还要继续跑 N 轮」。每轮结束打一个提示块，
#       并把「该开审核了」写进 report\review-requests\，让主 AI 在换轮前先叫审核子 agent。
#       不自动起子 agent（会绕开 goal/预算/权限）—— 只做**提示与记录**，起不起由主 AI 决定。
# ★ 必须放在 exit 判断【之前】：第一版写在后面，verify 一失败就 exit 1，
#   多轮提示永远打不出来（自测当场抓到）。
if ($Rounds -gt 0) {
    $nextRound = $Rounds - 1
    $reviewFile = Join-Path (Join-Path $global:RDD_SC.SC_REPORT "review-requests") "round-$((Get-Date -Format 'yyyyMMdd-HHmmss')).json"
    New-Item -ItemType Directory -Path (Split-Path $reviewFile) -Force | Out-Null
    @{
        at = (Get-Date).ToUniversalTime().ToString("o")
        mutation = $id
        batch = $(if ($env:RDD_BATCH_ID) { $env:RDD_BATCH_ID } else { "-" })
        round = $Round
        remaining = $nextRound
        ask = "开一个审核子 agent，只读本轮的批次卡+验证卡+证据，按 Z 迭代口径出「作品 bug vs harness 债」"
        evidence = @{
            batchCard = "docs\rdd-docs\rdd架构\实机验证\$BatchId-批次卡.md"
            verifyCard = "docs\rdd-docs\rdd架构\实机验证\$(Get-Date -Format 'yyyy-MM').md"
            monitor = "mc\The Best of Twilight Forest\config\numen\monitor"
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reviewFile -Encoding UTF8

    # 直接生成审核包（只读产物，不含自评）—— 让审核者拿到的不是「一句话请求」，
    # 而是一份能立刻判断的材料：判据 + 验证卡 + 部署流水 + 代码提交 + 证据坐标检查。
    # ★ 判定成败只能看退出码，不能看输出里有没有 .md ——
    #   报错信息本身就含「…批次卡.md」，用 -match '\.md$' 会把失败当成功（实测踩到，
    #   日志里明明写着「找不到批次卡」，提示块却打印「审核包已生成」= 假成功）。
    $packPath = ""
    $packErr = ""
    $reviewer = Join-Path $PSScriptRoot "verify-tools\review-batch.js"
    if ((Test-Path $reviewer) -and $env:RDD_BATCH_ID) {
        $packOut = & node $reviewer --batch $env:RDD_BATCH_ID 2>&1
        $packCode = $LASTEXITCODE
        # ★ 关键：node 的 stderr 在 PS 里是 **ErrorRecord 对象**，不是字符串 ——
        #   直接 -match 匹配的是类型描述，抓不到文本（实测踩到：报错信息为空）。
        #   所以先 Out-String 再按行切。
        $packText = ($packOut | Out-String)
        $packLines = $packText -split "`r?`n" | Where-Object { $_.Trim() }
        $packLines | Select-Object -Last 4 | ForEach-Object { Write-Output "  $_" }
        if ($packCode -eq 0) {
            $packPath = ($packLines | Where-Object { $_ -match '^\s*\S+\.md\s*$' } | Select-Object -First 1)
            if ($packPath) { $packPath = $packPath.Trim() }
        } else {
            $packErr = ($packLines | Where-Object { $_ -match '找不到批次卡|\[fail\]|Error' } | Select-Object -First 1)
            if (-not $packErr) { $packErr = "review-batch.js exit=$packCode（无输出）" }
            $packErr = "$packErr".Trim()
        }
    } elseif (-not $env:RDD_BATCH_ID) {
        $packErr = "没传 -BatchId（批次号是审核包的主键，不许猜）"
    }

    Write-Output ""
    Write-Output "════════ 多轮模式：本轮结束，还剩 $nextRound 轮 ════════"
    Write-Output "  ★ 换轮前先开审核（请求已落盘：$reviewFile）"
    if ($packPath) {
        Write-Output "  ★ 审核包已生成：$packPath"
    } else {
        # ★ 失败必须说失败，不许留一句含糊的「已生成」——那是假成功
        Write-Output "  ✘ 审核包没生成：$($packErr.Trim())"
        Write-Output "     → 缺批次卡就先建卡（判据冻结），否则审核无据可依"
    }
    Write-Output "     审什么：批次卡判据 vs 实机证据 vs 代码绑定，出「作品 bug / harness 债」两类结论"
    Write-Output "     为什么换轮前审：带着未发现的偏差进下一轮，偏差会复利"
    Write-Output "  ▶ 下一轮：run-mutation.ps1 -Round $($Round + 1) -Rounds $nextRound $(if ($BatchId) { "-BatchId $BatchId" })"
    Write-Output "════════════════════════════════════════════════════"
}

# 两个结论都跑完再一次性判（不许前一个把后一个挡掉）
if ($gateBlocked) {
    Write-Error "收尾闸 BLOCK：记录/证据未收口，下一轮不许开。修完重跑 postflight。"
    exit 1
}
if ($verifyFailed) {
    Write-Error "verify 未通过（证据未采集时必然如此：加 -CollectEvidence 重跑）"
    exit 1
}

Write-Output ""
Write-Output "=== 单轮闭环完成 ==="
Write-Output "报告: $(Join-Path $global:RDD_SC.SC_MUTATIONS $id)"

exit 0
