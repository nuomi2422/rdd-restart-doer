# 2026-11-18: bounded-live identity regressions. No game process is started.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../deploy-test-policy.ps1"
. "$PSScriptRoot/../bounded-live-launch-policy.ps1"

$root = Join-Path ([IO.Path]::GetTempPath()) ('rdd-launch-policy-' + [guid]::NewGuid().ToString('N'))
$save = Join-Path $root 'saves/live'
$mods = Join-Path $root 'mods'
$shaderpacks = Join-Path $root 'shaderpacks'
$batch = Join-Path $shaderpacks 'launch-live.bat'
$jar = Join-Path $mods 'example.jar'
$level = Join-Path $save 'level.dat'
$fixture = 'approved fixture'
$set = @{
    Instance = 'gpt'; GameDir = $root; Save = 'live'; LevelOverride = ''; Batch = $batch
    ExpectedRoot = $root; BatchSha = '215f39884604154ce56a91209f5e8e00337a2799bc7168a29c148eb3f41af913'; ModsSha = 'c4f2df8fc438acc49063c2a42f8e3dd274fc830200211cd5451cb0ff08e8e65b'
}

function Assert-Refusal([string]$Reason) {
    $caught = $null
    try { Assert-RddBoundedLiveLaunch @set } catch { $caught = $_ }
    if (-not $caught -or $caught.Exception.Message -notmatch $Reason) {
        throw "Expected a launch refusal matching '$Reason'; got: $caught"
    }
    Write-Output "BLOCK $Reason"
}

try {
    foreach ($dir in @($save, $mods, $shaderpacks)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    foreach ($file in @($batch, $jar, $level)) { [IO.File]::WriteAllText($file, $fixture) }
    [IO.File]::WriteAllText((Join-Path $mods 'offline-jar.jar.off'), 'disabled')
    Assert-RddBoundedLiveLaunch @set
    Write-Output 'PASS approved package, gpt instance and live save'

    [IO.File]::WriteAllText($jar, 'different bytes under the same name')
    Assert-Refusal 'installed JAR set differs'
    [IO.File]::WriteAllText($jar, $fixture)
    $extra = Join-Path $mods 'extra.jar'
    [IO.File]::WriteAllText($extra, $fixture)
    Assert-Refusal 'installed JAR set differs'
    Remove-Item -LiteralPath $extra

    $set.GameDir = $mods
    Assert-Refusal 'instance mismatch'
    $set.GameDir = $root
    $set.LevelOverride = 'other-world'
    Assert-Refusal 'save mismatch'
    $set.LevelOverride = ''
    $set.Save = 'other-world'
    Assert-Refusal 'save mismatch'
    $set.Save = 'live'
    [IO.File]::WriteAllText($level, '')
    Assert-Refusal 'level.dat is missing or empty'
    [IO.File]::WriteAllText($level, $fixture)
    [IO.File]::WriteAllText($batch, 'wrapper points at another instance or save')
    Assert-Refusal 'launch batch checksum mismatch'
} finally {
    if (Test-Path -LiteralPath $root) {
        $resolved = (Resolve-Path -LiteralPath $root).ProviderPath
        $temp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath.TrimEnd('\','/')
        if ((Split-Path -Parent $resolved) -ine $temp -or (Split-Path -Leaf $resolved) -notmatch '^rdd-launch-policy-[a-f0-9]{32}$') {
            throw "Unexpected fixture path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
