'use strict';
// 补第二轮：全局卡的 W 层说明（句式不同）+ stages.json plan 阶段
const fs = require('fs');

const G = 'C:/Users/lenovo/.config/opencode/AGENTS.md';
const S = 'E:/restart developing doer/stager/core/stages.json';
const changed = [];

// ── 全局卡：W 层两条 bullet ──────────────────────────────────────
const gOld = '- 2026-09-29 实测：以为 W 层不可用，实际 **GLM 4760 字 + Kimi 1352 字**（Qwen 只 235 字，不可用）\n- **三方交叉才可信**；冲突时不要和稀泥，把分歧点列出来交给用户';
const gNew = [
  '- 2026-09-29 实测：以为 W 层不可用，实际 **GLM 4760 字 + Kimi 1352 字**',
  '- **Qwen 的历史坑（已解）**：之前 Qwen 只回 235 字，**真因不是模型不行，是每次都要人工过人机验证**（captcha），',
  '  只有用户能亲手划一次。**2026-09-29 用户已手动过了一遍，现在可用了。**',
  '  再遇到又要人机验证 → 直接说"需要你划一次验证"，别自己判成"Qwen 不可用"',
  '- **多方交叉才可信**（Codex + GLM + DeepSeek + Kimi + Qwen）；冲突时不要和稀泥，把分歧点列出来交给用户',
].join('\n');

let g = fs.readFileSync(G, 'utf8');
if (g.includes(gOld)) { g = g.split(gOld).join(gNew); fs.writeFileSync(G, g, 'utf8'); changed.push('全局卡 W 层说明'); }
else { console.log('  -- 全局卡：已是新版'); }

// ── stages.json：plan 阶段的 W 层说明 ────────────────────────────
let s = fs.readFileSync(S, 'utf8');
const sOld = '"    ② W 池互审（GLM 为主，可加 DeepSeek；固定画像/浏览器不许关）",';
const sNew = [
  '"    ② W 池互审 —— 池子 4 家：GLM(主打) / DeepSeek / Kimi / Qwen",',
  '"       能几家用几家，全通就用满 4 家，不为凑数硬跑",',
  '"       ★ qwen 之前只回 235 字，真因是每次要人工过人机验证(captcha)；",',
  '"         用户 2026-09-29 已手动过一遍，现在可用 —— 别再自己判成 Qwen 不可用",',
  '"       ★ 固定画像：profile 固定 + 浏览器不许关 + 记住上次用哪个",',
].join(',\n        ');

if (s.includes(sOld)) {
  s = s.replace(sOld, sNew);
  fs.writeFileSync(S, s, 'utf8');
  changed.push('stages.json plan 阶段 W 层');
} else if (s.includes('池子 4 家：GLM(主打) / DeepSeek / Kimi / Qwen')) {
  console.log('  -- stages.json：已是新版');
} else {
  console.log('  !! stages.json：没匹配到，请手工看');
}

// ── 校验 JSON 合法 ───────────────────────────────────────────────
try {
  const j = JSON.parse(fs.readFileSync(S, 'utf8'));
  const plan = j.stages.find((x) => x.id === 'plan');
  console.log('  ok   stages.json JSON 合法，' + j.stages.length + ' 阶段');
  const w4 = plan.ai.filter((x) => /GLM\(主打\).*DeepSeek.*Kimi.*Qwen/.test(x));
  console.log('  ok   plan 阶段已写明 4 家：' + (w4.length ? '是' : '否'));
} catch (e) {
  console.log('  FAIL stages.json JSON 坏了：' + e.message);
  process.exitCode = 1;
}

console.log('');
console.log(changed.length ? '★ 补改：' + changed.join(' / ') : '（无改动）');
