# 源码与发布去向（2026-11-18核验）

| 用途 | 位置及准确版本 |
|---|---|
| 项目门面与基础管线 | nuomi2422/rdd-restart-doer，master |
| 工具发布 | nuomi2422/rdd-harness，main |
| 文档发布 | nuomi2422/rdd-docs，master；以知识库入口开始 |
| 本机游戏整合源码 | workspace/minecraft-numen，main，04bfe4b245201683ae87165d67db70dac3423e56 |
| Numen fork | nuomi2422/minecraft-numen，默认1.21.1，5bf1a057a356e97c0d7025bd066539fefb7b8e2f；远端未见main |
| 历史完整源码快照 | 本仓backup/minecraft-numen-04bfe4b-20261117，04bfe4b245201683ae87165d67db70dac3423e56 |
| 历史工作区快照 | 本仓backup/workspace-619109e-20261117，619109e72dd287f3c407260c1d607f483ff1610a |
| 历史Harness快照 | 本仓backup/rdd-harness-5bafe55-20261117，5bafe5550f6fe8750dccb8b81be0b9427b4ff2d3 |
| 历史文档快照 | rdd-docs的review/docs-2b717d2-20261117，2b717d2846dc5f2098be5b8da099afcaf38397c2 |

旧备份分支保留，不再向门面仓混入其它仓完整历史。完整源码后续使用专用私有源码仓，目标未确定前保留本机已验证bundle。本轮未向公开fork上传内部整合源码，也未修改仓可见性。

本地旧分支仅归档已被main包含、无worktree占用的项；bundle和refs/archive保留恢复。并行053工作树及未合入分支保留。版本位置不证明已部署或实机有效。
