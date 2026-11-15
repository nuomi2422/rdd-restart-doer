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
# 2026-11-13: exercise the exact reviewed 25b6 two-artifact branch against relocated files/CIM.
# Old cases above remain untouched. Digests/sizes below are substituted only in these copied fixtures.
$reviewCases=@('review-learner','review-rdd','review-env-only','review-wrong-instance','review-bad-id','review-bad-commit','review-bad-sha','review-wrong-module','review-wrong-size','review-dirty-source','review-missing-exit','review-running','review-unknown','review-wrong-root','review-jarpath','review-full','review-isolated')
foreach($case in $reviewCases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module=if($case -eq 'review-rdd'){'plugins:rdd'}else{'plugins:learner'}
 $id=if($module -eq 'plugins:rdd'){'mutation-build-2729529bc6e749dab1bb34cf2ebe96b3'}else{'mutation-build-1f1a8a7c967947669769dd2c7b6e8eb5'}
 $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact 'review-food-fixture-only';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash;$length=(Get-Item $artifact).Length
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace('\','/')).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace('\','/'))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace('\','/'))
 foreach($hash in @('F8222C4D4DA19EEE07E364241CCF1DECDA982740A1D0E83D00120DC4C4F8D9A2','F4A530DB5C33B5C5162AD50159A8F985101BA464D2A7BB2D43B27F16D5F3B605')){$deploy=$deploy.Replace($hash,$sha);$policy=$policy.Replace($hash,$sha)}
 $policy=$policy.Replace(',611020)',(','+$length+')')).Replace(',1171566)',(','+$length+')'))
 if($case -eq 'review-wrong-root'){$policy=$policy.Replace($root.Replace('\','/'),(Join-Path $d 'other-live').Replace('\','/'))}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit='25b6f23026e7bd6e6da13465b111d626c3995122'
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=$length}
 if($case -eq 'review-wrong-module'){$r.module='core:neoforge'}
 if($case -eq 'review-wrong-size'){$r.bytes=$length+1}
 if($case -eq 'review-dirty-source'){$r.sourceDirtyCountAfter=1}
 if($case -eq 'review-missing-exit'){$r.Remove('gradleExit')}
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'review-old-module';$oldHash=(Get-FileHash $old).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'review-old-api';$apiHash=(Get-FileHash $api).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'review-unchanged';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'review-running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'review-unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-review-food-25b6 -Instance gpt'
 if($case -eq 'review-env-only'){$argsText='-Mode original-review-food-25b6'}
 if($case -eq 'review-wrong-instance'){$argsText='-Mode original-review-food-25b6 -Instance test'}
 if($case -eq 'review-jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -eq 'review-full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'review-isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($case -eq 'review-bad-id'){$id='mutation-build-not-reviewed'}
 if($case -eq 'review-bad-commit'){$commit='0'*40}
 $wanted=if($case -eq 'review-bad-sha'){'0'*64}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -in @('review-learner','review-rdd')
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'review branch invoked generic config/launch'}
 if((Get-FileHash $other).Hash -ne $otherHash -or (Get-FileHash $api).Hash -ne $apiHash){throw 'review branch touched unrelated/API jar'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if((Get-FileHash $old).Hash -ne $sha -or $receipts.Count -ne 1){throw 'review output mismatch'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.success -ne $true -or $receipt.sourceCommit -cne $commit){throw 'review receipt invalid'}
  foreach($backup in $receipt.backups){if(-not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $backup.sha256){throw 'review backup mismatch'}}
 }else{
  if((Get-FileHash $old).Hash -ne $oldHash){throw 'refused review case wrote live mod'}
  foreach($receipt in $receipts){if((Get-Content $receipt.FullName -Raw | ConvertFrom-Json).success){throw 'refused review case signed success'}}
 }
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='copied exact 25b6 two-artifact branch with fake CIM, no real deployment'}
}
# 2026-11-14: one consumer-verified 1a347 learner artifact; old 78 controls above are unchanged.
# V09 lost review clocks. Exercise the real copied deploy entry, never a live path or real CIM.
$resultCases=@('result-learner','result-env-only','result-wrong-instance','result-bad-id','result-bad-commit','result-bad-sha','result-wrong-module','result-wrong-size','result-dirty-source','result-missing-exit','result-running','result-unknown','result-wrong-root','result-jarpath','result-jarname','result-full','result-isolated','result-copy-failure')
foreach($case in $resultCases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module='plugins:learner';$id='mutation-build-0cc0780d079e473d9e35b87ff3ac1a65'
 $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact 'result-review-fixture-only';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash;$length=(Get-Item $artifact).Length
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $fixedHash='653913D3E0E009045940DC8FF691892F1DC474766A9651DA6FE09FEF4836528C'
 $deploy=$deploy.Replace($fixedHash,$sha);$policy=$policy.Replace($fixedHash,$sha).Replace(',623053)',(','+$length+')'))
 if($case -eq 'result-wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
 if($case -eq 'result-copy-failure'){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture result copy failure'")}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit='1a347ba6b0ab16d2100d926e4ae58316912131ab'
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=$length}
 if($case -eq 'result-wrong-module'){$r.module='core:neoforge'}
 if($case -eq 'result-wrong-size'){$r.bytes=$length+1}
 if($case -eq 'result-dirty-source'){$r.sourceDirtyCountAfter=1}
 if($case -eq 'result-missing-exit'){$r.Remove('gradleExit')}
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'result-old-learner';$oldHash=(Get-FileHash $old).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'result-old-api';$apiHash=(Get-FileHash $api).Hash
 $core=Join-Path (Join-Path $root 'mods') 'numen-neoforge-1.21.1-0.1.3-dev.jar';Put $core 'result-old-core';$coreHash=(Get-FileHash $core).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'result-unchanged';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'result-running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'result-unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-result-review-1a347 -Instance gpt'
 if($case -eq 'result-env-only'){$argsText='-Mode original-result-review-1a347'}
 if($case -eq 'result-wrong-instance'){$argsText='-Mode original-result-review-1a347 -Instance test'}
 if($case -eq 'result-jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -eq 'result-jarname'){$argsText+=' -JarName "'+$names[$module]+'"'}
 if($case -eq 'result-full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'result-isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($case -eq 'result-bad-id'){$id='mutation-build-not-reviewed'}
 if($case -eq 'result-bad-commit'){$commit='0'*40}
 $wanted=if($case -eq 'result-bad-sha'){'0'*64}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -eq 'result-learner'
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'result branch invoked generic config/launch'}
 if((Get-FileHash $other).Hash -ne $otherHash -or (Get-FileHash $api).Hash -ne $apiHash -or (Get-FileHash $core).Hash -ne $coreHash){throw 'result branch touched unrelated/API/core jar'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok){
  if((Get-FileHash $old).Hash -ne $sha -or $receipts.Count -ne 1){throw 'result output mismatch'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.success -ne $true -or $receipt.sourceCommit -cne $commit -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne 1){throw 'result receipt invalid'}
  foreach($backup in $receipt.backups){if(-not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $oldHash -or $backup.sha256 -ne $oldHash){throw 'result backup mismatch'}}
 }else{
  if((Get-FileHash $old).Hash -ne $oldHash){throw 'refused result case wrote live mod'}
  foreach($receipt in $receipts){if((Get-Content $receipt.FullName -Raw | ConvertFrom-Json).success){throw 'refused result case signed success'}}
 }
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='copied exact 1a347 learner entry with fixture hashes/CIM, no real deployment'}
}

# 2026-11-14: a199 A1/core food fix, exactly two audited builds; old 96 cases stay intact.
# Copy the real entry/policy into temporary roots. Fixture hashes/CIM are never production proof.
$a199Cases=@('a199-core','a199-rdd','a199-env-only','a199-wrong-instance','a199-bad-id','a199-bad-commit','a199-bad-sha','a199-swapped-sha','a199-wrong-module','a199-wrong-size','a199-fixed-size','a199-dirty-source','a199-missing-exit','a199-nonzero-exit','a199-running','a199-unknown','a199-wrong-root','a199-jarpath','a199-jarname','a199-full','a199-isolated','a199-escape','a199-corrupt-artifact','a199-core-copy-failure','a199-rdd-copy-failure')
foreach($case in $a199Cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module=if($case -in @('a199-rdd','a199-rdd-copy-failure')){'plugins:rdd'}else{'core:neoforge'}
 $id=if($module -ceq 'core:neoforge'){'mutation-build-ffae833c8c124edd9d9494426c9c577c'}else{'mutation-build-a33e86a4a25c4a8782a6ed01c2a44fb3'}
 $fixedHash=if($module -ceq 'core:neoforge'){'C88FCC3E215CA7CDEC751D14F0B629CE2C059DF962913B9440E46C063B5160FC'}else{'1F16C8F52FF6C68F90A22D1630F2AF5411A819DA7E85970C0225892B2D9015FC'}
 $otherTupleHash=if($module -ceq 'core:neoforge'){'1F16C8F52FF6C68F90A22D1630F2AF5411A819DA7E85970C0225892B2D9015FC'}else{'C88FCC3E215CA7CDEC751D14F0B629CE2C059DF962913B9440E46C063B5160FC'}
 $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact ('a199-fixture-only-'+$module)
 $sha=(Get-FileHash $artifact -Algorithm SHA256).Hash;$length=(Get-Item $artifact).Length
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $deploy=$deploy.Replace($fixedHash,$sha);$policy=$policy.Replace($fixedHash,$sha)
 $fixedSize=if($case -eq 'a199-fixed-size'){$length+1}else{$length}
 $policy=$policy.Replace(',3080159)',(','+$fixedSize+')')).Replace(',1172244)',(','+$fixedSize+')'))
 if($case -eq 'a199-wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
 $copyFail=$case -in @('a199-core-copy-failure','a199-rdd-copy-failure')
 if($copyFail){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture a199 copy failure'")}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit='a199d778c3d8be921c5f21f5aae085b80d975106'
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=$length}
 if($case -eq 'a199-wrong-module'){$r.module='plugins:learner'}
 if($case -eq 'a199-wrong-size'){$r.bytes=$length+1}
 if($case -eq 'a199-dirty-source'){$r.sourceDirtyCountAfter=1}
 if($case -eq 'a199-missing-exit'){$r.Remove('gradleExit')}
 if($case -eq 'a199-nonzero-exit'){$r.gradleExit=1}
 if($case -eq 'a199-escape'){$r.artifact=Join-Path $root $names[$module]}
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 if($case -eq 'a199-corrupt-artifact'){Put $artifact 'corrupted-after-receipt'}
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'a199-old-target';$oldHash=(Get-FileHash $old).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'a199-old-api';$apiHash=(Get-FileHash $api).Hash
 $otherModule=if($module -ceq 'core:neoforge'){'plugins:rdd'}else{'core:neoforge'}
 $otherMod=Join-Path (Join-Path $root 'mods') $names[$otherModule];Put $otherMod 'a199-other-module';$otherModHash=(Get-FileHash $otherMod).Hash
 $learner=Join-Path (Join-Path $root 'mods') $names['plugins:learner'];Put $learner 'a199-old-learner';$learnerHash=(Get-FileHash $learner).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'a199-unrelated';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'a199-running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'a199-unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-a1-food-a199 -Instance gpt'
 if($case -eq 'a199-env-only'){$argsText='-Mode original-a1-food-a199'}
 if($case -eq 'a199-wrong-instance'){$argsText='-Mode original-a1-food-a199 -Instance test'}
 if($case -eq 'a199-jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -eq 'a199-jarname'){$argsText+=' -JarName "'+$names[$module]+'"'}
 if($case -eq 'a199-full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'a199-isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($case -eq 'a199-bad-id'){$id='mutation-build-not-a199'}
 if($case -eq 'a199-bad-commit'){$commit='0'*40}
 $wanted=if($case -eq 'a199-bad-sha'){'0'*64}elseif($case -eq 'a199-swapped-sha'){$otherTupleHash}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -in @('a199-core','a199-rdd')
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'a199 entry invoked generic config/launch'}
 if((Get-FileHash $other).Hash -ne $otherHash -or (Get-FileHash $otherMod).Hash -ne $otherModHash -or (Get-FileHash $learner).Hash -ne $learnerHash){throw 'a199 entry touched another package'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 $expectedBackups=if($module -ceq 'core:neoforge'){2}else{1}
 if($ok -or $copyFail){
  if($receipts.Count -ne 1){throw 'a199 missing or duplicate copy receipt'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.sourceCommit -cne $commit -or $receipt.module -cne $module -or $receipt.sha256 -ine $sha -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne $expectedBackups){throw 'a199 copy receipt mismatch'}
  foreach($backup in $receipt.backups){
   $expectedOld=if($backup.original -eq $api){$apiHash}elseif($backup.original -eq $old){$oldHash}else{throw 'unexpected backup path'}
   if(-not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $expectedOld -or $backup.sha256 -ne $expectedOld){throw 'a199 original backup not recoverable'}
  }
  if($module -ceq 'core:neoforge'){
   # Existing core order removes the standalone API before copy; failure does not restore it automatically.
   if(Test-Path $api){throw 'a199 core left standalone API after copy stage'}
  }elseif((Get-FileHash $api).Hash -ne $apiHash){throw 'a199 RDD changed standalone API'}
  if($ok){
   if((Get-FileHash $old).Hash -ne $sha -or $receipt.success -ne $true -or $receipt.status -cne 'DEPLOYED_TEST'){throw 'a199 successful copy mismatch'}
  }else{
   if((Get-FileHash $old).Hash -ne $oldHash -or $receipt.success -ne $false -or $receipt.status -cne 'failed' -or ($output -join ' ') -notmatch 'fixture\s+a199\s+copy\s+failure'){throw 'a199 copy failure misreported'}
  }
 }else{
  if((Get-FileHash $old).Hash -ne $oldHash -or (Get-FileHash $api).Hash -ne $apiHash -or $receipts.Count -ne 0){throw 'a199 refusal changed target/API or entered copy stage'}
 }
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='copied exact a199 core/RDD entry, fixture files/CIM only; no production deployment'}
}

# 2026-11-14: one compat learner successor (28ba) fixed tuple; old controls unchanged.
$successorCases=@('successor-learner','successor-env-only','successor-wrong-instance','successor-bad-id','successor-bad-commit','successor-bad-sha','successor-wrong-module','successor-wrong-size','successor-fixed-size','successor-dirty-source','successor-missing-exit','successor-nonzero-exit','successor-running','successor-unknown','successor-wrong-root','successor-jarpath','successor-jarname','successor-full','successor-isolated','successor-escape','successor-corrupt-artifact','successor-copy-failure')
foreach($case in $successorCases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module='plugins:learner';$id='mutation-build-412cb9c4933347d99785c5364e5008d9'
 $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact 'successor-28ba-fixture-only';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash;$length=(Get-Item $artifact).Length
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $fixedHash='F3FE5621F331B33D982B1CC9B6DF26304049CC04B2AC48AF3178C6BBFDA109CB'
 $fixedSize=if($case -eq 'successor-fixed-size'){$length+1}else{$length}
 $deploy=$deploy.Replace($fixedHash,$sha);$policy=$policy.Replace($fixedHash,$sha).Replace(',624872)',(','+$fixedSize+')'))
 if($case -eq 'successor-wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
 if($case -eq 'successor-copy-failure'){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture successor copy failure'")}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit='28ba205413b031f91a799fbe35f704831bd8982d'
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sha256=$sha;bytes=$length;sourceProof='pre-post-checks-consistent'}
 if($case -eq 'successor-wrong-module'){$r.module='core:neoforge'}
 if($case -eq 'successor-wrong-size'){$r.bytes=$length+1}
 if($case -eq 'successor-dirty-source'){$r.sourceDirtyCountAfter=1}
 if($case -eq 'successor-missing-exit'){$r.Remove('gradleExit')}
 if($case -eq 'successor-nonzero-exit'){$r.gradleExit=1}
 if($case -eq 'successor-escape'){$r.artifact=Join-Path $root $names[$module]}
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 if($case -eq 'successor-corrupt-artifact'){Put $artifact 'corrupted-after-receipt'}
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'successor-old-learner';$oldHash=(Get-FileHash $old).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'successor-old-api';$apiHash=(Get-FileHash $api).Hash
 $core=Join-Path (Join-Path $root 'mods') 'numen-neoforge-1.21.1-0.1.3-dev.jar';Put $core 'successor-old-core';$coreHash=(Get-FileHash $core).Hash
 $rdd=Join-Path (Join-Path $root 'mods') 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar';Put $rdd 'successor-old-rdd';$rddHash=(Get-FileHash $rdd).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'successor-unrelated';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'successor-running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'successor-unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-learner-successor-28ba -Instance gpt'
 if($case -eq 'successor-env-only'){$argsText='-Mode original-learner-successor-28ba'}
 if($case -eq 'successor-wrong-instance'){$argsText='-Mode original-learner-successor-28ba -Instance test'}
 if($case -eq 'successor-jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -eq 'successor-jarname'){$argsText+=' -JarName "'+$names[$module]+'"'}
 if($case -eq 'successor-full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'successor-isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($case -eq 'successor-bad-id'){$id='mutation-build-not-successor'}
 if($case -eq 'successor-bad-commit'){$commit='0'*40}
 $wanted=if($case -eq 'successor-bad-sha'){'0'*64}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -eq 'successor-learner'
 $copyFail=$case -eq 'successor-copy-failure'
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'successor entry invoked generic config/launch'}
 if((Get-FileHash $api).Hash -ne $apiHash -or (Get-FileHash $core).Hash -ne $coreHash -or (Get-FileHash $rdd).Hash -ne $rddHash -or (Get-FileHash $other).Hash -ne $otherHash){throw 'successor entry touched API/core/RDD/unrelated'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok -or $copyFail){
  if($receipts.Count -ne 1){throw 'successor missing or duplicate copy receipt'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.sourceCommit -cne $commit -or $receipt.module -cne $module -or $receipt.sha256 -ine $sha -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne 1){throw 'successor copy receipt mismatch'}
  $backup=@($receipt.backups)[0]
  if(-not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $oldHash -or $backup.sha256 -ne $oldHash){throw 'successor backup not recoverable'}
  if($ok){
   if((Get-FileHash $old).Hash -ne $sha -or $receipt.success -ne $true -or $receipt.status -cne 'DEPLOYED_TEST'){throw 'successor successful copy mismatch'}
  }else{
   if((Get-FileHash $old).Hash -ne $oldHash -or $receipt.success -ne $false -or $receipt.status -cne 'failed' -or ($output -join ' ') -notmatch 'fixture\s+successor\s+copy\s+failure'){throw 'successor copy failure misreported'}
  }
 }else{
  if((Get-FileHash $old).Hash -ne $oldHash -or $receipts.Count -ne 0){throw 'successor refusal changed target or entered copy stage'}
 }
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='copied exact 28ba learner successor entry, fixture files/CIM only; no production deployment'}
}

# 2026-11-14: one nudge RDD (86785) fixed tuple; the preceding 143 controls stay verbatim.
$nudgeCases=@('nudge-rdd','nudge-env-only','nudge-wrong-instance','nudge-bad-id','nudge-bad-commit','nudge-bad-sha','nudge-wrong-module','nudge-wrong-size','nudge-fixed-size','nudge-dirty-source','nudge-missing-exit','nudge-nonzero-exit','nudge-running','nudge-unknown','nudge-wrong-root','nudge-jarpath','nudge-jarname','nudge-full','nudge-isolated','nudge-escape','nudge-corrupt-artifact','nudge-copy-failure')
foreach($case in $nudgeCases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module='plugins:rdd';$id='mutation-build-9ac2a358204d457eb7a02ace7eabd9cb'
 $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
 $artifact=Join-Path $jd $names[$module];Put $artifact 'nudge-86785-fixture-only';$sha=(Get-FileHash $artifact -Algorithm SHA256).Hash;$length=(Get-Item $artifact).Length
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $fixedHash='A2F081963BDB715D73D26D433A1C0977941DE30515EFA017AB8EB228DD392106'
 $fixedSize=if($case -eq 'nudge-fixed-size'){$length+1}else{$length}
 $deploy=$deploy.Replace($fixedHash,$sha);$policy=$policy.Replace($fixedHash,$sha).Replace(',1173314)',(','+$fixedSize+')'))
 if($case -eq 'nudge-wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
 if($case -eq 'nudge-copy-failure'){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture nudge copy failure'")}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $commit='86785a7a61cc0cbeff5e0d32262d6e7dd829c194'
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sha256=$sha;bytes=$length;sourceProof='pre-post-checks-consistent'}
 if($case -eq 'nudge-wrong-module'){$r.module='core:neoforge'}
 if($case -eq 'nudge-wrong-size'){$r.bytes=$length+1}
 if($case -eq 'nudge-dirty-source'){$r.sourceDirtyCountAfter=1}
 if($case -eq 'nudge-missing-exit'){$r.Remove('gradleExit')}
 if($case -eq 'nudge-nonzero-exit'){$r.gradleExit=1}
 if($case -eq 'nudge-escape'){$r.artifact=Join-Path $root $names[$module]}
 if($case -eq 'nudge-dirty-source'){
  # Independently reject a clean receipt with bad sourceProof before the dirty-count deployment control.
  $r.sourceDirtyCountAfter=0;$r.sourceProof='fixture-invalid-source-proof'
  Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
  $proofRefused=$false
  try{
   & { . (Join-Path $scripts 'deploy-test-policy.ps1');Get-RddTestDeploySource -MutationId $id -ExpectedCommit $commit -ExpectedSha256 $sha -Mutations $mut -Original } | Out-Null
  }catch{if($_.Exception.Message -cne 'invalid source proof'){throw};$proofRefused=$true}
  if(-not $proofRefused){throw 'nudge invalid sourceProof accepted'}
  $r.sourceDirtyCountAfter=1;$r.sourceProof='pre-post-checks-consistent'
 }
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 if($case -eq 'nudge-corrupt-artifact'){Put $artifact 'corrupted-after-receipt'}
 $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old 'nudge-old-rdd';$oldHash=(Get-FileHash $old).Hash
 $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api 'nudge-old-api';$apiHash=(Get-FileHash $api).Hash
 $core=Join-Path (Join-Path $root 'mods') 'numen-neoforge-1.21.1-0.1.3-dev.jar';Put $core 'nudge-old-core';$coreHash=(Get-FileHash $core).Hash
 $learner=Join-Path (Join-Path $root 'mods') 'numen-plugin-learner-1.21.1-0.1.3-dev.jar';Put $learner 'nudge-old-learner';$learnerHash=(Get-FileHash $learner).Hash
 $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other 'nudge-unrelated';$otherHash=(Get-FileHash $other).Hash
 $cim=if($case -eq 'nudge-running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'nudge-unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-rdd-nudge-86785 -Instance gpt'
 if($case -eq 'nudge-env-only'){$argsText='-Mode original-rdd-nudge-86785'}
 if($case -eq 'nudge-wrong-instance'){$argsText='-Mode original-rdd-nudge-86785 -Instance test'}
 if($case -eq 'nudge-jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -eq 'nudge-jarname'){$argsText+=' -JarName "'+$names[$module]+'"'}
 if($case -eq 'nudge-full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'nudge-isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($case -eq 'nudge-bad-id'){$id='mutation-build-not-nudge'}
 if($case -eq 'nudge-bad-commit'){$commit='0'*40}
 $wanted=if($case -eq 'nudge-bad-sha'){'0'*64}else{$sha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -eq 'nudge-rdd'
 $copyFail=$case -eq 'nudge-copy-failure'
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'nudge entry invoked generic config/launch'}
 if((Get-FileHash $api).Hash -ne $apiHash -or (Get-FileHash $core).Hash -ne $coreHash -or (Get-FileHash $learner).Hash -ne $learnerHash -or (Get-FileHash $other).Hash -ne $otherHash){throw 'nudge entry touched API/core/learner/unrelated'}
 $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
 if($ok -or $copyFail){
  if($receipts.Count -ne 1){throw 'nudge missing or duplicate copy receipt'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.sourceCommit -cne $commit -or $receipt.module -cne $module -or $receipt.sha256 -ine $sha -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne 1){throw 'nudge copy receipt mismatch'}
  $backup=@($receipt.backups)[0]
  if($backup.original -cne $old -or -not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $oldHash -or $backup.sha256 -ne $oldHash){throw 'nudge backup not recoverable'}
  if($ok){
   if((Get-FileHash $old).Hash -ne $sha -or $receipt.success -ne $true -or $receipt.status -cne 'DEPLOYED_TEST'){throw 'nudge successful copy mismatch'}
  }else{
   if((Get-FileHash $old).Hash -ne $oldHash -or $receipt.success -ne $false -or $receipt.status -cne 'failed' -or ($output -join ' ') -notmatch 'fixture\s+nudge\s+copy\s+failure'){throw 'nudge copy failure misreported'}
  }
 }else{
  if((Get-FileHash $old).Hash -ne $oldHash -or $receipts.Count -ne 0){throw 'nudge refusal changed target or entered copy stage'}
 }
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;sourceProofRefused=$(if($case -eq 'nudge-dirty-source'){$proofRefused}else{$null});scope='copied exact 86785 nudge RDD entry, fixture files/CIM only; no production deployment'}
}

# 2026-11-14: aa735 same-source plugins, three copies plus 20 shared/cross-pair refusals.
# Preserve the original 165 cases verbatim; only relocated scripts, fake jars and fake CIM run here.
$parallelTuples=@{
 'plugins:rdd'=@('mutation-build-2f09f207d2d146619c65dc236c0b08c1','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','2FB0E0636B106DB48140DF5EFF859CDDAAC3350A15815933DD8DA9E54ACE588F',1173437)
 'plugins:learner'=@('mutation-build-9d7b663c3b04480ca78d80461399b4b2','numen-plugin-learner-1.21.1-0.1.3-dev.jar','3570AF13D57BA5F4ABF77D6064C4B9EEC82A81605EF29849B4F1FF00795094E6',625493)
 'plugins:experience'=@('mutation-build-d4121062b6e54cd78ffb32a6a86e23e5','numen-plugin-experience-1.21.1-0.1.3-dev.jar','99E188C606F72C40675926FDC432B1BEB5EA647E1E1F160C3A6DA23600BF3CBC',206899)
}
$parallelCases=@('aa735-rdd','aa735-learner','aa735-experience','aa735-rdd-sha-learner','aa735-learner-id-experience','aa735-experience-sha-rdd','aa735-bad-commit','aa735-wrong-module','aa735-wrong-size','aa735-fixed-size','aa735-bad-proof','aa735-env-only','aa735-wrong-instance','aa735-running','aa735-unknown','aa735-copy-failure','aa735-escape','aa735-wrong-root','aa735-jarpath','aa735-jarname','aa735-full','aa735-isolated','aa735-assembly-crossed')
foreach($case in $parallelCases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module=if($case -in @('aa735-learner','aa735-learner-id-experience','aa735-wrong-size','aa735-fixed-size','aa735-bad-proof','aa735-unknown','aa735-jarname')){'plugins:learner'}elseif($case -in @('aa735-experience','aa735-experience-sha-rdd','aa735-wrong-module','aa735-env-only','aa735-copy-failure','aa735-isolated','aa735-assembly-crossed')){'plugins:experience'}else{'plugins:rdd'}
 $commit='aa73586a069361aea5d263618d0dfa8b1bc40df3'
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47)).Replace('D:/rdd/workspace/rdd-selfcompile/instances/test',(Join-Path $d 'isolated-unused').Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $fixtureHashes=@{}
 foreach($m in @('plugins:rdd','plugins:learner','plugins:experience')){
  $t=$parallelTuples[$m];$jd=Join-Path (Join-Path $mut $t[0]) 'jar';New-Item -ItemType Directory $jd | Out-Null
  $a=Join-Path $jd $t[1];Put $a ('aa735-fixture-only-'+$m);$h=(Get-FileHash $a).Hash;$length=(Get-Item $a).Length;$fixtureHashes[$m]=$h
  $deploy=$deploy.Replace($t[2],$h);$policy=$policy.Replace($t[2],$h)
  $fixedSize=if($case -eq 'aa735-fixed-size' -and $m -ceq $module){$length+1}else{$length}
  $policy=$policy.Replace((','+$t[3]+')'),(','+$fixedSize+')'))
  $r=@{artifact=$a;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$m;instance='test';mutationId=$t[0];sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sha256=$h;bytes=$length;sourceProof='pre-post-checks-consistent'}
  if($m -ceq $module){
   if($case -eq 'aa735-wrong-module'){$r.module='core:neoforge'}
   if($case -eq 'aa735-wrong-size'){$r.bytes=$length+1}
   if($case -eq 'aa735-bad-proof'){$r.sourceProof='fixture-invalid-source-proof'}
   if($case -eq 'aa735-escape'){$r.artifact=Join-Path $root $t[1]}
  }
  Put (Join-Path (Split-Path $jd -Parent) 'phase-build.json') ($r|ConvertTo-Json)
 }
 if(@($fixtureHashes.Values|Select-Object -Unique).Count -ne 3){throw 'aa735 cross-pair hashes are not distinct'}
 if($case -eq 'aa735-wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
 if($case -eq 'aa735-copy-failure'){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture aa735 copy failure'")}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $t=$parallelTuples[$module];$id=$t[0];$artifact=Join-Path (Join-Path (Join-Path $mut $id) 'jar') $t[1];$sha=$fixtureHashes[$module]
 $modNames=@('numen_api-neoforge-1.21.1-0.1.3-dev.jar','numen-neoforge-1.21.1-0.1.3-dev.jar')+@('plugins:rdd','plugins:learner','plugins:experience'|ForEach-Object {$parallelTuples[$_][1]})
 $before=@{}
 foreach($name in $modNames){$p=Join-Path (Join-Path $root 'mods') $name;Put $p ('aa735-old-'+$name);$before[$name]=(Get-FileHash $p).Hash}
 $old=Join-Path (Join-Path $root 'mods') $t[1];$oldHash=$before[$t[1]]
 $priorDir=Join-Path $root 'disabled/prior-attempt';New-Item -ItemType Directory $priorDir | Out-Null
 $prior=Join-Path $priorDir $t[1];Put $prior 'aa735-prior-backup-sentinel';$priorHash=(Get-FileHash $prior).Hash
 $cim=if($case -eq 'aa735-running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'aa735-unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText='-Mode original-parallel-aa735 -Instance gpt'
 if($case -eq 'aa735-env-only'){$argsText='-Mode original-parallel-aa735'}
 if($case -eq 'aa735-wrong-instance'){$argsText='-Mode original-parallel-aa735 -Instance test'}
 if($case -eq 'aa735-jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($case -eq 'aa735-jarname'){$argsText+=' -JarName "'+$t[1]+'"'}
 if($case -eq 'aa735-full'){$argsText='-Mode full -Instance gpt'}
 if($case -eq 'aa735-isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($case -eq 'aa735-bad-commit'){$commit='0'*40}
 $wanted=$sha
 if($case -eq 'aa735-rdd-sha-learner'){$wanted=$fixtureHashes['plugins:learner']}
 if($case -eq 'aa735-learner-id-experience'){$id=$parallelTuples['plugins:experience'][0]}
 if($case -eq 'aa735-experience-sha-rdd'){$wanted=$fixtureHashes['plugins:rdd']}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 if($case -eq 'aa735-assembly-crossed'){
  # Independently close the Original assembly gate against a valid source with crossed name/hash.
  $wrapper='function Get-CimInstance { return @() }; . "'+(Join-Path $scripts 'deploy-test-policy.ps1')+'"; . "'+(Join-Path $scripts 'mc-identity.ps1')+'"; try { $s=Get-RddTestDeploySource -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$sha+' -Mutations "'+$mut+'" -Original; $s.name="'+$parallelTuples['plugins:rdd'][1]+'"; $s.sha="'+$fixtureHashes['plugins:rdd']+'"; Invoke-RddTestAssembly -Source $s -Root "'+$root.Replace([char]92,[char]47)+'" -Live "'+$root.Replace([char]92,[char]47)+'" -Original; exit 0 } catch { Write-Output $_.Exception.Message; exit 2 }'
 }
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -in @('aa735-rdd','aa735-learner','aa735-experience');$copyFail=$case -eq 'aa735-copy-failure'
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'aa735 entry invoked generic config/launch'}
 if((Get-FileHash $prior).Hash -ne $priorHash){throw 'aa735 entry changed an older backup'}
 if(@(Get-ChildItem (Join-Path $root 'mods') -File).Count -ne 5){throw 'aa735 changed the mod file set'}
 foreach($name in $modNames){if($name -cne $t[1] -and (Get-FileHash (Join-Path (Join-Path $root 'mods') $name)).Hash -ne $before[$name]){throw ('aa735 entry touched peer jar '+$name)}}
 $receipts=@(Get-ChildItem $mut -Recurse -Filter 'deploy-test-*.json')
 if($ok -or $copyFail){
  if($receipts.Count -ne 1){throw 'aa735 missing or duplicate copy receipt'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.sourceCommit -cne $commit -or $receipt.module -cne $module -or $receipt.sha256 -ine $sha -or $receipt.artifact -cne $artifact -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne 1){throw 'aa735 copy receipt mismatch'}
  $backup=@($receipt.backups)[0]
  if($backup.original -cne $old -or -not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $oldHash -or $backup.sha256 -ne $oldHash){throw 'aa735 backup not recoverable'}
  if($ok){
   if((Get-FileHash $old).Hash -ne $sha -or $receipt.success -ne $true -or $receipt.status -cne 'DEPLOYED_TEST'){throw 'aa735 successful copy mismatch'}
  }else{
   if((Get-FileHash $old).Hash -ne $oldHash -or $receipt.success -ne $false -or $receipt.status -cne 'failed' -or ($output -join ' ') -notmatch 'fixture\s+aa735\s+copy\s+failure'){throw 'aa735 copy failure misreported'}
  }
 }elseif((Get-FileHash $old).Hash -ne $oldHash -or $receipts.Count -ne 0){throw 'aa735 refusal changed target or entered copy stage'}
 if($case -eq 'aa735-assembly-crossed' -and ($output -join ' ') -notmatch 'unapproved\s+original\s+deployment'){throw 'aa735 crossed assembly missed tuple guard'}
 $results+=@{case=$case;module=$module;exit=$exit;passed=$true;poison=0;oldBackupPreserved=$true;unchangedPeers=4;scope='copied exact aa735 plugin entry, fixture files/CIM only; no production deployment'}
}

# 2026-11-14: 8853 same-source plugins, three copies plus 20 shared/cross-pair refusals.
# Preserve the original 188 cases verbatim; only relocated scripts, fake jars and fake CIM run here.
$why8853Tuples=@{
 'plugins:rdd'=@('mutation-build-bcf9062caa914d12b1d75a250e8bd5ee','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','8136345A8FFBC1322BC289B7CBEFF37479E9FC9D2573963CC6DB09B3674A9DCE',1188631)
 'plugins:learner'=@('mutation-build-5a5fccbb162244d0906d26be8d7f329d','numen-plugin-learner-1.21.1-0.1.3-dev.jar','F42716BC0C6C3CD980C3080614F356B58F7C6D9C47860360E1081CA33A07459F',637503)
 'plugins:experience'=@('mutation-build-7cc1a6f15b61475587953bf380d8f7b1','numen-plugin-experience-1.21.1-0.1.3-dev.jar','6371B7BF3926EBE8AA27A8A2AD63196A8B8F41C72E36ADB9EBA620755E717C00',207504)
}
$why8853Cases=@('8853-rdd','8853-learner','8853-experience','8853-rdd-sha-learner','8853-learner-id-experience','8853-experience-sha-rdd','8853-bad-commit','8853-wrong-module','8853-wrong-size','8853-fixed-size','8853-bad-proof','8853-env-only','8853-wrong-instance','8853-running','8853-unknown','8853-copy-failure','8853-escape','8853-wrong-root','8853-jarpath','8853-jarname','8853-full','8853-isolated','8853-assembly-crossed')
$v25Tuples=@{
 'plugins:rdd'=@('mutation-build-4ee45e827c1e439eb95638a175a68177','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','8B85F50E48BFCB922D15D0E46CD9F7E7EF75C125F826C396D3CE9E8DDBEE6B28',1191094)
 'plugins:experience'=@('mutation-build-f59304e827ee473bb10022854c2aaf2f','numen-plugin-experience-1.21.1-0.1.3-dev.jar','BD66DFDB53A0702B6884093A36AB0D0D10A005EFF6741C7A7915ED3EB949D7A5',207622)
}
$v25Cases=@('v25-rdd','v25-experience','v25-rdd-sha-experience','v25-experience-id-rdd','v25-bad-commit','v25-bad-source','v25-wrong-module','v25-wrong-size','v25-fixed-size','v25-bad-proof','v25-env-only','v25-wrong-instance','v25-running','v25-unknown','v25-copy-failure','v25-escape','v25-wrong-root','v25-jarpath','v25-jarname','v25-full','v25-isolated','v25-assembly-crossed','v25-assembly-name')
# Reuse the original copied-entry/receipt/backup runner; preserve every 8853/v25 case.
$b2c1Tuples=@{
 'plugins:rdd'=@('mutation-build-c3a130228cf54d41a05fa168e0446338','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','18C226A3450D36DE2CD4B126F4D639FA4A66E154AC9979DC02E91EEFD28F00DA',1193497)
}
$b2c1Cases=@('b2c1-rdd','b2c1-bad-commit','b2c1-wrong-size','b2c1-fixed-size','b2c1-bad-proof','b2c1-escape','b2c1-bad-source','b2c1-copy-failure','b2c1-wrong-root','b2c1-running','b2c1-unknown','b2c1-env-only','b2c1-wrong-instance','b2c1-jarpath','b2c1-jarname','b2c1-full','b2c1-isolated')
$dailyTuples=@{'plugins:rdd'=@('mutation-build-faa7ff97c0c44bb6b9d36aef17281ae9','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','C9798F2F4068266AF4574400ABD754B6CEF814D08B23E5A4FA3DC569E9A4C1E1',1195737)}
$dailyCases=@('daily-rdd','daily-bad-id','daily-bad-commit','daily-bad-sha','daily-wrong-size','daily-fixed-size','daily-bad-proof','daily-escape','daily-bad-source','daily-wrong-module','daily-copy-failure','daily-wrong-root','daily-running','daily-unknown','daily-env-only','daily-wrong-instance','daily-jarpath','daily-jarname','daily-full','daily-isolated')
foreach($release in @(
 @{tag='8853';commit='8853c569e6e51d0bc23a39b4b5dcdea7f685f69a';mode='original-why-8853';tuples=$why8853Tuples;cases=$why8853Cases},
 @{tag='v25';commit='144ac9570932de65b80ae61d0ffffcb317934922';mode='original-v25-144ac';tuples=$v25Tuples;cases=$v25Cases},
 @{tag='b2c1';commit='9f94bbbad357687538dc4c50498ae05a729d7f86';mode='original-b2-c1-9f94';tuples=$b2c1Tuples;cases=$b2c1Cases},
 @{tag='daily';commit='faede91ce4bf0ff5c9253df798988a4f4f8fddf9';mode='original-daily-faede';tuples=$dailyTuples;cases=$dailyCases}
)){
 $tuples=$release.tuples
 foreach($case in $release.cases){
 $kind=$case.Substring($release.tag.Length+1)
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
 $module=if($tuples.Count -eq 1){@($tuples.Keys)[0]}elseif($tuples.ContainsKey('plugins:learner') -and $kind -in @('learner','learner-id-experience','wrong-size','fixed-size','bad-proof','unknown','jarname')){'plugins:learner'}elseif($tuples.ContainsKey('plugins:experience') -and $kind -in @('experience','experience-id-rdd','experience-sha-rdd','wrong-module','env-only','copy-failure','isolated','assembly-crossed','assembly-name')){'plugins:experience'}else{'plugins:rdd'}
 $commit=$release.commit
 $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
 $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
 $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47)).Replace('D:/rdd/workspace/rdd-selfcompile/instances/test',(Join-Path $d 'isolated-unused').Replace([char]92,[char]47))
 $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
 $fixtureHashes=@{}
 foreach($m in $tuples.Keys){
  $t=$tuples[$m];$jd=Join-Path (Join-Path $mut $t[0]) 'jar';New-Item -ItemType Directory $jd | Out-Null
  $a=Join-Path $jd $t[1];Put $a ($release.tag+'-fixture-only-'+$m);$h=(Get-FileHash $a).Hash;$length=(Get-Item $a).Length;$fixtureHashes[$m]=$h
  $deploy=$deploy.Replace($t[2],$h);$policy=$policy.Replace($t[2],$h)
  $fixedSize=if($kind -eq 'fixed-size' -and $m -ceq $module){$length+1}else{$length}
  $policy=$policy.Replace((','+$t[3]+')'),(','+$fixedSize+')'))
  $r=@{artifact=$a;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$m;instance='test';mutationId=$t[0];sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sha256=$h;bytes=$length;sourceProof='pre-post-checks-consistent'}
  if($m -ceq $module){
   if($kind -eq 'wrong-module'){$r.module='core:neoforge'}
   if($kind -eq 'wrong-size'){$r.bytes=$length+1}
   if($kind -eq 'bad-proof'){$r.sourceProof='fixture-invalid-source-proof'}
   if($kind -eq 'escape'){$r.artifact=Join-Path $root $t[1]}
   if($kind -eq 'bad-source'){$r.sourceHeadAfter='0'*40}
  }
  Put (Join-Path (Split-Path $jd -Parent) 'phase-build.json') ($r|ConvertTo-Json)
 }
 if(@($fixtureHashes.Values|Select-Object -Unique).Count -ne $tuples.Count){throw 'release cross-pair hashes are not distinct'}
 if($kind -eq 'wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
 if($kind -eq 'copy-failure'){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture $($release.tag) copy failure'")}
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
 $t=$tuples[$module];$id=$t[0];$artifact=Join-Path (Join-Path (Join-Path $mut $id) 'jar') $t[1];$sha=$fixtureHashes[$module]
 $modNames=@((@('numen_api-neoforge-1.21.1-0.1.3-dev.jar','numen-neoforge-1.21.1-0.1.3-dev.jar','numen-plugin-learner-1.21.1-0.1.3-dev.jar')+@($tuples.Keys|ForEach-Object {$tuples[$_][1]}))|Select-Object -Unique)
 $before=@{}
 foreach($name in $modNames){$p=Join-Path (Join-Path $root 'mods') $name;Put $p ('8853-old-'+$name);$before[$name]=(Get-FileHash $p).Hash}
 $old=Join-Path (Join-Path $root 'mods') $t[1];$oldHash=$before[$t[1]]
 $priorDir=Join-Path $root 'disabled/prior-attempt';New-Item -ItemType Directory $priorDir | Out-Null
 $prior=Join-Path $priorDir $t[1];Put $prior '8853-prior-backup-sentinel';$priorHash=(Get-FileHash $prior).Hash
 $cim=if($kind -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($kind -eq 'unknown'){'throw "CIM unavailable"'}else{'return @()'}
 $argsText=('-Mode '+$release.mode+' -Instance gpt')
 if($kind -eq 'env-only'){$argsText=('-Mode '+$release.mode)}
 if($kind -eq 'wrong-instance'){$argsText=('-Mode '+$release.mode+' -Instance test')}
 if($kind -eq 'jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
 if($kind -eq 'jarname'){$argsText+=' -JarName "'+$t[1]+'"'}
 if($kind -eq 'full'){$argsText='-Mode full -Instance gpt'}
 if($kind -eq 'isolated'){$argsText='-Mode isolated-test -Instance test'}
 if($kind -eq 'bad-commit'){$commit='0'*40}
 if($kind -eq 'bad-id'){$id='mutation-build-not-'+$release.tag}
 $wanted=$sha
 if($kind -eq 'bad-sha'){$wanted='0'*64}
 if($kind -eq 'rdd-sha-learner'){$wanted=$fixtureHashes['plugins:learner']}
 if($kind -eq 'learner-id-experience'){$id=$tuples['plugins:experience'][0]}
 if($kind -eq 'experience-sha-rdd'){$wanted=$fixtureHashes['plugins:rdd']}
 if($kind -eq 'rdd-sha-experience'){$wanted=$fixtureHashes['plugins:experience']}
 if($kind -eq 'experience-id-rdd'){$id=$tuples['plugins:rdd'][0]}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
 if($kind -in @('assembly-crossed','assembly-name')){
  # Independently close the Original assembly gate against a valid source with crossed name/hash.
  $wrapper='function Get-CimInstance { return @() }; . "'+(Join-Path $scripts 'deploy-test-policy.ps1')+'"; . "'+(Join-Path $scripts 'mc-identity.ps1')+'"; try { $s=Get-RddTestDeploySource -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$sha+' -Mutations "'+$mut+'" -Original; $s.name="'+$tuples['plugins:rdd'][1]+'"; '+$(if($kind -eq 'assembly-crossed'){'$s.sha="'+$fixtureHashes['plugins:rdd']+'"; '})+'Invoke-RddTestAssembly -Source $s -Root "'+$root.Replace([char]92,[char]47)+'" -Live "'+$root.Replace([char]92,[char]47)+'" -Original; exit 0 } catch { Write-Output $_.Exception.Message; exit 2 }'
 }
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$kind -in @('rdd','learner','experience');$copyFail=$kind -eq 'copy-failure'
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'release entry invoked generic config/launch'}
 if((Get-FileHash $prior).Hash -ne $priorHash){throw 'release entry changed an older backup'}
 if(@(Get-ChildItem (Join-Path $root 'mods') -File).Count -ne $modNames.Count){throw 'release changed the mod file set'}
 foreach($name in $modNames){if($name -cne $t[1] -and (Get-FileHash (Join-Path (Join-Path $root 'mods') $name)).Hash -ne $before[$name]){throw ('release entry touched peer jar '+$name)}}
 $receipts=@(Get-ChildItem $mut -Recurse -Filter 'deploy-test-*.json')
 if($ok -or $copyFail){
  if($receipts.Count -ne 1){throw 'release missing or duplicate copy receipt'}
  $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
  if($receipt.sourceCommit -cne $commit -or $receipt.module -cne $module -or $receipt.sha256 -ine $sha -or $receipt.artifact -cne $artifact -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne 1){throw 'release copy receipt mismatch'}
  $backup=@($receipt.backups)[0]
  if($backup.original -cne $old -or -not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $oldHash -or $backup.sha256 -ne $oldHash){throw 'release backup not recoverable'}
  if($ok){
   if((Get-FileHash $old).Hash -ne $sha -or $receipt.success -ne $true -or $receipt.status -cne 'DEPLOYED_TEST'){throw 'release successful copy mismatch'}
  }else{
   if((Get-FileHash $old).Hash -ne $oldHash -or $receipt.success -ne $false -or $receipt.status -cne 'failed' -or ($output -join ' ') -notmatch ('fixture\s+'+$release.tag+'\s+copy\s+failure')){throw 'release copy failure misreported'}
  }
 }elseif((Get-FileHash $old).Hash -ne $oldHash -or $receipts.Count -ne 0){throw 'release refusal changed target or entered copy stage'}
 if($kind -in @('assembly-crossed','assembly-name') -and ($output -join ' ') -notmatch 'unapproved\s+original\s+deployment'){throw 'release crossed assembly missed tuple guard'}
 $results+=@{case=$case;module=$module;exit=$exit;passed=$true;poison=0;oldBackupPreserved=$true;unchangedPeers=4;scope=('copied exact '+$release.tag+' plugin entry, fixture files/CIM only; no production deployment')}
}

}

# 2026-11-15: V26 and V27 core releases share one copied-entry/receipt/backup runner; cases stay explicit.
 # 2026-11-15: own-learner single-tuple cases (prefix added when the real tuple row lands).
 $learnerOwnCases=@('learner','bad-id','bad-commit','bad-sha','bad-source','bad-proof','wrong-size','fixed-size','wrong-module','escape','copy-failure','wrong-root','running','unknown','env-only','wrong-instance','jarpath','jarname','full','isolated')

$v26Cases=@('v26-core','v26-rdd','v26-env-only','v26-wrong-instance','v26-bad-id','v26-bad-commit','v26-bad-sha','v26-swapped-sha','v26-wrong-module','v26-wrong-size','v26-fixed-size','v26-dirty-source','v26-missing-exit','v26-nonzero-exit','v26-running','v26-unknown','v26-wrong-root','v26-jarpath','v26-jarname','v26-full','v26-isolated','v26-escape','v26-corrupt-artifact','v26-core-copy-failure','v26-rdd-copy-failure')
$convoCases=@('convo-core','convo-bad-id','convo-bad-sha','convo-bad-source','convo-wrong-module','convo-wrong-size','convo-bad-proof','convo-escape','convo-copy-failure','convo-wrong-root','convo-running','convo-unknown','convo-env-only','convo-wrong-instance','convo-jarpath','convo-jarname','convo-full','convo-isolated')
$kbqCases=@('kbq-core','kbq-bad-id','kbq-bad-sha','kbq-bad-source','kbq-wrong-module','kbq-wrong-size','kbq-bad-proof','kbq-escape','kbq-copy-failure','kbq-wrong-root','kbq-running','kbq-unknown','kbq-env-only','kbq-wrong-instance','kbq-jarpath','kbq-jarname','kbq-full','kbq-isolated')
$coreReleases=@(
 @{tag='v26';commit='5c046644683b26b385ef06e57260f3aa16edfb1b';mode='original-v26-5c046';coreId='mutation-build-f5e19b3475a44df281915f229f2c1366';coreHash='2FC60365B898D3ACC903F461A2791864F48188670F21B02E05DD5E2AEFCE2989';coreBytes=3080162;rddId='mutation-build-fcfb896670ac47fc8c07725fae837c77';rddHash='BECF06531DB5E3911D91834B2785E3DB73AF4308331D6B3F0D9FB19BE306D01B';rddBytes=1192911;policyBytes=@(1192911,3080162);cases=$v26Cases},
 @{tag='convo';commit='1f2e86286113430b58425446a132b986d482cf10';mode='original-convo-1f2';coreId='mutation-build-c7b23cc99dfc4b8ea2f8a7da92606a2b';coreHash='9959267A3CC8D8B982ACEF99EAEB95030B75D5C6E83D4E3F85B5E74C236DCAC1';coreBytes=3081940;policyBytes=@(3081940);cases=$convoCases}
 @{tag='kbq';commit='83ddd36f00aecd64b220155bf53658dbac776df0';mode='original-kb-quota-83ddd';coreId='mutation-build-e5184f70bd7b41fdabdc3f85cbf17306';coreHash='FB48F4779F68827A3CCD8EDBAE002A6D2F769EBED005C6298E16C1556CC00A4D';coreBytes=3083591;policyBytes=@(3083591);cases=$kbqCases}
)
foreach($coreRelease in $coreReleases){
 $tag=$coreRelease.tag
 foreach($case in $coreRelease.cases){
  $kind=$case.Substring($tag.Length+1)
  $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
  New-Item -ItemType Directory $scripts,$root,$mut,(Join-Path $root 'mods') | Out-Null
  $module=if($kind -eq 'rdd' -or $kind -eq 'rdd-copy-failure'){'plugins:rdd'}else{'core:neoforge'}
  $id=if($module -ceq 'core:neoforge'){$coreRelease.coreId}else{$coreRelease.rddId}
  $fixedHash=if($module -ceq 'core:neoforge'){$coreRelease.coreHash}else{$coreRelease.rddHash}
  $otherTupleHash=if($module -ceq 'core:neoforge'){$coreRelease.rddHash}else{$coreRelease.coreHash}
  $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $jd | Out-Null
  $artifact=Join-Path $jd $names[$module];Put $artifact ($tag+'-fixture-only-'+$module)
  $sha=(Get-FileHash $artifact -Algorithm SHA256).Hash;$length=(Get-Item $artifact).Length
  $deploy=Get-Content (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
  $policy=Get-Content (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
  $deploy=$deploy.Replace('D:/rdd/workspace/rdd-selfcompile/mutations',$mut.Replace([char]92,[char]47)).Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
  $policy=$policy.Replace('D:/rdd/mc/The Best of Twilight Forest',$root.Replace([char]92,[char]47))
  $deploy=$deploy.Replace($fixedHash,$sha);$policy=$policy.Replace($fixedHash,$sha)
  $fixedSize=if($kind -eq 'fixed-size'){$length+1}else{$length}
  foreach($b in $coreRelease.policyBytes){$policy=$policy.Replace(','+$b+')',','+$fixedSize+')')}
  if($kind -eq 'wrong-root'){$policy=$policy.Replace($root.Replace([char]92,[char]47),(Join-Path $d 'other-live').Replace([char]92,[char]47))}
  $copyFail=$kind -in @('copy-failure','core-copy-failure','rdd-copy-failure')
  if($copyFail){$policy=$policy.Replace('[IO.File]::Copy($Source.artifact,$dest,$true)',"throw 'fixture $tag copy failure'")}
  Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
  Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $scripts 'mc-identity.ps1')
  $poison=Join-Path $d 'poison.txt'
  foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','mcp-drive.ps1','verify.ps1')){Put (Join-Path $scripts $n) ('Add-Content "'+$poison+'" POISON;throw "poison"')}
  $commit=$coreRelease.commit
  $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=$length}
  if($kind -eq 'bad-source'){$r.sourceHeadAfter='0'*40}
  if($kind -eq 'bad-proof'){$r.sourceProof='fixture-invalid-source-proof'}
  if($kind -eq 'wrong-module'){$r.module='plugins:learner'}
  if($kind -eq 'wrong-size'){$r.bytes=$length+1}
  if($kind -eq 'dirty-source'){$r.sourceDirtyCountAfter=1}
  if($kind -eq 'missing-exit'){$r.Remove('gradleExit')}
  if($kind -eq 'nonzero-exit'){$r.gradleExit=1}
  if($kind -eq 'escape'){$r.artifact=Join-Path $root $names[$module]}
  Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
  if($kind -eq 'corrupt-artifact'){Put $artifact 'corrupted-after-receipt'}
  $old=Join-Path (Join-Path $root 'mods') $names[$module];Put $old ($tag+'-old-target');$oldHash=(Get-FileHash $old).Hash
  $api=Join-Path (Join-Path $root 'mods') 'numen_api-neoforge-1.21.1-0.1.3-dev.jar';Put $api ($tag+'-old-api');$apiHash=(Get-FileHash $api).Hash
  $otherModule=if($module -ceq 'core:neoforge'){'plugins:rdd'}else{'core:neoforge'}
  $otherMod=Join-Path (Join-Path $root 'mods') $names[$otherModule];Put $otherMod ($tag+'-other-module');$otherModHash=(Get-FileHash $otherMod).Hash
  $learner=Join-Path (Join-Path $root 'mods') $names['plugins:learner'];Put $learner ($tag+'-old-learner');$learnerHash=(Get-FileHash $learner).Hash
  $other=Join-Path (Join-Path $root 'mods') 'unrelated.jar';Put $other ($tag+'-unrelated');$otherHash=(Get-FileHash $other).Hash
  $cim=if($kind -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($kind -eq 'unknown'){'throw "CIM unavailable"'}else{'return @()'}
  $argsText='-Mode '+$coreRelease.mode+' -Instance gpt'
  if($kind -eq 'env-only'){$argsText='-Mode '+$coreRelease.mode}
  if($kind -eq 'wrong-instance'){$argsText='-Mode '+$coreRelease.mode+' -Instance test'}
  if($kind -eq 'jarpath'){$argsText+=' -JarPath "'+$artifact+'"'}
  if($kind -eq 'jarname'){$argsText+=' -JarName "'+$names[$module]+'"'}
  if($kind -eq 'full'){$argsText='-Mode full -Instance gpt'}
  if($kind -eq 'isolated'){$argsText='-Mode isolated-test -Instance test'}
  if($kind -eq 'bad-id'){$id='mutation-build-not-'+$tag}
  if($kind -eq 'bad-commit'){$commit='0'*40}
  $wanted=if($kind -eq 'bad-sha'){'0'*64}elseif($kind -eq 'swapped-sha' -and $null -ne $otherTupleHash){$otherTupleHash}else{$sha}
  $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="gpt"; & "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$id+' -ExpectedCommit '+$commit+' -ExpectedSha256 '+$wanted+'; exit $LASTEXITCODE'
  $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
  $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
  Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
  $ok=$kind -in @('core','rdd')
  if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('parse failure in '+$case)}
  if(($exit -eq 0) -ne $ok){throw ('unexpected '+$case+' exit '+$exit)}
  if(Test-Path $poison){throw $tag+' entry invoked generic config/launch'}
  if((Get-FileHash $other).Hash -ne $otherHash -or (Get-FileHash $otherMod).Hash -ne $otherModHash -or (Get-FileHash $learner).Hash -ne $learnerHash){throw $tag+' entry touched another package'}
  $receipts=@(Get-ChildItem $md -Filter 'deploy-test-*.json')
  $expectedBackups=if($module -ceq 'core:neoforge'){2}else{1}
  if($ok -or $copyFail){
   if($receipts.Count -ne 1){throw $tag+' missing or duplicate copy receipt'}
   $receipt=Get-Content $receipts[0].FullName -Raw | ConvertFrom-Json
   if($receipt.sourceCommit -cne $commit -or $receipt.module -cne $module -or $receipt.sha256 -ine $sha -or $receipt.root -cne $root.Replace([char]92,[char]47) -or @($receipt.backups).Count -ne $expectedBackups){throw $tag+' copy receipt mismatch'}
   foreach($backup in $receipt.backups){
    $expectedOld=if($backup.original -eq $api){$apiHash}elseif($backup.original -eq $old){$oldHash}else{throw 'unexpected backup path'}
    if(-not(Test-Path $backup.saved) -or (Get-FileHash $backup.saved).Hash -ne $expectedOld -or $backup.sha256 -ne $expectedOld){throw $tag+' original backup not recoverable'}
   }
   if($module -ceq 'core:neoforge'){
    if(Test-Path $api){throw $tag+' core left standalone API after copy stage'}
   }elseif((Get-FileHash $api).Hash -ne $apiHash){throw $tag+' RDD changed standalone API'}
   if($ok){
    if((Get-FileHash $old).Hash -ne $sha -or $receipt.success -ne $true -or $receipt.status -cne 'DEPLOYED_TEST'){throw $tag+' successful copy mismatch'}
   }else{
    if((Get-FileHash $old).Hash -ne $oldHash -or $receipt.success -ne $false -or $receipt.status -cne 'failed' -or ($output -join ' ') -notmatch ('fixture\s+'+$tag+'\s+copy\s+failure')){throw $tag+' copy failure misreported'}
   }
  }else{
   if((Get-FileHash $old).Hash -ne $oldHash -or (Get-FileHash $api).Hash -ne $apiHash -or $receipts.Count -ne 0){throw $tag+' refusal changed target/API or entered copy stage'}
  }
  $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope=('copied exact '+$tag+' core/RDD entry, fixture files/CIM only; no production deployment')}
 }
}

Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 4)
Write-Output ('PASS '+$results.Count+' isolated test-deploy cases; no production entry/CIM/config')
# Do not leak the expected nonzero exit from the final refusal fixture.
exit 0
