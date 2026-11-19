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

# 2026-11-19: launch guard for frozen combo 3f3be4e1 (five installed artifacts plus the
# unchanged kept set). Strict per-package SHA, no separate enabled API, old core preserved.
function Assert-RddOvernightLaunch {
    param(
        [string]$Instance, [string]$GameDir, [string]$Save, [string]$LevelOverride, [string]$Batch,
        [string]$ExpectedRoot, [string]$BatchSha, [string]$ModsSha, [string]$State,
        [hashtable]$ExpectedPackages = $null, [switch]$SleepRetry
    )
    if ($SleepRetry -and $null -ne $ExpectedPackages) { throw 'sleep retry package override refused' }
    if (-not $ExpectedPackages) {
        $ExpectedPackages = @{
            'numen-neoforge-1.21.1-0.1.3-dev.jar' = 'F65B775B6E1DD2F5D8AA67C524CD5312DF00981A85E904C586DE41C17AAD708E'
            'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' = '3EF328E25F6E3314B16861D7D6B2148D8DC99939C4D904F488320CD88AF25740'
            'numen-plugin-acx-1.21.1-0.1.3-dev.jar' = '308215FAE9FD7038FB52D2AEA15EEA33794DE89C7B966AECD5E1AA4F24CCEE58'
            'numen-plugin-learner-1.21.1-0.1.3-dev.jar' = 'CE76DB2C99CC418E9C85794EFB57A51E0CA6BE7CF9B861E4DDFB5A3D84EFA2E8'
            'numen-plugin-worldstate-1.21.1-0.1.3-dev.jar' = '6C605D652A70C7A61779FE20021842763AC937D2379B49EC771418F67C1F79FB'
            'numen-plugin-camera-1.21.1-0.1.3-dev.jar' = '1BBCF6E88F2866E1D117C04AC758DFF952A61E6F24E00ACC2F81BC93596F3FD8'
            'numen-plugin-experience-1.21.1-0.1.3-dev.jar' = 'BD66DFDB53A0702B6884093A36AB0D0D10A005EFF6741C7A7915ED3EB949D7A5'
            'numen-plugin-selfcompile-1.21.1-0.1.3-dev.jar' = '9D44F06BE8C0E7F6A1629180565B0C4A02442185E38D54146097CC877A25D553'
            'numen-plugin-settlement-1.21.1-0.1.3-dev.jar' = '08A428EE3CBF838AD619A52AD0EB617B65C2EC27E1DC03F66CBDD8114F60A998'
            'minecraft-client-controller-neoforge-1.0.0.jar' = 'D5F1857206AC75678B1E2C3A95AE4DC518F4C1B1B48D7D4A9A8022E1EF70A260'
        }
    }
    if ($SleepRetry) {
        $ExpectedPackages['numen-plugin-rdd-1.21.1-0.1.3-dev.jar'] = '80B66639FF83E7FB289136E6B8F5A088CC0558DABADF2720490D0590AF4769A6'
    }
    if ($State -cne 'STOPPED') { throw "instance state is $State; launch requires STOPPED" }
    if ($Instance -cne 'gpt' -or [IO.Path]::GetFullPath($GameDir) -ine [IO.Path]::GetFullPath($ExpectedRoot)) {
        throw 'instance mismatch: expected original gpt game directory'
    }
    Assert-RddOrdinaryPath $GameDir
    if ($Save -cne 'live' -or ($LevelOverride -and $LevelOverride -cne $Save)) { throw 'save mismatch: expected live' }
    $levelDat = Join-Path $GameDir 'saves/live/level.dat'
    Assert-RddOrdinaryPath $levelDat
    $level = Get-Item -LiteralPath $levelDat -ErrorAction Stop
    if ($level.PSIsContainer -or $level.Length -le 0) { throw 'live save level.dat is missing or empty' }
    if ([IO.Path]::GetFullPath($Batch) -ine [IO.Path]::GetFullPath((Join-Path $GameDir 'shaderpacks/launch-live.bat'))) {
        throw 'launch batch path mismatch'
    }
    Assert-RddOrdinaryPath $Batch
    if ((Get-FileHash -LiteralPath $Batch -Algorithm SHA256 -ErrorAction Stop).Hash -ine $BatchSha) {
        throw 'launch batch checksum mismatch'
    }
    $mods = Join-Path $GameDir 'mods'
    Assert-RddOrdinaryPath $mods
    $jarHashes = @{}
    foreach ($jar in (Get-ChildItem -LiteralPath $mods -File -Force -ErrorAction Stop)) {
        if ($jar.Extension -ine '.jar') { continue }
        Assert-RddOrdinaryPath $jar.FullName
        if ($jar.Name.ToLowerInvariant().StartsWith('numen_api')) { throw 'separate API jar must stay disabled' }
        $jarHashes.Add($jar.Name.ToLowerInvariant(), (Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant())
    }
    foreach ($expected in $ExpectedPackages.Keys) {
        $expectedName = $expected.ToLowerInvariant()
        if (-not $jarHashes.ContainsKey($expectedName)) { throw "missing required package: $expected" }
        if ($jarHashes[$expectedName] -ine $ExpectedPackages[$expected]) { throw "package hash mismatch: $expected" }
    }
    foreach ($actualName in $jarHashes.Keys) {
        if (-not $ExpectedPackages.ContainsKey($actualName)) { throw "unexpected enabled package: $actualName" }
    }
    $names = @($jarHashes.Keys | ForEach-Object { $_.ToLowerInvariant() })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $rows = @($names | ForEach-Object { $_ + '=' + $jarHashes[$_].ToLowerInvariant() })
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join ([char]10)))
        $actual = [BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
    } finally { $sha256.Dispose() }
    if ($actual -ine $ModsSha) { throw 'installed JAR set differs from the approved deployment' }

    # The pre-install core (and its packaged API) must be preserved under disabled by the install.
    $oldCore = '644977E1F8E487719EBC660EA050037CEA52971BCAF6B6BE9C26194B091CCFB1'
    $preserved = $false
    $disabled = Join-Path $GameDir 'disabled'
    if (Test-Path -LiteralPath $disabled) {
        foreach ($file in (Get-ChildItem -LiteralPath $disabled -Recurse -File -Filter 'numen-neoforge-*.jar' -ErrorAction Stop)) {
            if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ieq $oldCore) { $preserved = $true; break }
        }
    }
    if (-not $preserved) { throw 'pre-install core (original API) not preserved in disabled' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $corePath = Join-Path $mods 'numen-neoforge-1.21.1-0.1.3-dev.jar'
    $zip = [IO.Compression.ZipFile]::OpenRead($corePath)
    try {
        $entryName = 'META-INF/jarjar/com.dwinovo.numen.api.numen_api-neoforge-1.21.1-0.1.3-dev.jar'
        if ($null -eq $zip.GetEntry($entryName)) { throw 'core is missing its packaged API entry' }
    } finally { $zip.Dispose() }
}
