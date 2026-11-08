# 2026-11-08: launcher instance boundary regression.
# Runs only mc-launch.mjs --dry; never starts Minecraft.
$ErrorActionPreference = 'Continue'
$node = if (Test-Path 'D:/rdd/tools/node/node.exe') { 'D:/rdd/tools/node/node.exe' } else { 'node' }
$launcher = 'D:/rdd/tools/mc-launch.mjs'
$root = Join-Path $env:TEMP ('rdd-launcher-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'mods') -Force | Out-Null
Set-Content -Path (Join-Path $root 'mods/dummy.jar') -Value 'x'
$cases = @(
  @{ name = 'valid-space-cn-no-options'; instance = $root; level = 'fresh-auto'; ok = $true },
  @{ name = 'truncated-existing'; instance = 'D:/rdd/mc/The'; level = 'fresh-auto'; ok = $false },
  @{ name = 'missing'; instance = (Join-Path $root 'missing'); level = 'fresh-auto'; ok = $false }
)
try {
  foreach ($c in $cases) {
    $args = @($launcher, '--instance', $c.instance, '--level', $c.level, '--dry')
    $out = & $node @args 2>&1 | Out-String
    $exit = $LASTEXITCODE
    if ($c.ok -and $exit -ne 0) { throw "case $($c.name) expected success, got ${exit}: $out" }
    if (-not $c.ok -and $exit -eq 0) { throw "case $($c.name) expected refusal, got success" }
    if (-not $c.ok -and $out -notmatch 'no mods|not a directory') { throw "case $($c.name) refusal message unclear: $out" }
  }
  Write-Output 'launcher-instance: PASS (valid/no-options, truncated, missing)'
} finally {
  Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}
