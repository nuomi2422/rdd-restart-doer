# make-offline-bundle.ps1
# ---------------------------------------------------------------------------
# Build a self-contained "extract -> compile with NO network" bundle for the
# minecraft-numen gradle project.  Contents: source + warm Gradle caches
# (fabric-loom / neoformruntime / modules-2) + offline Gradle distribution + JDK.
#
# ASCII-only on purpose: PS 5.1 misreads BOM-less UTF-8 .ps1 with non-ASCII.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File make-offline-bundle.ps1
#   ... -Staging D:\numen-offline-bundle -Archive D:\numen-offline-bundle.7z
#   ... -IncludeRuntimeAssets      (also bundle caches\minecraft so runClient works offline)
#   ... -Skip7z                    (stage only, do not compress)
# ---------------------------------------------------------------------------
param(
    [string]$Staging = 'D:\numen-offline-bundle',
    [string]$Archive = 'D:\numen-offline-bundle.7z',
    [switch]$IncludeRuntimeAssets,
    [switch]$Skip7z
)

$ErrorActionPreference = 'Stop'

$Root          = 'E:\restart developing doer'
$GradleHomeSrc = 'E:\.gradle'
$JdkSrc        = 'E:\jdk21\jdk-21.0.11+10'
$GradleDistSrc = Join-Path $Root 'gradle-9.2.0'
$NumenSrc      = Join-Path $Root 'minecraft-numen'
$SevenZip      = 'C:\Program Files\7-Zip\7z.exe'
$TplDir        = Join-Path $PSScriptRoot 'templates'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Robo($from, $to, [string[]]$extra) {
    $rb = @($from, $to, '/E', '/XF', '*.lock', '/NFL', '/NDL', '/NJH', '/NJS', '/R:1', '/W:1')
    if ($extra) { $rb += $extra }
    & robocopy @rb | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy '$from' -> '$to' failed (exit $LASTEXITCODE)" }
}

if (-not (Test-Path $TplDir)) { throw "templates dir missing: $TplDir" }

Step "reset staging: $Staging"
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $Staging 'gradle-home\caches') | Out-Null

$cacheItems = @('fabric-loom', 'neoformruntime', 'modules-2')
if ($IncludeRuntimeAssets) { $cacheItems += 'minecraft' }
foreach ($d in $cacheItems) {
    Step "copy gradle cache: $d"
    Robo (Join-Path $GradleHomeSrc "caches\$d") (Join-Path $Staging "gradle-home\caches\$d")
}

Step 'write clean gradle-home/gradle.properties (proxy disabled)'
Set-Content (Join-Path $Staging 'gradle-home\gradle.properties') "# offline bundle gradle-home: direct connection, no proxy`n" -Encoding ascii

Step 'copy offline Gradle distribution'
Robo $GradleDistSrc (Join-Path $Staging 'gradle-9.2.0')

Step 'copy JDK'
Robo $JdkSrc (Join-Path $Staging 'jdk\jdk-21.0.11+10')

Step 'copy source (minecraft-numen, minus build/.git/runs)'
Robo $NumenSrc (Join-Path $Staging 'src') @('/XD', '.git', 'build', '.gradle', 'runs', 'logs', 'out', '.idea')

# Neutralise the absolute org.gradle.java.home in the bundle's gradle.properties
# (it points at E:\jdk21\... which will not exist on the target machine).
$gp = Join-Path $Staging 'src\gradle.properties'
if (Test-Path $gp) {
    $t = Get-Content $gp -Raw -Encoding UTF8
    $t = [regex]::Replace($t, '(?m)^\s*org\.gradle\.java\.home\s*=.*$', '# org.gradle.java.home is supplied by build-offline.cmd JAVA_HOME')
    [IO.File]::WriteAllText($gp, $t, [Text.UTF8Encoding]::new($false))
    Step 'neutralised org.gradle.java.home in bundled src'
}

Step 'write launcher + readme'
Copy-Item (Join-Path $TplDir 'build-offline.cmd') (Join-Path $Staging 'build-offline.cmd') -Force
$commit = (git -C $NumenSrc rev-parse HEAD 2>$null)
$readme = Get-Content (Join-Path $TplDir 'README-OFFLINE.md') -Raw -Encoding UTF8
$readme = $readme.Replace('@@COMMIT@@', "$commit").Replace('@@DATE@@', (Get-Date -Format 'yyyy-MM-dd HH:mm'))
[IO.File]::WriteAllText((Join-Path $Staging 'README-OFFLINE.md'), $readme, [Text.UTF8Encoding]::new($false))

$size = (Get-ChildItem $Staging -Recurse -File | Measure-Object -Property Length -Sum).Sum
Step ("staged size: {0:N2} GB  ({1})" -f ($size / 1GB), $Staging)

if (-not $Skip7z) {
    if (-not (Test-Path $SevenZip)) { throw "7-Zip not found: $SevenZip" }
    Step "compress -> $Archive"
    if (Test-Path $Archive) { Remove-Item $Archive -Force }
    & $SevenZip a -t7z -mx=1 -mmt=on $Archive (Join-Path $Staging '*') | Out-Null
    if ($LASTEXITCODE -ge 2) { throw "7z failed (exit $LASTEXITCODE)" }
    Step ("archive: {0:N2} GB  ({1})" -f ((Get-Item $Archive).Length / 1GB), $Archive)
}

Write-Host 'DONE' -ForegroundColor Green
