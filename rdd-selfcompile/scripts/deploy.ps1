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

# 2026-11-14: A1 journal wiring and low-hp food completion; only these two audited a199 builds.
# Keep the stopped-live copy/backup path and every older rollback tuple.
if ($Mode -ceq 'original-a1-food-a199' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'a199d778c3d8be921c5f21f5aae085b80d975106' -and (($MutationId -ceq 'mutation-build-ffae833c8c124edd9d9494426c9c577c' -and $ExpectedSha256 -ieq 'C88FCC3E215CA7CDEC751D14F0B629CE2C059DF962913B9440E46C063B5160FC') -or ($MutationId -ceq 'mutation-build-a33e86a4a25c4a8782a6ed01c2a44fb3' -and $ExpectedSha256 -ieq '1F16C8F52FF6C68F90A22D1630F2AF5411A819DA7E85970C0225892B2D9015FC'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_A1_FOOD_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-14: exact compat learner successor build for the stopped original live only.
if ($Mode -ceq 'original-learner-successor-28ba' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '28ba205413b031f91a799fbe35f704831bd8982d' -and $MutationId -ceq 'mutation-build-412cb9c4933347d99785c5364e5008d9' -and $ExpectedSha256 -ieq 'F3FE5621F331B33D982B1CC9B6DF26304049CC04B2AC48AF3178C6BBFDA109CB') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_LEARNER_SUCCESSOR_28BA_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-15: exact inspected late-callback learner artifact (1e402); all older rollback tuples stay unchanged.
if ($Mode -ceq 'original-learner-late-1e402' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '1e40290cfad3e64a9fd4f3e1a015c73dd92e3646' -and $MutationId -ceq 'mutation-build-d5fcda28252c4f00b4b73edc70fd4a05' -and $ExpectedSha256 -ieq '886ECA7AF36A0D8273E8FB0591CF6D9322C05B9017B68EB7D98AA4CE34F23BF8') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_LEARNER_LATE_1E402_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-14: exact inspected 86785 nudge RDD artifact; all older rollback tuples and guards stay unchanged.
if ($Mode -ceq 'original-rdd-nudge-86785' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '86785a7a61cc0cbeff5e0d32262d6e7dd829c194' -and $MutationId -ceq 'mutation-build-9ac2a358204d457eb7a02ace7eabd9cb' -and $ExpectedSha256 -ieq 'A2F081963BDB715D73D26D433A1C0977941DE30515EFA017AB8EB228DD392106') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_RDD_NUDGE_86785_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-14: aa735 audited RDD/learner/experience only; one mutation per call, no core/API changes.
if ($Mode -ceq 'original-parallel-aa735' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'aa73586a069361aea5d263618d0dfa8b1bc40df3' -and (
 ($MutationId -ceq 'mutation-build-2f09f207d2d146619c65dc236c0b08c1' -and $ExpectedSha256 -ieq '2FB0E0636B106DB48140DF5EFF859CDDAAC3350A15815933DD8DA9E54ACE588F') -or
 ($MutationId -ceq 'mutation-build-9d7b663c3b04480ca78d80461399b4b2' -and $ExpectedSha256 -ieq '3570AF13D57BA5F4ABF77D6064C4B9EEC82A81605EF29849B4F1FF00795094E6') -or
 ($MutationId -ceq 'mutation-build-d4121062b6e54cd78ffb32a6a86e23e5' -and $ExpectedSha256 -ieq '99E188C606F72C40675926FDC432B1BEB5EA647E1E1F160C3A6DA23600BF3CBC'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_PARALLEL_AA735_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-14: 8853 verified RDD/learner/experience only; one mutation per call, no core/API changes.
if ($Mode -ceq 'original-why-8853' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '8853c569e6e51d0bc23a39b4b5dcdea7f685f69a' -and (
 ($MutationId -ceq 'mutation-build-bcf9062caa914d12b1d75a250e8bd5ee' -and $ExpectedSha256 -ieq '8136345A8FFBC1322BC289B7CBEFF37479E9FC9D2573963CC6DB09B3674A9DCE') -or
 ($MutationId -ceq 'mutation-build-5a5fccbb162244d0906d26be8d7f329d' -and $ExpectedSha256 -ieq 'F42716BC0C6C3CD980C3080614F356B58F7C6D9C47860360E1081CA33A07459F') -or
 ($MutationId -ceq 'mutation-build-7cc1a6f15b61475587953bf380d8f7b1' -and $ExpectedSha256 -ieq '6371B7BF3926EBE8AA27A8A2AD63196A8B8F41C72E36ADB9EBA620755E717C00'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_WHY_8853_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-14: V25 exact RDD/experience artifacts only; unchanged core/API/learner stay installed.
if ($Mode -ceq 'original-v25-144ac' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '144ac9570932de65b80ae61d0ffffcb317934922' -and (
 ($MutationId -ceq 'mutation-build-4ee45e827c1e439eb95638a175a68177' -and $ExpectedSha256 -ieq '8B85F50E48BFCB922D15D0E46CD9F7E7EF75C125F826C396D3CE9E8DDBEE6B28') -or
 ($MutationId -ceq 'mutation-build-f59304e827ee473bb10022854c2aaf2f' -and $ExpectedSha256 -ieq 'BD66DFDB53A0702B6884093A36AB0D0D10A005EFF6741C7A7915ED3EB949D7A5'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_V25_144AC_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-15: V26 exact RDD/core artifacts only; every older rollback tuple stays unchanged.
if ($Mode -ceq 'original-v26-5c046' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '5c046644683b26b385ef06e57260f3aa16edfb1b' -and (
 ($MutationId -ceq 'mutation-build-fcfb896670ac47fc8c07725fae837c77' -and $ExpectedSha256 -ieq 'BECF06531DB5E3911D91834B2785E3DB73AF4308331D6B3F0D9FB19BE306D01B') -or
 ($MutationId -ceq 'mutation-build-f5e19b3475a44df281915f229f2c1366' -and $ExpectedSha256 -ieq '2FC60365B898D3ACC903F461A2791864F48188670F21B02E05DD5E2AEFCE2989'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_V26_5C046_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-15: exact B2/C1 9f94 RDD artifact only; every older rollback tuple stays unchanged.
if ($Mode -ceq 'original-b2-c1-9f94' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '9f94bbbad357687538dc4c50498ae05a729d7f86' -and $MutationId -ceq 'mutation-build-c3a130228cf54d41a05fa168e0446338' -and $ExpectedSha256 -ieq '18C226A3450D36DE2CD4B126F4D639FA4A66E154AC9979DC02E91EEFD28F00DA') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_B2C1_9F94_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-15: exact V27 convo restore core artifact only; every older rollback tuple stays unchanged.
if ($Mode -ceq 'original-convo-1f2' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '1f2e86286113430b58425446a132b986d482cf10' -and $MutationId -ceq 'mutation-build-c7b23cc99dfc4b8ea2f8a7da92606a2b' -and $ExpectedSha256 -ieq '9959267A3CC8D8B982ACEF99EAEB95030B75D5C6E83D4E3F85B5E74C236DCAC1') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_CONVO_1F2_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-15: exact V28 KB-quota core artifact (83ddd) only; every older rollback tuple stays unchanged.
if ($Mode -ceq 'original-kb-quota-83ddd' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '83ddd36f00aecd64b220155bf53658dbac776df0' -and $MutationId -ceq 'mutation-build-e5184f70bd7b41fdabdc3f85cbf17306' -and $ExpectedSha256 -ieq 'FB48F4779F68827A3CCD8EDBAE002A6D2F769EBED005C6298E16C1556CC00A4D') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
} catch { Write-Error ('DEPLOY_KB_QUOTA_83DDD_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-15: exact V30 daily-condition RDD artifact (faede) only; every older rollback tuple stays unchanged.
if ($Mode -ceq 'original-daily-faede' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'faede91ce4bf0ff5c9253df798988a4f4f8fddf9' -and $MutationId -ceq 'mutation-build-faa7ff97c0c44bb6b9d36aef17281ae9' -and $ExpectedSha256 -ieq 'C9798F2F4068266AF4574400ABD754B6CEF814D08B23E5A4FA3DC569E9A4C1E1') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot\deploy-test-policy.ps1"
  . "$PSScriptRoot\mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
} catch { Write-Error ('DEPLOY_DAILY_FAEDE_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-16: exact tested manual integration; core embeds API, no standalone API tuple.
if ($Mode -ceq 'original-manual-0fada' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '0fada9b87cf75f719a7c0de9d269ff7009281b17' -and (
 ($MutationId -ceq 'mutation-build-917da3d407814f27bb8479f2d1c0b452' -and $ExpectedSha256 -ieq '3CA192EEF304964FC3C4424C5992A83F0E8E369A9741FABE177F15A3235D61B1') -or
 ($MutationId -ceq 'mutation-build-d2949d98ceab4084a3f18dedde8da948' -and $ExpectedSha256 -ieq '3814920BB30BA6B47E3A97FBF2C92FEF540D19AB9EC416A110F849AE1BC8D3BC'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_MANUAL_0FADA_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-16: verified HP provenance fix, exact core with embedded API only.
if ($Mode -ceq 'original-hp-e4ed' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'e4edcb356ff50516e3e145c06b718bdfbf5dce1b' -and $MutationId -ceq 'mutation-build-2cde0f776f7045b5ac6ce050a3479243' -and $ExpectedSha256 -ieq 'FEA637B008E50E0DA5D8C55264300AA127F61355E07B3284C9E310FBEEC5C862') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_HP_E4ED_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-16: exact bounded-food quota RDD successor; no core or other plugin permission.
if ($Mode -ceq 'original-quota-d6c97' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'd6c97dc4693ae6419a1d76c5b83fd2051a92f9c1' -and $MutationId -ceq 'mutation-build-21271b7839bc4c3286c1a0c4581f7af3' -and $ExpectedSha256 -ieq 'AEDF5FC53B0E5171F153FA09F0B32B280B500879295D6BD8579F3C0045BCBEC4') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_QUOTA_D6C97_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact language/header core release only; original stopped-live assembly and rollback checks remain.
if ($Mode -ceq 'original-ui-ddd42' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'ddd42b8005a9cab35710dc6652adba0bdb8fd5e5' -and $MutationId -ceq 'mutation-build-81c298370ef5495d8af734bd2290953c' -and $ExpectedSha256 -ieq 'C58E1F73D097A20CDCFF1F413C6D9C21F4EF76CD76872B6AE031BE2E493A3DCA') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_UI_DDD42_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# LH1: two exact original preparation artifacts, with separate source proofs.
if ($Mode -ceq 'original-lh1-prep' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and (($MutationId -ceq 'mutation-build-61d0b49492df4d238143c230a1a6ed40' -and $ExpectedCommit -ceq 'ab8cc639e9f69fae10c46216e6ad85cf95789815' -and $ExpectedSha256 -ieq '6C1BB8D816A8486F735C94D464D9933DA78F0899839B9F2596328B33CDA3ABF5') -or ($MutationId -ceq 'mutation-build-a19f8a022a5c4f39871cafda0bdbdc06' -and $ExpectedCommit -ceq '03f290fdb510438dc17c07be2b84407ec7f8fec2' -and $ExpectedSha256 -ieq 'FEE71CF0C84F30D0BDF38BEDC9C0E0B608BEE500A5F504E079FBB827CC83A897'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_LH1_PREP_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-16: exact class-split core (embedded API) and RDD only; no standalone API deployment.
if ($Mode -ceq 'original-class-split' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '7f09b9587731fa5caca670169ad1ff51298b3e81' -and (($MutationId -ceq 'mutation-build-60d0165f55ac4b7f9c61281e9cdc1663' -and $ExpectedSha256 -ieq '0200317C9BE01B46DF7087900063F021127FF5F4A16546E858D243B6B85CE900') -or ($MutationId -ceq 'mutation-build-8ea1cec5df834d04bcb90077743187d7' -and $ExpectedSha256 -ieq '40BFD00E914D3781616E5D13BF2A07FBB344445C72D78C4693459DE6879EB80D'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_CLASS_SPLIT_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-16: exact pending-death drop-only handoff RDD successor; keep installed core unchanged.
if ($Mode -ceq 'original-pending-death-b650' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'b650e75f0f5244a72f175c03679bdfd742a88ee2' -and $MutationId -ceq 'mutation-build-ea8be9aa893543648b3784c6e8597f27' -and $ExpectedSha256 -ieq '0D91487B6244722459FABE96CAD4DC971B9C825FAC308AE9347687FAAA11E713') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_PENDING_DEATH_B650_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# 2026-11-16: exact recovering-scope RDD successor only; keep installed core unchanged.
if ($Mode -ceq 'original-recovering-b2c' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'b2c31651979645a1007130465e5df3eee3e09ea8' -and $MutationId -ceq 'mutation-build-5ba3aaaeec62478f860acefd1b24bcf1' -and $ExpectedSha256 -ieq '0DEF5F96DB0CA315EB2F15A2B3CE816A5C46D7FC11F47CD2DE67A67F7F6477D3') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_RECOVERING_B2C_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact 3238 reviewed consolidation pair; no arbitrary source or jar selection.
if ($Mode -ceq 'original-consolidation-3238' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '3238c63e087aff10bd82eca1471740d48478976c' -and (($MutationId -ceq 'mutation-build-8f22b2d6d6fb487fa19c4207006c8d9d' -and $ExpectedSha256 -ieq '905DAA01BB3ADBBB479E3F498D0B42E416B918F58B63401808271121F87D4A4E') -or ($MutationId -ceq 'mutation-build-01d8b35cca62496fa1a1f2d13d25fe3a' -and $ExpectedSha256 -ieq '6D3E38E5A12BD9A54F9C3F6A6CAB3C2320DE8376567E02DD1A5274326C3C23D2'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_CONSOLIDATION_3238_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact reviewed 3ee7 trio only; no arbitrary source/path channel.
if ($Mode -ceq 'original-trio-3ee7' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '3ee7ff271c6c02bb74f828e7ba75cc27464b9600' -and (($MutationId -ceq 'mutation-build-13df6869a04f4607b499dd8c9d250e65' -and $ExpectedSha256 -ieq '4840D714F0E31C5E0F1C59214AF9A9C040A91C6E594328399492C5B37393DD6A') -or ($MutationId -ceq 'mutation-build-6abbdea615ba45d196b497ba7685f909' -and $ExpectedSha256 -ieq '1E01B60F697154AB082FBAAED8DB0EEA93BDAD4A43385A5ABF88D98DDDCE5287') -or ($MutationId -ceq 'mutation-build-63eaefff6767450e8dba4982162948a3' -and $ExpectedSha256 -ieq 'E0B937ECF0B828835FFE764BB2B339D4F9A70F0968849C9319FE67BFAF5160E8'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_TRIO_3EE7_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact reviewed c764 core/RDD plus cb7 fix learner trio only; no arbitrary source/path channel.
if ($Mode -ceq 'original-trio-cb7' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and ($ExpectedCommit -ceq 'c764d3f1bb3ba28814ce3496944d61144bf74297' -or $ExpectedCommit -ceq 'cb7f8fa7f798ae19e54ac7e22e05a5a53c131e55') -and (($MutationId -ceq 'mutation-build-387e668e375e48c89288cfa6bd44ff15' -and $ExpectedSha256 -ieq 'BE3EE8B2836104D18D412F2C3EC10265E957D631B480256853D22A41109C1F87') -or ($MutationId -ceq 'mutation-build-cc72c915e5aa432f9556f057af4661f9' -and $ExpectedSha256 -ieq 'D3A1A1C912E536629CF114E12E2FA534523158E168AA00A96A9A0F7247AA5DEA') -or ($MutationId -ceq 'mutation-build-c991005bded949bfa2ff7f4cc06c9e24' -and $ExpectedSha256 -ieq '110742902A1E00113D2604F3A93481EE9C679FFE4BFA13B61B55EBEEB576A3D1'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_TRIO_CB7_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact d20e integrated pair only; no source/path override.
if ($Mode -ceq 'original-pair-d20e' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq 'd20e061a87eeba7c2128f4940ff90b5dc9f5226d' -and (($MutationId -ceq 'mutation-build-6dbaf640631746f3960336119f97a01a' -and $ExpectedSha256 -ieq '362C8FEFB8ED5D8E8EF2D803465535AF1AAB6D162B59C3BB802ED1EB059A915B') -or ($MutationId -ceq 'mutation-build-818e9da828e4480a8779809bc9091976' -and $ExpectedSha256 -ieq '5558F0C546C5BA6A710996633DB3A6377DF09489BA25CF2A74DEA68114874707'))) {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_PAIR_D20E_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact V02 40905 single RDD artifact only; no source/path override.
if ($Mode -ceq 'original-v02-plan-40905' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '40905ed44408bf01b32cba1359501ecc5de472f9' -and $MutationId -ceq 'mutation-build-ebf6c66645bc4c8f873271dc57a38380' -and $ExpectedSha256 -ieq 'A92EB460C28AB0185C8DAE4A56E1AACF46AA1D4AF4570C3718E89BD8AFA942EE') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_V02_PLAN_40905_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact 4e110 projection single RDD artifact only; no source/path override.
if ($Mode -ceq 'original-projection-4e110' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '4e11016f70f310d87c57faa4818037fa7bcce100' -and $MutationId -ceq 'mutation-build-a72f05bde6494b1cb714cd0a334b9615' -and $ExpectedSha256 -ieq 'CFE9BEAAC8FBEF881F7F207DD5FD5608B788FA669D09416810F1BD86313D99D3') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_PROJECTION_4E110_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
}

# Exact 66e3 unified single RDD artifact only; no source/path override.
if ($Mode -ceq 'original-unified-66e3' -and $PSBoundParameters.ContainsKey('Instance') -and $Instance -ceq 'gpt' -and -not $JarPath -and -not $JarName -and $ExpectedCommit -ceq '66e3e1ce6a0f7226d127213638dd70245656864a' -and $MutationId -ceq 'mutation-build-4a3462707a304321b628e69862f570dd' -and $ExpectedSha256 -ieq '710B5787894DA9BB0C80AA5CE412A3A0AF1CF7B8A9BA3E93382D1CC12E98456C') {
 $ErrorActionPreference='Stop'
 try {
  . "$PSScriptRoot/deploy-test-policy.ps1"
  . "$PSScriptRoot/mc-identity.ps1"
  $source=Get-RddTestDeploySource -MutationId $MutationId -ExpectedCommit $ExpectedCommit -ExpectedSha256 $ExpectedSha256 -Mutations 'D:/rdd/workspace/rdd-selfcompile/mutations' -Original
  Invoke-RddTestAssembly -Source $source -Root 'D:/rdd/mc/The Best of Twilight Forest' -Live 'D:/rdd/mc/The Best of Twilight Forest' -Original | ConvertTo-Json -Depth 6
  exit 0
 } catch { Write-Error ('DEPLOY_UNIFIED_66E3_REFUSED_OR_FAILED: '+$_.Exception.Message);exit 2 }
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
