#!/usr/bin/env node
/**
 * 开闸健康度：把 `G4c-开闸卡.md` §9 那套「盯四个信号 + 30 分钟判据」变成一条命令。
 *
 * <p>为什么需要它：开闸那 30 分钟要同时看拒绝率、block 比例、`est/actual`、主人豁免、
 * 以及「S104 复盘被拦后有没有把条目放回队列」。手数六个文件既慢又容易漏，
 * 而漏掉的后果是「以为健康，其实条目被吞了」。
 *
 * <p>它只读，不改任何东西；口径全部来自开闸卡（S100/S101/S104/S105/S107/S107b）。
 *
 * 用法：
 *   node check-budget-health.js [--minutes 60] [--since 2026-10-21T03:00:00Z]
 *                               [--monitor <dir>] [--json] [--selftest]
 *
 * 退出码：0 = 健康 / 1 = 有警告 / 2 = 用法或环境错
 */

'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_MONITOR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';

const opt = {
  monitor: DEFAULT_MONITOR,
  minutes: 60,
  since: null,
  json: false,
  selftest: false,
};

function usage(msg) {
  if (msg) console.error('[用法] ' + msg);
  console.error('用法：node check-budget-health.js [--minutes 60] [--since <ISO>] [--monitor <dir>] [--json] [--selftest]');
  process.exit(2);
}

for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === '--minutes') opt.minutes = Number(process.argv[++i]);
  else if (a === '--since') opt.since = process.argv[++i];
  else if (a === '--monitor') opt.monitor = process.argv[++i];
  else if (a === '--json') opt.json = true;
  else if (a === '--selftest') opt.selftest = true;
  else if (a === '--help' || a === '-h') usage();
  else usage('未知参数 ' + a);
}

function readEvents(file) {
  if (!fs.existsSync(file)) return [];
  const out = [];
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const j = JSON.parse(line);
      const ts = Date.parse(j.timestamp);
      if (!Number.isFinite(ts)) continue;
      out.push({ ts, type: j.type, data: j.data || {} });
    } catch {
      // 坏行跳过（监测文件是滚动追加的，最后一行可能半截）
    }
  }
  return out;
}

function pct(x, digits = 1) {
  return (x * 100).toFixed(digits) + '%';
}

function quantile(sorted, q) {
  if (!sorted.length) return NaN;
  const i = Math.min(sorted.length - 1, Math.max(0, Math.round((sorted.length - 1) * q)));
  return sorted[i];
}

/**
 * 核心：给一批事件算健康度。**纯函数**，自测直接喂合成数据。
 * @returns {{warn: Array<{code:string,detail:string}>, info: object}}
 */
function analyse(events, opts) {
  const warn = [];
  const since = opts.sinceMs;
  const window = events.filter((e) => e.ts >= since);

  const reserves = window.filter((e) => e.type === 'budget_reserve');
  const settles = window.filter((e) => e.type === 'budget_settle');
  const blocks = window.filter((e) => e.type === 'budget_block');
  const overrides = window.filter((e) => e.type === 'budget_owner_override');
  const retries = window.filter((e) => e.type === 'budget_retry');
  const usage = window.filter((e) => e.type === 'llm_usage' && e.data.status === 'ok');

  const granted = reserves.filter((e) => e.data.status === 'granted').length;
  const rejected = reserves.filter((e) => e.data.status === 'rejected').length;
  const charged = settles.filter((e) => e.data.status === 'charged').length;
  const reconciled = settles.filter((e) => e.data.status === 'reconciled').length;

  // S101：拒绝率（分母 = 所有预留尝试）
  const attempts = granted + rejected;
  const rejectRate = attempts ? rejected / attempts : 0;

  // §9 第 3 步：block / (reserve + block)
  const blockShare = (granted + blocks.length) ? blocks.length / (granted + blocks.length) : 0;

  // S100：est/actual（只有 charged 且 actual>0 才算一对）
  const pairs = [];
  for (const s of settles) {
    if (s.data.status !== 'charged') continue;
    const actual = Number(s.data.actualTokens);
    const est = Number(s.data.estimatedTokens);
    if (actual > 0 && est > 0) pairs.push(est / actual);
  }
  pairs.sort((a, b) => a - b);

  // S105：判定调用有没有出现（出现了就该没有同刻 block）
  const judging = usage.filter((e) => String(e.data.phase || '').startsWith('goal_judging'));

  // 主人豁免（S107）：有 override 说明有人被豁免过 —— 出现正常，太多要查
  const overrideShare = attempts ? overrides.length / attempts : 0;

  // S104：learning 角色的 block 之后必须跟 review_failed
  const learningBlocks = blocks.filter((e) => e.data.role === 'learning');
  let unmatchedLearningBlocks = 0;
  for (const b of learningBlocks) {
    const follower = window.find((e) =>
      e.ts >= b.ts && e.ts <= b.ts + 30_000 && e.type === 'review_failed');
    if (!follower) unmatchedLearningBlocks++;
  }

  if (attempts === 0) {
    warn.push({ code: 'NO_TRAFFIC', detail: '窗口内没有任何预算预留 —— 她本来就没在干活，别当成功' });
  }
  if (attempts > 0 && rejectRate > 0.10) {
    warn.push({ code: 'REJECT_RATE_HIGH',
      detail: `拒绝率 ${pct(rejectRate)} 超 10%（S101 要求 ≤5%）：额度太小，回开闸卡 §9 第 0 步重算` });
  }
  if (attempts > 0 && rejectRate > 0.05 && rejectRate <= 0.10) {
    warn.push({ code: 'REJECT_RATE_WARN', detail: `拒绝率 ${pct(rejectRate)} 略高（S101 要求 ≤5%）` });
  }
  if (attempts >= 20 && blocks.length === 0) {
    warn.push({ code: 'NEVER_BLOCKED',
      detail: `预留 ${attempts} 次却一次没拦 —— 额度可能大得等于没开闸（不是坏事，但要确认是有意的）` });
  }
  if (blockShare > 0.10) {
    warn.push({ code: 'BLOCK_SHARE_HIGH', detail: `block/(reserve+block) = ${pct(blockShare)} 超 10%：额度不对` });
  }
  if (pairs.length >= 10) {
    const p90 = quantile(pairs, 0.9);
    if (p90 > 1.3) {
      warn.push({ code: 'ESTIMATE_P90_HIGH', detail: `est/actual P90 = ${p90.toFixed(2)} 超 1.3（S100）：校准系数要调` });
    }
  }
  if (unmatchedLearningBlocks > 0) {
    warn.push({ code: 'LEARNER_BLOCK_UNPAIRED',
      detail: `${unmatchedLearningBlocks} 次 learning 拦截后 30 秒内没有 review_failed —— 队列条目可能被吞（S104）` });
  }
  if (overrideShare > 0.30 && overrides.length >= 5) {
    warn.push({ code: 'OVERRIDE_TOO_OFTEN',
      detail: `主人豁免占 ${pct(overrideShare)}（${overrides.length} 次）—— 有人在刷额度，看 override 事件的 source` });
  }
  // ⚠️ 不要为「没有 goal_judging」报警（2026-10-21 自测抓到）：
  // 当前配置下只要 RDD 装着，`EntityAgentLoop.setGoal` 就会把内建目标置空（`:825-829`），
  // 内建判定**永远不会**跑 —— S105 在这种配置下是 **N/A**，报警只会变成常驻噪音。
  // 它只作为读数展示（见下面 info），不参与判定。

  return {
    warn,
    info: {
      windowMinutes: opts.minutes,
      reserves: { granted, rejected, rejectRate },
      settles: { charged, reconciled },
      blocks: blocks.length,
      blockShare,
      ownerOverrides: overrides.length,
      retries: retries.length,
      estimatePairs: pairs.length,
      estimateP50: pairs.length ? +quantile(pairs, 0.5).toFixed(3) : null,
      estimateP90: pairs.length ? +quantile(pairs, 0.9).toFixed(3) : null,
      goalJudging: judging.length,
      learningBlocks: learningBlocks.length,
      unmatchedLearningBlocks,
    },
  };
}

// ────────────────────────────── 自测 ──────────────────────────────
function selftest() {
  const now = Date.now();
  const ev = (offsetMs, type, data) => ({ ts: now - offsetMs, type, data });
  const cases = [];

  // 1) 健康：有流量、零拒绝、少量拦截、比例正常
  cases.push({
    name: 'healthy',
    events: [
      ...Array.from({ length: 20 }, (_, i) => ev(60_000 + i * 1000, 'budget_reserve', { status: 'granted' })),
      ...Array.from({ length: 20 }, (_, i) => ev(59_000 + i * 1000, 'budget_settle',
        { status: 'charged', estimatedTokens: 20_000, actualTokens: 19_000 })),
      ev(30_000, 'budget_block', { role: 'execution' }),
    ],
    wantWarn: 0,
  });

  // 2) 拒绝率过高
  cases.push({
    name: 'reject-high',
    events: [
      ...Array.from({ length: 5 }, (_, i) => ev(60_000 + i * 1000, 'budget_reserve', { status: 'granted' })),
      ...Array.from({ length: 5 }, (_, i) => ev(50_000 + i * 1000, 'budget_reserve', { status: 'rejected' })),
    ],
    wantCodes: ['REJECT_RATE_HIGH'],
  });

  // 3) learning 拦截没有配对 review_failed
  cases.push({
    name: 'learner-unpaired',
    events: [
      ...Array.from({ length: 10 }, (_, i) => ev(60_000 + i * 1000, 'budget_reserve', { status: 'granted' })),
      ev(20_000, 'budget_block', { role: 'learning' }),
    ],
    wantCodes: ['LEARNER_BLOCK_UNPAIRED'],
  });

  // 4) 完全没有流量
  cases.push({ name: 'no-traffic', events: [], wantCodes: ['NO_TRAFFIC'] });

  // 5) 校准 P90 超线
  cases.push({
    name: 'estimate-bad',
    events: Array.from({ length: 12 }, (_, i) => ev(60_000 + i * 1000, 'budget_settle',
      { status: 'charged', estimatedTokens: 60_000, actualTokens: 20_000 })),
    wantCodes: ['ESTIMATE_P90_HIGH'],
  });

  let pass = 0, fail = 0;
  const opts = { sinceMs: now - 3600_000, minutes: 60 };
  for (const c of cases) {
    const r = analyse(c.events, opts);
    const codes = r.warn.map((w) => w.code);
    let ok;
    if (c.wantCodes) ok = c.wantCodes.every((x) => codes.includes(x));
    else ok = r.warn.length === c.wantWarn;
    console.log(`  ${ok ? '✔' : '✘'} ${c.name.padEnd(16)} 期望 ${JSON.stringify(c.wantCodes || c.wantWarn)} 实得 ${JSON.stringify(codes)}`);
    ok ? pass++ : fail++;
  }

  // 6) 端到端：真的读文件（用临时目录造一个 context.jsonl）
  const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'budget-health-'));
  const lines = [];
  for (let i = 0; i < 6; i++) {
    lines.push(JSON.stringify({ timestamp: new Date(now - 100_000 + i * 1000).toISOString(),
      type: 'budget_reserve', data: { status: 'granted' } }));
    lines.push(JSON.stringify({ timestamp: new Date(now - 99_000 + i * 1000).toISOString(),
      type: 'budget_settle', data: { status: 'charged', estimatedTokens: 20000, actualTokens: 19000 } }));
  }
  lines.push(JSON.stringify({ timestamp: new Date(now - 50_000).toISOString(),
    type: 'budget_block', data: { role: 'execution' } }));
  fs.writeFileSync(path.join(tmp, 'context.jsonl'), lines.join('\n') + '\n', 'utf8');
  const events = readEvents(path.join(tmp, 'context.jsonl'));
  const r = analyse(events, { sinceMs: now - 600_000, minutes: 10 });
  const ok = events.length === 13 && r.info.reserves.granted === 6 && r.info.blocks === 1;
  console.log(`  ${ok ? '✔' : '✘'} e2e-read       读 13 条 / granted 6 / block 1 实得 ${events.length}/${r.info.reserves.granted}/${r.info.blocks}`);
  ok ? pass++ : fail++;
  fs.rmSync(tmp, { recursive: true, force: true });

  console.log(`\n  selftest: ${pass} 过 / ${fail} 败`);
  process.exit(fail ? 1 : 0);
}

// ────────────────────────────── 主流程 ──────────────────────────────
if (opt.selftest) selftest();

if (!fs.existsSync(opt.monitor)) {
  console.error('[env] 监测目录不存在: ' + opt.monitor);
  process.exit(2);
}

const sinceMs = opt.since
  ? Date.parse(opt.since)
  : Date.now() - opt.minutes * 60_000;
if (!Number.isFinite(sinceMs)) usage('--since 解析失败: ' + opt.since);

const ctxEvents = readEvents(path.join(opt.monitor, 'context.jsonl'));
const learnerFile = path.join(opt.monitor, 'learner.jsonl');
// review_failed 在 learner.jsonl 里，但 analyse 只按 type 匹配，合并进来即可
const all = ctxEvents.concat(readEvents(learnerFile));

const { warn, info } = analyse(all, { sinceMs, minutes: opt.minutes });

if (opt.json) {
  console.log(JSON.stringify({ warn, info }, null, 2));
  process.exit(warn.length ? 1 : 0);
}

console.log('');
console.log('════ 开闸健康度（G4c-开闸卡 §9）════');
console.log(`窗口     : 最近 ${opt.minutes} 分钟（since ${new Date(sinceMs).toISOString()}）`);
console.log(`预留     : granted=${info.reserves.granted}  rejected=${info.reserves.rejected}  拒绝率=${pct(info.reserves.rejectRate)}（S101 要求 ≤5%）`);
console.log(`扣账     : charged=${info.settles.charged}  reconciled=${info.settles.reconciled}`);
console.log(`拦截     : ${info.blocks} 次  block/(reserve+block)=${pct(info.blockShare)}（判据 0–5%，>10% 额度不对）`);
console.log(`主人豁免 : ${info.ownerOverrides} 次   窗口到点重试：${info.retries} 次`);
if (info.estimatePairs) {
  console.log(`估算/实际: ${info.estimatePairs} 对  P50=${info.estimateP50}  P90=${info.estimateP90}（S100 要求 P90 ≤1.3）`);
} else {
  console.log('估算/实际: 没有可用的 charged 对（actual>0）');
}
console.log(`判定调用 : goal_judging=${info.goalJudging} 次（当前配置下 RDD 接管目标，内建判定不跑 = N/A）`);
console.log(`复盘配对 : learning 拦截 ${info.learningBlocks} 次，其中未配对 ${info.unmatchedLearningBlocks} 次`);

console.log('');
if (!warn.length) {
  console.log('VERDICT=HEALTHY  四项信号都在健康区间');
} else {
  console.log('VERDICT=WARN  有 ' + warn.length + ' 条要处理：');
  for (const w of warn) console.log(`  · ${w.code}: ${w.detail}`);
}
console.log('');
process.exit(warn.length ? 1 : 0);
