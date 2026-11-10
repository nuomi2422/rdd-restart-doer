param([string]$EvidenceDir)
$ErrorActionPreference='Stop'
if(Test-Path $EvidenceDir){throw 'fresh evidence required'};New-Item -ItemType Directory $EvidenceDir|Out-Null
$src=Split-Path $PSScriptRoot -Parent;$utf8=[Text.UTF8Encoding]::new($true)
function Put($p,$s){[IO.File]::WriteAllText($p,$s,$utf8)}
$results=@()
foreach($case in @('default','gpt','env','level','nonzero','no-pid','unknown','valid')){
 $d=Join-Path $EvidenceDir $case;New-Item -ItemType Directory $d|Out-Null
 $root=Join-Path $d 'test';New-Item -ItemType Directory $root,(Join-Path $root 'saves'),(Join-Path $root 'logs'),(Join-Path $root 'config'),(Join-Path $root 'config/numen')|Out-Null
 Put (Join-Path $root 'config/numen/mcp_server.json') '{"enabled":false}'
 Put (Join-Path $root 'config/numen/mcp_clients.json') '{"enabled":false,"servers":[]}'
 $body=Get-Content (Join-Path $src 'launch-mc.ps1') -Raw
 Put (Join-Path $d 'launch-mc.ps1') ($body.Replace('D:/rdd/workspace/rdd-selfcompile/instances/test',$root.Replace('\','/')))
 Copy-Item (Join-Path $src 'mc-identity.ps1') (Join-Path $d 'mc-identity.ps1')
 $poison=Join-Path $d 'poison';Put (Join-Path $d 'config.ps1') ('Set-Content "'+$poison+'" poison;throw "config poison"')
 $extra=if($case -eq 'default'){''}elseif($case -eq 'gpt'){'-Mode isolated-title -Instance gpt'}elseif($case -eq 'env'){'-Mode isolated-title'}elseif($case -eq 'level'){'-Mode isolated-title -Instance test -level live'}else{'-Mode isolated-title -Instance test'}
 $exitCode=if($case -eq 'nonzero'){9}else{0};$pidValue=if($case -eq 'no-pid'){0}else{12345}
 $identityRoot=if($case -eq 'unknown'){'D:/other'}else{$root}
 $stub=@'
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction);if($Filter -like 'ProcessId=*'){return [pscustomobject]@{Name='javaw.exe';ProcessId=12345;CreationDate='fixture-time';CommandLine='java --gameDir "IDENTITY"'}};return @()}
function Start-Process {param($FilePath,$ArgumentList,$WorkingDirectory,$RedirectStandardOutput,$RedirectStandardError,$WindowStyle,[switch]$PassThru);if($ArgumentList -contains '--level' -or $ArgumentList -notcontains '--title-only'){throw 'wrong arguments'};[IO.File]::WriteAllText($RedirectStandardOutput,'{"ok":true,"pid":PIDVALUE,"log":"fixture"}');[IO.File]::WriteAllText($RedirectStandardError,'');$o=[pscustomobject]@{ExitCode=EXITVALUE};$o|Add-Member ScriptMethod Refresh {}; $o|Add-Member ScriptMethod WaitForExit {param($ms);return $true};return $o}
'@
 $stub=$stub.Replace('IDENTITY',$identityRoot).Replace('PIDVALUE',[string]$pidValue).Replace('EXITVALUE',[string]$exitCode)
 $runner=Join-Path $d 'run.ps1';Put $runner ($stub+'; $env:RDD_SELF_COMPILE_INSTANCE="test"; & "'+(Join-Path $d 'launch-mc.ps1')+'" '+$extra+'; exit $LASTEXITCODE')
 $ErrorActionPreference='Continue';$out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1;$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Put (Join-Path $d 'output.txt') ($out -join [Environment]::NewLine)
 if(($code -eq 0) -ne ($case -eq 'valid')){throw ('case '+$case+' exit '+$code)}
 if(Test-Path $poison){throw 'config invoked'}
 $results+=@{case=$case;exit=$code;pass=$true}
}
Put (Join-Path $EvidenceDir 'results.json') ($results|ConvertTo-Json)
Write-Output ('PASS '+$results.Count+' copied title launch cases; no actual spawn/CIM/config')
