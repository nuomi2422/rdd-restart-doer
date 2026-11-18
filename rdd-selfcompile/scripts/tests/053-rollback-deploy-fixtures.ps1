# 2026-11-19: managed rollback fixtures for the five released pre-053 packages.
# Temporary files and fake CIM only; never live IO, Java, deployment or launch.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $EvidenceDir){throw 'fresh fixture directory required'}
New-Item -ItemType Directory -Path $EvidenceDir | Out-Null
$src=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
$mode='original-053-rollback'
$tuples=@{
 'core'=@('core:neoforge','mutation-build-4fb0a7913e284b12b42e76c48aa5f96c','numen-neoforge-1.21.1-0.1.3-dev.jar','644977E1F8E487719EBC660EA050037CEA52971BCAF6B6BE9C26194B091CCFB1','04bfe4b245201683ae87165d67db70dac3423e56',2595944)
 'rdd'=@('plugins:rdd','mutation-build-6146ec9034f44279b611117c9fefa437','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','F43E78E10A9B86BE67C94D883E7F110EED3E9DBA308B27BBF5CE10948BFF837D','04bfe4b245201683ae87165d67db70dac3423e56',1261662)
 'acx'=@('plugins:acx','mutation-build-367b48b425d54ae5a48845153342fd4f','numen-plugin-acx-1.21.1-0.1.3-dev.jar','F91DB3B6342CF90F96C4D62471DB5BA2E4C8FDECB4D52DF9323C0D7976A7AF6C','842d7ee0123a8ead96a04ef673e0c29a2ff4534c',257694)
 'learner'=@('plugins:learner','mutation-build-c991005bded949bfa2ff7f4cc06c9e24','numen-plugin-learner-1.21.1-0.1.3-dev.jar','110742902A1E00113D2604F3A93481EE9C679FFE4BFA13B61B55EBEEB576A3D1','cb7f8fa7f798ae19e54ac7e22e05a5a53c131e55',642309)
 'worldstate'=@('plugins:worldstate','mutation-build-98aec306de93417e8d563efc62c96cbf','numen-plugin-worldstate-1.21.1-0.1.3-dev.jar','7702327FFBF94E53F12CC403FAA2439AE94C268CE68599CDF2A7C3118C49183B','e4edcb356ff50516e3e145c06b718bdfbf5dce1b',218980)
}
$cases=@('core','rdd','acx','learner','worldstate','wrong-mode','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','missing-source-proof','wrong-root','running','unknown','jarpath','jarname','full','cross-source','cross-module','cross-hash','wrong-size','fixed-size','artifact-escape')
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $f=$tuples[$(if($tuples.ContainsKey($case)){$case}else{'rdd'})]
 $id=$f[1];$md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $f[2];Put $artifact 'rollback-fixture-artifact';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 foreach($v in $tuples.Values){$deploy=$deploy.Replace($v[3],$sha);$policy=$policy.Replace($v[3],$sha)}
 $fixedBytes=if($case -ceq 'fixed-size'){(Get-Item $artifact).Length+1}else{(Get-Item $artifact).Length}
 $policy=$policy.Replace(','+$f[5]+',',','+$fixedBytes+',')
 $policy=$policy.Replace(','+$f[5]+')',','+$fixedBytes+')')
 if($case -eq 'wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-root').Replace([char]92,[char]47))}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $receipt=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$f[0];instance='test';mutationId=$id;sourceHead=$f[4];sourceHeadAfter=$f[4];expectedCommit=$f[4];sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=(Get-Item $artifact).Length}
 if($case -eq 'artifact-escape'){$esc=Join-Path $d 'poison-artifact.jar';Put $esc 'escaped';$receipt.artifact=$esc}
 if($case -eq 'wrong-module'){$receipt.module=if($f[0] -ceq 'plugins:rdd'){'core:neoforge'}else{'plugins:rdd'}}
 if($case -ceq 'cross-source'){$receipt.sourceHeadAfter='0'*40}
 if($case -ceq 'cross-module'){$receipt.module=if($f[0] -ceq 'plugins:learner'){'plugins:worldstate'}else{'plugins:learner'}}
 if($case -ceq 'cross-hash'){$receipt.sha256='F'*64}
 if($case -ceq 'wrong-size'){$receipt.bytes++}
 if($case -eq 'dirty-source'){$receipt.sourceDirtyCountAfter=1}
 if($case -eq 'missing-exit'){$receipt.Remove('gradleExit')}
 if($case -eq 'missing-source-proof'){$receipt.Remove('sourceProof')}
 Put (Join-Path $md 'phase-build.json') ($receipt|ConvertTo-Json)
 # Simulate a partial install that wrote the new jar but crashed before its receipt.
 $dest=Join-Path (Join-Path $root 'mods') $f[2];Put $dest 'installed-new-jar-without-receipt';$destHash=(Get-FileHash $dest).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'old-api';$apiHash=(Get-FileHash $api).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'unrelated';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode '+$mode+' -Instance gpt'
 if($case -eq 'wrong-mode'){$argsText='-Mode original-overnight-frozen -Instance gpt'}
 if($case -eq 'missing-mode'){$argsText='-Instance gpt'}
 if($case -eq 'env-only'){$argsText='-Mode '+$mode}
 if($case -eq 'wrong-instance'){$argsText='-Mode '+$mode+' -Instance test'}
 if($case -eq 'jarname'){$argsText+=' -JarName override.jar'}
 if($case -eq 'full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 $wantedCommit=if($case -eq 'bad-commit'){'0'*40}else{$f[4]}
 $wantedSha=if($case -eq 'bad-sha'){'0'*64}else{$sha}
 $wantedId=if($case -eq 'wrong-mutation'){'mutation-build-67d39fc91753488e9475cc577bd7665e'}else{$id}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$wantedId+' -ExpectedCommit '+$wantedCommit+' -ExpectedSha256 '+$wantedSha+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1;$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure '+$case)}
 $ok=$tuples.ContainsKey($case)
 if(($code -eq 0) -ne $ok){$results+=@{case=$case;exit=$code;passed=$false;expectedSuccess=$ok};Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5);throw ('unexpected '+$case+' exit '+$code)}
 if((Test-Path $poison) -or (Get-FileHash $other).Hash -ne $otherHash){throw ('scope violation '+$case)}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if($receipts.Count -ne 1 -or (Get-FileHash $dest).Hash -ne $sha){throw ('bad rollback '+$case)}
  if($f[0] -ceq 'core:neoforge' -and (Test-Path $api)){throw 'core left duplicate API'}
  $r=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if(!$r.success -or $r.sourceCommit -cne $f[4]){throw 'bad receipt'}
  $expectedBackups=if($f[0] -ceq 'core:neoforge'){2}else{1}
  if($r.module -cne $f[0] -or $r.sha256 -ine $sha -or $r.root -cne $root.Replace([char]92,[char]47) -or @($r.backups).Count -ne $expectedBackups){throw 'exact receipt tuple mismatch'}
  $destBackup=@($r.backups|Where-Object {$_.original -eq $dest})
  if($destBackup.Count -ne 1 -or $destBackup[0].sha256 -ne $destHash){throw 'partial-install destination was not preserved'}
  foreach($backup in $r.backups){
   $expectedOld=if($backup.original -eq $dest){$destHash}elseif($backup.original -eq $api){$apiHash}else{throw 'unexpected exact-tuple backup'}
   if((Get-FileHash $backup.saved).Hash -ne $expectedOld -or $backup.sha256 -ne $expectedOld){throw 'exact-tuple backup not recoverable'}
  }
  if($f[0] -cne 'core:neoforge' -and (Get-FileHash $api).Hash -ne $apiHash){throw 'plugin changed API'}
 }else{
  if((Get-FileHash $dest).Hash -ne $destHash -or (Get-FileHash $api).Hash -ne $apiHash){throw ('refusal wrote mods '+$case)}
  foreach($p in $receipts){if((Get-Content $p.FullName -Raw|ConvertFrom-Json).success){throw 'false success'}}
 }
 $results+=@{case=$case;exit=$code;passed=$true;scope='copied entry, relocated files and fake CIM only; not live rollback'}
}
# After the five rollbacks the old enabled set must satisfy the old bounded-live policy.
$full=Join-Path $EvidenceDir 'full-set';$scripts=Join-Path $full 'scripts';$root=Join-Path $full 'original-live';$mut=Join-Path $full 'mutations'
New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods'),(Join-Path $root 'saves/live'),(Join-Path $root 'shaderpacks') | Out-Null
Put (Join-Path $root 'saves/live/level.dat') 'fixture-level'
Put (Join-Path $root 'shaderpacks/launch-live.bat') 'fixture-batch'
foreach($v in $tuples.Values){Put (Join-Path $root ('mods/'+$v[2])) ('rollback-restored:'+$v[2])}
foreach($n in @('numen-plugin-camera-1.21.1-0.1.3-dev.jar','numen-plugin-experience-1.21.1-0.1.3-dev.jar','numen-plugin-selfcompile-1.21.1-0.1.3-dev.jar','numen-plugin-settlement-1.21.1-0.1.3-dev.jar','minecraft-client-controller-neoforge-1.0.0.jar')){Put (Join-Path $root ('mods/'+$n)) ('kept:'+$n)}
. (Join-Path $PSScriptRoot '../deploy-test-policy.ps1')
. (Join-Path $PSScriptRoot '../bounded-live-launch-policy.ps1')
$names=@(Get-ChildItem -LiteralPath (Join-Path $root 'mods') -Filter '*.jar' | ForEach-Object { $_.Name.ToLowerInvariant() });[Array]::Sort($names,[StringComparer]::Ordinal)
$rows=@($names|ForEach-Object{ $_+'='+((Get-FileHash -LiteralPath (Join-Path $root ('mods/'+$_)) -Algorithm SHA256).Hash.ToLowerInvariant()) })
$sha=[Security.Cryptography.SHA256]::Create();try{$b=[Text.Encoding]::UTF8.GetBytes(($rows -join ([char]10)));$digest=[BitConverter]::ToString($sha.ComputeHash($b)).Replace('-','')}finally{$sha.Dispose()}
Assert-RddBoundedLiveLaunch -Instance gpt -GameDir $root -Save live -LevelOverride '' -Batch (Join-Path $root 'shaderpacks/launch-live.bat') -ExpectedRoot $root -BatchSha ((Get-FileHash (Join-Path $root 'shaderpacks/launch-live.bat') -Algorithm SHA256).Hash) -ModsSha $digest
Write-Output 'PASS restored old set satisfies the old bounded-live launch guard'
# Wiring pin: rollback mode/ids live in the entry and policy; old/new launch digests stay fixed.
$deployText=Get-Content -LiteralPath (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
$policyText=Get-Content -LiteralPath (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
$launchText=Get-Content -LiteralPath (Join-Path $src 'launch-mc.ps1') -Raw -Encoding UTF8
foreach($needle in @('original-053-rollback','mutation-build-98aec306de93417e8d563efc62c96cbf')){if(-not $deployText.Contains($needle)){throw "rollback entry lost: $needle"}}
foreach($needle in @('7702327FFBF94E53F12CC403FAA2439AE94C268CE68599CDF2A7C3118C49183B','644977E1F8E487719EBC660EA050037CEA52971BCAF6B6BE9C26194B091CCFB1','F43E78E10A9B86BE67C94D883E7F110EED3E9DBA308B27BBF5CE10948BFF837D','F91DB3B6342CF90F96C4D62471DB5BA2E4C8FDECB4D52DF9323C0D7976A7AF6C','110742902A1E00113D2604F3A93481EE9C679FFE4BFA13B61B55EBEEB576A3D1')){if(-not $policyText.Contains($needle)){throw "rollback policy lost: $needle"}}
foreach($needle in @('8d7761d94e3ec03dd9516c80a57a8d8537c6c4b3eadd46169856ebbe36ae774a','d11a9a5870dd6cf7a0bb6782c761e2b5aba018e0e563b60acc62650a37c1016a')){if(-not $launchText.Contains($needle)){throw "launch digest lost: $needle"}}
Write-Output 'PASS rollback entry/policy pins and old/new launch digests'
if($results.Count -ne $cases.Count -or $results.Count -eq 0){throw 'incomplete fixture batch'}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
Write-Output ('PASS '+$results.Count+' exact 053 rollback deployment fixtures; no live mods or processes')
exit 0
