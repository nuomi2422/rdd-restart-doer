#!/usr/bin/env node
/**
 * H1 判据：**「身体空闲」判断只许有一处**（G3e-2，2026-10-21）。
 *
 * <p>为什么需要一条机检：签发凭据 = 宣称「此刻身体停着」。如果 A 处按「槽里没任务」判、
 * B 处按「不在等模型」判，就会出现「凭据说停着、实际在跑」——那正是 G3e 这一批要消灭的事故形态。
 * 靠「记得别写第二套」是不成立的，所以做成 grep。
 *
 * <p>判定：宿主代码里（`plugins/` 与 `api/common/src/client/`），
 * 若**同一个文件**既调 `currentTaskFor(` **又**引用 `isAwaitingLlmResponse()` / `isBusy()`，
 * 就认为它在手写「身体空闲」判断 —— 除非它在允许清单里（唯一实现处）。
 *
 * <p>不算违规的三种：
 *   ①定义处（`EntityAgentLoop` 自己声明 `isAwaitingLlmResponse`、`CompanionTickDispatcher` 自己声明 `currentTaskFor`）；
 *   ②只用一个信号（不构成「综合判断」）；
 *   ③注释里提到（扫描前会去掉行注释与块注释）。
 *
 * 用法：
 *   node check-idle-predicate.js [--src <minecraft-numen>] [--allow <文件名,...>] [--json] [--selftest]
 *
 * 退出码：0 = 合规 / 1 = 发现第二套判据 / 2 = 环境或用法错
 */

'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_SRC = 'D:\\rdd\\workspace\\minecraft-numen';
/** 唯一允许同时用两个信号的地方（G3e-2 建出来后就是它）。 */
const DEFAULT_ALLOW = ['RddSafePointIssuer.java'];
/** 只看宿主代码；纯核心（rdd-core）不碰身体状态。 */
const SCAN_ROOTS = ['plugins', path.join('api', 'common', 'src', 'client')];
/** 定义处豁免：这些文件是「信号的生产者」，不算消费者。 */
const DEFINITIONS = ['EntityAgentLoop.java', 'CompanionTickDispatcher.java'];

const opt = { src: DEFAULT_SRC, allow: DEFAULT_ALLOW.slice(), json: false, selftest: false };

function usage(msg) {
  if (msg) console.error('[用法] ' + msg);
  console.error('用法：node check-idle-predicate.js [--src <dir>] [--allow a.java,b.java] [--json] [--selftest]');
  process.exit(2);
}

for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === '--src') opt.src = process.argv[++i];
  else if (a === '--allow') opt.allow = String(process.argv[++i] || '').split(',').map((s) => s.trim()).filter(Boolean);
  else if (a === '--json') opt.json = true;
  else if (a === '--selftest') opt.selftest = true;
  else if (a === '--help' || a === '-h') usage();
  else usage('未知参数 ' + a);
}

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.java')) out.push(p);
  }
  return out;
}

/** 去掉注释再扫，避免「注释里提到」被当成违规。 */
function stripComments(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/[^\n]*/g, '');
}

/**
 * 纯函数：给一组 {name, text} 判断哪些文件在「手写第二套身体空闲判据」。
 * @returns {Array<{file:string, why:string}>}
 */
function findViolations(files, allow) {
  const out = [];
  for (const f of files) {
    if (allow.includes(f.name) || DEFINITIONS.includes(f.name)) continue;
    const code = stripComments(f.text);
    const hasTask = code.includes('currentTaskFor(');
    const hasLlm = code.includes('isAwaitingLlmResponse()') || code.includes('isBusy()');
    if (hasTask && hasLlm) {
      out.push({ file: f.name, why: '同时用了「槽里有没有任务」与「是否在轮中/等模型」两个信号' });
    }
  }
  return out;
}

// ────────────────────────────── 自测 ──────────────────────────────
function selftest() {
  const cases = [
    {
      name: 'clean（只用一个信号）',
      files: [{ name: 'A.java', text: 'boolean x = CompanionTickDispatcher.currentTaskFor(id) != null;' }],
      allow: [],
      want: 0,
    },
    {
      name: 'violation（两个信号，未允许）',
      files: [{
        name: 'B.java',
        text: 'var t = CompanionTickDispatcher.currentTaskFor(id);\nreturn t == null && !loop.isAwaitingLlmResponse();',
      }],
      allow: [],
      want: 1,
    },
    {
      name: 'allowlisted（唯一实现处）',
      files: [{
        name: 'RddSafePointIssuer.java',
        text: 'return CompanionTickDispatcher.currentTaskFor(id) == null && !l.isAwaitingLlmResponse();',
      }],
      allow: ['RddSafePointIssuer.java'],
      want: 0,
    },
    {
      name: 'definition（定义处豁免）',
      files: [{
        name: 'EntityAgentLoop.java',
        text: 'public boolean isBusy() { return bus; }\nvoid f(){ CompanionTickDispatcher.currentTaskFor(id); }',
      }],
      allow: [],
      want: 0,
    },
    {
      name: 'comment-only（注释里提到不算）',
      files: [{
        name: 'C.java',
        text: '// 这里不能写 currentTaskFor(...) && isAwaitingLlmResponse()\n/* 同上 isBusy() */\nint a = 1;',
      }],
      allow: [],
      want: 0,
    },
  ];
  let pass = 0, fail = 0;
  for (const c of cases) {
    const got = findViolations(c.files, c.allow);
    const ok = got.length === c.want;
    console.log(`  ${ok ? '✔' : '✘'} ${c.name.padEnd(28)} 期望违规 ${c.want} 实得 ${got.length}`);
    ok ? pass++ : fail++;
  }
  // 端到端：真扫一次仓库（今天应该是 0 —— G3e-2 还没施工）
  if (fs.existsSync(opt.src)) {
    const files = scanRepo(opt.src).map((p) => ({
      name: path.basename(p),
      text: fs.readFileSync(p, 'utf8'),
    }));
    const got = findViolations(files, opt.allow);
    const ok = got.length === 0;
    console.log(`  ${ok ? '✔' : '✘'} e2e-scan                     扫 ${files.length} 个文件，违规 ${got.length}`);
    ok ? pass++ : fail++;
  } else {
    console.log('  -  e2e-scan                     跳过（源码目录不存在）');
  }
  console.log(`\n  selftest: ${pass} 过 / ${fail} 败`);
  process.exit(fail ? 1 : 0);
}

function scanRepo(src) {
  const out = [];
  for (const r of SCAN_ROOTS) walk(path.join(src, r), out);
  return out;
}

// ────────────────────────────── 主流程 ──────────────────────────────
if (opt.selftest) selftest();

if (!fs.existsSync(opt.src)) {
  console.error('[env] 源码目录不存在: ' + opt.src);
  process.exit(2);
}

const files = scanRepo(opt.src).map((p) => ({ name: path.basename(p), text: fs.readFileSync(p, 'utf8') }));
const bad = findViolations(files, opt.allow);

if (opt.json) {
  console.log(JSON.stringify({ scanned: files.length, allow: opt.allow, violations: bad }, null, 2));
  process.exit(bad.length ? 1 : 0);
}

console.log('');
console.log('════ H1 判据：「身体空闲」判断只许有一处（G3e-2）════');
console.log(`扫描 : ${files.length} 个宿主源文件（plugins/ + api/common/src/client/）`);
console.log(`允许 : ${opt.allow.join(', ') || '(无)'}`);
console.log('');
if (!bad.length) {
  console.log('VERDICT=OK  没有发现第二套「身体空闲」判据');
} else {
  console.log('VERDICT=VIOLATION  发现手写第二套判据：');
  for (const v of bad) console.log(`  · ${v.file}：${v.why}`);
  console.log('  → 改法：调 `RddSafePointIssuer.bodyIdle(uuid)`，别自己组合信号。');
}
console.log('');
process.exit(bad.length ? 1 : 0);
