# GPT 讨论裁决：P2 切分（在真实代码上补语义层/决策层）（2026-09-25）

来源：固化会话 https://chatgpt.com/c/6ab526f0-8e10-83ec-9720-0dc8c1d961a6
原则：**不新增第二套 Scanner/Experience/Failure 系统，只在已有能力上补“语义层+决策层”。**

## 三问裁决
1) **World Asset Scanner**：✅ 扩展 `RddWorldAssetObserver`，不新建扫描器（否则出现 AssetRegistry/VillageRegistry/ResourceRegistry 多真相源）。
   - village 从 `location` 升级为节点：`{kind:village, position, state:DISCOVERED|SCANNED, resources:{food/crops/chest/books/villagers/iron_source}}`；发现=DISCOVERED，由 TaskChain 生成“Scan Village”任务，完成=SCANNED，以后不重复扫。
2) **AssetPurpose 放哪**：✅ **单独映射层**（`AssetPurposeStore` / `AssetRoleStore`），**不要污染 AssetEntry**（事实 vs 规划语义，生命周期不同；也不破坏 rdd-assets 持久化格式）。
   - 例：`{assetType:diamond_chestplate, roles:[{combat,reserved:1},{death_recovery,reserved:2}]}`；死亡时问“有没有 recovery role 的甲”。
3) **Failure Diagnosis**：✅ **代码先硬分类，AI 只负责 REPAIR/REPLAN 方案生成**。出口：RECOVER(死亡+有备用+有基地坐标→自动 RecoveryTask) / REPAIR(材料/路线/工具→交 Planner 补任务) / REPLAN(目标性破坏才重规划) / SELF_COMPILE(确定代码问题→mutation pipeline)。
   - **关键补丁**：FailureEvent→Decision→`applySupervisorDecision(REPLAN)`，这才给现有休眠的 REPLANNING 出口接上活触发器。

## GPT 调整后的 P2 顺序
- **P2.0 FailureEvent / RecoveryDecision 数据模型**（后续都依赖）
- **P2.1 AssetPurpose + ResourceBudget**
- **P2.2 RiskGate**（接 AssetPurpose + 经验 + StageMetadata → 允许/阻止/追加准备任务）
- **P2.3 Village/World 扩展**（依赖资产语义）
- **P2.4 ReplanContextBuilder**（汇总：失败原因+资产状态+完成事实+风险+经验 → Planner）

## 一句话
RDD 缺的不是更多任务节点，而是三个“脑区”：
`AssetRegistry`=世界知道有什么 · `AssetPurpose/RiskGate`=知道为什么重要 · `FailureDiagnosis/ReplanContext`=出问题知道还能不能救。
补完才从“任务执行器”变“生存型 Agent”。
