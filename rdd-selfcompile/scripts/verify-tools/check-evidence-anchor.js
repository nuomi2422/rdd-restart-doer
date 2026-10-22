#!/usr/bin/env node
'use strict';
/*
 * check-evidence-anchor.js —— 验证卡里的「证据坐标」到底指不指得到东西
 *
 * 为什么需要（2026-10-20 #087 实测）：
 *   复查 V-13 引用的 `[关键] minecraft:torch ×32` 时，grep 主 rdd.jsonl 命中 0 条，
 *   差点得出「汇报造假」的结论 —— 实际原文在**归档文件** rdd-1792489290677.jsonl 里。
 *   证据散落在多个 rdd*.jsonl / context-*.jsonl（含 monitor-archive），
 *   没有坐标就只能靠记忆哪个文件，每次复查都重新踩。
 *
 * 它查什么：
 *   A) 坐标能不能解析：`xxx.jsonl:1858` / `xxx.jsonl` 1858 行 → 文件在不在、行号越界没
 *   B) 坐标那一行是不是空壳：JSONL 行太短 = 多半是空行或占位
 *   C) 卡里引的原文片段在不在：优先查坐标行，其次全文件（行漂了给新行号）
 *   D) 有没有「只写文件名不写行号」的引用 → 这就是 H3 要堵的口子
 *
 * 判定分档（不谎报，对齐 check-doc-anchor-drift.js 的口径）：
 *   OK            坐标对得上，引文也在
 *   DRIFT         引文在文件里、但不在写的那个行号 → 给出正确行号
 *   MISSING_FILE  引用的文件根本不存在
 *   OUT_OF_RANGE  行号超出文件长度
 *   EMPTY_LINE    那一行是空的/太短，不可能是证据
 *   QUOTE_MISSING 引文在整个文件里都找不到 → 这条引用是编的
 *   NO_COORDINATE 提到了 jsonl 却没给行号 → 警告（不是失败，但 H3 要求补）
 *
 * 退出码：0 = 全 OK（警告不算失败）/ 2 = 有确定问题 / 3 = 用法或环境错
 *
 * 用法：
 *   node check-evidence-anchor.js                        # 用默认目录
 *   node check-evidence-anchor.js --cards <目录> --monitor <目录>
 *   node check-evidence-anchor.js --card G4b-批次卡.md    # 只查一张
 *   node check-evidence-anchor.js --selftest             # 证明检查器自己抓得住假证据
 */

const fs = require('fs');
const path = require('path');

const EXIT_OK = 0;
const EXIT_FAIL = 2;
const EXIT_USAGE = 3;

const DEFAULT_CARDS = 'D:\\rdd\\docs\\rdd-docs\\rdd架构\\实机验证';
const DEFAULT_MONITOR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';
// 证据不只躺在 monitor 里：
//   report\         ← deploy-ledger.jsonl（H4 部署流水）、w-replies 等
//   mutations\      ← 每次变异的 phase-*.json（含 jar sha）
// 只搜 monitor 会把「引用部署流水」判成 MISSING_FILE —— 假警报比没检查更糟，
// 它会教人忽略告警（2026-10-20 实测踩到）。
const DEFAULT_EXTRA_ROOTS = [
  'D:\\rdd\\workspace\\rdd-selfcompile\\report',
  'D:\\rdd\\workspace\\rdd-selfcompile\\mutations',
];

// 引文最短长度：太短的（如 `numen_context`）不当作「原文证据」来核对，
// 否则满屏假阳性。要求够长且带中文/数量符，才说明是真正的取证片段。
const QUOTE_MIN = 12;

const HELP = `用法：
  node check-evidence-anchor.js [选项]

  --cards <目录>     验证卡目录（默认 ${DEFAULT_CARDS}）
  --monitor <目录>   监测台目录，递归搜 *.jsonl（默认 ${DEFAULT_MONITOR}）
  --card <文件名>    只查某一张卡
  --verbose          逐条打印 OK 的坐标
  --selftest         自测：用合成数据证明本检查器能抓到假坐标/假引文
  --json             机器可读输出

退出码：0 全 OK ／ 2 有确定问题 ／ 3 用法或环境错`;

function parseArgs(argv) {
  const o = { cards: DEFAULT_CARDS, monitor: DEFAULT_MONITOR, extra: [], card: null, verbose: false, selftest: false, json: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--cards') o.cards = argv[++i];
    else if (a === '--monitor') o.monitor = argv[++i];
    else if (a === '--extra') o.extra.push(argv[++i]);
    else if (a === '--card') o.card = argv[++i];
    else if (a === '--verbose' || a === '-v') o.verbose = true;
    else if (a === '--selftest') o.selftest = true;
    else if (a === '--json') o.json = true;
    else if (a === '--help' || a === '-h') o.help = true;
  }
  return o;
}

const hasCJK = (s) => /[一-鿿]/.test(s);
// ★ 2026-10-22 假绿修复：原判据 `长度>=12 && (有中文 || × || 两位以上数字)`
//   把 `"role":"executor"` / `"actor":"supervisor"` 这类**短 JSON 键值对**全丢了。
//   后果是检查器对这些坐标「实际被核的引文数 = 0」→ 永远不可能报错（免检）。
//   2026-10-22 实测踩到：平行会话把 G5e:97 的坐标改到错误的归档文件
//   （该行不含 actor），却因为引文被丢弃而照样「通过」。
//   判别标准（别再犯）：**报「没问题」之前，先看这条坐标实际核了几条引文。**
//   ⇒ 加一条 JSON 键值对形态白名单，直接判为证据，不受长度/中文约束。
const JSON_KV = /^"[^"\n]{1,40}"\s*:\s*"[^"\n]{1,80}"$/;
const looksLikeEvidence = (s) =>
  JSON_KV.test(s.trim()) || (s.length >= QUOTE_MIN && (hasCJK(s) || /[×]/.test(s) || /\d{2,}/.test(s)));

/* ── 建立 jsonl 索引：basename → [完整路径…]（可能同名多份，全留着） ── */
function indexJsonl(root) {
  const idx = new Map();
  if (!fs.existsSync(root)) return idx;
  const walk = (dir, depth) => {
    if (depth > 6) return;
    let ents;
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full, depth + 1);
      else if (/\.jsonl$/i.test(e.name)) {
        if (!idx.has(e.name)) idx.set(e.name, []);
        idx.get(e.name).push(full);
      }
    }
  };
  walk(root, 0);
  return idx;
}

/**
 * ★ 2026-10-22 归档族索引（治「行号漂移」的根因，不是改数字）
 *
 * 实测根因（A1）：monitor 里的 `rdd.jsonl` 会轮转 —— 写卡时它还在，
 * 几小时后被换成 `rdd-<epoch>.jsonl` 存档、活动文件重新从第 1 行开始。
 * 于是「rdd.jsonl:922」在写卡时为真，轮转后活动文件只剩 841 行 → OUT_OF_RANGE。
 *
 * 原来的 indexJsonl 按 **basename** 建索引，`rdd-1792600891285.jsonl`
 * 永远成不了 `rdd.jsonl` 坐标的候选文件 → 归档兜底对 OUT_OF_RANGE 无效。
 *
 * 现在显式建族：`rdd.jsonl` ↔ `rdd-<epoch>.jsonl`、
 *              `context.jsonl` ↔ `context-<epoch>.jsonl`。
 * 族内任一份够长，就认为「这条坐标指向的是这个族里的某一行」。
 */
function familyOf(name) {
  const m = name.match(/^([A-Za-z0-9_.\-]+?)(?:-\d{8,})?\.jsonl$/i);
  return m ? m[1].toLowerCase() : name.toLowerCase();
}
function buildFamilies(idx) {
  const fam = new Map();
  for (const [name, files] of idx) {
    const key = familyOf(name);
    if (!fam.has(key)) fam.set(key, []);
    for (const f of files) if (!fam.get(key).includes(f)) fam.get(key).push(f);
  }
  return fam;
}

const lineCache = new Map();
function readLines(file) {
  if (lineCache.has(file)) return lineCache.get(file);
  let lines = null;
  try { lines = fs.readFileSync(file, 'utf8').split(/\r?\n/); } catch { lines = null; }
  lineCache.set(file, lines);
  return lines;
}

/* ── 从一张卡里抽出所有坐标 ── */
// 卡里的真实写法是「文件名被反引号包住」：`rdd.jsonl`:1827
// 所以文件名后面允许出现 反引号/引号/右括号/空白 再跟冒号或「第 N 行」。
// （第一版正则要求 .jsonl 紧跟冒号，结果一条都匹配不到 —— 自测抓到的第二个 bug。）
const SEP = '[`\'"」）)\\s]{0,4}';
const RE_COLON = new RegExp('([A-Za-z0-9_.\\-]+\\.jsonl)' + SEP + '[:：]\\s*(\\d{1,7})', 'g');
const RE_LINE = new RegExp('([A-Za-z0-9_.\\-]+\\.jsonl)' + SEP + '(?:第\\s*)?(\\d{1,7})\\s*行', 'g');
// 只提文件名、没给行号 —— 不用负向断言（JS 会回溯，导致带行号的也被误判），
// 改成「先扫全部文件名，再排除已在 coords 里带行号的那些」，见 checkCard。
const RE_ANY_NAME = /([A-Za-z0-9_.\-]+\.jsonl)/g;

function extractCoords(text) {
  const coords = [];
  const seen = new Set();
  const add = (name, line, col, form) => {
    const k = `${name}#${line}`;
    if (seen.has(k)) return;
    seen.add(k);
    coords.push({ name, line: parseInt(line, 10), col, form });
  };
  let m;
  while ((m = RE_COLON.exec(text))) add(m[1], m[2], m.index, 'colon');
  while ((m = RE_LINE.exec(text))) add(m[1], m[2], m.index, 'line-word');
  return coords;
}

/* ── 在坐标附近找「被引用的原文片段」 ── */
// 取该坐标所在行 + 后续 2 行里的反引号片段，长度/形态够像证据才核
// ★ 2026-10-22：坐标本身不是引文。
//   `rdd.jsonl`:922 这类片段也会被反引号包住，若被当成引文去核，
//   会因为「坐标不在日志行里」误报 QUOTE_MISSING。
//   实测踩过：平行会话把坐标改成 `rdd-1792587704647.jsonl`:922 后，
//   这个坐标片段自己就被当成引文送去核了。
const COORD_FRAG = /^[A-Za-z0-9_.\-]+\.jsonl\s*[:：]\s*\d+$/;
// ★ 2026-10-22 窗口不能跨条目。
//   §6.4 的写法是「一条坐标 + 空行 + 下一条坐标」。原实现取「本行 + 后 2 行」，
//   于是下一条的引文（如 `"role":"executor"`）会被算进上一条的窗口，
//   拿去跟上一条的坐标核 → 误报 QUOTE_MISSING（实测踩到，G5f X5 就是这样红的）。
//   判别标准：**报「引文不存在」之前，先看这条引文是不是属于下一条坐标。**
//   ⇒ 遇到空行就停。同一行内的多引文（含表格行）仍然全收。
function quotesNear(lines, lineIdx) {
  const out = [];
  for (let i = lineIdx; i <= Math.min(lineIdx + 2, lines.length - 1); i++) {
    if (i > lineIdx && lines[i].trim() === '') break;   // 空行 = 条目边界
    const re = /`([^`\n]{4,200})`/g;
    let m;
    while ((m = re.exec(lines[i]))) {
      const q = m[1].trim();
      if (looksLikeEvidence(q) && !/\.jsonl$/i.test(q) && !COORD_FRAG.test(q)) {
        out.push({ text: q, mdLine: i + 1 });
      }
    }
  }
  return out;
}
/* ── 核心判定 ── */
function checkCard(mdPath, idx, families) {
  const mdName = path.basename(mdPath);
  const raw = fs.readFileSync(mdPath, 'utf8');
  const lines = raw.split(/\r?\n/);
  const findings = [];
  const coords = extractCoords(raw);

  for (const c of coords) {
    // 这个坐标在第几行 md（用于取附近引文）
    const before = raw.slice(0, c.col);
    const mdLineIdx = before.split(/\r?\n/).length - 1;

    const candidates = idx.get(c.name) || [];
    if (candidates.length === 0) {
      findings.push({ level: 'MISSING_FILE', md: mdName, mdLine: mdLineIdx + 1, coord: `${c.name}:${c.line}`, detail: `监测目录里找不到 ${c.name}` });
      continue;
    }
    // 多份同名：任一份对得上就算 OK（归档/当前文件都可能）
    let best = null;
    for (const file of candidates) {
      const fl = readLines(file);
      if (!fl) continue;
      if (c.line > fl.length) {
        // ★ 2026-10-22：先看归档族里有没有哪一份够长。
        //   `rdd.jsonl` 会轮转，写卡时它够长、轮转后它不够长 ——
        //   这时判 OUT_OF_RANGE 是**假警报**（坐标当时是真的）。
        //   判「假警报」的依据：同族某份归档 >= 该行号。
        const fam = families && families.get(familyOf(c.name)) || [];
        const reachable = fam.some((f) => { const l = readLines(f); return l && l.length >= c.line; });
        if (!best) {
          best = reachable
            ? { level: 'OK', file, coord: `${c.name}:${c.line}`, rotated: true,
                detail: `${path.basename(file)} 只有 ${fl.length} 行，但归档族里有够长的文件 —— 日志轮转导致的行号失效，不是假坐标` }
            : { level: 'OUT_OF_RANGE', file, detail: `${path.basename(file)} 只有 ${fl.length} 行，引用第 ${c.line} 行（归档族里也没有够长的）` };
        }
        if (reachable) break;   // 族内有候选，不必继续看其他同名文件
        continue;
      }
      const lineText = fl[c.line - 1] || '';
      if (lineText.trim().length < 8) {
        if (!best) best = { level: 'EMPTY_LINE', file, detail: `${path.basename(file)}:${c.line} 是空行/占位` };
        continue;
      }
      // 引文核对
      const quotes = quotesNear(lines, mdLineIdx);
      let quoteVerdict = { level: 'OK' };
      for (const q of quotes) {
        if (lineText.includes(q.text)) continue;              // 就在这一行
        const hit = fl.findIndex((l) => l.includes(q.text));  // 行漂了？
        if (hit >= 0) { quoteVerdict = { level: 'DRIFT', actualLine: hit + 1, quote: q.text, mdLine: q.mdLine }; break; }
        quoteVerdict = { level: 'QUOTE_MISSING', quote: q.text, mdLine: q.mdLine };
        break;
      }
      if (quoteVerdict.level === 'OK') { best = { level: 'OK', file, coord: `${c.name}:${c.line}`, quotes: quotes.length }; break; }
      best = { level: quoteVerdict.level, file, ...quoteVerdict, coord: `${c.name}:${c.line}` };
    }
    if (best) findings.push({ md: mdName, mdLine: mdLineIdx + 1, ...best });
  }

  // 只写文件名没写行号 → H3 警告
  // 做法：先扫出所有出现过的 .jsonl 文件名，再排除「已经带行号」的那些。
  // 不用正则负向断言 —— JS 的 (?!...) 会回溯，把带行号的引用也判成没给行号（自测抓到过）。
  const bare = new Set();
  let m;
  while ((m = RE_ANY_NAME.exec(raw))) {
    const name = m[1];
    if (coords.some((c) => c.name === name)) continue;   // 这个文件在本卡里已有带行号的引用
    bare.add(name);
  }
  for (const name of bare) {
    // ★ 2026-10-21：区分「证据引用」与「指路」。
    // 实测 20 条 NO_COORDINATE 全是「查 monitor/brain.jsonl 的 blocker」这类**指路**，不是证据；
    // 逼它们编一个行号才是最坏的结果（H3 要的是坐标，不是编造）。
    // 约定：同一行里出现「指针」二字 = 明确声明这是指路，跳过。
    const pointer = raw.split(/\r?\n/).some((ln) => ln.includes(name) && ln.includes('指针'));
    if (pointer) continue;
    findings.push({ level: 'NO_COORDINATE', md: mdName, coord: name, detail: `引用了 ${name} 但没给行号（H3 要求 文件:行号；只是指路的话，在同一行写「指针」）` });
  }

  return findings;
}

/* ── 自测：证明检查器抓得住假东西 ── */
function selftest() {
  const os = require('os');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'evanchor-'));
  const mon = path.join(tmp, 'monitor');
  fs.mkdirSync(mon, { recursive: true });
  // 真证据：第 3 行含一段中文原文
  fs.writeFileSync(path.join(mon, 'rdd-real.jsonl'),
    '{"type":"a"}\n{"type":"b"}\n{"type":"c","note":"一级目标需求还差：[关键] minecraft:torch ×32（现有 22）"}\n', 'utf8');
  // ★ 2026-10-22 轮转族：`rot.jsonl` 现在只剩 1 行（已轮转），
  //   但归档 `rot-1792600891285.jsonl` 有 5 行 → 引 rot.jsonl:3 **不得**判 OUT_OF_RANGE。
  fs.writeFileSync(path.join(mon, 'rot.jsonl'), '{"type":"after-rotation"}\n', 'utf8');
  fs.writeFileSync(path.join(mon, 'rot-1792600891285.jsonl'),
    '{"a":1}\n{"a":2}\n{"a":3,"role":"executor"}\n{"a":4}\n{"a":5}\n', 'utf8');
  // 对照：另一个族里归档也短 → 该判 OUT_OF_RANGE（防止「族内有文件就一律放过」）
  fs.writeFileSync(path.join(mon, 'short.jsonl'), '{"b":1}\n', 'utf8');
  fs.writeFileSync(path.join(mon, 'short-1792600891285.jsonl'), '{"b":1}\n', 'utf8');

  const cards = path.join(tmp, 'cards');
  fs.mkdirSync(cards, { recursive: true });

  const cases = [
    { file: 'ok.md', body: '证据：`rdd-real.jsonl`:3\n`[关键] minecraft:torch ×32（现有 22）`', want: 'OK' },
    { file: 'drift.md', body: '证据：`rdd-real.jsonl`:1\n`[关键] minecraft:torch ×32（现有 22）`', want: 'DRIFT' },
    { file: 'missing.md', body: '证据：`rdd-nope.jsonl`:1', want: 'MISSING_FILE' },
    { file: 'range.md', body: '证据：`rdd-real.jsonl`:999', want: 'OUT_OF_RANGE' },
    { file: 'fake.md', body: '证据：`rdd-real.jsonl`:3\n`这段原文根本不存在于任何证据里 ×99`', want: 'QUOTE_MISSING' },
    { file: 'bare.md', body: '证据见 rdd-real.jsonl', want: 'NO_COORDINATE' },
    // 2026-10-21：指路 vs 证据。写了「指针」= 明确声明不是证据 → 不报；
    // 没写「指针」还是要报（否则这条规则会被「随手加两个字」滥用成万能免检）。
    { file: 'pointer.md', body: '异常时查 monitor/brain.jsonl 的 blocker（指针，不是证据）', want: 'OK' },
    { file: 'pointer-no-mark.md', body: '异常时查 monitor/brain.jsonl 的 blocker', want: 'NO_COORDINATE' },
    // 2026-10-22 假绿修复：短 JSON 键值对必须被当引文核。
    // 改前 `"role":"executor"` 被 looksLikeEvidence 丢掉 → 该坐标被核引文数=0 → 永远通过。
    { file: 'shortkv-ok.md', body: '证据：`rdd-real.jsonl`:3\n`"role":"executor"`', want: 'OK', setup: (mon2) => {
        const f = path.join(mon2, 'rdd-real.jsonl');
        const cur = fs.readFileSync(f, 'utf8').split(/\r?\n/);
        // 第 3 行原本以 `"}...` 结尾，把 role 插到对象里（不是替换结尾 —— 那样替换不到）
        cur[2] = cur[2].replace(/}\s*$/, ',"role":"executor"}');
        fs.writeFileSync(f, cur.join('\n'), 'utf8');
      } },
    { file: 'shortkv-fake.md', body: '证据：`rdd-real.jsonl`:3\n`"role":"planner"`', want: 'QUOTE_MISSING' },
    // 轮转族：活动文件被轮断了，但归档够长 → 不是假坐标
    { file: 'rotated-ok.md', body: '证据：`rot.jsonl`:3\n`"role":"executor"`', want: 'OK' },
    // 对照组：族内没有任何一份够长 → 该报越界
    { file: 'rotated-range.md', body: '证据：`short.jsonl`:3', want: 'OUT_OF_RANGE' },
  ];
  for (const c of cases) {
    if (c.setup) { try { c.setup(mon); } catch (e) { console.log(`  [setup fail] ${c.file}: ${e.message}`); } }
  }
  for (const c of cases) fs.writeFileSync(path.join(cards, c.file), c.body, 'utf8');

  const idx = indexJsonl(mon);
  // 归档族索引：rdd.jsonl ↔ rdd-<epoch>.jsonl（治行号漂移的假警报）
  const fams = buildFamilies(idx);
  let pass = 0, fail = 0;
  for (const c of cases) {
    const f = checkCard(path.join(cards, c.file), idx, fams);
    const got = f.length ? f[0].level : 'OK';
    const ok = got === c.want;
    console.log(`  ${ok ? '✔' : '✘'} ${c.file.padEnd(12)} 期望 ${c.want.padEnd(14)} 实得 ${got}`);
    ok ? pass++ : fail++;
  }
  console.log(`\n  selftest: ${pass} 过 / ${fail} 败`);
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
  return fail === 0 ? EXIT_OK : EXIT_FAIL;
}

/* ── main ── */
function main() {
  const opt = parseArgs(process.argv.slice(2));
  if (opt.help) { console.log(HELP); return EXIT_OK; }
  if (opt.selftest) return selftest();

  if (!fs.existsSync(opt.cards)) {
    console.error(`[env] 卡目录不存在：${opt.cards}`);
    return EXIT_USAGE;
  }
  if (!fs.existsSync(opt.monitor)) {
    console.error(`[env] 监测目录不存在：${opt.monitor}（用 --monitor 指定）`);
    return EXIT_USAGE;
  }

  const idx = indexJsonl(opt.monitor);
  // 把额外根（report\、mutations\）也建进索引，否则引用部署流水会假警报
  const extraRoots = opt.extra.length ? opt.extra : DEFAULT_EXTRA_ROOTS;
  for (const r of extraRoots) {
    if (!fs.existsSync(r)) continue;
    const sub = indexJsonl(r);
    for (const [k, v] of sub) {
      if (!idx.has(k)) idx.set(k, []);
      for (const p of v) if (!idx.get(k).includes(p)) idx.get(k).push(p);
    }
  }
  // 归档族索引必须在额外根并入之后再建，否则 report/ 里的同名文件不进族
  const families = buildFamilies(idx);
  let cards = fs.readdirSync(opt.cards).filter((f) => f.endsWith('.md') && !f.startsWith('_'));
  if (opt.card) cards = cards.filter((f) => f === opt.card);
  if (cards.length === 0) { console.error('[env] 没找到可查的卡'); return EXIT_USAGE; }

  const all = [];
  for (const f of cards) {
    try { all.push(...checkCard(path.join(opt.cards, f), idx, families)); }
    catch (e) { all.push({ level: 'READ_ERROR', md: f, detail: e.message }); }
  }

  const hard = all.filter((x) => ['MISSING_FILE', 'OUT_OF_RANGE', 'EMPTY_LINE', 'QUOTE_MISSING', 'READ_ERROR'].includes(x.level));
  const warn = all.filter((x) => ['DRIFT', 'NO_COORDINATE'].includes(x.level));

  if (opt.json) {
    console.log(JSON.stringify({ hard, warn, total: all.length }, null, 2));
  } else {
    // ★ 2026-10-22 报告口径：原来把 level:'OK' 的发现也 push 进 all，
  //   于是「解析出 19 条问题」= 0 hard + 12 warn + 7 OK，
  //   把已通过的也说成问题 —— 这个数比 warn 数大，读的人会以为漏报了。
  //   现在 OK 单独计数，只在 --verbose 时打印。
  const passed = all.filter((x) => x.level === 'OK');
  const problems = all.length - passed.length;
  const headline = opt.verbose
    ? `\n扫描 ${cards.length} 张卡，解析出 ${problems} 条问题（含警告）｜${passed.length} 条坐标已通过\n`
    : `\n扫描 ${cards.length} 张卡，解析出 ${problems} 条问题（含警告）\n`;
  console.log(headline);
    if (hard.length) {
      console.log('【失败】坐标指不到东西 / 引文不存在：');
      for (const h of hard) console.log(`  ✘ ${h.md}:${h.mdLine || '-'}  ${h.coord || ''}  ${h.level}  ${h.detail || ''}`);
      console.log('');
    }
    if (warn.length) {
      console.log('【警告】需要补坐标 / 行号漂了：');
      for (const w of warn) {
        const extra = w.level === 'DRIFT' ? `→ 实际在第 ${w.actualLine} 行（引文：${String(w.quote).slice(0, 40)}）` : (w.detail || '');
        console.log(`  ⚠ ${w.md}:${w.mdLine || '-'}  ${w.coord || ''}  ${w.level}  ${extra}`);
      }
      console.log('');
    }
    if (!hard.length && !warn.length) console.log('  ✔ 所有坐标都对得上，引文一致\n');
    console.log(`VERDICT: hard=${hard.length} warn=${warn.length}`);
  }
  return hard.length ? EXIT_FAIL : EXIT_OK;
}

process.exit(main());
