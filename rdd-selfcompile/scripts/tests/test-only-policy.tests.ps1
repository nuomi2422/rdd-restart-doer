# Offline policy fixtures and static TestOnly native wiring guard.
# 2026-11-12: caller Stop must not let PS5.1 stderr preempt native exit capture.
# Normal script invocation only; native execution requires the managed parent run.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\test-only-policy.ps1')
function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
function MustReject([scriptblock]$block) { $rejected=$false; try { & $block } catch { $rejected=$true }; Assert $rejected 'expected rejection' }
# Compare the actual Gradle argv for a pinned TestOnly run; no JVM is launched.
$profileRoot = 'D:\stock tests\frozen'
$profileTest = 'com.dwinovo.numen.plugins.rdd.RddPlanningStockFactTest'
$profilePlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($profileTest)
$defaultArgs = @(New-RddTestOnlyGradleArgs -Root $profileRoot -Plan $profilePlan)
$commonArgs = @('-p', $profileRoot, ':plugins:rdd:test', '--no-build-cache', '--no-daemon', '--rerun-tasks')
Assert (($defaultArgs -join '|') -ceq (($commonArgs + @('--tests', $profileTest)) -join '|')) 'default TestOnly argv stays unchanged'
$init = Join-Path (Split-Path $PSScriptRoot -Parent) 'test-only-low-memory.init.gradle'
$boundedArgs = @(New-RddTestOnlyGradleArgs -Root $profileRoot -Plan $profilePlan -TestLowMemory)
$expected = $commonArgs + @('--max-workers=1', '--no-parallel', '-Dorg.gradle.jvmargs=-Xmx1024m', '--init-script', $init, '--tests', $profileTest)
Assert (($boundedArgs -join '|') -ceq ($expected -join '|')) 'low memory adds only fixed resource flags; source path and exact selector remain separate arguments'
Write-Output 'TestOnly resource profile argv PASS (no Java)'
# 2026-11-14: exact rationale/reflection consumers; no cross-module or adjacent-name admission.
$rationaleTests=@(
    @{Module='plugins:rdd';WrongModule='plugins:learner';Class='com.dwinovo.numen.plugins.rdd.RddStageBRationaleRequestTest'},
    @{Module='plugins:rdd';WrongModule='plugins:learner';Class='com.dwinovo.numen.plugins.rdd.RddSubmissionRationaleHandoffTest'},
    @{Module='plugins:rdd';WrongModule='plugins:learner';Class='com.dwinovo.numen.plugins.rdd.RddObsidianPlanConsumerTest'},
    @{Module='plugins:learner';WrongModule='plugins:rdd';Class='com.dwinovo.numen.plugins.learner.core.AcxExecutionReflectorTest'}
)
foreach($rationaleCase in $rationaleTests){
    $rationalePlan=Get-RddTestOnlyPlan -Module $rationaleCase.Module -Tests @($rationaleCase.Class)
    Assert ($rationalePlan.Task -ceq (':'+$rationaleCase.Module+':test') -and $rationalePlan.Module -ceq $rationaleCase.Module -and $rationalePlan.Tests.Count -eq 1 -and $rationalePlan.Tests[0] -ceq $rationaleCase.Class) 'rationale/reflection keeps the exact module, task and test filter'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($rationaleCase.Class)).Module -ceq $rationaleCase.Module) 'rationale/reflection has one inferred owner'
    MustReject {Get-RddTestOnlyPlan -Module $rationaleCase.WrongModule -Tests @($rationaleCase.Class)}
    MustReject {Get-RddTestOnlyPlan -Module $rationaleCase.Module -Tests @($rationaleCase.Class+'Helper')}
    MustReject {Get-RddTestOnlyPlan -Module $rationaleCase.Module -Tests @($rationaleCase.Class+'*')}
}
Write-Output ('rationale/reflection exact registration '+(5*$rationaleTests.Count)+' assertions PASS (policy only; not Java execution)')
# 2026-11-13: exact C1 delivery consumers only; no wildcard/cross-module registration.
$c1Tests=@(
    @{Module='api:common';Class='com.dwinovo.numen.api.RequestDeliveredAggregationTest'},
    @{Module='ai';Class='com.dwinovo.numen.agent.llm.LlmObservationTest'},
    @{Module='plugins:learner';Class='com.dwinovo.numen.plugins.learner.core.SkillDeliveryEvidenceTest'}
)
foreach($case in $c1Tests){
    $c1Plan=Get-RddTestOnlyPlan -Module $case.Module -Tests @($case.Class)
    Assert ($c1Plan.Task -ceq (':'+$case.Module+':test') -and $c1Plan.Tests.Count -eq 1) 'C1 exact class maps only its existing module test task'
    $c1Inferred=Get-RddTestOnlyPlan -Module '' -Tests @($case.Class)
    Assert ($c1Inferred.Module -ceq $case.Module) 'C1 class inference remains single-module'
    foreach($wrong in @('api:common','ai','plugins:learner','plugins:rdd') | Where-Object {$_ -cne $case.Module}){
        MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($case.Class)}
    }
    MustReject {Get-RddTestOnlyPlan -Module $case.Module -Tests @($case.Class+'*')}
    MustReject {Get-RddTestOnlyPlan -Module $case.Module -Tests @($case.Class.ToLowerInvariant())}
}
MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($c1Tests[0].Class,$c1Tests[1].Class)}
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @('com.dwinovo.numen.agent.llm.OtherTest')}
Write-Output 'C1 exact registration 23 assertions PASS (policy only; not Java execution)'
# 2026-11-18: A-group run receipt isolation and its exact existing offline neighbor only.
$receiptTests=@('com.dwinovo.numen.acx.test.AcxRunReceiptIsolationTest','com.dwinovo.numen.acx.test.AcxOfflineSuiteTest')
foreach($receiptTest in $receiptTests){
    $receiptPlan=Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($receiptTest)
    Assert ($receiptPlan.Module -ceq 'plugins:acx' -and $receiptPlan.Task -ceq ':plugins:acx:test' -and $receiptPlan.Tests.Count -eq 1 -and $receiptPlan.Tests[0] -ceq $receiptTest) 'receipt consumer keeps exact module/task/class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($receiptTest)).Module -ceq 'plugins:acx') 'receipt consumer has one inferred owner'
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($receiptTest)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($receiptTest.ToLowerInvariant())}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($receiptTest+'Helper')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($receiptTest+'*')}
}
$receiptPair=Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests $receiptTests
Assert ($receiptPair.Task -ceq ':plugins:acx:test' -and $receiptPair.Tests.Count -eq 2) 'receipt exact pair remains one module'
Write-Output 'receipt isolation exact registration 13 assertions PASS (policy only; not Java execution)'
# 2026-11-18: C-group stock derivation/projection/planning remain three exact owners.
$stockCases=@(
    @{Module='world-state-core';Class='com.dwinovo.numen.worldstate.core.derive.SelfStockDerivationTest'},
    @{Module='plugins:worldstate';Class='com.dwinovo.numen.plugins.worldstate.SelfStockProjectionTest'},
    @{Module='plugins:rdd';Class='com.dwinovo.numen.plugins.rdd.RddPlanningStockFactTest'}
)
foreach($stockCase in $stockCases){
    $stockPlan=Get-RddTestOnlyPlan -Module $stockCase.Module -Tests @($stockCase.Class)
    Assert ($stockPlan.Module -ceq $stockCase.Module -and $stockPlan.Task -ceq (':'+$stockCase.Module+':test') -and $stockPlan.Tests.Count -eq 1 -and $stockPlan.Tests[0] -ceq $stockCase.Class) 'stock consumer keeps exact module/task/class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($stockCase.Class)).Module -ceq $stockCase.Module) 'stock consumer has one inferred owner'
    foreach($wrong in @('world-state-core','plugins:worldstate','plugins:rdd') | Where-Object {$_ -cne $stockCase.Module}){MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($stockCase.Class)}}
    MustReject {Get-RddTestOnlyPlan -Module $stockCase.Module -Tests @($stockCase.Class.ToLowerInvariant())}
    MustReject {Get-RddTestOnlyPlan -Module $stockCase.Module -Tests @($stockCase.Class+'Helper')}
    MustReject {Get-RddTestOnlyPlan -Module $stockCase.Module -Tests @($stockCase.Class+'*')}
}
MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($stockCases[0].Class,$stockCases[1].Class)}
Write-Output 'stock exact registration 22 assertions PASS (policy only; not Java execution)'
# 2026-11-18: explicit B owner consumer and C named neighbors, never package admission.
$ownerStockNeighbors=@(
    @{Module='plugins:rdd';Class='com.dwinovo.numen.plugins.rdd.RddPlanningHpFactTest'},
    @{Module='plugins:worldstate';Class='com.dwinovo.numen.plugins.worldstate.ObservationResponsesTest'},
    @{Module='plugins:worldstate';Class='com.dwinovo.numen.plugins.worldstate.SelfSampleReaderTest'},
    @{Module='plugins:acx';Class='com.dwinovo.numen.acx.test.AcxSessionOwnerConsumerTest'}
)
foreach($neighbor in $ownerStockNeighbors){
    $neighborPlan=Get-RddTestOnlyPlan -Module $neighbor.Module -Tests @($neighbor.Class)
    Assert ($neighborPlan.Module -ceq $neighbor.Module -and $neighborPlan.Task -ceq (':'+$neighbor.Module+':test') -and $neighborPlan.Tests.Count -eq 1 -and $neighborPlan.Tests[0] -ceq $neighbor.Class) 'owner/stock neighbor keeps exact module/task/class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($neighbor.Class)).Module -ceq $neighbor.Module) 'owner/stock neighbor has one inferred owner'
    foreach($wrong in @('plugins:rdd','plugins:worldstate','plugins:acx') | Where-Object {$_ -cne $neighbor.Module}){MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($neighbor.Class)}}
    MustReject {Get-RddTestOnlyPlan -Module $neighbor.Module -Tests @($neighbor.Class.ToLowerInvariant())}
    MustReject {Get-RddTestOnlyPlan -Module $neighbor.Module -Tests @($neighbor.Class+'Helper')}
    MustReject {Get-RddTestOnlyPlan -Module $neighbor.Module -Tests @($neighbor.Class+'*')}
}
Write-Output 'owner and stock neighbors exact registration 28 assertions PASS (policy only; not Java execution)'
# 2026-11-18: exact three-entry planning final-content consumer for the stock residual.
$planRequestTest='com.dwinovo.numen.plugins.rdd.RddPlanningStockRequestTest'
$planRequestPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planRequestTest)
Assert ($planRequestPlan.Module -ceq 'plugins:rdd' -and $planRequestPlan.Task -ceq ':plugins:rdd:test' -and $planRequestPlan.Tests.Count -eq 1 -and $planRequestPlan.Tests[0] -ceq $planRequestTest) 'planning stock request keeps exact module/task/class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($planRequestTest)).Module -ceq 'plugins:rdd') 'planning stock request has one inferred owner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($planRequestTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planRequestTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planRequestTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planRequestTest+'*')}
Write-Output 'planning stock request exact registration 7 assertions PASS (policy only; not Java execution)'
# 2026-11-18: exact B host consumer lives in plugins.acx, not the test package.
$boundHostTest='com.dwinovo.numen.plugins.acx.AcxBoundHostConsumerTest'
$boundHostPlan=Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($boundHostTest)
Assert ($boundHostPlan.Module -ceq 'plugins:acx' -and $boundHostPlan.Task -ceq ':plugins:acx:test' -and $boundHostPlan.Tests.Count -eq 1 -and $boundHostPlan.Tests[0] -ceq $boundHostTest) 'bound host keeps exact module/task/class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($boundHostTest)).Module -ceq 'plugins:acx') 'bound host has one inferred owner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($boundHostTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($boundHostTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($boundHostTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($boundHostTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @('com.dwinovo.numen.acx.test.AcxBoundHostConsumerTest')}
Write-Output 'bound host exact registration 7 assertions PASS (policy only; not Java execution)'
# 2026-11-18: B real CompanionBridge/FacadeTools consumer, exact class only.
$bridgeTest='com.dwinovo.numen.plugins.acx.AcxCompanionBridgeConsumerTest'
$bridgePlan=Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($bridgeTest)
Assert ($bridgePlan.Module -ceq 'plugins:acx' -and $bridgePlan.Task -ceq ':plugins:acx:test' -and $bridgePlan.Tests.Count -eq 1 -and $bridgePlan.Tests[0] -ceq $bridgeTest) 'companion bridge keeps exact module/task/class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($bridgeTest)).Module -ceq 'plugins:acx') 'companion bridge has one inferred owner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($bridgeTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($bridgeTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($bridgeTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($bridgeTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @('com.dwinovo.numen.acx.test.AcxCompanionBridgeConsumerTest')}
Write-Output 'companion bridge exact registration 7 assertions PASS (policy only; not Java execution)'
# 2026-11-18: exact known-backup selector consumer for the 174 next batch.
$baseReserveTest='com.dwinovo.numen.plugins.rdd.RddBaseReserveTest'
$baseReservePlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseReserveTest)
Assert ($baseReservePlan.Module -ceq 'plugins:rdd' -and $baseReservePlan.Task -ceq ':plugins:rdd:test' -and $baseReservePlan.Tests.Count -eq 1 -and $baseReservePlan.Tests[0] -ceq $baseReserveTest) 'base reserve keeps exact module/task/class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($baseReserveTest)).Module -ceq 'plugins:rdd') 'base reserve has one inferred owner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($baseReserveTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseReserveTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseReserveTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseReserveTest+'*')}
Write-Output 'base reserve exact registration 7 assertions PASS (policy only; not Java execution)'
# LH2 preparation: one existing farm consumer, never a package-prefix release.
$farmTest='com.dwinovo.numen.acx.test.AcxFarmContinueOfflineTest'
$farmPlan=Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($farmTest)
Assert ($farmPlan.Module -ceq 'plugins:acx' -and $farmPlan.Task -ceq ':plugins:acx:test' -and $farmPlan.Tests.Count -eq 1 -and $farmPlan.Tests[0] -ceq $farmTest) 'farm consumer keeps its exact module and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($farmTest)).Module -ceq 'plugins:acx') 'farm consumer has one inferred owner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($farmTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($farmTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($farmTest+'Helper')}
Write-Output 'farm preparation exact registration 5 assertions PASS (policy only; not Java execution)'

# Exact existing assembler consumer only; no retrieval package or adjacent class admission.
$assemblerTest='com.dwinovo.numen.agent.retrieval.MinimalContextAssemblerTest'
$assemblerPlan=Get-RddTestOnlyPlan -Module 'ai' -Tests @($assemblerTest)
Assert ($assemblerPlan.Module -ceq 'ai' -and $assemblerPlan.Task -ceq ':ai:test' -and $assemblerPlan.Tests.Count -eq 1 -and $assemblerPlan.Tests[0] -ceq $assemblerTest) 'assembler maps only the exact ai task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($assemblerTest)).Module -ceq 'ai') 'assembler has one inferred owner ai'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests @($assemblerTest)}
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @($assemblerTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @('com.dwinovo.numen.agent.retrieval.MinimalContextAssemblerAdjacentTest')}
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @($assemblerTest+'Helper')}
Write-Output 'assembler exact registration 6 assertions PASS (policy only; not Java execution)'
# 2026-11-13: exact learner mapping and registered dispatch consumers; no wildcard widening.
$dispatchTests=@('com.dwinovo.numen.plugins.learner.LearnerPluginDeliveryMappingTest','com.dwinovo.numen.plugins.learner.DeliveryDispatchIntegrationTest')
foreach($dispatchTest in $dispatchTests){
    $dispatchPlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($dispatchTest)
    Assert ($dispatchPlan.Task -ceq ':plugins:learner:test' -and $dispatchPlan.Tests.Count -eq 1) 'mapping/dispatch must map only the exact learner task'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($dispatchTest)).Module -ceq 'plugins:learner') 'learner dispatch has one inferred module'
    foreach($wrongModule in @('api:common','ai','plugins:rdd')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($dispatchTest)}}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($dispatchTest+'*')}
}
$dispatchPair=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $dispatchTests
Assert ($dispatchPair.Tests.Count -eq 2 -and $dispatchPair.Task -ceq ':plugins:learner:test') 'both exact learner consumers may run together'
Write-Output 'C1 learner mapping/dispatch 13 assertions PASS (policy only; not Java execution)'
# 2026-11-14: exact ReviewObservation + MonitorJournal learner tests; adjacent names stay rejected.
$reviewObservationTests=@(
    'com.dwinovo.numen.plugins.learner.LearnerReviewObservationTest',
    'com.dwinovo.numen.plugins.learner.LearnerMonitorJournalTest'
)
foreach($reviewObservationTest in $reviewObservationTests){
    $reviewObservationPlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewObservationTest)
    Assert ($reviewObservationPlan.Task -ceq ':plugins:learner:test' -and $reviewObservationPlan.Tests.Count -eq 1) 'new learner review/monitor test maps only learner task'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($reviewObservationTest)).Module -ceq 'plugins:learner') 'new learner review/monitor test has one inferred owner'
    foreach($wrongModule in @('api:common','ai','plugins:rdd','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($reviewObservationTest)}}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewObservationTest+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewObservationTest.ToLowerInvariant())}
}
$reviewObservationPair=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $reviewObservationTests
Assert ($reviewObservationPair.Tests.Count -eq 2 -and $reviewObservationPair.Task -ceq ':plugins:learner:test') 'both exact new learner review/monitor tests may run together'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.LearnerReviewObservationAdjacentTest')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.LearnerMonitorJournalTestHelper')}
Write-Output 'new learner review/monitor exact registration 19 assertions PASS (policy only; not Java execution)'
# 2026-11-13: narrow survival intent consumer, not a generic RDD test prefix.
$survivalIntentTest='com.dwinovo.numen.plugins.rdd.RddSurvivalIntentTest'
$survivalIntentPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($survivalIntentTest)
Assert ($survivalIntentPlan.Task -ceq ':plugins:rdd:test' -and $survivalIntentPlan.Tests.Count -eq 1) 'survival intent maps only the RDD plugin test task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($survivalIntentTest)).Module -ceq 'plugins:rdd') 'survival intent has one inferred owner'
foreach($wrongModule in @('api:common','ai','plugins:learner','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($survivalIntentTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddSurvivalIntent*')}
Write-Output 'survival intent exact registration 7 assertions PASS (policy only; not Java execution)'
# 2026-11-13: exact skill intake and adjacent storm guard consumers only.
$intakeTests=@('com.dwinovo.numen.plugins.learner.core.SkillDeliveryIntakeTest','com.dwinovo.numen.plugins.learner.core.StormGuardTest')
foreach($intakeTest in $intakeTests){
    $intakePlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($intakeTest)
    Assert ($intakePlan.Task -ceq ':plugins:learner:test' -and $intakePlan.Tests.Count -eq 1) 'intake/storm guard maps only the exact learner task'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($intakeTest)).Module -ceq 'plugins:learner') 'intake/storm guard has one inferred owner'
    foreach($wrongModule in @('api:common','ai','plugins:rdd','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($intakeTest)}}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($intakeTest+'*')}
}
$intakePair=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $intakeTests
Assert ($intakePair.Task -ceq ':plugins:learner:test' -and $intakePair.Tests.Count -eq 2) 'both exact learner intake controls may run together'
Write-Output 'skill intake/storm guard 15 assertions PASS (policy only; not Java execution)'
$test='com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest'
$p=Get-RddTestOnlyPlan -Module ' plugins:rdd ' -Tests @($test)
$inferred=Get-RddTestOnlyPlan -Module '' -Tests @('com.dwinovo.numen.plugins.rdd.RddStagePlannerParseTest')
Assert ($inferred.Task -ceq ':plugins:rdd:test') 'single-owner inference must pick plugins:rdd'
MustReject { Get-RddTestOnlyPlan -Module '' -Tests @('com.dwinovo.numen.plugins.rdd.RddStagePlannerParseTest','com.dwinovo.numen.monitor.WorldContextStampTest') }
MustReject { Get-RddTestOnlyPlan -Module '' -Tests @() }
$ws=Get-RddTestOnlyPlan -Module 'world-state-core' -Tests @('com.dwinovo.numen.worldstate.core.model.WorldIdentityTest')
Assert ($ws.Task -ceq ':world-state-core:test') 'world-state task must be fixed'
Assert ($p.Task -ceq ':plugins:rdd:test') 'task must be fixed'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd:jar' -Tests @($test) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('*.test') }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @() }
MustReject { Get-RddTestOnlyPlan -Module 'core:neoforge' -Tests @($test) }
$id = Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.monitor.WorldContextStampTest')
Assert ($id.Task -ceq ':api:common:test') 'api task must be fixed'
MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @($test) }
MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.monitor.WorldContextStampTest*') }
# 2026-11-12: admit only the frozen host-successor consumer, never a wildcard or another module.
$deathHostTest = 'com.dwinovo.numen.plugins.rdd.RddDeathPreparationHostSuccessorTest'
$deathHostPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($deathHostTest)
Assert ($deathHostPlan.Task -ceq ':plugins:rdd:test' -and $deathHostPlan.Tests.Count -eq 1) 'death host successor maps only to the exact RDD plugin test task'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($deathHostTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddDeathPreparationHost*')}
$mineRecoveryTest = 'com.dwinovo.numen.core.task.mine.MineHarvestRecoveryConsumerTest'
$mineRecoveryPlan = Get-RddTestOnlyPlan -Module 'core:common' -Tests @($mineRecoveryTest)
Assert ($mineRecoveryPlan.Task -ceq ':core:common:test' -and $mineRecoveryPlan.Tests.Count -eq 1) 'mine recovery consumer runs only core common'
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($mineRecoveryTest)}
MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @('com.dwinovo.numen.core.task.mine.MineHarvest*')}
$transportExternalTest = 'com.dwinovo.numen.client.agent.ServerToolTransportExternalNamespaceTest'
$transportExternalPlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($transportExternalTest)
Assert ($transportExternalPlan.Task -ceq ':api:common:test' -and $transportExternalPlan.Tests.Count -eq 1) 'external namespace routing stays on api common'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($transportExternalTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.client.agent.ServerToolTransportExternal*')}
$transportBindingTest = 'com.dwinovo.numen.client.agent.ServerToolTransportBindingTest'
$transportBindingPlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($transportBindingTest)
Assert ($transportBindingPlan.Task -ceq ':api:common:test' -and $transportBindingPlan.Tests.Count -eq 1) 'transport binding uses only api common'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($transportBindingTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.client.agent.ServerToolTransportBinding*')}
$transportReplyTest = 'com.dwinovo.numen.client.agent.ServerToolTransportReplyIsolationTest'
$transportReplyPlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($transportReplyTest)
Assert ($transportReplyPlan.Task -ceq ':api:common:test' -and $transportReplyPlan.Tests.Count -eq 1) 'transport reply isolation maps only to api common'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($transportReplyTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.client.agent.ServerToolTransport*')}
# 2026-11-14: exact temporary entity protection offline consumer; adjacent names refused.
$temporaryProtectionTest='com.dwinovo.numen.entity.TemporaryEntityProtectionTest'
$temporaryProtectionPlan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($temporaryProtectionTest)
Assert ($temporaryProtectionPlan.Task -ceq ':api:common:test' -and $temporaryProtectionPlan.Tests.Count -eq 1) 'temporary entity protection maps only api common test task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($temporaryProtectionTest)).Module -ceq 'api:common') 'temporary entity protection has one inferred owner'
foreach($wrongModule in @('ai','plugins:learner','plugins:rdd','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($temporaryProtectionTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($temporaryProtectionTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($temporaryProtectionTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.entity.TemporaryEntityProtectionAdjacentTest')}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.entity.TemporaryEntityProtectionTestHelper')}
Write-Output 'temporary entity protection exact registration 10 assertions PASS (policy only; not Java execution)'
$sleepHandoffTest = 'com.dwinovo.numen.api.SleepHandoffConsumerTest'
$sleepHandoffPlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($sleepHandoffTest)
Assert ($sleepHandoffPlan.Task -ceq ':api:common:test') 'sleep handoff maps only to api common'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($sleepHandoffTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.api.SleepHandoff*')}
$sleepQueueTest = 'com.dwinovo.numen.client.agent.SleepQueueGenerationTest'
$sleepQueuePlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($sleepQueueTest)
Assert ($sleepQueuePlan.Task -ceq ':api:common:test' -and $sleepQueuePlan.Tests.Count -eq 1) 'sleep queue consumer maps only to api common'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($sleepQueueTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.client.agent.SleepQueue*')}
$cameraTests = @('com.dwinovo.numen.plugins.camera.possess.PossessionRefreshWiringTest','com.dwinovo.numen.plugins.camera.possess.FollowRefreshTest')
$cameraPlan = Get-RddTestOnlyPlan -Module 'plugins:camera' -Tests $cameraTests
Assert ($cameraPlan.Task -ceq ':plugins:camera:test' -and $cameraPlan.Tests.Count -eq 2) 'camera refresh tests must map only to camera'
foreach($cameraTest in $cameraTests){MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($cameraTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:camera' -Tests @('com.dwinovo.numen.plugins.camera.possess.*')}
$sealTests = @('com.dwinovo.numen.plugins.camera.rec.SealLaunchTest','com.dwinovo.numen.plugins.camera.rec.VideoRecorderSealWiringPinTest')
$sealPlan = Get-RddTestOnlyPlan -Module 'plugins:camera' -Tests $sealTests
Assert ($sealPlan.Task -ceq ':plugins:camera:test' -and $sealPlan.Tests.Count -eq 2) 'exact seal regressions map only to camera'
foreach($n in $sealTests){MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($n)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:camera' -Tests @('com.dwinovo.numen.plugins.camera.rec.*')}
$acxLocationTest = 'com.dwinovo.numen.acx.test.AcxArtifactLocationScopeTest'
$acxLocationPlan = Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @($acxLocationTest)
Assert ($acxLocationPlan.Task -ceq ':plugins:acx:test' -and $acxLocationPlan.Tests.Count -eq 1) 'ACX artifact location uses only the exact ACX task'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($acxLocationTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:acx' -Tests @('com.dwinovo.numen.acx.test.*')}
$locationTest = 'com.dwinovo.numen.plugins.learner.skills.SkillLocationScopeDeliveryTest'
$locationPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($locationTest)
Assert ($locationPlan.Task -ceq ':plugins:learner:test' -and $locationPlan.Tests.Count -eq 1) 'location scope delivery uses only the exact learner test task'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($locationTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.skills.SkillLocation*')}
$locationCompat = @('com.dwinovo.numen.plugins.learner.skills.SkillRegistrarTest','com.dwinovo.numen.plugins.learner.core.ArtifactOutboxTest','com.dwinovo.numen.plugins.learner.contract.ArtifactValidatorTest')
$locationCompatPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $locationCompat
Assert ($locationCompatPlan.Task -ceq ':plugins:learner:test' -and $locationCompatPlan.Tests.Count -eq 3) 'location adjacent compatibility stays on learner task'
foreach($n in $locationCompat){MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($n)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.core.Artifact*')}
$accountingTest = 'com.dwinovo.numen.plugins.learner.skills.SkillsAccountingTest'
$accountingPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($accountingTest)
Assert ($accountingPlan.Task -ceq ':plugins:learner:test' -and $accountingPlan.Tests.Count -eq 1) 'skill accounting must map only to learner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($accountingTest)}
$maidSelfTest = 'com.dwinovo.numen.plugins.maidlink.MaidSelfHostContractTest'
$maidSelfPlan = Get-RddTestOnlyPlan -Module 'plugins:maidlink' -Tests @($maidSelfTest)
Assert ($maidSelfPlan.Task -ceq ':plugins:maidlink:test' -and $maidSelfPlan.Tests.Count -eq 1) 'maid SELF host test must map only to its optional plugin'
MustReject { Get-RddTestOnlyPlan -Module 'maid-link-core' -Tests @($maidSelfTest) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:maidlink' -Tests @('com.dwinovo.numen.plugins.maidlink.MaidSelfHost*') }
$skillTests = @('com.dwinovo.numen.plugins.learner.skills.SkillBodyDeliveryIntegrityTest', 'com.dwinovo.numen.plugins.learner.skills.SkillBodyStoreTest')
$skillPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $skillTests
Assert ($skillPlan.Task -ceq ':plugins:learner:test' -and $skillPlan.Tests.Count -eq 2) 'skill delivery tests must map to the learner test task'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.skills.SkillBody*') }
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests $skillTests }
$journalApiTest = 'com.dwinovo.numen.monitor.MonitoringJournalAcceptedTest'
$journalPluginTest = 'com.dwinovo.numen.plugins.rdd.RddMonitorJournalTest'
$journalApiPlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($journalApiTest)
$journalPluginPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($journalPluginTest)
Assert ($journalApiPlan.Task -ceq ':api:common:test' -and $journalApiPlan.Tests.Count -eq 1) 'journal acceptance maps only to api common'
Assert ($journalPluginPlan.Task -ceq ':plugins:rdd:test' -and $journalPluginPlan.Tests.Count -eq 1) 'rdd journal adapter maps only to rdd plugin'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($journalApiTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($journalPluginTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.monitor.MonitoringJournal*')}
$alarmTest = 'com.dwinovo.numen.plugins.rdd.RddAlarmResponseTextTest'
$alarmPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($alarmTest)
Assert ($alarmPlan.Task -ceq ':plugins:rdd:test' -and $alarmPlan.Tests.Count -eq 1) 'alarm response must map only to rdd plugin'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($alarmTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddAlarmResponse*')}
$sleepCoreTests = @('com.dwinovo.numen.rdd.side.SleepRiskPreemptionTest','com.dwinovo.numen.rdd.side.SleepSideTaskSpawnBindTest','com.dwinovo.numen.rdd.side.SideTaskDeclineTest')
$sleepHostTest = 'com.dwinovo.numen.plugins.rdd.SleepRiskHostTest'
$sleepCorePlan = Get-RddTestOnlyPlan -Module 'rdd-core' -Tests $sleepCoreTests
$sleepHostPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($sleepHostTest)
Assert ($sleepCorePlan.Task -ceq ':rdd-core:test' -and $sleepCorePlan.Tests.Count -eq 3) 'sleep core and lifecycle use exact core task'
Assert ($sleepHostPlan.Task -ceq ':plugins:rdd:test' -and $sleepHostPlan.Tests.Count -eq 1) 'sleep handoff uses exact host task'
foreach($n in $sleepCoreTests){MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($n)}}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($sleepHostTest)}

# 2026-11-13: exact food-supply admission priority consumer; rdd-core only, no wildcard or plugins:rdd widening.
$foodSupplyPriorityTest='com.dwinovo.numen.rdd.side.FoodSupplyAdmissionPriorityTest'
$foodSupplyPriorityPlan=Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($foodSupplyPriorityTest)
Assert ($foodSupplyPriorityPlan.Task -ceq ':rdd-core:test' -and $foodSupplyPriorityPlan.Tests.Count -eq 1) 'food supply priority must map only the exact rdd-core task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($foodSupplyPriorityTest)).Module -ceq 'rdd-core') 'food supply priority has one inferred owner rdd-core'
foreach($wrongModule in @('plugins:rdd','plugins:learner','api:common','ai')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($foodSupplyPriorityTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($foodSupplyPriorityTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($foodSupplyPriorityTest.ToLowerInvariant())}
Write-Output 'food supply priority exact registration 8 assertions PASS (policy only; not Java execution)'
# 2026-11-15: exact CompletedFactStore consumer; rdd-core only, adjacent names refused.
$completedFactStoreTest='com.dwinovo.numen.rdd.core.CompletedFactStoreTest'
$completedFactStorePlan=Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($completedFactStoreTest)
Assert ($completedFactStorePlan.Task -ceq ':rdd-core:test' -and $completedFactStorePlan.Tests.Count -eq 1) 'completed fact store must map only the exact rdd-core task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($completedFactStoreTest)).Module -ceq 'rdd-core') 'completed fact store has one inferred owner rdd-core'
foreach($wrongModule in @('api:common','ai','plugins:learner','plugins:rdd')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($completedFactStoreTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($completedFactStoreTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($completedFactStoreTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.core.CompletedFactStoreAdjacentTest')}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.core.CompletedFactStoreTestHelper')}
Write-Output 'completed fact store exact registration 10 assertions PASS (policy only; not Java execution)'
$deathPrepareTest = 'com.dwinovo.numen.rdd.side.death.DeathPreparationRegressionTest'
$deathPreparePlan = Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($deathPrepareTest)
Assert ($deathPreparePlan.Task -ceq ':rdd-core:test' -and $deathPreparePlan.Tests.Count -eq 1) 'death preparation must map only to rdd core'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($deathPrepareTest)}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.side.death.*')}
$recoveryCoreTests = @('com.dwinovo.numen.rdd.side.death.DeathPreparationFlowTest','com.dwinovo.numen.rdd.side.death.DeathPreparationScopeRegressionTest','com.dwinovo.numen.rdd.side.death.DeathRecoverySideTaskTypeTest','com.dwinovo.numen.rdd.side.death.DeathRecoveryDecisionTest','com.dwinovo.numen.rdd.policy.LossImpactAnalyzerTest','com.dwinovo.numen.rdd.core.TaskChainStickyNeedsTest','com.dwinovo.numen.rdd.core.TaskChainRestartRoundTripTest','com.dwinovo.numen.rdd.side.SleepRiskPreemptionTest')
$recoveryHostTests = @('com.dwinovo.numen.plugins.rdd.RddDeathEquipmentTest','com.dwinovo.numen.plugins.rdd.RddDeathPreparationWiringTest','com.dwinovo.numen.plugins.rdd.RddFactContextStickyNeedsTest')
$recoveryCorePlan = Get-RddTestOnlyPlan -Module 'rdd-core' -Tests $recoveryCoreTests
$recoveryHostPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests $recoveryHostTests
Assert ($recoveryCorePlan.Task -ceq ':rdd-core:test' -and $recoveryCorePlan.Tests.Count -eq 8) 'recovery and sleep core tests use exact core task'
Assert ($recoveryHostPlan.Task -ceq ':plugins:rdd:test' -and $recoveryHostPlan.Tests.Count -eq 3) 'recovery host tests use exact plugin task'
foreach($n in $recoveryCoreTests){MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($n)}}
foreach($n in $recoveryHostTests){MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($n)}}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.side.SleepRisk*')}
$basePlaybookTest = 'com.dwinovo.numen.plugins.rdd.RddBasePlaybookTest'
$basePlaybookPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($basePlaybookTest)
Assert ($basePlaybookPlan.Task -ceq ':plugins:rdd:test' -and $basePlaybookPlan.Tests.Count -eq 1) 'base playbook consumer must map only to rdd plugin'
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($basePlaybookTest) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddBasePlaybook*') }
$candidateTest = 'com.dwinovo.numen.plugins.learner.core.CandidateGateTest'
$candidatePlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($candidateTest)
Assert ($candidatePlan.Task -ceq ':plugins:learner:test' -and $candidatePlan.Tests.Count -eq 1) 'candidate gate test must map only to the learner task'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.core.CandidateGate*') }
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($candidateTest) }
$announceTest = 'com.dwinovo.numen.plugins.learner.core.AnnounceTextTest'
$announcePlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($announceTest)
Assert ($announcePlan.Task -ceq ':plugins:learner:test' -and $announcePlan.Tests.Count -eq 1) 'announce text test must map only to the learner task'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.core.AnnounceText*') }
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($announceTest) }
$evidenceTest = 'com.dwinovo.numen.plugins.learner.core.ExperienceSevenFieldsTest'
$evidencePlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($evidenceTest)
Assert ($evidencePlan.Task -ceq ':plugins:learner:test' -and $evidencePlan.Tests.Count -eq 1) 'experience evidence test must map only to the learner task'
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($evidenceTest) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.core.ExperienceSevenFields*') }
$reviewerEvidenceTest = 'com.dwinovo.numen.plugins.learner.LearnerReviewerEvidenceTest'
$reviewerEvidencePlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewerEvidenceTest)
Assert ($reviewerEvidencePlan.Task -ceq ':plugins:learner:test' -and $reviewerEvidencePlan.Tests.Count -eq 1) 'reviewer evidence test must map only to the learner task'
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($reviewerEvidenceTest) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.LearnerReviewerEvidence*') }
$skillsAggregateTest = 'com.dwinovo.numen.plugins.learner.skills.SkillsAggregateConsumerTest'
$skillsAggregatePlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($skillsAggregateTest)
Assert ($skillsAggregatePlan.Task -ceq ':plugins:learner:test' -and $skillsAggregatePlan.Tests.Count -eq 1) 'skills aggregate consumer must map only to learner'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($skillsAggregateTest) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.skills.SkillsAggregate*') }
$taskRecordTest = 'com.dwinovo.numen.task.TaskRecordTest'
$taskRecordPlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests @($taskRecordTest)
Assert ($taskRecordPlan.Task -ceq ':api:common:test' -and $taskRecordPlan.Tests.Count -eq 1) 'task record binding test must map only to api common'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($taskRecordTest) }
MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.task.TaskRecord*') }
$skillFeedbackTest = 'com.dwinovo.numen.plugins.learner.LearnerSkillTaskFeedbackTest'
$skillFeedbackPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($skillFeedbackTest)
Assert ($skillFeedbackPlan.Task -ceq ':plugins:learner:test' -and $skillFeedbackPlan.Tests.Count -eq 1) 'skill task feedback test must map only to learner'
MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @($skillFeedbackTest) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.LearnerSkillTaskFeedback*') }

# 2026-11-13: exact task-result intake consumer only; no wildcard or cross-module registration.
$taskResultIntakeTest='com.dwinovo.numen.plugins.learner.LearnerTaskResultIntakeTest'
$taskResultIntakePlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($taskResultIntakeTest)
Assert ($taskResultIntakePlan.Task -ceq ':plugins:learner:test' -and $taskResultIntakePlan.Tests.Count -eq 1) 'task result intake must map only the exact learner task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($taskResultIntakeTest)).Module -ceq 'plugins:learner') 'task result intake has one inferred owner'
foreach($wrongModule in @('api:common','ai','plugins:rdd','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($taskResultIntakeTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($taskResultIntakeTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($taskResultIntakeTest.ToLowerInvariant())}
Write-Output 'task result intake exact registration 8 assertions PASS (policy only; not Java execution)'
# 2026-11-13: persisted review-state red consumer must stay exact and learner-owned; no prefix widening.
$reviewStatePersistenceTest='com.dwinovo.numen.plugins.learner.ReviewStatePersistenceRedTest'
$reviewStatePersistencePlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewStatePersistenceTest)
Assert ($reviewStatePersistencePlan.Module -ceq 'plugins:learner' -and $reviewStatePersistencePlan.Task -ceq ':plugins:learner:test' -and $reviewStatePersistencePlan.Tests.Count -eq 1 -and $reviewStatePersistencePlan.Tests[0] -ceq $reviewStatePersistenceTest) 'review state persistence maps only its exact learner class and task'
$reviewStatePersistenceInferred=Get-RddTestOnlyPlan -Module '' -Tests @($reviewStatePersistenceTest)
Assert ($reviewStatePersistenceInferred.Module -ceq 'plugins:learner' -and $reviewStatePersistenceInferred.Task -ceq ':plugins:learner:test' -and $reviewStatePersistenceInferred.Tests.Count -eq 1 -and $reviewStatePersistenceInferred.Tests[0] -ceq $reviewStatePersistenceTest) 'review state persistence has one inferred learner owner and exact class'
foreach($wrongModule in @('api:common','ai','plugins:rdd','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($reviewStatePersistenceTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewStatePersistenceTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewStatePersistenceTest+'*')}
Write-Output 'review state persistence exact registration 8 assertions PASS (policy only; not Java execution)'
# Exact file/Gson, host-lock and pre-move read-refusal consumer; not native or move-failure proof.
$reviewStateFileConsumer='com.dwinovo.numen.plugins.learner.ReviewStateFileConsumerTest'
$reviewStateFilePlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewStateFileConsumer)
Assert ($reviewStateFilePlan.Task -ceq ':plugins:learner:test' -and $reviewStateFilePlan.Module -ceq 'plugins:learner' -and $reviewStateFilePlan.Tests.Count -eq 1 -and $reviewStateFilePlan.Tests[0] -ceq $reviewStateFileConsumer) 'review state file consumer preserves exact module, task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($reviewStateFileConsumer)).Module -ceq 'plugins:learner') 'review state file consumer has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($reviewStateFileConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($reviewStateFileConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewStateFileConsumer+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reviewStateFileConsumer+'Helper')}
Write-Output 'Review state file consumer exact registration 6 assertions PASS (policy only; not Java execution)'
# 2026-11-13: real scanOnce task-result host consumer must stay exact and learner-owned; no prefix widening.
$autoTaskResultIntakeTest='com.dwinovo.numen.plugins.learner.LearnerAutoTaskResultIntakeTest'
$autoTaskResultIntakePlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($autoTaskResultIntakeTest)
Assert ($autoTaskResultIntakePlan.Module -ceq 'plugins:learner' -and $autoTaskResultIntakePlan.Task -ceq ':plugins:learner:test' -and $autoTaskResultIntakePlan.Tests.Count -eq 1 -and $autoTaskResultIntakePlan.Tests[0] -ceq $autoTaskResultIntakeTest) 'auto task result intake maps only its exact learner class and task'
$autoTaskResultIntakeInferred=Get-RddTestOnlyPlan -Module '' -Tests @($autoTaskResultIntakeTest)
Assert ($autoTaskResultIntakeInferred.Module -ceq 'plugins:learner' -and $autoTaskResultIntakeInferred.Task -ceq ':plugins:learner:test' -and $autoTaskResultIntakeInferred.Tests.Count -eq 1 -and $autoTaskResultIntakeInferred.Tests[0] -ceq $autoTaskResultIntakeTest) 'auto task result intake has one inferred learner owner and exact class'
foreach($wrongModule in @('api:common','ai','plugins:rdd','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($autoTaskResultIntakeTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($autoTaskResultIntakeTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($autoTaskResultIntakeTest+'*')}
Write-Output 'auto task result intake exact registration 8 assertions PASS (policy only; not Java execution)'
$publicationTests = @(
    'com.dwinovo.numen.plugins.learner.skills.PublishBoundaryBodyTest',
    'com.dwinovo.numen.plugins.learner.skills.SkillRegistryPromoteTest',
    'com.dwinovo.numen.plugins.learner.skills.SkillCatalogViewTest',
    'com.dwinovo.numen.plugins.learner.skills.SkillRegistrarSharedRegistryTest',
    'com.dwinovo.numen.plugins.learner.skills.SkillsGapTest',
    'com.dwinovo.numen.plugins.learner.skills.SkillsKnowledgeContributorTest'
)
$publicationPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $publicationTests
Assert ($publicationPlan.Task -ceq ':plugins:learner:test' -and $publicationPlan.Tests.Count -eq 6) 'public skill publication regressions must map only to learner'
foreach ($publicationTest in $publicationTests) { MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($publicationTest) } }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.skills.*') }
$recurringTest = 'com.dwinovo.numen.rdd.side.SideTaskRecurringTest'
$recurringPlan = Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($recurringTest)
Assert ($recurringPlan.Task -ceq ':rdd-core:test' -and $recurringPlan.Tests.Count -eq 1) 'recurring goal qualification test must map only to rdd core'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($recurringTest) }
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.side.SideTaskRecurring*') }
$dailyCoreTest = 'com.dwinovo.numen.rdd.core.TaskChainDailyDispatchTest'
$dailyShellTest = 'com.dwinovo.numen.plugins.rdd.RddGoalDriverInjectionTest'
$dailyCorePlan = Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($dailyCoreTest)
$dailyShellPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($dailyShellTest)
Assert ($dailyCorePlan.Task -ceq ':rdd-core:test' -and $dailyCorePlan.Tests.Count -eq 1) 'daily dispatch test must map only to the core task'
Assert ($dailyShellPlan.Task -ceq ':plugins:rdd:test' -and $dailyShellPlan.Tests.Count -eq 1) 'daily injection test must map only to the plugin task'
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.core.TaskChainDaily*') }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddGoalDriverInjection*') }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($dailyCoreTest) }
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($dailyShellTest) }

# 2026-11-13: exact planning-observation wiring consumer; plugins:rdd only, journal control stays.
$planningObservationTest='com.dwinovo.numen.plugins.rdd.RddPlanningObservationWiringTest'
$planningObservationPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planningObservationTest)
Assert ($planningObservationPlan.Task -ceq ':plugins:rdd:test' -and $planningObservationPlan.Tests.Count -eq 1) 'planning observation wiring must map only the exact rdd plugin task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($planningObservationTest)).Module -ceq 'plugins:rdd') 'planning observation wiring has one inferred owner plugins:rdd'
foreach($wrongModule in @('api:common','ai','plugins:learner','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($planningObservationTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planningObservationTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($planningObservationTest.ToLowerInvariant())}
$journalControlPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddMonitorJournalTest')
Assert ($journalControlPlan.Task -ceq ':plugins:rdd:test' -and $journalControlPlan.Tests.Count -eq 1) 'existing journal control stays registered'
Write-Output 'planning observation exact registration 9 assertions PASS (policy only; not Java execution)'
# 2026-11-17: exact goto arrival consumer; no wildcard, adjacent class or module widening.
$arrivalTest='com.dwinovo.numen.core.task.move.MoveToArrivalConsumerTest'
$arrivalPlan=Get-RddTestOnlyPlan -Module 'core:common' -Tests @($arrivalTest)
Assert ($arrivalPlan.Task -ceq ':core:common:test' -and $arrivalPlan.Module -ceq 'core:common' -and $arrivalPlan.Tests.Count -eq 1 -and $arrivalPlan.Tests[0] -ceq $arrivalTest) 'arrival consumer keeps the exact core task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($arrivalTest)).Module -ceq 'core:common') 'arrival consumer has one inferred owner'
foreach($wrongModule in @('api:common','plugins:rdd','plugins:learner','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($arrivalTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($arrivalTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($arrivalTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($arrivalTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @('com.dwinovo.numen.core.task.move.MoveToArrivalAdjacentTest')}
Write-Output 'goto arrival consumer exact registration 10 assertions PASS (policy only; not Java execution)'
# Existing Stage-B node/recurrence consumer only; preserve exact module ownership.
$nodeTypeTest='com.dwinovo.numen.plugins.rdd.RddDecomposerNodeTypeTest'
$nodeTypePlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($nodeTypeTest)
Assert ($nodeTypePlan.Task -ceq ':plugins:rdd:test' -and $nodeTypePlan.Tests.Count -eq 1 -and $nodeTypePlan.Tests[0] -ceq $nodeTypeTest) 'Stage-B node consumer keeps the exact task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($nodeTypeTest)).Module -ceq 'plugins:rdd') 'Stage-B node consumer has one inferred owner'
MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($nodeTypeTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($nodeTypeTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($nodeTypeTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($nodeTypeTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($nodeTypeTest.ToLowerInvariant())}
Write-Output 'Stage-B node consumer exact registration 7 assertions PASS (policy only; not Java execution)'
# Exact current inventory projection and original completion consumer; no package widening.
foreach($inventoryConsumer in @('com.dwinovo.numen.plugins.rdd.RddInventoryProjectionTest','com.dwinovo.numen.plugins.rdd.EarlyAchievementInventoryRegressionTest')){
    $inventoryPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($inventoryConsumer)
    Assert ($inventoryPlan.Task -ceq ':plugins:rdd:test' -and $inventoryPlan.Tests.Count -eq 1 -and $inventoryPlan.Tests[0] -ceq $inventoryConsumer) 'inventory consumer keeps exact class and task'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($inventoryConsumer)).Module -ceq 'plugins:rdd') 'inventory consumer has one inferred owner'
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($inventoryConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($inventoryConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($inventoryConsumer+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($inventoryConsumer+'Helper')}
}
Write-Output 'inventory consumers exact registration 12 assertions PASS (policy only; not Java execution)'
# Original budget consumer and the prompt extraction seam only; exact class registration.
foreach($promptConsumer in @('com.dwinovo.numen.plugins.rdd.RddDecomposerAssetBoundsTest','com.dwinovo.numen.plugins.rdd.RddDecomposerPromptDelegationTest')){
    $promptPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($promptConsumer)
    Assert ($promptPlan.Task -ceq ':plugins:rdd:test' -and $promptPlan.Tests.Count -eq 1 -and $promptPlan.Tests[0] -ceq $promptConsumer) 'prompt consumer keeps exact class and task'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($promptConsumer)).Module -ceq 'plugins:rdd') 'prompt consumer has one owner'
    MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($promptConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($promptConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($promptConsumer+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($promptConsumer+'Extra')}
}
Write-Output 'prompt consumers exact registration 12 assertions PASS (policy only; not Java execution)'
# Bounded responsibility-split consumers and original pure early-completion controls.
foreach($consumerSpec in @(@('plugins:rdd','com.dwinovo.numen.plugins.rdd.RddEarlyProposalPublisherTest'),@('plugins:rdd','com.dwinovo.numen.plugins.rdd.RddControlFlagReadsTest'),@('rdd-core','com.dwinovo.numen.rdd.core.EarlyCompletionTest'),@('rdd-core','com.dwinovo.numen.rdd.core.RddEarlyCompletionProposalTest'))){
    $consumerModule=$consumerSpec[0];$consumerClass=$consumerSpec[1]
    $consumerPlan=Get-RddTestOnlyPlan -Module $consumerModule -Tests @($consumerClass)
    Assert ($consumerPlan.Task -ceq (':'+$consumerModule+':test') -and $consumerPlan.Tests.Count -eq 1 -and $consumerPlan.Tests[0] -ceq $consumerClass) 'responsibility consumer maps exact task and class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($consumerClass)).Module -ceq $consumerModule) 'responsibility consumer has one owner'
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($consumerClass)}
    MustReject {Get-RddTestOnlyPlan -Module 'core:common' -Tests @($consumerClass)}
    MustReject {Get-RddTestOnlyPlan -Module $consumerModule -Tests @($consumerClass+'*')}
    MustReject {Get-RddTestOnlyPlan -Module $consumerModule -Tests @($consumerClass+'Helper')}
}
Write-Output 'responsibility consumers exact registration 24 assertions PASS (policy only; not Java execution)'
# Verbatim cold-restore consumer; admission does not claim full Plugin platform coverage.
$restoreConsumer='com.dwinovo.numen.plugins.rdd.RddRuntimeRestoreConsumerTest'
$restorePlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($restoreConsumer)
Assert ($restorePlan.Task -ceq ':plugins:rdd:test' -and $restorePlan.Tests.Count -eq 1 -and $restorePlan.Tests[0] -ceq $restoreConsumer) 'restore consumer preserves exact task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($restoreConsumer)).Module -ceq 'plugins:rdd') 'restore consumer has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($restoreConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($restoreConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($restoreConsumer+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($restoreConsumer+'Helper')}
Write-Output 'restore consumer exact registration 6 assertions PASS (policy only; not Java execution)'
# Exact death-facts consumer and original ledger store; no Java execution or package widening.
foreach($deathConsumer in @('com.dwinovo.numen.plugins.rdd.RddDeathFactsConsumerTest','com.dwinovo.numen.plugins.rdd.RddDeathLedgerStoreTest')){
    $deathPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($deathConsumer)
    Assert ($deathPlan.Task -ceq ':plugins:rdd:test' -and $deathPlan.Tests.Count -eq 1 -and $deathPlan.Tests[0] -ceq $deathConsumer) 'death consumer preserves exact task and class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($deathConsumer)).Module -ceq 'plugins:rdd') 'death consumer has one owner'
    MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($deathConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($deathConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($deathConsumer+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($deathConsumer+'Helper')}
}
Write-Output 'death consumers exact registration 12 assertions PASS (policy only; not Java execution)'
# Exact existing Fact consumers and candidate Carry projection only; admission does not enable disabled Java tests.
foreach($projectionConsumer in @('com.dwinovo.numen.plugins.rdd.RddFactContextTest','com.dwinovo.numen.plugins.rdd.G1b2ManifestCacheTest','com.dwinovo.numen.plugins.rdd.G1bImportanceConsumerTest','com.dwinovo.numen.plugins.rdd.G1c2FingerprintTest','com.dwinovo.numen.plugins.rdd.G1c3TransformAttributionTest','com.dwinovo.numen.plugins.rdd.RddCarryProjectionTest')){
    $projectionPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($projectionConsumer)
    Assert ($projectionPlan.Task -ceq ':plugins:rdd:test' -and $projectionPlan.Tests.Count -eq 1 -and $projectionPlan.Tests[0] -ceq $projectionConsumer) 'projection consumer preserves exact task and class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($projectionConsumer)).Module -ceq 'plugins:rdd') 'projection consumer has one owner'
    MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($projectionConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($projectionConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($projectionConsumer+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($projectionConsumer+'Helper')}
}
Write-Output 'Fact and Carry projection exact registration 36 assertions PASS (policy only; not Java execution)'
# Original pure reservation render/ledger consumer only; preserve exact module and rejection controls.
$reservationConsumer='com.dwinovo.numen.plugins.rdd.G1cReservationWiringTest'
$reservationPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($reservationConsumer)
Assert ($reservationPlan.Task -ceq ':plugins:rdd:test' -and $reservationPlan.Tests.Count -eq 1 -and $reservationPlan.Tests[0] -ceq $reservationConsumer) 'reservation consumer preserves exact task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($reservationConsumer)).Module -ceq 'plugins:rdd') 'reservation consumer has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($reservationConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($reservationConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($reservationConsumer+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($reservationConsumer+'Helper')}
Write-Output 'reservation consumer exact registration 6 assertions PASS (policy only; not Java execution)'
# Exact loss analysis and original bounded Repair consumers; no host launch or policy widening.
foreach($repairConsumer in @('com.dwinovo.numen.plugins.rdd.RddRepairLossAnalysisTest','com.dwinovo.numen.plugins.rdd.RddRepairDispatchTimeoutTest','com.dwinovo.numen.plugins.rdd.RddRepairDispatchPinTest','com.dwinovo.numen.plugins.rdd.S1SemanticsWiringTest','com.dwinovo.numen.plugins.rdd.RddRepairLogPolicyTest')){
    $repairPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($repairConsumer)
    Assert ($repairPlan.Task -ceq ':plugins:rdd:test' -and $repairPlan.Tests.Count -eq 1 -and $repairPlan.Tests[0] -ceq $repairConsumer) 'repair consumer preserves exact task and class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($repairConsumer)).Module -ceq 'plugins:rdd') 'repair consumer has one owner'
    MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($repairConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($repairConsumer)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($repairConsumer+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($repairConsumer+'Helper')}
}
Write-Output 'Repair consumers exact registration 30 assertions PASS (policy only; not Java execution)'
# Exact Base source-slice fixture consumer; admission does not execute Java or native world sampling.
$baseFactsConsumer='com.dwinovo.numen.plugins.rdd.RddBaseFactsConsumerTest'
$baseFactsPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseFactsConsumer)
Assert ($baseFactsPlan.Task -ceq ':plugins:rdd:test' -and $baseFactsPlan.Tests.Count -eq 1 -and $baseFactsPlan.Tests[0] -ceq $baseFactsConsumer) 'base facts consumer preserves exact task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($baseFactsConsumer)).Module -ceq 'plugins:rdd') 'base facts consumer has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($baseFactsConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($baseFactsConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseFactsConsumer+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($baseFactsConsumer+'Helper')}
Write-Output 'Base facts consumer exact registration 6 assertions PASS (policy only; not Java execution)'
# Exact full notification owner plus facade excerpts with bounded IO shells; not client delivery.
$notificationsConsumer='com.dwinovo.numen.plugins.rdd.RddSupervisionNotificationsTest'
$notificationsPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($notificationsConsumer)
Assert ($notificationsPlan.Task -ceq ':plugins:rdd:test' -and $notificationsPlan.Tests.Count -eq 1 -and $notificationsPlan.Tests[0] -ceq $notificationsConsumer) 'notifications consumer preserves exact task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($notificationsConsumer)).Module -ceq 'plugins:rdd') 'notifications consumer has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($notificationsConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($notificationsConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($notificationsConsumer+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($notificationsConsumer+'Helper')}
Write-Output 'Notifications consumer exact registration 6 assertions PASS (policy only; not Java execution)'
# Exact whole failure-recovery owner plus optional-food source with bounded platform shells; not live watchers.
$failureRecoveryConsumer='com.dwinovo.numen.plugins.rdd.RddFailureRecoveryConsumerTest'
$failureRecoveryPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($failureRecoveryConsumer)
Assert ($failureRecoveryPlan.Task -ceq ':plugins:rdd:test' -and $failureRecoveryPlan.Module -ceq 'plugins:rdd' -and $failureRecoveryPlan.Tests.Count -eq 1 -and $failureRecoveryPlan.Tests[0] -ceq $failureRecoveryConsumer) 'failure recovery consumer preserves exact task and class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($failureRecoveryConsumer)).Module -ceq 'plugins:rdd') 'failure recovery consumer has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($failureRecoveryConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($failureRecoveryConsumer)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($failureRecoveryConsumer+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($failureRecoveryConsumer+'Helper')}
Write-Output 'Failure recovery consumer exact registration 6 assertions PASS (policy only; not Java execution)'
$navTests = @(
    'com.dwinovo.numen.core.task.move.MoveToTaskRecordTest',
    'com.dwinovo.numen.core.pathing.calc.NavGoalMembershipTest',
    'com.dwinovo.numen.core.pathing.calc.NavGoalDiagnosticsTest'
)
$navPlan = Get-RddTestOnlyPlan -Module 'core:common' -Tests $navTests
Assert ($navPlan.Task -ceq ':core:common:test' -and $navPlan.Tests.Count -eq 3) 'navigation diagnostics tests must map only to the core common task'
foreach ($navTest in $navTests) {
    MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($navTest) }
}
MustReject { Get-RddTestOnlyPlan -Module 'core:common' -Tests @('com.dwinovo.numen.core.pathing.calc.NavGoal*') }
MustReject { Get-RddTestOnlyPlan -Module 'core:common' -Tests @('com.dwinovo.numen.core.task.move.MoveToTask*') }
$attackTests = @('com.dwinovo.numen.core.tools.work.AttackToolContractTest','com.dwinovo.numen.core.combat.AttackPlanTest')
$attackPlan = Get-RddTestOnlyPlan -Module 'core:common' -Tests $attackTests
Assert ($attackPlan.Task -ceq ':core:common:test' -and $attackPlan.Tests.Count -eq 2) 'attack contract tests map only to core common'
foreach ($attackTest in $attackTests) {
    MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($attackTest) }
}
MustReject { Get-RddTestOnlyPlan -Module 'core:common' -Tests @('com.dwinovo.numen.core.tools.work.Attack*') }
$reviewTests = @('com.dwinovo.numen.plugins.learner.LearnerPluginAbortTest','com.dwinovo.numen.plugins.learner.LearnerPluginRestoreTest')
$reviewPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $reviewTests
Assert ($reviewPlan.Task -ceq ':plugins:learner:test' -and $reviewPlan.Tests.Count -eq 2) 'review continuity tests map only to learner'
foreach ($reviewTest in $reviewTests) {
    MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($reviewTest) }
}
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.LearnerPlugin*') }
$survivalTests = @('com.dwinovo.numen.plugins.rdd.RddSurvivalPreemptReplanHostTest','com.dwinovo.numen.plugins.rdd.RddSurvivalGateTest')
$survivalPlan = Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests $survivalTests
Assert ($survivalPlan.Task -ceq ':plugins:rdd:test' -and $survivalPlan.Tests.Count -eq 2) 'survival preemption host and gate controls map only to RDD'
foreach ($survivalTest in $survivalTests) {
    MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($survivalTest) }
}
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddSurvival*') }
# 2026-11-14: exact side-task nudge delivery consumer; adjacent names refused.
$sideTaskNudgeTest='com.dwinovo.numen.plugins.rdd.SideTaskNudgeDeliveryTest'
$sideTaskNudgePlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($sideTaskNudgeTest)
Assert ($sideTaskNudgePlan.Task -ceq ':plugins:rdd:test' -and $sideTaskNudgePlan.Tests.Count -eq 1) 'side-task nudge delivery maps only the RDD plugin test task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($sideTaskNudgeTest)).Module -ceq 'plugins:rdd') 'side-task nudge delivery has one inferred owner'
foreach($wrongModule in @('api:common','ai','plugins:learner','rdd-core')){MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($sideTaskNudgeTest)}}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($sideTaskNudgeTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($sideTaskNudgeTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.SideTaskNudgeDeliveryAdjacentTest')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.SideTaskNudgeDeliveryTestHelper')}
Write-Output 'side-task nudge delivery exact registration 10 assertions PASS (policy only; not Java execution)'
# 2026-11-14: exact why-body and original bridge controls, not a generic experience test prefix.
$experienceBridgeTests=@(
    'com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeWhyConsumerTest',
    'com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeTest',
    'com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeAudienceTest'
)
foreach($experienceBridgeTest in $experienceBridgeTests){
    $experiencePlan=Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests @($experienceBridgeTest)
    Assert ($experiencePlan.Task -ceq ':plugins:experience:test' -and $experiencePlan.Tests.Count -eq 1 -and $experiencePlan.Tests[0] -ceq $experienceBridgeTest) 'experience bridge preserves exact module/task/filter'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($experienceBridgeTest)).Module -ceq 'plugins:experience') 'experience bridge has one inferred owner'
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($experienceBridgeTest)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($experienceBridgeTest)}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests @($experienceBridgeTest+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests @($experienceBridgeTest.ToLowerInvariant())}
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests @($experienceBridgeTest+'Helper')}
}
Assert ((Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests $experienceBridgeTests).Tests.Count -eq 3) 'exact experience bridge trio stays selectable'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:experience' -Tests @('com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeOtherTest')}
Write-Output 'experience why bridge exact registration 23 assertions PASS (policy only; not Java execution)'
$managed = @()
$managed += (Join-Path $PSScriptRoot '../run-mutation.ps1')
$managed += (Join-Path $PSScriptRoot '../build-jar.ps1')
$enc = Test-RddPowerShellEncoding -Paths $managed
Assert ($enc.ok) ("managed scripts must keep BOM or stay ASCII: " + $enc.reason)
$plain = Join-Path $env:TEMP ('rdd-plain-' + [guid]::NewGuid().ToString('N') + '.ps1')
$bomFile = Join-Path $env:TEMP ('rdd-bom-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    [IO.File]::WriteAllText($plain, '# 中文注释', [Text.UTF8Encoding]::new($false))
    Assert (-not (Test-RddPowerShellEncoding -Paths @($plain)).ok) 'BOM-less non-ASCII must be rejected'
    [IO.File]::WriteAllText($bomFile, '# 中文注释', [Text.UTF8Encoding]::new($true))
    Assert ((Test-RddPowerShellEncoding -Paths @($bomFile)).ok) 'BOM preserved must pass'
    [IO.File]::WriteAllText($plain, '# ascii only', [Text.UTF8Encoding]::new($false))
    Assert ((Test-RddPowerShellEncoding -Paths @($plain)).ok) 'ASCII without BOM is safe'
} finally { Remove-Item -LiteralPath $plain,$bomFile -Force -ErrorAction SilentlyContinue }
$d=Join-Path $env:TEMP ('rdd-test-policy-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $d | Out-Null
try {
    Assert (-not (Test-RddTestOnlyReceipt -ExitCode 1 -ReportDir $d -ExpectedTests @($test)).ok) 'gradle failure must fail'
    Assert (-not (Test-RddTestOnlyReceipt -ExitCode 0 -ReportDir $d -ExpectedTests @($test)).ok) 'missing report must fail'
    $file=Join-Path $d "TEST-$test.xml"
    Set-Content -LiteralPath $file -Encoding UTF8 -Value "<testsuite name='$test' tests='0' failures='0' errors='0' skipped='0'/>"
    Assert (-not (Test-RddTestOnlyReceipt -ExitCode 0 -ReportDir $d -ExpectedTests @($test)).ok) 'zero tests must fail'
    Set-Content -LiteralPath $file -Encoding UTF8 -Value "<testsuite name='$test' tests='1' failures='1' errors='0' skipped='0'/>"
    Assert (-not (Test-RddTestOnlyReceipt -ExitCode 0 -ReportDir $d -ExpectedTests @($test)).ok) 'failed tests must fail'
    Set-Content -LiteralPath $file -Encoding UTF8 -Value "<testsuite name='$test' tests='1' failures='0' errors='0' skipped='0'/>"
    Assert ((Test-RddTestOnlyReceipt -ExitCode 0 -ReportDir $d -ExpectedTests @($test)).ok) 'valid report must pass'
    Assert (-not (Test-RddTestOnlyReceipt -ExitCode 7 -ReportDir $d -ExpectedTests @($test)).ok) 'nonzero gradle exit must beat a passing XML'
    Set-Content -LiteralPath $file -Encoding UTF8 -Value "<testsuite name='$test' tests='1' failures='0' errors='0' skipped='1'/>"
    Assert (-not (Test-RddTestOnlyReceipt -ExitCode 0 -ReportDir $d -ExpectedTests @($test)).ok) 'all-skipped suite must fail'
    Write-Output 'test-only policy fixtures PASS'
} finally { Remove-Item -LiteralPath $d -Recurse -Force }

# Static production wiring guard only: this does not execute native code or prove Java tests.
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../build-jar.ps1'),[ref]$tokens,[ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'build-jar must parse under default PowerShell'
$branch=@($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -ceq '$TestOnly' })
Assert ($branch.Count -eq 1) 'one production TestOnly branch required'
$body=$branch[0].Extent.Text
Assert ($body -match '(?s)\$nativePreference = \$ErrorActionPreference\s+\$gradleExit = \$null\s+try\s*\{\s*\$ErrorActionPreference = ''Continue''\s+\$global:LASTEXITCODE = \$null\s+& \$global:RDD_SC.GRADLE @gradleArgs \*> \$attempt.record.logFile\s+\$gradleExit = \$global:LASTEXITCODE\s*\}\s*finally\s*\{\s*\$ErrorActionPreference = \$nativePreference\s*\}') 'native exit capture must be locally protected with preference restoration'
Assert ($body -match 'if \(\$null -eq \$gradleExit\) \{ throw ''native-process-exit-unavailable'' \}') 'missing native exit must fail closed'
Assert ($body.IndexOf('native-process-exit-unavailable') -lt $body.IndexOf('$details.gradleExit = $gradleExit')) 'null exit must be refused before receipt handling'
Assert ($body.IndexOf('$ErrorActionPreference = $nativePreference') -lt $body.IndexOf('$after = Get-RddSourceSnapshot')) 'preference must be restored before post-source checks'
MustReject { Test-RddSourcePair -SourceRoot 'fixture' -ExpectedCommit '' }
MustReject { Test-RddSourcePair -SourceRoot '' -ExpectedCommit ('a'*40) }
Assert (Test-RddSourcePair -SourceRoot 'fixture' -ExpectedCommit ('a'*40)) 'complete source pair must remain accepted'
$before=@{head=('a'*40);branch='fixture';dirtyCount=0}
Assert (-not (Compare-RddSourceSnapshot -Before $before -After @{head=('b'*40);branch='fixture';dirtyCount=0}).ok) 'source HEAD drift must remain refused'
Assert (-not (Compare-RddSourceSnapshot -Before $before -After @{head=$before.head;branch='fixture';dirtyCount=1}).ok) 'source dirty post-check must remain refused'
Write-Output 'test-only static native wiring/source guards PASS (not native execution)'
# 2026-11-15: V27 single-pass conversation restore - exact three ai classes only.
$convoChecks=0
$convoTests=@(
    'com.dwinovo.numen.agent.llm.ConvoLogClearTest',
    'com.dwinovo.numen.agent.llm.ConvoLogPoisonTest',
    'com.dwinovo.numen.agent.llm.ConvoLogRestoreTest'
)
foreach($convoTest in $convoTests){
    $convoPlan=Get-RddTestOnlyPlan -Module 'ai' -Tests @($convoTest)
    Assert ($convoPlan.Task -ceq ':ai:test' -and $convoPlan.Module -ceq 'ai' -and $convoPlan.Tests.Count -eq 1 -and $convoPlan.Tests[0] -ceq $convoTest) 'convo restore exact class maps only the ai test task'; $convoChecks++
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($convoTest)).Module -ceq 'ai') 'convo restore class has one inferred owner ai'; $convoChecks++
    foreach($wrongModule in @('api:common','rdd-core','plugins:rdd','plugins:learner','plugins:experience')){
        MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($convoTest)}; $convoChecks++
    }
    MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @($convoTest+'*')}; $convoChecks++
    MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @($convoTest.ToLowerInvariant())}; $convoChecks++
    MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @($convoTest+'Helper')}; $convoChecks++
}
$convoTrio=Get-RddTestOnlyPlan -Module 'ai' -Tests $convoTests
Assert ($convoTrio.Tests.Count -eq 3 -and $convoTrio.Task -ceq ':ai:test') 'the exact three convo restore classes may run together'; $convoChecks++
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @('com.dwinovo.numen.agent.llm.ConvoLogAdjacentTest')}; $convoChecks++
Write-Output ('V27 convo restore exact registration ' + $convoChecks + ' assertions PASS (policy only; not Java execution)')

# 2026-11-15: exact HttpLlmTransportRetryTest only; wrong module/unknown http class stay rejected.
$httpChecks=0
$httpTest='com.dwinovo.numen.agent.http.HttpLlmTransportRetryTest'
$httpPlan=Get-RddTestOnlyPlan -Module 'ai' -Tests @($httpTest)
Assert ($httpPlan.Task -ceq ':ai:test' -and $httpPlan.Module -ceq 'ai' -and $httpPlan.Tests.Count -eq 1 -and $httpPlan.Tests[0] -ceq $httpTest) 'HttpLlmTransportRetryTest maps only the exact ai test task'; $httpChecks++
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($httpTest)).Module -ceq 'ai') 'HttpLlmTransportRetryTest has one inferred owner ai'; $httpChecks++
foreach($wrongModule in @('api:common','rdd-core','plugins:rdd','plugins:learner','plugins:experience')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($httpTest)}; $httpChecks++
}
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @('com.dwinovo.numen.agent.http.HttpLlmTransportOtherTest')}; $httpChecks++
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @($httpTest+'*')}; $httpChecks++
MustReject {Get-RddTestOnlyPlan -Module 'ai' -Tests @('com.dwinovo.numen.agent.http.HttpLlmTransportTest')}; $httpChecks++
Write-Output ('V27 http retry exact registration ' + $httpChecks + ' assertions PASS (policy only; not Java execution)')

# Exact existing loader test task; this admission does not enable other Minecraft tests.
$unloadChecks=0
$unloadTest='com.dwinovo.numen.debug.ChunkMapUnloadReadyTest'
$unloadPlan=Get-RddTestOnlyPlan -Module 'api:neoforge' -Tests @($unloadTest)
Assert ($unloadPlan.Task -ceq ':api:neoforge:test' -and $unloadPlan.Module -ceq 'api:neoforge' -and $unloadPlan.Tests.Count -eq 1 -and $unloadPlan.Tests[0] -ceq $unloadTest) 'bounded unload diagnostic maps only its exact loader task'; $unloadChecks++
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($unloadTest)).Module -ceq 'api:neoforge') 'bounded unload diagnostic has one inferred owner'; $unloadChecks++
foreach($wrongModule in @('api:common','ai','rdd-core','core:neoforge','plugins:rdd','plugins:learner')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($unloadTest)}; $unloadChecks++
}
foreach($wrongTest in @(($unloadTest+'*'),($unloadTest+'Helper'),($unloadTest.ToLowerInvariant()),'com.dwinovo.numen.debug.ChunkMapUnloadAdjacentTest')){
    MustReject {Get-RddTestOnlyPlan -Module 'api:neoforge' -Tests @($wrongTest)}; $unloadChecks++
}
MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($unloadTest,'com.dwinovo.numen.api.RequestDeliveredAggregationTest')}; $unloadChecks++
Write-Output ('bounded unload exact registration ' + $unloadChecks + ' assertions PASS (policy only; not Java execution)')

# 2026-11-15: exact TrajectorySlicesTest consumer only; no adjacent/wildcard/cross-module admission.
$trajectoryChecks=0
$trajectoryTest='com.dwinovo.numen.plugins.learner.core.TrajectorySlicesTest'
$trajectoryPlan=Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($trajectoryTest)
Assert ($trajectoryPlan.Task -ceq ':plugins:learner:test' -and $trajectoryPlan.Module -ceq 'plugins:learner' -and $trajectoryPlan.Tests.Count -eq 1 -and $trajectoryPlan.Tests[0] -ceq $trajectoryTest) 'TrajectorySlicesTest maps only the exact learner test task'; $trajectoryChecks++
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($trajectoryTest)).Module -ceq 'plugins:learner') 'TrajectorySlicesTest has one inferred owner plugins:learner'; $trajectoryChecks++
foreach($wrongModule in @('api:common','ai','plugins:rdd','rdd-core')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($trajectoryTest)}; $trajectoryChecks++
}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($trajectoryTest.ToLowerInvariant())}; $trajectoryChecks++
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($trajectoryTest+'*')}; $trajectoryChecks++
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.core.TrajectorySlicesAdjacentTest')}; $trajectoryChecks++
MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($trajectoryTest+'Helper')}; $trajectoryChecks++
Write-Output ('TrajectorySlices exact registration ' + $trajectoryChecks + ' assertions PASS (policy only; not Java execution)')

# 2026-11-15: exact RddFutureNeedsSignatureTest only; no adjacent/wildcard/cross-module admission.
$futureNeedsChecks=0
$futureNeedsTest='com.dwinovo.numen.plugins.rdd.RddFutureNeedsSignatureTest'
$futureNeedsPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($futureNeedsTest)
Assert ($futureNeedsPlan.Task -ceq ':plugins:rdd:test' -and $futureNeedsPlan.Module -ceq 'plugins:rdd' -and $futureNeedsPlan.Tests.Count -eq 1 -and $futureNeedsPlan.Tests[0] -ceq $futureNeedsTest) 'RddFutureNeedsSignatureTest maps only the exact RDD test task'; $futureNeedsChecks++
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($futureNeedsTest)).Module -ceq 'plugins:rdd') 'RddFutureNeedsSignatureTest has one inferred owner plugins:rdd'; $futureNeedsChecks++
foreach($wrongModule in @('api:common','ai','plugins:learner','rdd-core')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($futureNeedsTest)}; $futureNeedsChecks++
}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($futureNeedsTest.ToLowerInvariant())}; $futureNeedsChecks++
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($futureNeedsTest+'*')}; $futureNeedsChecks++
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('com.dwinovo.numen.plugins.rdd.RddFutureNeedsSignatureAdjacentTest')}; $futureNeedsChecks++
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($futureNeedsTest+'Helper')}; $futureNeedsChecks++
Write-Output ('RddFutureNeeds exact registration ' + $futureNeedsChecks + ' assertions PASS (policy only; not Java execution)')

# 2026-11-15: exact PreviewStartupTest; helper name rejected.
$previewStartupTest='com.dwinovo.numen.client.preview.PreviewStartupTest'
$previewStartupPlan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($previewStartupTest)
Assert ($previewStartupPlan.Task -ceq ':api:common:test' -and $previewStartupPlan.Module -ceq 'api:common' -and $previewStartupPlan.Tests.Count -eq 1 -and $previewStartupPlan.Tests[0] -ceq $previewStartupTest) 'PreviewStartupTest maps only the exact api:common task'
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($previewStartupTest+'Helper')}
Write-Output 'PreviewStartup exact registration 2 assertions PASS (policy only; not Java execution)'

# Exact final respawn event projection; no entity package wildcard or cross-module permission.
$respawnEventTest='com.dwinovo.numen.entity.RespawnEventSnapshotTest'
$respawnEventPlan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($respawnEventTest)
Assert ($respawnEventPlan.Task -ceq ':api:common:test' -and $respawnEventPlan.Module -ceq 'api:common' -and $respawnEventPlan.Tests.Count -eq 1 -and $respawnEventPlan.Tests[0] -ceq $respawnEventTest) 'respawn event maps only the exact api:common task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($respawnEventTest)).Module -ceq 'api:common') 'respawn event has one inferred module'
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($respawnEventTest)}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($respawnEventTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($respawnEventTest+'Helper')}
Write-Output 'Respawn event exact registration 5 assertions PASS (policy only; not Java execution)'

# Exact existing health-facts consumers; mandatory plan prose is not current SELF evidence.
$stateFactsTests=@('com.dwinovo.numen.api.StateFactsTest','com.dwinovo.numen.api.StateFragmentRegistryTest')
foreach($stateFactsTest in $stateFactsTests){
    $plan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($stateFactsTest)
    Assert ($plan.Task -ceq ':api:common:test' -and $plan.Module -ceq 'api:common' -and $plan.Tests.Count -eq 1 -and $plan.Tests[0] -ceq $stateFactsTest) 'state facts maps only the exact api common class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($stateFactsTest)).Module -ceq 'api:common') 'state facts has one inferred module'
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($stateFactsTest)}
    MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($stateFactsTest+'*')}
    MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($stateFactsTest+'Helper')}
    MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($stateFactsTest.ToLowerInvariant())}
}
Assert ((Get-RddTestOnlyPlan -Module 'api:common' -Tests $stateFactsTests).Tests.Count -eq 2) 'both exact state consumers may run together'
Write-Output 'State facts exact registration 13 assertions PASS (policy only; not Java execution)'

# Exact API-owned header geometry test; no UI module or screen-package admission.
$headerLayoutTest='com.dwinovo.numen.client.screen.HeaderLayoutTest'
$headerLayoutPlan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($headerLayoutTest)
Assert ($headerLayoutPlan.Task -ceq ':api:common:test' -and $headerLayoutPlan.Module -ceq 'api:common' -and $headerLayoutPlan.Tests.Count -eq 1 -and $headerLayoutPlan.Tests[0] -ceq $headerLayoutTest) 'header layout maps only the exact api common task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($headerLayoutTest)).Module -ceq 'api:common') 'header layout has one inferred module'
foreach($wrongModule in @('ui','api:neoforge','plugins:rdd','ai')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($headerLayoutTest)}
}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($headerLayoutTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($headerLayoutTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($headerLayoutTest+'Helper')}
Write-Output 'Header layout exact registration 9 assertions PASS (policy only; not Java execution)'

# Exact generated language-resource contract; no data/build-tool wildcard.
$languageResourcesTest='com.dwinovo.numen.data.LanguageResourcesTest'
$languageResourcesPlan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($languageResourcesTest)
Assert ($languageResourcesPlan.Task -ceq ':api:common:test' -and $languageResourcesPlan.Module -ceq 'api:common' -and $languageResourcesPlan.Tests.Count -eq 1 -and $languageResourcesPlan.Tests[0] -ceq $languageResourcesTest) 'language resources maps only the exact api common task'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($languageResourcesTest)).Module -ceq 'api:common') 'language resources has one inferred module'
foreach($wrongModule in @('ui','api:neoforge','plugins:rdd','ai')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($languageResourcesTest)}
}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($languageResourcesTest.ToLowerInvariant())}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($languageResourcesTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($languageResourcesTest+'Helper')}
Write-Output 'Language resources exact registration 9 assertions PASS (policy only; not Java execution)'

# LH1: exact learned-skill body/reference consumers, each owned by its original module.
$skillReferenceCases=@(
    @{Module='core:common';Class='com.dwinovo.numen.core.tools.agent.LoadSkillToolReferenceTest'},
    @{Module='plugins:learner';Class='com.dwinovo.numen.plugins.learner.skills.LearnedSkillBodyResolverTest'}
)
foreach($entry in $skillReferenceCases){
    $plan=Get-RddTestOnlyPlan -Module $entry.Module -Tests @($entry.Class)
    Assert ($plan.Task -ceq (':'+$entry.Module+':test') -and $plan.Module -ceq $entry.Module -and $plan.Tests.Count -eq 1 -and $plan.Tests[0] -ceq $entry.Class) 'skill reference maps only its exact module/task/class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($entry.Class)).Module -ceq $entry.Module) 'skill reference has one inferred owner'
    foreach($wrong in @('core:common','plugins:learner','api:common','plugins:acx') | Where-Object {$_ -cne $entry.Module}){
        MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($entry.Class)}
    }
    MustReject {Get-RddTestOnlyPlan -Module $entry.Module -Tests @($entry.Class+'Helper')}
    MustReject {Get-RddTestOnlyPlan -Module $entry.Module -Tests @($entry.Class+'*')}
    MustReject {Get-RddTestOnlyPlan -Module $entry.Module -Tests @($entry.Class.ToLowerInvariant())}
}
Write-Output 'Learned skill reference exact registration 16 assertions PASS (policy only; not Java execution)'

# Test-only admission for one pure sold-out predicate/callsite control, not selfcompile runtime permission.
$tradeSoldOutTest='com.dwinovo.numen.plugins.selfcompile.generated.RddTradeExecuteToolSoldOutTest'
$tradeSoldOutPlan=Get-RddTestOnlyPlan -Module 'plugins:selfcompile' -Tests @($tradeSoldOutTest)
Assert ($tradeSoldOutPlan.Task -ceq ':plugins:selfcompile:test' -and $tradeSoldOutPlan.Module -ceq 'plugins:selfcompile' -and $tradeSoldOutPlan.Tests.Count -eq 1 -and $tradeSoldOutPlan.Tests[0] -ceq $tradeSoldOutTest) 'sold-out test maps only exact selfcompile test task/class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($tradeSoldOutTest)).Module -ceq 'plugins:selfcompile') 'sold-out test has one inferred module'
foreach($wrong in @('plugins:rdd','plugins:learner','core:common','api:common')){
    MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($tradeSoldOutTest)}
}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:selfcompile' -Tests @($tradeSoldOutTest+'Helper')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:selfcompile' -Tests @($tradeSoldOutTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:selfcompile' -Tests @($tradeSoldOutTest.ToLowerInvariant())}
Write-Output 'Trade sold-out exact registration 9 assertions PASS (policy only; not Java execution)'

# Mechanical class split regression selection: exact consumers, no module/package widening.
$splitCases=@(
    @{Module='plugins:rdd';Class='com.dwinovo.numen.plugins.rdd.RddReplanPlanRendererTest'},
    @{Module='api:common';Class='com.dwinovo.numen.client.agent.BodySnapshotRendererFormatTest'},
    @{Module='rdd-core';Class='com.dwinovo.numen.rdd.core.G3cPlanPatchTest'},
    @{Module='rdd-core';Class='com.dwinovo.numen.rdd.core.G3eSafePointTest'},
    @{Module='rdd-core';Class='com.dwinovo.numen.rdd.core.TaskChainPatchBoundaryTest'}
)
foreach($c in $splitCases){
    $p=Get-RddTestOnlyPlan -Module $c.Module -Tests @($c.Class)
    Assert ($p.Task -ceq (':'+$c.Module+':test') -and $p.Tests.Count -eq 1 -and $p.Tests[0] -ceq $c.Class) 'split control maps exact module/class'
    Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($c.Class)).Module -ceq $c.Module) 'split control has unique owner'
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @($c.Class)}
    MustReject {Get-RddTestOnlyPlan -Module $c.Module -Tests @($c.Class+'*')}
    MustReject {Get-RddTestOnlyPlan -Module $c.Module -Tests @($c.Class+'Helper')}
}
Write-Output 'Class split exact registration 25 assertions PASS (policy only; not Java execution)'

# Exact regression for the observed pending-primary death settlement handoff.
$pendingDeathTest='com.dwinovo.numen.plugins.rdd.RddPendingDeathSettlementReplanTest'
$pendingDeathPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($pendingDeathTest)
Assert ($pendingDeathPlan.Task -ceq ':plugins:rdd:test' -and $pendingDeathPlan.Tests.Count -eq 1 -and $pendingDeathPlan.Tests[0] -ceq $pendingDeathTest) 'pending death handoff maps only exact RDD class'
Assert ((Get-RddTestOnlyPlan -Module '' -Tests @($pendingDeathTest)).Module -ceq 'plugins:rdd') 'pending death handoff has one owner'
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($pendingDeathTest)}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($pendingDeathTest+'*')}
MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($pendingDeathTest+'Helper')}
Write-Output 'Pending death settlement exact registration 5 assertions PASS (policy only; not Java execution)'

# 042R6: exact existing schema-facts consumer, distinct from WorldFactConditionsPinTest.
$worldFactConditionsTest='com.dwinovo.numen.rdd.core.WorldFactConditionsTest'
$worldFactConditionsPositive=0; $worldFactConditionsNegative=0
$worldFactConditionsPlan=Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($worldFactConditionsTest)
Assert ($worldFactConditionsPlan.Task -ceq ':rdd-core:test' -and $worldFactConditionsPlan.Module -ceq 'rdd-core' -and $worldFactConditionsPlan.Tests.Count -eq 1 -and $worldFactConditionsPlan.Tests[0] -ceq $worldFactConditionsTest) 'world fact conditions explicit selection keeps only the exact rdd-core task/class'; $worldFactConditionsPositive++
$worldFactConditionsInferred=Get-RddTestOnlyPlan -Module '' -Tests @($worldFactConditionsTest)
Assert ($worldFactConditionsInferred.Task -ceq ':rdd-core:test' -and $worldFactConditionsInferred.Module -ceq 'rdd-core' -and $worldFactConditionsInferred.Tests.Count -eq 1 -and $worldFactConditionsInferred.Tests[0] -ceq $worldFactConditionsTest) 'world fact conditions inference has only the exact rdd-core owner/task/class'; $worldFactConditionsPositive++
foreach($wrongModule in @('plugins:rdd','plugins:learner','api:common','ai')){
    MustReject {Get-RddTestOnlyPlan -Module $wrongModule -Tests @($worldFactConditionsTest)}; $worldFactConditionsNegative++
}
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.core.WorldFactConditionsAdjacentTest')}; $worldFactConditionsNegative++
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($worldFactConditionsTest+'Helper')}; $worldFactConditionsNegative++
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($worldFactConditionsTest.ToLowerInvariant())}; $worldFactConditionsNegative++
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @($worldFactConditionsTest+'*')}; $worldFactConditionsNegative++
MustReject {Get-RddTestOnlyPlan -Module 'rdd-core' -Tests @('com.dwinovo.numen.rdd.core.*')}; $worldFactConditionsNegative++
Write-Output ('WorldFactConditions exact registration '+$worldFactConditionsPositive+' positive, '+$worldFactConditionsNegative+' negative ('+($worldFactConditionsPositive+$worldFactConditionsNegative)+' assertions) PASS (policy only; not Java execution)')

# Existing defense/throttle regressions only; no package or cross-module admission.
$defenseThrottleCases=@(
    @{Module='core:common';Class='com.dwinovo.numen.core.task.chain.MobDefenseChainTest';Adjacent='com.dwinovo.numen.core.task.chain.MobDefenseChainAdjacentTest';Package='com.dwinovo.numen.core.task.chain.*'},
    @{Module='plugins:rdd';Class='com.dwinovo.numen.plugins.rdd.RddRiskGateExceptionThrottleTest';Adjacent='com.dwinovo.numen.plugins.rdd.RddRiskGateExceptionThrottleAdjacentTest';Package='com.dwinovo.numen.plugins.rdd.*'}
)
$defenseThrottlePositive=0; $defenseThrottleNegative=0
foreach($entry in $defenseThrottleCases){
    $plan=Get-RddTestOnlyPlan -Module $entry.Module -Tests @($entry.Class)
    Assert ($plan.Task -ceq (':'+$entry.Module+':test') -and $plan.Module -ceq $entry.Module -and $plan.Tests.Count -eq 1 -and $plan.Tests[0] -ceq $entry.Class) 'defense/throttle explicit exact module/task/class'; $defenseThrottlePositive++
    $inferred=Get-RddTestOnlyPlan -Module '' -Tests @($entry.Class)
    Assert ($inferred.Task -ceq (':'+$entry.Module+':test') -and $inferred.Module -ceq $entry.Module -and $inferred.Tests.Count -eq 1 -and $inferred.Tests[0] -ceq $entry.Class) 'defense/throttle inferred exact owner/task/class'; $defenseThrottlePositive++
    foreach($wrong in @('core:common','core:neoforge','plugins:rdd','api:common','ai','rdd-core','plugins:learner') | Where-Object {$_ -cne $entry.Module}){
        MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($entry.Class)}; $defenseThrottleNegative++
    }
    foreach($invalid in @($entry.Adjacent,($entry.Class+'Helper'),($entry.Class+'*'),$entry.Package,$entry.Class.ToLowerInvariant(),$entry.Class.ToUpperInvariant())){
        MustReject {Get-RddTestOnlyPlan -Module $entry.Module -Tests @($invalid)}; $defenseThrottleNegative++
        MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($invalid)}; $defenseThrottleNegative++
    }
}
MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($defenseThrottleCases[0].Class,$defenseThrottleCases[1].Class)}; $defenseThrottleNegative++
Write-Output ('Defense/throttle exact registration '+$defenseThrottlePositive+' positive, '+$defenseThrottleNegative+' negative PASS (policy only; not Java execution)')

# 174 temporary shelter: exact admission only; the in-flight consumer is not a Java pass.
$shelterCases=@(
    @{Module='core:common';Class='com.dwinovo.numen.core.task.build.BuildInPlaceTest';Adjacent='com.dwinovo.numen.core.task.build.BuildInPlaceAdjacentTest';Package='com.dwinovo.numen.core.task.build.*'},
    @{Module='core:common';Class='com.dwinovo.numen.core.task.build.BuildInPlaceConsumerTest';Adjacent='com.dwinovo.numen.core.task.build.BuildInPlaceConsumerAdjacentTest';Package='com.dwinovo.numen.core.task.build.*'},
    @{Module='plugins:acx';Class='com.dwinovo.numen.acx.test.Dig3Seal1EmergencyAcTest';Adjacent='com.dwinovo.numen.acx.test.Dig3Seal1EmergencyAcAdjacentTest';Package='com.dwinovo.numen.acx.test.*'}
)
$shelterPositive=0; $shelterNegative=0
foreach($entry in $shelterCases){
    $plan=Get-RddTestOnlyPlan -Module $entry.Module -Tests @($entry.Class)
    Assert ($plan.Task -ceq (':'+$entry.Module+':test') -and $plan.Module -ceq $entry.Module -and $plan.Tests.Count -eq 1 -and $plan.Tests[0] -ceq $entry.Class) 'shelter explicit selection preserves exact module/task/class'; $shelterPositive++
    $inferred=Get-RddTestOnlyPlan -Module '' -Tests @($entry.Class)
    Assert ($inferred.Task -ceq (':'+$entry.Module+':test') -and $inferred.Module -ceq $entry.Module -and $inferred.Tests.Count -eq 1 -and $inferred.Tests[0] -ceq $entry.Class) 'shelter inference preserves exact module/task/class'; $shelterPositive++
    foreach($wrong in @('core:common','plugins:acx','core:neoforge','plugins:rdd') | Where-Object {$_ -cne $entry.Module}){
        MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($entry.Class)}; $shelterNegative++
    }
    foreach($invalid in @($entry.Adjacent,($entry.Class+'Helper'),($entry.Class+'*'),$entry.Package,$entry.Class.ToLowerInvariant())){
        MustReject {Get-RddTestOnlyPlan -Module $entry.Module -Tests @($invalid)}; $shelterNegative++
        MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($invalid)}; $shelterNegative++
    }
}
$buildPair=@($shelterCases[0].Class,$shelterCases[1].Class)
$buildPlan=Get-RddTestOnlyPlan -Module 'core:common' -Tests $buildPair
Assert ($buildPlan.Task -ceq ':core:common:test' -and $buildPlan.Tests.Count -eq 2 -and $buildPlan.Tests[0] -ceq $buildPair[0] -and $buildPlan.Tests[1] -ceq $buildPair[1]) 'only the exact build pair may share the core test task'; $shelterPositive++
MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($buildPair[0],$shelterCases[2].Class)}; $shelterNegative++
Write-Output ('174 shelter exact registration '+$shelterPositive+' positive, '+$shelterNegative+' negative PASS (policy only; not Java execution)')

# 2026-11-17: exact StallWatcher consumer (real track/handleStalled source + mock IO boundary); no wildcard or adjacent admission.
$stallWatcherConsumerTest='com.dwinovo.numen.plugins.rdd.RddStallWatcherConsumerTest'
$stallWatcherPositive=0; $stallWatcherNegative=0
$stallWatcherPlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($stallWatcherConsumerTest)
Assert ($stallWatcherPlan.Task -ceq ':plugins:rdd:test' -and $stallWatcherPlan.Module -ceq 'plugins:rdd' -and $stallWatcherPlan.Tests.Count -eq 1 -and $stallWatcherPlan.Tests[0] -ceq $stallWatcherConsumerTest) 'StallWatcher consumer maps only the exact plugins:rdd task/class'; $stallWatcherPositive++
$stallWatcherInferred=Get-RddTestOnlyPlan -Module '' -Tests @($stallWatcherConsumerTest)
Assert ($stallWatcherInferred.Module -ceq 'plugins:rdd' -and $stallWatcherInferred.Task -ceq ':plugins:rdd:test' -and $stallWatcherInferred.Tests.Count -eq 1 -and $stallWatcherInferred.Tests[0] -ceq $stallWatcherConsumerTest) 'StallWatcher consumer has one inferred owner'; $stallWatcherPositive++
foreach($wrong in @('core:common','core:neoforge','api:common','ai','rdd-core','plugins:learner')){
    MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($stallWatcherConsumerTest)}; $stallWatcherNegative++
}
foreach($invalid in @('com.dwinovo.numen.plugins.rdd.RddStallWatcher*',($stallWatcherConsumerTest+'Helper'),$stallWatcherConsumerTest.ToLowerInvariant())){
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($invalid)}
    MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($invalid)}; $stallWatcherNegative+=2
}
Write-Output ('StallWatcher consumer exact registration '+$stallWatcherPositive+' positive, '+$stallWatcherNegative+' negative PASS (policy only; not Java execution)')

# 2026-11-17: exact SideTaskFoodDecline host consumer (source owner attempt06); plan-level admission only.
$foodDeclineConsumerTest='com.dwinovo.numen.plugins.rdd.SideTaskFoodDeclineConsumerTest'
$foodDeclinePositive=0; $foodDeclineNegative=0
$foodDeclinePlan=Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($foodDeclineConsumerTest)
Assert ($foodDeclinePlan.Task -ceq ':plugins:rdd:test' -and $foodDeclinePlan.Module -ceq 'plugins:rdd' -and $foodDeclinePlan.Tests.Count -eq 1 -and $foodDeclinePlan.Tests[0] -ceq $foodDeclineConsumerTest) 'SideTaskFoodDecline consumer maps only the exact plugins:rdd task/class'; $foodDeclinePositive++
$foodDeclineInferred=Get-RddTestOnlyPlan -Module '' -Tests @($foodDeclineConsumerTest)
Assert ($foodDeclineInferred.Module -ceq 'plugins:rdd' -and $foodDeclineInferred.Task -ceq ':plugins:rdd:test' -and $foodDeclineInferred.Tests.Count -eq 1 -and $foodDeclineInferred.Tests[0] -ceq $foodDeclineConsumerTest) 'SideTaskFoodDecline consumer has one inferred owner'; $foodDeclinePositive++
foreach($wrong in @('core:common','core:neoforge','api:common','ai','rdd-core','plugins:learner')){
    MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($foodDeclineConsumerTest)}; $foodDeclineNegative++
}
foreach($invalid in @('com.dwinovo.numen.plugins.rdd.SideTaskFoodDecline*',($foodDeclineConsumerTest+'Helper'),$foodDeclineConsumerTest.ToLowerInvariant())){
    MustReject {Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @($invalid)}
    MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($invalid)}; $foodDeclineNegative+=2
}
Write-Output ('SideTaskFoodDecline consumer exact registration '+$foodDeclinePositive+' positive, '+$foodDeclineNegative+' negative PASS (policy only; not Java execution)')

# 2026-11-17: exact SystemPromptWake consumer (API source owner 4号); plan-level admission only.
$systemWakeConsumerTest='com.dwinovo.numen.client.agent.SystemPromptWakeConsumerTest'
$systemWakePositive=0; $systemWakeNegative=0
$systemWakePlan=Get-RddTestOnlyPlan -Module 'api:common' -Tests @($systemWakeConsumerTest)
Assert ($systemWakePlan.Task -ceq ':api:common:test' -and $systemWakePlan.Module -ceq 'api:common' -and $systemWakePlan.Tests.Count -eq 1 -and $systemWakePlan.Tests[0] -ceq $systemWakeConsumerTest) 'SystemPromptWake consumer maps only the exact api:common task/class'; $systemWakePositive++
$systemWakeInferred=Get-RddTestOnlyPlan -Module '' -Tests @($systemWakeConsumerTest)
Assert ($systemWakeInferred.Module -ceq 'api:common' -and $systemWakeInferred.Task -ceq ':api:common:test' -and $systemWakeInferred.Tests.Count -eq 1 -and $systemWakeInferred.Tests[0] -ceq $systemWakeConsumerTest) 'SystemPromptWake consumer has one inferred owner'; $systemWakePositive++
foreach($wrong in @('core:common','core:neoforge','plugins:rdd','ai','rdd-core','plugins:learner')){
    MustReject {Get-RddTestOnlyPlan -Module $wrong -Tests @($systemWakeConsumerTest)}; $systemWakeNegative++
}
foreach($invalid in @('com.dwinovo.numen.client.agent.SystemPromptWake*',($systemWakeConsumerTest+'Helper'),$systemWakeConsumerTest.ToLowerInvariant())){
    MustReject {Get-RddTestOnlyPlan -Module 'api:common' -Tests @($invalid)}
    MustReject {Get-RddTestOnlyPlan -Module '' -Tests @($invalid)}; $systemWakeNegative+=2
}
Write-Output ('SystemPromptWake consumer exact registration '+$systemWakePositive+' positive, '+$systemWakeNegative+' negative PASS (policy only; not Java execution)')

# 2026-11-18: exact API context and task acceptance consumers; no package or class wildcards.
$apiRequestAcceptanceClasses = @(
    'com.dwinovo.numen.client.agent.AgentRequestContextTest',
    'com.dwinovo.numen.task.TaskAcceptanceConsumerTest'
)
foreach ($selector in $apiRequestAcceptanceClasses) {
    foreach ($module in @('api:common', '')) {
        $plan = Get-RddTestOnlyPlan -Module $module -Tests @($selector)
        Assert ($plan.Module -ceq 'api:common' -and $plan.Task -ceq ':api:common:test' -and
            $plan.Tests.Count -eq 1 -and $plan.Tests[0] -ceq $selector) "API consumer must retain its exact selector: $selector"
    }
    MustReject { Get-RddTestOnlyPlan -Module 'api:neoforge' -Tests @($selector) }
    $package = $selector.Substring(0, $selector.LastIndexOf('.'))
    foreach ($invalid in @(($package + '.*'), ($selector + '*'), ($selector + 'Helper'), $selector.ToLowerInvariant())) {
        MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @($invalid) }
        MustReject { Get-RddTestOnlyPlan -Module '' -Tests @($invalid) }
    }
}
$apiRequestAcceptancePlan = Get-RddTestOnlyPlan -Module 'api:common' -Tests $apiRequestAcceptanceClasses
Assert ($apiRequestAcceptancePlan.Task -ceq ':api:common:test' -and
    $apiRequestAcceptancePlan.Tests.Count -eq 2 -and
    $apiRequestAcceptancePlan.Tests[0] -ceq $apiRequestAcceptanceClasses[0] -and
    $apiRequestAcceptancePlan.Tests[1] -ceq $apiRequestAcceptanceClasses[1]) 'both exact API consumer selectors may be requested together'
Write-Output 'API request context / task acceptance exact registration 5 positive, 18 negative PASS (policy only; not Java execution)'
