'use strict';
// 全局卡自检（2026-10-04 起改了契约）
//
// 背景：AGENTS.md 瘦身后，**全局卡不再是它的全文副本，而是一张指针卡**。
// 原来的「全局卡必须逐条承载 B 版全文」这个契约已经不成立了 —— 那样正是
// 182 行漂移的成因（TL-2026-10-04-03）。新契约是：
//
//   ① 外层每条 `## 第 ` H2 都在全局卡里有对应条目（人能对上号）
//   ② 指针卡指向的每个文件**真实存在**（指了不存在的路径 = 又一次漂移）
//   ③ 全局卡**不承载** stage 流（四阶段/阶段必读/机器门/完成动作）—— 那些只该在 stage.md
//   ④ stage.md **确实承载** stage 流
//   ⑤ 没有残留的矛盾措辞
const fs = require('fs');
const path = require('path');

const G = 'C:/Users/admin/.config/opencode/AGENTS.md';
const B = 'D:/rdd/workspace/AGENTS.md';
const H = 'D:/rdd/harness/rdd-harness';

// ── 2026-10-19：全局卡缺失不再抛 ENOENT 栈 ────────────────────────────────
// 症状：换机后 `~/.config/opencode/AGENTS.md` 不存在，本脚本 readFileSync 直接崩，
//       P11 因此报 BLOCK —— 看起来像「规则打架」，其实是「文件没装」。
// 这属于「门禁自己的缺陷长得像债」那一族（bug-9/10 同类第 8 例）。
// 契约改成：缺全局卡 → 明确 SKIP + 给装法 + exit 3（环境错，不是债）。
const SKIP_EXIT = 3;
if (!fs.existsSync(G)) {
  console.log('全局卡   （不存在）');
  console.log('外层 B 版 ' + (fs.existsSync(B) ? fs.readFileSync(B, 'utf8').length + ' 字符' : '（也不存在）'));
  console.log('');
  console.log('  SKIP  全局指针卡缺失：' + G);
  console.log('        这不是「规则打架」，是这台机器还没装全局卡（换机/新用户常见）。');
  console.log('        装法：把基准版复制过去 ——');
  console.log('          copy "D:\\rdd\\docs\\rdd-docs\\rdd存放\\20260929-第二批-断线修复与硬门禁\\01-全局规则卡(改动后)\\AGENTS.md" "%USERPROFILE%\\.config\\opencode\\AGENTS.md"');
  console.log('        不装也不影响 DSH 侧干活 —— DSH 读的是外层 AGENTS.md + 各目录 _格式规范.md。');
  console.log('        装完重跑本脚本即可转 PASS。');
  process.exit(SKIP_EXIT);
}

const g = fs.readFileSync(G, 'utf8');
const b = fs.readFileSync(B, 'utf8');
const stage = fs.readFileSync(path.join(H, 'stage.md'), 'utf8');

const fail = [];
const ok = [];

console.log('全局卡   ' + g.length + ' 字符, ' + g.split(/\r?\n/).length + ' 行');
console.log('外层 B 版 ' + b.length + ' 字符, ' + b.split(/\r?\n/).length + ' 行');
console.log('stage.md ' + stage.length + ' 字符, ' + stage.split(/\r?\n/).length + ' 行');
console.log('');

// ① 外层每条 H2 都要在全局卡里有条目（按「第 N 条」这条 token 比，不比整行 ——
//    指针卡的小节标题会带自己的副标题，比整行会把真通过判成 MISS）
const bH2 = b.split(/\r?\n/).filter((l) => /^## 第 /.test(l));
const miss = bH2.filter((h) => {
  const no = (/^## 第 ([^\s]+) 条/.exec(h) || [])[1];
  return !new RegExp('^## 第 ' + no + ' 条', 'm').test(g);
});
if (miss.length === 0) ok.push('外层 ' + bH2.length + ' 条 H2 在全局卡都有对应条目');
else { fail.push('外层有 ' + miss.length + ' 条 H2 在全局卡里找不到：' + miss.join(' / ')); }

// ② 指针卡指向的文件必须存在
const POINTERS = [
  'D:/rdd/harness/rdd-harness/stage.md',
  'D:/rdd/docs/rdd-docs/知识库/进游戏验证/001-进游戏核心工具.md',
  'D:/rdd/docs/rdd-docs/知识库/退游戏/001-退游戏检查单.md',
  'D:/rdd/harness/rdd-harness/registry.json',
  'D:/rdd/harness/rdd-harness/standards.md',
  'D:/rdd/harness/rdd-harness/bin/harness-gate.js',
  'D:/rdd/workspace/AGENTS.md',
];
const noPoint = POINTERS.filter((p) => !fs.existsSync(p));
const notNamed = POINTERS.filter((p) => {
  const tail = p.split('/').pop();
  return p.indexOf('AGENTS.md') === -1 && !g.includes(tail);
});
if (noPoint.length === 0) ok.push('指针卡指向的 ' + POINTERS.length + ' 个文件全部存在');
else fail.push('指针卡指向的这些文件不存在：' + noPoint.join(' / '));
if (notNamed.length === 0) ok.push('指针卡正文把每个指针都写出来了（不是只给路径）');
else fail.push('指针卡没在正文点名：' + notNamed.map((p) => p.split('/').pop()).join(' / '));

// ③ 全局卡不得承载 stage 流。
//    只查**内容级标记**（真写了 stage 流才会出现的命令行/小节名），
//    不能查「机器门 / 阶段必读」这种词 —— 指针卡在「stage 流包含什么」那句话里
//    点到它们是应该的，误判会把这个检查变成永红的假警报。
const STAGE_FLOW = [
  'loop-gate.js', 'flow-gate.js', 'stager close --status', 'stager next',
  '## 第 1 条 · 四阶段', 'arch` 最终架构文档', 'stages.json` 的 `read[]`',
];
const leak = STAGE_FLOW.filter((k) => g.includes(k));
if (leak.length === 0) ok.push('全局卡没有承载 stage 流（' + STAGE_FLOW.length + ' 个关键词都不出现）');
else fail.push('全局卡混进了 stage 流内容：' + leak.join(' / '));

// ④ stage.md 必须确实承载 stage 流
const NEED_IN_STAGE = ['四阶段流水线', '阶段必读', '完成动作', 'loop-gate.js', 'flow-gate.js', 'stager.js', 'GLM 源码审'];
const absent = NEED_IN_STAGE.filter((k) => !stage.includes(k));
if (absent.length === 0) ok.push('stage.md 确实承载 stage 流（' + NEED_IN_STAGE.length + ' 个关键项都在）');
else fail.push('stage.md 缺这些 stage 流关键项：' + absent.join(' / '));

// ⑤ 全局专属块在位
const gOnly = ['provider 真源', '记忆库', 'GLOBAL-ONLY:END', '第 6 条'];
const missG = gOnly.filter((k) => !g.includes(k));
if (missG.length === 0) ok.push('全局专属块（provider / 记忆库 / 技能）在位');
else fail.push('全局专属块缺：' + missG.join(' / '));

// ⑥ 矛盾措辞
const bad = ['顺序不可颠倒', '从便宜到贵', '看不出才升', '≤10 分钟/次', 'Qwen 不用', '只回 235 字，不可用', '第一动作：开 stage'];
const badHit = bad.filter((k) => g.includes(k));
if (badHit.length === 0) ok.push('矛盾措辞 7 项全部清干净');
else fail.push('残留矛盾措辞：' + badHit.join(' / '));

ok.forEach((x) => console.log('  PASS  ' + x));
fail.forEach((x) => console.log('  FAIL  ' + x));
console.log('');
console.log(fail.length === 0
  ? '★ 指针卡与三份文件一致：' + ok.length + ' 项全过'
  : '✘ ' + fail.length + ' 项缺口（' + ok.length + ' 项过）');
process.exitCode = fail.length === 0 ? 0 : 1;
