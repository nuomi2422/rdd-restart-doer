# `check-budget-health.js` —— 开闸健康度一条命令

> 用途：把 `G4c-开闸卡.md` §9 那套「盯四个信号 + 30 分钟判据」变成一条命令。
> 只读，不改任何东西；口径全部来自开闸卡（S100 / S101 / S104 / S107 / S107b）。

## 怎么调

```powershell
# 开闸观察期看最近 30–60 分钟（这才是「校准后」的口径）
node verify-tools\check-budget-health.js --minutes 60

# 指定起点（跨过某次配置变更时用这个，别用大窗口混算）
node verify-tools\check-budget-health.js --since 2026-10-20T19:30:00Z

# 机器可读
node verify-tools\check-budget-health.js --minutes 60 --json

# 自测（6 条：健康 / 拒绝率高 / 复盘未配对 / 无流量 / 校准超线 / 端到端读文件）
node verify-tools\check-budget-health.js --selftest
```

退出码：`0` 健康 / `1` 有警告 / `2` 用法或环境错。

## 它算什么（每条的出处）

| 读数 | 口径 | 出处 |
|---|---|---|
| 拒绝率 | `rejected / (granted + rejected)` | **S101**：≤ 5% |
| block 占比 | `blocks / (granted + blocks)` | 开闸卡 §9 第 3 步：0–5%，>10% 额度不对 |
| 估算/实际 | `budget_settle` 里 `estimatedTokens / actualTokens` 的 P50/P90（只认 `charged` 且 `actual>0`） | **S100**：P90 ≤ 1.3 |
| 主人豁免 | `budget_owner_override` 次数 | **S107**（方案 A） |
| 窗口到点重试 | `budget_retry` 次数 | **S102** |
| learning 复盘配对 | `budget_block(role=learning)` 之后 30 秒内有没有 `review_failed` | **S104** |
| 判定调用 | `llm_usage.phase` 以 `goal_judging` 开头的次数 | **S105 —— 只展示，不报警** |

## 为什么 `goal_judging` 不报警

只要 RDD 装着，`EntityAgentLoop.setGoal` 在 `GoalSinks.dispatch` 返回 true 时会**主动把内建目标置空**
（`EntityAgentLoop.java:825-829`），内建判定**永远不会跑** —— 这个配置下 S105 是 **N/A**。
拿它报警只会变成常驻噪音（自测第 1 条抓到的就是这个）。

## 窗口的选择会改变结论（实测）

| 窗口 | 样本对 | P90 | 结论 |
|---|---|---|---|
| 最近 60 分钟 | 7 | **1.283** | `HEALTHY` |
| 最近 180 分钟 | 109 | 1.439 | `WARN`（混进了校准前的旧配对） |

**所以判「校准后是否达标」必须用短窗口或 `--since 校准时刻`**，不要用「最近一天」——
那是把校准前后混在一起算。

## 已知局限

- 只读 `context.jsonl` 与 `learner.jsonl`（其它监测文件与本工具无关）；
- 不判断「额度是不是配得合理」，只判断「这半小时的表现是否在区间内」；
- `NEVER_BLOCKED` 是**提示不是错误**：shadow 模式本来就永远不拦，确认这是当前模式即可。
