# backup-to-removable.ps1 -- 离线备份到 F:（可移动盘）
# 2026-10-01 · 目的：电脑坏了/进水后能复刻
#
# 设计要点
#  1. 排除构建垃圾（build/.gradle/node_modules）与实例配置（含 API key）
#  2. git 历史用 git bundle 单文件保存（.git 目录不给，但历史不能丢）
#  3. 生成 MANIFEST（文件数+字节数+SHA256 抽样）用于校验
#  4. F 是 FAT32：单文件上限 4GB —— 已确认无 >1GB 文件，安全
param(
  [string]$Dest = 'F:\Numen备份\2026-10-01'
)
$ErrorActionPreference = 'Continue'
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

# ---- robocopy 公共排除项 ----
# /XD 目录  /XF 文件
$XD = @('build','.gradle','node_modules','.git','mutations','logs','instances','run',
        '.stager\tasks\_tmp','heapdump')
$XF = @('mcp_server.json','numen_api-common.toml','numen_api*.toml','id_ed25519','id_rsa',
        '*.key','*.pem','.env','*.log','*.heapdump','*.hprof')

function Copy-Tree {
    param([string]$Src, [string]$Dst)
    if (-not (Test-Path -LiteralPath $Src)) { Write-Output "SKIP (不存在): $Src"; return }
    Write-Output "COPY: $Src  ->  $Dst"
    $args = @($Src, $Dst, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
    foreach ($d in $XD)  { $args += '/XD'; $args += $d }
    foreach ($f in $XF)  { $args += '/XF'; $args += $f }
    & robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Output ("  !! robocopy 异常 exit=" + $LASTEXITCODE + " -> " + $Src) }
}

Write-Output "==================== 开始备份 $stamp ===================="
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

# ① 架构文档（最重要，纯 md，已验证无密钥）
Copy-Tree 'E:\新建文件夹\rdd-docs\rdd架构'            (Join-Path $Dest '01-架构文档')
# ② Numen 源码（minecraft-numen 自己的仓）
Copy-Tree 'E:\restart developing doer\minecraft-numen' (Join-Path $Dest '02-源码-numen')
# ③ 自编译闭环（脚本/门禁/模板/报告）
Copy-Tree 'E:\restart developing doer\rdd-selfcompile' (Join-Path $Dest '03-自编译闭环')
# ④ 阶段管理 + 工具
Copy-Tree 'E:\restart developing doer\stager'   (Join-Path $Dest '04-stager阶段管理')
Copy-Tree 'E:\restart developing doer\mc-openclaw-controller' (Join-Path $Dest '05-OpenClaw控制器')
Copy-Tree 'E:\restart developing doer\rdd-monitor-publish-20260913' (Join-Path $Dest '06-监测台')
# ⑤ 规则卡与入口脚本（根仓顶层散文件，体积小但关键）
Copy-Tree 'E:\restart developing doer' (Join-Path $Dest '07-工作区根') | Out-Null

# ⑥ git 历史（bundle 单文件，.git 已在上面排除）
$bundleDir = Join-Path $Dest '08-git历史'
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
Write-Output "BUNDLE: minecraft-numen"
& git -C 'E:\restart developing doer\minecraft-numen' bundle create (Join-Path $bundleDir 'minecraft-numen-all.bundle') --all 2>&1 | ForEach-Object { "  $_" }
Write-Output "BUNDLE: 根仓"
& git -C 'E:\restart developing doer' bundle create (Join-Path $bundleDir 'workspace-root.bundle') --all 2>&1 | ForEach-Object { "  $_" }

# ⑦ 清单
Write-Output "MANIFEST 生成中..."
$manifest = Join-Path $Dest '99-MANIFEST.txt'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Numen 项目离线备份清单")
$lines.Add("生成时间: $stamp")
$lines.Add("源机器: $env:COMPUTERNAME")
$lines.Add("恢复指南: 见同目录 00-README-怎么恢复.md")
$lines.Add("")
$lines.Add("!!! 安全声明：已排除 mcp_server.json / numen_api-common.toml / id_ed25519 / *.key / *.log 等含凭据文件。")
$lines.Add("    恢复后需重新填 API key 与 MCP token（token 会话级，重启即变）。")
$lines.Add("")
foreach ($d in (Get-ChildItem $Dest -Directory | Sort-Object Name)) {
    $files = @(Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
    $sum = ($files | Measure-Object Length -Sum).Sum
    $lines.Add(("{0,-24} 文件 {1,6}  体积 {2,10:N0} MB" -f $d.Name, $files.Count, ($sum/1MB)))
}
$lines.Add("")
$lines.Add("--- 顶层文件 ---")
foreach ($f in (Get-ChildItem $Dest -File | Sort-Object Name)) {
    $lines.Add(("{0,-30} {1,10:N0} B" -f $f.Name, $f.Length))
}
$lines.Add("")
$lines.Add("--- 关键文件抽样 SHA256（用于校验复制完整性）---")
foreach ($rel in @(
  '01-架构文档\自编译统一版\41-第一批红线固化-20260930.md',
  '01-架构文档\自编译统一版\30-主要功能不回退清单.md',
  '01-架构文档\自编译统一版\44-工程经验-筐1六项收口-20260930.md',
  '02-源码-numen\rdd-core\src\main\java\com\dwinovo\numen\rdd\core\RddDeathLedger.java',
  '02-源码-numen\plugins\rdd\src\main\java\com\dwinovo\numen\plugins\rdd\RddDeathLedgerStore.java',
  '03-自编译闭环\scripts\launch-mc.ps1',
  '03-自编译闭环\scripts\loop-gate.js',
  '03-自编译闭环\scripts\run-mutation.ps1')) {
    $p = Join-Path $Dest $rel
    if (Test-Path -LiteralPath $p) {
        $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0,16)
        $lines.Add(("{0}  {1}" -f $h, $rel))
    } else {
        $lines.Add(("MISSING           " + $rel))
    }
}
# 拆成两步，避免 New-Object + 嵌套括号的 PS 5.1 解析坑
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($manifest, $lines, $utf8NoBom)
Write-Output "MANIFEST -> $manifest"

$total = (Get-ChildItem $Dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
Write-Output ("==================== 完成，总计 {0:N0} MB ====================" -f ($total/1MB))
