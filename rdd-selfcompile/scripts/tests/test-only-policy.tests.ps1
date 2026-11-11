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
$skillTests = @('com.dwinovo.numen.plugins.learner.skills.SkillBodyDeliveryIntegrityTest', 'com.dwinovo.numen.plugins.learner.skills.SkillBodyStoreTest')
$skillPlan = Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests $skillTests
Assert ($skillPlan.Task -ceq ':plugins:learner:test' -and $skillPlan.Tests.Count -eq 2) 'skill delivery tests must map to the learner test task'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:learner' -Tests @('com.dwinovo.numen.plugins.learner.skills.SkillBody*') }
MustReject { Get-RddTestOnlyPlan -Module 'rdd-core' -Tests $skillTests }
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
