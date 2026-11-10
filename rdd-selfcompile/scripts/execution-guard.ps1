# execution-guard.ps1 -- pure refusal policy for the incident freeze.
# No side effects: no file/process/config access. Safe to dot-source for offline checks.
function Get-RddRunModeDecision {
    param(
        [string]$Mode,
        [switch]$TestOnly,
        [string[]]$Tests = @()
    )
    $explicit = -not [string]::IsNullOrWhiteSpace($Mode)
    $switchOn = [bool]$TestOnly
    if (-not $explicit -and -not $switchOn) { return @{ ok=$false; reason='missing-explicit-mode' } }
    if ($explicit -and $switchOn -and $Mode -cne 'test-only') { return @{ ok=$false; reason='mode-conflict: explicit mode + -TestOnly' } }
    $effective = if ($explicit) { $Mode } else { 'test-only' }
    if ($effective -cnotin @('test-only', 'full')) { return @{ ok=$false; reason='unknown-mode' } }
    if ($effective -eq 'full') { return @{ ok=$false; reason='incident-freeze: full disabled pending commander batch' } }
    if (-not $Tests -or @($Tests).Count -eq 0) { return @{ ok=$false; reason='test-only requires exact -Tests' } }
    foreach ($t in @($Tests)) {
        if ([string]::IsNullOrWhiteSpace($t)) { return @{ ok=$false; reason='empty-test-class' } }
    }
    return @{ ok=$true; mode='test-only' }
}
function Get-RddDeployLaunchDecision {
    param([string]$Entry)
    return @{ ok=$false; reason=("incident-freeze: " + $Entry + " disabled pending commander batch") }
}
