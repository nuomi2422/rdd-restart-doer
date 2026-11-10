# Pure test-only command plan and JUnit receipt policy; never invokes Gradle or deployment.
function Get-RddTestOnlyPlan {
    param([string]$Module, [string[]]$Tests)
    # Module -> exact test classes. Unknown module or class is refused; never build
    # a Gradle task or test filter from caller text.
    $allowlist = @{
        'plugins:rdd' = @(
            'com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest',
            'com.dwinovo.numen.plugins.rdd.RddSettleStageFlagsTest'
        )
        'api:common' = @(
            'com.dwinovo.numen.api.ServerIdentitySnapshotTest',
            'com.dwinovo.numen.monitor.WorldContextStampTest'
        )
        'world-state-core' = @(
            'com.dwinovo.numen.worldstate.core.model.WorldIdentityTest'
        )
    }
    $module = $Module.Trim()
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
