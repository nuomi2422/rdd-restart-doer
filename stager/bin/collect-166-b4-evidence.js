#!/usr/bin/env node
/**
 * collect-166-b4-evidence.js -- 从原始 monitor 日志生成 B4（可回收死亡恢复）证据。
 *
 * 为什么需要它（收益）：
 *   B4 判据要求四段齐全：冻结 → 派恢复 → **回收成功** → 同版本恢复主线。
 *   手写这份 JSON 极易把"死过一次"当成"恢复成功"。本脚本只做搬运 + 断言：
 *   找不到 terminalReason === 'drops_recovered' 就 **REFUSE**（exit 2），不写文件。
 *
 * 用法：node collect-166-b4-evidence.js [--write]
 */
'use strict';
const fs = require('fs');
const path = require('path');

const MONITOR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';
const OUT = 'D:\\rdd\\harness\\rdd-harness\\runs\\166-B4-recoverable-death\\evidence\\recovery.json';
const write = process.argv.includes('--write');

function readAll() {
  const out = [];
  for (const f of fs.readdirSync(MONITOR).filter((x) => /^rdd.*\.jsonl$/.test(x))) {
    for (const line of fs.readFileSync(path.join(MONITOR, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch (e) { /* 坏行跳过 */ }
    }
  }
  out.sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));
  return out;
}

function sourceMeta() {
  const files = fs.readdirSync(MONITOR).filter((x) => /^rdd.*\.jsonl$/.test(x)).sort();
  return files.map((f) => {
    const p = path.join(MONITOR, f);
    const st = fs.statSync(p);
    const lines = fs.readFileSync(p, 'utf8').split('\n').filter((l) => l.trim()).length;
    return { file: f, lines, mtime: st.mtime.toISOString() };
  });
}

const events = readAll();
const settledAll = events.filter((e) => e.type === 'death_recovery_settled');
const recovered = settledAll.filter((e) => e.data && e.data.terminalReason === 'drops_recovered');

if (!recovered.length) {
  const last = settledAll[settledAll.length - 1];
  console.error('REFUSE: 没有任何 drops_recovered 结算 —— 没有一次真回收，B4 不能写 PASS');
  if (last) console.error('   最近一次结算是 seq=' + last.data.deathSeq + ' terminal=' + JSON.stringify(last.data.terminalReason));
  process.exit(2);
}

const pick = recovered[recovered.length - 1];
const seq = String(pick.data.deathSeq);
const createdAt = events.filter((e) => e.type === 'side_task_created' && String(e.data.deathSeq) === seq).slice(-1)[0];
const mainlinePrimaryId = createdAt && createdAt.data ? String(createdAt.data.mainlinePrimaryId || '') : '';

const windowEvents = events.filter((e) => {
  const t = e.timestamp || '';
  if (t < '2000') return false;
  const d = e.data || {};
  return String(d.deathSeq) === seq || /death_recovery|repair_task|side_task/.test(e.type);
});
const sinceSettle = events.filter((e) => e.type === 'taskchain_snapshot' && e.timestamp > pick.timestamp);
const backToMain = sinceSettle.find((e) => {
  const tc = e.data && e.data.taskChain;
  return tc && tc.primaryStatus === 'ACTIVE' && (!mainlinePrimaryId || tc.currentPrimaryId === mainlinePrimaryId);
});

const out = {
  batch: 'B4',
  status: 'PASS',
  generatedAt: new Date().toISOString(),
  generatedBy: 'collect-166-b4-evidence.js（只搬运原始事件）',
  source: sourceMeta(),
  deathSeq: Number(seq),
  // 2026-10-31：原来 slice(0,40) 且不排序 —— 112 条 repair_task_progress 把
  // companion_assets_invalidated / death_recovery_settled 挤出窗口（seq=33 明明真回收，
  // 证据里却没有那两条，gate 判 exit=1）。改为**关键事件优先**，进度类只用来填剩余额度。
  events: (() => {
    const KEY = /companion_assets_invalidated|side_task_created|side_task_activated|repair_task_dispatched|death_recovery_decision|death_recovery_settled|side_task_completed|side_task_skipped/;
    const PROGRESS = /repair_task_progress/;
    const sorted = windowEvents
      .filter((e) => KEY.test(e.type) || PROGRESS.test(e.type))
      .sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));
    const key = sorted.filter((e) => KEY.test(e.type));
    const prog = sorted.filter((e) => PROGRESS.test(e.type));
    return key.concat(prog.slice(0, Math.max(0, 120 - key.length)))
      .sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)))
      .map((e) => ({ type: e.type, at: e.timestamp, data: e.data }));
  })(),
  resume: {
    backToSamePrimary: Boolean(backToMain),
    mainlinePrimaryId,
    at: backToMain ? backToMain.timestamp : null,
    note: backToMain ? '主线已回到同一 primary 且 ACTIVE' : '未观测到主线回到同一 primary（B4 不能判过）'
  }
};

if (!out.resume.backToSamePrimary) {
  console.error('REFUSE: 有 drops_recovered 但没观测到主线回到同一 primary —— 不满足 S4 的「同版本恢复」');
  process.exit(2);
}

if (!write) {
  console.log(JSON.stringify({ dryRun: true, deathSeq: seq, events: out.events.length, resume: out.resume }, null, 2));
  process.exit(0);
}
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out, null, 2), 'utf8');
console.log('written ' + OUT + ' (deathSeq=' + seq + ', events=' + out.events.length + ')');
