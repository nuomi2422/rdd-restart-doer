#!/usr/bin/env node
/**
 * 建议采用率观测（167 §9.11）——**只观测，不做因果结论**。
 *
 * 为什么要有这个脚本：167 的新上下文块（<home>/<farm>/<death_spots>）都在给建议，
 * 「建议有没有被采纳」只能靠长期序列看，不能靠一次快照拍板。
 * 所以它做三件事：算当期采用率、算全局基线、把结果**追加**到台账形成时间序列。
 *
 * 口径（刻意窄）：动作集只算 mine|gather|farm_nearby；窗口 60s；
 * 基线用每 30s 滑一个 60s 窗。为什么窄：interact_at/scan_blocks 频率太高，
 * 放宽后基线自己就飙到 45%，任何结论都会被噪声淹没。
 *
 * 用法：node audit-advice.js [--since ISO] [--quiet]
 */
const fs = require('node:fs');
const path = require('node:path');

const MONITOR = 'D:/rdd/mc/The Best of Twilight Forest/config/numen/monitor';
const LEDGER_DIR = 'D:/rdd/workspace/stager/runs/advice-adoption';
const LEDGER = path.join(LEDGER_DIR, 'series.jsonl');

const args = process.argv.slice(2);
const sinceIdx = args.indexOf('--since');
const since = sinceIdx >= 0 ? args[sinceIdx + 1] : new Date(Date.now() - 3 * 3600_000).toISOString();
const quiet = args.includes('--quiet');

function readJsonl(prefix) {
  const out = [];
  for (const f of fs.readdirSync(MONITOR).filter(x => x.startsWith(prefix) && x.endsWith('.jsonl'))) {
    for (const line of fs.readFileSync(path.join(MONITOR, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch {}
    }
  }
  return out;
}

const NARROW = /^(mine|gather|farm_nearby)$/;
const sinceMs = Date.parse(since);

const calls = [];
for (const j of readJsonl('tools')) {
  const t = Date.parse(j.timestamp || '');
  if (!t || t < sinceMs) continue;
  const name = (j.data && (j.data.tool || j.data.name)) || j.tool || '';
  if (name) calls.push({ t, name });
}
calls.sort((a, b) => a.t - b.t);

const advised = [];
for (const j of readJsonl('rdd')) {
  if (j.type !== 'numen_context') continue;
  const t = Date.parse(j.timestamp || '');
  if (!t || t < sinceMs) continue;
  const c = String((j.data && j.data.context) || '');
  if (/reserve_next=gather /.test(c)) advised.push(t);
}

const hit = (t, winMs = 60_000) => calls.some(k => k.t >= t && k.t <= t + winMs && NARROW.test(k.name));
const adopted = advised.filter(t => hit(t)).length;

let windows = 0, baseHit = 0;
const t0 = sinceMs, t1 = calls.length ? calls[calls.length - 1].t : sinceMs;
for (let t = t0; t + 60_000 <= t1; t += 30_000) { windows++; if (hit(t)) baseHit++; }

const row = {
  at: new Date().toISOString(),
  since,
  advisedContexts: advised.length,
  adopted,
  adoptedRate: advised.length ? +(adopted / advised.length).toFixed(3) : null,
  baselineWindows: windows,
  baselineRate: windows ? +(baseHit / windows).toFixed(3) : null,
  calls: calls.length,
};
fs.mkdirSync(LEDGER_DIR, { recursive: true });
fs.appendFileSync(LEDGER, JSON.stringify(row) + '\n');

if (!quiet) {
  console.log(JSON.stringify(row, null, 0));
  console.log('提示：这是观察指标，不是因果证据（无随机对照，建议多出现在活动期）。');
}