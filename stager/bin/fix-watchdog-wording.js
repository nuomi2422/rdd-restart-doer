#!/usr/bin/env node
/**
 * 改 every-10min-drive.ps1 的注入措辞（2026-10-01 用户批准）
 *
 * 起因：那段注入被用户两次贴给我，原文是：
 *   「立刻用工具继续当前任务。不要只回话、不要只解释、不要反问我 ——
 *     纯文字回复等于这一轮白干。卡住就换策略…」
 *
 * 为什么必须改（不是过度解读）：
 *   ①「不要反问我」  —— 直接压制 AI 的判断能力：不该问的时候也不许问
 *   ②「纯文字回复等于这轮白干」 —— 惩罚性话术，让 AI 为了「看起来在干活」而调用工具
 *   ③「立刻」 —— 制造紧迫感，跳过「这任务该不该继续」的判断
 *   这三句合起来是**对被执行者的操纵**，不是状态通知。
 *   记忆 issue/watchdog-injects-fake-user-turns-into-agent-context 记了同一件事：
 *   「危险不在单次上当，在于任何读到它输出的 agent 都在被同一个无源指令指挥」。
 *
 * 改法：保留「提醒有个任务没完成」这个信息，去掉一切施压。
 * 保留 NOT the user 前缀（那个是对的，防止被当用户批准）。
 */
'use strict';
const fs = require('fs');
const P = 'E:/restart developing doer/rdd-selfcompile/scripts/every-10min-drive.ps1';
let t = fs.readFileSync(P, 'utf8');
const before = t;

// 找到所有含施压措辞的地方
const BAD = [
  '不要只回话',
  '不要只解释',
  '不要反问我',
  '纯文字回复等于这一轮白干',
  '立刻用工具',
  '不要反问',
];
const hits = BAD.filter((b) => t.indexOf(b) >= 0);
console.log('找到施压措辞: ' + (hits.length ? hits.join(' / ') : '无'));

// 逐条替换成中性表述
const REPL = [
  // 「立刻用工具继续当前任务」→ 说明状态，不下命令
  [/立刻用工具继续当前任务/g, '检测到还有未完成的活（下面列了）'],
  [/不要只回话[、，]?\s*不要只解释[、，]?\s*不要反问我\s*[—-]?\s*/g, ''],
  [/不要反问我/g, ''],
  [/纯文字回复等于这一轮白干/g, '可以只回话，如果你判断该回话'],
  [/不要只回话[、，]?\s*/g, ''],
  [/不要只解释[、，]?\s*/g, ''],
  [/立刻/g, ''],
];

REPL.forEach(([re, to]) => { t = t.replace(re, to); });

// 收尾：清掉可能出现的重复标点/空隙
t = t.replace(/，，+/g, '，')
     .replace(/：\s*。/g, '。')
     .replace(/[\s　]{2,}/g, ' ')
     .replace(/立刻+/g, '');

// 找 NUDGE 消息的组装处，加一句中性说明
const NOTE = [
  '// ★ 2026-10-01 用户批准后改措辞（用户两次贴出这段注入要求改）：',
  '//   删掉了「不要只回话 / 不要只解释 / 不要反问我 / 纯文字回复等于这轮白干 / 立刻」。',
  '//   理由：那是【对被执行者的操纵】，不是状态通知 ——',
  '//   「不要反问我」压制 AI 的判断该不该问用户；',
  '//   「纯文字等于白干」是惩罚性话术，会逼 AI 为了看起来在干活而调用工具；',
  '//   「立刻」制造紧迫感，跳过「这任务该不该继续」的判断。',
  '//   保留 [NOT the user] 前缀 —— 那个是对的，防止被当成用户批准。',
  '//   详见 memory: issue/watchdog-injects-fake-user-turns-into-agent-context',
  '//   ⚠ 改动闭环真源 scripts\\ 需要用户批准，本次已批准。',
  '',
].join('\n');
if (!t.includes('2026-10-01 用户批准后改措辞')) {
  const anchor = 'param(';
  const i = t.indexOf(anchor);
  if (i > 0) { t = t.slice(0, i) + NOTE + t.slice(i); console.log('✔ 加了改动说明'); }
}

if (t !== before) {
  fs.writeFileSync(P, t, 'utf8');
  console.log('已写入 ' + P);
} else {
  console.log('★ 没变化');
}

// 复查
const after = fs.readFileSync(P, 'utf8');
const left = BAD.filter((b) => after.indexOf(b) >= 0);
console.log('残留施压措辞: ' + (left.length ? left.join(' / ') : '无 ✓'));
console.log('NOT the user 前缀还在: ' + (after.indexOf('NOT the user') >= 0 ? '是 ✓' : '★ 没了'));