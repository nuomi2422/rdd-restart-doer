# 2026-11-19: copied exact five-artifact deployment entry for frozen combo 3f3be4e1;
# temporary files and fake CIM only, never live IO, Java, or a real deployment.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $EvidenceDir){throw 'fresh fixture directory required'}
New-Item -ItemType Directory -Path $EvidenceDir | Out-Null
$src=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
$commit='3f3be4e1e84e378e5ce0d5e20f8ba84ac95a17bc'
$mode='original-overnight-frozen'
$tuples=@{
 'core'=@('core:neoforge','mutation-build-67d39fc91753488e9475cc577bd7665e','numen-neoforge-1.21.1-0.1.3-dev.jar','F65B775B6E1DD2F5D8AA67C524CD5312DF00981A85E904C586DE41C17AAD708E',$commit,2613563)
 'rdd'=@('plugins:rdd','mutation-build-66e83074983b4bca9b6bba9816d7ee0b','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','3EF328E25F6E3314B16861D7D6B2148D8DC99939C4D904F488320CD88AF25740',$commit,1307211)
 'acx'=@('plugins:acx','mutation-build-bcbf2154bfa84a0b90ee87b9e5f1cef3','numen-plugin-acx-1.21.1-0.1.3-dev.jar','308215FAE9FD7038FB52D2AEA15EEA33794DE89C7B966AECD5E1AA4F24CCEE58',$commit,293542)
 'learner'=@('plugins:learner','mutation-build-00c23bbe3d334bd99c2028f7e8b12caa','numen-plugin-learner-1.21.1-0.1.3-dev.jar','CE76DB2C99CC418E9C85794EFB57A51E0CA6BE7CF9B861E4DDFB5A3D84EFA2E8',$commit,648961)
 'worldstate'=@('plugins:worldstate','mutation-build-6c91f476298f4f46a941ec656a4983e1','numen-plugin-worldstate-1.21.1-0.1.3-dev.jar','6C605D652A70C7A61779FE20021842763AC937D2379B49EC771418F67C1F79FB',$commit,230879)
}
$cases=@('core','rdd','acx','learner','worldstate','wrong-mode','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','missing-source-proof','wrong-root','running','unknown','jarpath','jarname','full','cross-source','cross-module','cross-hash','wrong-size','fixed-size')
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $f=$tuples[$(if($tuples.ContainsKey($case)){$case}else{'rdd'})]
 $id=$f[1];$md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $f[2];Put $artifact 'overnight-frozen-fixture-artifact';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 foreach($v in $tuples.Values){$deploy=$deploy.Replace($v[3],$sha);$policy=$policy.Replace($v[3],$sha)}
 $fixedLength=if($case -ceq 'fixed-size'){(Get-Item $artifact).Length+1}else{(Get-Item $artifact).Length}
 $policy=$policy.Replace(','+$f[5]+',',','+$fixedLength+',')
 if($case -eq 'wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-root').Replace([char]92,[char]47))}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $receipt=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$f[0];instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=(Get-Item $artifact).Length}
 if($case -eq 'wrong-module'){$receipt.module=if($f[0] -ceq 'plugins:rdd'){'core:neoforge'}else{'plugins:rdd'}}
 if($case -ceq 'cross-source'){$receipt.sourceHeadAfter='0'*40}
 if($case -ceq 'cross-module'){$receipt.module=if($f[0] -ceq 'plugins:learner'){'plugins:worldstate'}else{'plugins:learner'}}
 if($case -ceq 'cross-hash'){$receipt.sha256='F'*64}
 if($case -ceq 'wrong-size'){$receipt.bytes++}
 if($case -eq 'dirty-source'){$receipt.sourceDirtyCountAfter=1}
 if($case -eq 'missing-exit'){$receipt.Remove('gradleExit')}
 if($case -eq 'missing-source-proof'){$receipt.Remove('sourceProof')}
 Put (Join-Path $md 'phase-build.json') ($receipt|ConvertTo-Json)
 $dest=Join-Path (Join-Path $root 'mods') $f[2];Put $dest 'old-artifact';$oldHash=(Get-FileHash $dest).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'old-api';$apiHash=(Get-FileHash $api).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'unrelated';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode '+$mode+' -Instance gpt'
 if($case -eq 'wrong-mode'){$argsText='-Mode original-runtime-followups -Instance gpt'}
 if($case -eq 'missing-mode'){$argsText='-Instance gpt'}
 if($case -eq 'env-only'){$argsText='-Mode '+$mode}
 if($case -eq 'wrong-instance'){$argsText='-Mode '+$mode+' -Instance test'}
 if($case -eq 'jarname'){$argsText+=' -JarName override.jar'}
 if($case -eq 'full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 $wantedCommit=if($case -eq 'bad-commit'){'0'*40}else{$commit}
 $wantedSha=if($case -eq 'bad-sha'){'0'*64}else{$sha}
 $wantedId=if($case -eq 'wrong-mutation'){'mutation-build-not-approved'}else{$id}
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
  if($receipts.Count -ne 1 -or (Get-FileHash $dest).Hash -ne $sha){throw ('bad deployment '+$case)}
  if($f[0] -ceq 'core:neoforge' -and (Test-Path $api)){throw 'core left duplicate API'}
  $r=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if(!$r.success -or $r.sourceCommit -cne $commit){throw 'bad receipt'}
  $expectedBackups=if($f[0] -ceq 'core:neoforge'){2}else{1}
  if($r.module -cne $f[0] -or $r.sha256 -ine $sha -or $r.root -cne $root.Replace([char]92,[char]47) -or @($r.backups).Count -ne $expectedBackups){throw 'exact receipt tuple mismatch'}
  foreach($backup in $r.backups){
   $expectedOld=if($backup.original -eq $dest){$oldHash}elseif($backup.original -eq $api){$apiHash}else{throw 'unexpected exact-tuple backup'}
   if((Get-FileHash $backup.saved).Hash -ne $expectedOld -or $backup.sha256 -ne $expectedOld){throw 'exact-tuple backup not recoverable'}
  }
  if($f[0] -cne 'core:neoforge' -and (Get-FileHash $api).Hash -ne $apiHash){throw 'plugin changed API'}
 }else{
  if((Get-FileHash $dest).Hash -ne $oldHash -or (Get-FileHash $api).Hash -ne $apiHash){throw ('refusal wrote mods '+$case)}
  foreach($p in $receipts){if((Get-Content $p.FullName -Raw|ConvertFrom-Json).success){throw 'false success'}}
 }
 $results+=@{case=$case;exit=$code;passed=$true;scope='copied entry, relocated files and fake CIM only; not live deploy'}
}
if($results.Count -ne $cases.Count -or $results.Count -eq 0){throw 'incomplete fixture batch'}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
Write-Output ('PASS '+$results.Count+' exact overnight-frozen deployment fixtures; no live mods or processes')
exit 0
