# 部署 jar 到实验 mods（当前生产实例 mods 目录，阶段1同实例双存档）
param(
    [string]$MutationId,
    [ValidateSet('test','gpt')][string]$Instance = $env:RDD_SELF_COMPILE_INSTANCE
)

$env:RDD_SELF_COMPILE_INSTANCE = if ($Instance) { $Instance } else { 'test' }
. "$PSScriptRoot\config.ps1"

$dir = Join-Path $global:RDD_SC.SC_MUTATIONS $MutationId
if (-not (Test-Path $dir)) { throw "mutation not found: $dir" }

# 必须显式 -Encoding UTF8：Write-ResultJson 写的是 UTF-8 **无 BOM**，而 PS 5.1 的
# Get-Content 默认按系统 ANSI(GBK) 读 —— 里面有中文(比如构建失败时写的 gradle 错误摘要)
# 就会被读成乱码并把 JSON 解析搞崩，症状是"Invalid object passed in"而不是"build failed"，
# 把真正的错误盖掉。同一类坑已在 mc-watchdog.ps1(缺 BOM)和 2026-09-28 的控制字符污染上各撞一次。
$phase = Get-Content -LiteralPath (Join-Path $dir "phase-build.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $phase.success) { throw "build phase not successful" }
if ($phase.instance -and $phase.instance -ne $global:RDD_SC.SC_INSTANCE) { throw "mutation instance '$($phase.instance)' does not match selected '$($global:RDD_SC.SC_INSTANCE)'" }

$jar = Get-ChildItem (Join-Path $dir "jar") -Filter "*.jar" | Select-Object -First 1
if (-not $jar) { throw "no jar in mutation jar/ dir" }

# 部署到实验 mods（同实例 mods）
$dest = Join-Path $global:RDD_SC.MC_MODS $jar.Name
if (Test-Path $dest) {
    $bak = "$dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $dest $bak -Force
}
Copy-Item $jar.FullName $dest -Force
$sha = (Get-FileHash $dest -Algorithm SHA256).Hash

# ── H4 部署流水（2026-10-20 #087 起）─────────────────────────────
# 为什么加：12 个 jar sha 原先散在 12 处 #0xx 记录里，口头汇报「11 次部署」
# 无据可核；而 sha 是「现网到底跑的是哪版代码」的唯一机器可读锚。
# 现在每次部署自动追加一行：时间 | sha | 批次号 | mutation | 实例 | 目标路径。
# 批次号从环境变量 RDD_BATCH_ID 取（run-mutation.ps1 -BatchId 传入）；
# 没传就写 "-"（不许猜，猜出来的批次号比没有更坏）。
$ledger = Join-Path $global:RDD_SC.SC_REPORT "deploy-ledger.jsonl"
if (-not (Test-Path $global:RDD_SC.SC_REPORT)) { New-Item -ItemType Directory -Path $global:RDD_SC.SC_REPORT -Force | Out-Null }
$ledgerRow = @{ at = (Get-Date).ToUniversalTime().ToString("o"); sha = $sha; batch = $(if ($env:RDD_BATCH_ID) { $env:RDD_BATCH_ID } else { "-" }); mutation = $MutationId; instance = $global:RDD_SC.SC_INSTANCE; jar = $jar.Name; dest = $dest } | ConvertTo-Json -Compress
Add-Content -LiteralPath $ledger -Value $ledgerRow -Encoding UTF8

$result = @{
    success = $true
    stage = "deploy"
    deployedTo = $dest
    instance = $global:RDD_SC.SC_INSTANCE
    sha256 = $sha
    batch = $(if ($env:RDD_BATCH_ID) { $env:RDD_BATCH_ID } else { "-" })
    state = "DEPLOYED_EXPERIMENT"
}
Write-ResultJson (Join-Path $dir "phase-deploy.json") $result
Write-Output "DEPLOY_OK"
Write-Output "LEDGER_OK $sha batch=$env:RDD_BATCH_ID"
exit 0
