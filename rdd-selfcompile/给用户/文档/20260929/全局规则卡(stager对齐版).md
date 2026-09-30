# opencode · RDD 工作规则（2026-09-29 · stager 对齐版）

> **本文件是索引，不是教材。** 细则全在 `E:\新建文件夹\rdd架构\自编译统一版\`，按需查，别通读。
> **可执行的那一份**在工作区 `E:\restart developing doer\AGENTS.md`（B 版）—— 阶段/门禁/必读/判据都在那。
> 本文件**不得与它矛盾**；有冲突以工作区 B 版为准。
> 备份：`AGENTS.backup\AGENTS-20260929-230609-pre-stager-align.md`（本次改之前）。

---

## 0 · 开工前（3 条，硬的）

### 0.0 ★ 第一动作：开 stage（不许跳过）

```powershell
node "E:\restart developing doer\stager\bin\stager.js" start "<用户原话目标>" --actor "<你的名字>"
```

**没开 stage 就动手 = 这一轮作废。** 开完 `stager ctx` 会自动把
「当前阶段 + 该阶段必读 md + 最终架构文档 + 门禁还差什么」注入上下文。
换人接手：`stager swap <你>` → `stager ctx --full`。

### 0.1 第一句必须自报（不许只在脑子里想）

```text
🔀 自报｜模式: 人工(1)/自动(2)/离线(2) ｜ 档位: 工具级/模块级/架构级 ｜ 规则源: <读了哪几份>
体检｜心跳/provider/测试日志新鲜度/健康基线 ｜ 一刀切: 可开工 / 只许体检
本轮｜<一句话要做什么>
```

- **人工(1)** = 用户在场 ｜ **自动(2)** = **用户不说话（默认）** ｜ **离线(2)** = 用户不在线
- **自动/离线必开** `every-10min-drive.ps1 -Loop -IntervalSec 600`（心跳 `scripts\drive-heartbeat.log` 递增才算数）
- 体检四项：`九、维护体检`（已移入 `自编译统一版\`，四项内容未变）
- **档位=架构级 → 停下等用户批准再写码**

### 0.2 改代码/进游戏 → 闭环入口只有一个

```powershell
& "E:\restart developing doer\rdd-selfcompile\scripts\run-mutation.ps1" -Requirement "<需求>" -Module <模块>
```

**禁止**手写 gradle、**禁止**手动拷 jar（`permission.bash` 已 deny，绕不过去）。
- 常用 `-Module`：`plugins:rdd` / `plugins:learner` / `plugins:ac` / `plugins:experience` / `core:neoforge`
- 要证据就加 `-CollectEvidence -EvidenceTool <只读工具名>`
- ⚠️ 改执行层（core/common）必须 `-Module core:neoforge`（默认模块盖不到）

---

## 1 · 主流程 = stager 的 4 阶段（一条线，循环往复）

```
stager 管： ① 计划统筹 → ② 编码实现 → ③ 游戏验证 → ④ 记录收口
                  ↑                                              │
                  └──── 有洞：stager next 自动回①并 +1 轮 ──────┘
                        全过：stager close --status done → 关档
```

**阶段定义是数据驱动的**：`E:\restart developing doer\stager\core\stages.json`
（改流程只改这个 JSON，不改代码；每阶段的 `read[]` 就是"本阶段必读"）

**两个并行职责**：**A** 游戏里穷举能力→修复（回②）｜**B** 模块补全（回①）

### 每步的细则在哪（**只给索引，正文在文档里**）

| 阶段 | 细则文档 | 关键点 |
|---|---|---|
| ① 计划统筹 | `10-总流程与双模式.md`；`25-第二批设计` | 分流 + 写计划 + **W 池互审**（见 §2） |
| ② 编码实现 | `01-工程规范.md`（八项全表）；`11-模块化回滚`；`30-主要功能不回退清单` | 改接口先查消费者 + 契约回归 |
| ③ 游戏验证 | `12-进游戏验证工具集`；`04-进游戏巡检规范.md` §五；`13-监测台与巡检` | **多方查证**（见 §3）+ 自写工具（见 §3.5） |
| ④ 记录收口 | `05-记忆库与经验注入.md`；`01-工程规范.md` 第 8 条；`06-检查清单.md` | 记忆库 / `NumenApi` 跨插件门面 / 四段打勾 |

### 铁律（几条最容易忘的，直接列这）

- **关 MCP 止投**：免费 AI 只读观察。禁 `enqueue/mine/goto/attack/build`；允许 `get_self_status/scan_nearby_entities/rdd_get_inventory/list_companions`
- **开游戏默认 2 小时**（`launch-mc.ps1 -AutoStopMinutes 120`）。**自动关只是为了防 API 烧光，不是门禁** —— 关掉还没验完可以重新起
- **动世界之前先备份当前存档/自定义**
- **关 MC 防空转**（占内存，用户远程会连不上）
- **先排 provider 再判代码**：任何「它不动」的第 0 步是查日志有**无 401/402/5xx**。2026-09-28 实测 DeepSeek 402×49、0 成功 → 看着像执行层慢，真因是**没钱**
- **主链路不回退**：M1-M5 + RL-1..RL-9，拆解前先对照 `30-主要功能不回退清单.md`
- **端口真源**（旧文有误）：MCP **test=8766 / gpt=8765**；监测台 **test=8777 / gpt=8776**

---

## 2 · ① 计划：多 AI 互审

### 2.1 ★ GPT-6 是稀缺额度，默认不用

> `moyuu/gpt-6-astra` **额度用完就是用完了**，排期要看余额，别把整轮计划押在它身上。

| 情况 | 怎么用 | 用几次 |
|---|---|---|
| 常规任务（绝大多数） | **不用 GPT-6**：当前模型自己写计划 → W 池互审 | 0 |
| **一次性做大量模块** | 开头让 GPT-6 写总体文档：范围/切分/里程碑/不做什么 | **一次**，只在开头 |
| **超长任务**（跨多轮多天） | 开头让 GPT-6 写总体设计文档，后续轮次照着走 | **一次**，只在开头 |

**额度用完就跳过**，不等、不换、不硬凑；在计划书注明「GPT-6 额度用尽，本轮未用」。
**不许**为了"流程完整"反复重试烧额度。**拿不准先问 Codex**（read-only 沙箱，比 GPT-6 便宜）。

### 2.2 三条腿（W / C / 记忆）

| 层 | 谁 | 怎么叫 | 产物 |
|---|---|---|---|
| W | 网页免费模型 **GLM 为主**（可加 DeepSeek，池子共 4 家；Qwen 不用） | `node scripts\w-brain-drive.js askall "<问题>"` → `synth` | `rdd架构\brain-replies\w-*.md` |
| C | **codex** | `codex_codex_ask` | `rdd-selfcompile\report\外脑审稿-*.md` |
| 记忆 | **memory MCP** | `memory_search_nodes` **计划期就查** | `report\经验库检索留痕-*.md` |

### 2.3 ★ 固定画像（违反这条 = 白干）

| 规矩 | 原因 |
|---|---|
| **★ 画像（profile）必须固定** | 换 profile = 重新传一遍上下文，AI 接不上茬，理解会漂 |
| **★ 浏览器绝对不许关** | 关了 profile 状态丢失，同上 |
| **★ 记住上次用的是哪个，下次就开那个** | 记在 `w-platforms.json`；`w-brain-drive.js` 自带回退，**先跑再说** |

- 2026-09-29 实测：以为 W 层不可用，实际 **GLM 4760 字 + Kimi 1352 字**（Qwen 只 235 字，不可用）
- **三方交叉才可信**；冲突时不要和稀泥，把分歧点列出来交给用户
- **唯一例外**：用户明说「这次就走九步流，不走互审」→ `stager next --force --note "用户要求不走互审"`

---

## 3 · ③ 游戏验证：怎么找漏洞 + 怎么验自己的剧本

> **先说清楚：看干活 AI 的对话记录是零成本的，任何时候都能直接看，不需要"排在第几位"。**
> 不要把它塞进"便宜到贵"的队列 —— 那会让人以为必须按顺序走完才能看下一个。
> **真正需要按成本权衡的只有「画面」和「进游戏」这两件事。**

| 看什么 | 成本 | 能看出什么 |
|---|---|---|
| **干活 AI 自己的对话记录** | **免费 · 随时看** | 它说了什么、卡在哪、是不是在原地打转、它**以为**成功了其实没有。**大部分问题看这个就露出来了** |
| 画面 | 要截图 | 屏幕上实际发生什么，和它的自述对不对得上 |
| 任务执行效率 | 要跑脚本 | 横跳 / 失败风暴 / 乒乓循环 / planner_gap |

**怎么拿对话记录**：监测台「Numen AI」页 / `ai.jsonl` / `rdd.jsonl`（干净 UTF-8）

### 3.1 四方查证 = **证据清单，不是顺序**

这四层是**要凑齐的证据来源**，不是必须按次序走完的队列：

| 层 | 手段 | 什么时候必须补 |
|---|---|---|
| 决策链 | 监测台 `ai.jsonl` / 8776「Numen AI」页 | **永远要** —— 免费只读，随时能看 |
| 任务状态 | MCP `rdd_status` | 要说清"现在什么状态"时 |
| 任务效率 | `node scripts\task-efficiency-watch.js rdd --tag <runTag>` | 怀疑"原地打转/横跳/反复失败"时 |
| **视觉下现场** | **OpenClaw** `oc-drive.js`（**不经 Numen MCP → 同伴照常跑**）+ `mc-screenshot.ps1` → Read 看图 | **对不上账时**才上：AI 说做完了但世界没变 |

> **只有"视觉下现场"要权衡**（要开窗口、要花时间）。前三层免费只读，**想看就看，不用等、不用排队**。
> **别再因为「没开浏览器/不确定」而跳过**（用户已授权随便用）。
> 截图/快照**必须带时间戳 + runTag**，否则事后无法归因。

### 3.2 怎么验自己的剧本（OpenClaw 路线）

1. **自己用创造模式** + **用使命**（command/goal）**搭建环境**
2. **再切观察者模式**确认结果
3. **退游戏**

### 3.3 证据怎么写

`stager put --kind evidence`，必须含 **命令 + 关键输出行 + 时间戳 + runTag**。

### 3.4 监测台全程开着

用户要能随时看到你在干什么：gpt = **8776** ／ test = **8777**（真源 `config.ps1` 的 `MONITOR_URL`）

### 3.5 哪里不方便就自己写工具

**统一放一个文件夹**：`E:\restart developing doer\rdd-selfcompile\scripts\verify-tools\`
规矩见该目录 `README.md`：一个工具 = `<名>.ps1/.js` + 同名 `.md`；不许动 `scripts\` 根目录（闭环真源）；参数化；退出码有意义；`.ps1` 必须 UTF-8 BOM。

---

## 4 · 收工门（3 个，缺一不许说「走完流程了」）

```powershell
# ① 阶段门禁（stager 管：当前阶段该交的东西交了没）
node "E:\restart developing doer\stager\bin\stager.js" check
# ② 九步流硬门禁（20 项：六步 + 记忆/外脑/巡检/清单）
node "E:\restart developing doer\rdd-selfcompile\scripts\loop-gate.js" --since <今天> --keyword <模块> --head <本轮HEAD>
# ③ 自编译闭环门
node "E:\restart developing doer\rdd-selfcompile\scripts\flow-gate.js" --since <今天> --active <开工时的 store active>
```

**为什么 ② 比 ③ 严**：每项要求 **mtime 新 + 正文含本轮签名**。
只有时间戳的话，**旧文件改个时间就能骗过门禁**。
实证：③ 曾报 FLOW_COMPLETE，实际漏了 7 项（W层零产出/经验库没查/无契约回归/无不回退清单对照/verify 从未VERIFIED/巡检没跑/更新日志没写）。

**然后照 `06-检查清单.md` 逐条打勾**（开工/过程/收工/进游戏 四段），写 `测试日志.md` + `09-更新日志.md` + 经验库。

### ★ 完成动作（顺序别乱）

1. `stager close --status done --note "<一句话结论>"` ← **关 stage**（本轮必须有 `arch` + `evidence`）
2. **关游戏**（带 `-AutoStopMinutes` 会自关；手动起的自己关）
3. **代码推远端**（`git push`；commit message 用 `-F msg.txt`，含空格会被 shell 拆）
4. **报告各项验证证据 + 成果清单** → 汇总给用户
5. 用户说没问题 → 结束；**用户说有问题 → 进入下一轮**（`stager next` 或 `stager start` 新一轮）

### ★ 每 3 轮 · GLM 源码审

第 3/6/9 轮 → `stager ctx` 会自动提醒。**把本轮所有源码改动粘给 GLM**（直接粘文本，不要只给摘要/链接），审稿落 `rdd-selfcompile\report\`。

---

## 5 · 记忆库 / MCP 现状（实测，别凭印象）

- **memory 图谱此前一直是空的**（经验都进了文档没进图谱）→ 空库→查了没用→更不查 的正反馈坑。现已灌入 17 条
- `experience-core` 已上线（3 工具 `learn_learn/recall/verify`）；**`VectorExperienceRetriever` 接缝留着但未实现**
- **语义检索最小可行替代**（GLM+Kimi 一致）：**结构化 tag + 词法优先**。「Minecraft 是封闭域、词 gap 小」→ 向量是锦上添花。**别硬凑 top-5，返 0 条比凑 5 条好**
- **跨插件唯一门面 = `NumenApi`**（`numumen-plugin.gradle:37-44` 刻意封死跨插件 import；历史事故：rdd 内嵌 ac-core 撞 JPMS `ResolutionException`）
- `test` 实例 `[openai] api_key` **原为 EMPTY** → 验 LLM 链路用 `gpt`

---

## 6 · 东西放哪（用户随时要看/要用的）

**一律放** `E:\restart developing doer\rdd-selfcompile\给用户\`（报告/工具/截图/文档 + `INDEX.md`），
用 `stager publish <文件> --as report|tool|shot|doc --title "<标题>"` 放（自动登记索引）。
**不许**放 `mutations\`（61 个变异目录）、**不许**放 `%TEMP%`、**不许**放 `report\`（那是审稿原文）。

**我自己写的验证工具** → `rdd-selfcompile\scripts\verify-tools\`（**只放这一个文件夹**）。

---

## 7 · 交接与新资产

- **接手先看**：`E:\新建文件夹\rdd架构\self-compile-handoff.md`（不靠口头上下文即可接手）
- **细则索引**：`自编译统一版\INDEX.md` → `README.md` → `01-工程规范` → `10-总流程` → `06-检查清单`
- **★ stager 自己的交接**：`E:\restart developing doer\stager\STAGER.md`（给 AI）+ `README.md`（给人）
- **暗号**：运行模式只有 **1=人工 / 2=自动/离线**；能力暗号另有 `数字1~4`（`skills/` 目录）
- **本轮新资产**（2026-09-29）：
  | 资产 | 干什么 |
  |---|---|
  | `stager\` | 4 阶段状态机 + 门禁 + 文档注入 + 换人次 + 桌宠；**开工第 0 件事就是它** |
  | `loop-gate.js` | 九步流硬门禁（20 项） |
  | `collect-evidence.ps1` | 五件证据采集（让 verify 终于是 VERIFIED） |
  | `scripts\verify-tools\` | 我自写验证工具的**唯一**落点 |
  | `给用户\` | 要给你看/用的东西的**唯一**落点 |
  | `plugins/learner` | 学习者 v1 ｜ `30-主要功能不回退清单.md` |
