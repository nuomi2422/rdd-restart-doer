# budget-pairs.js —— 预算「估算 vs 实际」配对统计

## 干什么

把 monitor 里的 `budget_reserve`（占额时的估算）和 `budget_settle`（落地时的实际用量）按
`requestId` 配对，算 `est/actual` 的分布（P50/P90/P95/max），并给出「要把 P90 压到 1.3，
当前 `LIMIT_SAFETY_FACTOR=1.5` 应改成多少」。

这就是 **G4c 开闸前置项 S100** 的测量工具：样本 ≥30 对、校准后 P90 ≤1.3 才允许开闸。

## 为什么需要

G4a/G4b 的估算偏高约 3 倍（`est=61487` / `actual=20154`）。影子期无害——记账用实际值；
**开闸后有害**：配额只有约 1/3 可用，会产生大量「本不该拒」的拒绝。所以校准必须是开闸的前置，
而不是开闸之后的调优。

## 怎么调

```powershell
node budget-pairs.js                                  # 全部历史（含归档 context-*.jsonl）
node budget-pairs.js --since 2026-10-21T00:00:00Z     # 只看某段时间（采样窗口）
node budget-pairs.js --since <A> --until <B>          # 掐一个闭区间（跨配置切换时必须切开算）
node budget-pairs.js --windows                        # 按小时分桶看「额度 → 拒绝率」（S101）
node budget-pairs.js --json                           # 机读
node budget-pairs.js --monitor <monitor 目录>
```

退出码：`0` = 有样本（够不够 30 对不影响退出码）；`2` = 一对都没有；`3` = 环境/用法错。

## 它只认哪种配对

只统计 `budget_settle{status:"charged"}` 的配对。`status=reconciled`（预留过期或跨策略版本）
不代表估算准度，混进来会污染比例分布。

## 三条使用纪律

1. **采样配置必须「不会拒」**：`mode=shadow` + 角色给一个足够大的 `tokensPerWindow`
   （本次用 400000），否则被拒的调用没有预留，样本会偏向小请求。
2. **用 `--since` 掐窗口**：`rejected` 里会混进「人为设小限额做验证」的那些拒绝（例如
   `callsPerWindow=2` 的实机验证），算 S101 拒绝率时必须按时间窗排除，不许一把抓。
3. **样本够之前不许动系数**：`CompactSplit.LIMIT_SAFETY_FACTOR` 同时影响 replay 窗口与压缩闸，
   改它就是改行为，必须随 G4c 一起走完整回归 + 实机。

## 依赖

- Node 18+，无第三方依赖。
- 数据源：`<游戏目录>\config\numen\monitor\context*.jsonl`（主文件 + 归档文件都要扫，
  只扫主文件会假阴性 —— H3 的教训）。
