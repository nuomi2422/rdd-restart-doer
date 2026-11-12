# 2026-11-11: copied deployment entry; temporary IO and fake CIM only.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path $EvidenceDir){throw 'fresh fixture directory required'}
New-Item -ItemType Directory $EvidenceDir | Out-Null
$src=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
$cases=@('missing','gpt','env-only','bad-sha','bad-receipt','escape','running','unknown','copy-failure','core','rdd','learner','repeat','link','missing-exit','original-learner','original-env-only','original-wrong-instance','original-wrong-mutation','original-bad-sha','original-bad-commit','original-running','original-unknown')
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'test';$live=Join-Path $d 'live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$live,$mut,(Join-Path $root 'mods') | Out-Null
 if($case.StartsWith('original-')){$root=$live;New-Item -ItemType Directory (Join-Path $root 'mods') | Out-Null}
 $module=if($case -in @('rdd','original-wrong-mutation')){'plugins:rdd'}elseif($case -eq 'learner' -or $case.StartsWith('original-')){'plugins:learner'}else{'core:neoforge'}
 $ids=@{'core:neoforge'='ffa63f9a7b714ec6a9168d1b657c8e4d';'plugins:rdd'='0057cbc54b26481194dd1bf413c6a8b4';'plugins:learner'='52876a2a2dd44cc68009c3ad4992de35'}
 $names=@{'core:neoforge'='numen-neoforge-1.21.1-0.1.3-dev.jar';'plugins:rdd'='numen-plugin-rdd-1.21.1-0.1.3-dev.jar';'plugins:learner'='numen-plugin-learner-1.21.1-0.1.3-dev.jar'}
 $id='mutation-build-'+$ids[$module];$md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd -Force | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact 'fixture-new-artifact';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace('\','/')).Replace('D:/rdd/workspace/rdd-selfcompile/instances/test',$root.Replace('\','/')).Replace('D:/rdd/mc/The Best of Twilight Forest',$live.Replace('\','/'))
 $deploy=$deploy.Replace('BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A',$sha)
 Put (Join-Path $scripts 'deploy.ps1') $deploy
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw
 foreach($old in @('D8999610E5777B4A8F087C5C59C86C1D54E3187BF0C50EDA520D88DF6E97D056','E69DBC81A5C4539F83809FBFF89D693295750754ED7278B2B00566B08F007435','BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A')){$policy=$policy.Replace($old,$sha)}
 # Fixture artifact digest is relocated with the fixture source, not treated as production proof.
 if($case -eq 'copy-failure'){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture copy failure'")}
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$live.Replace('\','/'))
 Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit='65ffba3ecdd9171eb59af470ba275f9e6655900f'
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=(Get-Item $artifact).Length}
 if($case -eq 'bad-receipt'){$r.sourceDirtyCountAfter=1}
 if($case -eq 'missing-exit'){$r.Remove('gradleExit')}
 if($case -eq 'escape'){$r.artifact=Join-Path $live $names[$module]}
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'old-module'
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'old-api'
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'unchanged';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -in @('running','original-running')){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -in @('unknown','original-unknown')){'throw "CIM unavailable"'}else{'return @()'}
 if($case -eq 'link'){
  # Junction creation only inside fixture: consumer must reject the source parent.
  $payload=Join-Path $d 'source-jar-payload'
  if([IO.Path]::GetFullPath($jd) -ne [IO.Path]::GetFullPath((Join-Path $md 'jar')) -or (Test-Path $payload)){throw 'unsafe fixture relocation'}
  [IO.Directory]::Move($jd,$payload)
  New-Item -ItemType Junction -Path $jd -Target $payload | Out-Null
  # phase artifact remains the exact expected mutation/jar path.
 }
 $argsText="-Mode isolated-test -Instance test"
 if($case -eq 'missing'){$argsText=''}elseif($case -eq 'gpt'){$argsText='-Mode isolated-test -Instance gpt'}elseif($case -eq 'env-only'){$argsText='-Mode isolated-test'}
 if($case.StartsWith('original-')){$argsText='-Mode original-learner -Instance gpt'}
 if($case -eq 'original-env-only'){$argsText='-Mode original-learner'}
 if($case -eq 'original-wrong-instance'){$argsText='-Mode original-learner -Instance test'}
 if($case -eq 'original-bad-commit'){$commit='0'*40}
 $wanted=if($case -in @('bad-sha','original-bad-sha')){'0'*64}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+''+$(if($case -eq 'missing-sha'){''}else{' -ExpectedSha256 '+$wanted})+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -in @('core','rdd','learner','repeat','original-learner')
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('script parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected case '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'poison invoked'}
 if($case -eq 'link' -and ($output -join ' ') -notmatch 'linked\s+path\s+refu\s*sed'){throw 'root-link did not reach link guard'}
 if($case -eq 'missing-exit' -and ($output -join ' ') -notmatch 'invalid\s+build receipt'){throw 'missing-exit wrong refusal'}
 if((Get-FileHash $other).Hash -ne $otherHash){throw 'other mod modified'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if((Get-FileHash $old -Algorithm SHA256).Hash -ne $sha){throw 'copy sha mismatch'}
  if($module -eq 'core:neoforge' -and (Test-Path $api)){throw 'api not isolated'}
  $first=(Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json);$saved=@($first.backups|ForEach-Object {$_.saved})
  foreach($s in $saved){if(-not(Test-Path $s)){throw 'missing backup'}}
  if($case -eq 'repeat'){
   $before=@($saved|ForEach-Object {(Get-FileHash $_).Hash})
   $output=& powershell.exe -NoProfile -File $runner 2>&1
   if($LASTEXITCODE -ne 0){throw 'repeat failed'}
   for($i=0;$i -lt $saved.Count;$i++){if((Get-FileHash $saved[$i]).Hash -ne $before[$i]){throw 'original backup lost'}}
  }
 }else{foreach($receipt in $receipts){if((Get-Content $receipt.FullName -Raw | ConvertFrom-Json).success){throw 'failure signed success'}}}
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='temporary copied entry and fixture hashes/CIM only'}
}

# 2026-11-12: exercise the accepted-integration entry with relocated files/CIM only.
$acceptedCases=@('accepted-core','accepted-rdd','accepted-learner','accepted-env-only','accepted-wrong-instance','accepted-wrong-mutation','accepted-bad-commit','accepted-bad-sha','accepted-nonzero-exit','accepted-missing-exit','accepted-dirty-source','accepted-running','accepted-unknown','accepted-jarpath','accepted-full','next-core','next-learner','next-rdd','next-wrong-instance','next-wrong-mutation','next-bad-commit','next-bad-sha','next-running','next-unknown','next-full','e826-core','e826-rdd','e826-learner','e826-wrong-instance','e826-wrong-mutation','e826-bad-commit','e826-bad-sha','e826-wrong-module','e826-running','e826-unknown','e826-wrong-root','e826-jarpath','e826-full')
$acceptedIds=@{'core:neoforge'='14e46e1075514aed872cd27fe75b4a4a';'plugins:rdd'='34ab8109f7e042559e1de20539924c4d';'plugins:learner'='7130759b9c3044de8a1a8da8c5d1d881'}
$acceptedHashes=@('5BB40E1D16A1EEB3BAA67CA44997E51474641DE294BF4B2FC0A7E65E1F3BDF36','8CFDF0C65330BED70D9B32FC044CEB6A70DB893C759CCA96F9EF8CE4B01CE55C','47EE06D8B870E3C1484E68AD366ECCBABCC5C2E71CA9422B7513FFC9BE53B2C7','D7170FF629AF27CE7506929CC4CCCC364E38563691D8454C51C767551E34F8E0','DE809C7F8EADB2ECF92346471EA71749D42981633B9B6C00FF023A74E9F627CD','6721990F3A46121021BA13AD6721F664662AF4B2432EE36368BA2A4A2FE1A637','E7C047BBB321AC431346541291BE8CB493CB26B3329C58011E65BE2210297F9E','F5D92CB111AB07B8345E820E79801E9B3ED27E45A27A7F9FD0C9C50CF4DE0FD7')
foreach($case in $acceptedCases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $isNext=$case.StartsWith('next-');$isE826=$case.StartsWith('e826-')
 $module=if($case -in @('accepted-rdd','next-rdd','e826-rdd')){'plugins:rdd'}elseif($case -in @('accepted-core','next-core','e826-core')){'core:neoforge'}else{'plugins:learner'}
 $nextIds=@{'core:neoforge'='c9ac2a7723fa4674911de387184698c9';'plugins:learner'='bd0bcda5f6d245ecad714b5f4f022afd'}
 $e826Ids=@{'core:neoforge'='1dd867b5ae6a49c7aecc728e958d5dd8';'plugins:rdd'='674cea78df824d24b8039ff3f940f0e4';'plugins:learner'='cbb5ea3bc0804bc9ae6a6244c1b68c23'}
 $id='mutation-build-'+$(if($isE826){$e826Ids[$module]}elseif($isNext -and $module -ne 'plugins:rdd'){$nextIds[$module]}else{$acceptedIds[$module]});$md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact 'accepted-integration-fixture';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace('\','/')).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace('\','/'))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace('\','/'))
 if($case -eq 'e826-wrong-root'){$policy=$policy.Replace($root.Replace('\','/'),(Join-Path $d 'other-live').Replace('\','/'))}
 foreach($hash in $acceptedHashes){$deploy=$deploy.Replace($hash,$sha);$policy=$policy.Replace($hash,$sha)}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit=if($isE826){'e826813d962090dccaca62e03513079ca3a1fb7a'}elseif($isNext){'330b6f5b2b1fdc814d0e8d5ff2337fe11825ef73'}else{'bb0f1fd8507d82c4a3d3f9ecc9c6aa5fe5fb94ec'}
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=(Get-Item $artifact).Length}
 if($case -eq 'accepted-nonzero-exit'){$r.gradleExit=1}
 if($case -eq 'e826-wrong-module'){$r.module='core:neoforge'}
 if($case -eq 'accepted-missing-exit'){$r.Remove('gradleExit')}
 if($case -eq 'accepted-dirty-source'){$r.sourceDirtyCountAfter=1}
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'accepted-old-module';$oldHash=(Get-FileHash $old).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'accepted-old-api';$apiHash=(Get-FileHash $api).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'accepted-unchanged';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -in @('accepted-running','next-running','e826-running')){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -in @('accepted-unknown','next-unknown','e826-unknown')){'throw "CIM unavailable"'}else{'return @()'}
 $argsText=if($isE826){'-Mode original-e826 -Instance gpt'}elseif($isNext){'-Mode original-next-verified -Instance gpt'}else{'-Mode original-accepted -Instance gpt'}
 if($case -eq 'e826-wrong-instance'){$argsText='-Mode original-e826 -Instance test'}
 if($case -eq 'accepted-env-only'){$argsText='-Mode original-accepted'}
 if($case -in @('accepted-wrong-instance','next-wrong-instance')){$argsText=if($isNext){'-Mode original-next-verified -Instance test'}else{'-Mode original-accepted -Instance test'}}
 if($case -in @('accepted-full','next-full','e826-full')){$argsText='-Mode full -Instance gpt'}
 if($case -in @('accepted-jarpath','e826-jarpath')){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -in @('accepted-bad-commit','next-bad-commit','e826-bad-commit')){$commit='0'*40}
 if($case -in @('accepted-wrong-mutation','next-wrong-mutation','e826-wrong-mutation')){$id='mutation-build-not-accepted'}
 $wanted=if($case -in @('accepted-bad-sha','next-bad-sha','e826-bad-sha')){'0'*64}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -in @('accepted-core','accepted-rdd','accepted-learner','next-core','next-learner','e826-core','e826-rdd','e826-learner')
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('script parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected case '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'accepted entry invoked generic config/launch'}
 if((Get-FileHash $other).Hash -ne $otherHash){throw 'accepted entry modified other mod'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if((Get-FileHash $old).Hash -ne $sha -or $receipts.Count -ne 1){throw 'accepted deploy output mismatch'}
  if($module -eq 'core:neoforge' -and (Test-Path $api)){throw 'accepted core left standalone API'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.success -ne $true -or $receipt.sourceCommit -cne $commit){throw 'accepted receipt invalid'}
  foreach($backup in $receipt.backups){if(-not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $backup.sha256){throw 'accepted backup mismatch'}}
 }else{
  if((Get-FileHash $old).Hash -ne $oldHash -or (Get-FileHash $api).Hash -ne $apiHash){throw 'refused accepted entry modified mods'}
  foreach($receipt in $receipts){if((Get-Content $receipt.FullName -Raw | ConvertFrom-Json).success){throw 'refused accepted entry signed success'}}
 }
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='temporary accepted tuple/CIM fixture; no production deploy'}
}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 4)
Write-Output ('PASS '+$results.Count+' isolated test-deploy cases; no production entry/CIM/config')
# Do not leak the expected nonzero exit from the final refusal fixture.
exit 0
