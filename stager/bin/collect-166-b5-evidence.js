#!/usr/bin/env node
/**
 * collect-166-b5-evidence.js -- 生成 B5（无备用关键损失 → 重规划）证据。
 *
 * 强制条件（缺一即 REFUSE，exit 2）：
 *   1) loss_impact_recomputed.importantLoss === true（或 lossConfirmed === true）
 *   2) 同事件 backupSufficient === false
 *   3) 之后出现新计划（goal_staged / primary_expanded）
 *   4) 之后出现硬门事件（risk_gate_blocked / risk_gate_opened）
 * 用法：node collect-166-b5-evidence.js [--write]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const MONITOR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';
const OUT = 'D:\\rdd\\harness\\rdd-harness\\runs\\166-B5-death-replan\\evidence\\death-replan.json';
const write = process.argv.includes('--write');

function readAll() {
  const out = [];
  for (const f of fs.readdirSync(MONITOR).filter((x) => /^rdd.*\.jsonl$/.test(x))) {
    for (const line of fs.readFileSync(path.join(MONITOR, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch (e) { /* skip */ }
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

const ev = readAll();
const impacts = ev.filter((e) => e.type === 'loss_impact_recomputed'
  && e.data && (e.data.importantLoss === true || e.data.lossConfirmed === true)
  && e.data.backupSufficient === false);
if (!impacts.length) {
  const any = ev.filter((e) => e.type === 'loss_impact_recomputed').slice(-1)[0];
  console.error('REFUSE: 没有 importantLoss=true 且 backupSufficient=false 的损失事件 —— B5 不能写 PASS');
  if (any) console.error('   最近一次损失判定: importantLoss=' + any.data.importantLoss + ' backupSufficient=' + any.data.backupSufficient);
  process.exit(2);
}
const hit = impacts[impacts.length - 1];
const after = ev.filter((e) => e.timestamp > hit.timestamp);
const plan = after.find((e) => e.type === 'goal_staged' || e.type === 'primary_expanded');
const gate = after.find((e) => /^risk_gate_/.test(e.type));
if (!plan) { console.error('REFUSE: 有重要损失，但之后没观测到新计划（goal_staged/primary_expanded）'); process.exit(2); }
if (!gate) { console.error('REFUSE: 有重要损失与新计划，但之后没观测到硬门事件（risk_gate_*）'); process.exit(2); }

const out = {
  batch: 'B5', status: 'PASS', generatedAt: new Date().toISOString(),
  generatedBy: 'collect-166-b5-evidence.js（只搬运原始事件）',
  source: sourceMeta(),
  deathSeq: Number(hit.data.deathSeq || -1),
  events: [hit, plan, gate].map((e) => ({ type: e.type, at: e.timestamp, data: e.data })),
  replan: { requested: true, at: plan.timestamp },
  newPlan: { stages: plan.data && plan.data.stages ? plan.data.stages : (plan.data && plan.data.subtasks) || 1 },
  gate: { type: gate.type, at: gate.timestamp }
};
if (!write) { console.log(JSON.stringify(out, null, 1).slice(0, 800)); process.exit(0); }
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out, null, 2), 'utf8');
console.log('written ' + OUT);
