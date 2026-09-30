# 外脑审稿记录 · 2026-09-28 晚 · commit f4286d7e（执行层四修）

> 通道：codex（gpt-6-astra，按用户「省着点」只花一次调用）；范围：`git review --commit f4286d7e`
> 审稿人声明：只做源码追踪与内存态转移检查，**未跑 Gradle、未跑 Minecraft 集成测试**。
> 处置原则：外脑意见当参考不当真理 —— 下面每条都回真实源码核过，核不上的不采纳。

## 审稿提出的 4 条 → 逐条核实与处置

### [P1] 清理窗口压过救命反射（会致死）— **已核实成立，已修**
> 原文：`MLGChain.java:164-169`。若水在摔落后变得够不着，`cleanupTicks > 0` 让 `canRun()`
> 再为真 200 刻。`NumenCore.registerReflexes()` 把 MLG 注册在最前，`TaskSelector.select()`
> 取第一个能跑的，所以这个"低优先级清理"会压掉换气、窒息、岩浆、自卫约十秒。
> `return RUNNING` 并不会让路。快窗口到期后应把清理排到紧急反射之下。

**核实（全部对上）**：
- `api/common/.../task/TaskSelector.java:36-44` —— 遍历 reflexes，`reflex.canRun()` 为真即 `return`，**后面的全不看**。属实。
- `core/common/.../NumenCore.java:70-90` `registerReflexes()` —— 注册号 `MLG=10`、`LavaEscape=12`、
  `Suffocation=15`、`Breath=20`、`MobDefense=30`、`Unstuck=50`，注释明写"注册号小的先问"。属实，
  **且比审稿说的更重**：不只是换气，是四条全被压。
- 反向确认这个性质是**改动前就有的**（快窗口期间同样占身体），但我把窗口从 20 刻拉到 200 刻，
  把它从"顺手收一下"放大成了"一条反射压着救命反射十秒"。**这是我引入的回归。**

**修法**：新增纯判据 `TempResourceRules.cleanupMayYield(deadOrDying, inLava, inWall, drowning)`，
`MLGChain.canRun()` 在**清理阶段**（`reclaimTicks == 0`）必须让路；快窗口行为不变（仍属自救本身）。
`isInLava()` / `isInWall()` / `SurvivalDecisions.breathTriggered(...)` 三条都是现成便宜判据。
配 6 条单测（平安让行 / 让岩浆 / 让窒息 / 让换气 / 让死亡 / 一条就够）。

### [P2] 桶没了会留下永远没人销的挂账 — **已核实成立，已修**
> 原文：`MLGChain.java:299-301`。放完水后最后一个空桶被拿走，`reclaiming()` 使 `canRun()` 为假，
> 调度器调 `stop()`；该分支保留 200 刻预算，但只有 `tick()` 会递减或报放弃 —— 两者都不会发生。
> 挂账会在将来某个刻桶回来了时复活，绕过 `ABANDON_NO_BUCKET`。

**核实**：属实。`tick()` 是唯一递减 `cleanupTicks` 的地方，而 `canRun()==false` 时链根本不被选中。

**修法**：`stop()` 改成三路闭环 —— 水没了 → 自然结清销账；**没桶可装 → 报一笔"收不回来"并销账**；
水在且桶在 → 才留账进清理窗口。顺带给审稿问的"会不会无限续期"一个收敛论证：
`stop()` 只在 `cleanupTicks <= 0` 时发放，否则**每次抢占扣一格**，所以同一次放置发放的预算恒 ≤ 200，
耗尽即 `closeLedger()` 销账。配单测 `cleanupBudgetIsGrantedAtMostOncePerPlacement` 固化这个论证。
（该测试我第一版写错了模型——它假设预算耗尽后还能再发额度，可那时账已经销了。已按真实模型重写。）

### [P2] 超时/取消时 `all_picked_up` 误报 true — **已核实成立，已修**
> 原文：`CollectItemsCompanionTask.java:245-248`。若在走向第一个掉落物时超时或被取消，
> 三个缺口计数全为 0，`TaskSlot` 仍会组出结果，`cleanup()` 丢掉待办目标，
> 于是 `all_picked_up=true` 而掉落物还在地上。应额外要求"确实扫到了正常结束"。

**核实**：属实，且这正是本批要治的同一类病（"扫完了"被读成"拿到了"）——审稿抓得很准。
`r.markReachedEnd()` 只在 `tickScan()` 找不到候选时才打，超时/取消走不到那里。

**修法**：`CollectDecisions.sweepComplete` 加 `reachedEnd` 首参；记录侧加 `reachedEnd` 字段 +
`markReachedEnd()`；配单测 `notReachedEndIsNeverComplete`。

### [P2] 软方块记的是支撑方块而非真正落点 — **已核实成立，已修**
> 原文：`MLGChain.java:244-245`。干草/史莱姆放置在实心地面之上时，`ground` 是射线打到的**支撑方块**，
> 而 `Interaction.useBlock()` 是贴被点面放置的，通常落在 `ground.above()`。记 `ground`
> 等于给后续收尾指错坐标。

**核实**：属实。`aim` 的 blockPos 就是 `ground`（`clutch()` 里已断言 `aim.getBlockPos().equals(ground)`），
而 `BlockItem.place` 对不可替换的方块贴面放置 → 落点是 `relative(aim.getDirection())`。

**修法**：新增 `softBlockLandsAt()`（可替换则就地、否则贴面，与原版同一算法），在**点之前**算好；
点完再用 `softPlacedOk()` 回读那一格确认真的放上去了，日记里坐标才说得肯定。
（编译时踩到 `BlockState.is(Item)` 不存在，得用 `is(Blocks.HAY_BLOCK)`。）

## 未被采纳 / 存疑
- 审稿没有回答我原本想问的 Reflex 实例生命周期（`episodesInWindow` 是实例字段，会不会随任务重建而归零），
  但它的四条已足够说明这批不能收。`BreathChain` 计数器的生命周期问题**留作下一批**单独查证。

## 回归（修完四条后）
core/common **381**（373→381，+8）｜rdd-core **191**（不变）｜plugins/rdd **99**（不变）｜**0 失败**，合计 **671**。
编译期修掉 2 个错：`FluidTags` 少 import；`BlockState.is(Item)` 应为 `is(Block)`。
