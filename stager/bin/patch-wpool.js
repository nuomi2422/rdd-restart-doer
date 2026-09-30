'use strict';
/**
 * W 池扩容：glm / deepseek / kimi / qwen 四家
 * 背景（用户 2026-09-29 口述）：
 *   - DeepSeek 正式作为 W 池候选
 *   - Qwen 之前不可用的真因 = 每次都要人工过人机验证（captcha），只有用户能亲手划
 *   - 用户已经手动过了一遍 → Qwen 现在可用了
 *   - "偶尔能四个都用就四个都用" → 不强制，能几家就几家，全通就用满 4 家
 *
 * 改这些文件：
 *   1) scripts/w-platforms.json         加 deepseek 平台（askAll 自动遍历它）
 *   2) 全局卡 AGENTS.md                §2.2 W 层表述
 *   3) 工作区 B 版 AGENTS.md           §2 外脑分工表 + 交叉可信度那句
 *   4) AGENTS.md.draft-B.md            同上（草稿原件保持同步）
 *   5) stager/core/stages.json         plan 阶段的 W 层说明
 *   6) stager/STAGER.md                阶段表里的互审说明
 */

const fs = require('fs');
const path = require('path');
const R = 'E:/restart developing doer';
const G = 'C:/Users/lenovo/.config/opencode';
const changed = [];

function patch(file, pairs, label) {
  if (!fs.existsSync(file)) { console.log('  MISS ' + label); return; }
  let t = fs.readFileSync(file, 'utf8');
  const before = t;
  let n = 0;
  for (const [from, to] of pairs) {
    if (t.includes(from)) { t = t.split(from).join(to); n++; }
  }
  if (t !== before) {
    fs.writeFileSync(file, t, 'utf8');
    changed.push(label + ' (' + n + ' 处)');
    console.log('  ok   ' + label + ' — 改了 ' + n + ' 处');
  } else {
    console.log('  --   ' + label + ' — 无需改（已是新版）');
  }
}

// ── 1) w-platforms.json：加 deepseek ──────────────────────────────
const wp = path.join(R, 'rdd-selfcompile', 'scripts', 'w-platforms.json');
let w = fs.readFileSync(wp, 'utf8');
const wj = JSON.parse(w);
if (!wj.deepseek) {
  // 插到 glm 后面（GLM 是主打，DeepSeek 第二）
  const rebuilt = {};
  for (const [k, v] of Object.entries(wj)) {
    rebuilt[k] = v;
    if (k === 'glm') {
      rebuilt.deepseek = {
        url: 'https://chat.deepseek.com/',
        open: 'https://chat.deepseek.com/',
        input: ['textarea', 'div[contenteditable="true"]', '[contenteditable="true"]'],
        reply: ['[class*="markdown"]', '[class*="fbb737a4"]', '.markdown-body', '[class*="response"]', 'main'],
        stop: ['button[aria-label*="停止"]', 'button[aria-label*="Stop"]', '[class*="stop"]'],
        continue: ['继续生成', 'Continue'],
        _note: '2026-09-29 用户批准加入 W 池。找不到回复元素时用 w-brain-drive.js dump deepseek 核对选择器。',
      };
    }
  }
  rebuilt._comment = '特殊模式 W 层平台选择器覆盖文件（w-brain-drive.js 的 DEFAULT_PLATFORMS 在此之上合并）。' +
    'url/open/input[]/reply[]/send[]/stop[]/continue[]。selector 失效时用 probe 页面人工核对。' +
    '｜池子共 4 家：glm(主打) / deepseek / kimi / qwen。' +
    '｜qwen 历史问题：每次都要人工过人机验证(captcha)，只有用户能亲手划；2026-09-29 用户已手动过一遍，现在可用。' +
    '｜原则：能几家用几家，全通就用满 4 家，不为了凑数硬跑。';
  fs.writeFileSync(wp, JSON.stringify(rebuilt, null, 2), 'utf8');
  changed.push('w-platforms.json (+deepseek)');
  console.log('  ok   w-platforms.json — 已加 deepseek，池子 = ' +
    Object.keys(rebuilt).filter((k) => !k.startsWith('_')).join('/'));
} else {
  console.log('  --   w-platforms.json — deepseek 已存在');
}

// ── 2~4) 三份规则文档 ────────────────────────────────────────────
const OLD_TBL_G = '| W | 网页免费模型 **GLM 为主**（可加 DeepSeek，池子共 4 家；Qwen 不用） |';
const NEW_TBL_G = '| W | 网页免费模型 **4 家：GLM(主打) / DeepSeek / Kimi / Qwen** |';

const OLD_TBL_B = '| **任意难度 / 架构级** | **W 池**（主 GLM，可加 DeepSeek，池子共 **4** 家）互审 |';
const NEW_TBL_B = '| **任意难度 / 架构级** | **W 池 4 家互审：GLM(主打) / DeepSeek / Kimi / Qwen**（能几家用几家，全通就用满） |';

const OLD_NOTE = '> 2026-09-29 实测：以为 W 层不可用，实际 **GLM 4760 字 + Kimi 1352 字**（Qwen 只 235 字，不可用）。\n> **三方交叉才可信**（Codex + GLM + Kimi）；单个外脑会编。';
const NEW_NOTE = [
  '> **池子共 4 家：GLM(主打) / DeepSeek / Kimi / Qwen。** 能几家用几家，**全通就用满 4 家**，不为凑数硬跑。',
  '>',
  '> **Qwen 的历史坑（已解）**：之前 Qwen 只回 235 字，**真因不是模型不行，是每次都要人工过人机验证**',
  '> （captcha），只有用户能亲手划一次。**2026-09-29 用户已手动过了一遍，现在可用了。**',
  '> 再遇到又要人机验证时 → 直接说"需要你划一次验证"，别自己判成"Qwen 不可用"。',
  '>',
  '> 2026-09-29 实测：以为 W 层不可用，实际 **GLM 4760 字 + Kimi 1352 字**。',
  '> **多方交叉才可信**（Codex + GLM + DeepSeek + Kimi + Qwen）；单个外脑会编。',
].join('\n');

const OLD_STAGES = '"W 池互审：架构级/任何难度都走。GLM 为主，可加 DeepSeek，池子共 4 家。",';
const NEW_STAGES = '"W 池互审：架构级/任何难度都走。池子 4 家：GLM(主打)/DeepSeek/Kimi/Qwen。",\n        "  能几家用几家，全通就用满 4 家；不为凑数硬跑。qwen 之前只回 235 字是因为要人工过人机验证",\n        "  （captcha），用户 2026-09-29 已手动过一遍，现在可用 —— 别再自己判成 Qwen 不可用。",';

patch(path.join(G, 'AGENTS.md'), [[OLD_TBL_G, NEW_TBL_G], [OLD_NOTE, NEW_NOTE]], '全局卡 AGENTS.md');
patch(path.join(R, 'AGENTS.md'), [[OLD_TBL_B, NEW_TBL_B], [OLD_NOTE, NEW_NOTE]], '工作区 AGENTS.md (B 版)');
patch(path.join(R, 'AGENTS.md.draft-B.md'), [[OLD_TBL_B, NEW_TBL_B], [OLD_NOTE, NEW_NOTE]], '草稿原件 draft-B.md');
patch(path.join(R, 'stager', 'core', 'stages.json'), [[OLD_STAGES, NEW_STAGES]], 'stager stages.json');

console.log('');
console.log(changed.length ? '★ 改动：\n  ' + changed.join('\n  ') : '（无改动）');
