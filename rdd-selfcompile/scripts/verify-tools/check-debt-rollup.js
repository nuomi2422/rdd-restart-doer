#!/usr/bin/env node
'use strict';
/*
 * check-debt-rollup.js ——「债账有没有真的进表」的机检（H1 低成本落地）
 *
 * 为什么需要（2026-10-20 #091 自审）：
 *   H1 的试金石是「三值化必须不经任何人提醒、自己浮进下一步表」。实测连续多轮为负：
 *   主线报告写得越来越全（含「还不能用的」一节、复现命令、wire 工具），但
 *   `杂项记录` 的「下一步（汇总）」表经常**没被刷新**——完成的批次还挂在 P0，
 *   本轮新发现的技术债一条都没进表。这件事靠「我记得」是不成立的，所以做成机检。
 *
 * 它查什么（全部可机判，不做语义判断）：
 *   NO_SECTION              找不到「下一步」小节
 *   NO_DEBT_VOICE           该小节里没有任何一行提到「债 / 待修 / H 段」 —— 债账没进表
 *   COMPLETED_STILL_OPEN    某批次已在本文件的记录里 ✅，但下一步表里仍以未划线 P0 挂着（表没刷新）
 *   H_SECTION_MISSING       没有 `### H ·` 小节（harness 自身维护项无处落）
 *   BATCH_NOT_LISTED        （给 --batch 时）该批次在「下一步」小节与本文件的记录里都没出现
 *
 * 退出码：0 = 无 warn / 1 = 有 warn（不拦收工，供门禁记 WARN）/ 2 = 环境或用法错
 *
 * 用法：
 *   node check-debt-rollup.js                     # 当月
 *   node check-debt-rollup.js --date 2026-10-20   # 指定日期所在月
 *   node check-debt-rollup.js --batch G3e-2       # 额外核「本批进表了没有」
 *   node check-debt-rollup.js --json              # 机读（门禁用）
 *   node check-debt-rollup.js --selftest          # 证明检查器抓得住「表没刷新」
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const EXIT_OK = 0;
const EXIT_WARN = 1;
const EXIT_USAGE = 2;

const DEFAULT_DOCS = 'D:\\rdd\\docs\\rdd-docs';

function argOf(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
}

function monthOf(dateStr) {
  const s = dateStr || new Date().toISOString().slice(0, 10);
  return s.slice(0, 7);
}

/** 取出「## 下一步…」到下一个同/更高标题之间的文本（含 H 小节）。 */
function extractRollup(md) {
  const lines = md.split(/\r?\n/);
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/^##\s+下一步/.test(lines[i])) { start = i; break; }
  }
  if (start < 0) return null;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^##\s/.test(lines[i])) { end = i; break; }
  }
  return lines.slice(start, end).join('\n');
}

/** 未被删除线划掉的 P* 行（真正的「还挂着」）。 */
function openRows(section) {
  return section
    .split(/\r?\n/)
    .filter((l) => /^\|\s*P\d/.test(l.trim()) || /^\|\s*\*\*P\d/.test(l.trim()))
    .filter((l) => !l.includes('~~'));
}

/** 表格行按 `|` 切格（去掉首尾空段）。 */
function cellsOf(line) {
  const raw = line.split('|');
  if (raw.length && raw[0].trim() === '') raw.shift();
  if (raw.length && raw[raw.length - 1].trim() === '') raw.pop();
  return raw.map((c) => c.trim());
}

const ID_RE = /\bG\d[a-z]?(-\d)?\b/g;

/** 从一段文字里取批次号（按出现顺序去重）。 */
function idsIn(text) {
  return [...new Set(text.match(ID_RE) || [])];
}

/**
 * 取一条记录行「主体」里的批次号。
 *
 * <p>为什么要限定「主体」：记录行里会顺带提别的批次（#090 正文里提到 `G4c-开闸卡.md`），
 * 全文抓 id 会把「被提到的」当成「已完成的」，于是未完成的行被判成「表没刷新」——假阳性比不查更糟。
 * 所以只看第 3 格（事/描述）的前 60 个字符：那里才是这条记录的<b>主语</b>。
 */
function subjectIdsOfRow(line, cellIndex) {
  const c = cellsOf(line);
  const subject = c.length > cellIndex ? c[cellIndex] : (c[c.length - 1] || '');
  return idsIn(subject.slice(0, 60));
}

function check(md, opts) {
  const warn = [];
  const info = {};
  const section = extractRollup(md);
  info.hasSection = !!section;
  if (!section) {
    warn.push({ code: 'NO_SECTION', detail: '找不到「## 下一步（汇总，按优先级）」小节' });
    return { warn, info };
  }

  const debtVoice = /债|待修|H 段|h 段/.test(section);
  info.hasDebtVoice = debtVoice;
  if (!debtVoice) {
    warn.push({ code: 'NO_DEBT_VOICE', detail: '下一步表里没有任何一行提到「债 / 待修 / H 段」—— 债账没进表' });
  }

  const hasH = /^###\s*H\b/m.test(section) || /^###\s*H ·/m.test(section);
  info.hasHSection = hasH;
  if (!hasH) warn.push({ code: 'H_SECTION_MISSING', detail: '没有 `### H ·` 小节（harness 自身维护项无处落）' });

  // 已完成的批次还挂在未划线的 P0 行里 = 表没刷新
  const rows = openRows(section);
  info.openRows = rows.length;
  const doneIds = [];
  const DONE_WORD = /PASS|完成|收口|落地/;
  for (const line of md.split(/\r?\n/)) {
    if (!/^\|/.test(line.trim()) || !line.includes('✅')) continue;
    // 只认「主体里说了完成」的 ✅ 行。反例（2026-10-21 实测假阳性）：
    // `| … | #097 | **G4c 校准从「改常量」改成「配置旋钮」** | ✅ 已完成 |`
    // —— 这条 ✅ 说的是「校准这件子任务做完了」，不是「G4c 批次做完了」；
    // 只要主体里出现批次号就当成「批次已完成」，会把还挂着的 G4c 判成「表没刷新」。
    const subject = cellsOf(line)[2] || '';
    if (!DONE_WORD.test(subject)) continue;
    doneIds.push(...subjectIdsOfRow(line, 2));   // 记录表：日期|#NNN|内容|状态|下一步
  }
  const stale = [];
  for (const row of rows) {
    for (const id of subjectIdsOfRow(row, 1)) {   // 下一步表：优先级|事|判据|谁
      if (doneIds.includes(id)) stale.push(id);
    }
  }
  info.staleBatches = [...new Set(stale)];
  if (info.staleBatches.length) {
    warn.push({
      code: 'COMPLETED_STILL_OPEN',
      detail: `已完成的批次还挂在未完成的下一步行里（表没刷新）：${info.staleBatches.join(', ')}`,
    });
  }

  if (opts.batch) {
    const inSection = section.includes(opts.batch);
    const inEntries = new RegExp(`\\|\\s*#\\d+\\s*\\|[^\\n]*${opts.batch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`).test(md);
    info.batchListed = inSection || inEntries;
    if (!inSection) {
      warn.push({
        code: 'BATCH_NOT_LISTED',
        detail: `本批 ${opts.batch} 没有出现在「下一步」小节里` + (inEntries ? '（只在记录行里出现过）' : '（全文件都没有）'),
      });
    }
  }
  return { warn, info };
}

function selftest() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'debt-rollup-'));
  let failed = 0;
  let passed = 0;
  const expect = (name, md, opts, codes) => {
    const r = check(md, opts);
    const got = r.warn.map((w) => w.code).sort().join(',');
    const want = [...codes].sort().join(',');
    const ok = got === want;
    if (!ok) {
      failed++;
      console.log(`  FAIL ${name}: want[${want}] got[${got}]`);
    } else {
      passed++;
      console.log(`  ok   ${name}`);
    }
  };

  const healthy = [
    '| 2026-10-20 | #001 | **G3e 批次**，未完 | ⬜ 未完成 |',
    '',
    '## 下一步（汇总，按优先级）',
    '',
    '| 优先级 | 事 | 判据 | 谁 |',
    '|---|---|---|---|',
    '| **P0** | **G3e-2 宿主 issuer** | 冻结闸生效 | AI |',
    '| P1 | 债：估算校准 | 样本≥30 | AI |',
    '',
    '### H · harness 自身维护项',
    '',
    '| H1 | P0 | 债账进覆盖 | 可机检 | AI |',
    '',
  ].join('\n');
  expect('健康表', healthy, {}, []);

  const noSection = '| 2026-10-20 | #001 | x | ✅ |\n\n## 别的\n';
  expect('缺下一步小节', noSection, {}, ['NO_SECTION']);

  const noDebt = healthy.replace('| P1 | 债：估算校准 | 样本≥30 | AI |', '| P1 | 优化日志 | 更好读 | AI |')
    .replace('| H1 | P0 | 债账进覆盖 | 可机检 | AI |', '| H1 | P0 | 其它 | x | AI |');
  expect('一步不提债', noDebt, {}, ['NO_DEBT_VOICE']);

  const stale = healthy.replace('| **P0** | **G3e-2 宿主 issuer** | 冻结闸生效 | AI |',
    '| **P0** | **G3e 批次：安全点** | 旧凭据被拒 | AI |')
    .replace('| 2026-10-20 | #001 | **G3e 批次**，未完 | ⬜ 未完成 |',
      '| 2026-10-20 | #001 | **G3e 批次** 完成 | ✅ 已完成 |');
  expect('完成批次还挂在 P0', stale, {}, ['COMPLETED_STILL_OPEN']);

  // 2026-10-21 假阳性回归：✅ 行只是在讲「某个以批次号命名的子任务」做完了，
  // 主体没有「完成/PASS/收口/落地」字样 → 不该把这个批次标成已完成。
  const subTaskOnly = healthy.replace('| **P0** | **G3e-2 宿主 issuer** | 冻结闸生效 | AI |',
    '| **P0** | **G3e 批次：安全点** | 旧凭据被拒 | AI |')
    .replace('| 2026-10-20 | #001 | **G3e 批次**，未完 | ⬜ 未完成 |',
      '| 2026-10-20 | #002 | **G3e 校准子任务**改好了 | ✅ 已完成 |');
  expect('✅ 只是在讲子任务，不该算批次完成', subTaskOnly, {}, []);

  const noH = healthy.replace('### H · harness 自身维护项', '### 其它');
  expect('缺 H 小节', noH, {}, ['H_SECTION_MISSING']);

  const batchMiss = healthy;
  expect('本批未进表', batchMiss, { batch: 'G9z' }, ['BATCH_NOT_LISTED']);

  expect('本批已进表', healthy, { batch: 'G3e-2' }, []);

  fs.rmSync(tmp, { recursive: true, force: true });
  if (failed) {
    console.log(`SELFTEST_FAIL ${failed} 条`);
    return EXIT_FAIL_CODE;
  }
  console.log(`SELFTEST_OK ${passed}/${passed + failed}`);
  return EXIT_OK_CODE;
}

const EXIT_FAIL_CODE = 1;
const EXIT_OK_CODE = 0;

function main(argv) {
  if (argv.includes('--selftest')) return selftest();

  const docs = argOf(argv, '--docs') || DEFAULT_DOCS;
  const date = argOf(argv, '--date');
  const batch = argOf(argv, '--batch');
  const month = monthOf(date);
  const file = path.join(docs, 'rdd架构', '杂项记录', `${month}.md`);

  if (!fs.existsSync(file)) {
    const msg = `找不到 ${file}`;
    if (argv.includes('--json')) console.log(JSON.stringify({ warn: [{ code: 'NO_FILE', detail: msg }], info: { file } }));
    else console.log(`DEBT_ROLLUP_WARN ${msg}`);
    return EXIT_WARN;
  }

  const md = fs.readFileSync(file, 'utf8');
  const { warn, info } = check(md, { batch });

  if (argv.includes('--json')) {
    console.log(JSON.stringify({ warn, info: { ...info, file } }, null, 2));
  } else if (warn.length === 0) {
    console.log(`DEBT_ROLLUP_OK ${file}（下一步行=${info.openRows}，H 段=${info.hasHSection ? '有' : '无'}）`);
  } else {
    console.log(`DEBT_ROLLUP_WARN ${file}`);
    for (const w of warn) console.log(`  - ${w.code}: ${w.detail}`);
  }
  return warn.length ? EXIT_WARN : EXIT_OK;
}

if (require.main === module) {
  process.exit(main(process.argv.slice(2)));
}

module.exports = { check, extractRollup, openRows, monthOf };
