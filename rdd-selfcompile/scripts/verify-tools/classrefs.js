#!/usr/bin/env node
'use strict';
/**
 * classrefs.js —— 「这个 jar 引用了哪些 numen 类」的最小解析器（零依赖）
 *
 * WHY THIS EXISTS（2026-10-30，H10 事故的**真判据**）：
 *   2026-10-30 07:04，`api/common` 删掉 `EntityFilters`，插件 jar 却是删之前编的 ——
 *   运行时 `OpenAIProvider.buildToolList:156` 拿到 null spec，直接 FATAL 崩，同伴永远不进世界。
 *   当时的跨模块检查只有**时间图**（上游源码晚于 jar ⇒ 需重建评估），它只会说「可能」，
 *   而且过度报警：api/common 一动，8 个插件 jar 全部「更旧」。
 *
 *   时间图回答不了的那个问题，这里回答：**这个 jar 真正引用的类，当前 API 里还在不在。**
 *   - 在 → 这个 jar 与当前 API 相容，不必因为「上游动过」就重建；
 *   - 不在 → 一定会 NoClassDefFoundError / null spec，**硬 STALE**，不需要任何猜测。
 *
 * 怎么做的（不用第三方库）：
 *   1. 读 zip：从 EOCD 找中央目录 → 逐条读 local header → `zlib.inflateRawSync` 解压；
 *   2. 解 class 常量池：只认 tag=1(Utf8) 与 tag=7(Class)，其余按长度跳过；
 *   3. 被引用的名字 = CONSTANT_Class 的 name + 所有形如 `com/dwinovo/numen/...` 的 Utf8
 *      （描述符 `Lcom/...;` 也在这条里）；
 *   4. 可用名字 = **投放进 mods 的那几个 numen jar** 里的全部 `.class` 条目。
 *      ★ 只认真正加载的 jar —— build/libs 里的旧产物不算，否则「源码树里有」会冒充「运行时能加载」。
 *
 * 边界（说清楚，不吹）：
 *   - 只查 `com/dwinovo/numen/` 前缀的引用；第三方/原版类不归它管。
 *   - 不查方法/字段级签名变化（同名类改了方法签名仍可能 NoSuchMethodError）；
 *     那是下一步（可用 CONSTANT_NameAndType 比对，未做）。
 *   - `--stats` 会打印每个 jar 的类数/引用数/耗时，便于发现性能退化。
 *
 * USAGE：
 *   node classrefs.js --mods "D:\rdd\mc\The Best of Twilight Forest\mods"   # 人读报告
 *   node classrefs.js --mods <dir> --json                                  # 机器可读
 *   node classrefs.js --selftest                                          # 用内存构造的假 class 验解析器
 *
 * 退出码：0 = 无缺失引用 / 2 = 有缺失（硬 STALE） / 3 = 环境错
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const PREFIX = 'com/dwinovo/numen/';

// ── zip ───────────────────────────────────────────────────────────────────
function findEocd(buf) {
  const min = Math.max(0, buf.length - 65557);
  for (let i = buf.length - 22; i >= min; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) return i;
  }
  return -1;
}

/** 列出 zip 条目：[{ name, method, compressedSize, localOffset }] */
function listEntries(buf) {
  const eocd = findEocd(buf);
  if (eocd < 0) throw new Error('EOCD not found');
  const total = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = [];
  for (let i = 0; i < total; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('bad central dir at ' + p);
    const method = buf.readUInt16LE(p + 10);
    const compressedSize = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localOffset = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
    out.push({ name, method, compressedSize, localOffset });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

/** 取某个条目的解压后内容 */
function readEntry(buf, e) {
  const lh = e.localOffset;
  if (buf.readUInt32LE(lh) !== 0x04034b50) throw new Error('bad local header: ' + e.name);
  const nameLen = buf.readUInt16LE(lh + 26);
  const extraLen = buf.readUInt16LE(lh + 28);
  const start = lh + 30 + nameLen + extraLen;
  const data = buf.subarray(start, start + e.compressedSize);
  if (e.method === 0) return data;
  if (e.method === 8) return zlib.inflateRawSync(data);
  throw new Error('unsupported method ' + e.method + ' for ' + e.name);
}

// ── class constant pool ───────────────────────────────────────────────────
/**
 * 从一个 .class 的字节里取「它引用到的内部类名」。
 * @returns {{classes:Set<string>, utf8:Set<string>}}
 */
function parseClassRefs(bytes) {
  if (bytes.length < 10 || bytes.readUInt32BE(0) !== 0xcafebabe) return { classes: new Set(), utf8: new Set() };
  const cpCount = bytes.readUInt16BE(8);
  const utf8 = new Set();
  const utf8ByIndex = new Map();
  const classNameIdx = [];
  let p = 10;
  for (let i = 1; i < cpCount; i++) {
    const tag = bytes[p++];
    switch (tag) {
      case 1: { // Utf8
        const len = bytes.readUInt16BE(p); p += 2;
        const s = bytes.toString('utf8', p, p + len);
        utf8.add(s);
        utf8ByIndex.set(i, s);
        p += len;
        break;
      }
      case 7: { // Class → 指向某个 Utf8 槽位
        classNameIdx.push(bytes.readUInt16BE(p)); p += 2;
        break;
      }
      case 8: case 16: case 19: case 20: p += 2; break;          // String / MethodType / Module / Package
      case 15: p += 3; break;                                     // MethodHandle
      case 3: case 4: case 9: case 10: case 11: case 12: case 17: case 18: p += 4; break;
      case 5: case 6: p += 8; i++; break;                         // Long / Double 占两槽
      default:
        // 未知 tag：继续解析只会越界读，直接放弃这个类（不猜）
        return { classes: new Set(), utf8 };
    }
  }
  const classes = new Set();
  for (const idx of classNameIdx) {
    const s = utf8ByIndex.get(idx);
    if (s) classes.add(s);
  }
  return { classes, utf8 };
}

/** 从所有 Utf8 里挑出 numen 内部类名（含描述符形态 `Lcom/...;`）。 */
function pickNumenNames(utf8) {
  const out = new Set();
  for (const s of utf8) {
    let i = s.indexOf(PREFIX);
    while (i >= 0) {
      const head = s.slice(i);
      // 去掉描述符前缀与结尾分号：`Lcom/...;` / `[Lcom/...;` / 纯 `com/...`
      // ★ 字符集里必须带 `-`：`package-info` 是合法类名，漏了它会被截成 `.../package`，
      //   于是凭空多出「引用了不存在的包」这种假缺失（2026-10-30 首跑实测 11 条全是它）。
      const m = head.match(/^com\/dwinovo\/numen\/[A-Za-z0-9_$/-]+/);
      if (m) {
        const name = m[0].replace(/\/$/, '');
        // 只收「像类名」的：最后一段不能是空的；单独一个 `package` 段也不收
        if (name && !/\/$/.test(name)) out.add(name);
      }
      i = s.indexOf(PREFIX, i + 1);
    }
  }
  return out;
}

/** 一个 jar 里声明的全部类（内部名，无 .class 后缀） */
function declaredClasses(buf) {
  const set = new Set();
  for (const e of listEntries(buf)) {
    if (!e.name.endsWith('.class')) continue;
    if (e.name.startsWith('META-INF/')) continue;
    set.add(e.name.slice(0, -6));
  }
  return set;
}

/** 一个 jar 引用到的 numen 类名 */
function referencedClasses(buf) {
  const refs = new Set();
  let classes = 0;
  for (const e of listEntries(buf)) {
    if (!e.name.endsWith('.class') || e.name.startsWith('META-INF/')) continue;
    classes++;
    let parsed;
    try { parsed = parseClassRefs(readEntry(buf, e)); } catch { continue; }
    // 两条来源都要：CONSTANT_Class 给「直接引用的类」，Utf8 描述符给「签名里出现的类」
    const all = new Set([...parsed.classes, ...parsed.utf8]);
    for (const n of pickNumenNames(all)) refs.add(n);
  }
  return { refs, classes };
}

// ── 核对 ──────────────────────────────────────────────────────────────────
/**
 * @param {string} modsDir mods 目录（只认这里真正投放的 jar）
 * @returns {{ok:boolean, jars:Array, missing:Array}}
 */
function check(moodsDir) {
  const dir = moodsDir;
  const files = fs.readdirSync(dir).filter((f) => f.startsWith('numen') && f.endsWith('.jar'));
  const providerNames = ['numen_api', 'numen-neoforge'];
  const loaded = [];
  for (const f of files) {
    const full = path.join(dir, f);
    loaded.push({ file: f, full, buf: fs.readFileSync(full) });
  }
  // 2026-11-11: only one-level JarJar metadata registrations count, not arbitrary nested files.
  for (const outer of [...loaded]) {
    const entries = listEntries(outer.buf);
    const metadata = entries.find(e => e.name === 'META-INF/jarjar/metadata.json');
    if (!metadata) continue;
    const registered = JSON.parse(readEntry(outer.buf, metadata).toString('utf8'));
    if (!Array.isArray(registered.jars)) throw new Error('invalid JarJar metadata: ' + outer.file);
    for (const jar of registered.jars) {
      if (typeof jar.path !== 'string' || !jar.path.startsWith('META-INF/jarjar/') || !jar.path.endsWith('.jar') || jar.path.includes('..'))
        throw new Error('invalid JarJar registered path: ' + outer.file);
      const entry = entries.find(e => e.name === jar.path);
      if (!entry) throw new Error('missing registered JarJar: ' + jar.path);
      const buf = readEntry(outer.buf, entry);
      listEntries(buf); // malformed registered content must propagate environment failure
      loaded.push({ file: outer.file + '!/' + jar.path, full: outer.full, buf });
    }
  }
  // 「可用类」= 所有 numen jar 里声明的类的并集。
  // 为什么是并集而不是只取 api/core：rdd-core 的类内嵌在 plugins/rdd 里、ai/ui 平铺进 api jar，
  // 而 mods 里到底哪几个 jar 共存是运行时的真实状态 —— 用并集才是「运行时能不能加载到」。
  const available = new Set();
  const declaredBy = new Map();
  for (const j of loaded) {
    const decl = declaredClasses(j.buf);
    declaredBy.set(j.file, decl);
    for (const c of decl) available.add(c);
  }
  const jars = [];
  const missing = [];
  for (const j of loaded) {
    const t0 = Date.now();
    const { refs, classes } = referencedClasses(j.buf);
    const own = declaredBy.get(j.file) || new Set();
    const miss = [...refs].filter((r) => !available.has(r) && !own.has(r));
    jars.push({ file: j.file, classes, refs: refs.size, missing: miss.length, ms: Date.now() - t0 });
    for (const m of miss) missing.push({ jar: j.file, cls: m });
  }
  return { ok: missing.length === 0, jars, missing };
}

// ── CLI ───────────────────────────────────────────────────────────────────
// ── 测试夹具：内存里造一个最小 zip + 最小 class（只为验解析链路） ──────────
function buildZip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const e of entries) {
    const nameBuf = Buffer.from(e.name, 'utf8');
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(0, 6); lh.writeUInt16LE(0, 8);
    lh.writeUInt16LE(0, 10); lh.writeUInt16LE(0, 12); lh.writeUInt32LE(0, 14);
    lh.writeUInt32LE(e.data.length, 18); lh.writeUInt32LE(e.data.length, 22);
    lh.writeUInt16LE(nameBuf.length, 26); lh.writeUInt16LE(0, 28);
    locals.push(lh, nameBuf, e.data);
    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0); cd.writeUInt16LE(20, 4); cd.writeUInt16LE(20, 6);
    cd.writeUInt16LE(0, 8); cd.writeUInt16LE(0, 10);
    cd.writeUInt32LE(e.data.length, 20); cd.writeUInt32LE(e.data.length, 24);
    cd.writeUInt16LE(nameBuf.length, 28);
    cd.writeUInt32LE(offset, 42);
    centrals.push(cd, nameBuf);
    offset += 30 + nameBuf.length + e.data.length;
  }
  const cdBuf = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8); eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cdBuf.length, 12); eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cdBuf, eocd]);
}

/** 造一个「常量池里含这些类名」的最小 class（不追求可执行，只验解析） */
function synthClass(names) {
  const parts = [];
  let count = 1 + names.length * 2;
  for (const n of names) {
    const b = Buffer.from(n, 'utf8');
    const u = Buffer.alloc(3 + b.length);
    u.writeUInt8(1, 0); u.writeUInt16BE(b.length, 1); b.copy(u, 3);
    parts.push(u);
  }
  for (let i = 0; i < names.length; i++) {
    const c = Buffer.alloc(3);
    c.writeUInt8(7, 0); c.writeUInt16BE(1 + i, 1);   // 指向同名 Utf8 槽位
    parts.push(c);
  }
  const head = Buffer.alloc(10);
  head.writeUInt32BE(0xcafebabe, 0);
  head.writeUInt16BE(0, 4); head.writeUInt16BE(52, 6);
  head.writeUInt16BE(count, 8);
  return Buffer.concat([head, ...parts]);
}

// ── selftest ─────────────────────────────────────────────────────────────
function selftest() {
  const fails = [];
  const ok = (c, m) => { if (!c) fails.push(m); };

  // ① 解析器边界
  ok(parseClassRefs(Buffer.from([0, 1, 2, 3])).utf8.size === 0, '坏字节返回空集合，不抛错');
  ok(pickNumenNames(new Set(['L' + PREFIX + 'Foo;'])).has(PREFIX + 'Foo'), '描述符形态 Lcom/...; 能解析');
  ok(pickNumenNames(new Set(['[L' + PREFIX + 'Bar;'])).has(PREFIX + 'Bar'), '数组描述符也能解析');
  ok(pickNumenNames(new Set(['org/example/X'])).size === 0, '别的包不误收');
  ok(pickNumenNames(new Set([PREFIX + 'package-info'])).has(PREFIX + 'package-info'),
    'package-info 不被截成 .../package（2026-10-30 首跑 11 条假缺失就是它）');

  // ② 端到端：内存造一个 zip，插件引用 ApiPresent 与 ApiGone，api 只提供 ApiPresent
  const os = require('os');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'classrefs-'));
  try {
    const apiJar = buildZip([{ name: PREFIX + 'ApiPresent.class', data: synthClass([PREFIX + 'ApiPresent']) }]);
    const pluginJar = buildZip([{
      name: 'com/example/Plug.class',
      data: synthClass([PREFIX + 'ApiPresent', PREFIX + 'ApiGone']),
    }]);
    fs.writeFileSync(path.join(tmp, 'numen_api-fake.jar'), apiJar);
    fs.writeFileSync(path.join(tmp, 'numen-plugin-fake.jar'), pluginJar);

    const r1 = check(tmp);
    ok(r1.missing.length === 1 && r1.missing[0].cls === PREFIX + 'ApiGone',
      '端到端：引用了不存在的类必须报出来（实得 ' + JSON.stringify(r1.missing) + '）');
    ok(r1.ok === false, '端到端：有缺失时 ok=false');

    // ③ 把 ApiGone 补进 api jar → 必须转绿（证明它认的是「谁提供了这个类」）
    const apiJar2 = buildZip([
      { name: PREFIX + 'ApiPresent.class', data: synthClass([PREFIX + 'ApiPresent']) },
      { name: PREFIX + 'ApiGone.class', data: synthClass([PREFIX + 'ApiGone']) },
    ]);
    fs.writeFileSync(path.join(tmp, 'numen_api-fake.jar'), apiJar2);
    const r2 = check(tmp);
    ok(r2.missing.length === 0 && r2.ok === true, '端到端：补上类以后必须转绿（实得 ' + JSON.stringify(r2.missing) + '）');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }

  // ④ 真实 jar 上跑一遍（只读；不依赖游戏在跑）
  const MODS = 'D:\\rdd\\mc\\The Best of Twilight Forest\\mods';
  if (fs.existsSync(MODS)) {
    const apiJarName = fs.readdirSync(MODS).find((f) => f.startsWith('numen_api') && f.endsWith('.jar'));
    ok(!!apiJarName, '找到真实的 numen_api jar');
    if (apiJarName) {
      const buf = fs.readFileSync(path.join(MODS, apiJarName));
      const decl = declaredClasses(buf);
      ok(decl.size > 100, '真实 api jar 能列出类（' + decl.size + '）');
      const { refs, classes } = referencedClasses(buf);
      ok(classes > 100 && refs.size > 10, '真实 api jar 引用解析（类 ' + classes + ' / 引用 ' + refs.size + '）');
    }
  } else {
    fails.push('（跳过真实 jar 抽查：' + MODS + ' 不存在）');
  }

  for (const f of fails) console.log('  ✘ ' + f);
  console.log(fails.length ? 'SELFTEST FAIL (' + fails.length + ')' : 'SELFTEST OK');
  return fails.length ? 3 : 0;
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--selftest')) process.exit(selftest());
  const mi = argv.indexOf('--mods');
  const mods = mi >= 0 ? argv[mi + 1] : 'D:\\rdd\\mc\\The Best of Twilight Forest\\mods';
  if (!fs.existsSync(mods)) { console.error('mods 目录不存在: ' + mods); process.exit(3); }
  const r = check(mods);
  if (argv.includes('--json')) {
    console.log(JSON.stringify(r, null, 2));
    process.exit(r.ok ? 0 : 2);
  }
  console.log('════ 类级依赖核对（插件引用的 numen 类，当前 mods 里还在不在）════');
  for (const j of r.jars) {
    console.log(`   ${j.missing ? '✘' : '✔'} ${j.file.padEnd(46)} 类 ${String(j.classes).padStart(4)} · 引用 ${String(j.refs).padStart(3)} · 缺 ${j.missing} · ${j.ms}ms`);
    for (const m of r.missing.filter((x) => x.jar === j.file)) console.log('        └─ 缺: ' + m.cls);
  }
  console.log('');
  if (r.ok) {
    console.log('VERDICT=CLASSREFS_OK  没有「引用了但当前 mods 里没有」的类');
    process.exit(0);
  }
  console.log('VERDICT=CLASSREFS_MISSING  ' + r.missing.length + ' 条引用指向不存在的类 —— 这些一定会 NoClassDefFoundError：');
  for (const m of r.missing) console.log('   · ' + m.jar + ' → ' + m.cls);
  process.exit(2);
}

if (require.main === module) main();
module.exports = { listEntries, readEntry, parseClassRefs, pickNumenNames, declaredClasses, referencedClasses, check };
