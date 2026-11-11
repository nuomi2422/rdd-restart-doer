# 部署 jar 到实验 mods（当前生产实例 mods 目录，阶段1同实例双存档）
# H1-min 收敛：mods 只由本入口写；写入前用 mc-instance 的三态拒绝运行中/未知部署。
# 回滚不再自己 copy，改为调用本入口 -JarPath（同一落点）。
param(
    [string]$MutationId,
    [string]$JarPath,
    [string]$JarName,
    [ValidateSet('test','gpt')][string]$Instance = $env:RDD_SELF_COMPILE_INSTANCE,
    [string]$Mode,
    [string]$ExpectedCommit,
    [string]$ExpectedSha256
)

# 2026-11-11 explicit fixed test assembly only. Defaults and old overrides still refuse.
if ($Mode -ceq 'isolated-test' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'test' -and -not $JarPath -and -not $JarName -and $MutationId -and $ExpectedCommit -and $ExpectedSha256) {
    $ErrorActionPreference='Stop'
    try {
        . "$PSScriptRoot\deploy-test-policy.ps1"
        . "$PSScriptRoot\mc-identity.ps1"
        $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
        $result=Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/workspace/rdd-selfcompile/instances/test' -Live 'D:/rdd/mc/The Best of Twilight Forest'
        $result | ConvertTo-Json -Depth 6
        exit 0
    } catch { Write-Error ('DEPLOY_TEST_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}
# 2026-11-11 owner selected original live; exact pending-expansion RDD artifact only.
if ($Mode -ceq 'original-rdd' -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-1143a45ccf7c4b2789bb45ddc6dc5590','mutation-build-a4d56867456a4f18820d070a167ffa0a','mutation-build-60befb539f4e4c24b129e05c2f434d6b','mutation-build-3fde7607688541eb99b3de87fbbf6ad7','mutation-build-fc5f2711d6a545338719cc95750ce50d','mutation-build-7a2cded71c3e4230b7cca93ab67aa06f','mutation-build-8fe58bf41a5f456fbc5d407e2484fae3','mutation-build-84a320cad8ea474cab53da9d17480292')) {
 . "$PSScriptRoot\deploy-test-policy.ps1"
 . "$PSScriptRoot\mc-identity.ps1"
 $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
 Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
 exit 0
}
# Incident freeze: all other deployment remains refused.
Write-Output ("DEPLOY_REFUSED: incident-freeze: deploy disabled pending commander batch")
exit 2

if ($Instance) { $env:RDD_SELF_COMPILE_INSTANCE = $Instance } else { $env:RDD_SELF_COMPILE_INSTANCE = 'test' }
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\mc-instance.ps1"

$state = Get-RddMcState -Instance $global:RDD_SC.SC_INSTANCE
Write-Output "STATE_PROBE: attempt=1 state=$state"
if ($state -eq 'UNKNOWN') {
    # 2026-11-05：刚停游戏时可能残留"正在退出的 java"，WMI 读不到 CommandLine 就判 UNKNOWN。
    # 等 5 秒再判一次（只重试一次，避免掩盖真正无法判定实例的情况）。
    # 审计要求：这次重试必须留痕——不能静默掩盖一次"不可判定"。
    Write-Output "STATE_PROBE: UNKNOWN -> wait 5s -> retry"
    Start-Sleep -Seconds 5
    $state = Get-RddMcState -Instance $global:RDD_SC.SC_INSTANCE
    Write-Output "STATE_PROBE: attempt=2 state=$state"
}
if ($state -eq 'RUNNING') {
    Write-Output "DEPLOY_REFUSED_RUNNING: instance '$($global:RDD_SC.SC_INSTANCE)' is running"
    exit 5
}
if ($state -ne 'STOPPED') {
    Write-Output "DEPLOY_REFUSED_UNKNOWN: cannot verify instance '$($global:RDD_SC.SC_INSTANCE)' (state=$state)"
    exit 6
}

$dir = $null
$phase = $null
if ($JarPath) {
    if ($MutationId) { throw "use either -MutationId or -JarPath, not both" }
    if (-not (Test-Path -LiteralPath $JarPath -PathType Leaf)) { throw "jar not found: $JarPath" }
    if ($JarPath -notmatch '\.jar$') { throw "JarPath must be a .jar file" }
    $jar = Get-Item -LiteralPath $JarPath
    if (-not $JarName) { $JarName = $jar.Name }
    if ($JarName -match '[\\/]') { throw "JarName must be a basename" }
    if ($JarName -notmatch '^[A-Za-z0-9._-]+\.jar$') { throw "JarName must be a plain .jar name" }
} else {
    if (-not $MutationId) { throw "need -MutationId or -JarPath" }
    if ($MutationId -notmatch '^[A-Za-z0-9._-]+$') { throw "invalid MutationId" }
    $dir = Join-Path $global:RDD_SC.SC_MUTATIONS $MutationId
    if (-not (Test-Path $dir)) { throw "mutation not found: $dir" }

    $phase = Get-Content -LiteralPath (Join-Path $dir "phase-build.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $phase.success) { throw "build phase not successful" }
    if ($phase.instance -and $phase.instance -ne $global:RDD_SC.SC_INSTANCE) { throw "mutation instance '$($phase.instance)' does not match selected '$($global:RDD_SC.SC_INSTANCE)'" }

    $jar = Get-ChildItem (Join-Path $dir "jar") -Filter "*.jar" | Select-Object -First 1
    if (-not $jar) { throw "no jar in mutation jar/ dir" }
    $JarName = $jar.Name
}

$modsFull = [IO.Path]::GetFullPath($global:RDD_SC.MC_MODS)
$dest = Join-Path $modsFull $JarName
$destFull = [IO.Path]::GetFullPath($dest)
if (-not $destFull.StartsWith($modsFull + [IO.Path]::DirectorySeparatorChar)) { throw "dest escapes mods: $dest" }

$srcSha = (Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash
$bak = $null
if (Test-Path -LiteralPath $dest) {
    $bak = "$dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $dest -Destination $bak -Force
}
Copy-Item -LiteralPath $jar.FullName -Destination $dest -Force
$sha = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
if ($sha -ne $srcSha) {
    if ($bak) { Copy-Item -LiteralPath $bak -Destination $dest -Force } else { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
    throw "copy hash mismatch: $sha != $srcSha"
}

$ledger = Join-Path $global:RDD_SC.SC_REPORT "deploy-ledger.jsonl"
if (-not (Test-Path $global:RDD_SC.SC_REPORT)) { New-Item -ItemType Directory -Path $global:RDD_SC.SC_REPORT -Force | Out-Null }
$ledgerRow = @{ at = (Get-Date).ToUniversalTime().ToString("o"); sha = $sha; batch = $(if ($env:RDD_BATCH_ID) { $env:RDD_BATCH_ID } else { "-" }); mutation = $(if ($MutationId) { $MutationId } else { "-" }); instance = $global:RDD_SC.SC_INSTANCE; jar = $JarName; dest = $dest } | ConvertTo-Json -Compress
Add-Content -LiteralPath $ledger -Value $ledgerRow -Encoding UTF8

if ($MutationId) {
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
}
Write-Output "DEPLOY_OK"
Write-Output "LEDGER_OK $sha batch=$env:RDD_BATCH_ID"
exit 0
