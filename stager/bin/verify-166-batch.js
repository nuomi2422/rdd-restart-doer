#!/usr/bin/env node
/**
 * verify-166-batch.js -- enforce the current 166 batch before stager advances.
 *
 * WHY THIS EXISTS (2026-10-31):
 *   goal.js is a global lock and can contain unrelated items. The 166施工单 needs
 *   a batch-local gate so an unrelated failed item cannot block it, and no later
 *   Bn can be entered before its own B(n-1) evidence and current re-run pass.
 *
 * USAGE:
 *   node verify-166-batch.js B0
 *
 * NOTES:
 *   * Evidence is accepted only when the goal item has a successful prove record.
 *   * The item's command is re-run here; stale prove output is insufficient.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const root = path.resolve(__dirname, '..');
const runtime = process.env.STAGER_RUNTIME || path.join(root, '.stager');
const batchFile = path.join(runtime, '166-batch.json');
const requested = process.argv.slice(2).find((x) => /^B[0-8]$/.test(x)) || '';
const batchState = fs.existsSync(batchFile)
  ? JSON.parse(fs.readFileSync(batchFile, 'utf8').replace(/^\uFEFF/, ''))
  : { current: 'B0' };
const batch = requested || batchState.current;
const goalFile = path.join(runtime, 'goal.json');
const goal = JSON.parse(fs.readFileSync(goalFile, 'utf8').replace(/^\uFEFF/, ''));
if (!/^B[0-8]$/.test(batch)) {
  console.error('166 batch must be B0..B8');
  process.exit(2);
}
if (batch !== batchState.current && !requested) {
  console.error('166 batch cursor is invalid');
  process.exit(2);
}
if (goal.title !== '166 死亡后重要度重规划与稳态主线闭环') {
  console.error('active goal is not 166');
  process.exit(2);
}
const index = Number(batch.slice(1));
const item = (goal.items || []).find((x) => x.id === batch);
if (!item) {
  console.error(batch + ' is not registered in goal lock');
  process.exit(1);
}
const evidence = (item.evidence || []).some((x) => x && x.ok);
if (!evidence) {
  console.error(batch + ' has no successful prove evidence');
  process.exit(1);
}
if (!item.cmd) {
  console.error(batch + ' has no machine command');
  process.exit(1);
}
const r = cp.spawnSync(item.cmd, { shell: true, encoding: 'utf8', timeout: 120000, windowsHide: true });
const out = ((r.stdout || '') + (r.stderr || '')).trim();
const code = r.status == null ? -1 : r.status;
const expect = item.expect ? new RegExp(item.expect) : null;
if (code !== 0 || (expect && !expect.test(out))) {
  console.error(batch + ' current re-run failed: exit=' + code + (out ? ' output=' + out.slice(0, 500).replace(/\s+/g, ' ') : ''));
  process.exit(1);
}
if (index > 0) {
  const prev = (goal.items || []).find((x) => x.id === 'B' + (index - 1));
  const prevEvidence = prev && (prev.evidence || []).some((x) => x && x.ok);
  if (!prevEvidence) {
    console.error('previous batch B' + (index - 1) + ' has no successful evidence');
    process.exit(1);
  }
}
if (process.argv.includes('--advance')) {
  const n = Number(batch.slice(1));
  batchState.current = n >= 8 ? 'DONE' : 'B' + (n + 1);
  batchState.updatedAt = new Date().toISOString();
  fs.mkdirSync(path.dirname(batchFile), { recursive: true });
  fs.writeFileSync(batchFile + '.tmp', JSON.stringify(batchState, null, 2), 'utf8');
  fs.renameSync(batchFile + '.tmp', batchFile);
  console.log(batch + ' batch gate PASS; cursor=' + batchState.current);
} else {
  console.log(batch + ' batch gate PASS');
}
process.exit(0);
