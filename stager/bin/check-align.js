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

const G = 'C:/Users/admin/.config/opencode/AGENTS.md';
const B = 'D:/rdd/workspace/AGENTS.md';
const F = 'C:/Users/admin/.config/opencode/FLOW-MANDATE.md';
const STAGE = 'D:/rdd/harness/rdd-harness/stage.md';

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
const P = ['D:/rdd/harness/rdd-harness/stage.md', 'D:/rdd/harness/rdd-harness/进游戏前必读-游戏内能力清单.md'];
const missP = P.filter((p) => !fs.existsSync(p));
if (missP.length === 0) good.push('细则两份文件真实存在');
else bad.push('文件不存在：' + missP.join(' / '));

// ⑦ stages.json ↔ harness 的接线（2026-10-04 加：进出游戏 = 换阶段提示）
//    这条查的是「声明在 stages.json 里的东西是不是真的存在/一致」：
//    · $harnessGate 的两个命令指向的门禁脚本必须在
//    · 四个阶段每个都必须有 harness 字段（不然某个阶段会静默不提示）
//    · harness.cmd 与 ai[] 里给 AI 的那行命令必须指向同一个 mode（preflight/postflight）
//      —— 这两条如果不一致，AI 照 ai[] 跑，而门禁按 cmd 判，永远对不上
//    · stage.md 必须也承载同一套（不然 AI 读 stage.md 时看不到进出游戏提示）
//    ★ 与 P4/P10/Q7/Q9/bug-10 同族的第 8 个教训：声明 ≠ 接线。
const SJ = 'D:/rdd/workspace/stager/core/stages.json';
try {
  const sj = JSON.parse(fs.readFileSync(SJ, 'utf8'));
  const HG = sj['$harnessGate'] || {};
  if (!HG.gateExe || !fs.existsSync(HG.gateExe)) bad.push('stages.json 的 $harnessGate.gateExe 指向的门禁脚本不存在：' + HG.gateExe);
  const noHook = sj.stages.filter((x) => !x.harness);
  if (noHook.length === 0) good.push('stages.json 四个阶段都挂了 harness 提示');
  else bad.push('这几个阶段没挂 harness 提示（会在该阶段静默不提醒进出游戏）：' + noHook.map((x) => x.id).join(' / '));
  // ★ 判据从 harness.cmd 改成 harness.mode —— 2026-10-04 stages.json 里那四个
  //   harness.cmd 写的全是字面量 "$harnessGate.cmdPre"，而 **stager.js 不解析 $ 引用**，
  //   那串永远不会被执行（属"空头支票"那一族）。改成语义字段 mode 后，
  //   「唯一可执行的命令在 ai[] 里，mode 只是声明」这条分工才是真的。
  const badMode = sj.stages.filter((x) => x.harness && !['preflight', 'postflight'].includes(x.harness.mode));
  if (badMode.length === 0) good.push('每阶段 harness.mode 都是 preflight/postflight（没有假引用字符串）');
  else bad.push('这阶段的 harness.mode 不是 preflight/postflight：' + badMode.map((x) => x.id).join(' / '));
  const stillCmd = sj.stages.filter((x) => x.harness && x.harness.cmd);
  if (stillCmd.length === 0) good.push('harness.cmd 已全部去掉（那是不会被执行的空头支票）');
  else bad.push('harness.cmd 还在：' + stillCmd.map((x) => x.id).join(' / ') + ' —— stager.js 不解析 $ 引用');
  const modeMismatch = sj.stages.filter((x) => {
    if (!x.harness || !x.harness.mode) return false;
    const aiTxt = (x.ai || []).join('\n');
    return !new RegExp('harness-gate\\.js" ' + x.harness.mode).test(aiTxt);
  });
  if (modeMismatch.length === 0) good.push('每阶段 harness.mode 与 ai[] 给的命令 mode 一致');
  else bad.push('harness.mode 与 ai[] 里的命令 mode 对不上（AI 会照 ai[] 跑，门禁按 mode 判）：' + modeMismatch.map((x) => x.id).join(' / '));
  // stage.md 也得承载同一套，否则 AI 读细则时看不到
  const S_HOOK = [
    ['进出游戏 = 换阶段提示', /进出游戏\s*=\s*换阶段提示/],
    ['preflight 命令', /harness-gate\.js" preflight/],
    ['postflight 命令', /harness-gate\.js" postflight/],
    ['ASK 提示说明', /☞/],
    ['退出码 0/1/3', /exit=0[\s\S]{0,40}1[\s\S]{0,40}3|退出码/],
    ['外脑可选', /外脑[\s\S]{0,10}可选/],
    ['能力清单指向', /进游戏前必读-游戏内能力清单\.md/],
    ['arch 是防迷路的锚', /防迷路的锚/],
  ];
  const missHook = S_HOOK.filter((x) => !x[1].test(s)).map((x) => x[0]);
  if (missHook.length === 0) good.push('stage.md 承载了同一套进出游戏提示与外脑可选规则');
  else bad.push('stage.md 缺：' + missHook.join(' / ') + '（stages.json 已经声明了，细则却没写 → 又一次两份文件漂移）');
  // stages.json 里不得再有「外脑必问」这种与新裁定矛盾的措辞
  const sjRaw = fs.readFileSync(SJ, 'utf8');
  if (!/外脑必问/.test(sjRaw)) good.push('stages.json 里没有与「外脑可选」矛盾的措辞');
  else bad.push('stages.json 里还有「外脑必问」—— 与 2026-10-04「外脑降为可选」的裁定矛盾');
} catch (e) {
  bad.push('stages.json 读不了或格式错：' + e.message);
}

good.forEach((x) => console.log('  PASS  ' + x));
warn.forEach((x) => console.log('  WARN  ' + x));
bad.forEach((x) => console.log('  BLOCK ' + x));
console.log('');
console.log(bad.length === 0
  ? '★ 三层分工一致：' + good.length + ' 项全过' + (warn.length ? '，' + warn.length + ' 项提醒' : '')
  : '✘ ' + bad.length + ' 项缺口（' + good.length + ' 项过' + (warn.length ? '，' + warn.length + ' 项提醒' : '') + '）');
process.exitCode = bad.length === 0 ? 0 : 1;