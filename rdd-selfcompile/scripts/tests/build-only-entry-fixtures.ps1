# 2026-11-11 isolated production script copies; dependency/path fixtures only.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path $EvidenceDir){throw 'fresh evidence directory required'}
New-Item -ItemType Directory $EvidenceDir | Out-Null
$production=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
$cases=@(
 @{name='no-mode';extra=@();fail=$true},
 @{name='full';extra=@('-Mode','full');fail=$true},
 @{name='gpt';extra=@('-Mode','build-only','-Instance','gpt');fail=$true},
 @{name='missing-instance';extra=@('-Mode','build-only');fail=$true},
 @{name='conflict';extra=@('-Mode','build-only','-Instance','test','-TestOnly');fail=$true},
 @{name='bad-hash';extra=@('-Mode','build-only','-Instance','test');badHash=$true;fail=$true},
 @{name='gradle-nonzero';extra=@('-Mode','build-only','-Instance','test');gradleExit=9;fail=$true},
 @{name='missing-jar';extra=@('-Mode','build-only','-Instance','test');noJar=$true;fail=$true},
 @{name='classifier';extra=@('-Mode','build-only','-Instance','test');suffix='-api';fail=$true},
 @{name='wrong-version';extra=@('-Mode','build-only','-Instance','test');wrongVersion=$true;fail=$true},
 @{name='post-change';extra=@('-Mode','build-only','-Instance','test');changed=$true;fail=$true},
 @{name='stderr-zero';extra=@('-Mode','build-only','-Instance','test');stderr=$true;fail=$false},
 @{name='stderr-nine';extra=@('-Mode','build-only','-Instance','test');stderr=$true;gradleExit=9;fail=$true},
 @{name='launch-missing';extra=@('-Mode','build-only','-Instance','test');missingExe=$true;fail=$true}
)
foreach($module in @('api:neoforge','core:neoforge','plugins:rdd','plugins:learner')){
 $cases+=@{name=('ok-'+$module.Replace(':','-'));extra=@('-Mode','build-only','-Instance','test');module=$module;fail=$false}
}
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case.name; $scripts=Join-Path $d 'scripts'; $repo=Join-Path $d 'source'
 New-Item -ItemType Directory $scripts,$repo | Out-Null
 foreach($n in @('run-mutation.ps1','build-jar.ps1','execution-guard.ps1')){Copy-Item (Join-Path $production $n) (Join-Path $scripts $n)}
 # Preserve production branch body; only concrete external path dependencies are relocated.
 $build=Get-Content (Join-Path $scripts 'build-jar.ps1') -Raw
 $build=$build.Replace('D:/rdd/workspace/minecraft-numen',$repo.Replace('\','/'))
 $fakeGradle=Join-Path $d 'gradle.cmd'
 $build=$build.Replace('D:/rdd/workspace/gradle-9.2.0/bin/gradle.bat',$fakeGradle.Replace('\','/'))
 Put (Join-Path $scripts 'build-jar.ps1') $build
 $helper=Get-Content (Join-Path $production 'test-only-policy.ps1') -Raw
 # Keep real comparison and JSON writer; source identity is explicitly a fake dependency, not a trusted production repo.
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseInput($helper,[ref]$tokens,[ref]$errors)
 $functions=(@($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in @('Compare-RddSourceSnapshot','Write-RddAttemptJson') } | ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine)
 $postHash=if($case.changed){'b'*40}else{'a'*40}
 $stub=@'
function Resolve-RddTrustedSourceRoot {param($Root,$ExpectedCommit,$RepoRoot);return @{root=$Root;head=('a'*40);branch='FIXTURE';dirtyCount=0}}
function Get-RddSourceSnapshot {param($Root);return @{head='POSTHASH';branch='FIXTURE';dirtyCount=0}}
'@
 Put (Join-Path $scripts 'test-only-policy.ps1') ($functions+[Environment]::NewLine+$stub.Replace('POSTHASH',$postHash))
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','new-mutation.ps1','deploy.ps1','launch-mc.ps1','mcp-drive.ps1','verify.ps1','postflight.ps1')){Put (Join-Path $scripts $n) ('Add-Content -LiteralPath "'+$poison+'" -Value "POISON"; exit 91')}
 $module=if($case.module){$case.module}else{'plugins:rdd'}
 $prefix=@{'api:neoforge'='numen_api-neoforge';'core:neoforge'='numen-neoforge';'plugins:rdd'='numen-plugin-rdd';'plugins:learner'='numen-plugin-learner'}[$module]
 $libs=Join-Path $repo ($module.Replace(':','/')+'/build/libs');New-Item -ItemType Directory $libs -Force | Out-Null
 $version=if($case.wrongVersion){'9.9.9'}else{'0.1.3-dev'}
 $jar=Join-Path $libs ($prefix+'-1.21.1-'+$version+$case.suffix+'.jar')
 $exit=if($case.gradleExit){$case.gradleExit}else{0}
 $cmd="@echo off"+[Environment]::NewLine+"echo BUILD SUCCESSFUL"+[Environment]::NewLine
 if(-not $case.noJar){$cmd+='echo fixture-artifact>'+('"'+$jar+'"')+[Environment]::NewLine}
 if($case.stderr){$cmd+='echo fixture-warning 1>&2'+[Environment]::NewLine}
 $cmd+='exit /b '+$exit+[Environment]::NewLine
 if(-not $case.missingExe){[IO.File]::WriteAllText($fakeGradle,$cmd,[Text.Encoding]::ASCII)}
 $hash=if($case.badHash){'short'}else{'a'*40}
 $argv=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $scripts 'run-mutation.ps1'))+$case.extra+@('-Module',$module,'-SourceRoot',$repo,'-ExpectedCommit',$hash)
 $ErrorActionPreference='Continue'
 $output=& powershell.exe @argv 2>&1; $code=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $receipts=@(Get-ChildItem (Join-Path $d 'mutations') -Filter phase-build.json -Recurse -ErrorAction SilentlyContinue)
 $passed=$code -eq 0
 if(Test-Path $poison){throw ('poison invoked: '+$case.name)}
 if($passed -eq [bool]$case.fail){throw ('unexpected exit: '+$case.name+' code='+$code)}
 if($passed){
  if($receipts.Count -ne 1){throw 'missing unique receipt'}
  $r=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if(-not $r.success -or $r.deployed -or $r.sha256 -cne (Get-FileHash $r.artifact -Algorithm SHA256).Hash){throw 'bad artifact receipt'}
 }else{foreach($p in $receipts){if((Get-Content $p.FullName -Raw | ConvertFrom-Json).success){throw 'false passed receipt'}}}
 $results+=@{case=$case.name;exit=$code;poisonCount=0;passed=$true;sourceIdentity='fixture dependency, not production git proof'}
}
Put (Join-Path $EvidenceDir 'results.json') ($results | ConvertTo-Json -Depth 5)
Write-Output ('PASS '+$results.Count+' isolated copied-entry cases; poison=0; no real Gradle/config/instance')
