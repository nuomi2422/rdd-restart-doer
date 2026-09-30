'use strict';
/**
 * 规则文件冲突自查（正则版，兼容"全局卡已含 B 版全文"的合并形态）
 *
 * 查两件事：
 *   ① 有没有**矛盾措辞**残留（旧规则和新规则打架的信号）
 *   ② 关键能力点**在不在**
 *
 * 覆盖面检查（全局卡有没有漏掉 B 版的条款）→ 看 check-global.js
 */

const fs = require('fs');
const R = 'E:/restart developing doer';
const G = 'C:/Users/lenovo/.config/opencode/AGENTS.md';
const B = R + '/AGENTS.md';
const F = 'C:/Users/lenovo/.config/opencode/FLOW-MANDATE.md';
const g = fs.readFileSync(G, 'utf8');
const b = fs.readFileSync(B, 'utf8');
const f = fs.readFileSync(F, 'utf8');

console.log('全局卡   ' + g.length + ' 字符, ' + g.split(/\r?\n/).length + ' 行');
console.log('工作区B版 ' + b.length + ' 字符, ' + b.split(/\r?\n/).length + ' 行');
console.log('FLOW-MAND ' + f.length + ' 字符, ' + f.split(/\r?\n/).length + ' 行');
console.log('');
console.log('=== ① 矛盾措辞（出现 = 打架，必须 0）===');

// 每条：[说明, 旧/错措辞正则]
const bads = [
  ['「顺序不可颠倒」', /顺序不可颠倒/],
  ['「从便宜到贵」', /从便宜到贵/],
  ['「看不出才升 ④」', /看不出才升/],
  ['「≤10 分钟/次」旧 MC 时长', /≤10\s*分钟\/次/],
  ['「≤60」旧 MC 时长', /不在\s*\*?\*?≤60/],
  ['「Qwen 不用」', /Qwen 不用/],
  ['「Qwen 只 235 字，不可用」', /Qwen 只 235 字，不可用/],
  ['「两个都要过」（实际列了三个门）', /机器门（两个/],
  ['手写 gradle 建议', /建议手动 Copy-Item/],
  ['「第 1 次跑请先看 README」', /先看.*README.*再开工/],
];
let bad = 0;
bads.forEach((c) => {
  const hitG = c[1].test(g), hitB = c[1].test(b);
  const bad_ = hitG || hitB;
  if (bad_) bad++;
  console.log((bad_ ? '  BAD  ' : '  ok   ') + c[0] + (hitG ? ' [全局卡]' : '') + (hitB ? ' [B版]' : ''));
});

console.log('');
console.log('=== ② 关键能力点（缺 = 要补）===');
const musts = [
  ['第0条 开 stage 硬门', /第一动作：开 stage/],
  ['自报三段模板', /自报｜模式/],
  ['4 阶段流水线', /四阶段流水线|① 计划统筹/],
  ['每阶段必读 md', /该阶段必读的 md 清单|· 必读/],
  ['GPT-6 稀缺默认不用', /稀缺额度[\s\S]{0,20}默认不用/],
  ['W 池 4 家', /GLM\(主打\)[\s\S]{0,30}DeepSeek[\s\S]{0,20}Kimi[\s\S]{0,20}Qwen/],
  ['Qwen captcha 根因', /人机验证/],
  ['固定画像 浏览器不许关', /浏览器绝对不许关/],
  ['找漏洞=随时能看不是排队', /排在第几位/],
  ['OpenClaw 验证剧本', /创造模式/],
  ['verify-tools 单一落点', /verify-tools/],
  ['给用户目录 + publish', /给用户/],
  ['每 3 轮 GLM 源码审', /每\s*(3|三)\s*轮[\s\S]{0,20}?GLM 源码审/],
  ['完成动作 5 步', /完成动作（顺序别乱）/],
  ['三个机器门', /① 阶段门禁/],
  ['开游戏默认 2 小时', /默认\s*2\s*小时/],
  ['离线(2) 模式', /离线\(2\)/],
  ['动世界前备份自定义', /备份当前存档\/自定义/],
];
let miss = 0;
musts.forEach((c) => {
  const okG = c[1].test(g), okB = c[1].test(b);
  const o = okG || okB;
  if (!o) miss++;
  console.log((o ? '  ok   ' : '  MISS ') + c[0] + (okG && okB ? ' [两份都有]' : okG ? ' [仅全局卡]' : okB ? ' [仅B版]' : ''));
});

console.log('');
const okAll = bad === 0 && miss === 0;
console.log(okAll ? '★ 无矛盾 (' + bads.length + ' 项) + 能力点齐全 (' + musts.length + ' 项)'
  : '✘ 矛盾 ' + bad + ' 项，缺口 ' + miss + ' 项');
process.exitCode = okAll ? 0 : 1;
