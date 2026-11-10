# 安全编译 + 打包 selfcompile 插件 jar（期3：正确检测编译失败）
param(
    [string]$MutationId,
    [string]$ModuleOverride,
    [switch]$TestOnly,
    [string[]]$Tests = @()
)

. "$PSScriptRoot\config.ps1"

# 2026-09-29: honour the moduleOverride that AGENTS.md/handoff always demanded.
# Without this the only way to build e.g. plugins:learner was a hand-written
# gradle call, which permission.bash denies.  Default behaviour is unchanged.
$defaultModule = 'plugins:selfcompile'
if ($TestOnly) {
    # Test mode resolves the module ONLY from the fixed allowlist table. Top-level
    # modules such as world-state-core have no "group:name" shape, and caller text
    # must never become a Gradle task.
    . "$PSScriptRoot\test-only-policy.ps1"
    $requested = if (-not [string]::IsNullOrWhiteSpace($ModuleOverride)) { $ModuleOverride } else { $env:RDD_SELF_COMPILE_MODULE }
    try { $testPlan = Get-RddTestOnlyPlan -Module $requested -Tests $Tests }
    catch { Write-Error $_; exit 2 }
    $effectiveModule = $testPlan.Module
} else {
    if (-not [string]::IsNullOrWhiteSpace($ModuleOverride)) {
        Set-RddSelfCompileModule $ModuleOverride | Out-Null
    } else {
        Set-RddSelfCompileModule $env:RDD_SELF_COMPILE_MODULE | Out-Null
    }
    $effectiveModule = $global:RDD_SC.PLUGIN_MODULE
}
if (-not $TestOnly -and $Tests.Count -gt 0) {
    Write-Error 'Tests requires TestOnly'; exit 2
}

$dir = Join-Path $global:RDD_SC.SC_MUTATIONS $MutationId
if (-not (Test-Path $dir)) { throw "mutation not found: $dir" }

$env:JAVA_HOME = $global:RDD_SC.JAVA_HOME
$env:GRADLE_OPTS = $global:RDD_SC.GRADLE_OPTS

Write-Output "编译插件模块 $effectiveModule ..."
Push-Location $global:RDD_SC.NUMMEN_REPO
$logFile = Join-Path $dir "phase-build.log"
# NOTE: must be "$($effectiveModule)", NOT "$effectiveModule".  PowerShell treats
# ':' as part of a variable name (scope syntax), so ":$effectiveModule:jar"
# expands to the single char ':' and gradle then reports
# "Cannot locate tasks that match ':'".  Caught 2026-09-29 with
# -ModuleOverride plugins:learner.  Keep the sub-expression form.
$gradleTask = ":$($effectiveModule):jar"
$gradleArgs = @('-p', $global:RDD_SC.NUMMEN_REPO, $gradleTask, '--no-build-cache', '--no-daemon')
if ($TestOnly) {
    $gradleArgs = @('-p', $global:RDD_SC.NUMMEN_REPO, $testPlan.Task, '--no-build-cache', '--no-daemon', '--rerun-tasks')
    foreach ($testName in $testPlan.Tests) { $gradleArgs += @('--tests', $testName) }
    $logFile = Join-Path $dir 'phase-test.log'
    # Isolate reports in this mutation; no old XML can satisfy this invocation.
    $env:RDD_TEST_REPORT_DIR = Join-Path $dir 'test-results'
    if (Test-Path -LiteralPath $env:RDD_TEST_REPORT_DIR) { Pop-Location; Write-Error 'test report directory already exists'; exit 2 }
}
try {
    & $global:RDD_SC.GRADLE @gradleArgs *> $logFile
    $gradleExit = $LASTEXITCODE
} finally {
    if ($TestOnly) { Remove-Item Env:RDD_TEST_REPORT_DIR -ErrorAction SilentlyContinue }
    Pop-Location
}
if ($TestOnly) {
    $reportDir = Join-Path $dir 'test-results'
    $receipt = Test-RddTestOnlyReceipt -ExitCode $gradleExit -ReportDir $reportDir -ExpectedTests $testPlan.Tests
    Write-ResultJson (Join-Path $dir 'phase-test.json') @{ success=$receipt.ok; stage='test-only'; reason=$receipt.reason; gradleExit=$gradleExit; reportDir=$reportDir; tests=$testPlan.Tests; deployed=$false }
    if (-not $receipt.ok) { Write-Output ("TEST_FAIL: " + $receipt.reason); exit 1 }
    Write-Output 'TEST_OK'; exit 0
}

# 编译日志内容
$log = if (Test-Path $logFile) { Get-Content $logFile -Raw } else { "" }

# 失败判定：日志含编译失败标记，或缺少 BUILD SUCCESSFUL
$compileFailed = ($log -match "错误") -or ($log -match "\d+ 个错误") -or ($log -match "BUILD FAILED")
$buildOk = (-not $compileFailed) -and ($log -match "BUILD SUCCESSFUL")

if (-not $buildOk) {
    # 提取错误摘要
    $errSummary = ""
    $errLines = $log -split "`n" | Select-String -Pattern "错误|FAILED" | Select-Object -First 3
    if ($errLines) { $errSummary = ($errLines -join " | ") }
    $result = @{ success = $false; stage = "build-jar"; error = $errSummary; log = $logFile; moduleOverride = $effectiveModule }
    Write-ResultJson (Join-Path $dir "phase-build.json") $result
    Write-Output "BUILD_FAIL: $errSummary"
    exit 1
}

# 找产物 jar
# 2026-09-29: 排除 sources/javadoc/-api 等 classifier 变体。Gradle 的 mtime 排序会把
# 它们排到主 jar 前面（api:neoforge 实测选中了 numen_api-neoforge-*-api.jar），
# 部署出去 MC 不认，主 jar 却没更新 —— 症状是"构建成功但游戏行为没变"。
$jar = Get-ChildItem (Join-Path $global:RDD_SC.NUMMEN_REPO $global:RDD_SC.PLUGIN_JAR_GLOB) -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '-(sources|javadoc)\.jar$' -and $_.Name -notmatch '-api\.jar$' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $jar) {
    $result = @{ success = $false; stage = "build-jar"; error = "no plugin jar produced"; log = $logFile; moduleOverride = $effectiveModule; jarGlob = $global:RDD_SC.PLUGIN_JAR_GLOB }
    Write-ResultJson (Join-Path $dir "phase-build.json") $result
    Write-Output "BUILD_FAIL: no jar"
    exit 1
}

$jarDest = Join-Path $dir "jar"
Copy-Item $jar.FullName $jarDest -Force
$sha = (Get-FileHash $jar.FullName -Algorithm SHA256).Hash

$result = @{
    success = $true
    stage = "build-jar"
    jarPath = $jar.FullName
    jarCopiedTo = (Join-Path $jarDest $jar.Name)
    sha256 = $sha
    instance = $global:RDD_SC.SC_INSTANCE
    gameDir = $global:RDD_SC.MC_GAME_DIR
    state = "COMPILED"
    moduleOverride = $effectiveModule
    moduleIsDefault = ($effectiveModule -eq $defaultModule)
    jarGlob = $global:RDD_SC.PLUGIN_JAR_GLOB
}
Write-ResultJson (Join-Path $dir "phase-build.json") $result
Write-Output "BUILD_OK"
exit 0
