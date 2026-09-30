<#
    stager.ps1 —— PowerShell 包装（和 stager.cmd 等价）

    用法：
      & "E:\restart developing doer\stager\bin\stager.ps1" ctx
      & "E:\restart developing doer\stager\bin\stager.ps1" next --note "写完了"

    -RequireModule stager 会把 stager 函数塞进当前会话，不用每次写全路径。
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'stager.js'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($Args -contains '-RequireModule') {
    $Args = @($Args | Where-Object { $_ -ne '-RequireModule' })
    function stager { & $cli @Args }
    Set-Alias -Name stagerx -Value stager -Scope Global -ErrorAction SilentlyContinue
    Write-Host "stager() 已注入当前会话。例：stager ctx / stager next --note 'x' / stager status" -ForegroundColor Green
    return
}

& node $cli @Args
exit $LASTEXITCODE
