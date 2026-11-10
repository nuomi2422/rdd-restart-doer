$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\test-only-policy.ps1')
function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
function MustReject([scriptblock]$block) { $rejected=$false; try { & $block } catch { $rejected=$true }; Assert $rejected 'expected rejection' }
$test='com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest'
$p=Get-RddTestOnlyPlan -Module ' plugins:rdd ' -Tests @($test)
Assert ($p.Task -ceq ':plugins:rdd:test') 'task must be fixed'
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd:jar' -Tests @($test) }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @('*.test') }
MustReject { Get-RddTestOnlyPlan -Module 'plugins:rdd' -Tests @() }
MustReject { Get-RddTestOnlyPlan -Module 'core:neoforge' -Tests @($test) }
$id = Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.monitor.WorldContextStampTest')
Assert ($id.Task -ceq ':api:common:test') 'api task must be fixed'
MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @($test) }
MustReject { Get-RddTestOnlyPlan -Module 'api:common' -Tests @('com.dwinovo.numen.monitor.WorldContextStampTest*') }
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
