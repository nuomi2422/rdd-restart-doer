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
# 2026-11-13: recovery RDD adds one inspected tuple, explicit gpt only; legacy selection unchanged.
if ($Mode -ceq 'original-rdd' -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and (($PSBoundParameters.ContainsKey('Instance') -and $MutationId -ceq 'mutation-build-1fa09220d99b4f78b504e3ea1287cfe5') -or $MutationId -cin @('mutation-build-1143a45ccf7c4b2789bb45ddc6dc5590','mutation-build-a4d56867456a4f18820d070a167ffa0a','mutation-build-60befb539f4e4c24b129e05c2f434d6b','mutation-build-3fde7607688541eb99b3de87fbbf6ad7','mutation-build-fc5f2711d6a545338719cc95750ce50d','mutation-build-7a2cded71c3e4230b7cca93ab67aa06f','mutation-build-8fe58bf41a5f456fbc5d407e2484fae3','mutation-build-84a320cad8ea474cab53da9d17480292','mutation-build-19ecce8338544ef789794af2c268c681'))) {
 . "$PSScriptRoot\deploy-test-policy.ps1"
 . "$PSScriptRoot\mc-identity.ps1"
 $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
 Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
 exit 0
}
# 2026-11-12: reuse only the managed learner artifact to unblock original live entry.
if ($Mode -ceq 'original-learner' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-52876a2a2dd44cc68009c3ad4992de35' -and $ExpectedCommit -ceq '65ffba3ecdd9171eb59af470ba275f9e6655900f' -and $ExpectedSha256 -ieq 'BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_LEARNER_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}
# 2026-11-12: one accepted integration, exact managed tuples; no generic deployment.
if ($Mode -ceq 'original-accepted' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-14e46e1075514aed872cd27fe75b4a4a','mutation-build-34ab8109f7e042559e1de20539924c4d','mutation-build-7130759b9c3044de8a1a8da8c5d1d881') -and $ExpectedCommit -ceq 'bb0f1fd8507d82c4a3d3f9ecc9c6aa5fe5fb94ec' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_ACCEPTED_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-12: exact verified 330b core and learner for the stopped original live only.
if ($Mode -ceq 'original-next-verified' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-c9ac2a7723fa4674911de387184698c9','mutation-build-bd0bcda5f6d245ecad714b5f4f022afd') -and $ExpectedCommit -ceq '330b6f5b2b1fdc814d0e8d5ff2337fe11825ef73' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_NEXT_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}


# 2026-11-12: e826 exact managed three-artifact original-live deployment only.
if ($Mode -ceq 'original-e826' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-1dd867b5ae6a49c7aecc728e958d5dd8','mutation-build-674cea78df824d24b8039ff3f940f0e4','mutation-build-cbb5ea3bc0804bc9ae6a6244c1b68c23') -and $ExpectedCommit -ceq 'e826813d962090dccaca62e03513079ca3a1fb7a' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_E826_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-12: owner-found issues; exact tested four-artifact 4b2f batch on stopped original live only.
if ($Mode -ceq 'original-owner-findings' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-1fb466ca58004f7d83afd093013d68c3','mutation-build-937966ec05724882916105cd45f470b4','mutation-build-f0a3c69242714cde8d1152170c1fe931','mutation-build-aea5643ec50a4601a4663e945af7162f') -and $ExpectedCommit -ceq '4b2f202b3b8df1fa3d54f9961a26c273ef36f9d0' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_OWNER_FINDINGS_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-12: exact consumer-verified runtime-followups batch; no generic deploy permission.
if ($Mode -ceq 'original-runtime-followups' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-c0961c5a6e3b46edb927a3236be61058','mutation-build-6ed6b106a2c646018015ee3bc29967cd','mutation-build-dd6531bb6a114bdc85cb01235537e15e','mutation-build-367b48b425d54ae5a48845153342fd4f') -and $ExpectedCommit -ceq '842d7ee0123a8ead96a04ef673e0c29a2ff4534c' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_RUNTIME_FOLLOWUPS_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-12: unique replies preserve MCP ownership; exact 32-test core tuple only.
if ($Mode -ceq 'original-transport-external' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-4f56fc55b7be483cab7f8e24579d9749' -and $ExpectedCommit -ceq 'f7b7c48a1ebbf93dd79e04bc6e596872c187273e' -and $ExpectedSha256 -ieq 'AF772A3F55B206F13E464807F7897FB1F85759A22D92F2D21F0F328336E8CD19') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_TRANSPORT_EXTERNAL_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-12: inspected mine-recovery core, one exact managed tuple on stopped original live.
if ($Mode -ceq 'original-mine-recovery' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-702ea0b018534536977499b23ccee172' -and $ExpectedCommit -ceq '78c3fd296145c79dd3bad5dda643641b2ccf2a70' -and $ExpectedSha256 -ieq '789EF0A21435E7939058E2EDEF74F078386EF2BB7B9E296D54EDF0091FA97E67') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations'
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_MINE_RECOVERY_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-13: exact inspected attack-description core only; no generic release permission.
if ($Mode -ceq 'original-attack-contract' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-2048390e5f5a4cbb9ed777ed789f28d1') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_ATTACK_CONTRACT_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-13: inspected learner restore consumer only; exact tuple on original stopped live.
if ($Mode -ceq 'original-learner-restore' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-363dd216836540e0b05899ecd4e4002c') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_LEARNER_RESTORE_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-13: inspected survival-preempt replan RDD; one exact stopped original-live tuple.
if ($Mode -ceq 'original-survival-replan' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-a8815be16204427a8297995d57efbcdc') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_SURVIVAL_REPLAN_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-13: one inspected d9 B2 artifact; retain stopped original-live checks, backups and receipt verification.
if ($Mode -ceq 'original-survival-intent' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-40e931ffc2264468ae8972af764742df' -and $ExpectedCommit -ceq 'd9a76ab43a049809b512d3fff8a52d0180552ee1' -and $ExpectedSha256 -ieq 'B9D26D7B057C52394531E66B7B3A937C09ECE70D633555DCE95F24845EFDA053') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_SURVIVAL_INTENT_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-13: coherent C1/B2 release; exact ec1b source and three managed artifacts only.
if ($Mode -ceq 'original-c1-b2-verified' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-f081e4e6f60e4bf090a7d425a81e1158','mutation-build-330e7ece7f8b472bac3b487b8c099e10','mutation-build-1f0beb3c375e44999b96395022952d94') -and $ExpectedCommit -ceq 'ec1b770985b476ae986998957a455a5eeca76fd0' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_C1_B2_VERIFIED_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-13: reviewed generation guard and food admission; two exact managed artifacts only.
# V08 exposed source/package drift. Keep the old freeze and stopped-live checks, not a generic release lane.
if ($Mode -ceq 'original-review-food-25b6' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -cin @('mutation-build-1f1a8a7c967947669769dd2c7b6e8eb5','mutation-build-2729529bc6e749dab1bb34cf2ebe96b3') -and $ExpectedCommit -ceq '25b6f23026e7bd6e6da13465b111d626c3995122' -and $ExpectedSha256) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_REVIEW_FOOD_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-14: 131 consumer checks passed on 1a347; publish only this inspected learner build.
# V09 exposed nonpersistent review clocks. Keep stopped-live/backup checks and the old 25b6 rollback tuple.
if ($Mode -ceq 'original-result-review-1a347' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $MutationId -ceq 'mutation-build-0cc0780d079e473d9e35b87ff3ac1a65' -and $ExpectedCommit -ceq '1a347ba6b0ab16d2100d926e4ae58316912131ab' -and $ExpectedSha256 -ieq '653913D3E0E009045940DC8FF691892F1DC474766A9651DA6FE09FEF4836528C') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_RESULT_REVIEW_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
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
