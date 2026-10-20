<#
    按命令行关键字找并杀掉进程
    ★★★ 安全锁（2026-10-01 血泪）★★★

    事故记录：这个脚本第一次跑时 -Match 没传进来（空值），
    而 `$p.CommandLine -match ''` 对**任何字符串都返回 true**，
    于是 explorer.exe / svchost.exe / OpenCode.exe / ShellHost / QQ … 全被杀，
    用户的桌面和窗口全没了。

    所以下面这个守卫是**必须的**，不是防御性冗余：
      ① $Match 为空 / 长度 < 3 → 立刻退出，一个进程都不碰
      ② 关键字命中太多（>30 个）→ 拒绝执行并报错，宁可不杀也不误杀
      ③ 只杀名字在白名单里的脚本类进程（powershell/node/cmd/python），
         绝不动 explorer / svchost / OpenCode 这类系统/应用进程
#>
param(
    [string]$Match = '',
    [switch]$Quiet
)

# ── 守卫 ①：空 / 太短的关键字一律拒绝 ──────────────────
if ([string]::IsNullOrWhiteSpace($Match)) {
    Write-Error 'Match 为空 —— 拒绝执行。（空正则会匹配所有进程，见脚本头事故记录）'
    exit 1
}
if ($Match.Length -lt 3) {
    Write-Error ("Match 太短（'" + $Match + "'）—— 拒绝执行，太容易误伤。至少 3 个字符。")
    exit 1
}

# ── 守卫 ②：只碰脚本类进程，绝不动系统/桌面/主程序 ────────────
$ALLOWED = @('powershell', 'pwsh', 'node', 'cmd', 'python', 'pythonw', 'conhost')

$ErrorActionPreference = 'SilentlyContinue'
$cim = Get-CimInstance Win32_Process
$cands = $cim | Where-Object {
    $_.CommandLine -and
    $_.CommandLine -match $Match -and
    ($ALLOWED -contains $_.Name.Replace('.exe', '').ToLower())
}

if (@($cands).Count -eq 0) { if (-not $Quiet) { Write-Output '  (none matched)' }; exit 0 }

# ── 守卫 ③：命中太多就是匹配写错了，宁可不杀 ────────────────
if (@($cands).Count -gt 30) {
    Write-Error ("命中 " + @($cands).Count + " 个进程 —— 关键字 '" + $Match + "' 很可能写错了（例如 'start' 会匹配所有 startup 相关）。拒绝执行。")
    Write-Error '请写更具体的关键字，例如 every-10min-drive、start-pet.ps1、stage-heartbeat'
    exit 1
}

foreach ($c in $cands) {
    if (-not $Quiet) { Write-Output ("  kill " + $c.ProcessId + "  " + $c.Name) }
    Stop-Process -Id $c.ProcessId -Force
}
if (-not $Quiet) { Write-Output ("  killed " + @($cands).Count) }
exit 0