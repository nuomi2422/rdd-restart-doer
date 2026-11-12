# Offline policy fixtures and static TestOnly native wiring guard.
# 2026-11-12: caller Stop must not let PS5.1 stderr preempt native exit capture.
# Normal script invocation only; native execution requires the managed parent run.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\test-only-policy.ps1')
function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
function MustReject([scriptblock]$block) { $rejected=$false; try { & $block } catch { $rejected=$true }; Assert $rejected 'expected rejection' }
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