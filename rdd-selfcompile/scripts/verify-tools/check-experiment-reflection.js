#!/usr/bin/env node
/**
 * check-experiment-reflection.js —— 实验台「反思与提醒」体检（Q18 的执行体）
 *
 * 为什么要有它（2026-10-27 主人指示）:
 *   「给 harness 门禁退游戏的时候，加一个门禁提示，就是可以给实验台写新的工具，
 *    并且写实验台实验数据的反思和提醒」
 *
 * 主人的意思有两条，本脚本只做**只读体检**，不替人写：
 *   ① **实验台可以长新工具**：跑完一轮实验，如果外面缺一个观测/切片/对照的手段，
 *      该补的是「实验台工具」而不是手工重复劳动。判据 = 已有的 exp-* / bench / mf-observer
 *      清单 + 本轮有没有新增；
 *   ② **实验数据的反思要落地**：每轮实验的数据（journal / learn-summary / verdict.json）
 *      必须配一份「人话反思」——这轮看到了什么、哪里反直觉、下一步改什么。
 *      判据 = 本轮修改过的实验产物里，有没有对应日期的反思文档（rdd存放 或 experiments/notes）。
 *
 * 设计纪律（与 check-evidence-anchor / check-debt-rollup 同族）:
 *   - **只读**：不写任何文件；输出 JSON 给门禁聚合。
 *   - **不冒充判断**：缺反思 / 账本没更新 = warn，不 BLOCK（实验可能还在跑；制造假红比漏报更糟）。
 *   - **诚实边界**：找不到数据目录 = unknown，不折成「没做」。
 *
 * ★ 2026-10-28 收紧（用户验收「实验台 AI 到底有没有在用」时发现两个假绿）：
 *   ① 反思原来只按**文件名**认（含「实验」就算）→ `87-实验台-架构与封存` 这种架构文档被算成反思。
 *      现在按**内容**：四问（看到什么 / 反直觉 / 证伪 / 下一步）至少命中两项，且必须含「证伪」或「反直觉」。
 *   ② 只看「有没有反思」，不看「数据进没进账本」→ 跑完一轮什么都不记也算过。
 *      现在同时查 experiments/workbench.json 的 tips/probes/signals/verdicts 新增；
 *      有产物、有反思但账本 0 新增 → warn（数据没进实验台）。
 *
 * 用法:
 *   node check-experiment-reflection.js            # 人读
 *   node check-experiment-reflection.js --json     # 机读（门禁用）
 *   node check-experiment-reflection.js --since 2026-10-27
 * 退出码: 0=有反思/账本已更新/无新数据; 1=有数据但反思或账本缺(warn); 2=环境/输入错误
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', '..', '..');   // D:\rdd
const HARNESS = path.join(ROOT, 'harness', 'rdd-harness');
const EXPERIMENTS = path.join(HARNESS, 'experiments');
const DOCS_REPORT = path.join(ROOT, 'docs', 'rdd-docs', 'rdd存放');
const DOCS_UNIFIED = path.join(ROOT, 'docs', 'rdd-docs', 'rdd架构', '自编译统一版');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i > -1 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}

function mtime(p) {
  try { return fs.statSync(p).mtimeMs; } catch { return 0; }
}

function listDir(p) {
  try { return fs.readdirSync(p); } catch { return null; }
}

function walk(dir, depth, out) {
  out = out || [];
  if (depth < 0) return out;
  const names = listDir(dir);
  if (!names) return out;
  for (const n of names) {
    const full = path.join(dir, n);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    if (st.isDirectory()) walk(full, depth - 1, out);
    else out.push(full);
  }
  return out;
}

/** 实验台工具清单：bin 下真正属于「实验/观测」这一族的脚本（2026-10-28 扩表）。 */
function benchTools() {
  const bin = path.join(HARNESS, 'bin');
  const names = listDir(bin) || [];
  return names
    .filter((n) => /\.js$/.test(n))
    .filter((n) => /^(exp-|bench|world-view|observer-|mf-|snapshot-world|selfcompile-drain|intent-evidence|watch-vulnerability|run-long-horizon|weekly-metrics)/.test(n))
    .sort();
}

/** 本轮（since 之后）动过的实验产物。 */
function freshArtifacts(sinceMs) {
  const files = walk(EXPERIMENTS, 3, []).filter((f) => mtime(f) >= sinceMs);
  return files.map((f) => path.relative(HARNESS, f)).sort();
}

/**
 * ★ 2026-10-28 收紧：原来只按**文件名**匹配（含「实验」就算），于是「87-实验台-架构与封存」
 * 这种架构文档也被算成一篇反思 —— 数据没更新、反思没写，门禁照样报 pass。
 * 现在改成**内容判据**：四个问题里至少要回答两个（看到什么 / 哪反直觉 / 证伪了什么 / 下一步只改哪个），
 * 且「证伪」或「反直觉」必须占一个 —— 架构文档天然没有这两样。
 */
const MARKERS = [
  { key: '看到', re: /看到了什么|观察到|数据显示|读数|现象是|实测到/ },
  { key: '反直觉', re: /反直觉|出乎意料|与预期不符|没想到|意外|反常|跟想的不一样/ },
  { key: '证伪', re: /证伪|推翻了|假设不成立|假设错|没支持|打脸|否证/ },
  { key: '下一步', re: /下一步|下一轮|下轮|明天|接下来|只改一个变量|只改|接着改/ },
];

function reflectionHits(text) {
  return MARKERS.filter((m) => m.re.test(text)).map((m) => m.key);
}

function reflections(sinceMs) {
  const out = [];
  for (const dir of [DOCS_REPORT, path.join(EXPERIMENTS, 'notes'), DOCS_UNIFIED]) {
    const names = listDir(dir);
    if (!names) continue;
    for (const n of names) {
      if (!/\.md$/.test(n)) continue;
      const full = path.join(dir, n);
      if (mtime(full) < sinceMs) continue;
      let text = '';
      try {
        if (fs.statSync(full).size > 512 * 1024) continue;   // 超大文档不读（不可能是一页纸反思）
        text = fs.readFileSync(full, 'utf8');
      } catch { continue; }
      const hits = reflectionHits(text);
      const core = hits.includes('证伪') || hits.includes('反直觉');
      if (hits.length >= 2 && core) out.push({ path: path.relative(ROOT, full), hits });
    }
  }
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

/** 账本新鲜度：workbench.json 里 since 之后新增的 tip/probe/signal/verdict 条数。 */
function ledgerFresh(sinceMs) {
  const p = path.join(EXPERIMENTS, 'workbench.json');
  if (!fs.existsSync(p)) return { count: 0, newest: null, ok: false };
  let w;
  try { w = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return { count: 0, newest: null, ok: false }; }
  let count = 0, newest = 0;
  for (const key of ['tips', 'probes', 'signals', 'verdicts']) {
    for (const row of (w[key] || [])) {
      const t = Date.parse(row.added_at || row.at || '');
      if (Number.isNaN(t)) continue;
      if (t >= sinceMs) count++;
      if (t > newest) newest = t;
    }
  }
  return { count, newest: newest ? new Date(newest).toISOString() : null, ok: true };
}

function main() {
  const sinceStr = arg('since', new Date().toISOString().slice(0, 10));
  const sinceMs = Date.parse(sinceStr + 'T00:00:00Z');
  if (Number.isNaN(sinceMs)) {
    console.error(JSON.stringify({ ok: false, code: 'BAD_INPUT', error: 'bad --since' }));
    process.exit(2);
  }

  const hasExperiments = listDir(EXPERIMENTS) !== null;
  const tools = benchTools();
  const fresh = hasExperiments ? freshArtifacts(sinceMs) : [];
  // README / 账本本身 / live 视图缓存都不算「数据产物」
  const dataFresh = fresh.filter((f) => !/(^|[\\/])(README\.md|workbench\.json)$/.test(f) && !/(^|[\\/])live[\\/]/.test(f));
  const notes = reflections(sinceMs);
  const ledger = ledgerFresh(sinceMs);
  const activity = dataFresh.length + ledger.count;

  const verdict = {
    ok: true,
    since: sinceStr,
    benchTools: tools.length,
    freshArtifacts: fresh.slice(0, 12),
    freshArtifactCount: fresh.length,
    dataArtifactCount: dataFresh.length,
    ledgerFresh: ledger.count,
    ledgerNewest: ledger.newest,
    reflections: notes.map((n) => n.path).slice(0, 8),
    reflectionHits: notes.slice(0, 8).map((n) => ({ path: n.path, hits: n.hits })),
    reflectionCount: notes.length,
    // 三条人话提醒（不冒充判断，只摆在面前）
    reminders: [
      '① 这轮实验缺的观测手段，该补成**实验台工具**（harness/bin/exp-*、bench、mf-*、observer-*）而不是手工重复；' +
      '新工具要能一条命令复现，带 --help 与自测',
      '② 每轮数据必须配一份**人话反思**：看到了什么 / 哪里反直觉 / 下一步改哪个变量；数字进 journal，判断进反思，两者别混',
      '③ 反思里写清「这轮**证伪**了什么」——只写"有效/无效"不算，要说清哪个假设被数据推翻了',
      '④ 数据要**进账本**（bench tip add / probe add / signal add / verdict add）—— 只写在聊天里等于没写',
    ],
  };

  if (!hasExperiments) {
    verdict.severity = 'unknown';
    verdict.why = `实验目录不存在（${EXPERIMENTS}）—— 没跑过实验，不折成"没写反思"`;
  } else if (activity === 0) {
    verdict.severity = 'skip';
    verdict.why = '本轮没有实验产物更新、账本也没有新增（没跑实验，跳过）';
  } else if (notes.length === 0) {
    verdict.ok = false;
    verdict.severity = 'warn';
    verdict.why = `本轮有 ${dataFresh.length} 个实验产物更新 / 账本新增 ${ledger.count} 条，但没找到同时段的反思文档（要写清看到什么·反直觉·证伪·下一步，至少两项且含证伪或反直觉）—— 数据有了、反思没落`;
  } else if (ledger.count === 0) {
    verdict.ok = false;
    verdict.severity = 'warn';
    verdict.why = `本轮产物 ${dataFresh.length} 个、反思 ${notes.length} 篇，但**账本 0 新增**（tip/probe/signal/verdict 都没有）—— 数据没进实验台，下一个人还是得考古`;
  } else {
    verdict.severity = 'pass';
    verdict.why = `本轮产物 ${dataFresh.length} 个、账本新增 ${ledger.count} 条、反思 ${notes.length} 篇`;
  }

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(verdict, null, 2));
  } else {
    console.log(`实验台反思体检 @ ${sinceStr}`);
    console.log(`  实验台工具：${verdict.benchTools} 个（${tools.slice(0, 6).join(', ')}…）`);
    console.log(`  本轮实验产物：${verdict.dataArtifactCount} 个（全部更新 ${verdict.freshArtifactCount}）`);
    if (dataFresh.length) dataFresh.slice(0, 5).forEach((f) => console.log(`    - ${f}`));
    console.log(`  账本新增：${verdict.ledgerFresh} 条${verdict.ledgerNewest ? '（最近 ' + verdict.ledgerNewest + '）' : ''}`);
    console.log(`  本轮反思：${verdict.reflectionCount} 篇`);
    notes.slice(0, 5).forEach((n) => console.log(`    - ${n.path}  命中 ${n.hits.join('/')}`));
    console.log(`  结论：${verdict.severity} —— ${verdict.why}`);
    console.log('  提醒：');
    verdict.reminders.forEach((r) => console.log('    ' + r));
  }
  process.exit(verdict.ok ? 0 : 1);
}

main();
