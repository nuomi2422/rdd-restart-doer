# verify-jar.ps1 -- confirm a deployed jar actually CONTAINS the classes you think it does.
#
# Why (2026-11-05): mods/numen-plugin-worldstate...jar was built at 06:03, but Readiness.class
# and ObservableStoreV2.class only appeared at 07:20+. DEPLOY_OK only says "the copy succeeded",
# not "the copy is the right thing". Same family as RefreshResult=SUCCESS while put() silently
# rejected the write (D-017).
#
# ASCII only on purpose: PowerShell 5.1 reads UTF-8-without-BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts\verify-jar.ps1 -Jar <path> -Required Readiness.class,ObservableStoreV2.class
# Exit codes: 0 = all present, 2 = missing entries, 3 = jar not found / unreadable.

param(
    [Parameter(Mandatory = $true)][string]$Jar,
    [string[]]$Required = @(),
    [switch]$List
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Jar -PathType Leaf)) {
    Write-Output ("VERIFY_JAR: jar not found: " + $Jar)
    exit 3
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Jar).Path)
} catch {
    Write-Output ("VERIFY_JAR: cannot open jar: " + $_.Exception.Message)
    exit 3
}

try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName })

    if ($List) {
        foreach ($e in $entries) { Write-Output $e }
    }

    # -File passes "a,b" as ONE string, so split on commas here (same reason we do not rely on
    # the caller's quoting).
    $wanted = @()
    foreach ($r in $Required) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        foreach ($part in ($r -split ',')) {
            $t = $part.Trim()
            if ($t.Length -gt 0) { $wanted += $t }
        }
    }

    $missing = @()
    foreach ($r in $wanted) {
        $hit = @($entries | Where-Object { $_.EndsWith($r, [System.StringComparison]::Ordinal) })
        if ($hit.Count -eq 0) { $missing += $r }
    }

    Write-Output ("VERIFY_JAR: jar=" + (Split-Path -Leaf $Jar))
    Write-Output ("VERIFY_JAR: entries=" + $entries.Count + " required=" + $wanted.Count + " missing=" + $missing.Count)
    if ($missing.Count -gt 0) {
        foreach ($m in $missing) { Write-Output ("VERIFY_JAR: MISSING " + $m) }
        exit 2
    }
    Write-Output "VERIFY_JAR: OK"
    exit 0
} finally {
    $zip.Dispose()
}
