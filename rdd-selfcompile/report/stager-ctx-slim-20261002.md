# Stage 提示瘦身 + 插件复活 · 经验（2026-10-02）

## 坑 1：插件「看着没事」≠ 加载过 —— ESM 重复 function 声明是语法错误

`stager/opencode-plugin/stager-plugin.mjs` 里 `fingerprintOf` 定义了两次（第 38-40 行、第 49-51 行），
后者覆盖前者且丢了 `docRev`。ESM 严格模式下重复 `function` 声明**是语法错误**，
import 整个模块直接 `SyntaxError: Identifier 'fingerprintOf' has already been declared`
→ **这个插件从写下来那天起就一次都没被 opencode 加载过**，自动注入一直是死的。
（旁证：整个会话上下文里从没出现过 `## ▶▶ 现在在：` 横幅。）

同一文件里 `readJson` 被调用 4 次、**0 处定义** —— 就算语法修好，下一步就是 `ReferenceError`。

**对策**：改插件后必须 `import` 实测（`probe-plugin.mjs` 直接 import 再调钩子），
不能靠 `stager self-test`（那测的是 CLI，不加载插件）或「读一遍看着对」。
凡是 opencode 插件/opencode.json 里注册的东西，一律当独立可执行物验。

## 坑 2：降级路径必须跟主路径同等保证，否则降级 = 静默丢关键信息

`stager-plugin.mjs` 写死 `body.length > 2200` 就走 `briefSummary`。
实测 plan 的 `ai[]` 光 bullets 就 2654 字符 → **plan/implement/close 三个阶段每次都被砍**，
而旧 `briefSummary` 里**根本没有 `read[]`** → 「这阶段必读哪几份 md」被静默丢掉，
跟 AGENTS.md「不读不许动手」直接冲突，且**没有任何报错**。

**对策**：①阈值改成 `MAX_CTX_CHARS` 常量；②精简版与全量版共用同一套门禁计算（`gateState`）；
③**任何降级/兜底分支都要单独测**，并显式断言「降级后关键字段还在吗」。

## 坑 3：同一份事实只能有一个家 —— AGENTS.md 已被 opencode 每轮自动注入

`E:\restart developing doer\AGENTS.md` 里的内容会作为项目指令**每轮自动进上下文**
（会话里能看到 `Instructions from: E:\restart developing doer\AGENTS.md`）。
所以 AGENTS.md **本身就是索引**：阶段、必读清单、门禁、命令入口它都已经写了。
`stages.json` 的 `ai[]` 再抄一遍 = **每轮双份**，纯烧 context，且两份必然漂移。

**裁定（用户 2026-10-02）**：
- **AGENTS.md = 唯一索引**（阶段 / 必读 / 门禁）→ AI 读一遍就够，不必再打开任何 md。
- `ai[]` 只留**不在 AGENTS.md 里的增量**：①查经验库 ②外脑必问 ③本阶段独有硬动作。
- 插件注入砍到 ~10 行：只留活状态（现在在哪个阶段 / 门禁差什么 / 已交几份文档）。
- 瘦身幅度：四阶段 `ai[]` 合计 **10229 → 5613 字符**；全量注入正文 **4196 → 1808~2380 字符**。

## 坑 4：AI 侧通道的「查经验库」纯靠文本自觉，代码从不调 MCP

`Grep stager/**/*.js "memory_search_nodes|经验库|memory_search|memory_read_graph"` → **无命中**。
stager 代码从不碰 memory MCP，「动手前先查经验图谱」只是 `ai[]` 里的一句文本，
模型不照做就没人发现 —— 和「纪律写进文档不自动生效」是同一个病。

**对策**：想真的强制，得在插件钩子里程序化调用 memory（当前未做）；
现在只保证文本在每个阶段的 `ai[]` 里，且每阶段 ai[] 必含三块（经验库 / 外脑 / Goodhart）。
脚本校验：`ai[]` 里三块每阶段都在。

## 本轮改动清单

| 文件 | 改了什么 |
|---|---|
| `stager/core/stages.json` | 四阶段 `ai[]` 瘦身（common 块 + 各阶段增量）；read[] / gate / stages 顺序未动 |
| `stager/opencode-plugin/stager-plugin.mjs` | ①合掉重复 `fingerprintOf`、补回 `docRev` ②补 `readJson` 定义 ③`MAX_CTX_CHARS` 常量化 ④`briefSummary` 走共用 `gateState` ⑤删流水线表 / read[] 渲染 / 硬规矩 5 条，注入瘦到 ~10 行 ⑥删重复的任务行 |

**验证**：`stager self-test` = pass=39 fail=0；`probe-plugin2.mjs` 钩子 OK，注入 1 段 1920 字符，
四阶段全量正文 1808/1860/2212/2380 **全部 < 2500，不降级**。

⚠️ `probe-plugin2.mjs` 仍打印「精简版缺 read[]」—— 这是**预期**，
因为按裁定 read[] 已从注入里撤走（AGENTS.md 承担），旧断言该删。