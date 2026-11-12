# 2026-11-12: copied exact four-artifact deployment entry; temporary files/fake CIM, never live IO.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $EvidenceDir){throw 'fresh fixture directory required'}
New-Item -ItemType Directory -Path $EvidenceDir | Out-Null
$src=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
$commit='4b2f202b3b8df1fa3d54f9961a26c273ef36f9d0'
$tuples=@{
 'core'=@('core:neoforge','mutation-build-1fb466ca58004f7d83afd093013d68c3','numen-neoforge-1.21.1-0.1.3-dev.jar','524966B50E335424F7B9D252C5DEF8F61702C11EABC1E5C80AB79C7C1AFBDC1A')
 'rdd'=@('plugins:rdd','mutation-build-937966ec05724882916105cd45f470b4','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','C4A9403A6A6F45E9D7846F0B88B89BE3D36D8EB706CD11BC35404E192697653F')
 'learner'=@('plugins:learner','mutation-build-f0a3c69242714cde8d1152170c1fe931','numen-plugin-learner-1.21.1-0.1.3-dev.jar','FDDAF2A2431CECB6A059107907F081140D3AF4EC07888BC0E3079261253F8C0F')
 'camera'=@('plugins:camera','mutation-build-aea5643ec50a4601a4663e945af7162f','numen-plugin-camera-1.21.1-0.1.3-dev.jar','1BBCF6E88F2866E1D117C04AC758DFF952A61E6F24E00ACC2F81BC93596F3FD8')
}
$cases=@('core','rdd','learner','camera','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','wrong-root','running','unknown','jarpath','full')
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $f=$tuples[$(if($tuples.ContainsKey($case)){$case}else{'rdd'})]
 $id=$f[1];$md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $f[2];Put $artifact 'owner-findings-fixture-artifact';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 foreach($v in $tuples.Values){$deploy=$deploy.Replace($v[3],$sha);$policy=$policy.Replace($v[3],$sha)}
 if($case -eq 'wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-root').Replace([char]92,[char]47))}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $receipt=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$f[0];instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=(Get-Item $artifact).Length}
 if($case -eq 'wrong-module'){$receipt.module='core:neoforge'}
 if($case -eq 'dirty-source'){$receipt.sourceDirtyCountAfter=1}
 if($case -eq 'missing-exit'){$receipt.Remove('gradleExit')}
 Put (Join-Path $md 'phase-build.json') ($receipt|ConvertTo-Json)
 $dest=Join-Path (Join-Path $root 'mods') $f[2];Put $dest 'old-artifact';$oldHash=(Get-FileHash $dest).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'old-api';$apiHash=(Get-FileHash $api).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'unrelated';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-owner-findings -Instance gpt'
 if($case -eq 'missing-mode'){$argsText='-Instance gpt'}
 if($case -eq 'env-only'){$argsText='-Mode original-owner-findings'}
 if($case -eq 'wrong-instance'){$argsText='-Mode original-owner-findings -Instance test'}
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
 if(($code -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$code)}
 if((Test-Path $poison) -or (Get-FileHash $other).Hash -ne $otherHash){throw ('scope violation '+$case)}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if($receipts.Count -ne 1 -or (Get-FileHash $dest).Hash -ne $sha){throw ('bad deployment '+$case)}
  if($f[0] -eq 'core:neoforge' -and (Test-Path $api)){throw 'core left duplicate API'}
  $r=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if(!$r.success -or $r.sourceCommit -cne $commit){throw 'bad receipt'}
  foreach($b in $r.backups){if((Get-FileHash $b.saved).Hash -ne $b.sha256){throw 'bad backup'}}
 }else{
  if((Get-FileHash $dest).Hash -ne $oldHash -or (Get-FileHash $api).Hash -ne $apiHash){throw ('refusal wrote mods '+$case)}
  foreach($p in $receipts){if((Get-Content $p.FullName -Raw|ConvertFrom-Json).success){throw 'false success'}}
 }
 $results+=@{case=$case;exit=$code;passed=$true;scope='copied entry, relocated files and fake CIM only; not live deploy'}
}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
Write-Output ('PASS '+$results.Count+' exact owner findings deployment fixtures; no live mods or processes')
exit 0
