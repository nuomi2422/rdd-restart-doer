# 送审包 · 第一批收尾（2026-09-30 01:05）

> 交给**贵模型**审。审什么：**架构成色、隐性风险、该拆什么、该删什么**。
> 同目录有 `diff-vs-redline-95938d25.patch`（126 KB 全量 diff）+ 8 个新文件全文。

---

## 0. 一句话背景

RDD（Numen 的 Minecraft 自主代理）回退到 `95938d25`（"第一批红线基线"）后，做了三件事：
**士兵↔军师协商**、**卡死检测**、**暂停(PAUSE)** + 顺带修的生命周期工具。
现在要收尾：审代码、拆、删、清理。

---

## 1. 边界：哪些**不许**动（红线）

| 红线 | 内容 | 破线判据 |
|---|---|---|
| **RL-1 / RL-9** | **单驾驶员**：规划/监督层**不得**自动提交身体工具 | 日志出现「已提交身体任务」而 `rdd-bodydispatch.flag` 不存在 |
| **RL-6** | 死亡走修复链，不伪装 LOST | 资产被判 LOST 但没经 `RddRepairDispatch` |
| **RL-7** | 死亡支线"先捡包后取备用" | 支线顺序反了 |
| **RL-3** | 风险门 + 前置事实 | 未授权 Nether 级放行 |
| 主链路 | `规划→判定→执行→打勾→下一级` | 逐字未变，本批**全是新增旁路** |

**本批改动的自证**：22 个文件 `+756 / -31`，其中 `-31` 全在测试与 `TaskNegotiation.kinds()`；
主链路 `markStalled`/`markFailed`/`markCompleted`/`requestReplan` 的**转移语义一字未动**。

---

## 2. 改了什么（按"能不能删"分组）

### A 组 · 状态机扩展（**最需要你判断架构成色的**）
| 文件 | 改动 | 我的理由 | 我的疑虑 |
|---|---|---|---|
| `rdd-core/.../api/SubtaskStatus.java` | +`PAUSED` | SKIPPED=放弃、FAILED=做不到、PAUSED=先放着，三者语义必须分开 | **枚举值膨胀**。PAUSED 与 COOLDOWN/INVALIDATED 的边界是否清晰？ |
| `rdd-core/.../core/TaskChain.java` | +106 行 | `pauseSubtask`/`resumeFromPaused`/`isPaused`/`pauseReasonsView` + 持久化对称点 | **`pauseReasons` 与 `skipReasons` 两套几乎重复**。是否该抽 `OptionalReason` 抽象？ |
| `rdd-core/.../fail/TaskNegotiation.java` | +`Kind.PAUSE` | 士兵的"我做不到"要与"换个做法"(COUNTER) 区分 | `isPauseRequest()` 与 `needsSupervisorAction()` **两个布尔表达一个四态枚举**，迟早有人漏判 |
| `rdd-core/.../core/RddRuntime.java` | +30 行 暂停计时 | 复评闸需要"停了多久" | **用 `System.nanoTime()` 当游戏时间**（`currentGameTime()` 自己算）——与 RDD 别处的 `RddInstrumentation.currentGameTimeTicks()` 不一致 |

### B 组 · 监督/监察
| 文件 | 改动 | 我的疑虑 |
|---|---|---|
| `plugins/rdd/.../RddStallPolicy.java` | +43 `llmIdle`/`shouldNudgeLlmIdle`（阈值 10） | 阈值是启发式；GLM 已证"空转 35.6s < 有效 44.0s"，**任何纯时间阈值都区分不了**。真正的判据在响应内容（`:ai` 层），本批未做 |
| `plugins/rdd/.../RddStallWatcher.java` | +21 提前拍醒 | 文案越来越长（8 行），**是不是该抽成常量/模板**？ |
| `rdd-core/.../RddDeathLedger.java` | **新增 200 行** | 见 §3 |

### C 组 · 生命周期工具
| 文件 | 改动 | 我的疑虑 |
|---|---|---|
| `core/.../UsePortal*.java`（3 个新文件） | 走进门块 + 等原版传送 | `MIN_STAND_OFF`/`ENTER_TIMEOUT_TICKS`/`VANILLA_TELEPORT_TICKS` 三个魔数；**只测了 nether，没测 end** |
| `plugins/rdd/.../RddDebugKillTool.java` | `hurt(genericKill,MAX)` → `entity.kill()` | 旧写法**静默说谎**（回成功但没死）。新写法如实回报 `alive`。还有别的"调试工具说谎"吗？ |

---

## 3. 我自己最不满意的三处（请重点看）

### ① `RddDeathLedger` 是纯增量，**没接线到消费侧**
只写了 200 行 + 8 条单测，`render()` 产出的文本进了 `repair_task_dispatched` 事件和 nudge，
但**没有一个查询接口回答"这次死亡的东西还在吗"**给规划器用。
→ 是不是应该并进 `AssetRegistry` 而不是独立一个类？或者干脆砍掉、只在事件里带 `expiresAt` 就够？

### ② `RddDetector` 正在变成上帝类
本批 +90 行。`handlePaused` 塞进 `tickRuntime` 主流程，而它已经 900+ 行、承载了
资产观测/协商/暂停/STALLED/FAILED/重试/资产失效。
→ **该不该把"状态机推进"整体抽成策略对象？** 我没敢动（RL 红线都盯着这个文件）。

### ③ PAUSE 的两个布尔判据
见 §2-A 组最后一行。

---

## 4. 已验 / 未验（**请按这个分量审**）

### ✅ 实机验证过
- PAUSE 落地（**两次**实战触发，含军师随即改单 `grass_block→dirt` = 通融）
- 卡死检测 `llm_idle_stall` 阈值 10s 提前 5 秒预警且改变行为
- 协商通道端到端（RUNNING 时 COUNTER → REPLANNING → 规划器逐条采纳）
- OpenCode Go 订阅接入（`x-opencode-session` + 自定义 UA）

### ❌ 未验（**别当已完成**）
- `use_portal` **v2 完全未验**（v1 已实机证明是错的：门不能被 USE）
- PAUSE 的"条件满足自动恢复"分支未验
- 死亡台账的多次死亡倒计时未验
- 铁甲/农田/粮仓/死亡全流程 —— 用户 01:00 决定**不验了**

### 回归
`core/common 388` ｜ `ai 109` ｜ `rdd-core 245` ｜ `plugins/rdd 103` = **845 / 0 失败**

---

## 5. 明确要你回答的 5 个问题

1. **`RddDeathLedger` 该留、该并、还是该砍？**（我倾向砍到只剩事件字段）
2. **`RddDetector` 要不要拆？** 拆的话边界划在哪、怎么不破 RL 红线？
3. **`SubtaskStatus` 再加值是否已经过头？** 9 个值里 `COOLDOWN`/`INVALIDATED`/`PAUSED` 有人用吗？
4. **`TaskChain` 的 `skipReasons`/`pauseReasons` 该不该合并抽象？**
5. **`RddRuntime.currentGameTime()` 用 `nanoTime` 与 `RddInstrumentation.currentGameTimeTicks()` 不一致 —— 该统一到哪个？**

---

## 6. 顺带：工作区有 30 个垃圾探针文件该删
`.apply3-evidence.txt` / `.brain-recon.txt` / `.cdp-connect.txt` / `.jdk21-locate2.txt` /
`.stop-loss.txt` … 共 30 个，还有 `plugins/learner/`（回退后残留的 build 目录）
与 `plugins/rdd-feeds-ds.js`、`docs/data-flow-review.md`（**归属不明，等你判**）。
→ 这些是"临时探针落盘忘了清"，**请审稿时一并给出删/留判断**。
