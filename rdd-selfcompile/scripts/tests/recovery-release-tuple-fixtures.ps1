# recovery-release-tuple fixtures -- frozen offline contract for the ba010 recovery RDD.
# WHY (2026-11-13): register one inspected build without granting generic/test-root release.
# USAGE: powershell.exe -NoProfile -File <this> -EvidenceDir <fresh-temp-path>
# Copies the real deploy/policy; only paths and simulated artifact digests are relocated.
# Fake phase receipts/CIM/artifacts stay under TEMP. Never deploys, launches or stops Minecraft.
# Original identity helpers are read-only dependencies: no identity/mcinstance file is copied/edited.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
$EvidenceDir=[IO.Path]::GetFullPath($EvidenceDir)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)+[char]92
if(-not $EvidenceDir.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $EvidenceDir)){throw 'fresh TEMP fixture directory required'}
New-Item -ItemType Directory $EvidenceDir | Out-Null
$src=Split-Path $PSScriptRoot -Parent
$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
function ReadText($p){[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)}
function Slash($p){$p.Replace([char]92,[char]47)}
function Parse($p){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e);if($e.Count){throw ('fixture environment/parse error: '+$p)}}
function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
$idNew='mutation-build-1fa09220d99b4f78b504e3ea1287cfe5'
$commitNew='ba010d4c616caacd78ff871c23965014f11e016c'
$shaNew='4304CCEADCEA124F60A4034579F7C1BF795B90547AA68A53FEC77A8D323ADD65'
$nameNew='numen-plugin-rdd-1.21.1-0.1.3-dev.jar'
$oldLiveSha='894F7C5E3C08784D75CED0405BC6780976C7A2A8F48C5579C870A51CCD7BB6E5'
$cases=@('new-rdd','repeat','sourcewrongmodule','coreonly','wronghash','artifacthash','receipthash','commit','mutation','name','bytes','fixedbytes','sourceproof','missingproof','gradleexit','missingexit','deployed','dirtybefore','dirtyafter','sourcebefore','sourceafter','receiptcommit','receiptmutation','receiptinstance','status','success','stage','pathescape','root','wronginstance','omittedexplicit','envonly','running','unknown','reparse-source','reparse-root','reparse-mods','JarPath','JarName','full','default','isolated-test','missingcommit','missingsha','copylocked','old-rdd','old-rdd-env','old-core','old-learner','rejected-a182','rejected-0a')
$results=@()
foreach($case in $cases){
 $d=Join-Path $EvidenceDir $case;$scripts=Join-Path $d 'scripts';$root=Join-Path $d 'original-live';$mut=Join-Path $d 'mutations'
 New-Item -ItemType Directory $scripts,$mut | Out-Null
 if($case -eq 'reparse-root'){$payload=Join-Path $d 'root-payload';New-Item -ItemType Directory $payload | Out-Null;New-Item -ItemType Junction -Path $root -Target $payload | Out-Null}else{New-Item -ItemType Directory $root | Out-Null}
 $mods=Join-Path $root 'mods'
 if($case -eq 'reparse-mods'){$payload=Join-Path $d 'mods-payload';New-Item -ItemType Directory $payload | Out-Null;New-Item -ItemType Junction -Path $mods -Target $payload | Out-Null}else{New-Item -ItemType Directory $mods | Out-Null}
 $id=$idNew;$commit=$commitNew;$fixedSha=$shaNew;$name=$nameNew;$module='plugins:rdd';$mode='original-rdd';$size=1153095
 if($case -in @('old-rdd','old-rdd-env')){$id='mutation-build-19ecce8338544ef789794af2c268c681';$commit='6d848bdae594859c24e2d3d5e3d0ac48d931f439';$fixedSha='E13FD247A7627D37135DC060AD31A1D596E53F07AB3D5D150ACB84FBBF4DFE3E'}
 if($case -eq 'old-core'){$id='mutation-build-702ea0b018534536977499b23ccee172';$commit='78c3fd296145c79dd3bad5dda643641b2ccf2a70';$fixedSha='789EF0A21435E7939058E2EDEF74F078386EF2BB7B9E296D54EDF0091FA97E67';$name='numen-neoforge-1.21.1-0.1.3-dev.jar';$module='core:neoforge';$mode='original-mine-recovery'}
 if($case -eq 'old-learner'){$id='mutation-build-52876a2a2dd44cc68009c3ad4992de35';$commit='65ffba3ecdd9171eb59af470ba275f9e6655900f';$fixedSha='BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A';$name='numen-plugin-learner-1.21.1-0.1.3-dev.jar';$module='plugins:learner';$mode='original-learner'}
 if($case -eq 'rejected-a182'){$id='mutation-build-3f3141f9f1ea4952accb744e620fb5d4';$commit='a18215c6f8434e3f388c95c6e6d49734d0db6912';$fixedSha='EBDC5EFCE4423180D9FB0E2896A3DEF417550E6D5DD9B6BA336A07A93795EDB1';$size=1152233}
 if($case -eq 'rejected-0a'){$commit='0a077116189740bf9c43fd0375c4274ea7b0ae0f'}
 if($case -eq 'fixedbytes'){$size++}
 $md=Join-Path $mut $id;$jd=Join-Path $md 'jar';New-Item -ItemType Directory $md | Out-Null
 if($case -eq 'reparse-source'){$payload=Join-Path $d 'jar-payload';New-Item -ItemType Directory $payload | Out-Null;New-Item -ItemType Junction -Path $jd -Target $payload | Out-Null}else{New-Item -ItemType Directory $jd | Out-Null}
 $artifact=Join-Path $jd $name
 if($case -in @('name','coreonly')){$artifact=Join-Path $jd 'numen-neoforge-1.21.1-0.1.3-dev.jar'}
 [IO.File]::WriteAllBytes($artifact,(New-Object byte[] $size));$sha=Hash $artifact
 $deploy=(ReadText (Join-Path $src 'deploy.ps1')).Replace('D:/rdd/workspace/rdd-selfcompile/mutations',(Slash $mut)).Replace('D:/rdd/workspace/rdd-selfcompile/instances/test',(Slash $root)).Replace('D:/rdd/mc/The Best of Twilight Forest',(Slash $root)).Replace($fixedSha,$sha)
 # Resolve existing identity dependency read-only; do not touch this sibling-owned source.
 $deploy=$deploy.Replace('$PSScriptRoot\mc-identity.ps1',(Join-Path $src 'mc-identity.ps1'))
 $policy=(ReadText (Join-Path $src 'deploy-test-policy.ps1')).Replace('D:/rdd/mc/The Best of Twilight Forest',(Slash $root)).Replace($fixedSha,$sha)
 if($case -eq 'root'){
  $otherRoot=Join-Path $d 'other-root';New-Item -ItemType Directory $otherRoot,(Join-Path $otherRoot 'mods') | Out-Null
  $deploy=$deploy.Replace(("-Root '"+(Slash $root)+"'"),("-Root '"+(Slash $otherRoot)+"'"))
 }
 Put (Join-Path $scripts 'deploy.ps1') $deploy;Put (Join-Path $scripts 'deploy-test-policy.ps1') $policy
 $poison=Join-Path $d 'poison.txt'
 foreach($n in @('config.ps1','launch-mc.ps1','new-mutation.ps1','verify.ps1','mcp-drive.ps1','build-jar.ps1')){Put (Join-Path $scripts $n) ('[IO.File]::WriteAllText("'+$poison+'","POISON");throw "poison"')}
 $r=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module=$module;instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=$size;fixture='FAKE receipt, temporary directory only'}
 switch($case){
  'sourcewrongmodule'{$r.module='core:neoforge'} 'coreonly'{$r.module='core:neoforge'}
  'receipthash'{$r.sha256='0'*64} 'bytes'{$r.bytes++}
  'sourceproof'{$r.sourceProof='unverified'} 'missingproof'{$r.Remove('sourceProof')}
  'gradleexit'{$r.gradleExit=1} 'missingexit'{$r.Remove('gradleExit')}
  'deployed'{$r.deployed=$true} 'dirtybefore'{$r.sourceDirtyCount=1} 'dirtyafter'{$r.sourceDirtyCountAfter=1}
  'sourcebefore'{$r.sourceHead='0'*40} 'sourceafter'{$r.sourceHeadAfter='0'*40} 'receiptcommit'{$r.expectedCommit='0'*40}
  'receiptmutation'{$r.mutationId='mutation-build-wrong'} 'receiptinstance'{$r.instance='gpt'}
  'status'{$r.status='failed'} 'success'{$r.success=$false} 'stage'{$r.stage='full'}
  'pathescape'{$r.artifact=Join-Path $d $name}
 }
 Put (Join-Path $md 'phase-build.json') ($r|ConvertTo-Json)
 $phaseHash=Hash (Join-Path $md 'phase-build.json')
 if($case -eq 'artifacthash'){[IO.File]::WriteAllBytes($artifact,(New-Object byte[] ($size+1)))}
 $dest=Join-Path $mods $name;Put $dest ('FAKE old artifact '+$oldLiveSha);$oldHash=Hash $dest
 $sentinels=@{}
 foreach($n in @('numen_api-neoforge-1.21.1-0.1.3-dev.jar','unrelated.jar','unchanged.txt','numen-plugin-acx-1.21.1-0.1.3-dev.jar')){$p=Join-Path $mods $n;Put $p ('FAKE unchanged '+$n);$sentinels[$p]=Hash $p}
 if($module -ne 'core:neoforge'){$p=Join-Path $mods 'numen-neoforge-1.21.1-0.1.3-dev.jar';Put $p 'FAKE live core 789EF0';$sentinels[$p]=Hash $p}
 $cim=if($case -eq 'running'){'return @([pscustomobject]@{CommandLine=''java --gameDir "ROOT"''})'.Replace('ROOT',$root)}elseif($case -eq 'unknown'){'throw "FAKE CIM unavailable"'}else{'return @()'}
 $argsText='-Mode '+$mode+' -Instance gpt';$envInstance='gpt'
 switch($case){
  'wronginstance'{$argsText='-Mode original-rdd -Instance test'}
  'omittedexplicit'{$argsText='-Mode original-rdd';$envInstance=''} 'envonly'{$argsText='-Mode original-rdd'}
  'old-rdd-env'{$argsText='-Mode original-rdd'}
  'full'{$argsText='-Mode full -Instance gpt'} 'default'{$argsText='-Instance gpt'}
  'isolated-test'{$argsText='-Mode isolated-test -Instance test'}
  'JarPath'{$argsText+=' -JarPath "'+$artifact+'"'} 'JarName'{$argsText+=' -JarName override.jar'}
 }
 $wantedCommit=if($case -eq 'commit'){'0'*40}else{$commit}
 $wantedSha=if($case -eq 'wronghash'){'0'*64}else{$sha}
 $wantedId=if($case -eq 'mutation'){'mutation-build-not-approved'}else{$id}
 $invoke='& "'+(Join-Path $scripts 'deploy.ps1')+'" '+$argsText+' -MutationId '+$wantedId
 if($case -ne 'missingcommit'){$invoke+=' -ExpectedCommit '+$wantedCommit}
 if($case -ne 'missingsha'){$invoke+=' -ExpectedSha256 '+$wantedSha}
 $wrapper='function Get-CimInstance { '+$cim+' }; $env:RDD_SELF_COMPILE_INSTANCE="'+$envInstance+'"; '+$invoke+'; exit $LASTEXITCODE'
 $runner=Join-Path $d 'run.ps1';Put $runner $wrapper
 foreach($p in @($runner,(Join-Path $scripts 'deploy.ps1'),(Join-Path $scripts 'deploy-test-policy.ps1'))){Parse $p}
 $lock=$null
 try{
  if($case -eq 'copylocked'){$lock=[IO.File]::Open($dest,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
  $ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -File $runner 2>&1;$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 }finally{if($lock){$lock.Dispose()}}
 $text=$output -join [Environment]::NewLine;Put (Join-Path $d 'output.txt') $text
 if($text -match 'ParserError|UnexpectedToken|PSSecurityException|not recognized|CommandNotFoundException|poison'){throw ('environment/fixture failure, not business red: '+$case)}
 $ok=$case -in @('new-rdd','repeat','old-rdd','old-rdd-env','old-core','old-learner')
 $expected=if($case -in @('sourcewrongmodule','gradleexit','missingexit','deployed','receiptmutation','receiptinstance','status','success','stage')){'invalid build receipt'}elseif($case -in @('sourceproof','missingproof','dirtybefore','dirtyafter','sourcebefore','sourceafter','receiptcommit')){'invalid source proof'}elseif($case -in @('bytes','fixedbytes','artifacthash','receipthash')){'artifact hash or size mismatch'}elseif($case -eq 'wronghash'){'expected sha differs from fixed artifact'}elseif($case -in @('commit','missingcommit')){'unapproved source selection'}elseif($case -eq 'missingsha'){'expected sha differs from fixed artifact'}elseif($case -eq 'pathescape'){'artifact escapes fixed mutation jar'}elseif($case -eq 'root'){'unapproved original deployment'}elseif($case.StartsWith('reparse-')){'linked path refused'}elseif($case -in @('running','unknown')){'test instance not proven stopped'}elseif($case -eq 'isolated-test'){'recovery artifact requires original deployment'}elseif($case -in @('name','coreonly')){'artifact escapes fixed mutation jar'}elseif($case -eq 'copylocked'){'used by another process'}else{'DEPLOY_REFUSED: incident-freeze'}
 $normalized=$text -replace '\s+',' '
 $reasonMatched=$ok -or (($text -replace '\s+','') -match [regex]::Escape(($expected -replace '\s+','')))
 $receipts=@(Get-ChildItem -LiteralPath $md -Filter 'deploy-test-*.json')
 if(Test-Path $poison){throw ('generic entry reached: '+$case)}
 if((Hash (Join-Path $md 'phase-build.json')) -cne $phaseHash){throw 'fake input receipt changed'}
 foreach($p in $sentinels.Keys){if($ok -and $module -eq 'core:neoforge' -and $p.EndsWith('numen_api-neoforge-1.21.1-0.1.3-dev.jar')){if(Test-Path $p){throw 'legacy core API behavior changed'}}elseif(!(Test-Path $p) -or (Hash $p) -cne $sentinels[$p]){throw ('unrelated/API file changed: '+$case)}}
 if($code -eq 0){
  if(-not $ok){throw ('unsafe false success: '+$case)}
  if((Hash $dest) -cne $sha -or $receipts.Count -ne 1){throw ('destination or receipt mismatch: '+$case)}
  $rr=ReadText $receipts[0].FullName|ConvertFrom-Json
  if(!$rr.success -or $rr.status -cne 'DEPLOYED_TEST' -or $rr.root -cne (Slash $root) -or $rr.sourceCommit -cne $commit -or $rr.sha256 -cne $sha -or $rr.module -cne $module){throw 'bad success receipt'}
  $backups=@($rr.backups|Where-Object {$_.original -eq $dest})
  if($backups.Count -ne 1 -or $backups[0].sha256 -cne $oldHash -or (Hash $backups[0].saved) -cne $oldHash){throw 'original old RDD backup mismatch'}
  if($module -eq 'plugins:rdd' -and $rr.backups.Count -ne 1){throw 'RDD touched other artifacts'}
  foreach($b in $rr.backups){if((Hash $b.saved) -cne $b.sha256){throw 'backup hash mismatch'}}
  if($case -eq 'repeat'){
   $first=$backups[0].saved;$ErrorActionPreference='Continue';$again=& powershell.exe -NoProfile -File $runner 2>&1;$repeatCode=$LASTEXITCODE;$ErrorActionPreference='Stop'
   Put (Join-Path $d 'repeat-output.txt') ($again -join [Environment]::NewLine)
   if($repeatCode -ne 0 -or (Hash $first) -cne $oldHash -or (Hash $dest) -cne $sha -or @(Get-ChildItem $md -Filter 'deploy-test-*.json').Count -ne 2){throw 'repeat lost first backup'}
  }
 }else{
  if((Hash $dest) -cne $oldHash){throw ('refusal/error modified destination: '+$case)}
  foreach($p in $receipts){if((ReadText $p.FullName|ConvertFrom-Json).success){throw 'refusal signed success'}}
 }
 $classification=if($ok -and $code -ne 0){'missing-required-positive'}elseif(-not $reasonMatched -and $normalized -match 'DEPLOY_REFUSED: incident-freeze|unapproved source selection'){'registration-masked-guard'}elseif(-not $reasonMatched){'wrong-refusal-reason'}else{'pass'}
 $results+=[pscustomobject]@{case=$case;exit=$code;expectedSuccess=$ok;passed=($classification -eq 'pass');classification=$classification;expectedReason=$expected;reasonMatched=$reasonMatched;scope='TEMP copied production guards; fake receipt/artifact digest/CIM; NOT production release'}
 Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
}
$bad=@($results|Where-Object {!$_.passed})
Put (Join-Path $EvidenceDir 'summary.json') (@{total=$results.Count;passed=$results.Count-$bad.Count;notPassed=$bad.Count;productionDeploy=$false;fixtureSha256=(Hash $PSCommandPath);groups=@($results|Group-Object classification|ForEach-Object {@{classification=$_.Name;count=$_.Count}})}|ConvertTo-Json -Depth 5)
Write-Output ('OFFLINE CONTRACT cases='+$results.Count+' pass='+($results.Count-$bad.Count)+' notPassed='+$bad.Count+'; no live IO/launch/stop/MCP')
if($bad.Count){exit 1};exit 0
