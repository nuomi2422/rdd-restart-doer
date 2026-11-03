#!/usr/bin/env node
/**
 * 当日/当窗口日报（长跑观察用）。只读，不出结论，只把事实摆齐：
 *   工具调用数 / 死亡与死因 / protection_escalated / 风险门开拦 /
 *   基地阶段分布 / reserve_next 出现 / 建议采用率（复用 audit-advice 口径）/ 经验库状态。
 *
 * 追加到 stager/runs/daily/series.jsonl，便于跨轮对比。
 * 用法：node audit-daily.js [--since ISO] [--hours N]
 */
const fs = require('node:fs');
const path = require('node:path');

const MONITOR = 'D:/rdd/mc/The Best of Twilight Forest/config/numen/monitor';
const NUMEN = 'D:/rdd/mc/The Best of Twilight Forest/config/numen';
const OUT_DIR = 'D:/rdd/workspace/stager/runs/daily';
const COMPANION = 'a43d753e-790d-472b-8d5b-dc18ac0afbc0';

const args = process.argv.slice(2);
const hIdx = args.indexOf('--hours');
const hours = hIdx >= 0 ? Number(args[hIdx + 1]) : 6;
const sIdx = args.indexOf('--since');
const since = sIdx >= 0 ? args[sIdx + 1] : new Date(Date.now() - hours * 3600_000).toISOString();
const sinceMs = Date.parse(since);

function lines(prefix) {
  const out = [];
  for (const f of fs.readdirSync(MONITOR).filter(x => x.startsWith(prefix) && x.endsWith('.jsonl'))) {
    for (const l of fs.readFileSync(path.join(MONITOR, f), 'utf8').split('\n')) {
      if (!l.trim()) continue;
      try { out.push(JSON.parse(l)); } catch {}
    }
  }
  return out;
}

const rdd = lines('rdd').filter(j => Date.parse(j.timestamp || '') >= sinceMs);
const tools = lines('tools').filter(j => Date.parse(j.timestamp || '') >= sinceMs);
const instr = lines('instrumentation').filter(j => Date.parse(j.timestamp || '') >= sinceMs);

const kinds = {};
for (const j of rdd) {
  const t = String(j.type || '');
  if (/^(protection_escalated|risk_gate_opened|risk_gate_blocked|death_recovery_settled|side_task_cancelled|farm_production_observed|home_plan_ready|repeat_death_nearby)$/.test(t)) {
    kinds[t] = (kinds[t] || 0) + 1;
  }
}

const deaths = instr.filter(j => j.type === 'death').map(j => ({
  seq: j.data && j.data.deathSeq,
  kind: (j.data && j.data.deathKind) || 'unknown',
  at: j.timestamp,
}));
const deathKinds = {};
for (const d of deaths) deathKinds[d.kind] = (deathKinds[d.kind] || 0) + 1;

const stages = {};
let reserveNext = 0, ctxCount = 0;
for (const j of rdd) {
  if (j.type !== 'numen_context') continue;
  const c = String((j.data && j.data.context) || '');
  if (!c.includes('<home>')) continue;
  ctxCount++;
  const m = c.match(/home_stage=(\w+)/);
  if (m) stages[m[1]] = (stages[m[1]] || 0) + 1;
  if (c.includes('reserve_next=')) reserveNext++;
}

let lib = null;
try {
  const f = path.join(NUMEN, 'experience-' + COMPANION + '.jsonl');
  const st = {};
  for (const l of fs.readFileSync(f, 'utf8').split('\n')) {
    if (!l.trim()) continue;
    try { const j = JSON.parse(l); const s = j.status || (j.data && j.data.status) || '?'; st[s] = (st[s] || 0) + 1; } catch {}
  }
  lib = st;
} catch (e) { lib = null; }

const row = {
  at: new Date().toISOString(),
  since,
  toolCalls: tools.length,
  events: kinds,
  deaths: deaths.length,
  deathKinds,
  contexts: ctxCount,
  homeStages: stages,
  reserveNextShown: reserveNext,
  experienceLib: lib,
};
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.appendFileSync(path.join(OUT_DIR, 'series.jsonl'), JSON.stringify(row) + '\n');
console.log(JSON.stringify(row, null, 1));