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
 $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($output -join [Environment]::NewLine)
 $ok=$case -in @('core','rdd','learner','repeat','original-learner')
 if(($output -join ' ') -match 'ParserError|UnexpectedToken'){throw ('script parse failure in '+$case)}
 if(($exit -eq 0) -ne $ok){throw ('unexpected case '+$case+' exit '+$exit)}
 if(Test-Path $poison){throw 'poison invoked'}
 if($case -eq 'link' -and ($output -join ' ') -notmatch 'linked path refu\s*sed'){throw 'root-link did not reach link guard'}
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
   $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1
   if($LASTEXITCODE -ne 0){throw 'repeat failed'}
   for($i=0;$i -lt $saved.Count;$i++){if((Get-FileHash $saved[$i]).Hash -ne $before[$i]){throw 'original backup lost'}}
  }
 }else{foreach($receipt in $receipts){if((Get-Content $receipt.FullName -Raw | ConvertFrom-Json).success){throw 'failure signed success'}}}
 $results+=@{case=$case;exit=$exit;passed=$true;poison=0;scope='temporary copied entry and fixture hashes/CIM only'}
}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 4)
Write-Output ('PASS '+$results.Count+' isolated test-deploy cases; no production entry/CIM/config')
