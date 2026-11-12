# execution-guard.ps1 -- pure refusal policy for the incident freeze.
# No side effects: no file/process/config access. Safe to dot-source for offline checks.
function Resolve-RddRunMode {
    param(
        [string]$Mode,
        [switch]$TestOnly
    )
    $explicit = -not [string]::IsNullOrWhiteSpace($Mode)
    $switchOn = [bool]$TestOnly
    if (-not $explicit -and -not $switchOn) { return @{ ok=$false; reason='missing-explicit-mode' } }
    if ($explicit -and $switchOn -and $Mode -cne 'test-only') { return @{ ok=$false; reason='mode-conflict: explicit mode + -TestOnly' } }
    $effective = if ($explicit) { $Mode } else { 'test-only' }
    if ($effective -cnotin @('test-only', 'build-only', 'full')) { return @{ ok=$false; reason='unknown-mode' } }
    if ($effective -eq 'full') { return @{ ok=$false; reason='incident-freeze: full disabled pending commander batch' } }
    return @{ ok=$true; mode=$effective }
}
function Test-RddTestSelection {
    param([string[]]$Tests)
    if (-not $Tests -or @($Tests).Count -eq 0) { return @{ ok=$false; reason='test-only requires exact -Tests' } }
    foreach ($t in @($Tests)) {
        if ([string]::IsNullOrWhiteSpace($t)) { return @{ ok=$false; reason='empty-test-class' } }
    }
    return @{ ok=$true }
}
function Get-RddDeployLaunchDecision {
    param([string]$Entry)
    return @{ ok=$false; reason=("incident-freeze: " + $Entry + " disabled pending commander batch") }
}
# 2026-11-11: explicit build-only is not permission for any deploy/launch path.
function Get-RddBuildOnlyPlan {
    param([string]$Instance,[bool]$InstanceExplicit,[string]$Module,[string]$SourceRoot,[string]$ExpectedCommit)
    if (-not $InstanceExplicit -or $Instance -cne 'test') { throw 'build-only requires explicit -Instance test' }
    if ([string]::IsNullOrWhiteSpace($SourceRoot) -or $ExpectedCommit -cnotmatch '^[0-9a-fA-F]{40}$') { throw 'build-only requires SourceRoot and full ExpectedCommit' }
    $names = @{'api:neoforge'='numen_api-neoforge';'core:neoforge'='numen-neoforge';'plugins:rdd'='numen-plugin-rdd';'plugins:learner'='numen-plugin-learner';'plugins:maidlink'='numen-plugin-maidlink'}
    if (-not $names.ContainsKey($Module) -or $Module -cnotin @('api:neoforge','core:neoforge','plugins:rdd','plugins:learner','plugins:maidlink')) { throw 'build-only module refused' }
    return @{module=$Module;task=(':'+$Module+':jar');relativeDir=($Module.Replace(':','/')+'/build/libs');artifactPrefix=$names[$Module]}
}
function Select-RddBuildArtifact {
    param([string[]]$Names,[string]$Prefix)

    $hits=@($Names | Where-Object { $_ -ceq ($Prefix+'-1.21.1-0.1.3-dev.jar') })
    if($hits.Count -ne 1){throw 'expected exactly one fixed release jar'}
    return $hits[0]
}
