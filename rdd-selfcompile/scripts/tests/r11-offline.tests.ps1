# 2026-11-11: isolated R11 fixtures only. Never invoke or dot-source production entries/config.
param([string]$EvidenceDir)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) { throw 'explicit temporary evidence directory required' }
if (Test-Path -LiteralPath $EvidenceDir) { throw 'evidence directory must be new' }
New-Item -ItemType Directory -Path $EvidenceDir -ErrorAction Stop | Out-Null
$root=Split-Path $PSScriptRoot -Parent
function Parse-Only($name) {
 $tokens=$null; $errors=$null
 $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('parse error: '+$name+': '+$errors[0].Message)}
 return $ast
}
$policy=Parse-Only 'test-only-policy.ps1'
# Load only function definitions extracted from the real source, no top-level entry execution.
foreach($definition in $policy.EndBlock.Statements){
 if($definition -isnot [System.Management.Automation.Language.FunctionDefinitionAst]){throw 'unexpected policy top-level statement'}
 . ([ScriptBlock]::Create($definition.Extent.Text))
}
$script:passed=0
function Assert($condition,$label){if(-not $condition){throw ('FAIL '+$label)};$script:passed++;Write-Output ('PASS '+$label)}
function Reject([scriptblock]$action,$label){$rejected=$false;try{& $action | Out-Null}catch{$rejected=$true};Assert $rejected $label}
$mutation=Join-Path $EvidenceDir 'mutation'
New-Item -ItemType Directory -Path $mutation | Out-Null
$old=Join-Path $mutation 'phase-test.json'
[IO.File]::WriteAllText($old,'{"success":true,"historical":true}')
$oldHash=(Get-FileHash $old).Hash
$a=New-RddTestAttempt -MutationDir $mutation -Module 'api:common' -Tests @('fixture')
Assert ((Get-Content $a.currentPath -Raw | ConvertFrom-Json).status -eq 'pending') 'pending-current-before-validation'
Complete-RddTestAttempt -Attempt $a -Status 'passed' -Reason 'fixture-only'
$aHash=(Get-FileHash $a.statePath).Hash
$b=New-RddTestAttempt -MutationDir $mutation -Module 'bad-module' -Tests @('fixture')
try{Get-RddTestOnlyPlan -Module 'bad-module' -Tests @('fixture') | Out-Null}catch{Complete-RddTestAttempt -Attempt $b -Status 'failed' -Reason $_.Exception.Message}
Assert ((Get-Content $b.currentPath -Raw | ConvertFrom-Json).attemptId -eq $b.id) 'failed-attempt-is-current-not-old-success'
Assert ((Get-Content $b.statePath -Raw | ConvertFrom-Json).status -eq 'failed') 'module-rejection-recorded-failed'
Assert ((Get-FileHash $old).Hash -eq $oldHash -and (Get-FileHash $a.statePath).Hash -eq $aHash) 'historical-success-unchanged'
$c=New-RddTestAttempt -MutationDir $mutation -Module 'api:common' -Tests @('fixture')
[IO.File]::WriteAllText($c.record.logFile,'interrupted-first-attempt')
$logHash=(Get-FileHash $c.record.logFile).Hash
$d=New-RddTestAttempt -MutationDir $mutation -Module 'api:common' -Tests @('fixture')
Assert ($c.record.logFile -ne $d.record.logFile -and $c.record.reportDir -ne $d.record.reportDir) 'retry-log-and-xml-paths-distinct'
Assert ((Get-Content $c.statePath -Raw | ConvertFrom-Json).status -eq 'pending' -and (Get-FileHash $c.record.logFile).Hash -eq $logHash) 'interrupted-pending-and-log-preserved'
Reject {Complete-RddTestAttempt -Attempt $a -Status 'failed' -Reason 'overwrite'} 'finalized-history-cannot-be-rewritten'
Reject {Test-RddSourcePair -SourceRoot '' -ExpectedCommit 'abc'} 'expected-only-refused'
Reject {Test-RddSourcePair -SourceRoot 'fixture' -ExpectedCommit ''} 'root-only-refused'
Assert (-not (Test-RddSourcePair -SourceRoot '' -ExpectedCommit '')) 'default-root-explicitly-unverified'
$before=@{head=('a'*40);branch='fixture';dirtyCount=0}
Assert (-not (Compare-RddSourceSnapshot -Before $before -After @{head=$before.head;branch='fixture';dirtyCount=1}).ok) 'same-head-persistent-dirty-unknown'
Assert ((Compare-RddSourceSnapshot -Before $before -After $before).reason -eq 'pre-post-checks-consistent') 'proof-limited-to-pre-post'
# Substitute Git output/exit only. No actual git process or repository is accessed.
$script:failGit=''
function git {
 $call=$args -join ' '
 $global:LASTEXITCODE=0
 if($script:failGit -and $call.Contains($script:failGit)){$global:LASTEXITCODE=128;return}
 if($call.Contains('--abbrev-ref')){'fixture'}elseif($call.Contains('rev-parse HEAD')){'a'*40}
}
foreach($failure in @('rev-parse HEAD','--abbrev-ref','status --porcelain')){
 $script:failGit=$failure
 $unknown=New-RddTestAttempt -MutationDir $mutation -Module 'api:common' -Tests @('fixture')
 try{$snapshot=Get-RddSourceSnapshot -Root 'fixture';throw 'unexpected source snapshot success'}catch{
  if($_.Exception.Message -notlike '*git-command-failed*'){throw}
  Complete-RddTestAttempt -Attempt $unknown -Status 'unknown' -Reason $_.Exception.Message
 }
 Assert ((Get-Content $unknown.statePath -Raw | ConvertFrom-Json).status -eq 'unknown') ('git-error-not-clean: '+$failure)
}
Remove-Item Function:git
# IO failure must throw before any test work; fixtures never contain a runner.
$blocked=Join-Path $EvidenceDir 'blocked'
New-Item -ItemType Directory -Path $blocked | Out-Null
New-Item -ItemType Directory -Path (Join-Path $blocked 'current-attempt.json') | Out-Null
Reject {New-RddTestAttempt -MutationDir $blocked -Module 'api:common' -Tests @('fixture')} 'current-write-failure-aborts'
# Source-validation refusal is current failure, not stale historical success.
$invalid=New-RddTestAttempt -MutationDir $mutation -Module 'maid-link-core' -Tests @('fixture')
try { Resolve-RddTrustedSourceRoot -Root '' -ExpectedCommit 'abc' -RepoRoot 'fixture' | Out-Null }
catch { Complete-RddTestAttempt -Attempt $invalid -Status 'failed' -Reason $_.Exception.Message }
Assert ((Get-Content $invalid.currentPath -Raw | ConvertFrom-Json).status -eq 'failed') 'source-early-refusal-current-failed'
# Static consumer wiring: use real command AST, not comment string matching.
$checked=@($policy.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-RddCheckedGit'},$true))[0]
$gitStatements=@($checked.Body.EndBlock.Statements)
Assert ($gitStatements[0].Extent.Text.Contains('& git -C $Root @GitArgs') -and $gitStatements[1].Extent.Text.Trim() -eq '$code = $LASTEXITCODE' -and $gitStatements[2].Extent.Text.Contains('if ($code -ne 0)')) 'git-output-exit-check-adjacent'
$build=Parse-Only 'build-jar.ps1'
$commands=@($build.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst]},$true))
$new=@($commands | Where-Object {$_.GetCommandName() -eq 'New-RddTestAttempt'})[0]
$plan=@($commands | Where-Object {$_.GetCommandName() -eq 'Get-RddTestOnlyPlan'})[0]
$source=@($commands | Where-Object {$_.GetCommandName() -eq 'Resolve-RddTrustedSourceRoot'})[0]
Assert ($new -and $new.Extent.StartOffset -lt $plan.Extent.StartOffset -and $new.Extent.StartOffset -lt $source.Extent.StartOffset) 'attempt-published-before-module-and-source-checks'
Assert (@($commands | Where-Object {$_.GetCommandName() -eq 'Get-RddSourceSnapshot'}).Count -eq 1) 'build-post-check-uses-shared-sampler'
$resolve=@($policy.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-RddTrustedSourceRoot'},$true))[0]
Assert ($resolve.Body.Extent.Text.Contains('Get-RddSourceSnapshot')) 'pre-check-uses-shared-sampler'
$buildText=$build.Extent.Text
Assert ($buildText.Contains('$attempt.record.reportDir') -and $buildText.Contains('$attempt.record.logFile') -and -not $buildText.Contains('Join-Path $dir ''phase-test.json''')) 'consumer-only-uses-attempt-log-xml-receipt'
$run=Parse-Only 'run-mutation.ps1'
$pair=@($run.FindAll({param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.Contains('if ($hasSourceRoot -xor $hasExpectedCommit)')},$true))[0]
$config=@($run.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.Extent.Text.Contains('. "$PSScriptRoot\config.ps1"')},$true))[0]
Assert ($pair -and $config -and $pair.Extent.StartOffset -lt $config.Extent.StartOffset) 'run-pair-rejection-before-config'
foreach($file in @('deploy.ps1','launch-mc.ps1')){
 $f=Parse-Only $file
 Assert ($f.EndBlock.Statements[1] -is [System.Management.Automation.Language.ExitStatementAst]) ($file+'-hard-refusal-preserved')
}
Write-Output ('RESULT passed='+$script:passed+' failed=0; evidence=AST-and-isolated-functions-only')
Write-Output ('FIXTURE_DIR='+$EvidenceDir)
