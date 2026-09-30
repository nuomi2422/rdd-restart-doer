# RDD 自编译 V3 架构改进计划

> 来源：国内大外脑 DeepSeek（P0/P1 实审，spectrum 到 file:行）+ 国外大外脑 GPT（复核 A/B/C）
> 状态：已完成三方回合（DS 审查 → GPT 逐条表态 → GPT 补漏 → GPT 计划）
> 落盘：2026-09-24

## 结论摘要

DS 修的是「RDD 任务链状态机是否正确」；GPT 强调 RDD 下一阶段重点不是扩展任务链，而是补 **Evidence Layer（证据层）+ Mutation Governance（修改治理层）+ Validation Pipeline（验证流水线）** 三层——决定它是「AI 自动写代码」还是「真正的 AI 自我工程循环」。

## A. GPT 对 DS 审查意见逐条表态（全部同意，含独立评级）

| # | 问题 | 同意度 | 优先级 |
|---|------|--------|--------|
| 1 | 资产真相链断裂：usableCounts/activateCurrentFromRegistry 定义未进主循环 | 完全同意 | P0 |
| 2 | 整数校验：usableCounts 只校验 >=0 不校验整数（0.5→0 截断） | 完全同意 | P1/P0 |
| 3 | 自动恢复越权：RECOVERING 自动 resume 与宿主显式契约冲突 | 完全同意 | P0 |
| 4 | 恢复状态污染：RECOVERING 残留 activeExecutionId 幽灵执行 | 完全同意 | P0 |
| 5 | 非法状态接受：ACTIVE+unexpanded 不拒绝 | 完全同意 | P0 |
| 6 | JSON 静默失败：corrupt JSON catch 后 return 永不推进 | 完全同意 | P0 |
| 7 | 恢复预算丢失：retries/stallCounts/gapParked 跨重启失效 | 完全同意 | P0+ |
| 8 | Supervisor 无反馈：applySupervisorDecision 无返回值 | 完全同意 | P0 |
| 9 | Supervisor 孤岛：NEED_MORE_EVIDENCE/DEFER 空分支哑火 | 完全同意 | P0 |
| 10 | AWAITING_SUPERVISOR 无驱动 | 完全同意 | P0 |
| 11 | publish() no-op | 同意（视阶段） | P1→P0 |
| 12 | resumeFromReplanning 全量重置破坏历史事实 | 同意 | P1 |
| 13 | fromJson 不校验 attempts/skipReasons | 同意 | P1 |
| 14 | usableCounts 返回 HashMap 可变 | 部分同意 | P2 |

关键状态约束表（GPT 提出）：
```
ACTIVE:             executionId required
RECOVERING:         executionId must null
AWAITING_SUPERVISOR: executionId optional
ACTIVE && unexpanded  →  CORRUPTED_STATE
```

## B. GPT 补漏：DS 纯源码审查看不见的自编译闭环保级风险

| # | 风险 | 等级 |
|---|------|------|
| B1 | 验证反馈≠真实成功（Semantic Verification Gap）：编译成功+MCP返回success ≠ 游戏行为真成功；需三级验证 Level0编译/Level1加载/Level2世界确认，只有 L2 才能 markSuccess | P0 |
| B2 | MCP 工具返回可信度不足：transportSuccess ≠ worldConfirmed，返回需分层 ToolResult | P0 |
| B3 | 自修改因果链缺失：multiple commits 后无法回答「哪个修改导致现在行为」 | P0 |
| B4 | 自修改权限无限扩大：需 Tier0 配置/Tier1 局部单文件单模块/Tier2 架构（人工确认） | P0 |
| B5 | compile≠release：GENERATED→COMPILED→LOADED→BEHAVIOR_TESTED→PROMOTED 状态流水线 | P0 |
| B6 | 多 Harness（GPT/Claude/DS/Codex）并发修改核心文件冲突 | P1 |
| B7 | 错误经验污染长期记忆（观察 B7→假设→验证后知识，分级入记忆） | P1 |
| B8 | 游戏世界状态漂移（经验 TTL） | P1 |
| B9 | Supervisor 可能优化错误目标（需 System Integrity Supervisor 检查成功率/回滚次数） | P1 |
| B10 | 缺少人工接管窗口（WAITING_HUMAN_APPROVAL） | P1 |

## C. 文件级任务表

### C0. P0（4 条）

**1. 统一资产真相源**
- 文件：`rdd/asset/AssetRegistry.java`、`rdd/runtime/RddRuntime.java`、`rdd/detector/RddDetector.java`、`rdd/task/RddChainFactory.java`
- 改法：AssetRegistry 提供可信资产状态，Runtime 改用 activateCurrentFromRegistry()，移除 Detector 直接 inventory 扫描驱动，新增统一 isValidCount() 拒绝负数/小数/UNKNOWN/INVALID
- 测试：AssetRegistryTest（正常/0/负数/小数/未知状态）；gradle test --tests AssetRegistryTest

**2. 恢复状态机重构**
- 文件：`rdd/runtime/RddRuntime.java`、`rdd/detector/RddDetector.java`、`rdd/state/TaskChainState.java`
- 改法：禁止 Detector 在 RECOVERING 自动 resumeFromRecovering()；状态不变量校验约束非法组合；恢复改 Request→Supervisor→Runtime 显式流程
- 测试：RecoveryStateMachineTest（Detector tick 不自动恢复/非法状态进 CORRUPTED_STATE/Supervisor 确认后才 ACTIVE）

**3. 恢复预算持久化**
- 文件：`rdd/model/TaskChain.java`、`rdd/persistence/TaskChainSerializer.java`
- 改法：持久化 retries/stallCount/gapParked/lastFailureReason；fromJson() 加 schema 校验，损坏 JSON 触发恢复流程而非静默 return
- 测试：TaskChainPersistenceTest（重启后字段保持/非法 JSON 触发 CorruptStateException）

**4. Supervisor 反馈闭环**
- 文件：`rdd/supervisor/SupervisorManager.java`、`rdd/model/SupervisorDecisionResult.java`
- 改法：applySupervisorDecision() 返回 accepted/reason/nextState 对象；补 NEED_MORE_EVIDENCE/DEFER 分支，加 Supervisor 请求队列防 AWAITING_SUPERVISOR 无人推进
- 测试：SupervisorFlowTest（DEFER→WAITING_TIMER / NEED_MORE_EVIDENCE→WAITING_EVIDENCE / 重复 tick 不重复提交）

### C1. P1（5 条）

**5. Evidence Layer（B1/B2 落地）**
- 文件：`rdd/evidence/EvidenceCollector.java`、`rdd/evidence/EvidenceRecord.java`、`rdd/evidence/EvidenceValidator.java`（新增）
- 改法：MCP 通信/工具执行/世界状态分层保存；只有通过世界事实验证的事件才能触发任务完成；记录证据来源/时间/验证项
- 测试：EvidenceValidationTest（MCP 成功但世界未变 → 保持未完成；真实状态变化 → 完成）

**6. 自修改因果链（B3）**
- 文件：`rdd/mutation/MutationRecord.java`、`rdd/mutation/MutationTracker.java`（新增）、`rdd/selfcompile/SelfCompileManager.java`
- 改法：记录版本号/修改文件/触发原因/关联 Bug/验证结果，形成问题→修改→测试→结果可追踪链路
- 测试：MutationTrackerTest（定位导致成功/失败的具体变更）

**7. 验证流水线（B5）**
- 文件：`rdd/selfcompile/ValidationPipeline.java`（新增）、`rdd/selfcompile/DeployManager.java`
- 改法：GENERATED→COMPILED→LOADED→BEHAVIOR_TESTED→PROMOTED；compile success 不再是上线条件
- 测试：ValidationPipelineTest（编译成功但加载失败/加载成功但行为失败均不能 PROMOTED）

**8. 修改权限分级（B4/B10）**
- 文件：`rdd/governance/MutationPolicy.java`、`rdd/governance/MutationPermission.java`（新增）
- 改法：Tier0 配置（自动）/Tier1 单文件单模块（自动）/Tier2 Runtime·状态机·MCP核心（人工或 Supervisor 审批）
- 测试：MutationPolicyTest（配置自动允许/核心进入 WAITING_HUMAN_APPROVAL/非法修改拒绝）

**9. 多 Harness 并发修改锁（B6）**
- 文件：`rdd/mutation/MutationLockManager.java`（新增）、`rdd/harness/AgentSession.java`
- 改法：文件锁：持有者/租约时间/修改上下文，防多 Agent 同时改核心代码互相覆盖
- 测试：MutationLockTest（两 Agent 同时改同文件，仅一个获写权限，另一个等待）

### C2. P2（3 条）

**10. 资产快照（防同任务周期内状态漂移）**
- 文件：`rdd/asset/AssetRegistry.java`、`rdd/model/AssetSnapshot.java`（新增）
- 改法：任务开始时固化资产快照，Runtime/Supervisor/Evidence 用同一份，避免实时查询漂移
- 测试：AssetSnapshotTest（任务中改库存，验证仍基于原始上下文判断）

**11. 事件总线统一（降模块耦合）**
- 文件：`rdd/event/RuntimeEventBus.java`、`rdd/event/RuntimeEvent.java`（新增）`、rdd/runtime/RddRuntime.java`
- 改法：统一事件结构：事件 ID/时间戳/来源模块/关联任务 ID；Monitor/Supervisor/Memory 订阅解耦
- 测试：RuntimeEventBusIntegrationTest（启动/失败/恢复/完成全事件正确发布）

**12. 经验分级（B7 落地）**
- 文件：`rdd/expmem/KnowledgeStore.java`、`rdd/expmem/ExperienceRecord.java`
- 改法：Observation→Hypothesis→Verified Knowledge 三级；只有验证后知识进长期记忆；未验证观察带 TTL 自动过期（B8）
- 测试：ExperienceGradingTest（一次工具失败不直接进长期知识；验证后提升；过期淘汰）

## 实施顺序建议
P0 的 1→2→3→4 是一个干净状态机重建序列（先资产真相源，再恢复语义，再持久化，再 Supervisor 反馈），建议按此顺序单模块落地、每步测试+日志+回滚点。