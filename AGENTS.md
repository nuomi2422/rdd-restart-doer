## ★★★ 第 −1 条 · 所有 shell 一律后台跑（用户被卡了几十次）
用户提出要求之后，一律走九步编程流

**任何 shell 命令都不要前台阻塞等待。** 要么用 `Start-Process … -WindowStyle Minimized` 脱离启动，要么让命令自己立刻返回。**加长 timeout 不是解法。**

> ⚠️ **含中文路径的 wrapper 一律写 node `.js`，不要用 `.ps1`**（PS 5.1 读 UTF-8 无 BOM 的 `.ps1` 会把中文路径读成乱码，`MODULE_NOT_FOUND`）。

## 第 −0.5 条 · 写作格式不在这里（2026-10-19 拆出去）

**本文件只管「怎么干活」，不管「怎么写文档」。** 进哪个目录干活，先读那个目录的 `_格式规范.md`：

| 你要写 | 读这份 |
|---|---|
| 任意目录规划 / 什么该放哪 | `D:\rdd\docs\rdd-docs\rdd架构\目录规范.md` |
| 先判「写哪一类」 | `…\rdd架构\_格式规范.md` |
| 项目大事记 | `…\rdd架构\项目历史\_格式规范.md` |
| 模块架构（含代码↔意图绑定） | `…\rdd架构\模块架构\_格式规范.md` |
| 红线 tag 回退点 | `…\rdd架构\红线回退\_格式规范.md` |
| 零散的今天干了啥/下一步 | `…\rdd架构\杂项记录\_格式规范.md` |
| 起停/端口/备份/救火 | `…\rdd架构\运维\_格式规范.md` |
| 跨模块的代码解释 | `…\rdd架构\代码解释\_格式规范.md` |
| 编号文档（NN-xxx） | `…\rdd架构\自编译统一版\_格式规范.md` |
| harness（registry / 时间锁 / skill） | `D:\rdd\harness\rdd-harness\_格式规范.md` |
| 代码 / 提交信息 / 脚本头注释 | `D:\rdd\workspace\_格式规范.md` |
| 给用户看的报告 | `…\rdd存放\_格式规范.md` |

> 为什么拆：以前所有写作规则都堆在这个文件里，结果它越写越胖、换个目录干活的人不知道该按哪个格式写、
> 规则一改就要动全局文件（已实测丢过 182 行，时间锁 `TL-2026-10-04-03`）。
> **本文件只保留指针，不复制正文** —— 复制就是下一次漂移的种子。

## 第 0 条 · stage 流已降级为「可选，默认不用」（2026-10-21）

> **默认不开 stage。** 用户 2026-10-21 定：
> 「原本的 stage 流程感觉太臃肿了……实际上所有挂在的话，基本上就进游戏和退游戏那两个
> 挂在大门，东西也更加确定性，原本的 stage 就可以差不多废弃和隐藏了。」
>
> **为什么**：`stager` 的 `.stager\tasks\` 长期是空的（实测 0 项）—— 没人走 stage。
> 主 AI 的实际节奏是「按文档分批写码 → 进游戏验 → 退游戏回填」，
> 计划那一步已经被 75 号蓝图取代了。**挂在没人走的流程上的必读清单 = 从没被执行过。**

**现在真正的门只有两个**（都在 `harness-gate.js`，不依赖任何流程）：

| 门 | 什么时候 | 挂了什么 |
|---|---|---|
| **preflight** | **进游戏前** | P1–P5 编译/部署/提交、P9 时间锁、P10 编号、P13 能力清单、**P14 工作区干净**、**P15 要不要打存档快照** |
| **postflight** | **退游戏后** | Q1–Q13 记录/证据/图谱/编号、**Q14 证据坐标**、**Q16 文档书写清单** |

```powershell
node "D:\rdd\harness\rdd-harness\bin\harness-gate.js" preflight  --since <今天> --keyword <模块>
node "D:\rdd\harness\rdd-harness\bin\harness-gate.js" postflight --since <今天> --keyword <模块>
```

**什么时候还开 stage**：只有用户**明确说**「开 stage」时。那时才读 `stage.md`，
并跑 `stager start "<用户原话目标>"`。其余情况一律按普通任务直接做。

> ### ★ 四阶段流水线 / 阶段必读 / 机器门 / 完成动作 —— 全在 stage.md，本文件不承载
>
> ```text
> D:\rdd\harness\rdd-harness\stage.md
> ```
>
> **开 stage 之前不必读它，不开 stage 永远不要读它。**
> 要改 stage 流（加阶段 / 改门禁 / 改必读）改 `stage.md` + `stager\core\stages.json`，**不要改本文件**。
> 原因：本文件 2026-10-04 瘦身就是为了消掉「三份规则文件副本互相漂移」（全局那份已丢 182 行，时间锁 `TL-2026-10-04-03`）。


## 第 0.5 条 · ★ 要主人拍板 → **先过筛子**，过了才走 decide-inbox

> 用户 2026-10-21 定：**「拍板」不是批次流程的一部分，是治理层和执行层之间的独立通道。**
> 它**不依赖 stage**（不开 stage 也能用），队列落成 append-only 的
> `docs\rdd-docs\rdd存放\decisions.jsonl`，和 `memory.jsonl` 一个待遇。

**凡是要主人拍板的事，先过一道筛子**（2026-10-22 用户改口径：**宁可漏，不要多**）：

> **不可逆，且对外吗？**
>
> - **不是** → **退回去：「你自己定，写进卡里。」** 不许发到主人面前。
> - **是** → 才走下面的 `decide-inbox` 举手。

**筛子没过 = 举手 = 错。** 每次盖章都是给主人交的注意力税。主人只该看到「一个核心决策」，
其余（S101 · H-Q3 · G5f 采集 · G6a · 报告放行门禁 · 周行为指标 · 推送到主分支 · 快照 · 文档回填）
**全部沉到机器层，自己做完自己记账**。

> 决策权分配的完整口径在 `C:\Users\admin\.dsh\AGENTS.md` §0.5（主人的三个不可替代角色、那张卡、不许再加工具）。
> **每次开工先读它。**

筛子过了，才举手：

```powershell
node "D:\rdd\harness\rdd-harness\bin\decide-inbox.js" add "<要主人拍板的那件事>" `
  --risk high-arch `
  --why "<影响面 / 两条路的代价 / 不决定会怎样>" `
  --opt "A|<方案甲>|rec|<选了它的后果>" `
  --opt "B|<方案乙>||<选了它的后果>" `
  --batch <批次号>
```

**主人拍完之后，你必读**（这是闭环的另一半 —— 不读等于没接通）：

```powershell
node "D:\rdd\harness\rdd-harness\bin\decide-inbox.js" digest
```

- `digest` 会列出「主人已拍板」的项，**那条决定覆盖你之前的任何倾向**。
- 除非发现事实与决策时的假设不符，不要再改主意；确实必须改，先说明「哪一条假设不成立了」，再重新 `add`。
- **禁止**把「等主人拍板」只写在文档里就继续干 —— 那样主人根本不知道你在等。
- 判据：`add` 会拦下机械性技术问题（真源 `stager\core\decide-policy.json`）。被拦了就是你自己该定，别 `--force`。
- **不许因为「拿不准」就举手** —— 拿不准时按最保守的那条路走，并写明「这里本该问你，我按保守走了」。

> 为什么加这条：2026-10-21 实测，主 AI 一直在文档里写「owner 批准动刀 AC-B18」（#122），
> 但主人看不到、也点不了 —— 链路两端都在，只差中间这根线。
>
> 为什么改口径：同一天实测「宁多勿漏」把主人淹在一堆机械性技术问题里，**一个都定不了**。
> 2026-10-22 用户定：「每次盖章都是注意力税」→ 筛子 + 单一核心决策。

## 第 0.6 条 · 存档快照是**你自己的工具**（用不用你判断，删也归你）

> 用户 2026-10-21 定：「不一定自动打，应该是要干活的 AI 知道这个东西的存在，
> 他要用的时候才用，而且还要主动的删掉……快照的话应该是执行 AI 自己的事。」

**它不是给用户批的事，是你干活的手段。** 什么时候用：

- 这次验证会**破坏环境**（挖洞 / 丢东西 / 改同伴状态 / 改配置）→ 打一份再进游戏
- 想**同一场景反复重跑**（判据要多次采样）→ 打一份当基准

```powershell
# 打（游戏必须已停）
node "D:\rdd\harness\rdd-harness\bin\snapshot-world.js" --name before-<批次> --apply
# 跑坏了回滚
node "D:\rdd\harness\rdd-harness\bin\snapshot-world.js" --restore before-<批次> --apply
# 看还有几个、占多少、哪些该删
node "D:\rdd\harness\rdd-harness\bin\snapshot-world.js" --status
# 删过期的（默认 TTL 48 小时）
node "D:\rdd\harness\rdd-harness\bin\snapshot-world.js" --prune --apply
```

**★ 用完自己删。** 它是工作副本，不是资产 —— 每份 30 MB 级，攒着只会占盘。
默认 TTL 48 小时；退游戏回填时顺手 `--prune`。

> 快照里存三样（体积差 6 倍，工具已分开处理）：
> `saves\<世界>\` 全量 ｜ `config\numen\`（排除 monitor）全量 ｜ `monitor\` 只留最近 30 分钟。
> 回滚会自动删 `session.lock`（不删游戏拒绝进入），并先打一份 `pre-restore` 后悔药。

## 第 1 条 · 工程纪律

### 1.1 编译只有一个通道（手写 gradle / 手动拷 jar 已被 permission deny，绕不过去）

```powershell
& "D:\rdd\workspace\rdd-selfcompile\scripts\run-mutation.ps1" -Requirement "<需求>" -Module <模块>
```

- `-Module`：`plugins:rdd` / `plugins:learner` / `plugins:acx` / `plugins:experience` / `plugins:camera` / `core:neoforge`
- **改执行层（`core/common` 的类）必须 `-Module core:neoforge`**，默认模块盖不到
- `-MaxAttempts N` 止损循环 ｜ `-SkipLaunch -SkipMcp` 只编译+部署 ｜ `-AutoStopMinutes N`（默认 120）
- **一个 mutation 只放一个 jar**（`deploy.ps1` 取 jar 目录下的第一个）→ 多模块要用多个 mutation
- 改接口**先查消费者**：`FailureClassifier` 那种 switch 穷举，加枚举值不同步补 case 就编译不过
- **搬走一个 mixin 必须在原宿主模块里同步拆除并重建宿主 jar**，否则两个 mixin 同时注入同一方法
- **不信 `DEPLOY_OK` 一句话**：用 `node rdd-selfcompile\scripts\verify-tools\check-runtime-deployment.js` 核（退出码 2 = 有源码领先于 jar）

### 1.2 提交纪律

> ⚠️ **`git add -A` 会卷进别人的改动。** 本工作区**常有两个会话并行改同一个仓库**。
> **精确 add 指定文件**：`git add <路径1> <路径2>…`。提交前必跑 `git status --short` 逐行确认，每一行都是你改的。
> commit message 一律 `git commit -F msg.txt`（含空格会被 shell 拆）。
> **写进文档的纪律不自动生效，得靠每次提交前的习惯。**

- 2026-10-01 实测已出过一次事故（`MAX_QUEUE=63` 的变异被卷进 commit，HEAD 一度是坏的）
- 2026-10-01 **二次事故**：在 `rdd-docs` 又用了 `-A`，把并行会话的整个同步批次（**167 个文件**）卷进一个提交信息写着「三件待办全部不做」的 commit。数据没丢，但**提交信息与内容严重不符**。rdd-docs 尤其危险 —— 副本同步一次就动 147 个文件。
- 改文档后记得 commit（`rdd-docs` / `rdd-harness` 都是独立仓库）

### 1.3 源码改了 ≠ 运行时生效

只改源码就写「已改完」= 把中间态当完成态。中间隔着 **编译 → 部署 jar → 重启游戏** 三步。
**判据有工具，别靠记性**：

```powershell
node rdd-selfcompile\scripts\verify-tools\check-runtime-deployment.js    # 退出码 2 = 有源码领先于 jar
```

★ 它比的是「**最后一次改 `src/main/java`** 的提交」vs jar 的 `LastWriteTime」，**不是**「最后一次提交」—— 只改 `*Test.java` 时 jar 本来就不用重部署（这个区分不做会满屏假警报）。

### 1.4 改路径必须全仓 grep，不要凭印象只搜一个目录

散落的硬编码路径已经收成配置。**别再自己写死路径**：

| 侧 | 改这里 | 覆盖什么 |
|---|---|---|
| **node**（stager / loop-gate / stage-heartbeat） | `stager\core\stages.json` 的 `docsRoot` + `docsOut` | ctx 必读清单 · publish 投放到哪 |
| **PowerShell**（sync-unified-copy / backup-to-removable 等） | `rdd-selfcompile\scripts\config.ps1` 的 `DOCS_ROOT` / `DOCS_UNIFIED` / `DOCS_OUT` | 副本同步 / 备份 |

⚠️ **以前这里写的是「改完跑 stager.js self-check 验 read[] 真实存在」—— 那个命令根本不存在**（真命令是 self-test，验的是状态机不是路径）。
g --files 一下 read[] 里的每个路径即可，别照抄不存在的命令。

> 为什么加这条：2026-10-01 知识库搬家（`rdd架构` → `rdd-docs\rdd架构`），**13 处散落硬编码全失配** ——
> ctx 指向不存在的目录、loop-gate 读不到测试日志、publish 往废弃目录投。
> 第一次只搜了 `stager/` 就以为改完了，**漏了 `rdd-selfcompile\scripts` 的 5 处**（其中 loop-gate 是硬门禁）。

### 1.5 改接口前先读 75 号 §15（`IC-75-r1`，2026-10-20）

任务链/资产/检索/学习发布相关接口的契约在 `…\自编译统一版\75-目标资产与统一检索层重构决策草案-20261019.md` **§15**：模块落点与单向依赖、链实例与版本 CAS、attempt 唯一性与幂等、事实读取（未知≠空）、检索/发布/样本字段、分批迁移与 12 项断言。
同文 **§16** 是施工顺序真源：G1→G7 分组、每批闭环门（批次卡→判据冻结→实机→回填→模块文档）、§16.4 放行条件。批次进度查 `…\rdd架构\杂项记录\2026-10.md` 文末汇总表。
动这些接口前先读；交接时写 `contractRevision=IC-75-r1` 和「你的实现→契约」映射。已有等价实现保留，不为统一类名返工。

## 第 2 条 · 常见坑（杂项，别重踩）

| 坑 | 症状 | 对策 |
|---|---|---|
| **PS 5.1 按 ANSI 读无 BOM 的 UTF-8** | `.ps1` 中文乱码 + 一串语法错 | `.ps1` **必须写 UTF-8 BOM** |
| **`node -e "…"` 内联被 PS 引号拆坏** | 各种诡异报错 | **一律写 `.js` 文件再 `node file.js`** |
| **PS `:` 插值** | `":$mod:jar"` 整串变成 `:`，gradle 报找不到 task `:` | 用 `":$($mod):jar"` |
| **MCP 端口** | 文档里写过 test=8765，**是错的** | **live=8765**（真源：`<实例>\config\numen\mcp_server.json`）。test=8766 已停用 |
| **监测台端口** | 记混 | **live=8776**（真源：`config.ps1` 的 `MONITOR_URL`）。test=8777 已停用 |
| **游戏日志中文是 GBK** | 用中文 grep 假阴性 | 判中文功能查**监测台 `rdd.jsonl`**（干净 UTF-8） |
| **`get_self_status` 等 MCP 工具** | 直接派活会被门禁拒 | 关 MCP 止投，只读 |
| **test 实例 `api_key` 是 EMPTY** | 验 LLM 链路失败 | **用 live 实例**（`[openai]` 段） |
| **Bash 工具 120s 超时** | 杀掉等待循环（**但 MC 照样在跑**） | 起了就查状态，**别重发** |
| **W 池调用别用默认 120s** | 大部分模型 2~3 分钟才说完，**GLM 可能要 4~5 分钟**，超时会被砍，**白等一场** | `bash(timeout=60000)` 起步；**超时就查落盘文件**（`report\w-replies\*.json`），别重发 |
| ⚠️ **GLM 抓回复会抓到上一轮旧答案** | 2026-09-30 实测：GLM 浏览器里答对了，但落盘文件里存的是上一轮「1+1等于2」。**是脚本抓错元素，不是 GLM 答错**（Qwen/Kimi/DeepSeek 同时同题抓取正确）。时序偶发，非必现 | **互审前先跑探针** `node rdd-selfcompile\scripts\w-probe.js`（发随机数问题核对答案）；探针不过就别问 |
| **provider 先排再判代码** | 「它不动」被误判成执行层慢 | 第 0 步查日志有**无 401/402/5xx**（2026-09-28 实测 DeepSeek 402×49、0 成功 = 没钱） |
| ⚠️ **写「怎么修」之前先实测** | 照着症状猜出来的修法可能是错的 | 2026-10-01 我把 `plugins/rdd` 单测加载不了诊断成「缺 `numen_api`、加一行 `testImplementation` 就行」—— 并行会话实测发现**真正缺的是整个 Minecraft 测试运行期**，是 moddev 配置改造不是一行的事。**症状 ≠ 病因** |
| ⚠️ **回执 `success:true` ≠ 东西真存在** | openclaw 的 `keyDown t` 回执 success 但什么都不会发生（`InputHandler` 只有 7 个键分支）；`record` 回执 ok 但落的是无扩展名文件 | **回执只说明「handler 没抛异常」**。落盘/生效要自己查（文件在不在、内容对不对） |
| ⚠️ **失败模式不要设计成静默** | `cam.json` 的 `target:"RDD"` 匹配不到同伴就静默退回第一人称，**一个错都不报** | 匹配不到要**明确报失败文案**。这类「智能性错误」已全部记进 `rddharness\registry.json` 的 `timeLocks`（带 guard + reviewBy） |

### ★ 实例叫法（2026-10-01 用户确认：只用 live）

| 叫法 | 指什么 | 状态 |
|---|---|---|
| **live** | `D:\rdd\mc\The Best of Twilight Forest` | ✅ **唯一在用** —— 用户口中的「live」就是它 |
| ~~gpt~~ | **同一个目录**，只是脚本参数名（`config.ps1` 的 `ValidateSet('test','gpt')`） | 别当成另一个实例 |
| ~~test~~ | `rdd-selfcompile\instances\test` | ❌ **已停用**，不计入任何债 |

**三个叫法是同一个东西**：`live` = `gpt 实例` = `The Best of Twilight Forest`。
文档里一律叫 **live**；只有在写命令行时才写 `-Instance gpt`（那是**参数名**，不是实例名）。

> ⚠️ 改叫法时**别顺手把 `ValidateSet` 也改了** —— 那是脚本契约，`launch-mc.ps1` /
> `run-mutation.ps1` / `config.ps1` 都按它传参。

---

## 第 3 条 · 本工作区地图

| 路径 | 是什么 | 关键入口 |
|---|---|---|
| `stager\` | **★ 流程状态机**（4 阶段 / 轮次 / 人次 / 文档 / 门禁 / 桌宠）。stage 流的实现 | `bin\stager.js ctx`、`core\stages.json`（阶段定义）、`bin\repo-status.js`（**套娃仓库状态面板**）、`pet\start-pet.ps1`（桌宠） |
| `minecraft-numen\` | **Numen 源码 · 真源**（Java / Gradle 9.2 / JDK 21 / NeoForge 1.21.1）。全部游戏代码在这 | `gradlew.bat :plugins:rdd:test`、`plugins/camera/`（2026-10-04 新增的客户端相机模块 numencam） |
| `rdd-selfcompile\` | **自编译运行时真源**。`scripts\`（闭环/看门狗/巡检/外脑/回滚/清理）、`templates\`、`mutations\`、`ai-bridge\` | `scripts\run-mutation.ps1`（**唯一改码入口**）、`scripts\config.ps1`（真源） |
| `rdd-monitor-publish-20260913\` | **监测台 live 副本**（只读观测） | `monitoring-station\server.mjs` → `http://127.0.0.1:8776/` |
| `mc-openclaw-controller\` | OpenClaw 客户端玩家控制器（8080，键鼠/感知/截图）。仓库已打 tag `archived-2026-10-01`，但**运行时仍然是活的依赖**（`mc-watch.js` 会调它） | `scripts\server.js`（**必须先于游戏起**）、`scripts\oc-send.js`、`scripts\capture-win.ps1` |
| `gradle-9.2.0\` | 离线 Gradle 发行版 | `gradle-9.2.0\bin\gradle.bat` |

### ⚠ 套娃仓库（本工作区有 6 个 git 仓库）

外层 `D:\rdd\workspace` 有一个，另有 5 个套娃：`minecraft-numen`（真源）、
`rdd-selfcompile\ai-bridge`、`rdd-monitor-publish-20260913`、`mc-openclaw-controller`、`voyager`。

**外层 `.gitignore` 排掉了它们**（理由：提交只会存成 gitlink 指针，克隆外层拿不到内容）。
代价是**外层 git 完全看不见内层改动** —— 所以 `stager` 门禁和 `loop-gate` 的
「本轮有按模块 commit」判据**对 `minecraft-numen` 的改动是盲的**。

**动子仓库前后跑一次** `node stager\bin\repo-status.js`（只读，一次看清 6 个仓库的
HEAD / 脏项 / 推没推 / 有没有远程 / 是不是浅克隆）。**跨仓库对账时看它，不要只看外层 `git log`。**

### ⚠ `plugins/selfcompile` ≠ 改码通道（2026-10-01 核实，容易搞错）

游戏里那个 `selfcompile` 插件**不是改码通道**，它现在只是
**工程流 stager 里「进游戏监督 AI」那个小流程的落地面**：

| | 干什么 | 谁在用 |
|---|---|---|
| 游戏内 `selfcompile_request` | 把游戏内 AI 的需求写进审计目录 | 游戏里的 AI |
| 游戏内 `selfcompile_status` | 查状态（idle/controlled） | 游戏里的 AI |
| 游戏内 `RddWhereamiTool` / `RddGetInventoryTool` | `generated/` 下，**它自己产的**，每轮变异要手工改入口注册 | 游戏里的 AI |
| 外层 `run-mutation.ps1` | **★ 唯一的改码通道**（编译/部署/起游戏/MCP/取证） | 本工程流 |

`selfcompile_request` 的工具描述原话：**「只创建审计目录，不生成代码、不执行命令、不编译、不部署」**

`plugins/selfcompile/MutationPipeline.java` 那条 11 态变异流水线
（编译 / 验证 / 预算止损 / Harness 写锁）**在生产代码里 0 处引用，只有单测能调到**——
**它已经关着了，不是"在跑但有风险"，是根本没接上线**。代码里已加停用注释。
⚠️ **别去接线它** —— 外层已有一套 MutationId 与门禁，两套并存必然漂移。

---

## 第 4 条 · AI 工程脚手架 RDD Harness（`D:\rdd\harness\rdd-harness\`）

**= 工具注册表 + 编程规范 + 两段门禁 + 时间锁。** 独立 git 仓库 `nuomi2422/rdd-harness`（私有）。

```powershell
node "D:\rdd\harness\rdd-harness\bin\harness-gate.js" selftest
node "D:\rdd\harness\rdd-harness\bin\harness-gate.js" preflight --since <今天> --keyword <模块> --head <HEAD>
node "D:\rdd\harness\rdd-harness\bin\harness-gate.js" postflight --since <今天> --keyword <模块> --head <HEAD>
```

- **`registry.json`** = 唯一真源（74 工具 / 13 项 preflight / 12 项 postflight / 10 条时间锁 / 编号规则 / 10 个已知 bug）
- **`standards.md`** = 编程规范唯一真源（8 域 40 条带 id）；`rdd-docs\…\01-工程规范.md` 是它的镜像
- **`进游戏前必读-游戏内能力清单.md`** = **进游戏之前必读一遍**（游戏里有哪些能力 + 正确调用姿势 + 坑）
- **`stage.md`** = ★ stage 流（**只在开 stage 时读**）
- 退出码：`0` 全过 ／ `1` 有 BLOCK ／ `3` 环境错（不是债）

> **总结 / 复盘 / 经验文档一律写 `rdd-docs\rdd架构\`，不写进 harness 目录。**

### 4.1 进游戏 / 退游戏的标准动作（2026-10-19 明确）

| 时机 | 必做 |
|---|---|
| **进游戏前** | ①读能力清单 ②`preflight` → `BLOCK=0` ③**建验证卡（判据先写死）**到 `rdd架构\实机验证\YYYY-MM.md` ④起游戏 |
| **退游戏后** | ①`postflight` ②回填验证卡（结果/**原因**/复现） ③`杂项记录\` 加一行 ④确认 java 进程归零 ⑤新坑写记忆库 |

> ⚠️ 只编译没进游戏 = 🟡「已写码未实测」，**不是** ✅ 已完成。
> ⚠️ 验证卡**不许验完再补判据** —— 那是拿结果改标准。

#### ★ 写完卡立刻跑一次机检（2026-10-22 加，别跳过）

**坐标当场校验**，不然下一轮要从聊天记录里考古（而聊天记录会被压缩掉）：

```powershell
node D:\rdd\workspace\rdd-selfcompile\scripts\verify-tools\check-evidence-anchor.js --card "<卡文件名>.md"
```

`hard=0` 才算写完。红了当场改，**不要把带 hard 的卡留在盘上**。

> 2026-10-22 实测：3 条 hard 错全是「写卡时坐标是真的，几小时后日志轮转 /
> 引文写成摘要」—— 没有一条是当场伪造坐标。但只要**当时跑过一次**，
> 至少能区分「轮转失效」和「引文根本不在日志里」，
> 而后者才是要追责的那类。
> 引用会轮转的日志（`rdd*.jsonl` / `context*.jsonl`）必须写**归档文件名**，
> 别写活动文件名；`tools.jsonl` 不轮转，可以写活动文件名。

**三份知识/资产库各管一段**：

| 库 | 远程 | 装什么 |
|---|---|---|
| `D:\rdd\docs\rdd-docs\` | `nuomi2422/rdd-docs` | **设计+规范+叙事的真源**（70 份编号文档 + 七类活文档）+ 用户要看的东西（`rdd存放\`） |
| `D:\rdd\harness\rdd-harness\` | `nuomi2422/rdd-harness` | **注册表 / 规范契约 / 门禁 / 时间锁 / stage 流 / 实测档案** |
| 外层 + 5 个套娃 | 各自 | 代码 |

---

## 第 5 条 · 交接与资产

- **接手先看**：`D:\rdd\docs\rdd-docs\rdd架构\self-compile-handoff.md`
- **换人接手**：`node stager\bin\stager.js swap "<你的名字>"` → `stager ctx --full`
- **规则正文全在** `D:\rdd\docs\rdd-docs\rdd架构\自编译统一版\`
- 想解决 X 该读哪份 → `50-按主题导航.md` ｜ 那天他究竟做了什么 → `51-研发叙事时间线.md`
- **文档里的行号会漂** —— 想知道准不准，跑
  `node rdd-selfcompile\scripts\verify-tools\check-doc-anchor-drift.js --docs "D:\rdd\docs\rdd-docs\rdd架构" --src "D:\rdd\workspace\minecraft-numen"`

### ★ 用户只看这一个地方

```text
D:\rdd\docs\rdd-docs\rdd存放\
```

### 全目录分工（别搞混）

| 目录 | 谁用 |
|---|---|
| `D:\rdd\docs\rdd-docs\rdd存放\` | **用户** —— 要看、要用、要点的，**全部放这里** |
| `D:\rdd\docs\rdd-docs\rdd架构\` | AI —— 设计+规范+叙事的真源 |
| `D:\rdd\harness\rdd-harness\` | AI —— 注册表 / 门禁 / stage 流（**不放总结**） |
| `rdd-selfcompile\report\` | AI —— 外脑审稿原文（W 池回复也归档到这） |
| `rdd-selfcompile\scripts\` | AI —— 闭环真源，**改动要用户批准** |
| `rdd-selfcompile\scripts\verify-tools\` | AI —— 验证工具 |
| `rdd-selfcompile\mutations\` | AI —— 每次变异的临时工作区（**用户别翻**） |
| `stager\` | AI —— 阶段状态机（**桌宠源码在 `stager\pet\`，harness 里那批 `.bat` 只是启动台副本**） |
| `D:\rdd\tools\mcp-memory\` | AI —— MCP 记忆库（库文件在 `rdd架构\_memory\memory.jsonl`） |

### 七类文档在哪（2026-10-19 建，**都是文件夹**，别再各写各的）

| 要写 | 去哪 |
|---|---|
| 项目大事记（时间/为什么/代价） | `rdd架构\项目历史\`（`YYYY-MM至MM-主题.md`，追加） |
| 某模块的架构全景 | `rdd架构\模块架构\<模块>.md` |
| 红线 tag 回退点 | `rdd架构\红线回退\索引-按红线.md`（追加） |
| 零散的今天干了啥/下一步 | `rdd架构\杂项记录\YYYY-MM.md`（`#NNN`，追加） |
| 起停/端口/备份/救火 | `rdd架构\运维\总览.md` |
| 跨模块的代码↔意图绑定 | `rdd架构\代码解释\`（模块内的写模块文档 §8） |
| **实机验证（进游戏）** | `rdd架构\实机验证\YYYY-MM.md`（判据/原因/数据/结果/复现，**进游戏前建卡**） |

> 每个文件夹里都有自己的 `_格式规范.md`；**进目录先读它**，别回头翻本文件。
> 「定时写文档」的真实含义：**上面每个事件发生时就写**（完成一件事 → 杂项记录；
> 退游戏 → 验证卡；踩坑 → 时间锁 + 记忆库），不是按闹钟写。

> `rdd-selfcompile\给用户\` 已废弃（内容已归到 `rdd存放`）。
> `rdd架构\特殊模式\` 已废弃：原目录移到 `_废弃-特殊模式-20260930\`（68 个文件都在，没删），
> 审稿原文已拷到 `rdd-selfcompile\report\w-replies\`。
