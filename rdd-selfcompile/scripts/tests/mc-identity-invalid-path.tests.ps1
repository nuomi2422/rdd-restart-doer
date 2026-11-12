# mc-identity-invalid-path.tests.ps1 -- synthetic exception-boundary regression.
# WHY (2026-11-13): Path.IsPathRooted can throw before the canonicaliser's catch.
# Run: powershell -NoProfile -File ./rdd-selfcompile/scripts/tests/mc-identity-invalid-path.tests.ps1
# ASCII only; no game/process queries. Dot-source definitions, then replace OS boundaries.
# These inputs reproduce a function boundary, not any particular live Java argument.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'mc-instance.ps1')
$script:passed = 0
$script:failed = 0
$script:forbiddenCalls = 0
$script:processCalls = 0
$script:cimCalls = 0
$script:processThrows = $false
$script:cimThrows = $false
$script:fixtureDir = 'D:\fixture\mine'
$script:fixtureAlive = @([pscustomobject]@{ ProcessName='javaw' })
$script:fixtureProcesses = @()
function Check($Name, $Expected, [scriptblock]$Actual) {
    try {
        $value = & $Actual
        if ("$Expected" -eq "$value") { $script:passed++ }
        else {
            $script:failed++
            Write-Output ("FAIL {0} expected=[{1}] actual=[{2}]" -f $Name,$Expected,$value)
        }
    } catch {
        $script:failed++
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.GetType().Name } else { 'none' }
        # Do not print complete commands, arguments, or exception messages.
        Write-Output ("FAIL {0} THREW outer={1} inner={2} line={3}" -f $Name,$_.Exception.GetType().Name,$inner,$_.InvocationInfo.ScriptLineNumber)
    }
}
function Get-RddMcGameDir { param($Instance) return $script:fixtureDir }
function Get-Process {
    param($ErrorAction)
    $script:processCalls++
    if ($script:processThrows) { throw 'fixture process enumeration failed' }
    return $script:fixtureAlive
}
function Get-CimInstance {
    param($ClassName, $Filter, $ErrorAction)
    $script:cimCalls++
    if ($script:cimThrows) { throw 'fixture CIM enumeration failed' }
    return $script:fixtureProcesses
}
function Stop-Process { $script:forbiddenCalls++; throw 'forbidden stop boundary' }
function Start-Sleep { $script:forbiddenCalls++; throw 'forbidden sleep boundary' }
function Invoke-RddExitAudit { $script:forbiddenCalls++; throw 'forbidden audit boundary' }
function Check-State($Name, $Expected, [string[]]$Commands, $Directory = 'D:\fixture\mine') {
    $script:fixtureDir = $Directory
    $script:fixtureProcesses = @($Commands | ForEach-Object { [pscustomobject]@{ CommandLine=$_ } })
    $script:processCalls = 0; $script:cimCalls = 0
    Check "$Name/state" $Expected { Get-RddMcState -Instance fixture }
    Check "$Name/fake-process" 1 { $script:processCalls }
    Check "$Name/fake-CIM" 1 { $script:cimCalls }
}
Write-Output ("ENGINE version={0} edition={1}" -f $PSVersionTable.PSVersion,$PSVersionTable.PSEdition)
$mine = 'D:\fixture\mine'
$valid = 'javaw --gameDir=D:\fixture\mine'
$badPaths = @(
    @{ Name='nul'; Value=('D:\fixture\bad' + [char]0 + 'path') },
    @{ Name='control'; Value=('D:\fixture\bad' + [char]1 + 'path') },
    @{ Name='bad-colon'; Value='D::\fixture\bad' }
)
foreach ($case in $badPaths) {
    $name = $case.Name; $bad = $case.Value
    Check "$name/path-key" $true { $null -eq (ConvertTo-RddMcPathKey $bad) }
    # Both explicit forms, including quoted invalid values, stay UNDECIDABLE.
    $commands = @(('javaw --gameDir=' + $bad), ('javaw --gameDir "' + $bad + '"'))
    Check "$name/explicit-form-count" 2 { $commands.Count }
    foreach ($command in $commands) {
        Check "$name/declared" 'UNDECIDABLE' { Get-RddMcCommandLineMatch $command $mine }
        Check "$name/legacy-wrapper" $false { Test-RddMcCommandLineMatches $command $mine }
        Check-State "$name/declared-only" 'UNKNOWN' @($command)
        Check-State "$name/invalid-before-match" 'RUNNING' @($command,$valid)
        Check-State "$name/match-before-invalid" 'RUNNING' @($valid,$command)
        $duplicate = $command + ' --gameDir=' + $mine
        Check "$name/declared-invalid-before-match" 'MATCH' { Get-RddMcCommandLineMatch $duplicate $mine }
        $duplicate = $valid + ' --gameDir=' + $bad
        Check "$name/declared-match-before-invalid" 'MATCH' { Get-RddMcCommandLineMatch $duplicate $mine }
    }
    Check "$name/invalid-target" 'UNDECIDABLE' { Get-RddMcCommandLineMatch $valid $bad }
    Check-State "$name/invalid-target" 'UNKNOWN' @($valid) $bad
    $ordinary = 'java -jar launcher.jar -Dmisc=' + $bad
    Check "$name/heuristic" 'NO_MATCH' { Get-RddMcCommandLineMatch $ordinary $mine }
    Check-State "$name/ordinary-java" 'STOPPED' @($ordinary)
    $bare = $ordinary + ' ' + $mine
    Check "$name/heuristic-invalid-before-match" 'MATCH' { Get-RddMcCommandLineMatch $bare $mine }
    $bare = 'java ' + $mine + ' -Dmisc=' + $bad
    Check "$name/heuristic-match-before-invalid" 'MATCH' { Get-RddMcCommandLineMatch $bare $mine }
    $bridge = $command + ' -jar soul-core-bridge.jar'
    Check "$name/bridge" 'NO_MATCH' { Get-RddMcCommandLineMatch $bridge $mine }
    Check-State "$name/bridge" 'STOPPED' @($bridge)
}
# Embedded quotes are invalid to the path API, but command-line quotes remain the
# existing splitter's syntax. Do not rewrite the parser to make a new quote grammar.
$quotePath = 'D:\fixture\bad"path'
Check 'embedded-quote/path-key' $true { $null -eq (ConvertTo-RddMcPathKey $quotePath) }
Check 'embedded-quote/target' 'UNDECIDABLE' { Get-RddMcCommandLineMatch $valid $quotePath }
Check-State 'embedded-quote/target' 'UNKNOWN' @($valid) $quotePath
Check 'normal-quoted-key' $mine { ConvertTo-RddMcPathKey ('"' + $mine + '"') }
Check 'normal-quoted-declaration' 'MATCH' { Get-RddMcCommandLineMatch ('java --gameDir "' + $mine + '"') $mine }
Check 'embedded-command-quote-still-splitter-syntax' 'NO_MATCH' { Get-RddMcCommandLineMatch ('java --gameDir=' + $quotePath) $mine }
$relativeJunk = 'misc' + [char]0 + 'token'
Check 'relative-illegal-token/path-key' $true { $null -eq (ConvertTo-RddMcPathKey $relativeJunk) }
Check 'relative-illegal-token/heuristic' 'NO_MATCH' { Get-RddMcCommandLineMatch ('java -jar launcher.jar ' + $relativeJunk) $mine }
Check-State 'relative-illegal-token/ordinary-java' 'STOPPED' @('java -jar launcher.jar ' + $relativeJunk)
Check-State 'valid-target' 'RUNNING' @($valid)
Check-State 'different-instance' 'STOPPED' @('java --gameDir=D:\fixture\other')
Check-State 'prefix-sibling' 'STOPPED' @('java --gameDir=D:\fixture\mine-other')
Check-State 'nested-instance' 'STOPPED' @('java --gameDir=D:\fixture\mine\saves')
Check-State 'missing-command' 'UNKNOWN' @('')
$script:processThrows = $true
Check 'enumeration-failure' 'UNKNOWN' { Get-RddMcState -Instance fixture }
$script:processThrows = $false; $script:cimThrows = $true
Check 'CIM-failure' 'UNKNOWN' { Get-RddMcState -Instance fixture }
$script:cimThrows = $false; $script:fixtureProcesses = @()
Check 'empty-CIM-despite-java' 'UNKNOWN' { Get-RddMcState -Instance fixture }
$script:fixtureAlive = @()
Check 'successful-enumeration-no-java' 'STOPPED' { Get-RddMcState -Instance fixture }
Check 'no-stop-sleep-audit-calls' 0 { $script:forbiddenCalls }
Write-Output ("RESULT passed={0} failed={1} (synthetic only; real identity/state functions, fake OS boundaries)" -f $script:passed,$script:failed)
if ($script:failed -gt 0) { exit 1 }
