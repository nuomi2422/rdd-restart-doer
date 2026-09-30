'use strict';
// 全局卡 vs 工作区 B 版 —— 冲突自查
const fs = require('fs');
const G = 'C:/Users/lenovo/.config/opencode/AGENTS.md';
const B = 'E:/restart developing doer/AGENTS.md';
const t = fs.readFileSync(G, 'utf8');
const b = fs.readFileSync(B, 'utf8');

console.log('全局卡 ' + t.length + ' 字符, ' + t.split(/\r?\n/).length + ' 行');
console.log('工作区B版 ' + b.length + ' 字符, ' + b.split(/\r?\n/).length + ' 行');
console.log('');
console.log('=== 冲突自查 ===');

const checks = [
  ['旧措辞「顺序不可颠倒」已删', !t.includes('顺序不可颠倒')],
  ['旧措辞「从便宜到贵」已删', !t.includes('从便宜到贵')],
  ['旧措辞「③ 看不出才升 ④」已删', !t.includes('看不出才升')],
  ['有 stager 硬门（§0.0）', t.includes('第一动作：开 stage')],
  ['自报模板含离线(2)', t.includes('离线(2)')],
  ['MC 默认 2 小时', t.includes('开游戏默认 2 小时')],
  ['旧的「≤10 分钟/次」已删', !t.includes('≤10 分钟/次')],
  ['GPT-6 默认不用', t.includes('GPT-6 是稀缺额度，默认不用')],
  ['固定画像：浏览器不许关', t.includes('浏览器绝对不许关')],
  ['固定画像：记住上次用哪个', t.includes('记住上次用的是哪个')],
  ['收工门 3 个（check/loop/flow）', t.includes('① 阶段门禁') && t.includes('② 九步流硬门禁') && t.includes('③ 自编译闭环门')],
  ['找漏洞=随时能看不是排队', t.includes('排在第几位')],
  ['verify-tools 单一落点', t.includes('verify-tools')],
  ['给用户目录规则', t.includes('给用户')],
  ['每 3 轮 GLM 源码审', t.includes('每 3 轮 · GLM 源码审')],
  ['冲突裁定条款', t.includes('有冲突以工作区 B 版为准')],
  ['完成动作 5 步', t.includes('完成动作（顺序别乱）')],
  ['开游戏前备份自定义', t.includes('备份当前存档/自定义')],
  ['端口真源仍对', t.includes('test=8766') && t.includes('gpt=8776')],
  ['无乱码（关键锚点可读）', t.includes('第一动作：开 stage') && t.includes('阶段门禁')],
];

let bad = 0;
checks.forEach(function (c) {
  console.log((c[1] ? '  ok   ' : '  FAIL ') + c[0]);
  if (!c[1]) bad++;
});
console.log('');
console.log(bad === 0 ? '★ 全部通过（' + checks.length + ' 项）' : (bad + ' 项没过'));
process.exitCode = bad ? 1 : 0;
