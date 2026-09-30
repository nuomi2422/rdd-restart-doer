# GPT 对“本轮验证总结+任务链数据流”的回应（2026-09-25）

来源：固化会话 https://chatgpt.com/c/6ab526f0-8e10-83ec-9720-0dc8c1d961a6

## 1) 数据流有无断点/黑箱 → 主链闭环，但有三个关键黑箱
- **黑箱A 规划动机未结构化保存**：LLM 产生阶段，但“为什么这么规划”（如进下界需抗火/缺药水）只在 prompt 过程里，不进 TaskChain 数据；重规划只知道“要进下界”，不知“当初为什么”。建议加 `StageMetadata`（附加说明层，不替代 TaskChain）。
- **黑箱B 失败后无真正恢复决策层**：现在 FAILED→retry→耗尽→escalate，但 escalate 后缺“为什么失败/该换工具/换路线/重规划/修代码”。建议 `FailureEvent→FailureClassifier→RecoveryPolicy→Retry/Replan/SelfCompile`。
- **黑箱C 资产有状态无用途**：知道 `diamond_armor:2`，但不知“1套在用/1套死亡备用”。建议 `AssetPurpose`（role: backup_recovery 等）。

## 2) 食物默认可跳是否需要下限 → 需要
- 修复方向对（解决死锁），但不能简单全部 optional，否则会出现“缺食→继续矿洞/战斗→死亡”。
- 升级为 `FoodRequirementPolicy`，按 `RiskLevel` 动态：普通可继续；矿洞/下界/末地必须满足最低储备。**应与 RiskGate 共用。**

## 3) 消耗品对方块放行 → 解决明显错误，但长期别堆 if
- 不建议继续 `if 熔炉/营火/酿造台…`，应抽象 `UseActionResolver`（目标类型+物品类型+动作 统一动作模型）。
- 方块类需覆盖：熔炉/高炉/烟熏炉/营火/灵魂营火/酿造台/工作台/铁砧/附魔台/容器；实体类：村民/动物/怪物/玩家；空气使用：药水/食物/弓箭。重点是一致模型，不是数量。

## 4) 下一主线 → 是 RiskGate，但别单独做
- 建议 **RiskGate + Requirement 系统 + ReplanContext 一起推进**。RiskGate 不能凭空知道“什么危险/需要什么/缺什么”，需 资产(当前有什么)+阶段(准备做什么)+经验(类似历史)。
- 结构：`Stage → RiskEvaluator → (允许执行 | 生成准备任务)`；例：进下界→发现钻石甲/抗火药水/备用装备不足→禁止进入+追加准备任务（做第二套装备/抗火药水/建临时基地）。硬约束由代码执行，不靠 LLM 记规则。

## GPT 最终排序
P0 完成事实继承 ✅ · P1 资产真相 ✅
→ **P2 RiskGate + Requirement 系统 ★★★★★**
→ P3 Failure Recovery Loop ★★★★☆
→ P4 ReplanContext ★★★★☆
→ P5 SelfCompile 增强 ★★★☆☆（作 Recovery 最后一级，不抢主线）

一句话：现在最缺的不是“AI 会不会规划”，而是“AI 规划前有没有可靠世界状态、有没有不能违反的生存规则”——正是 RiskGate 要补的。
