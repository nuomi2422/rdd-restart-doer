# GPT 组长 · 第三轮裁决（2026-09-24）

来源：固化会话 https://chatgpt.com/c/6ab526f0-8e10-83ec-9720-0dc8c1d961a6
性质：对 P0/P1 落地的收紧意见 + 用户三议题裁决 + 优先级重排

## 一、P0 收紧（对 DS 意见的表态）
1. 粒度：**不替换 StageFact**，改为在其下挂 `ConditionFact[]`（StageFact=“完成了吗”，ConditionFact=“为什么认为完成”，如 diamond_armor>=2 / fire_resistance_potion>=3 / safe_portal=true）。
2. 近似匹配：**同意 DS**，P0 收紧为**仅允许 goal lineage 完全一致**（或人工/AI 显式确认迁移），**关闭自动 bigram 继承**；跨目标继承留给以后 GoalFamily。
3. forget → 改为 **invalidateFact**：不删历史，标记 `historicalCompleted=true / currentValid=false`（基地被摧毁 ≠ 没建过），与资产层一致。
4. 全阶段命中→COMPLETED：补明确转换 `ACTIVE→COMPLETING→COMPLETED`；COMPLETED 后**禁止 resume/expand/retry**，除非新 goal instance。

## 二、议题1 高风险维度保命前置 —— 优先级最高 ★★★★★
新增 `rdd-core/policy/RiskGate`（执行前检查，非规划器）：只回答 允许/不允许 + 缺什么。
规则按维度硬编码，例：进下界要求 diamond_armor≥2、fire_resistance_potion≥3、backup_chest required…
拒绝时：生成补充任务（做第二套钻石甲 / 抗火药水）后再放行。**不靠 LLM 自觉。**

## 三、议题2 监督连续性 ★★★★☆
新增 Supervisor Recovery Loop：`FailureEvent → FailureClassifier → RecoveryPolicy → Replan/Retry/SelfCompile`。
分类：A 资源问题→重新规划资源获取；B 路径问题→换策略/扩大搜索；C 工具问题→修工具调用；D 软件问题→进入 SelfCompile。
关键：**不要“遇任何问题让 Supervisor 重想”**（会停摆），要按类分诊。

## 四、议题3 自变异 AI 产出接回主链路
不让另一个 AI 直接改主工程；走变更包：`AI生成变更包 → Change Proposal → Harness验证 → Merge → Runtime加载`。
落盘：`rdd-selfcompile/proposals/<date>-<id>.json`（problem/files/patch/tests/verification）。
状态机：`PROPOSED→COMPILED→TESTED→VERIFIED→ACTIVE`。禁止“AI写码直接替换 jar”。

## 五、优先级重排（GPT 定）
P0 完成事实层（已完成） → **P1 AssetTruth + RiskGate（合并做）** → P2 Supervisor Recovery Loop → P3 ReplanContext → P4 SelfCompile 闭环。
只做一个：**P1 = AssetTruth + RiskGate**。理由：当前最大能力缺口不是“会不会规划”，而是“规划时是否知道真实世界、是否知道哪些风险不能赌”。
