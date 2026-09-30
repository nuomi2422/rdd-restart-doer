# RDD 任务链 · 本轮验证总结 + 数据流（2026-09-25）

> 用途：①给主人复查“任务链究竟能干什么” ②发给 GPT 外脑讨论。
> 范围：2026-09-24~25 本轮所有已落地改动 + 进游戏实测证据 + 端到端数据流（对着真实源码）。

---

## A. 本轮做了什么（代码 + 提交 + 测试）

| 主题 | 内容 | 提交 | 测试 |
|---|---|---|---|
| AC 三修 | ToolRegistry 3参注册硬失败(不再静默丢schema)、FileAcVersionStore 原子写、AcParamValidator isInteger 扩类型 | `4c176c3a`/`f58215f5` | ac-core 28、api:common 458、plugins:ac 8 |
| P0 完成事实继承 | rdd-core `fact/`(StageKeyNormalizer/GoalLineage/StageFact/SubtaskFact/CompletedFactStore)；TaskChain += `satisfiedStages`（构造+CONFIRM 跳过已达成一级、全达成→COMPLETED、不伪造二级完成、JSON 向后兼容） | `22f6af36`/`bef8e244` | rdd-core +25 测 |
| P0 接线 | `RddFactStore`(rdd-facts/<uuid>.json)；bindCurrent 注入 satisfiedStageKeys；CONFIRM 记阶段事实 | `f599c4f0` | plugins:rdd |
| P1 死亡资产失效 | `AssetRegistry.invalidateByType`；`numen.on(DEATH)` → 背包资产失效+清规划缓存+落盘+监测事件 | `d5341833`/`9e9b5648` | rdd-core +2 测 |
| P1.5 口径统一 | `PlanningAssetSnapshot`(缓存背包为底+注册表真相覆盖，失效移除并记 lost/unknown)；Stage-A/B 提示词+Guard 统一取它 | `8d57bbcd`/`047cdbea` | rdd-core +6 测 |
| 任务链死锁修复 | `RddOptionalFood` 放宽：任意食物(group=food 或 food 物品)默认可跳过(保留 optional=false 否决) | `113e7a03` | plugins:rdd |
| 工具修复 | ①CraftOps hint 扫描带行为判定(模组工作台5~16格不再误报None) ②interact_at 打开工作站GUI 不再谎报“nothing changed” ③interact_at 允许对方块用消耗品(营火烤肉/熔炉/喂动物/堆肥) | `2ed073f5`/`5c34199c` | core 编译 + 根 build |
| 规划知识(数据) | builtin-experience.jsonl +3 条(POLICY)：缺食优先去村庄、安全递进(食物→铁甲→钻石甲)、挖矿走安全通道不进矿洞乱跑；mc-guide.md 校正记录 | 数据文件 | JSON 逐行校验 0 坏(43 行) |
| watchdog | nudge 带“[自变异待处理] queue/requests/mutations(近24h 非终态)”摘要 | 外部脚本 | -DryRun 通过 |

rdd-core 累计 **86 测 0 失败**；plugins:rdd 全绿。

---

## B. 进游戏验证证据（gpt 实例，真实日志/文件）

1. **P1 死亡失效**：日志 `[rdd] 同伴死亡：背包资产失效 16 项`；监测 `rdd.jsonl` 事件 `{"type":"companion_assets_invalidated","invalidatedInventoryEntries":16,"reason":"companion_death"}`。
2. **P1.5 规划口径**：规划请求正文(`supervisor_context`.`context.user`)的“你当前已真实持有”= 死亡后真实背包（钻石装备全无，只有 stone/wooden 工具）；未见旧装备假设。
3. **P0 完成事实**：新代码下第 0 阶段 CONFIRM → `config\numen\rdd-facts\c29c5c40-….json` 生成（`evidence=primary confirmed` + 二级留档）；主人重下 /goal 已亲见跳过行为。
4. **死锁现场**：链卡在 `primary-c29c5c40-1-s7 = {asset_key:minecraft:cooked_porkchop, minimum:2} [FAILED]`；AI 请求 `rdd_skip_optional` 被旧策略拒绝 → 本轮已放宽。
5. **AI 自诊(工具侧)**：interact_at 放熔炉“nothing visibly changed”（7次仅1成）；craft 报“None within 16 blocks”而 goto/build 说台就在附近 → 两处已修。
6. **自变异请求**：游戏内 `selfcompile_request` 落盘 `config\numen\selfcompile\mutations\<id>\manifest.json`；最新一条正是“拿食物右键营火被拒”——与本轮第③修复同一根因。

---

## C. 任务链端到端数据流（对着真实源码）

### C0. 输入与规划（Stage-A）
```
主人 /goal X
  → GoalSinks sink (RddPlugin.setup 注册)
  → RddPlugin.beginPlanning (DECOMPOSING.add, 清 RddGoalDriver)
  → RddStagePlanner.planStages:
        planningPrompt(目标, planningSnapshot(真实资产), 世界资产)  + 经验知识 attach
        → LLM 工具 plan_stages（2~12 个一级阶段主题 + 可选 wait_for 跨级资产门）
  → RddPlanGuard.filterStages（未获要求的可选分支丢弃）
  → RddChainFactory.fromStages → Goal（N 个"未展开"一级, id=primary-<uuid8>-i）
  → RddPlugin.bindCurrent:
        new TaskChain(goal, facts(uuid).satisfiedStageKeys(goal))
        （已达成阶段键命中的一级 → 跳过；全命中→COMPLETED）
        + RddRuntime(chain, AssetRegistry) + saveRuntimes()
```
- 备选回落：Stage-A 失败/空 → `RddDecomposer.decompose`(单遍) → `RddChainFactory.fromSpec/fromObjective`（占位链，目标不被吞）。

### C1. 懒展开（Stage-B，一级到达未展开时）
```
RddDetector(每秒) 发现 currentPrimary 未展开
  → RddPlugin.reportExpansionNeeded(de-dup)
  → RddGoalDriver.needExpansion（预算/冷却/in-flight 门 RddExpansionPolicy）
  → RddDecomposer.decomposeSpecs(主题, attempt, 已完成阶段)
        decompositionPrompt(真实资产快照) + 失败重试提示 + 经验知识
        → LLM 工具 decompose_goal（1~8 个二级: condition(asset_key/group/world-fact) + 可选 body）
  → RddPlanGuard.filterSubtasks（可选升级未获要求→丢；已持有→复用）
  → RddRuntime.expandCurrentPrimary(注入二级, 全 PENDING)
```
- 失败 §9：≤3 次带上下文重试 → COOLDOWN → 预算耗尽 escalate=停靠（绝不塞占位假二级/不伪造完成）。

### C2. 依赖门与激活
```
currentPrimaryReady: 看一级 wait_for
  → activateCurrentWithRegistry → AssetRegistry.usableCounts()
        （只算 status==OBSERVED 且有 inventory_scan 计数的条目；UNKNOWN/INVALID 不满足门）
  → 满足: ACTIVE + 当前二级 RUNNING；不满足: WAITING(等资产)
```

### C3. 执行与完成判定（每 tick）
```
RddDetector 观测真实世界
  → 硬条件: HardCodedEvaluator(背包)/WorldFactConditions(advancement/structure/entity_killed/base)
  → 满足 → RddRuntime.applyHardCoded → TaskChain: 二级 COMPLETED → advanceOrAwait
  → 该一级二级全完成 → AWAITING_SUPERVISOR
  → CONFIRM → 记阶段事实(CompletedFactStore→rdd-facts) → 推进下一个"未达成一级"（跳过已满足）
        全阶段达成 → primaryStatus=COMPLETED
```
- 失败/卡死：`retries` 计数 → `handleSubtaskFailure`(预算内重跑；耗尽→可选食物自动跳过[本轮放宽] / escalate)；stall 检测→`nudge` 注入 AI。

### C4. 资产数据流（P1/P1.5）
```
背包：RddDetector 每 1s cacheInventory(LAST_INVENTORY) + 每 5s populateAssets→AssetRegistry(inventory_scan, 缺者补0)
世界：RddWorldAssetObserver 每 30s → AssetRegistry(world_base/machine/structure/entity)
  → PlanningAssetSnapshot.from(缓存背包, 注册表):
        注册表 OBSERVED 覆盖计数；INVALID/UNKNOWN 移除并记 lost/unknown；world_ 不参与背包计数
  → Stage-A/B 提示词 + PlanGuard 统一取它
死亡：numen.on(DEATH) → invalidateByType("inventory_scan") + 清 LAST_INVENTORY + saveAssets + 事件 companion_assets_invalidated
```

### C5. 持久化与监测
```
持久化：rdd-tasks/<uuid>.json(TaskChain.toJson/fromJson) · rdd-facts/<uuid>.json(CompletedFactStore) · rdd-assets/<uuid>.json(仅 world_)
重启：restoreRuntimes → TaskChain.fromJson → 在途执行归一为 RECOVERING
监测：RddMonitor.publish → config/numen/monitor/{rdd,ai,context,events,state,tools}.jsonl → 监测台 127.0.0.1:8776
```

### C6. 旁路
- **AC 原子工具**：plugins:ac，ac_execute 桥接；ac-library.json 持久化（本轮修原子写/参数校验）。
- **自变异**：游戏内 `selfcompile_request` → `config\numen\selfcompile\mutations\<id>\`（manifest/source/classes/reports）；外部 harness 队列 `rdd-selfcompile\scripts\selfcompile-queue.json` + `requests\req-*.json`；watchdog nudge 现带待处理摘要。

---

## D. 已知边界 / 未做
- **REPLANNING 状态机出口在生产不触发**（REPLAN/REJECT 仅测试构造）——“重规划”实际走 `/goal 重绑 + Stage-A/B 重分解`。
- P0 事实只在“新代码后 CONFIRM 的阶段”积累；旧链已完成阶段无事实，不会被跳过。
- 近似血缘(bigram 0.6)仍偏宽（GPT/DS 建议收紧为“同血缘+全等”），P0 未改。
- `forget/invalidateFact`（历史完成但当前不可用）未做。
- `RiskGate`（下界/末地保命硬门）未做=GPT 定的最高优先 P1。
- 监督恢复环(FailureClassifier/RecoveryPolicy)、ReplanContextBuilder、Proposal/Merge、自变异 Proposal 流水线：均未做。

## E. 给 GPT 的讨论问题
1. 数据流是否有断点/黑箱（主人想确认“任务链究竟能干什么”）。
2. 死锁修复(食物默认可跳)是否会引入“该吃的不吃”风险，需要什么下限？
3. 工具修复(消耗品对方块放行)是否够稳，还需覆盖哪些方块/实体交互？
4. 下一条主线是否就按 RiskGate(AssetTruth+保命硬门) 推进。
