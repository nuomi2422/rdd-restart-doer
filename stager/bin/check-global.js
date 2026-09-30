'use strict';
// 合并后自检：全局卡 vs 工作区 B 版，条款齐全 + 无残留矛盾措辞
const fs = require('fs');
const G = 'C:/Users/lenovo/.config/opencode/AGENTS.md';
const B = 'E:/restart developing doer/AGENTS.md';
const g = fs.readFileSync(G, 'utf8');
const b = fs.readFileSync(B, 'utf8');

console.log('全局卡   ' + g.length + ' 字符, ' + g.split(/\r?\n/).length + ' 行');
console.log('工作区B版 ' + b.length + ' 字符, ' + b.split(/\r?\n/).length + ' 行');
console.log('');

// B 版每一条 H2 标题都要出现在全局卡里
const bH2 = b.split(/\r?\n/).filter((l) => /^## 第 /.test(l));
const miss = bH2.filter((h) => !g.includes(h));
console.log('B 版条款 ' + bH2.length + ' 条 → 全局卡缺 ' + miss.length + ' 条');
miss.forEach((h) => console.log('  MISS ' + h));

// 全局专属三块
const gOnly = ['第 12 条', '第 13 条', '第 14 条', 'provider 真源', '记忆库 / MCP 现状', '暗号 / 技能 / 交接', 'GLOBAL-ONLY:END'];
const missG = gOnly.filter((k) => !g.includes(k));
console.log('全局专属 7 项 → 缺 ' + missG.length + ' 项');
missG.forEach((k) => console.log('  MISS ' + k));

// 矛盾措辞
const bad = ['顺序不可颠倒', '从便宜到贵', '看不出才升', '≤10 分钟/次', 'Qwen 不用', '只回 235 字，不可用'];
const badHit = bad.filter((k) => g.includes(k));
console.log('矛盾措辞 6 项 → 残留 ' + badHit.length + ' 项');
badHit.forEach((k) => console.log('  BAD ' + k));

// 关键能力点（用宽松匹配，避免假阴性）
const must = [
  ['开 stage 硬门', /第一动作：开 stage/],
  ['GPT-6 稀缺默认不用', /稀缺额度.*默认不用/],
  ['W 池 4 家', /GLM\(主打\).*DeepSeek.*Kimi.*Qwen/],
  ['Qwen captcha 根因', /captcha/],
  ['固定画像 浏览器不许关', /浏览器绝对不许关/],
  ['找漏洞=随时能看', /排在第几位/],
  ['verify-tools 单一落点', /verify-tools/],
  ['给用户目录', /给用户/],
  ['每 3 轮 GLM 源码审', /每\s*(3|三)\s*轮[\s\S]{0,20}?GLM 源码审/],
  ['完成动作 5 步', /完成动作（顺序别乱）/],
  ['开游戏默认 2 小时', /默认\s*2\s*小时|开游戏一律默认 2 小时/],
  ['离线(2) 模式', /离线\(2\)/],
  ['动世界前备份', /备份当前存档\/自定义/],
  ['三个机器门', /① 阶段门禁|阶段门禁/],
  ['自报三段模板', /自报｜模式/],
];
const missM = must.filter((c) => !c[1].test(g)).map((c) => c[0]);
console.log('关键能力点 ' + must.length + ' 项 → 缺 ' + missM.length + ' 项');
missM.forEach((k) => console.log('  MISS ' + k));

const okAll = miss.length === 0 && missG.length === 0 && badHit.length === 0 && missM.length === 0;
console.log('');
console.log(okAll ? '★ 全局卡已自足：任何 cwd 的 AI 直接可用' : '✘ 还有 ' +
  (miss.length + missG.length + badHit.length + missM.length) + ' 项缺口');
process.exitCode = okAll ? 0 : 1;
