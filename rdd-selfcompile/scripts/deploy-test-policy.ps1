# 2026-11-11: narrow fixed-artifact test assembly. No live config or launch access.
function Assert-RddOrdinaryPath {
 param([string]$Path)
 $p=[IO.Path]::GetFullPath($Path)
 while($p){
  $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'linked path refused'}
  $parent=Split-Path $p -Parent
  if($parent -eq $p){break};$p=$parent
 }
}
function Get-RddTestDeploySource {
 param([string]$MutationId,[string]$ExpectedCommit,[string]$ExpectedSha256,[string]$Mutations)
 $fixed=@{
  'mutation-build-ffa63f9a7b714ec6a9168d1b657c8e4d'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','D8999610E5777B4A8F087C5C59C86C1D54E3187BF0C50EDA520D88DF6E97D056')
  'mutation-build-0057cbc54b26481194dd1bf413c6a8b4'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','E69DBC81A5C4539F83809FBFF89D693295750754ED7278B2B00566B08F007435')
  'mutation-build-52876a2a2dd44cc68009c3ad4992de35'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A')
 }
 $commit='65ffba3ecdd9171eb59af470ba275f9e6655900f'
 # 2026-11-11: bounded no-chain observation fix, only this new RDD artifact.
 if($MutationId -ceq 'mutation-build-6b8413e1eb554f6db920c9760c89a270'){
  $fixed=@{'mutation-build-6b8413e1eb554f6db920c9760c89a270'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','E06DAA86F139312CEB7A7ED4DED5D7312C3DCD2DD6DB6114049AAFF2CD243EFD')}
  $commit='7760964f2f6e0b41d5a56e91d3ba835df9d92530'
 }
 if($MutationId -ceq 'mutation-build-1143a45ccf7c4b2789bb45ddc6dc5590'){
  $fixed=@{'mutation-build-1143a45ccf7c4b2789bb45ddc6dc5590'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','9FCA8846600702A092FC8ED299FAD76CBFC9167039B5A434BDFBDFBCC25CBA9D')}
  $commit='6b87976f9726936497544703fa596088a5ad6f5f'
 }
 if($MutationId -ceq 'mutation-build-a4d56867456a4f18820d070a167ffa0a'){
  $fixed=@{'mutation-build-a4d56867456a4f18820d070a167ffa0a'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','70526EA8562A8B03EB36324D529604D1A8AC2FB1EDA7666106B4301D50FB7D17')}
  $commit='cbe8ad44c0b18f3ab5ec0d2c19ccc7e91e677fe2'
 }
 if($MutationId -ceq 'mutation-build-60befb539f4e4c24b129e05c2f434d6b'){
  $fixed=@{'mutation-build-60befb539f4e4c24b129e05c2f434d6b'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','CF2D115CC63997473668EEF6A13A5F259A4E483FE517BE66F2194B88862509CF')}
  $commit='a5c47538f38ece2b65c0ef863bde865627eb4310'
 }
 if($MutationId -cin @('mutation-build-3fde7607688541eb99b3de87fbbf6ad7','mutation-build-fc5f2711d6a545338719cc95750ce50d')){
  $fixed=@{
   'mutation-build-3fde7607688541eb99b3de87fbbf6ad7'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','6F543C5CF947F9CE163691663F3124EF3F91C1B6AC79E3A3118D7173BA420E64')
   'mutation-build-fc5f2711d6a545338719cc95750ce50d'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','40D367375CBCEE41723B8162F70F69DB732A4B9CACE2DEE74FAE5AB02A7219E8')
  }
  $commit='e1ad23d0fbb4679e3af749d377b39b6b2da45fbe'
 }
 if($MutationId -ceq 'mutation-build-7a2cded71c3e4230b7cca93ab67aa06f'){
  $fixed=@{'mutation-build-7a2cded71c3e4230b7cca93ab67aa06f'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','04A5195DD1AEE334F20B8B4017E195D8DB360D2614E5E9B8710E2E4AB303562D')}
  $commit='d06618143655f7608890c86ea48a8dcb43dc1341'
 }
 if($MutationId -ceq 'mutation-build-8fe58bf41a5f456fbc5d407e2484fae3'){
  $fixed=@{'mutation-build-8fe58bf41a5f456fbc5d407e2484fae3'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','F90EB4AC7A80EA6D0188432A75A5B9362BFE17E61E45158369588EAC66C54753')}
  $commit='7cf784df48d0362e60fa70e300b7711feaaa9452'
 }
 if($MutationId -ceq 'mutation-build-84a320cad8ea474cab53da9d17480292'){
  $fixed=@{'mutation-build-84a320cad8ea474cab53da9d17480292'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','ACB70945FAE340207EE7D3E08B24547512B522E7ADD475DB0189F05AF94640D9')}
  $commit='7cc063c55b86a1bff83d90237c61a3cd12928abb'
 }
 if($ExpectedCommit -cne $commit -or -not $fixed.ContainsKey($MutationId)){throw 'unapproved source selection'}
 $f=$fixed[$MutationId];if($ExpectedSha256 -ine $f[2]){throw 'expected sha differs from fixed artifact'}
 $dir=Join-Path $Mutations $MutationId
 $phase=Join-Path $dir 'phase-build.json';Assert-RddOrdinaryPath $phase
 $r=Get-Content -LiteralPath $phase -Raw -Encoding UTF8 | ConvertFrom-Json
 $artifact=[IO.Path]::GetFullPath((Join-Path (Join-Path $dir 'jar') $f[1]))
 if([IO.Path]::GetFullPath($r.artifact) -ine $artifact){throw 'artifact escapes fixed mutation jar'}
 Assert-RddOrdinaryPath $artifact
 if($r.status -cne 'passed' -or $r.success -ne $true -or $null -eq $r.gradleExit -or $r.gradleExit -ne 0 -or $r.deployed -ne $false -or $r.stage -cne 'build-only' -or $r.module -cne $f[0] -or $r.instance -cne 'test' -or $r.mutationId -cne $MutationId){throw 'invalid build receipt'}
 if($r.sourceHead -cne $commit -or $r.sourceHeadAfter -cne $commit -or $r.expectedCommit -cne $commit -or $null -eq $r.sourceDirtyCount -or $null -eq $r.sourceDirtyCountAfter -or $r.sourceDirtyCount -ne 0 -or $r.sourceDirtyCountAfter -ne 0 -or $r.sourceProof -cne 'pre-post-checks-consistent'){throw 'invalid source proof'}
 $sha=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
 if($sha -ine $f[2] -or $r.sha256 -ine $sha -or (Get-Item -LiteralPath $artifact).Length -ne $r.bytes){throw 'artifact hash or size mismatch'}
 return @{dir=$dir;artifact=$artifact;name=$f[1];sha=$sha;commit=$commit;module=$f[0]}
}
function Get-RddTestDeployState {
 param([string]$Root)
 try{
  $procs=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
  if($procs.Count -eq 0){return 'STOPPED'} # successful CIM enumeration, no Java process
  $matches=@($procs | ForEach-Object {Get-RddMcCommandLineMatch -CommandLine $_.CommandLine -GameDir $Root})
  return Get-RddMcStateFromMatches $matches
 }catch{return 'UNKNOWN'}
}
function Invoke-RddTestAssembly {
 param($Source,[string]$Root,[string]$Live,[switch]$Original)
 Assert-RddOrdinaryPath $Root;Assert-RddOrdinaryPath $Live
 if($Original){
  if($Root -cne 'D:/rdd/mc/The Best of Twilight Forest' -or $Source.commit -cnotin @('6b87976f9726936497544703fa596088a5ad6f5f','cbe8ad44c0b18f3ab5ec0d2c19ccc7e91e677fe2','a5c47538f38ece2b65c0ef863bde865627eb4310','e1ad23d0fbb4679e3af749d377b39b6b2da45fbe','d06618143655f7608890c86ea48a8dcb43dc1341','7cf784df48d0362e60fa70e300b7711feaaa9452')){throw 'unapproved original deployment'}
 }elseif([IO.Path]::GetFullPath($Root) -ieq [IO.Path]::GetFullPath($Live)){throw 'test root is live'}
 $mods=Join-Path $Root 'mods';Assert-RddOrdinaryPath $mods
 if((Get-RddTestDeployState $Root) -cne 'STOPPED'){throw 'test instance not proven stopped'}
 $dest=Join-Path $mods $Source.name
 if(Test-Path -LiteralPath $dest){Assert-RddOrdinaryPath $dest}
 $api=Join-Path $mods 'numen_api-neoforge-1.21.1-0.1.3-dev.jar'
 if($Source.module -ceq 'core:neoforge' -and (Test-Path -LiteralPath $api)){Assert-RddOrdinaryPath $api}
 $attempt='deploy-test-'+[guid]::NewGuid().ToString('N')
 $receipt=Join-Path $Source.dir ($attempt+'.json')
 $backupRoot=Join-Path $Root 'disabled'
 if(Test-Path $backupRoot){Assert-RddOrdinaryPath $backupRoot}else{New-Item -ItemType Directory $backupRoot | Out-Null}
 $backup=Join-Path $backupRoot $attempt;New-Item -ItemType Directory $backup | Out-Null
 $r=@{stage='deploy-test';status='pending';success=$false;instance='test';root=$Root;sourceCommit=$Source.commit;module=$Source.module;sha256=$Source.sha;artifact=$Source.artifact;backups=@();receipt=$receipt}
 try{
  foreach($old in @($dest,$api)){
   if($old -eq $api -and $Source.module -cne 'core:neoforge'){continue}
   if(-not (Test-Path -LiteralPath $old)){continue}
   $oldHash=(Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash
   $saved=Join-Path $backup ([IO.Path]::GetFileName($old))
   [IO.File]::Copy($old,$saved,$false)
   if((Get-FileHash $saved -Algorithm SHA256).Hash -cne $oldHash){throw 'backup hash mismatch'}
   $r.backups+=@{original=$old;saved=$saved;sha256=$oldHash}
  }
  if($Source.module -ceq 'core:neoforge' -and (Test-Path -LiteralPath $api)){[IO.File]::Delete($api)}
  [IO.File]::Copy($Source.artifact,$dest,$true)
  if((Get-FileHash $dest -Algorithm SHA256).Hash -cne $Source.sha){throw 'destination hash mismatch'}
  $r.status='DEPLOYED_TEST';$r.success=$true
 }catch{$r.status='failed';$r.reason=$_.Exception.Message;throw}finally{
  [IO.File]::WriteAllText($receipt,($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 }
 return $r
}
