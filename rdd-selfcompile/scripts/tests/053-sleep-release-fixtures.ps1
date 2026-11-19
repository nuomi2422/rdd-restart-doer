# Exact 053 sleep-retry transition using relocated files and fake process state.
param([Parameter(Mandatory=$true)][string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $EvidenceDir){throw 'fresh fixture directory required'}
New-Item -ItemType Directory -Path $EvidenceDir | Out-Null
$src=Split-Path $PSScriptRoot -Parent
$rdd='numen-plugin-rdd-1.21.1-0.1.3-dev.jar'
$rootLiteral='D:/rdd/mc/The Best of Twilight Forest'
$mutLiteral='D:/rdd/workspace/rdd-selfcompile/mutations'
$oldId='mutation-build-66e83074983b4bca9b6bba9816d7ee0b'
$newId='mutation-build-61bb38e06c114253b74aeff0b247013c'
$oldCommit='3f3be4e1e84e378e5ce0d5e20f8ba84ac95a17bc'
$newCommit='3ed4f016e01e79d106fb97054a8931204b7a8f58'
$oldDigest='d11a9a5870dd6cf7a0bb6782c761e2b5aba018e0e563b60acc62650a37c1016a'
$newDigest='6874a747c34392e39b0a80279fe9ec2caf3876006369b315bcf7ab9aa591dd2c'
$newRealHash='80B66639FF83E7FB289136E6B8F5A088CC0558DABADF2720490D0590AF4769A6'
$core='numen-neoforge-1.21.1-0.1.3-dev.jar'
$oldCoreHash='644977E1F8E487719EBC660EA050037CEA52971BCAF6B6BE9C26194B091CCFB1'
$deployText=Get-Content -LiteralPath (Join-Path $src 'deploy.ps1') -Raw -Encoding UTF8
$policyText=Get-Content -LiteralPath (Join-Path $src 'deploy-test-policy.ps1') -Raw -Encoding UTF8
$guardText=Get-Content -LiteralPath (Join-Path $src 'bounded-live-launch-policy.ps1') -Raw -Encoding UTF8
$launchText=Get-Content -LiteralPath (Join-Path $src 'launch-mc.ps1') -Raw -Encoding UTF8
$stopAt='$env:RDD_LEVEL = $global:RDD_SC.MC_SAVE'
if($launchText.IndexOf($stopAt) -lt 0){throw 'launch policy boundary missing'}
# Execute the real entry up to the decision; do not retain any launcher process code.
$launchPrefix=$launchText.Substring(0,$launchText.IndexOf($stopAt))+"`nWrite-Output 'FIXTURE_LAUNCH_ALLOWED';exit 0"
$packages=@{}
foreach($hit in [regex]::Matches($guardText,"(?m)^\s*'([^']+\.jar)'\s*=\s*'([A-F0-9]{64})'\s*$")){
    $packages.Add($hit.Groups[1].Value,$hit.Groups[2].Value)
}
if($packages.Count -ne 10 -or -not $packages.ContainsKey($rdd)){throw 'base set is not ten packages'}
function Put($p,$s){[IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($true))}
function Digest($map){
    [string[]]$names=@($map.Keys);[Array]::Sort($names,[StringComparer]::Ordinal)
    $rows=@($names|ForEach-Object{ $_+'='+$map[$_].ToLowerInvariant() })
    $sha=[Security.Cryptography.SHA256]::Create()
    try{[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($rows -join ([char]10))))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
$updated=$packages.Clone();$updated[$rdd]=$newRealHash
if((Digest $packages) -ne $oldDigest -or (Digest $updated) -ne $newDigest){throw 'pinned launch digest differs from package map'}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Join-Path $EvidenceDir 'original'
$mods=Join-Path $root 'mods'
$scripts=Join-Path $EvidenceDir 'scripts'
$mut=Join-Path $EvidenceDir 'mutations'
$disabled=Join-Path $root 'disabled'
New-Item -ItemType Directory -Path $mods,$scripts,$mut,$disabled,(Join-Path $root 'saves/live'),(Join-Path $root 'shaderpacks') -Force | Out-Null
$level=Join-Path $root 'saves/live/level.dat'
$batch=Join-Path $root 'shaderpacks/launch-live.bat'
Put $level 'original fixture save'
Put $batch 'fixture-only batch'
$levelHash=(Get-FileHash -LiteralPath $level).Hash
$preserved=Join-Path $disabled $core
Put $preserved 'prior core fixture'
$zip=[IO.Compression.ZipFile]::Open((Join-Path $mods $core),[IO.Compression.ZipArchiveMode]::Create)
try{ $null=$zip.CreateEntry('META-INF/jarjar/com.dwinovo.numen.api.numen_api-neoforge-1.21.1-0.1.3-dev.jar') }
finally{ $zip.Dispose() }
$old=@{}
foreach($name in $packages.Keys){
    $file=Join-Path $mods $name
    if($name -ne $core){Put $file ('fixture: '+$name)}
    $old[$name]=(Get-FileHash -LiteralPath $file).Hash
}

function Build($id,$commit,$label){
    $dir=Join-Path $mut $id
    $jar=Join-Path $dir 'jar'
    New-Item -ItemType Directory -Path $jar -Force | Out-Null
    $artifact=Join-Path $jar $rdd
    Put $artifact $label
    $sha=(Get-FileHash -LiteralPath $artifact).Hash
    $bytes=(Get-Item -LiteralPath $artifact).Length
    $receipt=@{artifact=$artifact;status='passed';success=$true;gradleExit=0;deployed=$false;stage='build-only';module='plugins:rdd';instance='test';mutationId=$id;sourceHead=$commit;sourceHeadAfter=$commit;expectedCommit=$commit;sourceDirtyCount=0;sourceDirtyCountAfter=0;sourceProof='pre-post-checks-consistent';sha256=$sha;bytes=$bytes}
    $phase=Join-Path $dir 'phase-build.json'
    Put $phase ($receipt|ConvertTo-Json)
    @{path=$artifact;sha=$sha;bytes=$bytes;phase=$phase;receipt=$receipt;id=$id;commit=$commit;dir=$dir}
}
$before=Build $oldId $oldCommit ('fixture: '+$rdd)
$after=Build $newId $newCommit 'new sleep-retry RDD fixture'
if($before.sha -ne $old[$rdd]){throw 'old rollback source mismatch'}
$new=$old.Clone();$new[$rdd]=$after.sha
$replace=@{
    $rootLiteral=$root.Replace([char]92,[char]47)
    $mutLiteral=$mut.Replace([char]92,[char]47)
    $oldDigest=(Digest $old)
    $newDigest=(Digest $new)
    $oldCoreHash=(Get-FileHash -LiteralPath $preserved).Hash
    'eb1f4a378cd78a76ff9a356db5eaeca3ebad7894a12b0bc017e1bd2a171a8494'=(Get-FileHash -LiteralPath $batch).Hash
    $newRealHash=$after.sha
}
foreach($n in $packages.Keys){$replace[$packages[$n]]=$old[$n]}
function Relocate([string]$text){
    foreach($key in $replace.Keys){$text=$text.Replace($key,[string]$replace[$key])}
    return $text.Replace(',1308931,',(','+$after.bytes+',')).Replace(',1307211,',(','+$before.bytes+','))
}
Put (Join-Path $scripts 'deploy.ps1') (Relocate $deployText)
Put (Join-Path $scripts 'launch-mc.ps1') (Relocate $launchPrefix)
Put (Join-Path $scripts 'deploy-test-policy.ps1') (Relocate $policyText)
Put (Join-Path $scripts 'bounded-live-launch-policy.ps1') (Relocate $guardText)
Copy-Item -LiteralPath (Join-Path $src 'mc-identity.ps1') -Destination $scripts
Put (Join-Path $scripts 'config.ps1') '$global:RDD_SC=@{SC_INSTANCE=$env:RDD_SELF_COMPILE_INSTANCE;MC_GAME_DIR=$env:FIXTURE_ROOT;MC_SAVE="live";MC_BAT=(Join-Path $env:FIXTURE_ROOT "shaderpacks/launch-live.bat")}'
Put (Join-Path $scripts 'mc-instance.ps1') 'function Get-RddMcState { param($Instance);return $env:FIXTURE_STATE }'
$runner=Join-Path $EvidenceDir 'runner.ps1'
Put $runner @'
param([string]$Entry,[string]$Mode,[string]$Instance,[string]$State,[string]$FixtureRoot,
      [string]$Level,[string]$Build,[string]$Commit,[string]$Sha,[switch]$EnvOnly,[switch]$JarOverride)
$env:FIXTURE_STATE=$State
$env:FIXTURE_ROOT=$FixtureRoot
$env:RDD_LEVEL=$Level
$env:RDD_SELF_COMPILE_INSTANCE=$Instance
function Get-CimInstance {
    if($env:FIXTURE_STATE -eq 'RUNNING'){return [pscustomobject]@{CommandLine=('java --gameDir "'+$env:FIXTURE_ROOT+'"')}}
    if($env:FIXTURE_STATE -eq 'UNKNOWN'){throw 'fixture CIM unavailable'}
    return @()
}
function Start-Process { throw 'fixture must never start a process' }
$a=@{Mode=$Mode}
if(-not $EnvOnly){$a.Instance=$Instance}
if($Build){$a.MutationId=$Build;$a.ExpectedCommit=$Commit;$a.ExpectedSha256=$Sha}
if($JarOverride){$a.JarName='other.jar'}
& $Entry @a
exit $LASTEXITCODE
'@
$results=[Collections.Generic.List[Object]]::new()
function Call($label,$entry,$mode,[bool]$accept,[string]$reason,$source=$null,$options=@{}){
    $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-Entry',(Join-Path $scripts $entry),'-Mode',$mode,
        '-Instance',$(if($options.Instance){$options.Instance}else{'gpt'}),
        '-State',$(if($options.State){$options.State}else{'STOPPED'}),'-FixtureRoot',$root)
    if($options.Level){$a+=@('-Level',$options.Level)}
    if($options.EnvOnly){$a+='-EnvOnly'}
    if($options.JarOverride){$a+='-JarOverride'}
    if($source){$a+=@('-Build',$source.id,'-Commit',$source.commit,'-Sha',$source.sha)}
    $ErrorActionPreference='Continue';$out=& powershell.exe @a 2>&1;$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
    $log=$out -join [Environment]::NewLine
    Put (Join-Path $EvidenceDir ($label+'.txt')) $log
    if(($code -eq 0) -ne $accept -or ($reason -and $log -notmatch $reason) -or
        $log -match 'ParserError|UnexpectedToken|fixture must never start a process'){
        throw "$label exit=$code unexpected; see $EvidenceDir"
    }
    $results.Add(@{case=$label;exit=$code;passed=$true})
}
function Assert-Set($map){
    $files=@(Get-ChildItem -LiteralPath $mods -File -Filter '*.jar')
    if($files.Count -ne $map.Count){throw 'mixed mod set'}
    foreach($j in $files){if((Get-FileHash -LiteralPath $j.FullName).Hash -ne $map[$j.Name]){throw "wrong on-disk hash: $($j.Name)"}}
    if((Get-FileHash -LiteralPath $level).Hash -ne $levelHash){throw 'save changed'}
}

$deployMode='original-053-sleep-retry'
$launchMode='053-sleep-retry-launch'
Call 'old-launch-accepts-old' 'launch-mc.ps1' '053-overnight-launch' $true 'FIXTURE_LAUNCH_ALLOWED'
Call 'new-launch-refuses-old-rdd' 'launch-mc.ps1' $launchMode $false 'package hash mismatch'
$bad=$after.Clone();$bad.sha='0'*64
Call 'install-wrong-rdd-argument' 'deploy.ps1' $deployMode $false 'DEPLOY_REFUSED' $bad
Call 'install-refuses-old-tuple' 'deploy.ps1' $deployMode $false 'DEPLOY_REFUSED' $before
Call 'install-wrong-instance' 'deploy.ps1' $deployMode $false 'DEPLOY_REFUSED' $after @{Instance='test'}
Call 'install-env-only' 'deploy.ps1' $deployMode $false 'DEPLOY_REFUSED' $after @{EnvOnly=$true}
Call 'install-arbitrary-jar' 'deploy.ps1' $deployMode $false 'DEPLOY_REFUSED' $after @{JarOverride=$true}
Call 'install-running' 'deploy.ps1' $deployMode $false 'state is RUNNING' $after @{State='RUNNING'}
Call 'install-unknown' 'deploy.ps1' $deployMode $false 'state is UNKNOWN' $after @{State='UNKNOWN'}
Call 'install-wrong-save' 'deploy.ps1' $deployMode $false 'save mismatch' $after @{Level='other'}
Put $after.path 'tampered managed artifact'
Call 'install-bad-artifact' 'deploy.ps1' $deployMode $false 'artifact hash or size mismatch' $after
Put $after.path 'new sleep-retry RDD fixture'
$after.receipt.bytes++
Put $after.phase ($after.receipt|ConvertTo-Json)
Call 'install-size-disagrees' 'deploy.ps1' $deployMode $false 'artifact hash or size mismatch' $after
$after.receipt.bytes--
Put $after.phase ($after.receipt|ConvertTo-Json)

$other=Join-Path $mods 'numen-plugin-acx-1.21.1-0.1.3-dev.jar'
$untouched=[IO.File]::ReadAllBytes($other)
Put $other 'mixed legacy ACX'
Call 'install-refuses-other-package-change' 'deploy.ps1' $deployMode $false 'package hash mismatch.*acx' $after
[IO.File]::WriteAllBytes($other,$untouched)
if(@(Get-ChildItem -LiteralPath $after.dir -Filter 'deploy-test-*.json').Count -ne 0){throw 'refused input created a receipt'}
Assert-Set $old

Call 'install-only-rdd' 'deploy.ps1' $deployMode $true 'DEPLOYED_TEST' $after
Assert-Set $new
$proofs=@(Get-ChildItem -LiteralPath $after.dir -Filter 'deploy-test-*.json')
if($proofs.Count -ne 1){throw 'missing unique install receipt'}
$receipt=Get-Content -LiteralPath $proofs[0].FullName -Raw | ConvertFrom-Json
if($receipt.module -cne 'plugins:rdd' -or $receipt.sourceCommit -cne $newCommit -or @($receipt.backups).Count -ne 1 -or
    $receipt.backups[0].sha256 -ne $before.sha -or (Get-FileHash -LiteralPath $receipt.backups[0].saved).Hash -ne $before.sha){
    throw 'prior RDD missing from verified backup'
}
Call 'new-launch-accepts-new' 'launch-mc.ps1' $launchMode $true 'FIXTURE_LAUNCH_ALLOWED'
Call 'old-launch-refuses-new-rdd' 'launch-mc.ps1' '053-overnight-launch' $false 'package hash mismatch'
Call 'new-launch-running' 'launch-mc.ps1' $launchMode $false 'LAUNCH_SKIP_ALREADY_RUNNING' $null @{State='RUNNING'}
Call 'new-launch-unknown' 'launch-mc.ps1' $launchMode $false 'LAUNCH_REFUSED_UNKNOWN' $null @{State='UNKNOWN'}
Call 'new-launch-wrong-instance' 'launch-mc.ps1' $launchMode $false 'LAUNCH_REFUSED' $null @{Instance='test'}
Call 'new-launch-env-only' 'launch-mc.ps1' $launchMode $false 'LAUNCH_REFUSED' $null @{EnvOnly=$true}
Call 'new-launch-wrong-save' 'launch-mc.ps1' $launchMode $false 'save mismatch' $null @{Level='other'}
foreach($n in ($packages.Keys | Where-Object {$_ -ne $rdd})){
    $file=Join-Path $mods $n
    $saved=[IO.File]::ReadAllBytes($file)
    Put $file 'mix'
    Call ('new-launch-refuses-mix-'+$n) 'launch-mc.ps1' $launchMode $false ('package hash mismatch: '+[regex]::Escape($n))
    [IO.File]::WriteAllBytes($file,$saved)
}
Call 'old-rdd-restore-uses-existing-entry' 'deploy.ps1' 'original-overnight-frozen' $true 'DEPLOYED_TEST' $before
Assert-Set $old
Call 'old-launch-works-after-restore' 'launch-mc.ps1' '053-overnight-launch' $true 'FIXTURE_LAUNCH_ALLOWED'
Call 'new-launch-refuses-restored-set' 'launch-mc.ps1' $launchMode $false 'package hash mismatch'
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json -Depth 5)
Write-Output ("PASS "+$results.Count+" exact sleep-retry release fixtures")
exit 0
