#!/usr/bin/env node
'use strict';
/*
 * review-batch.js —— 每轮跑完后的「批次审核包」生成器（H13 的执行侧）
 *
 * 为什么需要（2026-10-20 用户要求）：
 *   用户原话：「子agent审核可以加一个多轮开关后就可以提示审一下」。
 *   run-mutation.ps1 -Rounds 已经会在每轮结束落盘 review-requests\round-*.json，
 *   但那个文件只是「请求」，没人把它变成审核者能直接吃的材料。
 *   本脚本把「该审什么」组装成一份**只读审核包**：批次卡判据 + 验证卡证据 +
 *   代码绑定 + 本轮部署 sha + 已知债，一次性摆给审核者（人或子 agent）。
 *
 * 设计铁律（沿用 adversarial-review.js 的 A 方案）：
 *   **只给原始产物，不给作者的结论/自评。** 让审核者自己找矛盾。
 *   审核包里【刻意不含】「本批已 PASS」这类自我评价 —— 那会带偏审核。
 *
 * 它做什么：
 *   1. 读批次卡 → 抽出判据表（S 编号 + 判据文字）
 *   2. 读验证卡 → 抽出对应 V- 卡的「结果/原因/证据」
 *   3. 跑 check-evidence-anchor.js → 证据坐标是否指得到东西
 *   4. 读 deploy-ledger.jsonl → 本批部署过哪些 sha
 *   5. 读 git log → 本批代码提交（只读，不改仓库）
 *   6. 汇总成一份 markdown 审核包 + 一份 JSON（给子 agent 吃）
 *
 * 用法：
 *   node review-batch.js --batch G4b                 # 生成审核包
 *   node review-batch.js --batch G4b --out <目录>
 *   node review-batch.js --batch G4b --json-only
 *   node review-batch.js --latest                    # 取 review-requests 里最新一条
 *   node review-batch.js --selftest                  # 证明能正确抽出判据
 *
 * 退出码：0 正常 / 2 找不到批次卡 / 3 用法或环境错
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const RDD = 'D:\\rdd';
const CARDS = path.join(RDD, 'docs', 'rdd-docs', 'rdd架构', '实机验证');
const REPORT = path.join(RDD, 'workspace', 'rdd-selfcompile', 'report');
const REQUESTS = path.join(REPORT, 'review-requests');
const LEDGER = path.join(REPORT, 'deploy-ledger.jsonl');
const NUMEN = path.join(RDD, 'workspace', 'minecraft-numen');
const CHECKER = path.join(RDD, 'workspace', 'rdd-selfcompile', 'scripts', 'verify-tools', 'check-evidence-anchor.js');
const MONITOR = path.join(RDD, 'mc', 'The Best of Twilight Forest', 'config', 'numen', 'monitor');

const EXIT_OK = 0, EXIT_NO_CARD = 2, EXIT_USAGE = 3;

const HELP = `用法：
  node review-batch.js --batch <batchId> [--out <目录>] [--json-only]
  node review-batch.js --latest
  node review-batch.js --selftest

  --batch      批次号（如 G4b），对应 实机验证\\<batchId>-批次卡.md
  --latest     取 report\\review-requests\\ 里最新一条的 batch 字段
  --out        输出目录（默认 report\\review-packs\\）
  --json-only  只写 JSON，不写 markdown

退出码：0 正常 / 2 找不到批次卡 / 3 用法或环境错`;

function parseArgs(argv) {
  const o = { batch: null, latest: false, out: null, jsonOnly: false, selftest: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--batch') o.batch = argv[++i];
    else if (a === '--latest') o.latest = true;
    else if (a === '--out') o.out = argv[++i];
    else if (a === '--json-only') o.jsonOnly = true;
    else if (a === '--selftest') o.selftest = true;
    else if (a === '--help' || a === '-h') o.help = true;
  }
  return o;
}

/* ── 从批次卡抽判据表 ── */
// 判据行的形态：| S82 | 离线 | 场景 | 判据 | 证据坐标 |
function extractCriteria(md) {
  const out = [];
  for (const line of md.split(/\r?\n/)) {
    const cells = line.split('|').map((s) => s.trim());
    if (cells.length < 5) continue;
    const id = cells[1];
    if (!/^S\d+[a-z]?$/.test(id)) continue;              // 只要 S 编号行
    if (/^-+$/.test(cells[2])) continue;                 // 表头分隔线
    out.push({
      id,
      env: cells[2] || '',
      scenario: cells[3] || '',
      criterion: cells[4] || '',
      evidenceCoord: cells[5] || '',                     // 可能不存在（旧卡）
    });
  }
  return out;
}

/* ── 从批次卡抽「判据冻结坐标」 ── */
// 真实卡里「判据冻结」标题与 commit 常在**不同行**（标题一行、commit 下一行），
// 所以用 [\s\S]{0,200}? 跨行找，而不是要求同一行（自测抓到过）。
function extractFreezeCoord(md) {
  const m = md.match(/判据冻结[\s\S]{0,200}?commit\s*`([0-9a-f]{7,40})`/i);
  return m ? m[1] : null;
}

/* ── 从验证卡抽对应 V- 卡（按 batchId 找触发原因里提到的 V 编号） ── */
function extractVerifyCards(md, batchId) {
  const cards = [];
  const re = /^#{2,3}\s*(V-\d{8}-\d{2})\s*[·:：]?\s*(.*)$/gm;
  const marks = [];
  let m;
  while ((m = re.exec(md))) marks.push({ id: m[1], title: m[2], start: m.index });
  for (let i = 0; i < marks.length; i++) {
    const end = i + 1 < marks.length ? marks[i + 1].start : md.length;
    const body = md.slice(marks[i].start, end);
    // 与批次相关：正文提到 batchId 或卡头写了 batchId
    if (!new RegExp(batchId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i').test(body)) continue;
    const status = (body.match(/\|\s*状态\s*\|\s*([^|\n]+)/) || [])[1] || '';
    const result = (body.match(/\|\s*结果\s*\|\s*([^|\n]+)/) || [])[1] || '';
    const reason = (body.match(/\|\s*原因\s*\|\s*([^|\n]+)/) || [])[1] || '';
    cards.push({ id: marks[i].id, title: marks[i].title, status: status.trim(), result: result.trim(), reason: reason.trim() });
  }
  return cards;
}

/* ── 读部署流水里本批的行 ── */
function extractDeploys(batchId) {
  if (!fs.existsSync(LEDGER)) return { rows: [], unknownBatch: 0 };
  const rows = [];
  let unknownBatch = 0;
  for (const line of fs.readFileSync(LEDGER, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const j = JSON.parse(line);
      if (j.batch === batchId) rows.push(j);
      else if (j.batch === '-') unknownBatch++;
    } catch { /* 坏行跳过 */ }
  }
  return { rows, unknownBatch };
}

/* ── 跑证据坐标检查（只读） ── */
function runEvidenceCheck() {
  if (!fs.existsSync(CHECKER)) return { error: '检查器不存在' };
  const r = spawnSync(process.execPath, [CHECKER, '--cards', CARDS, '--monitor', MONITOR, '--json'], { encoding: 'utf8', timeout: 60000 });
  try { return JSON.parse(r.stdout || '{}'); } catch { return { error: `检查器输出无法解析（exit=${r.status}）` }; }
}

/* ── 本批的代码提交（只读 git log） ── */
function extractCommits(batchId) {
  const r = spawnSync('C:\\Users\\admin\\AppData\\Local\\Programs\\MinGit\\cmd\\git.exe',
    ['-C', NUMEN, 'log', '--since=3 days ago', '--format=%h|%ad|%s', '--date=format:%m-%d %H:%M'],
    { encoding: 'utf8', timeout: 30000 });
  if (r.status !== 0) return [];
  return r.stdout.split(/\r?\n/).filter((l) => l.trim() && new RegExp(batchId, 'i').test(l));
}

/* ── 组装审核包 ── */
function buildPack(batchId) {
  const cardPath = path.join(CARDS, `${batchId}-批次卡.md`);
  if (!fs.existsSync(cardPath)) return { error: `找不到批次卡：${cardPath}`, code: EXIT_NO_CARD };
  const card = fs.readFileSync(cardPath, 'utf8');
  const criteria = extractCriteria(card);
  const freeze = extractFreezeCoord(card);

  const monthCard = path.join(CARDS, `${new Date().toISOString().slice(0, 7)}.md`);
  const verifyText = fs.existsSync(monthCard) ? fs.readFileSync(monthCard, 'utf8') : '';
  const verifyCards = extractVerifyCards(verifyText, batchId);

  const deploys = extractDeploys(batchId);
  const commits = extractCommits(batchId);
  const evidence = runEvidenceCheck();

  // ★ 刻意不含「本批已 PASS」这类自评 —— 只给原始产物，让审核者自己找矛盾
  return {
    batchId,
    generatedAt: new Date().toISOString(),
    cardPath,
    freezeCommit: freeze,
    criteriaCount: criteria.length,
    criteria,
    verifyCards,
    deploys: deploys.rows,
    ledgerUnknownBatch: deploys.unknownBatch,
    commits,
    evidenceSummary: {
      hard: (evidence.hard || []).length,
      warn: (evidence.warn || []).length,
      hardItems: (evidence.hard || []).slice(0, 20),
      warnItems: (evidence.warn || []).slice(0, 20),
      error: evidence.error || null,
    },
    auditInstructions: [
      '你是一个独立审核者。只依据下面的原始产物判断，不要相信任何自评。',
      '按 Z 迭代口径分两类：①作品 bug（改掉就完）②harness 债（goal/工具/文档没拦住，改进所有未来批次）。',
      '重点找三类矛盾：判据没被证据覆盖 / 证据坐标指不到东西 / 声明与代码绑定不一致。',
      '找不到问题也要说「查了哪些、为什么没找到」，不许只写「通过」。',
    ],
  };
}

function renderMarkdown(pack) {
  const L = [];
  L.push(`# 批次审核包 · ${pack.batchId}`);
  L.push('');
  L.push(`> 生成于 ${pack.generatedAt} ｜ 本包**只含原始产物**，不含任何自评结论。`);
  L.push(`> 审核口径见文末「审核说明」。`);
  L.push('');
  L.push('## 1 · 判据冻结坐标');
  L.push('');
  L.push(pack.freezeCommit ? `commit \`${pack.freezeCommit}\`` : '**未填**（旧格式卡，或起草时未提交）');
  L.push('');
  L.push(`对账命令：\`git -C "D:\\rdd\\docs\\rdd-docs" log -1 --format=%cI ${pack.freezeCommit || '<sha>'}\``);
  L.push(`→ 该时刻必须**早于**下方验证卡的实机证据时间戳。`);
  L.push('');
  L.push(`## 2 · 判据（${pack.criteriaCount} 条）`);
  L.push('');
  if (pack.criteria.length === 0) L.push('（没抽到判据 —— 卡格式可能不对）');
  else {
    L.push('| # | 环境 | 场景 | 判据 | 证据坐标 |');
    L.push('|---|---|---|---|---|');
    for (const c of pack.criteria) L.push(`| ${c.id} | ${c.env} | ${c.scenario} | ${c.criterion} | ${c.evidenceCoord || '—'} |`);
  }
  L.push('');
  L.push(`## 3 · 验证卡（提到 ${pack.batchId} 的）`);
  L.push('');
  if (pack.verifyCards.length === 0) L.push('（验证卡里没有提到本批次 —— 这是缺口，说明判据与证据没连上）');
  else {
    for (const v of pack.verifyCards) {
      L.push(`### ${v.id} · ${v.title}`);
      L.push(`- 状态：${v.status}`);
      L.push(`- 结果：${v.result}`);
      L.push(`- 原因：${v.reason}`);
      L.push('');
    }
  }
  L.push(`## 4 · 本批部署（deploy-ledger.jsonl）`);
  L.push('');
  if (pack.deploys.length === 0) {
    // ★ 这是审计发现，不是「没部署」的同义词：
    //   可能是真没部署，也可能是部署时没传 -BatchId（流水照记，只是 batch="-"）。
    //   两者必须分开说，否则审核者会误判。
    const unknown = pack.ledgerUnknownBatch || 0;
    L.push('**⚠ 流水里没有本批记录**。两种可能，必须查清是哪一种：');
    L.push(`1. 本批**没部署**（离线批，如 G4a）；`);
    L.push(`2. 部署了但**没传 \`-BatchId\`** —— 流水里会记成 \`batch="-"\`（当前未知批次共 ${unknown} 条）。`);
    L.push('');
    L.push('判据：若验证卡里有实机证据（说明跑过游戏），就必须有部署记录；没有 = 部署走了旁路，属 harness 债。');
  } else {
    L.push('| 时间 | sha | mutation | 实例 |');
    L.push('|---|---|---|---|');
    for (const d of pack.deploys) L.push(`| ${d.at} | ${d.sha.slice(0, 12)}… | ${d.mutation} | ${d.instance} |`);
  }
  L.push('');
  L.push(`## 5 · 本批代码提交（minecraft-numen）`);
  L.push('');
  if (pack.commits.length === 0) L.push('（git log 近 3 天没有提到本批的提交）');
  else for (const c of pack.commits) L.push(`- \`${c}\``);
  L.push('');
  L.push(`## 6 · 证据坐标检查（check-evidence-anchor.js）`);
  L.push('');
  L.push(`hard=${pack.evidenceSummary.hard} warn=${pack.evidenceSummary.warn}`);
  if (pack.evidenceSummary.error) L.push(`\n检查器报错：${pack.evidenceSummary.error}`);
  if (pack.evidenceSummary.hardItems.length) {
    L.push('\n**hard（坐标指不到东西/引文不存在）**：');
    for (const h of pack.evidenceSummary.hardItems) L.push(`- ${h.md}:${h.mdLine || '-'} ${h.level} ${h.coord || ''}`);
  }
  if (pack.evidenceSummary.warnItems.length) {
    L.push('\n**warn（缺行号/行漂了）**：');
    for (const w of pack.evidenceSummary.warnItems) L.push(`- ${w.md}:${w.mdLine || '-'} ${w.level} ${w.coord || ''}`);
  }
  L.push('');
  L.push('## 7 · 审核说明');
  L.push('');
  for (const s of pack.auditInstructions) L.push(`- ${s}`);
  L.push('');
  return L.join('\n');
}

/* ── 自测 ── */
function selftest() {
  const sample = [
    '| # | 环境 | 场景 | 判据 | 证据坐标 |',
    '|---|---|---|---|---|',
    '| S82 | 离线 | 必知区 900 + 上限 800 | status=DENIED | 验后回填 |',
    '| S83 | 离线 | 必知 200 + 可选 300 | 保留必知+A | 验后回填 |',
    '| 备注 | 不是判据 | 应被忽略 | x | y |',
  ].join('\n');
  const got = extractCriteria(sample);
  const okCount = got.length === 2;
  console.log(`  ${okCount ? '✔' : '✘'} 判据抽取：期望 2 条，实得 ${got.length} 条`);

  // 样例要贴近真实卡：标题一行、commit 下一行（跨行抽取是重点）
  const freeze = extractFreezeCoord('### 判据冻结坐标\n> **commit `cb1d3dbf9a13`**（2026-10-20 23:18:54）');
  const okFreeze = freeze === 'cb1d3dbf9a13';
  console.log(`  ${okFreeze ? '✔' : '✘'} 冻结坐标抽取：期望 cb1d3dbf9a13，实得 ${freeze}`);

  const vtext = [
    '## V-20261020-26 · G4b 降档实机',
    '| 状态 | ✅ 通过 |',
    '| 结果 | 四条全过 |',
    '| 原因 | 因为 X |',
    '',
    '## V-20261020-27 · 别的批次',
    '| 状态 | 🟡 |',
  ].join('\n');
  const vc = extractVerifyCards(vtext, 'G4b');
  const okV = vc.length === 1 && vc[0].id === 'V-20261020-26';
  console.log(`  ${okV ? '✔' : '✘'} 验证卡抽取：期望 1 张 V-20261020-26，实得 ${vc.map((x) => x.id).join(',') || '空'}`);

  const allOk = okCount && okFreeze && okV;
  console.log(`\n  selftest: ${allOk ? 'PASS' : 'FAIL'}`);
  return allOk ? EXIT_OK : EXIT_NO_CARD;
}

/* ── main ── */
function main() {
  const opt = parseArgs(process.argv.slice(2));
  if (opt.help) { console.log(HELP); return EXIT_OK; }
  if (opt.selftest) return selftest();

  let batchId = opt.batch;
  if (opt.latest || !batchId) {
    if (!fs.existsSync(REQUESTS)) { console.error(`[env] 没有 review-requests 目录：${REQUESTS}`); return EXIT_USAGE; }
    const files = fs.readdirSync(REQUESTS).filter((f) => f.endsWith('.json')).sort();
    if (files.length === 0) { console.error('[env] review-requests 里没有请求文件'); return EXIT_USAGE; }
    const latest = JSON.parse(fs.readFileSync(path.join(REQUESTS, files[files.length - 1]), 'utf8'));
    batchId = latest.batch && latest.batch !== '-' ? latest.batch : null;
    if (!batchId) { console.error('[env] 最新请求里没有批次号（部署时没传 -BatchId）'); return EXIT_USAGE; }
    console.log(`[latest] 取最新请求的批次：${batchId}`);
  }

  const pack = buildPack(batchId);
  if (pack.error) { console.error(`[fail] ${pack.error}`); return pack.code || EXIT_USAGE; }

  const outDir = opt.out || path.join(REPORT, 'review-packs');
  fs.mkdirSync(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const base = path.join(outDir, `${batchId}-${stamp}`);
  fs.writeFileSync(`${base}.json`, JSON.stringify(pack, null, 2), 'utf8');
  if (!opt.jsonOnly) fs.writeFileSync(`${base}.md`, renderMarkdown(pack), 'utf8');

  console.log(`审核包已生成：`);
  console.log(`  ${base}.json`);
  if (!opt.jsonOnly) console.log(`  ${base}.md`);
  console.log(`  判据 ${pack.criteriaCount} 条 ｜ 验证卡 ${pack.verifyCards.length} 张 ｜ 部署 ${pack.deploys.length} 次 ｜ 提交 ${pack.commits.length} 条 ｜ 证据 hard=${pack.evidenceSummary.hard} warn=${pack.evidenceSummary.warn}`);
  return EXIT_OK;
}

process.exit(main());
