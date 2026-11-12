# Offline consumer regression: actual Stop-RddMcInstance, all OS boundaries replaced.
# 2026-11-13: a close request is not a save receipt; graceful-only must never force.
# Run: powershell -NoProfile -File ./rdd-selfcompile/scripts/tests/mc-graceful-stop.tests.ps1
# Dot-sourcing production only defines functions; no live CIM, processes, windows or audit.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'mc-instance.ps1')
$script:passed = 0
$script:failed = 0
$script:birth = [datetime]'2026-11-12T12:00:00Z'
function Check($Name, $Expected, $Actual) {
    if ("$Expected" -eq "$Actual") { $script:passed++ }
    else { $script:failed++; Write-Output "FAIL $Name expected=[$Expected] actual=[$Actual]" }
}
function Get-RddMcGameDir {
    param($Instance)
    if ($script:scenario -eq 'directory-drift' -and $script:cimCalls -ge 1) { return 'D:/fixture/other' }
    return 'D:/fixture/mine'
}
function Get-RddMcState {
    param($Instance)
    $script:stateCalls++
    if ($script:scenario -eq 'state-throw') { throw 'fixture state query failed' }
    if ($script:scenario -eq 'unknown') { return 'UNKNOWN' }
    if ($script:scenario -eq 'already-stopped') { return 'STOPPED' }
    if ($script:scenario -eq 'stopped-before-request' -and $script:stateCalls -ge 2) { return 'STOPPED' }
    if ($script:forceCalls -gt 0) { return 'STOPPED' }
    if ($script:closeCalls -gt 0) {
        if ($script:scenario -in @('success','stop-not-exited','dispose-throw','close-false-stopped')) { return 'STOPPED' }
        if ($script:scenario -eq 'unknown-with-exit') { return 'UNKNOWN' }
        if ($script:scenario -eq 'unknown-after') { return 'UNKNOWN' }
    }
    return 'RUNNING'
}
function New-FakeIdentity($ProcessId = 42) {
    return [pscustomobject]@{
        ProcessId = $ProcessId; CreationDate = $script:birth; Name = 'javaw.exe'
        CommandLine = 'javaw --gameDir=D:/fixture/mine'
    }
}
function Get-RddMcProcess {
    param($Instance)
    $script:cimCalls++
    if ($script:scenario -eq 'query-throw') { throw 'fixture identity query failed' }
    if ($script:scenario -eq 'empty') { return @() }
    $p = New-FakeIdentity
    if ($script:scenario -eq 'other-instance') { $p.CommandLine = 'javaw --gameDir=D:/fixture/other' }
    if ($script:scenario -eq 'bridge') { $p.CommandLine += ' -jar soul-core-bridge.jar' }
    if ($script:scenario -eq 'missing-birth') { $p.CreationDate = $null }
    if ($script:scenario -eq 'wrong-name') { $p.Name = 'not-java.exe' }
    if ($script:scenario -eq 'missing-command') { $p.CommandLine = $null }
    if ($script:scenario -eq 'server') { $p.CommandLine = 'java -jar server.jar' }
    if ($script:cimCalls -ge 2) {
        if ($script:scenario -eq 'changed-pid') { $p.ProcessId = 43 }
        if ($script:scenario -eq 'reused-cim-pid') { $p.CreationDate = $script:birth.AddSeconds(1) }
        if ($script:scenario -eq 'changed-command') { $p.CommandLine = 'javaw --gameDir=D:/fixture/other' }
        if ($script:scenario -eq 'same-instance-command-drift') { $p.CommandLine += ' -Xmx8G' }
    }
    if ($script:closeCalls -gt 0 -and $script:scenario -eq 'drift-after') { $p.CreationDate = $script:birth.AddSeconds(1) }
    if ($script:scenario -eq 'multiple') { return @($p, (New-FakeIdentity 43)) }
    return $p
}
function Get-Process {
    param($Id, $ErrorAction)
    $script:processCalls++
    if ($script:scenario -eq 'process-throw') { throw 'fixture process query failed' }
    $p = [pscustomobject]@{
        Id = 42; StartTime = $script:birth; ProcessName = 'javaw'
        Handle = [intptr]123; MainWindowHandle = [intptr]456; HasExited = $false
    }
    if ($script:scenario -eq 'wrong-pid') { $p.Id = 43 }
    if ($script:scenario -eq 'reused-pid') { $p.StartTime = $script:birth.AddSeconds(1) }
    if ($script:scenario -eq 'no-window') { $p.MainWindowHandle = [intptr]0 }
    if ($script:scenario -eq 'no-handle') { $p.Handle = [intptr]0 }
    if ($script:scenario -eq 'missing-start') { $p.StartTime = $null }
    if ($script:scenario -eq 'process-exited') { $p.HasExited = $true }
    if ($script:scenario -eq 'wrong-process-name') { $p.ProcessName = 'not-java' }
    $p | Add-Member ScriptMethod Refresh {
        $script:refreshCalls++
        if ($script:scenario -eq 'refresh-throw') { throw 'fixture refresh failed' }
        if ($script:scenario -eq 'handle-drift' -and $script:refreshCalls -ge 2) { $this.Handle = [intptr]234 }
        if ($script:scenario -eq 'start-drift' -and $script:refreshCalls -ge 2) { $this.StartTime = $script:birth.AddSeconds(1) }
        if ($script:closeCalls -gt 0 -and $script:scenario -in @('success','dispose-throw','unknown-with-exit')) { $this.HasExited = $true }
        if ($script:scenario -eq 'window-drift' -and $script:refreshCalls -ge 2) { $this.MainWindowHandle = [intptr]789 }
    }
    $p | Add-Member ScriptMethod CloseMainWindow {
        $script:closeCalls++
        $script:closedIds += $this.Id
        if ($script:scenario -eq 'close-throw') { throw 'fixture close failed' }
        return ($script:scenario -notin @('close-false','close-false-stopped'))
    }
    $p | Add-Member ScriptMethod Dispose {
        $script:disposeCalls++
        if ($script:scenario -eq 'dispose-throw') { throw 'fixture disposal failed' }
    }
    return $p
}
function Get-CimInstance { $script:unmockedCalls++; throw 'UNMOCKED CIM boundary' }
function Stop-Process { param($Id, [switch]$Force, $ErrorAction) $script:forceCalls++; $script:forcedIds += $Id }
function Invoke-RddExitAudit { $script:auditCalls++ }
function Get-Date {
    $result = $script:clock
    $script:clock = $script:clock.AddMilliseconds(100)
    return $result
}
function Start-Sleep { param($Milliseconds, $Seconds) $script:sleepCalls++; $script:clock = $script:clock.AddMilliseconds($Milliseconds + 1000 * $Seconds) }
function Run-Case($Name, $Pattern, $Close = 0, $Audit = 0, $Force = 0, [switch]$Legacy) {
    $script:scenario = $Name
    $script:clock = $script:birth
    $script:stateCalls = 0; $script:cimCalls = 0; $script:processCalls = 0
    $script:refreshCalls = 0; $script:disposeCalls = 0; $script:sleepCalls = 0
    $script:closeCalls = 0; $script:forceCalls = 0; $script:auditCalls = 0
    $script:closedIds = @(); $script:forcedIds = @(); $script:unmockedCalls = 0
    try {
        if ($Legacy) { $result = Stop-RddMcInstance -Instance fixture -TimeoutSec 1 }
        else { $result = Stop-RddMcInstance -Instance fixture -TimeoutSec 1 -GracefulOnly }
    } catch { $result = "THREW: $_" }
    Check "$Name/result" $true ("$result" -match $Pattern)
    Check "$Name/close" $Close $script:closeCalls
    Check "$Name/audit" $Audit $script:auditCalls
    Check "$Name/force" $Force $script:forceCalls
    if (-not $Legacy) {
        Check "$Name/no-save-claim" $false ("$result" -match 'saved|save(PASS|=true|Succeeded)')
        Check "$Name/target-only" $true (@($script:closedIds | Where-Object { $_ -ne 42 }).Count -eq 0)
        Check "$Name/disposed" $script:processCalls $script:disposeCalls
        Check "$Name/no-live-CIM" 0 $script:unmockedCalls
        $script:gracefulForceTotal += $script:forceCalls
        if ($Audit -gt 0) { Check "$Name/save-unknown" $true ("$result" -match 'save=UNKNOWN') }
        if ($Name -eq 'already-stopped') { Check "$Name/no-target-query" 0 $script:cimCalls }
    }
    Write-Output ("CASE {0} result=[{1}] close={2} force={3} audit={4}" -f $Name,$result,$script:closeCalls,$script:forceCalls,$script:auditCalls)
}
Write-Output ("GracefulOnly parameter present: " + (Get-Command Stop-RddMcInstance).Parameters.ContainsKey('GracefulOnly'))
$script:gracefulForceTotal = 0
Run-Case 'success' '^STOP_CLAIMED: requested target stopped' 1 1
Run-Case 'already-stopped' '^already down$'
Run-Case 'unknown' '^STOP_UNKNOWN'
Run-Case 'empty' '^STOP_UNKNOWN'
Run-Case 'multiple' '^STOP_UNKNOWN'
Run-Case 'query-throw' '^STOP_UNKNOWN'
Run-Case 'process-throw' '^STOP_UNKNOWN'
Run-Case 'other-instance' '^STOP_UNKNOWN'
Run-Case 'bridge' '^STOP_UNKNOWN'
Run-Case 'missing-birth' '^STOP_UNKNOWN'
Run-Case 'wrong-pid' '^STOP_UNKNOWN'
Run-Case 'reused-pid' '^STOP_UNKNOWN'
Run-Case 'reused-cim-pid' '^STOP_UNKNOWN'
Run-Case 'changed-pid' '^STOP_UNKNOWN'
Run-Case 'changed-command' '^STOP_UNKNOWN'
Run-Case 'no-handle' '^STOP_UNKNOWN'
Run-Case 'no-window' '^STOP_REFUSED: no window'
Run-Case 'window-drift' '^STOP_UNKNOWN'
Run-Case 'stopped-before-request' '^STOP_UNKNOWN'
Run-Case 'close-false' '^STOP_REFUSED: close request rejected' 1
Run-Case 'close-throw' '^STOP_UNKNOWN' 1
Run-Case 'timeout' '^STOP_TIMEOUT: close requested' 1
Run-Case 'unknown-after' '^STOP_UNKNOWN' 1
Run-Case 'drift-after' '^STOP_UNKNOWN' 1
Run-Case 'state-throw' '^STOP_UNKNOWN'
Run-Case 'directory-drift' '^STOP_UNKNOWN'
Run-Case 'wrong-name' '^STOP_UNKNOWN'
Run-Case 'missing-command' '^STOP_UNKNOWN'
Run-Case 'server' '^STOP_UNKNOWN'
Run-Case 'same-instance-command-drift' '^STOP_UNKNOWN'
Run-Case 'missing-start' '^STOP_UNKNOWN'
Run-Case 'process-exited' '^STOP_UNKNOWN'
Run-Case 'wrong-process-name' '^STOP_UNKNOWN'
Run-Case 'refresh-throw' '^STOP_UNKNOWN'
Run-Case 'handle-drift' '^STOP_UNKNOWN'
Run-Case 'start-drift' '^STOP_UNKNOWN'
Run-Case 'stop-not-exited' '^STOP_UNKNOWN' 1
Run-Case 'unknown-with-exit' '^STOP_UNKNOWN' 1
Run-Case 'close-false-stopped' '^STOP_REFUSED: close request rejected' 1
Run-Case 'dispose-throw' '^STOP_CLAIMED: requested target stopped' 1 1
Write-Output "GRACEFUL forceCallsTotal=$script:gracefulForceTotal"
# Existing callers retain their old return values and force fallback.
Run-Case 'success' '^stopped-gracefully' 1 1 0 -Legacy
Run-Case 'no-window' '^stopped-forced' 0 1 1 -Legacy
Run-Case 'timeout' '^stopped-forced' 1 1 1 -Legacy
Run-Case 'unknown' '^STOP_UNKNOWN' 0 0 0 -Legacy
Write-Output "RESULT passed=$script:passed failed=$script:failed (all processes/windows/clock/audit are fakes)"
if ($script:failed -gt 0) { exit 1 }
