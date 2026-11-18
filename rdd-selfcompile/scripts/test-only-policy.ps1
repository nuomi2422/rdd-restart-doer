# Pure test-only command plan and JUnit receipt policy; never invokes Gradle or deployment.
function New-RddTestOnlyGradleArgs {
    param([string]$Root, $Plan, [switch]$TestLowMemory)
    $argv = @('-p', $Root, $Plan.Task, '--no-build-cache', '--no-daemon', '--rerun-tasks')
    if ($TestLowMemory) {
        $init = Join-Path $PSScriptRoot 'test-only-low-memory.init.gradle'
        if (-not (Test-Path -LiteralPath $init -PathType Leaf)) { throw 'TestLowMemory init script missing' }
        $argv += @('--max-workers=1', '--no-parallel', '-Dorg.gradle.jvmargs=-Xmx1024m', '--init-script', $init)
    }
    foreach ($test in $Plan.Tests) { $argv += @('--tests', $test) }
    $argv
}
function Get-RddTestOnlyPlan {
    param([string]$Module, [string[]]$Tests)
    # Module -> exact test classes. Unknown module or class is refused; never build
    # a Gradle task or test filter from caller text.
    $allowlist = @{
        'plugins:rdd' = @(
            'com.dwinovo.numen.plugins.rdd.RddRiskGateExceptionThrottleTest',
            'com.dwinovo.numen.plugins.rdd.RddSurvivalIntentTest',
            'com.dwinovo.numen.plugins.rdd.RddSurvivalPreemptReplanHostTest',
            'com.dwinovo.numen.plugins.rdd.RddSurvivalGateTest',
            'com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest',
            'com.dwinovo.numen.plugins.rdd.RddSettleStageFlagsTest',
            'com.dwinovo.numen.plugins.rdd.RddStagePlannerParseTest',
            'com.dwinovo.numen.plugins.rdd.RddStageBRationaleRequestTest',
            'com.dwinovo.numen.plugins.rdd.RddSubmissionRationaleHandoffTest',
            'com.dwinovo.numen.plugins.rdd.RddObsidianPlanConsumerTest',
            'com.dwinovo.numen.plugins.rdd.RddDecomposerParseTest',
            'com.dwinovo.numen.plugins.rdd.RddDecomposerNodeTypeTest',
            'com.dwinovo.numen.plugins.rdd.RddDecomposerAssetBoundsTest',
            'com.dwinovo.numen.plugins.rdd.RddDecomposerPromptDelegationTest',
            'com.dwinovo.numen.plugins.rdd.RddPlanGuardTest',
            'com.dwinovo.numen.plugins.rdd.RddPersonalRespawnPolicyTest',
            'com.dwinovo.numen.plugins.rdd.RddHomeReserveFreshnessTest',
            'com.dwinovo.numen.plugins.rdd.RddExternalResetWiringTest',
            'com.dwinovo.numen.plugins.rdd.RddEarlyCompletionEvidenceTest',
            'com.dwinovo.numen.plugins.rdd.RddEarlyProposalPublisherTest',
            'com.dwinovo.numen.plugins.rdd.RddControlFlagReadsTest',
            'com.dwinovo.numen.plugins.rdd.RddRuntimeRestoreConsumerTest',
            'com.dwinovo.numen.plugins.rdd.RddFailureRecoveryConsumerTest',
            'com.dwinovo.numen.plugins.rdd.RddDeathFactsConsumerTest',
            'com.dwinovo.numen.plugins.rdd.RddDeathLedgerStoreTest',
            'com.dwinovo.numen.plugins.rdd.VerifiedCompletionIntegrationTest',
            'com.dwinovo.numen.plugins.rdd.StageCompletionCommitTest',
            'com.dwinovo.numen.plugins.rdd.RddMainlineWiringPinTest',
            'com.dwinovo.numen.plugins.rdd.RddInventoryProjectionTest',
            'com.dwinovo.numen.plugins.rdd.EarlyAchievementInventoryRegressionTest',
            'com.dwinovo.numen.plugins.rdd.RddPlanningKnowledgeTest',
            'com.dwinovo.numen.plugins.rdd.RddSurvivalDoctrineTest',
            'com.dwinovo.numen.plugins.rdd.RddBasePlaybookTest',
            'com.dwinovo.numen.plugins.rdd.RddBaseFactsConsumerTest',
            'com.dwinovo.numen.plugins.rdd.RddAlarmResponseTextTest',
            'com.dwinovo.numen.plugins.rdd.RddMonitorJournalTest',
            'com.dwinovo.numen.plugins.rdd.SleepRiskHostTest',
            'com.dwinovo.numen.plugins.rdd.RddDeathEquipmentTest',
            'com.dwinovo.numen.plugins.rdd.RddDeathPreparationWiringTest',
            'com.dwinovo.numen.plugins.rdd.RddDeathPreparationHostSuccessorTest',
            'com.dwinovo.numen.plugins.rdd.RddRepairLossAnalysisTest',
            'com.dwinovo.numen.plugins.rdd.RddRepairDispatchTimeoutTest',
            'com.dwinovo.numen.plugins.rdd.RddRepairDispatchPinTest',
            'com.dwinovo.numen.plugins.rdd.S1SemanticsWiringTest',
            'com.dwinovo.numen.plugins.rdd.RddRepairLogPolicyTest',
            'com.dwinovo.numen.plugins.rdd.RddFactContextStickyNeedsTest',
            'com.dwinovo.numen.plugins.rdd.RddFactContextTest',
            'com.dwinovo.numen.plugins.rdd.G1b2ManifestCacheTest',
            'com.dwinovo.numen.plugins.rdd.G1bImportanceConsumerTest',
            'com.dwinovo.numen.plugins.rdd.G1c2FingerprintTest',
            'com.dwinovo.numen.plugins.rdd.G1c3TransformAttributionTest',
            'com.dwinovo.numen.plugins.rdd.G1cReservationWiringTest',
            'com.dwinovo.numen.plugins.rdd.RddCarryProjectionTest',
            'com.dwinovo.numen.plugins.rdd.RddAssetsToolTest',
            'com.dwinovo.numen.plugins.rdd.RddAssetStoreTest',
            'com.dwinovo.numen.plugins.rdd.MachinePointRecheckTest',
            'com.dwinovo.numen.plugins.rdd.RddGoalDriverInjectionTest',
            'com.dwinovo.numen.plugins.rdd.SideTaskNudgeDeliveryTest',
            'com.dwinovo.numen.plugins.rdd.RddPlanningObservationWiringTest',
            'com.dwinovo.numen.plugins.rdd.RddSupervisionNotificationsTest',
            'com.dwinovo.numen.plugins.rdd.RddFutureNeedsSignatureTest',
            # Exact existing food-hint consumer; supersedes the unmerged multi-state candidate route.
            'com.dwinovo.numen.plugins.rdd.RddNeedsTextTest',
            'com.dwinovo.numen.plugins.rdd.RddReplanPlanRendererTest',
            'com.dwinovo.numen.plugins.rdd.RddPendingDeathSettlementReplanTest',
            # 2026-11-17: exact StallWatcher track/handleStalled consumer; no package or adjacent admission.
            'com.dwinovo.numen.plugins.rdd.RddStallWatcherConsumerTest',
            # 2026-11-17: exact SideTaskFoodDecline host consumer; plan-level admission only.
            'com.dwinovo.numen.plugins.rdd.SideTaskFoodDeclineConsumerTest',
            'com.dwinovo.numen.plugins.rdd.RddPlanningStockFactTest',
            'com.dwinovo.numen.plugins.rdd.RddPlanningHpFactTest',
            'com.dwinovo.numen.plugins.rdd.RddPlanningStockRequestTest'
        )
        'ai' = @(
            'com.dwinovo.numen.agent.llm.LlmObservationTest',
            'com.dwinovo.numen.agent.retrieval.MinimalContextAssemblerTest',
            # 2026-11-15: V27 single-pass conversation restore, exact three classes only.
            'com.dwinovo.numen.agent.llm.ConvoLogClearTest',
            'com.dwinovo.numen.agent.llm.ConvoLogPoisonTest',
            'com.dwinovo.numen.agent.llm.ConvoLogRestoreTest'
            # 2026-11-15: exact HttpLlmTransportRetryTest only; no http wildcard/adjacent admission.
            'com.dwinovo.numen.agent.http.HttpLlmTransportRetryTest'
        )
        # 2026-11-15: one bounded native shutdown diagnostic; never admit adjacent MC tests.
        'api:neoforge' = @(
            'com.dwinovo.numen.debug.ChunkMapUnloadReadyTest'
        )
        'api:common' = @(
            'com.dwinovo.numen.api.RequestDeliveredAggregationTest',
            'com.dwinovo.numen.api.ServerIdentitySnapshotTest',
            'com.dwinovo.numen.api.ExternalCommandPolicyTest',
            'com.dwinovo.numen.monitor.WorldContextStampTest',
            'com.dwinovo.numen.monitor.MonitoringJournalAcceptedTest',
            'com.dwinovo.numen.api.RationaleContextTest',
            'com.dwinovo.numen.client.agent.OwnerStopLatchTest',
            'com.dwinovo.numen.client.agent.SleepQueueGenerationTest',
            'com.dwinovo.numen.client.agent.ServerToolTransportReplyIsolationTest',
            'com.dwinovo.numen.client.agent.ServerToolTransportBindingTest',
            'com.dwinovo.numen.client.agent.ServerToolTransportExternalNamespaceTest',
            'com.dwinovo.numen.api.SleepHandoffConsumerTest',
            'com.dwinovo.numen.api.EnqueueReceiptTest',
            'com.dwinovo.numen.api.EnqueueReceiptCompatTest',
            'com.dwinovo.numen.api.EnqueueTransactionMatrixTest',
            'com.dwinovo.numen.api.EnqueueTransactionQueueTest',
            'com.dwinovo.numen.api.CapturedOwnerInputTest',
            'com.dwinovo.numen.client.chat.QuickVoiceCaptureTest',
            'com.dwinovo.numen.api.ExecutorRetrievalInputTest',
            'com.dwinovo.numen.api.StateFactsTest',
            'com.dwinovo.numen.api.StateFragmentRegistryTest',
            'com.dwinovo.numen.api.ExecutorBudgetAggregationTest',
            'com.dwinovo.numen.api.ExecutorCompanionIsolationTest',
            'com.dwinovo.numen.entity.TemporaryEntityProtectionTest',
            'com.dwinovo.numen.entity.RespawnEventSnapshotTest',
            'com.dwinovo.numen.task.TaskRecordTest',
            'com.dwinovo.numen.api.CompanionEndpointTest',
            'com.dwinovo.numen.client.screen.HeaderLayoutTest',
            'com.dwinovo.numen.data.LanguageResourcesTest',
            'com.dwinovo.numen.client.preview.PreviewStartupTest',
            'com.dwinovo.numen.client.agent.BodySnapshotRendererFormatTest',
            # 2026-11-17: exact SystemPromptWake consumer; plan-level admission only.
            'com.dwinovo.numen.client.agent.SystemPromptWakeConsumerTest',
            'com.dwinovo.numen.client.agent.AgentRequestContextTest',
            'com.dwinovo.numen.task.TaskAcceptanceConsumerTest'
        )
        'plugins:learner' = @(
            'com.dwinovo.numen.plugins.learner.LearnerAutoDeliveryIntakeTest',
            'com.dwinovo.numen.plugins.learner.LearnerAutoIntakeTest',
            'com.dwinovo.numen.plugins.learner.core.UsageLedgerTest',
            'com.dwinovo.numen.plugins.learner.core.AcxExecutionReflectorTest',
            'com.dwinovo.numen.plugins.learner.core.SkillDeliveryIntakeTest',
            'com.dwinovo.numen.plugins.learner.core.StormGuardTest',
            'com.dwinovo.numen.plugins.learner.LearnerPluginDeliveryMappingTest',
            'com.dwinovo.numen.plugins.learner.DeliveryDispatchIntegrationTest',
            'com.dwinovo.numen.plugins.learner.core.SkillDeliveryEvidenceTest',
            'com.dwinovo.numen.plugins.learner.LearnerPluginAbortTest',
            'com.dwinovo.numen.plugins.learner.LearnerPluginRestoreTest',
            'com.dwinovo.numen.plugins.learner.ReviewStatePersistenceRedTest',
            'com.dwinovo.numen.plugins.learner.ReviewStateFileConsumerTest',
            'com.dwinovo.numen.plugins.learner.ReviewCompletionTest',
            'com.dwinovo.numen.plugins.learner.ReviewTargetGateTest',
            'com.dwinovo.numen.plugins.learner.LearnerReviewObservationTest',
            'com.dwinovo.numen.plugins.learner.LearnerMonitorJournalTest',
            'com.dwinovo.numen.plugins.learner.core.TrajectorySlicesTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillBodyDeliveryIntegrityTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillBodyStoreTest',
            'com.dwinovo.numen.plugins.learner.core.CandidateGateTest',
            'com.dwinovo.numen.plugins.learner.core.AnnounceTextTest',
            'com.dwinovo.numen.plugins.learner.core.ExperienceSevenFieldsTest',
            'com.dwinovo.numen.plugins.learner.LearnerReviewerEvidenceTest',
            'com.dwinovo.numen.plugins.learner.LearnerSkillTaskFeedbackTest',
            'com.dwinovo.numen.plugins.learner.skills.PublishBoundaryBodyTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillRegistryPromoteTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillCatalogViewTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillRegistrarSharedRegistryTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillsGapTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillsKnowledgeContributorTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillsAggregateConsumerTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillsAccountingTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillLocationScopeDeliveryTest',
            'com.dwinovo.numen.plugins.learner.skills.SkillRegistrarTest',
            'com.dwinovo.numen.plugins.learner.skills.LearnedSkillBodyResolverTest',
            'com.dwinovo.numen.plugins.learner.core.ArtifactOutboxTest',
            'com.dwinovo.numen.plugins.learner.contract.ArtifactValidatorTest',
            'com.dwinovo.numen.plugins.learner.LearnerAutoTaskResultIntakeTest',
            'com.dwinovo.numen.plugins.learner.LearnerTaskResultIntakeTest'
        )
        'plugins:selfcompile' = @(
            'com.dwinovo.numen.plugins.selfcompile.generated.RddTradeExecuteToolSoldOutTest'
        )
        'core:common' = @(
            # 174 temporary shelter: exact gate and in-flight consumer, not a Java pass.
            'com.dwinovo.numen.core.task.build.BuildInPlaceTest',
            'com.dwinovo.numen.core.task.build.BuildInPlaceConsumerTest',
            'com.dwinovo.numen.core.task.chain.MobDefenseChainTest',
            'com.dwinovo.numen.core.tools.agent.LoadSkillToolReferenceTest',
            'com.dwinovo.numen.core.tools.work.AttackToolContractTest',
            'com.dwinovo.numen.core.combat.AttackPlanTest',
            'com.dwinovo.numen.core.task.mine.MineHarvestRecoveryConsumerTest',
            'com.dwinovo.numen.api.PlanningKnowledgeAggregationTest',
            'com.dwinovo.numen.core.task.move.MoveToTaskRecordTest',
            'com.dwinovo.numen.core.task.move.MoveToArrivalConsumerTest',
            'com.dwinovo.numen.core.pathing.calc.NavGoalMembershipTest',
            'com.dwinovo.numen.core.pathing.calc.NavGoalDiagnosticsTest'
        )
        'rdd-core' = @(
            'com.dwinovo.numen.rdd.core.EarlyCompletionTest',
            'com.dwinovo.numen.rdd.core.RddEarlyCompletionProposalTest',
            'com.dwinovo.numen.rdd.core.TaskChainCompletionCopyTest',
            'com.dwinovo.numen.rdd.core.G3cPlanPatchTest',
            'com.dwinovo.numen.rdd.core.G3eSafePointTest',
            'com.dwinovo.numen.rdd.core.TaskChainPatchBoundaryTest',
            'com.dwinovo.numen.rdd.core.BaseSelectorTest',
            'com.dwinovo.numen.rdd.core.TaskChainDailyDispatchTest',
            'com.dwinovo.numen.rdd.core.WorldFactConditionsPinTest',
            'com.dwinovo.numen.rdd.core.WorldFactConditionsTest',
            'com.dwinovo.numen.rdd.side.FoodSupplySideTaskTypeTest',
            'com.dwinovo.numen.rdd.side.SideTaskEngineTest',
            'com.dwinovo.numen.rdd.side.SideTaskRecurringTest',
            'com.dwinovo.numen.rdd.side.death.DeathPreparationRegressionTest',
            'com.dwinovo.numen.rdd.side.death.DeathPreparationFlowTest',
            'com.dwinovo.numen.rdd.side.death.DeathPreparationScopeRegressionTest',
            'com.dwinovo.numen.rdd.side.death.DeathRecoverySideTaskTypeTest',
            'com.dwinovo.numen.rdd.side.death.DeathRecoveryDecisionTest',
            'com.dwinovo.numen.rdd.policy.LossImpactAnalyzerTest',
            'com.dwinovo.numen.rdd.core.TaskChainStickyNeedsTest',
            'com.dwinovo.numen.rdd.core.TaskChainRestartRoundTripTest',
            'com.dwinovo.numen.rdd.side.SleepRiskPreemptionTest',
            'com.dwinovo.numen.rdd.side.SleepSideTaskSpawnBindTest',
            'com.dwinovo.numen.rdd.side.SideTaskDeclineTest',
            'com.dwinovo.numen.rdd.core.CompletedFactStoreTest',
            'com.dwinovo.numen.rdd.side.FoodSupplyAdmissionPriorityTest'
        )
        'world-state-core' = @(
            'com.dwinovo.numen.worldstate.core.model.WorldIdentityTest',
            'com.dwinovo.numen.worldstate.core.derive.SelfStockDerivationTest'
        )
        'plugins:worldstate' = @(
            'com.dwinovo.numen.plugins.worldstate.SelfStockProjectionTest',
            'com.dwinovo.numen.plugins.worldstate.ObservationResponsesTest',
            'com.dwinovo.numen.plugins.worldstate.SelfSampleReaderTest'
        )
        'maid-link-core' = @(
            'com.dwinovo.numen.link.core.MaidLinkCoreContractTest'
        )
        'plugins:acx' = @(
            'com.dwinovo.numen.acx.test.AcxRunReceiptIsolationTest',
            'com.dwinovo.numen.acx.test.AcxOfflineSuiteTest',
            'com.dwinovo.numen.acx.test.AcxSessionOwnerConsumerTest',
            'com.dwinovo.numen.plugins.acx.AcxBoundHostConsumerTest',
            'com.dwinovo.numen.plugins.acx.AcxCompanionBridgeConsumerTest',
            'com.dwinovo.numen.acx.test.Dig3Seal1EmergencyAcTest',
            'com.dwinovo.numen.acx.test.AcxArtifactLocationScopeTest',
            'com.dwinovo.numen.acx.test.AcxFarmContinueOfflineTest'
        )
        # 2026-11-14: exact existing experience bridge consumers; no prefix or whole-module execution.
        'plugins:experience' = @(
            'com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeWhyConsumerTest',
            'com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeTest',
            'com.dwinovo.numen.plugins.experience.ExperienceStoreRetrievalBridgeAudienceTest'
        )
        'plugins:camera' = @(
            'com.dwinovo.numen.plugins.camera.possess.PossessionRefreshWiringTest',
            'com.dwinovo.numen.plugins.camera.possess.FollowRefreshTest',
            'com.dwinovo.numen.plugins.camera.rec.SealLaunchTest',
            'com.dwinovo.numen.plugins.camera.rec.VideoRecorderSealWiringPinTest'
        )
        'plugins:maidlink' = @(
            'com.dwinovo.numen.plugins.maidlink.MaidSelfHostContractTest'
        )
    }
    $module = if ($null -eq $Module) { '' } else { $Module.Trim() }
    if ($module -eq '') {
        # No module given: accept only when every requested class belongs to exactly one
        # allowlisted module. Anything ambiguous stays refused.
        $owners = @()
        foreach ($name in @($Tests)) {
            if ($null -eq $name) { continue }
            foreach ($k in $allowlist.Keys) { if ($allowlist[$k] -ccontains $name.Trim()) { if ($owners -notcontains $k) { $owners += $k } } }
        }
        if ($owners.Count -ne 1) { throw 'test-only module is not allowed (pass an allowlisted module)' }
        $module = $owners[0]
    }
    if (-not $allowlist.ContainsKey($module)) { throw 'test-only module is not allowed' }
    $allowed = $allowlist[$module]
    if (-not $Tests -or $Tests.Count -eq 0) { throw 'at least one exact test class is required' }
    $normalized = @()
    foreach ($name in $Tests) {
        if ($null -eq $name) { throw 'null test class is not allowed' }
        $n = $name.Trim()
        if ($n -cnotin $allowed) { throw "test class is not allowed: $n" }
        if ($n -cnotin $normalized) { $normalized += $n }
    }
    return @{ Task = ":$($module):test"; Module = $module; Tests = $normalized }
}
# PowerShell 5.1 reads BOM-less UTF-8 as the local code page. A rewrite that drops the
# BOM turns Chinese comments into a ParserError before any test runs; check bytes, not text.
function Test-RddPowerShellEncoding {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        $bytes = [IO.File]::ReadAllBytes($p)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
        if ($hasBom) { continue }
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        foreach ($ch in $text.ToCharArray()) {
            if ([int]$ch -gt 127) { return @{ ok = $false; reason = "missing-bom:$([IO.Path]::GetFileName($p))" } }
        }
    }
    return @{ ok = $true; reason = 'encoding-ok' }
}
function Test-RddTestOnlyReceipt {
    param([int]$ExitCode, [string]$ReportDir, [string[]]$ExpectedTests)
    if ($ExitCode -ne 0) { return @{ ok=$false; reason='gradle-exit' } }
    if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) { return @{ ok=$false; reason='reports-missing' } }
    foreach ($name in $ExpectedTests) {
        $file = Join-Path $ReportDir "TEST-$name.xml"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @{ ok=$false; reason="report-missing:$name" } }
        try { [xml]$xml = Get-Content -LiteralPath $file -Raw -Encoding UTF8 } catch { return @{ ok=$false; reason="bad-xml:$name" } }
        if ($null -eq $xml.testsuite -or $xml.testsuite.name -cne $name) { return @{ ok=$false; reason="wrong-suite:$name" } }
        $tests=0; $failures=0; $errors=0; $skipped=0
        if (-not [int]::TryParse([string]$xml.testsuite.tests,[ref]$tests) -or
            -not [int]::TryParse([string]$xml.testsuite.failures,[ref]$failures) -or
            -not [int]::TryParse([string]$xml.testsuite.errors,[ref]$errors) -or
            -not [int]::TryParse([string]$xml.testsuite.skipped,[ref]$skipped)) { return @{ ok=$false; reason="bad-counts:$name" } }
        if ($tests -le 0 -or $skipped -ge $tests -or $failures -ne 0 -or $errors -ne 0) { return @{ ok=$false; reason="test-failed-or-empty:$name" } }
    }
    return @{ ok=$true; reason='passed' }
}

# 2026-11-11 R11: each Git output is usable only after its own exit code.
function Invoke-RddCheckedGit {
    param([string]$Root, [string[]]$GitArgs)
    $output = @(& git -C $Root @GitArgs 2>$null)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('git-command-failed: ' + ($GitArgs -join ' ') + '; exit=' + $code) }
    return $output
}
function Get-RddSourceSnapshot {
    param([string]$Root)
    $head = @(Invoke-RddCheckedGit -Root $Root -GitArgs @('rev-parse','HEAD'))
    $branch = @(Invoke-RddCheckedGit -Root $Root -GitArgs @('rev-parse','--abbrev-ref','HEAD'))
    $dirty = @(Invoke-RddCheckedGit -Root $Root -GitArgs @('status','--porcelain'))
    if ($head.Count -ne 1 -or [string]::IsNullOrWhiteSpace($head[0]) -or $branch.Count -ne 1 -or [string]::IsNullOrWhiteSpace($branch[0])) { throw 'git-command-failed: empty or ambiguous HEAD/branch' }
    return @{ head=$head[0].Trim(); branch=$branch[0].Trim(); dirtyCount=$dirty.Count }
}
function Test-RddSourcePair {
    param([string]$SourceRoot, [string]$ExpectedCommit)
    $hasRoot = -not [string]::IsNullOrWhiteSpace($SourceRoot)
    $hasCommit = -not [string]::IsNullOrWhiteSpace($ExpectedCommit)
    if ($hasRoot -xor $hasCommit) { throw 'SourceRoot and ExpectedCommit must be provided together' }
    return $hasRoot
}
function Compare-RddSourceSnapshot {
    param($Before, $After)
    if ($null -eq $After) { return @{ok=$false; reason='source-state-unknown'} }
    if ($Before.head -cne $After.head -or $Before.branch -cne $After.branch -or $After.dirtyCount -ne 0) { return @{ok=$false; reason='source-changed-during-test'} }
    return @{ok=$true; reason='pre-post-checks-consistent'}
}
# Source proof is only the pre/post checks, not an exclusive or immutable build input.
function Resolve-RddTrustedSourceRoot {
    param([string]$Root, [string]$ExpectedCommit, [string]$RepoRoot)
    if (-not (Test-RddSourcePair -SourceRoot $Root -ExpectedCommit $ExpectedCommit)) { throw 'explicit source root and commit required' }
    $full = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "source root not found: $full" }
    $top = @(Invoke-RddCheckedGit -Root $full -GitArgs @('rev-parse','--show-toplevel'))
    if ($top.Count -ne 1 -or [string]::IsNullOrWhiteSpace($top[0])) { throw 'git-command-failed: invalid toplevel' }
    $topFull = [IO.Path]::GetFullPath($top[0].Trim())
    if (-not [string]::Equals($topFull, $full, [StringComparison]::OrdinalIgnoreCase)) { throw 'source root is not the worktree top-level' }
    $common = @(Invoke-RddCheckedGit -Root $full -GitArgs @('rev-parse','--git-common-dir'))
    if ($common.Count -ne 1 -or [string]::IsNullOrWhiteSpace($common[0])) { throw 'git-command-failed: invalid common dir' }
    $commonPath = $common[0].Trim()
    if (-not [IO.Path]::IsPathRooted($commonPath)) { $commonPath = Join-Path $full $commonPath }
    $commonFull = [IO.Path]::GetFullPath($commonPath)
    $repoGit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($RepoRoot)) '.git'))
    if (-not [string]::Equals($commonFull, $repoGit, [StringComparison]::OrdinalIgnoreCase)) { throw 'worktree belongs to a different repository' }
    $listed = @(Invoke-RddCheckedGit -Root $full -GitArgs @('worktree','list','--porcelain'))
    $norm = { param($p) ([IO.Path]::GetFullPath($p).Replace('\','/')).TrimEnd('/') }
    $target = & $norm $full
    $registered = $false
    foreach ($line in $listed) {
        if ($line -match '^worktree\s+(.+)$') {
            $candidate = & $norm $Matches[1].Trim()
            if ([string]::Equals($candidate, $target, [StringComparison]::OrdinalIgnoreCase)) { $registered = $true; break }
        }
    }
    if (-not $registered) { throw 'worktree is not registered in git worktree list' }
    $snapshot = Get-RddSourceSnapshot -Root $full
    if ($ExpectedCommit -cnotmatch '^[0-9a-fA-F]{40}$' -or $snapshot.head -ine $ExpectedCommit) { throw 'HEAD mismatch: full ExpectedCommit required' }
    if ($snapshot.dirtyCount -ne 0) { throw 'worktree is dirty; test requires clean source' }
    return @{root=$full; head=$snapshot.head; branch=$snapshot.branch; dirtyCount=0}
}
# Attempt IO is deliberately limited to its mutation directory; callers fail closed on IO errors.
function Write-RddAttemptJson {
    param([string]$Path, $Value)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    if ([IO.Directory]::Exists($Path)) { throw 'attempt state path is a directory' }
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}
function New-RddTestAttempt {
    param([string]$MutationDir, [string]$Module, [string[]]$Tests)
    if (-not (Test-Path -LiteralPath $MutationDir -PathType Container)) { throw 'mutation not found' }
    $id = 'attempt-' + [guid]::NewGuid().ToString('N')
    $attemptDir = Join-Path $MutationDir $id
    New-Item -ItemType Directory -Path $attemptDir -ErrorAction Stop | Out-Null
    $record = @{attemptId=$id; status='pending'; success=$false; stage='test-only'; deployed=$false; module=$Module; tests=@($Tests); startedAt=[datetime]::UtcNow.ToString('o'); reason='not-completed'; sourceVerified=$false; sourceProof='not-provided'; logFile=(Join-Path $attemptDir 'phase-test.log'); reportDir=(Join-Path $attemptDir 'test-results')}
    $attempt = @{id=$id; dir=$attemptDir; statePath=(Join-Path $attemptDir 'phase-test.json'); currentPath=(Join-Path $MutationDir 'current-attempt.json'); record=$record}
    Write-RddAttemptJson -Path $attempt.statePath -Value $record
    Write-RddAttemptJson -Path $attempt.currentPath -Value @{attemptId=$id; statePath=$attempt.statePath; status='pending'; success=$false}
    return $attempt
}
function Complete-RddTestAttempt {
    param($Attempt, [ValidateSet('passed','failed','unknown')][string]$Status, [string]$Reason, $Details=@{})
    $existing = Get-Content -LiteralPath $Attempt.statePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if ($existing.attemptId -cne $Attempt.id -or $existing.status -cne 'pending') { throw 'attempt already finalized or mismatched' }
    $current = Get-Content -LiteralPath $Attempt.currentPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if ($current.attemptId -cne $Attempt.id) { throw 'attempt superseded; cannot publish as current' }
    $record = @{} + $Attempt.record
    foreach ($key in $Details.Keys) { $record[$key] = $Details[$key] }
    $record.status=$Status; $record.success=($Status -eq 'passed'); $record.reason=$Reason; $record.finishedAt=[datetime]::UtcNow.ToString('o')
    Write-RddAttemptJson -Path $Attempt.statePath -Value $record
    Write-RddAttemptJson -Path $Attempt.currentPath -Value @{attemptId=$Attempt.id; statePath=$Attempt.statePath; status=$Status; success=$record.success}
}
