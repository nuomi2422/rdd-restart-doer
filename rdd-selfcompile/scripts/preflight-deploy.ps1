# preflight-deploy.ps1 -- one command to prove all deployable jars match current source.
#
# Why (2026-11-05): twice in one night a jar was installed that did not contain the new code
# (worldstate missing Readiness.class; rdd built before the F1/F2/F3 commit). verify-install.ps1
# does the per-jar checks; this runs them for every artifact we ship, so "did I forget one?"
# is answered by one command instead of memory.
#
# ASCII only on purpose: PowerShell 5.1 reads UTF-8-without-BOM as GBK.
#
# Usage:
#   powershell -NoProfile -File scripts\preflight-deploy.ps1
#   powershell -NoProfile -File scripts\preflight-deploy.ps1 -CommitMap @{ 'rdd'='01dac1fae' }
# Exit: 0 = all okay, 1 = at least one failure.

param(
    [string]$Mods = 'D:/rdd/mc/The Best of Twilight Forest/mods',
    [string]$Repo = 'D:/rdd/workspace/minecraft-numen',
    [hashtable]$CommitMap = @{}
)

$ErrorActionPreference = 'Stop'

# name | installed file | built file | required classes
$items = @(
    @{ name='api';        installed='numen_api-neoforge-1.21.1-0.1.3-dev.jar';
       built='api/neoforge/build/libs/numen_api-neoforge-1.21.1-0.1.3-dev.jar';
       req='Readiness.class,ChangesQuery.class,ChangesV2Response.class' },
    @{ name='worldstate'; installed='numen-plugin-worldstate-1.21.1-0.1.3-dev.jar';
       built='plugins/worldstate/build/libs/numen-plugin-worldstate-1.21.1-0.1.3-dev.jar';
       req='ObservableStoreV2.class,WorldStateSchema.class,VersionedChangesMapper.class' },
    @{ name='rdd';        installed='numen-plugin-rdd-1.21.1-0.1.3-dev.jar';
       built='plugins/rdd/build/libs/numen-plugin-rdd-1.21.1-0.1.3-dev.jar';
       req='ContainerChangePoller.class,RddClock.class,RddCondition.class' }
)

$failed = 0
foreach ($it in $items) {
    $inst = Join-Path $Mods $it.installed
    $bld = Join-Path $Repo $it.built
    $commit = ''
    if ($CommitMap.ContainsKey($it.name)) { $commit = [string]$CommitMap[$it.name] }

    Write-Output ('--- ' + $it.name)
    $args = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'verify-install.ps1'),
              '-Installed', $inst, '-Built', $bld, '-Required', $it.req, '-Repo', $Repo)
    if ($commit -ne '') { $args += @('-Commit', $commit) }
    $out = & powershell @args 2>&1 | Out-String
    Write-Output $out.TrimEnd()
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

Write-Output ''
if ($failed -gt 0) {
    Write-Output ('PREFLIGHT: FAIL (' + $failed + ' artifact(s))')
    exit 1
}
Write-Output 'PREFLIGHT: ALL OK'
exit 0
