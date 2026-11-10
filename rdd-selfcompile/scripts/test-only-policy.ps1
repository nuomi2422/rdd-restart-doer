# Pure test-only command plan and JUnit receipt policy; never invokes Gradle or deployment.
function Get-RddTestOnlyPlan {
    param([string]$Module, [string[]]$Tests)
    $allowed = @(
        'com.dwinovo.numen.plugins.rdd.RddSettleStageUnmetTest',
        'com.dwinovo.numen.plugins.rdd.RddSettleStageFlagsTest'
    )
    if (($Module.Trim()) -cne 'plugins:rdd') { throw 'test-only module is not allowed' }
    if (-not $Tests -or $Tests.Count -eq 0) { throw 'at least one exact test class is required' }
    $normalized = @()
    foreach ($name in $Tests) {
        if ($null -eq $name) { throw 'null test class is not allowed' }
        $n = $name.Trim()
        if ($n -cnotin $allowed) { throw "test class is not allowed: $n" }
        if ($n -cnotin $normalized) { $normalized += $n }
    }
    return @{ Task = ':plugins:rdd:test'; Tests = $normalized }
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
