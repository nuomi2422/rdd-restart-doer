# 工作区规则薄壳 · D:\rdd\workspace

## ★★★ 开工第 0 件事（硬门 · 2026-09-29 加 · 不改这里就等于没开工）★★★

**任何"要改代码/要进游戏"的任务，开工前先把这两条读出来并照着走。**
（痛点：文档齐全、脚本齐全，但 AI 一上来就**手写 gradle + 手动部署**，把自编译闭环整个绕过 → 好系统派不上用场。）

```text
① 本任务走的是【自编译闭环】，入口只有一个（禁止手写 gradle / 手动拷 jar）：
     & "D:\rdd\workspace\rdd-selfcompile\scripts\run-mutation.ps1" -Requirement "你的需求"
   （单轮：new-mutation → gen-code → build-jar → deploy → verify → verdict.json；
     止损循环用 -MaxAttempts N；只编译不跑游戏用 -SkipLaunch -SkipMcp）

② 收工前必须让机器门放行（不过 = 不许说"走完流程了"）：
     node "D:\rdd\workspace\rdd-selfcompile\scripts\flow-gate.js" --since <今天> --active <开工时的 store active>
   → 输出 VERDICT=NOT_DONE 就回去补，别上报完成。
```

**为什么写在这里**：这条曾反复被绕过（AI 只"读过"文档，不"走"流程）。**读 §开工必读 ≠ 走了流程。**

> ★ **接手先看交接**：`D:\rdd\extras\rdd架构\self-compile-handoff.md`
> （当前状态 / 红线锚点 / 待办与未验证 / 正确流程 / 踩坑清单 / 文档索引 —— 不靠口头上下文即可接手）

---

> 2026-09-28 建。**本文件故意不复制规则正文，只做指针**——规则一改就到处过期（这正是旧 `rdd-monitor-publish-20260913\AGENTS.md` 里那套 MaidSoulCore1 规则与现行体系打架的根因）。
> 作用：在本工作区**任意子目录**开 opencode 新会话时，都会自动读到本文件 → 顺着指针找到唯一真身。

---

## 开工必读（按序，缺一不可）

1. **全局规则卡（真身·全文读）**：`C:\Users\admin\.config\opencode\AGENTS.md`
   含：〇-a 开工第一句硬门（开口自报）/ 一·九步流九规范 / 二·关 MCP 止投 / 三·分工链 / 四·记录改动 / 七·暗号索引 / 八·外脑 / 九·维护体检 / 十·监测台 / 末尾完成检查索引。
2. **本薄壳**（工作区地图 + 运行时要点，即本文件）。
3. **统一版必读 4 份（★ 少一份 = 无授权；其余 18 份按需才开，绝不整目录全读）**：
   `D:\rdd\extras\rdd架构\自编译统一版\INDEX.md` → `README.md` → `01-工程规范.md` → `10-总流程与双模式.md`
4. **★ 收工必读 + 必跑（验收门）**：`06-检查清单.md` —— 开工/过程/收工/进游戏四段**逐条勾**。
   **收工第 1 条 = 跑机器门**（只认盘上实物，**不认"读过文档"**）：
   `node rdd-selfcompile\scripts\flow-gate.js --since <今天> --active <开工时的 store active>`
   → 输出 `VERDICT=NOT_DONE` 就**不许收工**、不许对外说"走完流程了"。

> 为什么要拎出来：`10-总流程`（干什么/什么顺序）和 `06-检查清单`（验收）是这一整套的两根主梁，
> 曾经被归进"19 份按需才开"→ **流程和验收门自己被降级成可选项**（2026-09-28 用户拍板修正）。

**然后**：第一条回复第一行按 〇-a 自报三段（模式 / 档位 / 体检+本轮），「规则源」写明读了哪几份。
**不读真身不算开工**；没自报 = 无授权（不得架构级改动、不得对外承诺、不得自称完成）。

---

## 本工作区地图（各目录干什么）

| 路径 | 是什么 | 关键入口 |
|---|---|---|
| `minecraft-numen\` | **Numen 源码**（Java / Gradle 9.2 / JDK 21 / NeoForge 1.21.1）。模块 `rdd-core`、`ac-core`、`experience-core`、`api`、`core`、`ai`、`ui`；插件 `plugins\{rdd,ac,selfcompile,tlm,ysm,experience}` | `gradlew.bat :plugins:rdd:test`、`plugins/selfcompile/.../generated/`（自写工具落点） |
| `rdd-selfcompile\` | **自编译运行时真源**。`scripts\`（闭环 / 看门狗 / 巡检 / 外脑 / 回滚 / 清理）、`templates\`、`mutations\`（每次变异工作区）、`selfcompile\{stable,candidates,archive,mutations}+active.json`、`ai-bridge\`、`instances\test` | 脚本清单见 `scripts\` 与统一版 `02-工具资产清单.md` |
| `rdd-monitor-publish-20260913\` | **监测台 live 副本**（只读观测） | `monitoring-station\server.mjs` → `http://127.0.0.1:8776/` |
| `mc-openclaw-controller\` | OpenClaw **客户端玩家控制器**（8080，键鼠/感知/截图）。**不经 Numen MCP → 同伴 AI 照常跑，可共存** | `node mc-openclaw-controller\scripts\server.js` + `oc-drive.js` |
| `gradle-9.2.0\` | 离线 Gradle 发行版 | `gradle-9.2.0\bin\gradle.bat` |
| `stager\` | **★ 编程流程阶段管理器**（阶段 / 轮次 / 人次 / 文档 / 门禁 + 桌面宠物）。任何"要做开发活"的都归它管 | `stager\bin\stager.js ctx`（AI 开工第一条）、`stager\STAGER.md`（细则）、`stager\core\stages.json`（阶段定义）、`stager\pet\start-pet.ps1`（桌宠） |

---

## 运行时要点（省得每次重查）

- **构建环境**：`JAVA_HOME=D:\rdd\tools\jdk21\jdk-21.0.11+10`、`GRADLE=D:\rdd\workspace\gradle-9.2.0\bin\gradle.bat`、代理 `127.0.0.1:7897`（真源：`rdd-selfcompile\scripts\config.ps1`）
- **双实例**：默认 `test`（隔离，MCP 8765 / 监测台 8777 / `rdd-selfcompile\instances\test`）；`gpt` = 生产（`D:\rdd\mc\The Best of Twilight Forest`，监测台 8776），**必须显式 `-Instance gpt`**
- **单轮闭环**：`& rdd-selfcompile\scripts\run-mutation.ps1 -Requirement "…"`；止损循环加 `-MaxAttempts N`；`-SkipLaunch -SkipMcp` 只编译+部署
- **长任务前提**（断一不可）：① watchdog `every-10min-drive.ps1` 在跑，`scripts\drive-heartbeat.log` 末行递增 ② 监测台 8776 在跑 ③ **关 MCP 止投**（免费 AI 只读观察，不投 enqueue/mine/goto/attack/build）
- **MC 时长铁律**：用户在线 **≤10 分钟/次**，不在 **≤60 分钟/次**（`launch-mc.ps1 -AutoStopMinutes 10|60`）
- **回滚**：`node rdd-selfcompile\scripts\selfcompile-store.js status|promote|rollback`（只有 `VERIFIED` 能进 active；回滚 = 切 `active.json` 指针）
- **视觉**：`scripts\mc-screenshot.ps1 [-Foreground]` 截 MC 窗口 PNG → 用 Read 看图（最小化窗口会被跳过，先还原）
- **巡检**：`node scripts\redline-watch.js <同伴>`（常开，不得只看一眼就停）
- **三不**（全局卡核心）：不烧额度、不越权、**不无证据宣称完成**（编译成功 ≠ 行为成功；MCP OK ≠ 世界真变）

---

## 子目录自带 AGENTS.md 的读法

- `rdd-monitor-publish-20260913\AGENTS.md` — 2026-09-28 已清理（旧 MaidSoulCore1 段移出，原文备份在同目录 `.bak-20260928-…`），现为监测台入口 + 指向全局卡。
- `rdd-selfcompile\ai-bridge\AGENTS.md` — ai-bridge **项目交接文档**（架构/文件/已知问题/三轮加固史），是技术文档不是规则卡，可直接读。
- `minecraft-numen\tools\ui-textures\AGENTS.md` + `CLAUDE.md` — 第三方目录自带，与本体系无关。
- **冲突裁定**：本工作区任何 AGENTS.md 与全局规则卡不一致 → **一律以全局卡为准**。

---

## provider 真话（别按不存在的机制做规划）

- **默认模型 = `moyuu/gpt-6-astra`**：中转 `https://moyuu.cc/v1`，key 来自 cc-switch 的 `My` 供应商（2026-09-28 实测 `chat/completions` 与 `responses` 双端点均通）。**架构决策/深审就用它**。
- 该 key **喂不动 `gpt-5.6-terra`（503）**；实测中转站只有 `gpt-6-astra` 在 chat/completions 上稳定，其余 5 个模型报 500/503 → opencode 里**只用 `gpt-6-astra`**。
- `small_model` = `opencode/big-pickle`（免费，只做标题生成）；`openrouter` 仍配着（免费池约 20 req/min）。
- **「多 provider 自动降级」不成立**（429/5xx 要人工 `/model` 切）。`opencode.jsonc` 只是待填 key 模板。
- **Codex CLI 也统一到这把 key**：`~/.codex/auth.json` + `config.toml` 的 `name="My"` / `model="gpt-6-astra"`（原为 `520` + `gpt-5.6-terra`）。

## ▶ STAGER 阶段管理器（自动）

**每个会话开工前先跑**：`node "D:\rdd\workspace\stager\bin\stager.js" ctx`
有输出就照着当前阶段做，做完 `next`（过不了门禁就按提示补文档）。细则见 `D:\rdd\workspace\stager\STAGER.md`。
