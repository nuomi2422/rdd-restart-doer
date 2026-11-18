# 2026-11-19: 053 frozen-combo launch guard regressions. No game process, no Java, no live write.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../deploy-test-policy.ps1"
. "$PSScriptRoot/../bounded-live-launch-policy.ps1"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$live='D:/rdd/mc/The Best of Twilight Forest'
$oldCoreSource=Join-Path $live 'mods/numen-neoforge-1.21.1-0.1.3-dev.jar'

function New-Fixture([string]$root,[switch]$NoApiEntry,[switch]$SkipOldCore,[switch]$NoExtraTotals){
    foreach($d in @('saves/live','mods','shaderpacks')){ New-Item -ItemType Directory -Path (Join-Path $root $d) -Force | Out-Null }
    [IO.File]::WriteAllText((Join-Path $root 'saves/live/level.dat'),'fixture-level')
    [IO.File]::WriteAllText((Join-Path $root 'shaderpacks/launch-live.bat'),'fixture-batch')
    if(-not $SkipOldCore){
        $old=Join-Path $root 'disabled/old'; New-Item -ItemType Directory -Path $old -Force | Out-Null
        Copy-Item -LiteralPath $oldCoreSource -Destination (Join-Path $old 'numen-neoforge-1.21.1-0.1.3-dev.jar')
    }
    $coreZipPath=Join-Path $root 'mods/numen-neoforge-1.21.1-0.1.3-dev.jar'
    $zip=[IO.Compression.ZipFile]::Open($coreZipPath,[IO.Compression.ZipArchiveMode]::Create)
    try{
        if(-not $NoApiEntry){
            $entry=$zip.CreateEntry('META-INF/jarjar/com.dwinovo.numen.api.numen_api-neoforge-1.21.1-0.1.3-dev.jar')
            $stream=$entry.Open()
            try{ $bytes=[Text.Encoding]::UTF8.GetBytes('fixture-api'); $stream.Write($bytes,0,$bytes.Length) } finally{ $stream.Dispose() }
        }
    } finally{ $zip.Dispose() }
    foreach($n in @(
        'numen-plugin-rdd-1.21.1-0.1.3-dev.jar','numen-plugin-acx-1.21.1-0.1.3-dev.jar',
        'numen-plugin-learner-1.21.1-0.1.3-dev.jar','numen-plugin-worldstate-1.21.1-0.1.3-dev.jar',
        'numen-plugin-camera-1.21.1-0.1.3-dev.jar','numen-plugin-experience-1.21.1-0.1.3-dev.jar',
        'numen-plugin-selfcompile-1.21.1-0.1.3-dev.jar','numen-plugin-settlement-1.21.1-0.1.3-dev.jar',
        'minecraft-client-controller-neoforge-1.0.0.jar')){
        [IO.File]::WriteAllText((Join-Path $root "mods/$n"), ("fixture:"+$n))
    }
    $map=@{}
    foreach($f in (Get-ChildItem -LiteralPath (Join-Path $root 'mods') -Filter '*.jar')){
        $map[$f.Name]=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    $names=@($map.Keys | ForEach-Object { $_.ToLowerInvariant() })
    [Array]::Sort($names,[StringComparer]::Ordinal)
    $rows=@($names | ForEach-Object { $_ + '=' + $map[$_].ToLowerInvariant() })
    $sha=[Security.Cryptography.SHA256]::Create()
    try{ $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join ([char]10))); $digest=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') }
    finally{ $sha.Dispose() }
    return @{
        Instance='gpt'; GameDir=$root; Save='live'; LevelOverride=''; Batch=(Join-Path $root 'shaderpacks/launch-live.bat')
        ExpectedRoot=$root; BatchSha=(Get-FileHash -LiteralPath (Join-Path $root 'shaderpacks/launch-live.bat') -Algorithm SHA256).Hash
        ModsSha=$digest; State='STOPPED'; ExpectedPackages=$map
    }
}
function Expect-Refusal($set,[string]$reason){
    $caught=$null
    try{ Assert-RddOvernightLaunch @set }catch{ $caught=$_ }
    if(-not $caught -or $caught.Exception.Message -notmatch $reason){ throw "Expected refusal '$reason'; got: $caught" }
    Write-Output ("BLOCK "+$reason)
}
$rootBase=Join-Path ([IO.Path]::GetTempPath()) ('rdd-053-launch-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $rootBase | Out-Null
try{
    $set=New-Fixture (Join-Path $rootBase 'accept')
    Assert-RddOvernightLaunch @set
    Write-Output 'PASS 053 candidate package set, live save, STOPPED and preserved old core'

    $set.State='RUNNING'; Expect-Refusal $set 'instance state is RUNNING'
    $set=New-Fixture (Join-Path $rootBase 'unknown'); $set.State='UNKNOWN'; Expect-Refusal $set 'instance state is UNKNOWN'
    $set=New-Fixture (Join-Path $rootBase 'instance'); $set.Instance='test'; Expect-Refusal $set 'instance mismatch'
    $set=New-Fixture (Join-Path $rootBase 'root'); $set.GameDir=(Join-Path $rootBase 'elsewhere'); Expect-Refusal $set 'instance mismatch'
    $set=New-Fixture (Join-Path $rootBase 'save'); $set.LevelOverride='other'; Expect-Refusal $set 'save mismatch'
    $set=New-Fixture (Join-Path $rootBase 'level'); [IO.File]::WriteAllText((Join-Path $set.GameDir 'saves/live/level.dat'),''); Expect-Refusal $set 'level.dat is missing or empty'
    $set=New-Fixture (Join-Path $rootBase 'batch'); [IO.File]::WriteAllText($set.Batch,'different-batch'); Expect-Refusal $set 'launch batch checksum mismatch'

    $set=New-Fixture (Join-Path $rootBase 'api'); [IO.File]::WriteAllText((Join-Path $set.GameDir 'mods/numen_api-neoforge-1.21.1-0.1.3-dev.jar'),'separate-api'); Expect-Refusal $set 'separate API jar must stay disabled'
    $set=New-Fixture (Join-Path $rootBase 'extra'); [IO.File]::WriteAllText((Join-Path $set.GameDir 'mods/extra.jar'),'extra'); Expect-Refusal $set 'unexpected enabled package: extra.jar'
    $set=New-Fixture (Join-Path $rootBase 'missing'); $set.ExpectedPackages['missing-plugin.jar']=('A'*64); Expect-Refusal $set 'missing required package: missing-plugin.jar'
    $set=New-Fixture (Join-Path $rootBase 'hash'); [IO.File]::WriteAllText((Join-Path $set.GameDir 'mods/numen-plugin-camera-1.21.1-0.1.3-dev.jar'),'tampered'); Expect-Refusal $set 'package hash mismatch: numen-plugin-camera-1.21.1-0.1.3-dev.jar'
    $set=New-Fixture (Join-Path $rootBase 'oldcore') -SkipOldCore; Expect-Refusal $set 'pre-install core \(original API\) not preserved in disabled'
    $set=New-Fixture (Join-Path $rootBase 'noapi') -NoApiEntry; Expect-Refusal $set 'core is missing its packaged API entry'
    $set=New-Fixture (Join-Path $rootBase 'digest'); $set.ModsSha=('0'*64); Expect-Refusal $set 'installed JAR set differs'

    # Wiring pin: the exact 053 constants and the STOPPED state must still be in the entry/policy.
    $launch=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../launch-mc.ps1') -Raw -Encoding UTF8
    $policyText=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../bounded-live-launch-policy.ps1') -Raw -Encoding UTF8
    foreach($needle in @(
        '053-overnight-launch','3f3be4e1e84e378e5ce0d5e20f8ba84ac95a17bc',
        'd11a9a5870dd6cf7a0bb6782c761e2b5aba018e0e563b60acc62650a37c1016a',
        '-State $state')){
        if(-not $launch.Contains($needle)){ throw "launch entry lost: $needle" }
    }
    foreach($needle in @(
        'F65B775B6E1DD2F5D8AA67C524CD5312DF00981A85E904C586DE41C17AAD708E',
        '3EF328E25F6E3314B16861D7D6B2148D8DC99939C4D904F488320CD88AF25740',
        '308215FAE9FD7038FB52D2AEA15EEA33794DE89C7B966AECD5E1AA4F24CCEE58',
        'CE76DB2C99CC418E9C85794EFB57A51E0CA6BE7CF9B861E4DDFB5A3D84EFA2E8',
        '6C605D652A70C7A61779FE20021842763AC937D2379B49EC771418F67C1F79FB')){
        if(-not $policyText.Contains($needle)){ throw "launch policy lost: $needle" }
    }
    Write-Output 'PASS launch entry pins 053 mode, candidate commit, digest, STOPPED input and five SHAs'
}finally{
    if(Test-Path -LiteralPath $rootBase){
        $resolved=(Resolve-Path -LiteralPath $rootBase).ProviderPath
        $temp=(Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath.TrimEnd('\','/')
        if((Split-Path -Parent $resolved) -ine $temp -or (Split-Path -Leaf $resolved) -notmatch '^rdd-053-launch-[a-f0-9]{32}$'){ throw "Unexpected fixture path: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Output 'PASS 053 overnight launch policy fixtures (offline only)'
exit 0
