# mc-identity.tests.ps1 -- offline counterexamples for 042 R0 (no game, no WMI, no processes).
# ASCII only. Run: powershell -NoProfile -File scripts\tests\mc-identity.tests.ps1
# Exit code 0 = all green, 1 = at least one failure.

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'mc-identity.ps1')

$script:pass = 0
$script:fail = 0

function Check {
    param([string]$Name, $Expected, $Actual)
    if ("$Expected" -eq "$Actual") {
        $script:pass++
    } else {
        $script:fail++
        Write-Output ("FAIL  " + $Name)
        Write-Output ("        expected: " + $Expected)
        Write-Output ("        actual:   " + $Actual)
    }
}

$gpt  = 'D:\rdd\mc\The Best of Twilight Forest'
$test = 'D:\rdd\workspace\rdd-selfcompile\instances\test'

# --- 1. plain, no spaces in dir ---
Check 'plain --gameDir value' $true (Test-RddMcCommandLineMatches "--gameDir $test --level live" $test)

# --- 2. --gameDir=value with spaces, quoted ---
Check 'quoted --gameDir= with spaces' $true (Test-RddMcCommandLineMatches ('"--gameDir=' + $gpt + '" --level live') $gpt)

# --- 3. --gameDir value with spaces, quoted value ---
Check 'quoted value after --gameDir' $true (Test-RddMcCommandLineMatches ('--gameDir "' + $gpt + '"') $gpt)

# --- 4. forward slashes ---
Check 'forward slashes' $true (Test-RddMcCommandLineMatches ('"--gameDir=D:/rdd/mc/The Best of Twilight Forest"') $gpt)

# --- 5. trailing backslash on the declared value ---
Check 'trailing backslash' $true (Test-RddMcCommandLineMatches ('"--gameDir=' + $gpt + '\"') $gpt)

# --- 6. case insensitive ---
Check 'case insensitive' $true (Test-RddMcCommandLineMatches ('"--gameDir=' + $gpt.ToUpper() + '"') $gpt)

# --- 7. same prefix, different dir: must NOT match ---
Check 'prefix sibling is not a match' $false (Test-RddMcCommandLineMatches ('"--gameDir=' + $gpt + '-test"') $gpt)

# --- 8. substring inside a longer path: must NOT match ---
Check 'nested subdir is not a match' $false (Test-RddMcCommandLineMatches ('--gameDir=' + $gpt + '\saves\live') $gpt)

# --- 9. bridge process is not the game ---
Check 'bridge excluded' $false (Test-RddMcCommandLineMatches ('"--gameDir=' + $gpt + '" -jar soul-core-bridge.jar') $gpt)

# --- 9b. unquoted path with spaces cannot be matched (the OS splits it too) ---
Check 'unquoted spaces do not match' $false (Test-RddMcCommandLineMatches ('--gameDir=' + $gpt) $gpt)

# --- 10. no --gameDir declared, bare path token still matches ---
Check 'bare path token' $true (Test-RddMcCommandLineMatches ('java -jar x.jar "' + $gpt + '" --level live') $gpt)

# --- 11. jar path only, different dir ---
Check 'unrelated jar path' $false (Test-RddMcCommandLineMatches 'java -jar D:\other\launcher.jar --level live' $gpt)

# --- 12. empty / null command line ---
Check 'empty command line' $false (Test-RddMcCommandLineMatches '' $gpt)
Check 'null command line' $false (Test-RddMcCommandLineMatches $null $gpt)

# --- 13. a declared but unresolvable --gameDir is UNDECIDABLE, not NO_MATCH ---
# (peer review 2026-11-05: "declared but cannot resolve" and "different instance" are
#  two different things; collapsing them turns an unverifiable process into STOPPED)
Check 'declared relative -> undecidable' 'UNDECIDABLE' (Get-RddMcCommandLineMatch '--gameDir=instances\test' $test)
# the boolean wrapper is legacy and folds UNDECIDABLE into false -- kept only as a compat check
Check 'legacy wrapper folds undecidable to false' $false (Test-RddMcCommandLineMatches '--gameDir=instances\test' $test)
Check 'declared other dir -> no match' 'NO_MATCH' (Get-RddMcCommandLineMatch ('--gameDir=' + $test) $gpt)
Check 'declared same dir -> match' 'MATCH' (Get-RddMcCommandLineMatch ('--gameDir=' + $test) $test)
Check 'empty command line -> undecidable' 'UNDECIDABLE' (Get-RddMcCommandLineMatch '' $gpt)
Check 'bridge -> no match, not undecidable' 'NO_MATCH' (Get-RddMcCommandLineMatch ('--gameDir=' + $gpt + ' -jar soul-core-bridge.jar') $gpt)

# --- 13b. no --gameDir declared: relative tokens are skipped, not undecidable ---
# (otherwise every ordinary java process would read UNDECIDABLE and STOPPED would never happen)
Check 'heuristic skips relative tokens' 'NO_MATCH' (Get-RddMcCommandLineMatch 'java -jar launcher.jar --level live' $gpt)

# --- 13c. state decision over per-process results ---
Check 'state: match wins' 'RUNNING' (Get-RddMcStateFromMatches @('NO_MATCH','MATCH','UNDECIDABLE'))
Check 'state: undecidable alone is unknown' 'UNKNOWN' (Get-RddMcStateFromMatches @('NO_MATCH','UNDECIDABLE'))
Check 'state: all no-match is stopped' 'STOPPED' (Get-RddMcStateFromMatches @('NO_MATCH','NO_MATCH'))
# empty input is NOT evidence of absence (peer review B.2.1)
Check 'state: empty is unknown' 'UNKNOWN' (Get-RddMcStateFromMatches @())
Check 'state: null is unknown' 'UNKNOWN' (Get-RddMcStateFromMatches $null)

# --- 13d. drive root keeps its separator (peer review B.2.4) ---
Check 'drive root not trimmed to D:' 'D:\' (ConvertTo-RddMcPathKey 'D:\')
Check 'normal dir still trimmed' 'D:\a' (ConvertTo-RddMcPathKey 'D:\a\')

# --- 14. other instance declared ---
Check 'other instance declared' $false (Test-RddMcCommandLineMatches ('--gameDir ' + $test) $gpt)

# --- 15. splitter keeps quoted spaces together ---
$t = @(Split-RddMcCommandLine '--gameDir "D:\a b\c" --level live')
Check 'splitter token count' 4 $t.Count
Check 'splitter quoted token' 'D:\a b\c' $t[1]

# --- 16. declared-dir extraction ---
$d = @(Get-RddMcDeclaredGameDir '--gameDir=D:\x --gameDir D:\y')
Check 'declared dir count' 2 $d.Count
Check 'declared dir first' 'D:\x' $d[0]

# --- 17. process name helper ---
Check 'javaw.exe is java' $true (Test-RddMcProcessName 'javaw.exe')
Check 'java is java' $true (Test-RddMcProcessName 'java')
Check 'node is not java' $false (Test-RddMcProcessName 'node')

Write-Output ''
Write-Output ("passed=" + $script:pass + " failed=" + $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }