# mc-identity.ps1 -- pure, testable process-identity helpers for RDD Minecraft instances.
# 042 R0: the command-line parsing and instance matching used to be inline inside
# Get-RddMcState / Get-RddMcProcess, which used two DIFFERENT algorithms (tokenised
# exact compare vs. -like substring). This module is the single implementation.
#
# ASCII only on purpose: PowerShell 5.1 reads UTF-8-without-BOM as GBK and CJK can
# swallow a newline. See start-rdd.ps1 header.
#
# No side effects: every function here is pure and safe to call in offline tests.

# Deliberately no Set-StrictMode here: this file is dot-sourced by mc-instance.ps1
# and must not change the caller's strict-mode setting.

# Split a Windows command line into tokens, honouring double quotes.
# Quotes are removed; a quoted run may contain spaces.
function Split-RddMcCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }

    $tokens = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQuotes = $false

    foreach ($ch in $CommandLine.ToCharArray()) {
        if ($ch -eq [char]'"') { $inQuotes = -not $inQuotes; continue }
        if (-not $inQuotes -and [char]::IsWhiteSpace($ch)) {
            if ($sb.Length -gt 0) {
                [void]$tokens.Add($sb.ToString())
                [void]$sb.Clear()
            }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($sb.Length -gt 0) { [void]$tokens.Add($sb.ToString()) }

    return $tokens.ToArray()
}

# Canonical form for comparison: absolute, forward/back slashes unified, no trailing sep.
# Returns $null when the value cannot be canonicalised (caller must treat that as "no match").
function ConvertTo-RddMcPathKey {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim().Trim([char]'"')
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($p)) { return $null }

    try {
        $full = [System.IO.Path]::GetFullPath($p)
    } catch {
        return $null
    }
    $full = $full -replace '/', '\'
    # Guard the drive root: TrimEnd on "D:\" would yield "D:" (drive-relative, different meaning).
    if ($full.Length -gt 3) { $full = $full.TrimEnd([char]'\') }
    return $full
}

# Values explicitly declared as the game directory: --gameDir <value> and --gameDir=<value>.
function Get-RddMcDeclaredGameDir {
    param([string]$CommandLine)

    $tokens = @(Split-RddMcCommandLine $CommandLine)
    $out = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -match '^--gameDir=(.+)$') { [void]$out.Add($Matches[1]); continue }
        if ($t -ieq '--gameDir' -and ($i + 1) -lt $tokens.Count) { [void]$out.Add($tokens[$i + 1]); continue }
    }
    return $out.ToArray()
}

# Three-state identity: MATCH / NO_MATCH / UNDECIDABLE.
#
# Why three and not a boolean (042 R0): "declared a --gameDir but I cannot resolve it"
# is NOT the same as "this is a different instance". Collapsing the first into NO_MATCH
# turns an unverifiable process into STOPPED, which is exactly what R0 forbids.
#   - an explicit --gameDir is authoritative: resolvable and equal -> MATCH;
#     resolvable and different -> NO_MATCH; unresolvable -> UNDECIDABLE;
#   - with no --gameDir, any token may be the dir (heuristic); unresolvable tokens are
#     skipped here on purpose -- treating every relative token as UNDECIDABLE would make
#     STOPPED unreachable for ordinary java processes;
#   - the companion bridge is not the game.
function Get-RddMcCommandLineMatch {
    param(
        [string]$CommandLine,
        [string]$GameDir
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return 'UNDECIDABLE' }
    if ([string]::IsNullOrWhiteSpace($GameDir)) { return 'UNDECIDABLE' }

    # The soul-core-bridge process carries the save dir in its command line but is not the game.
    if ($CommandLine -like '*soul-core-bridge*') { return 'NO_MATCH' }

    $target = ConvertTo-RddMcPathKey $GameDir
    if ($null -eq $target) { return 'UNDECIDABLE' }

    $declared = @(Get-RddMcDeclaredGameDir $CommandLine)
    if ($declared.Count -gt 0) {
        $sawUnresolvable = $false
        foreach ($c in $declared) {
            $key = ConvertTo-RddMcPathKey $c
            if ($null -eq $key) { $sawUnresolvable = $true; continue }
            if ([string]::Equals($key, $target, [System.StringComparison]::OrdinalIgnoreCase)) { return 'MATCH' }
        }
        if ($sawUnresolvable) { return 'UNDECIDABLE' }
        return 'NO_MATCH'
    }

    foreach ($c in @(Split-RddMcCommandLine $CommandLine)) {
        $key = ConvertTo-RddMcPathKey $c
        if ($null -eq $key) { continue }
        if ([string]::Equals($key, $target, [System.StringComparison]::OrdinalIgnoreCase)) { return 'MATCH' }
    }
    return 'NO_MATCH'
}

# LEGACY ONLY: folds UNDECIDABLE into false, which is exactly the bug this module exists
# to prevent. New call sites must use Get-RddMcCommandLineMatch and handle the third state.
function Test-RddMcCommandLineMatches {
    param(
        [string]$CommandLine,
        [string]$GameDir
    )
    return ((Get-RddMcCommandLineMatch $CommandLine $GameDir) -eq 'MATCH')
}

# Pure state decision over per-process match results (042 R0).
#   any MATCH       -> RUNNING   (a decided match beats an undecidable sibling)
#   any UNDECIDABLE -> UNKNOWN   (we cannot rule the target out)
#   otherwise       -> STOPPED
# 042 R0: an EMPTY list is not evidence of absence. A caller that legitimately has no
# java process must reach STOPPED from its own successful full enumeration and never by
# handing this function an empty array -- otherwise a failed enumeration that yields []
# silently becomes "not running" (peer review 2026-11-05, B.2.1).
function Get-RddMcStateFromMatches {
    param([string[]]$Matches)

    if ($null -eq $Matches -or $Matches.Count -eq 0) { return 'UNKNOWN' }
    foreach ($m in $Matches) { if ($m -eq 'MATCH') { return 'RUNNING' } }
    foreach ($m in $Matches) { if ($m -eq 'UNDECIDABLE') { return 'UNKNOWN' } }
    return 'STOPPED'
}

# Is a process of this name a possible Minecraft client? (identity is decided later)
function Test-RddMcProcessName {
    param([string]$ProcessName)

    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    $n = $ProcessName.Trim()
    if ($n.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        $n = $n.Substring(0, $n.Length - 4)
    }
    return ($n -ieq 'java' -or $n -ieq 'javaw')
}
