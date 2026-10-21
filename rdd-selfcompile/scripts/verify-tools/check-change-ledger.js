#!/usr/bin/env node
/**
 * 台账可核：`rdd存放/改动台账-*.md` 里列的提交，和仓库里真实存在的提交**对不对得上**。
 *
 * <p>为什么需要：台账是手写的，手写的表会腐化 —— 漏记一个提交、写错一个 sha，
 * 读的人就会以为「这份表是全的」。这一条把它变成机检。
 *
 * <p><b>为什么不直接调 git</b>：本机沙箱下 node 的 `child_process` 捕获输出会 EPERM
 * （管道被禁），所以这里只做**纯文本比对**：先自己导出一份日志，再喂进来。
 *
 * 用法：
 *   1) 导出（范围按台账口径自己定）：
 *      git -C D:\rdd\workspace\minecraft-numen log --since "2026-10-20 19:00" \
 *          --pretty=format:%h > D:\rdd\workspace\.tmp\gitlog.txt
 *   2) 比对：
 *      node check-change-ledger.js --log D:\rdd\workspace\.tmp\gitlog.txt
 *                                   [--ledger <台账.md>] [--json] [--selftest]
 *
 * 退出码：0 = 都覆盖了 / 1 = 有漏记或幻影 id / 2 = 用法或环境错
 */

'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_LEDGER = 'D:\\rdd\\docs\\rdd-docs\\rdd存放\\改动台账-20261021.md';

const opt = { log: null, ledger: DEFAULT_LEDGER, json: false, selftest: false };

function usage(msg) {
  if (msg) console.error('[用法] ' + msg);
  console.error('用法：node check-change-ledger.js --log <gitlog.txt> [--ledger <台账.md>] [--json] [--selftest]');
  process.exit(2);
}

for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === '--log') opt.log = process.argv[++i];
  else if (a === '--ledger') opt.ledger = process.argv[++i];
  else if (a === '--json') opt.json = true;
  else if (a === '--selftest') opt.selftest = true;
  else if (a === '--help' || a === '-h') usage();
  else usage('未知参数 ' + a);
}

/**
 * 读文本，**认 BOM**。
 * 为什么：PowerShell 5.1 的 `>` 重定向默认写 UTF-16LE，`readFileSync(...,'utf8')` 会读成乱码，
 * 于是每一行都匹配不上、所有台账 id 都被误判成「幻影」（2026-10-21 自测后第一次真跑就踩了）。
 */
function readTextSmart(file) {
  const buf = fs.readFileSync(file);
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return buf.toString('utf16le').replace(/^\uFEFF/, '');
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) return buf.toString('utf8').replace(/^\uFEFF/, '');
  return buf.toString('utf8');
}

/** 从 git log 文本里取 7 位短 sha（每行开头）。 */
function parseLog(text) {
  const out = [];
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^([0-9a-f]{7,40})\b/);
    if (m) out.push(m[1].slice(0, 7));
  }
  return out;
}

/** 从台账 markdown 里取所有 7 位以上 hex（反引号里、表格里都算）。 */
function parseLedger(text) {
  const out = new Set();
  for (const m of text.matchAll(/\b([0-9a-f]{7,40})\b/g)) {
    // 排除明显的非 sha（全数字、日期形如 20261021）
    const s = m[1];
    // 批次号也可能是全 hex（如 acb12b2），写在 batch= 后面 —— 它不是 git 对象。
    const before = text.slice(Math.max(0, m.index - 6), m.index);
    if (/batch=$/i.test(before)) continue;
    if (/^\d+$/.test(s)) continue;
    if (!/[a-f]/.test(s)) continue;
    out.add(s.slice(0, 7));
  }
  return [...out];
}

/**
 * 纯函数：比对。
 * @returns {{missing: string[], phantom: string[], covered: number, total: number}}
 */
function compare(logIds, ledgerIds) {
  const ledger = new Set(ledgerIds);
  const log = new Set(logIds);
  const missing = logIds.filter((id) => !ledger.has(id));   // 仓库有、台账没写
  const phantom = ledgerIds.filter((id) => !log.has(id));   // 台账写了、仓库没有
  return { missing, phantom, covered: logIds.length - missing.length, total: logIds.length };
}

// ────────────────────────────── 自测 ──────────────────────────────
function selftest() {
  const cases = [
    {
      name: '全覆盖',
      log: 'aaaaaaa feat: x\nbbbbbbb fix: y\n',
      ledger: '提交 `aaaaaaa` 与 `bbbbbbb` 都记了',
      want: { missing: 0, phantom: 0 },
    },
    {
      name: '漏一条',
      log: 'aaaaaaa feat: x\nbbbbbbb fix: y\n',
      ledger: '只记了 `aaaaaaa`',
      want: { missing: 1, phantom: 0 },
    },
    {
      name: '幻影 id（写错/编的）',
      log: 'aaaaaaa|feat: x\n',
      ledger: '记了 `aaaaaaa` 和 `deadbee`',
      want: { missing: 0, phantom: 1 },
    },
    {
      name: '日期不该被当成 sha',
      log: 'aaaaaaa|feat: x\n',
      ledger: '2026-10-21 记 `aaaaaaa`',
      want: { missing: 0, phantom: 0 },
    },
    {
      name: '批次号不该被当成 sha',
      log: 'aaaaaaa|feat: x\n',
      ledger: 'batch=acb12b2 记 `aaaaaaa`',
      want: { missing: 0, phantom: 0 },
    },
  ];
  let pass = 0, fail = 0;
  for (const c of cases) {
    const r = compare(parseLog(c.log), parseLedger(c.ledger));
    const ok = r.missing.length === c.want.missing && r.phantom.length === c.want.phantom;
    console.log(`  ${ok ? '✔' : '✘'} ${c.name.padEnd(18)} 期望 漏${c.want.missing}/幻${c.want.phantom} 实得 漏${r.missing.length}/幻${r.phantom.length}`);
    ok ? pass++ : fail++;
  }
  // 端到端：真读台账文件（若能读）
  if (fs.existsSync(DEFAULT_LEDGER)) {
    const ids = parseLedger(readTextSmart(DEFAULT_LEDGER));
    const ok = ids.length >= 10;
    console.log(`  ${ok ? '✔' : '✘'} e2e-ledger         从台账里解析出 ${ids.length} 个 sha`);
    ok ? pass++ : fail++;
  }
  console.log(`\n  selftest: ${pass} 过 / ${fail} 败`);
  process.exit(fail ? 1 : 0);
}

// ────────────────────────────── 主流程 ──────────────────────────────
if (opt.selftest) selftest();

if (!opt.log) usage('缺 --log（先把 git log 导出来）');
if (!fs.existsSync(opt.log)) { console.error('[env] 日志文件不存在: ' + opt.log); process.exit(2); }
if (!fs.existsSync(opt.ledger)) { console.error('[env] 台账文件不存在: ' + opt.ledger); process.exit(2); }

const logIds = parseLog(readTextSmart(opt.log));
const ledgerIds = parseLedger(readTextSmart(opt.ledger));
const r = compare(logIds, ledgerIds);

if (opt.json) {
  console.log(JSON.stringify({ ledger: opt.ledger, log: opt.log, ...r, ledgerIds }, null, 2));
  process.exit(r.missing.length || r.phantom.length ? 1 : 0);
}

console.log('');
console.log('════ 台账可核（台账 vs git log）════');
console.log(`台账 : ${path.basename(opt.ledger)}（解析出 ${ledgerIds.length} 个 sha）`);
console.log(`日志 : ${path.basename(opt.log)}（${r.total} 个提交）`);
console.log(`覆盖 : ${r.covered}/${r.total}`);
console.log('');
if (!r.missing.length && !r.phantom.length) {
  console.log('VERDICT=OK  台账与仓库一致');
} else {
  if (r.missing.length) {
    console.log('VERDICT=INCOMPLETE  仓库里有、台账没记的：');
    for (const id of r.missing) console.log(`  · ${id}`);
  }
  if (r.phantom.length) {
    console.log('VERDICT=PHANTOM  台账写了、仓库里找不到的（写错或编的）：');
    for (const id of r.phantom) console.log(`  · ${id}`);
  }
}
console.log('');
process.exit(r.missing.length || r.phantom.length ? 1 : 0);
