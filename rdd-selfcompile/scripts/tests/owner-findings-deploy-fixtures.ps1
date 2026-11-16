# 2026-11-12: copied exact four-artifact deployment entry; temporary files/fake CIM, never live IO.
param([Parameter(Mandatory=$true)][string]$EvidenceDir,[ValidateSet('owner-findings','runtime-followups','transport-external','mine-recovery','lh1-prep','class-split','pending-death-b650','recovering-b2c')][string]$Batch='owner-findings')
$ErrorActionPreference='Stop'
$singleRdd=$Batch -cin @('pending-death-b650','recovering-b2c')
$exactTuple=$singleRdd -or $Batch -cin @('lh1-prep','class-split')
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
$mode='original-owner-findings'
if($Batch -ceq 'runtime-followups'){
 $commit='842d7ee0123a8ead96a04ef673e0c29a2ff4534c';$mode='original-runtime-followups'
 $tuples=@{
  'core'=@('core:neoforge','mutation-build-c0961c5a6e3b46edb927a3236be61058','numen-neoforge-1.21.1-0.1.3-dev.jar','F11A3B6A2459F3D1ED1F792C682C315326E1A8C10AC95DCB5B9DDF331399E1EB')
  'rdd'=@('plugins:rdd','mutation-build-6ed6b106a2c646018015ee3bc29967cd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','894F7C5E3C08784D75CED0405BC6780976C7A2A8F48C5579C870A51CCD7BB6E5')
  'learner'=@('plugins:learner','mutation-build-dd6531bb6a114bdc85cb01235537e15e','numen-plugin-learner-1.21.1-0.1.3-dev.jar','20F1E8AC2F467880A0728F6161CFE5A250BF21CB4C4381428DE77934A3238D3B')
  'acx'=@('plugins:acx','mutation-build-367b48b425d54ae5a48845153342fd4f','numen-plugin-acx-1.21.1-0.1.3-dev.jar','F91DB3B6342CF90F96C4D62471DB5BA2E4C8FDECB4D52DF9323C0D7976A7AF6C')
 }
}
if($Batch -ceq 'transport-external'){
 $commit='f7b7c48a1ebbf93dd79e04bc6e596872c187273e';$mode='original-transport-external'
 $tuples=@{'core'=@('core:neoforge','mutation-build-4f56fc55b7be483cab7f8e24579d9749','numen-neoforge-1.21.1-0.1.3-dev.jar','AF772A3F55B206F13E464807F7897FB1F85759A22D92F2D21F0F328336E8CD19')}
}
# 2026-11-12: the inspected 702ea core only; copied scripts, fake CIM and relocated IO.
if($Batch -ceq 'mine-recovery'){
 $commit='78c3fd296145c79dd3bad5dda643641b2ccf2a70';$mode='original-mine-recovery'
 $tuples=@{'core'=@('core:neoforge','mutation-build-702ea0b018534536977499b23ccee172','numen-neoforge-1.21.1-0.1.3-dev.jar','789EF0A21435E7939058E2EDEF74F078386EF2BB7B9E296D54EDF0091FA97E67')}
}
$last=if($Batch -ceq 'runtime-followups'){'acx'}else{'camera'}
$cases=@('core','rdd','learner',$last,'missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','wrong-root','running','unknown','jarpath','full')
if($Batch -ceq 'transport-external'){$cases=@('core','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','wrong-root','running','unknown','jarpath','full','rejected-fde74')}
if($Batch -ceq 'mine-recovery'){$cases=@('wrong-mode','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','missing-source-proof','wrong-root','running','unknown','jarpath','jarname','full','rejected-fde74','core')}
if($Batch -ceq 'lh1-prep'){
 $mode='original-lh1-prep'
 $tuples=@{
  'core'=@('core:neoforge','mutation-build-61d0b49492df4d238143c230a1a6ed40','numen-neoforge-1.21.1-0.1.3-dev.jar','6C1BB8D816A8486F735C94D464D9933DA78F0899839B9F2596328B33CDA3ABF5','ab8cc639e9f69fae10c46216e6ad85cf95789815',2587339)
  'learner'=@('plugins:learner','mutation-build-a19f8a022a5c4f39871cafda0bdbdc06','numen-plugin-learner-1.21.1-0.1.3-dev.jar','FEE71CF0C84F30D0BDF38BEDC9C0E0B608BEE500A5F504E079FBB827CC83A897','03f290fdb510438dc17c07be2b84407ec7f8fec2',641209)
 }
 $cases=@('core','learner','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','missing-source-proof','wrong-root','running','unknown','jarpath','jarname','full','cross-source','cross-module','cross-hash','wrong-size','fixed-size')
}
# 2026-11-16: class-split shares LH1's exact-tuple controls, but both sources have the same commit.
if($Batch -ceq 'class-split'){
 $mode='original-class-split'
 $tuples=@{
  'core'=@('core:neoforge','mutation-build-60d0165f55ac4b7f9c61281e9cdc1663','numen-neoforge-1.21.1-0.1.3-dev.jar','0200317C9BE01B46DF7087900063F021127FF5F4A16546E858D243B6B85CE900','7f09b9587731fa5caca670169ad1ff51298b3e81',2588931)
  'rdd'=@('plugins:rdd','mutation-build-8ea1cec5df834d04bcb90077743187d7','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','40BFD00E914D3781616E5D13BF2A07FBB344445C72D78C4693459DE6879EB80D','7f09b9587731fa5caca670169ad1ff51298b3e81',1210867)
 }
 $cases=@('core','rdd','wrong-mode','isolated-test','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','missing-source-proof','wrong-root','running','unknown','jarpath','jarname','full','cross-source','cross-module','cross-hash','wrong-size','fixed-size')
}
# 2026-11-16: only the pending-death RDD successor; every negative case selects that RDD tuple.
if($Batch -ceq 'pending-death-b650'){
 $mode='original-pending-death-b650'
 $tuples=@{'rdd'=@('plugins:rdd','mutation-build-ea8be9aa893543648b3784c6e8597f27','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','0D91487B6244722459FABE96CAD4DC971B9C825FAC308AE9347687FAAA11E713','b650e75f0f5244a72f175c03679bdfd742a88ee2',1213368)}
}
if($Batch -ceq 'recovering-b2c'){
 $mode='original-recovering-b2c'
 $tuples=@{'rdd'=@('plugins:rdd','mutation-build-5ba3aaaeec62478f860acefd1b24bcf1','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','0DEF5F96DB0CA315EB2F15A2B3CE816A5C46D7FC11F47CD2DE67A67F7F6477D3','b2c31651979645a1007130465e5df3eee3e09ea8',1213395)}
}
if($singleRdd){
 $cases=@('rdd','wrong-mode','isolated-test','missing-mode','env-only','wrong-instance','bad-commit','bad-sha','wrong-mutation','wrong-module','dirty-source','missing-exit','missing-source-proof','wrong-root','running','unknown','jarpath','jarname','full','cross-source','cross-module','cross-hash','wrong-size','fixed-size','class-split-purpose','lh1-prep-purpose')
 if($Batch -ceq 'recovering-b2c'){$cases+='pending-death-purpose'}
}
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $f=$tuples[$(if($tuples.ContainsKey($case)){$case}elseif($Batch -cin @('transport-external','mine-recovery','lh1-prep','class-split')){'core'}else{'rdd'})]
 $id=$f[1];$md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 if($exactTuple){$commit=$f[4]}
 $artifact=Join-Path $jd $f[2];Put $artifact 'owner-findings-fixture-artifact';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 foreach($v in $tuples.Values){
  $replacement=if($exactTuple -and $v[1] -cne $id){'F'*64}else{$sha}
  $deploy=$deploy.Replace($v[3],$replacement);$policy=$policy.Replace($v[3],$replacement)
 }
 if($exactTuple){
  $fixedLength=if($case -ceq 'fixed-size'){(Get-Item $artifact).Length+1}else{(Get-Item $artifact).Length}
  $policy=$policy.Replace(','+$f[5]+')',','+$fixedLength+')')
 }
 if($case -eq 'wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-root').Replace([char]92,[char]47))}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $receipt=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$f[0];instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=(Get-Item $artifact).Length}
 if($case -eq 'wrong-module'){$receipt.module=if($Batch -cin @('transport-external','mine-recovery','lh1-prep','class-split')){'plugins:rdd'}else{'core:neoforge'}}
 if($exactTuple){
  if($case -ceq 'cross-source'){$receipt.sourceHeadAfter=if(($singleRdd -or $Batch -ceq 'class-split')){'0'*40}else{$tuples['learner'][4]}}
  if($case -ceq 'cross-module'){$receipt.module=if($singleRdd){'core:neoforge'}elseif($Batch -ceq 'class-split'){$tuples['rdd'][0]}else{'plugins:learner'}}
  if($case -ceq 'cross-hash'){$receipt.sha256='F'*64}
  if($case -ceq 'wrong-size'){$receipt.bytes++}
 }
 if($exactTuple -and $case -cin @('wrong-module','cross-module') -and $receipt.module -ceq $f[0]){throw ('ineffective module negative control '+$case)}
 if($case -eq 'dirty-source'){$receipt.sourceDirtyCountAfter=1}
 if($case -eq 'missing-exit'){$receipt.Remove('gradleExit')}
 if($case -eq 'missing-source-proof'){$receipt.Remove('sourceProof')}
 Put (Join-Path $md 'phase-build.json') ($receipt|ConvertTo-Json)
 $dest=Join-Path (Join-Path $root 'mods') $f[2];Put $dest 'old-artifact';$oldHash=(Get-FileHash $dest).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'old-api';$apiHash=(Get-FileHash $api).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'unrelated';$otherHash=(Get-FileHash $other).Hash
 if($singleRdd){
  $core=Join-Path (Join-Path $root 'mods') 'numen-neoforge-1.21.1-0.1.3-dev.jar';Put $core 'old-core';$coreHash=(Get-FileHash $core).Hash
 }
 $cim=if($case -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode '+$mode+' -Instance gpt'
 if($case -eq 'wrong-mode'){$argsText='-Mode original-transport-external -Instance gpt'}
 if($case -eq 'isolated-test'){$argsText='-Mode isolated-test -Instance test'}
 if($case -ceq 'pending-death-purpose'){$argsText='-Mode original-pending-death-b650 -Instance gpt'}
 if($case -ceq 'class-split-purpose'){$argsText='-Mode original-class-split -Instance gpt'}
 if($case -ceq 'lh1-prep-purpose'){$argsText='-Mode original-lh1-prep -Instance gpt'}
 if($case -eq 'jarname'){$argsText+=' -JarName override.jar'}
 if($case -eq 'missing-mode'){$argsText='-Instance gpt'}
 if($case -eq 'env-only'){$argsText='-Mode '+$mode}
 if($case -eq 'wrong-instance'){$argsText='-Mode '+$mode+' -Instance test'}
 if($case -eq 'full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 $wantedCommit=if($case -eq 'bad-commit'){'0'*40}else{$commit}
 $wantedSha=if($case -eq 'bad-sha'){'0'*64}else{$sha}
 $wantedId=if($case -eq 'wrong-mutation'){'mutation-build-not-approved'}else{$id}
 if($case -eq 'rejected-fde74'){$wantedId='mutation-build-ee21dad901a8440ba35ca559f8a70128';$wantedCommit='fde74e3b44e1b7cc9629b5554655f6fbecd46262';$wantedSha='DAF28A57B950EA13EC351559AEE96962C6798AF52EC407B6F06F46C0A2C7DDAA'}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$wantedId+' -ExpectedCommit '+$wantedCommit+' -ExpectedSha256 '+$wantedSha+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1;$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure '+$case)}
 $guardOutput=($output -join '') -replace '\s',''
 if($Batch -ceq 'class-split' -and $case -ceq 'isolated-test' -and $guardOutput -notmatch 'class-splitrequiresoriginaldeployment'){throw 'isolated class-split source guard not reached'}
 if($Batch -ceq 'pending-death-b650' -and $case -ceq 'isolated-test' -and $guardOutput -notmatch 'pending-deathb650requiresoriginaldeployment'){throw 'isolated pending-death source guard not reached'}
 if($Batch -ceq 'recovering-b2c' -and $case -ceq 'isolated-test' -and $guardOutput -notmatch 'recoveringb2crequiresoriginaldeployment'){throw 'isolated recovering source guard not reached'}
 $ok=$tuples.ContainsKey($case)
 if(($code -eq 0) -ne $ok){
  if($Batch -ceq 'mine-recovery'){
   $results+=@{case=$case;exit=$code;passed=$false;expectedSuccess=$ok;scope='copied entry, relocated files and fake CIM only; not live deploy'}
   Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
  }
  throw ('unexpected '+$case+' exit '+$code)
 }
 if((Test-Path $poison) -or (Get-FileHash $other).Hash -ne $otherHash){throw ('scope violation '+$case)}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if($receipts.Count -ne 1 -or (Get-FileHash $dest).Hash -ne $sha){throw ('bad deployment '+$case)}
  if($f[0] -eq 'core:neoforge' -and (Test-Path $api)){throw 'core left duplicate API'}
  $r=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if(!$r.success -or $r.sourceCommit -cne $commit){throw 'bad receipt'}
  if($exactTuple){
   $expectedBackups=if($f[0] -ceq 'core:neoforge'){2}else{1}
   if($r.module -cne $f[0] -or $r.sha256 -ine $sha -or $r.root -cne $root.Replace([char]92,[char]47) -or @($r.backups).Count -ne $expectedBackups){throw 'exact receipt tuple mismatch'}
   foreach($backup in $r.backups){
    $expectedOld=if($backup.original -eq $dest){$oldHash}elseif($backup.original -eq $api){$apiHash}else{throw 'unexpected exact-tuple backup'}
    if((Get-FileHash $backup.saved).Hash -ne $expectedOld -or $backup.sha256 -ne $expectedOld){throw 'exact-tuple backup not recoverable'}
   }
   if($f[0] -cne 'core:neoforge' -and (Get-FileHash $api).Hash -ne $apiHash){throw 'plugin changed API'}
  }
  if($Batch -ceq 'mine-recovery'){
   if($r.root -cne $root.Replace([char]92,[char]47) -or $r.backups.Count -ne 2){throw 'bad fixed root or backup count'}
   $coreBackup=@($r.backups|Where-Object {$_.original -eq $dest});$apiBackup=@($r.backups|Where-Object {$_.original -eq $api})
   if($coreBackup.Count -ne 1 -or $apiBackup.Count -ne 1 -or $coreBackup[0].sha256 -cne $oldHash -or $apiBackup[0].sha256 -cne $apiHash){throw 'old core/API backup identity mismatch'}
  }
  foreach($b in $r.backups){if((Get-FileHash $b.saved).Hash -ne $b.sha256){throw 'bad backup'}}
 }else{
  if((Get-FileHash $dest).Hash -ne $oldHash -or (Get-FileHash $api).Hash -ne $apiHash){throw ('refusal wrote mods '+$case)}
  foreach($p in $receipts){if((Get-Content $p.FullName -Raw|ConvertFrom-Json).success){throw 'false success'}}
 }
 if($singleRdd -and ((Get-FileHash $core).Hash -ne $coreHash -or (Get-FileHash $api).Hash -ne $apiHash)){throw ('RDD changed core '+$case)}
 $result=@{case=$case;exit=$code;passed=$true;scope='copied entry, relocated files and fake CIM only; not live deploy'}
 if($singleRdd){$result.coreHashBefore=$coreHash;$result.coreHashAfter=(Get-FileHash $core).Hash;$result.apiHashBefore=$apiHash;$result.apiHashAfter=(Get-FileHash $api).Hash;$result.unrelatedHashBefore=$otherHash;$result.unrelatedHashAfter=(Get-FileHash $other).Hash}
 $results+=$result
}
if($results.Count -ne $cases.Count -or $results.Count -eq 0){throw 'incomplete fixture batch'}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
Write-Output ('PASS '+$results.Count+' exact owner findings deployment fixtures; no live mods or processes')
exit 0
