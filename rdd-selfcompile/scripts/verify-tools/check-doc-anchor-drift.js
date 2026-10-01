#!/usr/bin/env node
'use strict';
/*
 * check-doc-anchor-drift.js
 * 查文档里的代码锚点是否还指对地方，并给出**新行号**（让文档能被自动修）。
 *
 * 抓两类锚点：
 *   A) 行号锚点   Foo.java:123
 *   B) 体量锚点   同一行里出现「N 行」且提到某个已知 java 类
 *
 * 判定分四档，不谎报：
 *   DEAD        文档提到的符号在源码里彻底找不到     → 确定失效
 *   DRIFT       符号还在，但不在文档写的那一行       → 漂了，直接给出新行号
 *   UNVERIFIABLE 行号在范围内但认不出符号           → 交给人/AI 判，附该行实测内容
 *   CLEAN       对得上
 *   MISSING_FILE 文档引用的文件在源码树里不存在      → 确定失效（多半是拼错）
 *
 * 为什么需要：30 号文档自己写了「数字引用规约」要求数字带模块/日期/来源，
 * 但那是纪律不是机制 —— 实测 RddPlugin.java:69 实际在 64 行，
 * 类行数从 706/1150/913 漂到 858/1376/993，没人发现。
 *
 * 退出码：0 = 无确定漂移 / 2 = 有漂移 / 3 = 用法或环境错
 */

const fs = require('fs');
const path = require('path');

const EXIT_OK = 0;
const EXIT_DRIFT = 2;
const EXIT_USAGE = 3;

function parseArgs(argv) {
  const out = { docs: [], src: null, slack: 15, verbose: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--docs') out.docs.push(argv[++i]);
    else if (a === '--src') out.src = argv[++i];
    else if (a === '--slack') out.slack = parseInt(argv[++i], 10);
    else if (a === '--verbose' || a === '-v') out.verbose = true;
    else if (a === '--help' || a === '-h') out.help = true;
  }
  return out;
}

const HELP = `用法：
  node check-doc-anchor-drift.js --docs <目录> [--docs <目录2>…] --src <源码根> [--slack N] [--verbose]

  --docs    含 md 的目录（可重复）。扫顶层 + 一层子目录
  --src     java 源码根目录（用于按文件名定位）
  --slack   「行号大致算对」的行数容差，默认 15
  --verbose 逐条打印 CLEAN 的锚点

判定分档（不谎报）：
  CLEAN         对得上
  DRIFT         符号还在、行号偏了        → 报新行号，可直接改文档
  SIZE_DRIFT    类行数偏了                → 报实测行数
  DEAD          符号彻底没了              → 不是漂，是失效，得查历史
  MISSING_FILE  文件不存在                → 多半拼错，报形近真名
  UNVERIFIABLE  认不出符号                → 附该行实测内容，人/AI 判，不判死
  HISTORICAL    上述任一项出现在*带日期的历史快照*里 → 单独归类，不算今天的债

退出码：0 = 无确定漂移（非历史）｜ 2 = 有确定漂移 ｜ 3 = 用法或环境错`;

function walkMd(dir, acc) {
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); }
  catch (e) { return acc; }
  for (const e of ents) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === '.git' || e.name === 'node_modules') continue;
      walkMd(p, acc);
    } else if (e.name.toLowerCase().endsWith('.md')) {
      acc.push(p);
    }
  }
  return acc;
}

function indexJava(srcRoot) {
  const map = new Map();
  (function walk(dir) {
    let ents;
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (e) { return; }
    for (const e of ents) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === '.git' || e.name === 'build' || e.name === '.gradle' || e.name === 'node_modules') continue;
        walk(p);
      } else if (e.name.endsWith('.java')) {
        if (!map.has(e.name)) map.set(e.name, []);
        map.get(e.name).push(p);
      }
    }
  })(srcRoot);
  return map;
}

const readCache = new Map();
function readLines(file) {
  if (!readCache.has(file)) {
    readCache.set(file, fs.readFileSync(file, 'utf8').split(/\r?\n/));
  }
  return readCache.get(file);
}

function stripMd(s) {
  return s.replace(/[*`_~]/g, '');
}

const RE_LINE_ANCHOR = /([A-Za-z0-9_]+\.java)\s*[:：]\s*(\d{2,5})/g;
// 形如 "706 行" / "706行的 TaskChain" / "`TaskChain` | **706** |" 的同行体量锚点
const RE_ROW_SIZE = /(\d{2,5})\s*行/;

const JAVA_KEYWORDS = new Set([
  'public','private','protected','static','final','void','int','boolean','String','boolean','return',
  'new','class','interface','enum','record','import','package','extends','implements','this','super',
  'null','true','false','if','else','for','while','switch','case','break','continue','throw','try',
  'catch','finally','default','synchronized','volatile','abstract','override','throws','long','double',
]);

/** 从文档那一行里抽出「这个行号锚点到底在说什么符号」 */
function extractSymbols(docLineText, fileStem) {
  const out = new Set();
  // 反引号里的标识符最可信：`bodySubmissionEnabled` / `RuntimeStore.restore`
  for (const m of docLineText.matchAll(/`([A-Za-z_][A-Za-z0-9_]*)`/g)) {
    if (!JAVA_KEYWORDS.has(m[1]) && m[1] !== fileStem) out.add(m[1]);
  }
  // 锚点后面紧跟的裸标识符：Foo.java:81 MAX_REPLAN_PER_PRIMARY
  const after = docLineText.match(/[.:：]\s*\d{2,5}\s+([A-Za-z_][A-Za-z0-9_]*)/);
  if (after && !JAVA_KEYWORDS.has(after[1])) out.add(after[1]);
  // 形如 "bodySubmissionEnabled（RddPlugin.java:69）"
  const before = docLineText.match(/([A-Za-z_][A-Za-z0-9_]*)\s*[（(][^）)]*[.:：]\s*\d{2,5}\s*[）)]/);
  if (before && !JAVA_KEYWORDS.has(before[1])) out.add(before[1]);

  // 去 markdown 强调会吃掉下划线：`:81 MAX_REPLAN_PER_PRIMARY` 被 stripMd 剥成
  // `MAXREPLANPERPRIMARY` → 源码里永远找不到 → 误报 DEAD。
  // 补救：把无下划线的大写驼峰还原成「可能的候选」，交由 findSymbolLines 用前缀匹配兜底。
  const raw = docLineText;
  for (const m of raw.matchAll(/\b([A-Z][A-Z0-9]{6,})\b/g)) {
    out.add(m[1]);
  }
  return [...out];
}

/** 在源码里找这个符号声明在第几行（认注释不算；认全大写名的下划线丢失形态） */
function findSymbolLines(javaLines, sym) {
  const hits = [];
  const esc = sym.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const res = [new RegExp(`\\b${esc}\\b`)];
  // stripMd 会吃掉下划线 → 源码里 SELF_COMPILE，文档里读成 SELFCOMPILE。
  // 办法：把「全大写驼峰」拆成带 _? 的模式，逐字符对齐。
  if (/^[A-Z0-9]+$/.test(sym) && sym.length >= 6) {
    let pat = '';
    for (const c of sym) pat += (c === c.toUpperCase() && /[A-Z0-9]/.test(c)) ? c + '_?' : c;
    res.push(new RegExp(`\\b${pat}\\b`));
  }

  for (let i = 0; i < javaLines.length; i++) {
    const l = javaLines[i];
    if (l.trim().startsWith('*') || l.trim().startsWith('//')) continue; // 注释不算声明
    if (res.some(r => r.test(l))) hits.push(i + 1);
  }
  return hits;
}

/**
 * 这份文档是不是「带日期的历史快照」？
 *
 * 为什么要分这一档：像 `23-A组架构四件套合入-20260928.md`、`测试日志.md` 这种，
 * 它记的是**当时**的代码长什么样 —— 那时候 81 行确实是 MAX_REPLAN。
 * 把它当漂移去"修"就是**篡改历史记录**，是错的。
 *
 * 判定依据（保守，宁可漏判也不误判）：
 *   1. 文件名带日期后缀 -YYYYMMDD 或 YYYYMMDD
 *   2. 文件名含快照性质的词：测试日志 / 更新日志 / 纪要 / 记录 / 检测报告 / handoff / HANDOFF
 * 只有这些才归 HISTORICAL；活文档（README / 30 红线 / 24 运维 / 50 / 51）不算。
 */
const SNAPSHOT_NAME = /-\d{8}\.md$|^\d{8}-|(测试日志|更新日志|纪要|记录|检测报告|快照)/;
function isSnapshotDoc(mdPath) {
  return SNAPSHOT_NAME.test(path.basename(mdPath));
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.docs.length || !args.src) {
    console.log(HELP);
    process.exit(args.help ? EXIT_OK : EXIT_USAGE);
  }
  if (!fs.existsSync(args.src)) {
    console.error(`源码根不存在: ${args.src}`);
    process.exit(EXIT_USAGE);
  }

  const javaIdx = indexJava(args.src);
  const mdFiles = [];
  const seenMd = new Set();
  for (const d of args.docs) {
    if (!fs.existsSync(d)) {
      console.error(`文档目录不存在: ${d}`);
      process.exit(EXIT_USAGE);
    }
    // 顶层 .md + 一层子目录（跳过更深层，避免 _归档 之类的嵌套副本重复命中）
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); }
    catch (e) { continue; }
    const push = (p) => {
      const r = path.resolve(p);
      if (seenMd.has(r)) return;
      seenMd.add(r);
      mdFiles.push(p);
    };
    for (const e of ents) {
      const p = path.join(d, e.name);
      if (e.isFile() && e.name.toLowerCase().endsWith('.md')) push(p);
      else if (e.isDirectory() && e.name !== '.git' && e.name !== 'node_modules') {
        for (const e2 of fs.readdirSync(p, { withFileTypes: true })) {
          if (e2.isFile() && e2.name.toLowerCase().endsWith('.md')) push(path.join(p, e2.name));
        }
      }
    }
  }
  if (!mdFiles.length) {
    console.error('文档目录里没有 .md');
    process.exit(EXIT_USAGE);
  }

  const findings = [];
  const tally = { CLEAN: 0, UNVERIFIABLE: 0 };

  for (const md of mdFiles) {
    const mdLines = readLines(md);
    mdLines.forEach((raw, idx) => {
      const docLine = idx + 1;
      const text = stripMd(raw);

      RE_LINE_ANCHOR.lastIndex = 0;
      let m;
      while ((m = RE_LINE_ANCHOR.exec(text)) !== null) {
        const file = m[1];
        const claimed = parseInt(m[2], 10);
        const stem = file.replace(/\.java$/, '');
        const cands = javaIdx.get(file);

        if (!cands) {
          // 拼错的可能性：MrpServer vs McpServer
          const near = [...javaIdx.keys()].filter(k =>
            k.length === file.length && levenshtein(k.toLowerCase(), file.toLowerCase()) <= 2);
          findings.push({
            kind: 'MISSING_FILE', md, docLine, file, claimed,
            msg: `源码树里没有 ${file}` + (near.length ? `；你是不是想写 ${near.join(' / ')}？` : ''),
          });
          continue;
        }

        const syms = extractSymbols(text, stem);
        let best = null; // {verdict, actualLine, detail}

        if (syms.length === 0) {
          // 认不出符号：只能报「该行实测内容」让人判
          const at = cands.map(c => readLines(c)[claimed - 1]);
          findings.push({
            kind: 'UNVERIFIABLE', md, docLine, file, claimed,
            msg: `认不出符号，无法自动判定；${file}:${claimed} 实测是: ${at.map(s => (s || '').trim().slice(0, 70)).filter(Boolean).join(' | ') || '(空行或越界)'}`,
          });
          tally.UNVERIFIABLE++;
          continue;
        }

        // 逐个符号找，取最贴近 claimed 的那个
        for (const sym of syms) {
          for (const c of cands) {
            const jl = readLines(c);
            const hits = findSymbolLines(jl, sym);
            if (!hits.length) continue;
            const nearest = hits.reduce((a, b) =>
              Math.abs(b - claimed) < Math.abs(a - claimed) ? b : a);
            const dist = Math.abs(nearest - claimed);
            const cand = { sym, nearest, dist, all: hits };
            if (!best || cand.dist < best.dist) best = cand;
          }
          if (best && best.dist <= args.slack) break; // 够近了，不必再看别的符号
        }

        if (!best) {
          findings.push({
            kind: 'DEAD', md, docLine, file, claimed,
            msg: `文档提到的符号 ${syms.join(' / ')} 在 ${file} 里彻底找不到（不是漂，是没了）`,
          });
        } else if (best.dist === 0) {
          tally.CLEAN++;
          if (args.verbose) console.log(`  CLEAN  ${path.basename(md)}:${docLine}  ${file}:${claimed} ${best.sym}`);
        } else if (best.dist <= args.slack) {
          findings.push({
            kind: 'DRIFT', md, docLine, file, claimed,
            msg: `${file}:${claimed} → 实际在 **${best.nearest}**（${best.sym}，偏 ${best.dist} 行）`,
            fix: `${file}:${claimed}`, fixTo: `${file}:${best.nearest}`,
          });
        } else {
          findings.push({
            kind: 'UNVERIFIABLE', md, docLine, file, claimed,
            msg: `符号 ${best.sym} 还在但离得太远（文档 ${claimed}，实际 ${best.nearest}，偏 ${best.dist} 行）—— 大概率这段代码被重写了，请人判`,
          });
          tally.UNVERIFIABLE++;
        }
      }

      // ---- 体量锚点：同一行出现「N 行」且提到已知 java 类 ----
      const rm = RE_ROW_SIZE.exec(text);
      if (rm) {
        const claimed = parseInt(rm[1], 10);
        // 这一行里提到的所有已知 java 类（去重，取最像被描述的那个）
        const mentioned = [...javaIdx.keys()]
          .filter(f => text.includes(f) || text.includes(f.replace(/\.java$/, '')))
          .map(f => f.replace(/\.java$/, ''));
        if (mentioned.length === 1 || (mentioned.length > 1 && text.includes('`' + mentioned[0] + '`'))) {
          const stem = mentioned[0];
          for (const c of javaIdx.get(stem + '.java')) {
            const actual = readLines(c).length;
            const diff = Math.abs(actual - claimed);
            if (diff > 8) {
              findings.push({
                kind: 'SIZE_DRIFT', md, docLine, file: stem + '.java', claimed,
                msg: `文档称 ${stem}.java ${claimed} 行，实测 **${actual}** 行（偏 ${diff}）`,
                fix: `${stem}.java ${claimed}行`, fixTo: `${stem}.java ${actual}行`,
              });
            } else {
              tally.CLEAN++;
              if (args.verbose) console.log(`  CLEAN  ${path.basename(md)}:${docLine}  ${stem} ${claimed}行`);
            }
            break;
          }
        }
      }
    });
  }

  // 分档：历史快照里的漂移不是今天的债，单独归类（见 isSnapshotDoc 的理由）
  for (const f of findings) {
    if (f.kind !== 'CLEAN' && isSnapshotDoc(f.md)) f.historical = true;
  }
  const live = findings.filter(f => !f.historical);
  const snap = findings.filter(f => f.historical);
  const hard = live.filter(f => f.kind !== 'UNVERIFIABLE');

  // 去重：多个 --docs 有父子关系时（指定了子目录又指定了父目录），
  // 同一份 md 会被扫两遍，报同样的漂移。加 md 文件名 + 判定内容做键。
  {
    const seen = new Map();
    for (const f of findings) {
      const key = `${path.resolve(f.md)}|${f.docLine}|${f.kind}|${f.msg}`;
      if (!seen.has(key)) seen.set(key, f);
    }
    findings.length = 0;
    findings.push(...seen.values());
  }

  console.log('');
  console.log('════ 文档代码锚点漂移检查 ════');
  console.log(`文档目录 : ${args.docs.join('  ')}`);
  console.log(`源码根   : ${args.src}`);
  console.log(`md 文件  : ${mdFiles.length}`);
  console.log(`判定     : 对得上 ${tally.CLEAN} / 认不出需人判 ${tally.UNVERIFIABLE} / 确定漂移 ${hard.length}`);
  console.log(`          （另有 ${snap.length} 处在带日期的历史快照里，不算今天的债）`);
  console.log('');

  if (!hard.length) {
    console.log('VERDICT=CLEAN   活文档里没有发现确定漂移');
    if (tally.UNVERIFIABLE) console.log(`（另有 ${tally.UNVERIFIABLE} 处认不出符号，已在报告里附实测行内容，未判死）`);
    process.exit(EXIT_OK);
  }

  for (const kind of ['DRIFT', 'SIZE_DRIFT', 'DEAD', 'MISSING_FILE', 'UNVERIFIABLE']) {
    const list = live.filter(f => f.kind === kind);
    if (!list.length) continue;
    const title = {
      DRIFT: 'DRIFT · 符号还在，行号偏了（附新行号，可直接改文档）',
      SIZE_DRIFT: 'SIZE_DRIFT · 类行数偏了',
      DEAD: 'DEAD · 文档说的符号在代码里没了',
      MISSING_FILE: 'MISSING_FILE · 引用的文件不存在',
      UNVERIFIABLE: 'UNVERIFIABLE · 认不出符号，需人/AI 判（未判死）',
    }[kind];
    console.log(`── ${title} (${list.length}) ──`);
    for (const f of list) {
      console.log(`  ${path.basename(f.md)}:${f.docLine}`);
      console.log(`      ${f.msg}`);
    }
    console.log('');
  }

  if (snap.length) {
    console.log(`── HISTORICAL · 历史快照里的偏移（${snap.length}）—— 不建议改，见下 ──`);
    const byDoc = {};
    for (const f of snap) (byDoc[f.md] = byDoc[f.md] || []).push(f);
    for (const md of Object.keys(byDoc)) {
      console.log(`  ${path.basename(md)}  (${byDoc[md].length} 处)`);
    }
    console.log('    ↑ 这些文档记的是「当时」的代码状态，偏移是**正常的**。');
    console.log('      要改的不是数字，而是加一句「此行号已随 <commit> 漂移，见 50 号导航 §三」。');
    console.log('');
  }

  console.log(`确定漂移 ${hard.length} 处（活文档），历史快照偏移 ${snap.length} 处，另 ${tally.UNVERIFIABLE} 处待人判`);
  console.log('VERDICT=DRIFT  活文档里的代码锚点已对不上实际代码 —— 两份各说各话，得改一边');
  process.exit(EXIT_DRIFT);
}

function levenshtein(a, b) {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return dp[a.length][b.length];
}

main();