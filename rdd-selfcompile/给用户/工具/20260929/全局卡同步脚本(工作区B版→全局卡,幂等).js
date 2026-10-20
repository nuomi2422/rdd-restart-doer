'use strict';
/**
 * 把工作区 B 版（可执行流水线，460 行）合并进**全局卡**，做成自足的一份。
 *
 * 为什么要合而不是只留指针：
 *   - 全局卡 `~/.config/opencode/AGENTS.md` 在**每个会话**的系统提示里，不管在哪个 cwd
 *   - 工作区 `D:\rdd\workspace\AGENTS.md` 只在这个工作区生效
 *   - 之前全局卡只写"细则在工作区 B 版" → AI 换个目录就找不到规则 = 直接失效
 *
 * 合并规则：
 *   主体 = B 版全文（阶段/门禁/必读/判据/找漏洞/写工具/放哪/改流程）
 *   追加 = 全局卡独有的 3 块（provider 真源 / 记忆库 MCP 现状 / 模式暗号与技能）
 *   头部 = 说明这是全局版 + 与工作区版同源 + 备份位置
 *
 * 幂等：重复跑不会叠加（先剥掉旧追加段再拼）
 */

const fs = require('fs');
const path = require('path');
const G = 'C:/Users/admin/.config/opencode/AGENTS.md';
const B = 'D:/rdd/workspace/AGENTS.md';
const MARK_A = '\n<!-- ===== GLOBAL-ONLY:BEGIN ===== -->';
const MARK_B = '<!-- ===== GLOBAL-ONLY:END ===== -->\n';

// ── 备份（只备一次，同名不覆盖） ────────────────────────────────
const bdir = path.join('C:/Users/admin/.config/opencode/AGENTS.backup');
if (!fs.existsSync(bdir)) fs.mkdirSync(bdir, { recursive: true });
const cur = fs.readFileSync(G, 'utf8');
const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
const bk = path.join(bdir, 'AGENTS-' + stamp + '-pre-global-merge.md');
fs.writeFileSync(bk, cur, 'utf8');
console.log('备份 → ' + bk + '  (' + cur.length + ' 字符)');

// ── B 版主体：剥掉旧标题块，换成全局版头 ────────────────────────
let b = fs.readFileSync(B, 'utf8');
// 剥掉 B 版的旧 header（第 1 行到第一个 "## " 之前）
const firstH2 = b.indexOf('\n## ');
b = b.slice(firstH2 + 1);
// 剥掉 B 版里"本文件是工作区版"的自我说明（若有）
b = b.replace(/^> 用户 2026-09-29.*\n(>.*\n)*\n/m, '');

const header = [
  '# opencode · RDD 工作规则（B 版 · 全局已覆盖 · 2026-09-29）',
  '',
  '> **本文件是每个会话都在系统提示里的那一份**，任何工作目录的 AI 都能直接用 —— 不用切目录、不用找指针。',
  '> 与工作区版同源（内容一致）：`D:\\rdd\\workspace\\AGENTS.md`（改那边 → 重跑 `stager\\bin\\merge-global.js` 同步过来）',
  '> 细则正文：`D:\\rdd\\docs\\rdd-docs\\rdd架构\\自编译统一版\\`（`INDEX.md` → `README.md` → `01-工程规范` → `10-总流程` → `06-检查清单`）',
  '> 阶段状态机：`D:\\rdd\\workspace\\stager\\`（第 0 条那条就是它）',
  '> 备份：`AGENTS.backup\\AGENTS-' + stamp + '-pre-global-merge.md`（合并之前那份）',
  '',
  '---',
  '',
].join('\n');

// ── 全局卡独有的三块（工作区 B 版里没有的） ────────────────────
const globalOnly = MARK_A + '\n\n' + [
  '## 第 12 条 · provider 真源（全局专属 · 别按不存在的机制做规划）',
  '',
  '- **默认模型 = `moyuu/gpt-6-astra`**：中转 `https://moyuu.cc/v1`，key 来自 cc-switch 的 `My` 供应商（2026-09-28 实测 `chat/completions` 与 `responses` 双端点均通）。**架构决策/深审就用它**。',
  '- 该 key **喂不动 `gpt-5.6-terra`（503）**；实测中转站只有 `gpt-6-astra` 稳定，其余 5 个模型报 500/503 → opencode 里**只用 `gpt-6-astra`**。',
  '- `small_model` = `opencode/big-pickle`（免费，只做标题生成）。',
  '- **「多 provider 自动降级」不成立**（429/5xx 要人工 `/model` 切）。',
  '- **Codex CLI 也统一到这把 key**：`~/.codex/auth.json` + `config.toml` 的 `name="My"` / `model="gpt-6-astra"`。',
  '- **GPT-6 额度纪律**：稀缺额度，**默认不用**（见 §2.1）。额度用完就跳过，不等不换不硬凑。',
  '',
  '---',
  '',
  '## 第 13 条 · 记忆库 / MCP 现状（全局专属 · 实测，别凭印象）',
  '',
  '- **memory 图谱此前一直是空的**（经验都进了文档没进图谱）→ 空库→查了没用→更不查 的正反馈坑。现已灌入 17 条。**别只写文档不进图谱。**',
  '- `experience-core` 已上线（3 工具 `learn_learn` / `recall` / `verify`）；**`VectorExperienceRetriever` 接缝留着但未实现**。',
  '- **语义检索最小可行替代**（GLM+Kimi 一致）：**结构化 tag + 词法优先**。「Minecraft 是封闭域、词 gap 小」→ 向量是锦上添花。**别硬凑 top-5，返 0 条比凑 5 条好。**',
  '- **跨插件唯一门面 = `NumenApi`**（`numumen-plugin.gradle:37-44` 刻意封死跨插件 import；历史事故：rdd 内嵌 ac-core 撞 JPMS `ResolutionException`）。',
  '- `test` 实例 `[openai] api_key` **原为 EMPTY** → **验 LLM 链路必须用 `gpt` 实例**。',
  '',
  '---',
  '',
  '## 第 14 条 · 暗号 / 技能 / 交接（全局专属）',
  '',
  '| 项 | 是什么 |',
  '|---|---|',
  '| 模式暗号 | **1=人工 / 2=自动 / 离线（2）** |',
  '| 能力暗号 | `数字1~4`（`skills/` 目录）：`1`=长任务轮询通关MC ｜ `4`=特殊模式工程闭环 |',
  '| 技能 | `C:\\Users\\admin\\.config\\opencode\\skills`（含 `~/.agents/skills`、`~/.claude/skills`） |',
  '| 接手先看 | `D:\\rdd\\docs\\rdd-docs\\rdd架构\\self-compile-handoff.md`（不靠口头上下文即可接手） |',
  '| stager 交接 | `stager\\STAGER.md`（给 AI） + `stager\\README.md`（给人） |',
  '| 换人接手 | `stager swap "<你的名字>"` → `stager ctx --full`（把历史文档全文注入） |',
  '',
  '**本轮新资产（2026-09-29）**',
  '',
  '| 资产 | 干什么 |',
  '|---|---|',
  '| `stager\\` | 4 阶段状态机 + 门禁 + 文档注入 + 换人次 + 桌面宠物（9 表情） |',
  '| `loop-gate.js` | 九步流硬门禁（20 项，mtime + 正文签名双重把关） |',
  '| `collect-evidence.ps1` | 五件证据采集（让 verify 终于是 VERIFIED） |',
  '| `scripts\\verify-tools\\` | 我自写验证工具的**唯一**落点 |',
  '| `rdd-selfcompile\\给用户\\` | 要给你看/用的东西的**唯一**落点（`stager publish` 自动登记 INDEX） |',
  '| `w-platforms.json` | W 池 4 家：GLM(主打) / DeepSeek / Kimi / Qwen |',
  '| `plugins/learner` | 学习者 v1 ｜ `30-主要功能不回退清单.md` |',
  '',
  MARK_B,
].join('\n') + '\n';

// ── 拼装（幂等：先剥旧段） ───────────────────────────────────────
let out = header + b;
out = out.replace(/\n<!-- ===== GLOBAL-ONLY:BEGIN ===== -->[\s\S]*?<!-- ===== GLOBAL-ONLY:END ===== -->\n/, '\n');
out = out.replace(/\n{4,}/g, '\n\n\n') + '\n' + globalOnly;
fs.writeFileSync(G, out, 'utf8');

const x = fs.readFileSync(G, 'utf8');
console.log('全局卡合并后: ' + x.length + ' 字符, ' + x.split(/\r?\n/).length + ' 行');
console.log('含 B 版全部条款: ' +
  ['第 0 条', '第 1 条', '第 8 条', '第 11 条', 'provider 真源', '记忆库 / MCP 现状', '暗号 / 技能']
    .every((k) => x.includes(k)) ? '是' : '否（要查）');
