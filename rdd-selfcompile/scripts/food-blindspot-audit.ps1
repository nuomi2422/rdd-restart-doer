param(
  [string]$GameDir = 'D:/rdd/mc/The Best of Twilight Forest',
  [int]$LookbackHours = 24
)
$ErrorActionPreference = 'Stop'
$mon = Join-Path $GameDir 'config/numen/monitor'
$cut = (Get-Date).AddHours(-$LookbackHours)
$danger = New-Object System.Collections.ArrayList
$deaths = New-Object System.Collections.ArrayList
$judgeable = 0
$unknown = 0
if (Test-Path (Join-Path $mon 'context.jsonl')) {
  Get-Content (Join-Path $mon 'context.jsonl') -Encoding UTF8 | ForEach-Object {
    $line = $_
    $hm = [regex]::Match($line, 'hunger[^0-9]{0,4}(\d{1,2})')
    if (-not $hm.Success) { return }
    $pm = [regex]::Match($line, 'hp[^0-9]{0,4}(\d{1,2})')
    $ts = 'unknown-time'
    $tm = [regex]::Match($line, '"timestamp"\s*:\s*"([^"]+)"')
    if ($tm.Success) { $ts = $tm.Groups[1].Value }
    $hunger = [int]$hm.Groups[1].Value
    $hp = if ($pm.Success) { [int]$pm.Groups[1].Value } else { -1 }
    if ($hunger -lt 0 -and $hp -lt 0) { $unknown++; return }
    $judgeable++
    if (($hunger -le 6 -and $hunger -ge 0) -or ($hp -le 8 -and $hp -gt 0)) {
      [void]$danger.Add([pscustomobject]@{ time = $ts; hunger = $hunger; hp = $hp })
    }
  }
}
if (Test-Path (Join-Path $mon 'rdd.jsonl')) {
  Get-Content (Join-Path $mon 'rdd.jsonl') -Encoding UTF8 | ForEach-Object {
    if ($_ -match 'starvation_death|"type":"death"') { [void]$deaths.Add($_) }
  }
}
$foodDue = 0
if (Test-Path (Join-Path $mon 'rdd.jsonl')) {
  $foodDue = (Select-String -Path (Join-Path $mon 'rdd.jsonl') -Pattern '"typeId":"food_supply"' | Measure-Object).Count
}
$coverage = 'N/A (no hunger/hp fields in logs)'
if ($judgeable + $unknown -gt 0) { $coverage = ([math]::Round(100.0 * $judgeable / ($judgeable + $unknown), 1).ToString() + '%') }
Write-Output ('danger_windows=' + $danger.Count + ' judgeable=' + $judgeable + ' unknown=' + $unknown + ' coverage=' + $coverage)
Write-Output ('food_supply_events=' + $foodDue + ' starvation_deaths=' + $deaths.Count)
Write-Output 'danger windows:'
$danger | Select-Object -First 10 | ForEach-Object { [string]$_.time + ' hunger=' + $_.hunger + ' hp=' + $_.hp }
