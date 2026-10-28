# spawn-observer.ps1 -- 在主世界拉起一个创造模式的观察者同伴（第二视角）
#
# 为什么存在（2026-10-28）：mineflayer 连不了 NeoForge 实例（FML 握手门，
# 见 tools/mineflayer/README.md），但 Numen 本身就能 create_companion 造服务端玩家实体
# -- 这条路能进主世界、能开创造、能跟 RDD 并存。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:/rdd/workspace/scripts/spawn-observer.ps1
#
# 前提：游戏已起、MCP 8765 在听（start-rdd.ps1 之后）。
# 同伴写进 saves/live/playerdata/<uuid>.dat，重启后仍在。
# 重复跑安全：create_companion 对同名同伴是幂等的（不会造第二个）。

param(
    [string]$Name = 'Observer'
)

$ErrorActionPreference = 'Stop'
$MCP  = 'D:/rdd/workspace/rdd-selfcompile/scripts/mcp-call.js'
$SEND = 'D:/rdd/harness/rdd-harness/bin/send-mc-command.ps1'

function Call-Mcp {
    param([string]$Tool, [string]$Companion, [string]$Args)
    $argv = @($MCP, $Tool, $Companion)
    if ($Args) { $argv += $Args }
    $out = & node @argv 2>&1
    return ($out | Out-String).Trim()
}

Write-Output ('summon (idempotent) ' + $Name + ' ...')
Call-Mcp -Tool 'create_companion' -Companion 'RDD' -Args ('name=' + $Name) | Out-Null
Start-Sleep -Seconds 6

# 切创造模式（/gamemode 走 MCP 没有对应工具，必须用 send-mc-command）
& powershell -NoProfile -ExecutionPolicy Bypass -File $SEND -Text ('/gamemode creative ' + $Name) | Out-Null
Start-Sleep -Seconds 2

Write-Output ('status: ' + [string](Call-Mcp -Tool 'get_self_status' -Companion $Name))
Write-Output 'done.'
