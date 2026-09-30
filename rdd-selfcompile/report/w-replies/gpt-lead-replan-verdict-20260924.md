# GPT 组长裁决 · 重规划方向（2026-09-24）

来源：固化会话 https://chatgpt.com/c/6ab526f0-8e10-83ec-9720-0dc8c1d961a6
性质：初步裁决（用户将再投新架构想法，此为基准）

## 核心判断
旧重规划最大问题不是分级不够多，而是「规划输入不完整 + 状态重置破坏事实」：
1. resumeFromReplanning() 把本级二级全量重置 PENDING → DONE 节点失去历史事实 → 已完成任务被重规划/重复执行。
2. 资产丢失时重规划没拿到真实资产状态，沿用旧假设 → 规划层与资产真相层脱节。

## 方向：从「节点重规划」升级为「基于世界状态快照的增量重规划」(状态重规划)

事件发生 → 收集世界快照（资产/任务状态/已完成节点/失败原因/环境）→ 生成当前真实状态模型 → AI 基于真实状态重规划剩余目标 → 合并旧历史(不覆盖事实) → 继续执行

### 1. DONE 节点 = 不可侵犯事实
REPLAN 只处理 PENDING / RUNNING失败 / BLOCKED；DONE 保留。
TaskGraph: A DONE, B DONE, C LOST_ASSET, D PENDING → 输出 A/保留 B/保留 C/修复 D/新路径 E/新路径

### 2. 新增 ReplanContextBuilder
职责：收集 TaskChainState + AssetRegistry + InventorySnapshot + WorldSnapshot + FailureEvent + Tool 状态 → 输出 ReplanContext.json 给 AI（含 goal/completed/lost_assets/available_assets/failure/constraints[do_not_repeat_completed]）

### 3. Planner 输出 ReplanProposal（preserve/repair/append），不直接覆盖 TaskChain
由 Runtime 合并 & 验证（状态真实性、DONE 保护、合法性检查）。
AI 负责推理/路径设计/替代方案；Runtime 负责事实。

## P0 优先级
1. 修 resumeFromReplanning() 不允许清空 DONE
2. 建 ReplanContextBuilder
3. 建资产真相输入接口
4. Planner 输出 Proposal 不直接改 TaskChain

## 给我的审查边界提醒（等用户投新架构时重点审查）
状态源、规划权限、合并机制