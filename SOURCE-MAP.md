# 源码与发布去向（2026-11-18 03:40 核验）

总共四个仓库，只有文档是闭源的。

| 用途 | 仓 | 可见性 | 准确版本 |
|---|---|---|---|
| 外部展示（本仓） | nuomi2422/rdd-restart-doer | 公开 | master |
| 游戏源码 | nuomi2422/minecraft-numen | 公开 | main = 04bfe4b245201683ae87165d67db70dac3423e56 |
| Harness 工具与技能 | nuomi2422/rdd-harness | 公开 | main |
| 文档与知识库 | nuomi2422/rdd-docs | 私有（含 API/凭据） | master |

## 指针

- 游戏源码：https://github.com/nuomi2422/minecraft-numen/tree/main —— fork 自 Dwinovo/minecraft-numen（上游只拉不推），RDD 的改动全部在这条 main 上。
- Harness：https://github.com/nuomi2422/rdd-harness
- 文档：https://github.com/nuomi2422/rdd-docs （需要权限，因为里面有 API 凭据）

## 说明

本仓只做展示和指针，不承载源码本体。历史 backup/* 分支是 2026-11 之前的快照，内容与源码、harness 重复，保留待清理，不作为真源。版本位置不证明已部署或实机有效。
