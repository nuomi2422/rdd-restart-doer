# verify-install.ps1 -- prove that what is IN mods matches what you just BUILT, for the right source.
#
# Why (2026-11-05, twice in one night):
#   1) mods/numen-plugin-worldstate.jar was 06:03 while Readiness.class appeared 07:20+ -> the jar
#      simply did not contain the new classes.
#   2) a rebuilt rdd jar (08:12:11) was copied in, but the fixes were committed at 08:15:01 ->
#      the smoke test ran the OLD code and we called it green.
# "installed, ran, logged, green" does NOT imply "the new build is what ran".
#
# Three hard checks (about 10 seconds):
#   A. sha256(installed) == sha256(built)
#   B. built jar mtime > target commit time        (catches "built before the fix")
#   C. required .class entries exist in the installed jar (catches "jar lacks the class")
#
# ASCII only on purpose: PowerShell 5.1 reads UTF-8-without-BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts\verify-install.ps1 `
#       -Installed "D:\rdd\mc\...\mods\numen-plugin-rdd-....jar" `
#       -Built     "D:\rdd\workspace\minecraft-numen\plugins\rdd\build\libs\numen-plugin-rdd-....jar" `
#       -Commit "380d4f744" `
#       -Required "ContainerChangePoller.class,RddCondition.class"
# Exit codes: 0 = all good, 2 = hash mismatch, 3 = stale build (built before commit), 4 = missing class, 5 = file missing.

param(
    [Parameter(Mandatory = $true)][string]$Installed,
    [Parameter(Mandatory = $true)][string]$Built,
    [string]$Commit = '',
    [string]$Required = '',
    [string]$Repo = 'D:/rdd/workspace/minecraft-numen'
)

$ErrorActionPreference = 'Stop'

foreach ($p in @($Installed, $Built)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Write-Output ("VERIFY_INSTALL: file not found: " + $p)
        exit 5
    }
}

$hIn = (Get-FileHash -LiteralPath $Installed -Algorithm SHA256).Hash
$hB  = (Get-FileHash -LiteralPath $Built -Algorithm SHA256).Hash
$tIn = (Get-Item -LiteralPath $Installed).LastWriteTime
$tB  = (Get-Item -LiteralPath $Built).LastWriteTime
Write-Output ("VERIFY_INSTALL: installed sha256=" + $hIn.Substring(0, 16) + " mtime=" + $tIn.ToString('HH:mm:ss') + " size=" + (Get-Item $Installed).Length)
Write-Output ("VERIFY_INSTALL: built     sha256=" + $hB.Substring(0, 16) + " mtime=" + $tB.ToString('HH:mm:ss') + " size=" + (Get-Item $Built).Length)

if ($hIn -ne $hB) {
    Write-Output "VERIFY_INSTALL: FAIL hash differs - the installed jar is NOT the one you built"
    exit 2
}
Write-Output "VERIFY_INSTALL: hash OK"

if (-not [string]::IsNullOrWhiteSpace($Commit)) {
    Push-Location $Repo
    try {
        $raw = & git show -s --format=%ct $Commit 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
            Write-Output ("VERIFY_INSTALL: FAIL cannot resolve commit " + $Commit)
            exit 3
        }
        $commitTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$raw).LocalDateTime
        Write-Output ("VERIFY_INSTALL: commit " + $Commit + " time=" + $commitTime.ToString('HH:mm:ss'))
        if ($tB -lt $commitTime) {
            Write-Output ("VERIFY_INSTALL: FAIL built jar (" + $tB.ToString('HH:mm:ss') + ") is OLDER than commit (" + $commitTime.ToString('HH:mm:ss') + ") - rebuild before installing")
            exit 3
        }
        Write-Output "VERIFY_INSTALL: build is newer than commit OK"
    } finally {
        Pop-Location
    }
}

if (-not [string]::IsNullOrWhiteSpace($Required)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Installed).Path)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
        $wanted = @()
        foreach ($r in ($Required -split ',')) { if ($r.Trim().Length -gt 0) { $wanted += $r.Trim() } }
        $missing = @()
        foreach ($w in $wanted) {
            $hit = @($entries | Where-Object { $_.EndsWith($w, [System.StringComparison]::Ordinal) })
            if ($hit.Count -eq 0) { $missing += $w }
            else { Write-Output ("VERIFY_INSTALL: found " + $hit[0]) }
        }
        if ($missing.Count -gt 0) {
            foreach ($m in $missing) { Write-Output ("VERIFY_INSTALL: FAIL missing class " + $m) }
            exit 4
        }
    } finally {
        $zip.Dispose()
    }
    Write-Output "VERIFY_INSTALL: required classes OK"
}

Write-Output "VERIFY_INSTALL: ALL OK"
exit 0
