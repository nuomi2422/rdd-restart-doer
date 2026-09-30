# GPT 外脑意见 — RDD 资产语义层（2026-09-25）

## 背景（我们问的）

RDD 任务链三个叠加问题：
1. 重规划资产快照被失效注册表清空（死亡后重规划倒退铁器时代）
2. 计划方向反了：有村庄应先进村庄认领据点，而非野外自建
3. 资产转移（小麦→面包后认为小麦没了）+ 无时间成本/效率权衡（种田不该进主线、不该等作物）

## GPT 结论（原文要点）

> 这三个问题本质不是三个独立 bug，而是同一个缺陷：
> **RDD 现在有"资产存在性"，但缺少"资产用途和决策价值"。**
> 目前系统知道：我有多少铁 / 我有多少钻石 / 我去过某个位置。
> 但不知道：这个东西为什么存在 / 丢了之后影响哪个阶段 / 这个基地是不是我的恢复点 / 这个食物是不是未来 10 个任务的储备。
> 所以需要补"资产语义层"，但**不需要推翻 TaskChain 架构**。

### 问题1：失效 ≠ 不存在
- 现在 ASSET 三态（OBSERVED/UNKNOWN/INVALID）不够；应区分 **CURRENT / LOST / UNKNOWN / DESTROYED**。
- 死亡不是 `DiamondArmor -> INVALID`，而是 `current=false; historical=true; state=LOST; lastKnownLocation=base01; purpose=backup_equipment`。
- 最小改法：**不动 AssetRegistry 核心**，新增 `AssetHistory`（assetId / state / purpose / lastKnownPos / lastSeenTime）；死亡 = invalidate() + recordLost()；Planner 输入从"当前资产"改"当前资产 + 历史恢复资产"。
- 提示词增加："你当前没有钻石甲，但历史记录显示基地A有备用钻石甲x2/食物箱/附魔台——优先判断是否可恢复。"
- 定性：**资产模型增强 P2**，非架构级。

### 问题2：村庄应从 location 资产升级为 semantic asset
- VillageNode：position / resources{food,crop,chest,villager,iron_golem} / visited / scanned / securityScore / purpose=early_base。
- 最小改法：扩 `RddWorldAssetObserver` 加 `VillageScanner`，输出 `{type:village,scanned:true,resources:{...}}`；再配经验规则 `IF early_game AND village exists THEN prefer establish temporary base`——**不要让 LLM 自己悟**。
- 定性：**World Asset Scanner 增强**，非架构级。

### 问题3（最重要）：资产派生 + 时间成本/效率
- 现在资产只有"有什么"，没有"价值"。
- 应增加 **Asset Utility**：purpose / utility / cost / dependency / decay。
  - 钻石甲：purpose=combat_survival, utility=high, cost=expensive, dependency=diamond+enchant
  - 食物：purpose=survival_budget, utility=medium, decay=time
  - 基地：purpose=recovery_point, utility=very_high_after_death
- Planner 不直接选任务，先算：`TaskValue = progress_gain - time_cost - risk + future_reuse`
- 最小改法：新增 `AssetPurpose`（独立于 AssetEntry：AssetEntry 是事实，Purpose 是解释），Planner 输入增加"asset utility summary"。
- 定性：**接近架构升级，但不推翻**；属规划层增强。

## GPT 给的优先级
1. **P2.1 资产历史/恢复语义** → `Lost != Gone`，死亡后不变智障
2. **P2.2 RiskGate + AssetPurpose** → 为什么要提前准备
3. **P2.3 村庄节点化** → 开局效率
4. **P2.4 时间成本评分** → 长期自主优化

最终形态：Planner 输入 = 目标 + 当前资产 + 历史资产 + 风险 + 经验 + 时间成本 + 环境 → 选择策略 → 生成 TaskChain。
TaskChain 继续当执行器。

> **"这比给 LLM 塞更多经验有效，因为它改变的是'AI 看到世界的方式'。"**

## 我们的落地判断
- 与 GPT 方向一致；我们已先行改了 `PlanningAssetSnapshot`（INVALID/UNKNOWN 只提示不清空）+ 死亡不再清空缓存（GPT 的"Lost≠Gone"的最小版）。
- 下一步按 GPT 排序：P2.1 AssetHistory（含 purpose/lastKnownPos）→ P2.2 AssetPurpose → P2.3 VillageNode → P2.4 时间成本评分。
- P5（SelfCompile）暂缓，本主题优先。
