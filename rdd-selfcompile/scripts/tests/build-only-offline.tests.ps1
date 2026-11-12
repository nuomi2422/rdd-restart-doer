# 2026-11-11: isolated policy/source-pin tests only; never invoke production entries/config/Gradle.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'execution-guard.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'guard parse failed'}
foreach($d in $ast.EndBlock.Statements){
 if($d -isnot [Management.Automation.Language.FunctionDefinitionAst]){throw 'unexpected guard statement'}
 . ([scriptblock]::Create($d.Extent.Text))
}
function Assert($c,$label){if(-not $c){throw ('FAIL '+$label)};Write-Output ('PASS '+$label)}
function Reject([scriptblock]$f,$label){$bad=$false;try{& $f | Out-Null}catch{$bad=$true};Assert $bad $label}
Assert (-not (Resolve-RddRunMode).ok) 'no-mode-refused'
Assert (-not (Resolve-RddRunMode -Mode full).ok) 'full-refused'
Assert (-not (Resolve-RddRunMode -Mode build-only -TestOnly).ok) 'mode-conflict'
Assert ((Resolve-RddRunMode -TestOnly).mode -eq 'test-only') 'test-only-preserved'
Assert ((Resolve-RddRunMode -Mode build-only).mode -eq 'build-only') 'explicit-build-only'
foreach($m in @('api:neoforge','core:neoforge','plugins:rdd','plugins:learner','plugins:maidlink')){
 $p=Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module $m -SourceRoot 'fixture' -ExpectedCommit ('a'*40)
 Assert ($p.task -ceq (':'+$m+':jar')) ('exact-task-'+$m)
}
Reject {Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $false -Module 'plugins:rdd' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'environment-instance-not-explicit'
Reject {Get-RddBuildOnlyPlan -Instance gpt -InstanceExplicit $true -Module 'plugins:rdd' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'gpt-refused'
Reject {Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module ':plugins:rdd:runClient' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'task-injection-refused'
Reject {Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module 'plugins:rdd' -SourceRoot fixture -ExpectedCommit 'short'} 'short-hash-refused'
# 2026-11-12: one optional SELF reader release only; this grants no deployment or launch.
$maid=Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module 'plugins:maidlink' -SourceRoot fixture -ExpectedCommit ('a'*40)
Assert ($maid.artifactPrefix -ceq 'numen-plugin-maidlink' -and $maid.relativeDir -ceq 'plugins/maidlink/build/libs') 'maidlink-exact-artifact'
Reject {Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module 'plugins:maidlink:runClient' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'maidlink-task-injection-refused'
Reject {Get-RddBuildOnlyPlan -Instance gpt -InstanceExplicit $true -Module 'plugins:maidlink' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'maidlink-original-instance-refused'
# 2026-11-12: exact verified camera artifact; no deployment or launch permission.
$camera=Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module 'plugins:camera' -SourceRoot fixture -ExpectedCommit ('a'*40)
Assert ($camera.task -ceq ':plugins:camera:jar' -and $camera.artifactPrefix -ceq 'numen-plugin-camera' -and $camera.relativeDir -ceq 'plugins/camera/build/libs') 'camera-exact-artifact'
Reject {Get-RddBuildOnlyPlan -Instance gpt -InstanceExplicit $true -Module 'plugins:camera' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'camera-original-instance-refused'
Reject {Get-RddBuildOnlyPlan -Instance test -InstanceExplicit $true -Module 'plugins:camera:runClient' -SourceRoot fixture -ExpectedCommit ('a'*40)} 'camera-task-injection-refused'
Reject {Select-RddBuildArtifact -Names @('numen-plugin-camera-1.21.1-0.1.3-dev-api.jar') -Prefix 'numen-plugin-camera'} 'camera-classifier-refused'
$n='numen-plugin-rdd-1.21.1-0.1.3-dev.jar'
Assert ((Select-RddBuildArtifact -Names @($n,'numen-plugin-rdd-1.21.1-0.1.3-dev-api.jar','numen-plugin-rdd-1.21.1-0.1.3-dev-sources.jar') -Prefix 'numen-plugin-rdd') -ceq $n) 'release-not-classifier'
Reject {Select-RddBuildArtifact -Names @($n,$n) -Prefix 'numen-plugin-rdd'} 'ambiguous-release-refused'
Reject {Select-RddBuildArtifact -Names @('numen-plugin-rdd-1.21.1-0.1.3-dev-api.jar') -Prefix 'numen-plugin-rdd'} 'api-only-refused'
# Pins prove wiring only, not executed Gradle/copy or Minecraft behavior.
$run=Get-Content -LiteralPath (Join-Path $root 'run-mutation.ps1') -Raw
$build=Get-Content -LiteralPath (Join-Path $root 'build-jar.ps1') -Raw
Assert ($run.IndexOf('Get-RddBuildOnlyPlan') -lt $run.IndexOf('. "$PSScriptRoot\config.ps1"')) 'selection-before-config'
Assert ($run.Contains('exit $buildExit')) 'build-only-return-before-closure'
Assert ($build.IndexOf('Resolve-RddTrustedSourceRoot') -lt $build.IndexOf("'mutation-build-'")) 'trusted-source-before-mutation'
# 2026-11-12: native stderr repair uses the explicit global exit slot; pin its reset/capture/fail-closed path.
Assert ($build.Contains('$global:LASTEXITCODE=$null') -and $build.Contains('$code=$global:LASTEXITCODE') -and $build.Contains('native-process-exit-unavailable') -and $build.Contains('Compare-RddSourceSnapshot')) 'native-exit-and-source-postcheck'
Assert ($build.Contains('[IO.File]::Copy($artifact,$dest,$false)')) 'fresh-artifact-copy-no-overwrite'
Assert ($build.Contains('deployed=$false')) 'receipt-not-deployed-pin'
