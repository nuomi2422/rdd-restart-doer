#!/usr/bin/env node
/**
 * collect-166-b3-evidence.js -- 从原始 monitor 日志生成 B3 证据文件。
 *
 * 为什么需要它（收益）：
 *   B3 的机读判据（166-goal-check.js）要求证据文件同时含
 *   risk_gate_blocked（带 missing）+ risk_gate_opened + interventions。
 *   手写这种 JSON 极易造假或漏项；脚本只做"搬运 + 断言"：
 *   —— 找不到 opened 事件就**拒绝写文件**（exit 2），从源头杜绝"手搓通过"。
 *
 * 用法：
 *   node collect-166-b3-evidence.js [--write]
 * 不加 --write 只打印将要写什么（dry-run）。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const MONITOR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';
const OUT = 'D:\\rdd\\harness\\rdd-harness\\runs\\166-B3-risk-gate\\evidence\\risk-gate.json';
const write = process.argv.includes('--write');
// --out <path>：不改覆盖历史存档时，另存一份（例如带 source 元数据的新版）
const outArgIdx = process.argv.indexOf('--out');
const outPath = outArgIdx > 0 && process.argv[outArgIdx + 1] ? process.argv[outArgIdx + 1] : null;

function readJsonl(dir) {
  const out = [];
  for (const f of fs.readdirSync(dir).filter((x) => /^rdd.*\.jsonl$/.test(x))) {
    for (const line of fs.readFileSync(path.join(dir, f), 'utf8').split('\n')) {
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

const events = readJsonl(MONITOR);
const pick = (type) => events.filter((e) => e && e.type === type);
const blocked = pick('risk_gate_blocked');
const opened = pick('risk_gate_opened');
const adminUsed = pick('admin_command_used');

if (!blocked.length) {
  console.error('REFUSE: 没有任何 risk_gate_blocked —— 没有阻止就没有 B3 的前半段');
  process.exit(2);
}
const blockedWithMissing = blocked.filter((e) => e.data && Array.isArray(e.data.missing) && e.data.missing.length > 0);
if (!blockedWithMissing.length) {
  console.error('REFUSE: 有 blocked 但都没带 missing 缺口明细，不算有效阻止');
  process.exit(2);
}
if (!opened.length) {
  console.error('REFUSE: 没有 risk_gate_opened —— 放行半段没发生，B3 不能写 PASS');
  process.exit(2);
}

const out = {
  batch: 'B3',
  status: 'PASS',
  generatedAt: new Date().toISOString(),
  generatedBy: 'collect-166-b3-evidence.js（只搬运原始事件，不构造结论）',
  objective: 'B3 风险门：缺资源阻止 + 补齐后放行',
  events: [
    ...blockedWithMissing.map((e) => ({ type: 'risk_gate_blocked', at: e.timestamp, data: e.data })),
    ...opened.map((e) => ({ type: 'risk_gate_opened', at: e.timestamp, data: e.data }))
  ],
  interventions: adminUsed.length
    ? [{ kind: 'admin_give', count: adminUsed.length, note: '回执自带 cheated=true；本文件不把它当自然获得证据' }]
    : [{ kind: 'natural', note: '无 admin 干预记录' }],
  notes: '由脚本从原始日志搬运，避免手写证据。',
  source: sourceMeta(),
};

if (!write) {
  console.log(JSON.stringify({ dryRun: true, blocked: blockedWithMissing.length, opened: opened.length, out }, null, 2).slice(0, 1200));
  process.exit(0);
}
const target = outPath || OUT;
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, JSON.stringify(out, null, 2), 'utf8');
console.log('written ' + target + ' (blocked=' + blockedWithMissing.length + ', opened=' + opened.length + ')');
