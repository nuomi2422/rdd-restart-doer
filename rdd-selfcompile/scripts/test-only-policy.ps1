# Pure test-only command plan and JUnit receipt policy; never invokes Gradle or deployment.
function Get-RddTestOnlyPlan {
    param([string]$Module, [string[]]$Tests)
    # Module -> exact test classes. Unknown module or class is refused; never build
    # a Gradle task or test filter from caller text.
    $allowlist = @{
        'plugins:rdd' = @(
            'com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest',
            'com.dwinovo.numen.plugins.rdd.RddSettleStageFlagsTest',
            'com.dwinovo.numen.plugins.rdd.RddStagePlannerParseTest',
            'com.dwinovo.numen.plugins.rdd.RddEarlyCompletionEvidenceTest',
            'com.dwinovo.numen.plugins.rdd.VerifiedCompletionIntegrationTest'
        )
        'api:common' = @(
            'com.dwinovo.numen.api.ServerIdentitySnapshotTest',
            'com.dwinovo.numen.monitor.WorldContextStampTest',
            'com.dwinovo.numen.api.RationaleContextTest',
            'com.dwinovo.numen.client.agent.OwnerStopLatchTest',
            'com.dwinovo.numen.api.EnqueueReceiptTest',
            'com.dwinovo.numen.api.EnqueueReceiptCompatTest',
            'com.dwinovo.numen.api.EnqueueTransactionMatrixTest',
            'com.dwinovo.numen.api.EnqueueTransactionQueueTest'
        )
        'world-state-core' = @(
            'com.dwinovo.numen.worldstate.core.model.WorldIdentityTest'
        )
        'maid-link-core' = @(
            'com.dwinovo.numen.link.core.MaidLinkCoreContractTest'
        )
    }
    $module = if ($null -eq $Module) { '' } else { $Module.Trim() }
    if ($module -eq '') {
        # No module given: accept only when every requested class belongs to exactly one
        # allowlisted module. Anything ambiguous stays refused.
        $owners = @()
        foreach ($name in @($Tests)) {
            if ($null -eq $name) { continue }
            foreach ($k in $allowlist.Keys) { if ($allowlist[$k] -ccontains $name.Trim()) { if ($owners -notcontains $k) { $owners += $k } } }
        }
        if ($owners.Count -ne 1) { throw 'test-only module is not allowed (pass an allowlisted module)' }
        $module = $owners[0]
    }
    if (-not $allowlist.ContainsKey($module)) { throw 'test-only module is not allowed' }
    $allowed = $allowlist[$module]
    if (-not $Tests -or $Tests.Count -eq 0) { throw 'at least one exact test class is required' }
    $normalized = @()
    foreach ($name in $Tests) {
        if ($null -eq $name) { throw 'null test class is not allowed' }
        $n = $name.Trim()
        if ($n -cnotin $allowed) { throw "test class is not allowed: $n" }
        if ($n -cnotin $normalized) { $normalized += $n }
    }
    return @{ Task = ":$($module):test"; Module = $module; Tests = $normalized }
}
# PowerShell 5.1 reads BOM-less UTF-8 as the local code page. A rewrite that drops the
# BOM turns Chinese comments into a ParserError before any test runs; check bytes, not text.
function Test-RddPowerShellEncoding {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        $bytes = [IO.File]::ReadAllBytes($p)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
        if ($hasBom) { continue }
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        foreach ($ch in $text.ToCharArray()) {
            if ([int]$ch -gt 127) { return @{ ok = $false; reason = "missing-bom:$([IO.Path]::GetFileName($p))" } }
        }
    }
    return @{ ok = $true; reason = 'encoding-ok' }
}
function Test-RddTestOnlyReceipt {
    param([int]$ExitCode, [string]$ReportDir, [string[]]$ExpectedTests)
    if ($ExitCode -ne 0) { return @{ ok=$false; reason='gradle-exit' } }
    if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) { return @{ ok=$false; reason='reports-missing' } }
    foreach ($name in $ExpectedTests) {
        $file = Join-Path $ReportDir "TEST-$name.xml"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @{ ok=$false; reason="report-missing:$name" } }
        try { [xml]$xml = Get-Content -LiteralPath $file -Raw -Encoding UTF8 } catch { return @{ ok=$false; reason="bad-xml:$name" } }
        if ($null -eq $xml.testsuite -or $xml.testsuite.name -cne $name) { return @{ ok=$false; reason="wrong-suite:$name" } }
        $tests=0; $failures=0; $errors=0; $skipped=0
        if (-not [int]::TryParse([string]$xml.testsuite.tests,[ref]$tests) -or
            -not [int]::TryParse([string]$xml.testsuite.failures,[ref]$failures) -or
            -not [int]::TryParse([string]$xml.testsuite.errors,[ref]$errors) -or
            -not [int]::TryParse([string]$xml.testsuite.skipped,[ref]$skipped)) { return @{ ok=$false; reason="bad-counts:$name" } }
        if ($tests -le 0 -or $skipped -ge $tests -or $failures -ne 0 -or $errors -ne 0) { return @{ ok=$false; reason="test-failed-or-empty:$name" } }
    }
    return @{ ok=$true; reason='passed' }
}

# R-11: validate a candidate test source root as a registered, clean worktree of the main repo.
function Resolve-RddTrustedSourceRoot {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$ExpectedCommit,
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'source root is required' }
    if ([string]::IsNullOrWhiteSpace($ExpectedCommit)) { throw 'expected commit is required' }
    $full = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "source root not found: $full" }
    $top = (& git -C $full rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($top)) { throw 'source root is not a git worktree' }
    $topFull = [IO.Path]::GetFullPath($top.Trim())
    if (-not [string]::Equals($topFull, $full, [StringComparison]::OrdinalIgnoreCase)) { throw 'source root is not the worktree top-level' }
    $common = (& git -C $full rev-parse --git-common-dir 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($common)) { throw 'cannot resolve git common dir' }
    $commonPath = $common.Trim()
    if (-not [IO.Path]::IsPathRooted($commonPath)) { $commonPath = Join-Path $full $commonPath }
    $commonFull = [IO.Path]::GetFullPath($commonPath)
    $repoGit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($RepoRoot)) '.git'))
    if (-not [string]::Equals($commonFull, $repoGit, [StringComparison]::OrdinalIgnoreCase)) { throw 'worktree belongs to a different repository' }
    $listed = @(& git -C $full worktree list --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'cannot list worktrees' }
    $norm = { param($p) ([IO.Path]::GetFullPath($p).Replace('\','/')).TrimEnd('/') }
    $target = & $norm $full
    $registered = $false
    foreach ($line in $listed) {
        if ($line -match '^worktree\s+(.+)$') {
            $candidate = & $norm $Matches[1].Trim()
            if ([string]::Equals($candidate, $target, [StringComparison]::OrdinalIgnoreCase)) { $registered = $true; break }
        }
    }
    if (-not $registered) { throw 'worktree is not registered in git worktree list' }
    $head = (& git -C $full rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'cannot resolve HEAD' }
    if ($head -ne $ExpectedCommit) { throw "HEAD mismatch: expected $ExpectedCommit, got $head" }
    $branch = (& git -C $full rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $dirty = @(& git -C $full status --porcelain 2>$null)
    if ($dirty.Count -gt 0) { throw "worktree is dirty ($($dirty.Count) entries); authoritative test requires clean source" }
    return @{ root=$full; head=$head; branch=$branch; dirtyCount=$dirty.Count }
}
