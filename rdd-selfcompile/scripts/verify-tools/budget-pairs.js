#!/usr/bin/env node
'use strict';
/*
 * budget-pairs.js —— 预算「估算 vs 实际」配对统计（G4c 前置项 S100 的测量工具）
 *
 * 为什么需要：G4a/G4b 的预留估算偏高约 3 倍（est=61487 / actual=20154）。
 * 影子期无害（记账用实际值），但**开闸后有害**：配额只有约 1/3 可用，
 * 会产生大量「本不该拒」的拒绝。开闸前置条件 S100 要求：样本 ≥30 对，且校准后
 * est/actual 的 P90 ≤ 1.3。这个工具就是那只尺。
 *
 * 它怎么配对：`budget_reserve{status=granted, requestId, estimatedTokens}`
 *  ↔ `budget_settle{requestId, status, actualTokens}`。只认 `status=charged` 的配对
 *  （`reconciled` 说明预留跨了策略版本或过期，那一对不代表估算准度）。
 *
 * 查哪些文件：默认把 monitor 目录下所有 `context*.jsonl` 都扫一遍 ——
 * 归档文件（context-<stamp>.jsonl）里有更早的样本，只扫主文件会假阴性（H3 的教训）。
 *
 * 用法：
 *   node budget-pairs.js                       # 全部历史
 *   node budget-pairs.js --since 2026-10-21T00:00:00Z
 *   node budget-pairs.js --json                # 机读
 *   node budget-pairs.js --monitor <目录>
 *
 * 退出码：0 = 有样本（不管够不够 30）；2 = 一对样本都没有；3 = 用法/环境错
 */

const fs = require('fs');
const path = require('path');

const DEFAULT_MONITOR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';
const TARGET_P90 = 1.3;

function argOf(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
}

function listContextFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((f) => /^context.*\.jsonl$/.test(f))
    .map((f) => path.join(dir, f));
}

function readEvents(files, since) {
  const reserves = new Map();
  const settles = [];
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    for (const line of text.split('\n')) {
      if (!line || (line.indexOf('budget_reserve') < 0 && line.indexOf('budget_settle') < 0)) continue;
      let e;
      try { e = JSON.parse(line); } catch { continue; }
      if (since && e.timestamp < since) continue;
      const d = e.data || {};
      if (e.type === 'budget_reserve') {
        reserves.set(d.requestId, { est: d.estimatedTokens, status: d.status, role: d.role, ts: e.timestamp });
      } else if (e.type === 'budget_settle') {
        settles.push({ requestId: d.requestId, status: d.status, actual: d.actualTokens, est: d.estimatedTokens, role: d.role, ts: e.timestamp });
      }
    }
  }
  return { reserves, settles };
}

function pct(sorted, p) {
  if (!sorted.length) return null;
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function main(argv) {
  const monitor = argOf(argv, '--monitor') || DEFAULT_MONITOR;
  const since = argOf(argv, '--since');
  const files = listContextFiles(monitor);
  if (!files.length) {
    console.error(`没找到 context*.jsonl：${monitor}`);
    return 3;
  }

  const { reserves, settles } = readEvents(files, since);

  const pairs = [];
  let rejected = 0;
  let granted = 0;
  for (const r of reserves.values()) {
    if (r.status === 'granted') granted++;
    else rejected++;
  }
  const settleStatus = new Map();
  for (const s of settles) {
    settleStatus.set(s.status, (settleStatus.get(s.status) || 0) + 1);
    if (s.status !== 'charged') continue;             // 只认干净的扣账配对
    const r = reserves.get(s.requestId);
    const est = s.est != null ? s.est : (r ? r.est : null);
    const actual = s.actual;
    if (est == null || actual == null || actual <= 0) continue;
    pairs.push({ requestId: s.requestId, est, actual, ratio: est / actual, role: s.role, ts: s.ts });
  }

  const ratios = pairs.map((p) => p.ratio).sort((a, b) => a - b);
  const out = {
    files: files.length,
    since: since || '(all)',
    granted,
    rejected,
    settleStatuses: Object.fromEntries(settleStatus),
    pairs: pairs.length,
    ratio: {
      median: pct(ratios, 50),
      p90: pct(ratios, 90),
      p95: pct(ratios, 95),
      max: ratios.length ? ratios[ratios.length - 1] : null,
      min: ratios.length ? ratios[0] : null,
    },
    // 想把 P90 压到 TARGET_P90，budget-policy.json 的 estimateMultiplier 该取多少
    suggestedFactorMultiplier: ratios.length ? Number(((TARGET_P90 / pct(ratios, 90)) * 1).toFixed(3)) : null,
    suggestedEstimateMultiplier: ratios.length ? Number((TARGET_P90 / pct(ratios, 90)).toFixed(3)) : null,
    sampleOk: pairs.length >= 30,
    p90Ok: ratios.length ? pct(ratios, 90) <= TARGET_P90 : false,
  };

  if (argv.includes('--json')) {
    console.log(JSON.stringify(out, null, 2));
  } else {
    console.log(`样本文件 ${out.files} 个（since ${out.since}）`);
    console.log(`预留：granted=${granted}  rejected=${rejected}   扣账状态：${JSON.stringify(out.settleStatuses)}`);
    console.log(`可用配对（charged 且 actual>0）：${out.pairs} 对${out.sampleOk ? '' : '  ← S100 要 ≥30 对'}`);
    if (out.pairs) {
      console.log(`est/actual 比值：min=${out.ratio.min.toFixed(2)}  P50=${out.ratio.median.toFixed(2)}` +
        `  P90=${out.ratio.p90.toFixed(2)}  P95=${out.ratio.p95.toFixed(2)}  max=${out.ratio.max.toFixed(2)}`);
      // 2026-10-21 改判：校准旋钮是 budget-policy.json 的 estimateMultiplier（热重载），
      // 不是 CompactSplit.LIMIT_SAFETY_FACTOR（那把尺同时管 replay 窗口与压缩闸，不参与预算判额）。
      console.log(`要把 P90 压到 ${TARGET_P90}：把 budget-policy.json 的 "estimateMultiplier" 设为 ` +
        `${out.suggestedEstimateMultiplier}（当前未配置 = 1.0）`);
      console.log(`（历史口径备查：CompactSplit.LIMIT_SAFETY_FACTOR=1.5 不参与预算判额，别改它来调预算）`);
      console.log(`S100：样本 ${out.sampleOk ? 'OK' : '不足'} / P90 ${out.p90Ok ? 'OK' : '超标'}`);
    }
  }
  return pairs.length ? 0 : 2;
}

if (require.main === module) {
  process.exit(main(process.argv.slice(2)));
}

module.exports = { readEvents, listContextFiles };
