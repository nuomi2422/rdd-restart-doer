'use strict';
// 三份规则文件的分工自检（2026-10-04 改了契约）
//
// 背景：stage 流从 AGENTS.md 搬进了 rddharness\stage.md 之后，
// 「AGENTS.md 是唯一承载全部细则的那份」这个前提不成立了。
// 原来的 check-align.js 按那个前提跑，于是把「细则搬走了」误报成 14 项缺口 ——
// 门禁一旦长期红就等于没有门禁（同 P10 / P10b / Q9 那条教训）。
//
// 新契约：细则分三层，各层自己查自己那份有没有漏。
//   ① 全局卡（指针）  —— 不承载细则，只承载指针 + 摘要   → 真问题由 check-global.js 查
//   ② 外层 AGENTS.md  —— 工程纪律 + 杂项 + 索引地图
//   ③ stage.md        —— stage 流（四阶段/必读/机器门/完成动作/改流程）
const fs = require('fs');
const path = require('path');

const G = 'C:/Users/lenovo/.config/opencode/AGENTS.md';
const B = 'E:/restart developing doer/AGENTS.md';
const F = 'C:/Users/lenovo/.config/opencode/FLOW-MANDATE.md';
const STAGE = 'E:/新建文件夹/rddharness/stage.md';

const g = fs.existsSync(G) ? fs.readFileSync(G, 'utf8') : '';
const b = fs.readFileSync(B, 'utf8');
const f = fs.existsSync(F) ? fs.readFileSync(F, 'utf8') : '';
const s = fs.existsSync(STAGE) ? fs.readFileSync(STAGE, 'utf8') : '';

console.log('全局卡   ' + g.length + ' 字符, ' + g.split(/\r?\n/).length + ' 行');
console.log('外层 B 版 ' + b.length + ' 字符, ' + b.split(/\r?\n/).length + ' 行');
console.log('FLOW-MANDATE ' + f.length + ' 字符');
console.log('stage.md ' + s.length + ' 字符, ' + s.split(/\r?\n/).length + ' 行');
console.log('');

const bad = [], warn = [], good = [];

// ① 矛盾措辞（出现即打架，0 容忍 —— 这条跨三层都查）
const CONFLICT = [
  '顺序不可颠倒', '从便宜到贵', '看不出才升', '≤10 分钟/次', '≤60',
  'Qwen 不用', 'Qwen 只 235 字，不可用', '两个都要过', '手写 gradle 建议',
];
const hitC = CONFLICT.filter((k) => g.includes(k) || b.includes(k) || s.includes(k));
if (hitC.length === 0) good.push('矛盾措辞 ' + CONFLICT.length + ' 项：三层全部清干净');
else bad.push('矛盾措辞残留：' + hitC.join(' / '));

// ② 外层 B 版必须承载的：工程纪律 + 杂项 + 索引
const B_NEED = [
  ['编译唯一通道', /run-mutation\.ps1/],
  ['精确 add 禁 -A', /git add -A/],
  ['commit -F msg.txt', /msg\.txt/],
  ['源码改了≠运行时生效', /check-runtime-deployment/],
  ['改路径全仓 grep', /改路径必须全仓 grep/],
  ['PS 5.1 BOM 坑', /UTF-8 BOM/],
  ['node -e 引号坑', /node -e/],
  ['MCP live=8765', /8765/],
  ['监测台 live=8776', /8776/],
  ['游戏日志 GBK', /GBK/],
  ['实例叫法表', /实例叫法/],
  ['工作区地图', /本工作区地图/],
  ['套娃仓库 6 个', /6 个 git 仓库/],
  ['repo-status 跨仓库对账', /repo-status\.js/],
  ['plugins/selfcompile ≠ 改码通道', /plugins\/selfcompile/],
  ['harness 指针', /rddharness/],
  ['交接与资产', /交接与资产/],
  ['用户唯一收件箱', /rdd存放/],
];
const missB = B_NEED.filter((x) => !x[1].test(b)).map((x) => x[0]);
if (missB.length === 0) good.push('外层 B 版工程纪律 ' + B_NEED.length + ' 项齐全');
else bad.push('外层 B 版缺：' + missB.join(' / '));

// ③ 外层 B 版**不该**再有的：stage 流（搬走了就别留着，留着就变成第二份副本）
//    ⚠️ 只查**内容级标记**。像「四阶段流水线 / 阶段必读 / 机器门」这种词，
//    外层第 0 条那句「★ 四阶段流水线……全在 stage.md」的点名是应该有的，
//    按词查会把这个检查变成永红的假警报（同 P10 / P10b / Q9 的教训）。
const B_SHOULDNT = [
  ['四阶段流水线图', /① 计划统筹 plan/],
  ['阶段必读小节表', /### ① 计划统筹 · 必读/],
  ['完成动作清单', /完成动作（顺序别乱）/],
  ['loop-gate 命令', /loop-gate\.js/],
  ['flow-gate 命令', /flow-gate\.js/],
  ['GLM 源码审', /GLM 源码审/],
];
const leakB = B_SHOULDNT.filter((x) => x[1].test(b)).map((x) => x[0]);
if (leakB.length === 0) good.push('外层 B 版没有 stage 流残留（' + B_SHOULDNT.length + ' 项都不在）');
else bad.push('外层 B 版还在承载 stage 流：' + leakB.join(' / ') + '（应只在 stage.md）');

// ④ stage.md 必须承载的：stage 流全套
const S_NEED = [
  ['四阶段流水线', /四阶段流水线/],
  ['四阶段门禁表', /计划统筹/],
  ['① 计划统筹 必读', /### ① 计划统筹 · 必读/],
  ['② 编码实现 必读', /### ② 编码实现 · 必读/],
  ['③ 游戏验证 必读', /### ③ 游戏验证 · 必读/],
  ['④ 记录收口 必读', /### ④ 记录收口 · 必读/],
  ['机器门 loop-gate', /loop-gate\.js/],
  ['机器门 flow-gate', /flow-gate\.js/],
  ['阶段门禁 stager check', /stager\.js" check|bin\\stager\.js check|stager check/],
  ['完成动作', /完成动作（顺序别乱）/],
  ['进游戏前必读 清单', /进游戏前必读-游戏内能力清单\.md/],
  ['GLM 源码审', /GLM 源码审/],
  ['改流程 stages.json', /stages\.json/],
  ['stager 交接', /STAGER\.md|swap/],
];
const missS = S_NEED.filter((x) => !x[1].test(s)).map((x) => x[0]);
if (missS.length === 0) good.push('stage.md 承载 stage 流 ' + S_NEED.length + ' 项齐全');
else bad.push('stage.md 缺：' + missS.join(' / '));

// ⑤ FLOW-MANDATE.md 指向的 AGENTS.md 小节是否还在（它引的是「第 N 条」）
const fmRefs = [...f.matchAll(/第\s*([0-9\-−]+)\s*条/g)].map((m) => m[1]);
const deadRef = fmRefs.filter((n) => !new RegExp('^##+ 第 ' + n.replace('−', '-') + ' 条', 'm').test(b + '\n' + s));
if (fmRefs.length === 0) good.push('FLOW-MANDATE.md 没有硬指小节号的引用');
else if (deadRef.length === 0) good.push('FLOW-MANDATE.md 引用的 ' + fmRefs.length + ' 个小节号在 B版/stage.md 里都还在');
else warn.push('FLOW-MANDATE.md 引的小节号已经不存在：' + deadRef.join(' / ') + '（B版瘦身了，要么改引用要么改 FLOW-MANDATE）');

// ⑥ 三份路径存在性
const P = ['E:/新建文件夹/rddharness/stage.md', 'E:/新建文件夹/rddharness/进游戏前必读-游戏内能力清单.md'];
const missP = P.filter((p) => !fs.existsSync(p));
if (missP.length === 0) good.push('细则两份文件真实存在');
else bad.push('文件不存在：' + missP.join(' / '));

good.forEach((x) => console.log('  PASS  ' + x));
warn.forEach((x) => console.log('  WARN  ' + x));
bad.forEach((x) => console.log('  BLOCK ' + x));
console.log('');
console.log(bad.length === 0
  ? '★ 三层分工一致：' + good.length + ' 项全过' + (warn.length ? '，' + warn.length + ' 项提醒' : '')
  : '✘ ' + bad.length + ' 项缺口（' + good.length + ' 项过' + (warn.length ? '，' + warn.length + ' 项提醒' : '') + '）');
process.exitCode = bad.length === 0 ? 0 : 1;