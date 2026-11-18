# 2026-11-18: Check the actual bounded-live launch inputs against the approved deployment.
function Assert-RddBoundedLiveLaunch {
    param(
        [string]$Instance, [string]$GameDir, [string]$Save, [string]$LevelOverride, [string]$Batch,
        [string]$ExpectedRoot, [string]$BatchSha, [string]$ModsSha
    )

    if ($Instance -cne 'gpt' -or [IO.Path]::GetFullPath($GameDir) -ine [IO.Path]::GetFullPath($ExpectedRoot)) {
        throw 'instance mismatch: expected original gpt game directory'
    }
    Assert-RddOrdinaryPath $GameDir
    if ($Save -cne 'live' -or ($LevelOverride -and $LevelOverride -cne $Save)) {
        throw 'save mismatch: expected live'
    }
    $levelDat = Join-Path $GameDir 'saves/live/level.dat'
    Assert-RddOrdinaryPath $levelDat
    $level = Get-Item -LiteralPath $levelDat -ErrorAction Stop
    if ($level.PSIsContainer -or $level.Length -le 0) { throw 'live save level.dat is missing or empty' }

    # The checked batch passes the original root and the validated RDD_LEVEL to mc-launch.mjs.
    if ([IO.Path]::GetFullPath($Batch) -ine [IO.Path]::GetFullPath((Join-Path $GameDir 'shaderpacks/launch-live.bat'))) {
        throw 'launch batch path mismatch'
    }
    Assert-RddOrdinaryPath $Batch
    if ((Get-FileHash -LiteralPath $Batch -Algorithm SHA256 -ErrorAction Stop).Hash -ine $BatchSha) {
        throw 'launch batch checksum mismatch'
    }

    # Hash all enabled top-level JARs, including third-party dependencies. Compare bytes,
    # names and set membership; a timestamp or Git HEAD cannot prove any of those.
    $mods = Join-Path $GameDir 'mods'
    Assert-RddOrdinaryPath $mods
    $jarHashes = @{}
    foreach ($jar in (Get-ChildItem -LiteralPath $mods -File -Force -ErrorAction Stop)) {
        if ($jar.Extension -ine '.jar') { continue }
        Assert-RddOrdinaryPath $jar.FullName
        $jarHashes.Add($jar.Name.ToLowerInvariant(), (Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant())
    }
    [string[]]$names = @($jarHashes.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $rows = @($names | ForEach-Object { $_ + '=' + $jarHashes[$_] })
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join ([char]10)))
        $actual = [BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
    } finally { $sha256.Dispose() }
    if ($actual -ine $ModsSha) { throw 'installed JAR set differs from the approved deployment' }
}
