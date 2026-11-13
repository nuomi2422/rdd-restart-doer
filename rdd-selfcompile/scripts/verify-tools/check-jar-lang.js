#!/usr/bin/env node
// check-jar-lang.js -- 检查部署到 live 的 numen_api jar 是否带 datagen 语言文件。
//
// 为什么需要它（TL-2026-10-06-01，静默失效类）：
//   翻译键全在 ModLanguageData（源码里），但 lang JSON 是 :api:neoforge:runData 的产物，
//   落在 api/neoforge/src/generated/resources/（被 .gitignore 忽略、由 sourceSets 带进构建）。
//   本地 run-mutation 构建不跑 datagen —— 一旦生成目录被删/被清，dev jar 就静默缺翻译，
//   游戏里所有 I18n 键显示成原始键（numen.xxx），无任何报错。
//
// 2026-11-13: reuse classrefs ZIP reader; inspect exact entries in a standalone API
// or one-level API registered by JarJar metadata. Raw filename strings are not evidence.
// Resource presence does not prove the game renders translated text.
//
// usage:
//   node check-jar-lang.js                  # 默认查 live 实例 mods 下的 numen_api jar
//   node check-jar-lang.js --dir <mods目录> # 指定 mods 目录
//   node check-jar-lang.js --jar <文件>     # 直接指定 jar
//   node check-jar-lang.js --json           # 机器可读输出
//
// exit: 0 = 两个语言文件都在；1 = 缺（部署 jar 没带翻译）；3 = 环境错（目录/jar 找不到）

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const { listEntries, readEntry } = createRequire(import.meta.url)('./classrefs.js');

const LIVE_MODS = 'D:\\rdd\\mc\\The Best of Twilight Forest\\mods';
const WANTED = ['assets/numen_api/lang/en_us.json', 'assets/numen_api/lang/zh_cn.json'];

function parseArgs(argv) {
  const a = { dir: LIVE_MODS, jar: null, json: false };
  for (let i = 2; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--dir') a.dir = argv[++i];
    else if (t === '--jar') a.jar = argv[++i];
    else if (t === '--json') a.json = true;
    else if (t === '--help' || t === '-h') { console.log(fs.readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(0, 17).join('\n')); process.exit(0); }
    else { console.error('unknown arg: ' + t); process.exit(3); }
  }
  return a;
}

function findApi(args) {
  const files = args.jar ? [args.jar] : fs.readdirSync(args.dir)
    .filter(f => /^(?:numen_api|numen)-neoforge-.*\.jar$/.test(f))
    .map(f => path.join(args.dir, f));
  const candidates = [];
  for (const jar of files) {
    const buf = fs.readFileSync(jar), entries = listEntries(buf);
    if (/^numen_api-neoforge-/.test(path.basename(jar)) ||
        (args.jar && !/^numen-neoforge-/.test(path.basename(jar)))) {
      candidates.push({ jar, buf, entries, entryJar: null });
      continue;
    }
    const metadata = entries.filter(e => e.name === 'META-INF/jarjar/metadata.json');
    if (!metadata.length) continue;
    if (metadata.length !== 1) throw new Error('ambiguous JarJar metadata: ' + jar);
    const registered = JSON.parse(readEntry(buf, metadata[0]).toString('utf8'));
    if (!Array.isArray(registered.jars)) throw new Error('invalid JarJar metadata: ' + jar);
    for (const item of registered.jars) {
      const name = item.path;
      if (typeof name !== 'string' || !name.startsWith('META-INF/jarjar/') ||
          !name.endsWith('.jar') || name.includes('..') || name.includes('\\'))
        throw new Error('invalid registered JarJar path: ' + jar);
      const isApi = /(?:^|[/.])numen_api-neoforge-[^/]+\.jar$/.test(name) ||
        item.identifier?.artifact === 'numen_api-neoforge';
      if (!isApi) continue;
      const matches = entries.filter(e => e.name === name);
      if (matches.length !== 1) throw new Error('missing or ambiguous registered API: ' + name);
      const inner = readEntry(buf, matches[0]);
      candidates.push({ jar, buf: inner, entries: listEntries(inner), entryJar: name });
    }
  }
  if (candidates.length !== 1) throw new Error('expected one API provider, found ' + candidates.length);
  return candidates[0];
}

try {
  const args = parseArgs(process.argv);
  const { jar, buf, entries, entryJar } = findApi(args);
  const present = {};
  for (const w of WANTED) {
    const matches = entries.filter(e => e.name === w);
    if (matches.length > 1) throw new Error('ambiguous language entry: ' + w);
    if (matches.length) readEntry(buf, matches[0]); // Invalid compressed content is ENV, not presence.
    present[w] = matches.length === 1;
  }
  const ok = WANTED.every(w => present[w]), stat = fs.statSync(jar);
  const out = {
    ok, state: ok ? 'OK' : 'MISSING_LANG', jar, entryJar,
    jarMtime: stat.mtime.toISOString(), jarBytes: stat.size, entries: present,
    hint: ok ? 'Language entries present; runtime translation is not verified.'
      : 'API language entries missing. Generate datagen resources and rebuild the actual owning distribution before managed deployment; do not add a duplicate standalone API jar.',
  };
  if (args.json) console.log(JSON.stringify(out, null, 2));
  else {
    console.log('[check-jar-lang] ' + out.state + ' ' + jar + (entryJar ? '!/' + entryJar : ''));
    for (const w of WANTED) console.log('  ' + (present[w] ? 'present' : 'missing') + ' ' + w);
    console.log('  ' + out.hint);
  }
  process.exit(ok ? 0 : 1);
} catch (e) {
  const out = { ok: false, state: 'ENV', detail: e.message };
  if (process.argv.includes('--json')) console.log(JSON.stringify(out));
  else console.error('[check-jar-lang] ENV: ' + out.detail);
  process.exit(3);
}
