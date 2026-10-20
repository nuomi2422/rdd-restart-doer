# AGENTS.md · 2026-09-29（B 版 · 已实装）

> 用户 2026-09-29 审过草稿后拍板实装。
> **备份**：`AGENTS.backup\AGENTS-20260929-230301-pre-B版.md`（本轮换之前的原版）、
>           `AGENTS.backup\AGENTS-20260929-124005-pre-slim.md`（更早的全文版）。
> **草稿原件**：`AGENTS.md.draft-B.md`（要改先改它，审完再覆盖本文件）。
>
> **和旧版的差别**：旧版是「指针集合」（告诉你去哪读）；这版是**一条可执行的流水线**
> ——阶段、门禁、必读、判据全写在文件里，AI 不需要猜、不需要记得读第二份文档。

## 第 0 条 · 硬门（任何工程任务的第一动作，不许跳过）

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" start "<用户原话目标>" --actor "<你的名字>"
```

**开工前必须报 stage。** 没开 stage 就动手 = 这一轮作废。

开完档后 `stager ctx` 会把下面这些自动注入到你的上下文里（opencode 插件已装）。
没被注入就手动跑一次：

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" ctx
```

`ctx` 里有三样东西，**每次动手前都要看**：
1. **当前阶段 + 该阶段必读的 md 清单**（不读不许动手）
2. **★ 最终架构文档**（所有 AI 的锚，防跑偏）
3. **门禁还差什么**（不达标 `next` 会直接拒你）

> 第一句话自报（模式 / 档位 / 规则源 / 体检 / 本轮），然后跑 stage，然后干活。
> 顺序不许换：**先报 → 再开 stage → 再读必读 → 再动手**。

---

## 第 1 条 · 四阶段流水线（走完一轮自动 +1，直到任务真正完成）

```
  ① 计划统筹 plan ──→ ② 编码实现 implement ──→ ③ 游戏验证 verify ──→ ④ 记录收口 close
        ↑                                                                       │
        └───────────── 有洞 / 没验完：stager next 自动回①并 +1 轮 ────────────────┘
                      全过：stager close --status done → 关档结束
```

**每阶段必须跑一次。** 每阶段跑完打标记推进，门禁不达标 `next` 会拒。
轮次上限默认 5 轮（`start --rounds N` 改），到顶了要 `--force --note "为什么超"`。

| # | 阶段 | id | 门禁（不达标不许走） | 表情 |
|---|---|---|---|---|
| ① | 🗺️ 计划统筹 | `plan` | `plan` 文档 + **`arch` 最终架构文档** | 疑惑 |
| ② | ⚙️ 编码实现 | `implement` | `implement` 标记 | 平静 |
| ③ | 🧪 游戏验证 | `verify` | `evidence` 文档 | 惊讶 |
| ④ | 🎉 记录收口 | `close` | `experience` 文档 + `check` 标记 | 大笑 |

**门禁没过 = 桌宠会变成叉腰生气**（`02-angry.png`）。这是给你看的信号，不是装饰。

### ① 计划统筹 · 必读

```
D:\rdd\extras\rdd架构\自编译统一版\10-总流程与双模式.md
D:\rdd\extras\rdd架构\自编译统一版\01-工程规范.md
D:\rdd\extras\rdd架构\自编译统一版\30-主要功能不回退清单.md
```

**★ 目标分流（先判，判完写进目标书 `stager put --kind goal`）**

| goalType | 什么时候选 | 干什么 |
|---|---|---|
| `module` | 要给 Numen 加能力 / 修 bug | 改代码为主，走②③ |
| `exploit` | 要在 Minecraft 世界里找可利用的行为/机制 | **不改代码**，走③为主，找到了再决定要不要固化 |
| `free` | 用户没说清楚 | 先摸清现状（读代码 + 看监测台 + 看 AI 日志）再回来重分流 |
| `tidy` | 改流程 / 工具 / 规则本身 | 不碰游戏逻辑，改完要证明没破坏原链路 |

**★ 计划怎么出（默认不花 GPT-6）**

> **GPT-6（`moyuu/gpt-6-astra`）是稀缺额度，默认不用。**
> 额度用完就是用完了 —— 排期要看余额，别把整轮计划押在它身上。
> **只有两种情况才动用它**，而且**只在开头用一次**抓方向，不参与后续轮次。

**【默认路线 · 绝大多数任务走这条】**

```
   用户目标
     │
     ├─▶ ① 当前模型自己写计划（opencode 就能写）
     │      ★ 写文件用 write 工具，不要 node -e 内联（会被 PS 引号规则拆坏）
     │
     ├─▶ ② W 池互审（见第 2 条）→ GLM 为主，可加 DeepSeek
     │      固定画像 · 浏览器不许关 · 记住上次用哪个
     │
     ├─▶ ③ 汇总各家意见 → 逐条标注【采纳】/【驳回 理由】
     │
     ├─▶ ④ 冻结成「最终架构文档」
     │      stager put --kind arch --title "最终架构文档-vN"
     │      ★ 这份是所有 AI 的锚，每阶段都要回头读，防跑偏
     │
     └─▶ ⑤ 计划成立 → stager next 进编码
```

**【GPT-6 例外 · 只在这两种情况动用】**

| 情况 | 怎么用 | 用几次 |
|---|---|---|
| **一次性做大量模块**（一批插件/一批工具同时上） | 开头让 GPT-6 写总体文档，**抓方向、定边界、排优先级** | **一次**，只在开头 |
| **超长任务**（跨多轮、多天、跨阶段的大工程） | 开头让 GPT-6 写总体设计文档，后续轮次照着它走 | **一次**，只在开头 |

```
   用户目标
     │
     └─▶ ① GPT-6 出【总体方向文档】（开头这一次，不再来回）
          范围边界 / 模块切分 / 里程碑 / 明确不做什么
            │
            ├─▶ ② opencode 拆成本轮可执行的计划
            │
            ├─▶ ③ W 池互审 → 汇总
            │
            └─▶ ④ 冻结 arch → stager next
```

**GPT-6 额度用完了怎么办** → **跳过，不等、不换、不硬凑**。
走上面的默认路线（当前模型写 + W 池互审），并在目标书/计划书里注明「GPT-6 额度用尽，本轮未用」。
**不许**为了"流程完整"反复重试烧额度。

**什么时候值得动用 Codex** → 非常难 / 架构级 / 拿不准的时候（第 2 条）。
Codex 是 read-only 沙箱问答，比 GPT-6 便宜，**拿不准先问它**。

### ② 编码实现 · 必读

```
D:\rdd\extras\rdd架构\自编译统一版\01-工程规范.md   （八项全表）
D:\rdd\extras\rdd架构\自编译统一版\11-模块化回滚.md
D:\rdd\extras\rdd架构\自编译统一版\30-主要功能不回退清单.md
```

**入口只有一个（手写 gradle / 手动拷 jar 已被 permission deny，绕不过去）：**

```powershell
& "D:\rdd\workspace\rdd-selfcompile\scripts\run-mutation.ps1" -Requirement "<需求>" -Module <模块>
```

- `-Module`：`plugins:rdd` / `plugins:learner` / `plugins:ac` / `plugins:experience` / `core:neoforge`
- **改执行层（`core/common` 的类）必须 `-Module core:neoforge`**，默认模块盖不到
- `-MaxAttempts N` 止损循环 ｜ `-SkipLaunch -SkipMcp` 只编译+部署
- 改接口**先查消费者**：`FailureClassifier` 那种 switch 穷举，加枚举值不同步补 case 就编译不过

写完：`stager implement --note "改了什么 / 为什么 / 怎么调的 / 入口出口"`

### ③ 游戏验证 · 必读（**这一阶段规范最多**）

```
D:\rdd\extras\rdd架构\自编译统一版\12-进游戏验证工具集.md    ← 工具/脚本全在这
D:\rdd\extras\rdd架构\自编译统一版\04-进游戏巡检规范.md    ← 四层监察
D:\rdd\extras\rdd架构\自编译统一版\13-监测台与巡检.md
```

**开游戏**

```powershell
& "D:\rdd\workspace\rdd-selfcompile\scripts\launch-mc.ps1" -Instance gpt -AutoStopMinutes 120
```

- **默认 2 小时**
- **自动关只是防 API 烧光，不是门禁** —— 关掉还没验完，**可以重新起**
- **★ 动世界之前先备份当前存档/自定义**
- 用户在场改 `-AutoStopMinutes 10`（省额度）

**★ 找漏洞怎么看（不是排队，是随时能看）**

> **先说清楚：看干活 AI 的对话记录是零成本的，任何时候都能直接看，不需要"排在第几位"。**
> 不要把它当成"便宜到贵"队列里的第一档 —— 那会让人以为必须按顺序走完才能看下一个。
> **真正需要按成本权衡的只有"画面"和"进游戏"这两件事。**

| 看什么 | 成本 | 能看出什么 |
|---|---|---|
| **干活 AI 自己的对话记录** | **免费 · 随时看** | 它说了什么、卡在哪、是不是在原地打转、它**以为**自己成功了但其实没有。**大部分问题看这个就露出来了** |
| 画面 | 要截图 | 屏幕上实际发生什么，和它的自述对不对得上 |
| 任务执行效率 | 要跑脚本 | 横跳 / 失败风暴 / 乒乓循环 / planner_gap（规划层原地打转） |

**怎么拿对话记录**：监测台「Numen AI」页 / `ai.jsonl` / `rdd.jsonl`（干净 UTF-8）

**★ 验证自己的剧本（OpenClaw 路线）**

```powershell
node "D:\rdd\workspace\mc-openclaw-controller\scripts\server.js"    # 8080
node "D:\rdd\workspace\mc-openclaw-controller\scripts\oc-drive.js"   # 键鼠/感知/截图
```

1. **自己用创造模式** + **用使命**（command/goal）**搭建环境**
2. **再切观察者模式**确认结果
3. **退游戏**

> OpenClaw 不经过 Numen MCP → **同伴 AI 照常跑，可以共存**。

**★ 四方查证 = 证据清单，不是顺序**

这四层是**要凑齐的证据来源**，不是必须按次序走完的队列：

| 层 | 手段 | 什么时候必须补 |
|---|---|---|
| 决策链 | 监测台 `ai.jsonl` / 「Numen AI」页 | 永远要 —— 免费只读，而且**随时可以看** |
| 任务状态 | MCP `rdd_status` | 要说清"任务现在什么状态"时 |
| 任务效率 | `node scripts\task-efficiency-watch.js rdd --tag <runTag>` | 怀疑"原地打转 / 横跳 / 反复失败"时 |
| 视觉下现场 | OpenClaw `oc-drive.js` + `mc-screenshot.ps1` → Read 看图 | **对不上账时**才上：AI 说做完了但世界没变 |

> **只有"视觉下现场"要权衡**（要开窗口、要花时间）。
> 前三层都是免费只读，**想看就看，不用等、不用排队**。
> 截图/快照**必须带时间戳 + runTag**，否则事后无法归因。

**证据怎么写**：`stager put --kind evidence`，必须含 **命令 + 关键输出行 + 时间戳 + runTag**。
没 runTag 事后无法归因，等于没证据。

**★ 哪里不方便就自己写工具（统一放一个文件夹）**

```text
D:\rdd\workspace\rdd-selfcompile\scripts\verify-tools\
```

| 规矩 | 说明 |
|---|---|
| **只放这一个文件夹** | 散落的工具下次就找不到了，等于白写 |
| 一个工具 = `<名字>.ps1/.js` + **同名 `.md`** | 没说明的工具等于没有 |
| **不许动 `scripts\` 根目录的既有脚本** | 那是闭环真源，改坏了整条链断；要改得先问用户 |
| 参数化，不写死路径/任务/时间 | 下次换个任务还能用 |
| 退出码有意义（0=通过） | 才能接进 `run-mutation.ps1 -CollectEvidence` 当证据 |
| `.ps1` 必须 UTF-8 BOM | PS 5.1 按 ANSI 读无 BOM 会语法错 |
| 写完在同名 `.md` 记：干什么 / 怎么调 / 依赖 / 什么时候该删 | 半年后才知道它是干嘛的 |

**★ 随时开着监测台**（用户要能随时看到你在干什么）：gpt = **8776** ／ test = **8777**

### ④ 记录收口 · 必读

```
D:\rdd\extras\rdd架构\自编译统一版\06-检查清单.md      ← 收工段逐条打勾
D:\rdd\extras\rdd架构\自编译统一版\01-工程规范.md      ← 第 8 条：写工程经验
D:\rdd\extras\rdd架构\自编译统一版\30-主要功能不回退清单.md
```

**① 记录经验 → 灌进 memory MCP**

```powershell
# memory_create_entities / memory_add_observations
```

**别只写文档不进图谱。** 空库 → 查了没用 → 更不查，这是踩过的正反馈坑。

**② 写工程规范第 8 条要求的四件**：改了哪 / 为什么 / 怎么调的 / 入口出口
**③** `stager put --kind experience --title "工程经验-<批次>"`
**④ 机器门（两个都要过）**

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" check
node "D:\rdd\workspace\rdd-selfcompile\scripts\loop-gate.js" --since <今天> --keyword <模块> --head <本轮HEAD>
node "D:\rdd\workspace\rdd-selfcompile\scripts\flow-gate.js" --since <今天> --active <开工时的 store active>
```

`flow-gate` 输出 `VERDICT=NOT_DONE` → **不许收工、不许上报完成**。

**⑤ 判定：走回炉，还是走完成**

```
有洞 / 没验完  →  stager next          （自动回① +1轮，上轮标记全部作废）
全过          →  走下面的「完成动作」
```

**★ 完成动作（顺序别乱）**

```powershell
stager close --status done --note "<一句话结论>"   # ① 关 stage
```

1. `stager close --status done` —— **关 stage**（本轮必须有 `arch` + `evidence`，否则会被拦）
2. **关游戏** —— 带 `-AutoStopMinutes` 起的会自动关；手动起的**自己关，别占内存**
3. **代码推到远端** —— `git push`（commit message 用 `-F msg.txt`，含空格会被 shell 拆）
4. **报告各项验证证据 + 成果清单**
5. **汇总给用户**
6. 用户说**没问题** → 真正结束；用户说**有问题** → `stager start` 新一轮，或 `stager round --force` 接着修

---

## 第 2 条 · 外脑分工（W 池 + Codex）

### 分工

| 难度 | 走谁 |
|---|---|
| 普通 | 不用外脑，当前模型自己写 |
| **任意难度 / 架构级** | **W 池**（主 GLM，可加 DeepSeek，池子共 **4** 家）互审 |
| **非常难 / 架构级 / 拿不准** | **W 池 + Codex CLI**（`codex_codex_ask`，read-only 沙箱） |

### ★ 固定画像（违反这条 = 白干）

```
W 层用 node scripts\w-brain-drive.js askall "<问题>"  →  rdd架构\brain-replies\w-*.md
```

| 规矩 | 原因 |
|---|---|
| **★ 画像（profile）必须固定** | 换 profile = 重新传一遍上下文，AI 接不上茬，理解会漂 |
| **★ 浏览器绝对不许关** | 关了 profile 状态丢失，同上 |
| **★ 记住上次用的是哪个，下次就开那个** | 记在 `w-platforms.json`；`w-brain-drive.js` 自带 profile 回退，**先跑再说**，别因为"浏览器没开"就跳过 |

> 2026-09-29 实测：以为 W 层不可用，实际 **GLM 4760 字 + Kimi 1352 字**（Qwen 只 235 字，不可用）。
> **三方交叉才可信**（Codex + GLM + Kimi）；单个外脑会编。
> 冲突时不要和稀泥，把分歧点列出来交给用户。

### 唯一例外

**用户明说「这次就走九步流，不走互审」** → 跳过 W 池，`stager next --force --note "用户要求不走互审"`。
这是唯一允许 `--force` 走计划阶段的场景。

---

## 第 3 条 · 每三轮 · GLM 源码审

```
第 3 / 6 / 9 … 轮 → stager ctx 会自动在注入包里提醒你
```

**动作**：把本轮**所有源码改动**粘给 GLM 审一遍。

- **直接粘文本**，不要只给摘要或链接（GLM 看不到你的文件）
- 走完 3 轮再发，不是每轮都发
- 审稿落 `rdd-selfcompile\report\`
- 审出 P0/P1 → 记进待办，下一轮计划阶段必须处理

---

## 第 4 条 · 模式

| 情况 | 模式 | 规矩 |
|---|---|---|
| 用户在场 | **人工(1)** | MC ≤10 分钟/次，改 `-AutoStopMinutes 10` |
| **用户不说话** | **自动(2)** | 默认走这个；MC ≤60 分钟/次 |
| **用户不在线** | **离线(2)** | 同上 + 必须开 `every-10min-drive.ps1 -Loop -IntervalSec 600` |

**自动模式必开心跳**：`scripts\drive-heartbeat.log` 末行递增才算数（不递增 = 看门狗没跑）。

---

## 第 5 条 · 三不（不可协商）

1. **不烧额度** —— 免费 AI 只读观察；关 MCP 止投（禁 `enqueue`/`mine`/`goto`/`attack`/`build`；
   允许 `get_self_status`/`scan_nearby_entities`/`rdd_get_inventory`/`list_companions`）
2. **不越权** —— 跨插件唯一门面 = `NumenApi`（`numumen-plugin.gradle` 刻意封死跨插件 import，
   历史事故：rdd 内嵌 ac-core 撞 JPMS `ResolutionException`）
3. **不无证据宣称完成** —— **编译成功 ≠ 行为成功；MCP OK ≠ 世界真变**

---

## 第 6 条 · 常见坑（别重踩）

| 坑 | 症状 | 对策 |
|---|---|---|
| **PS 5.1 按 ANSI 读无 BOM 的 UTF-8** | `.ps1` 中文乱码 + 一串语法错 | `.ps1` **必须写 UTF-8 BOM** |
| **`node -e "…"` 内联被 PS 引号拆坏** | 各种诡异报错 | **一律写 `.js` 文件再 `node file.js`** |
| **PS `:` 插值** | `":$mod:jar"` 整串变成 `:`，gradle 报找不到 task `:` | 用 `":$($mod):jar"` |
| **MCP 端口** | 文档里写过 test=8765，**是错的** | **test=8766 ／ gpt=8765**（真源：各实例 `config\numen\mcp_server.json`） |
| **监测台端口** | 记混 | **gpt=8776 ／ test=8777**（真源：`config.ps1` 的 `MONITOR_URL`） |
| **游戏日志中文是 GBK** | 用中文 grep 假阴性 | 判中文功能查**监测台 `rdd.jsonl`**（干净 UTF-8） |
| **`get_self_status` 等 MCP 工具** | 直接派活会被门禁拒 | 关 MCP 止投，只读 |
| **test 实例 `api_key` 是 EMPTY** | 验 LLM 链路失败 | **用 gpt 实例**（`[openai]` 段） |
| **Bash 工具 120s 超时** | 杀掉等待循环（**但 MC 照样在跑**） | 起了就查状态，**别重发** |
| **provider 先排再判代码** | 「它不动」被误判成执行层慢 | 第 0 步查日志有**无 401/402/5xx**（2026-09-28 实测 DeepSeek 402×49、0 成功 = 没钱） |

---

## 第 7 条 · 本工作区地图

| 路径 | 是什么 | 关键入口 |
|---|---|---|
| `stager\` | **★ 流程状态机**（4 阶段 / 轮次 / 人次 / 文档 / 门禁 / 桌宠）。第 0 条那条就是它 | `bin\stager.js ctx`（AI 开工第一条）、`core\stages.json`（阶段定义）、`pet\start-pet.ps1`（桌宠） |
| `minecraft-numen\` | **Numen 源码**（Java / Gradle 9.2 / JDK 21 / NeoForge 1.21.1） | `gradlew.bat :plugins:rdd:test`、`plugins/selfcompile/.../generated/` |
| `rdd-selfcompile\` | **自编译运行时真源**。`scripts\`（闭环/看门狗/巡检/外脑/回滚/清理）、`templates\`、`mutations\`、`ai-bridge\` | `scripts\run-mutation.ps1`（**唯一改码入口**）、`scripts\config.ps1`（真源） |
| `rdd-monitor-publish-20260913\` | **监测台 live 副本**（只读观测） | `monitoring-station\server.mjs` → `http://127.0.0.1:8776/` |
| `mc-openclaw-controller\` | OpenClaw **客户端玩家控制器**（8080，键鼠/感知/截图）。**不经 Numen MCP → 同伴 AI 照常跑** | `scripts\server.js` + `oc-drive.js` |
| `gradle-9.2.0\` | 离线 Gradle 发行版 | `gradle-9.2.0\bin\gradle.bat` |

**真正的规则正文在** `D:\rdd\extras\rdd架构\自编译统一版\`（`INDEX.md` → `README.md`）。
本文件是**可执行的那一份**：阶段 + 门禁 + 必读 + 判据。正文细节去那 39 份里查。

---

## 第 8 条 · 东西放哪（用户随时要看/要用的东西）

**凡是「用户要看」或「用户要用」的，一律放这一个文件夹：**

```text
D:\rdd\workspace\rdd-selfcompile\给用户\
├── 报告\    ← 这轮做完的总结报告
├── 工具\    ← 给用户用的工具（双击能跑那种）
├── 截图\    ← 验证过程的画面证据
├── 文档\    ← 给用户看的说明（人话版，不是技术规格）
└── INDEX.md ← 索引，publish 时自动更新，最新在最上
```

**规矩**

| 规矩 | 说明 |
|---|---|
| 用 `stager publish` 放，**不要手写** | 自动登记进 `INDEX.md`，用户不用翻目录找 |
| **用户在场 / 不在场都一样** | 不因为"用户没看"就不放 —— 用户上线后要看的就是这些 |
| **不许放 `mutations\`** | 61 个变异目录，用户不该去翻 |
| **不许放 `%TEMP%`** | 下次会话就没了 = 白干 |
| 报告要写人话 | 用户要的是「结论 + 怎么用」，不是内部术语堆砌 |

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" publish "<文件>" --as report|tool|shot|doc --title "<标题>"
```

### 全目录分工（别搞混）

| 目录 | 谁用 |
|---|---|
| `rdd-selfcompile\给用户\` | **用户** —— 要看、要用、要点的 |
| `rdd-selfcompile\scripts\` | AI —— 闭环真源，**改动要用户批准** |
| `rdd-selfcompile\scripts\verify-tools\` | AI —— 我自己写的验证工具 |
| `rdd-selfcompile\mutations\` | AI —— 每次变异的临时工作区（**用户别翻**） |
| `rdd-selfcompile\report\` | AI —— 外脑审稿原文 |
| `stager\` | AI —— 阶段状态机 |

---

## 第 9 条 · 改流程怎么改

**stager 的阶段是数据驱动的** —— 改 `stager\core\stages.json`，改完立刻生效，不用改代码。

```jsonc
{
  "loopTo": "plan",              // 轮回回到哪
  "goalTypes": { "module": "...", "exploit": "...", "free": "...", "tidy": "..." },
  "docKinds": { "goal": "...", "plan": "...", "arch": "...", "evidence": "...", ... },
  "stages": [{
    "id": "plan", "name": "计划统筹", "icon": "🗺️", "expr": "confused",
    "next": "implement",
    "read":  ["...必读 md..."],   // ← 改这里就改「本阶段必读」
    "gate": { "docs": ["plan", "arch"] },   // ← 改这里就改门禁
    "brief": "...", "ai": ["...必做..."]
  }]
}
```

加阶段 / 改门禁 / 改必读 / 改表情映射，全在这一份 JSON 里。

---

## 第 10 条 · 交接与资产

- **接手先看**：`D:\rdd\extras\rdd架构\self-compile-handoff.md`
- **stager 自己的交接**：`stager\STAGER.md`（给 AI）+ `stager\README.md`（给人）
- **换人接手**：`stager swap "<你的名字>"` → `stager ctx --full`（把历史文档全文注入给你）
- **桌宠**：`stager\启动桌宠.bat` 或 `stager pet`；点一下报「阶段 (n/4) / 第几轮 / 轮回几次 / 人次 / 门禁」
- **桌宠表情**：门禁没过 = 叉腰生气；计划 = 疑惑；写码 = 平静；验证 = 惊讶；收工 = 大笑；空闲 = 害羞

---

## 第 11 条 · 一句话

> **先开 stage，读该阶段必读，回头看最终架构文档，干活，存证据，推门禁。**
> **编译成功 ≠ 行为成功；MCP OK ≠ 世界真变；读文档 ≠ 走流程。**
