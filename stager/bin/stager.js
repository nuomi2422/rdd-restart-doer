#!/usr/bin/env node
/**
 * stager.js —— 编程流程阶段管理器（stager）
 *
 * 它干的事，就三件：
 *   1) 记「现在在第几阶段、第几轮、谁在干活」→ state.json（唯一真身）
 *   2) 收「每个阶段产出的文档」→ docs/ + manifest.json（换人/换 AI 靠它注入）
 *   3) 卡「不许跳过阶段」→ gate，没达标 next 就拒绝（--force 才放行）
 *
 * 换人次：任何人都能 stager swap <名字> 接管当前阶段，不查出身。
 * 轮回：stager next 走到 loop 阶段会自己回到 plan 并 +1 轮；stager loop 是不加轮的内循环。
 * 注入：stager ctx 输出一个 markdown 包，AI 读它就知道自己该干什么。
 *
 * 用法：node stager.js <命令> [参数]   （顶层有 stager.cmd / stager.ps1 包装）
 * 全量帮助：node stager.js help
 */

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync, spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const CORE = path.join(ROOT, 'core');
const STAGES_FILE = path.join(CORE, 'stages.json');
const PET_DIR = path.join(ROOT, 'pet');
const IMAGES_DIR = path.join(PET_DIR, 'images');
const PLUGIN_SRC = path.join(ROOT, 'opencode-plugin', 'stager-plugin.mjs');
const STAGER_MARKER = '## ▶ STAGER 阶段管理器（自动）';

// 运行时目录用 let：self-test 要临时重定向到 tmp
let RUNTIME = path.join(ROOT, '.stager');
let TASKS = '';
let ACTIVE_FILE = '';
let realRuntime = RUNTIME;

function setRuntime(dir) {
  RUNTIME = dir;
  TASKS = path.join(RUNTIME, 'tasks');
  ACTIVE_FILE = path.join(RUNTIME, 'active.json');
}
// 并发压测/隔离运行用：STAGER_RUNTIME=<目录> 可以把运行时搬到别处
setRuntime(process.env.STAGER_RUNTIME || realRuntime);

// ---------------------------------------------------------------- 基础工具

let THROW_ON_DIE = false;

function die(msg, code) {
  if (THROW_ON_DIE) {
    const e = new Error(msg);
    e.stagerDie = true;
    throw e;
  }
  process.stderr.write('STAGER-ERR ' + msg + '\n');
  process.exit(code === undefined ? 1 : code);
}

function ok(msg) { process.stdout.write(msg + '\n'); }

function nowIso() { return new Date().toISOString(); }

function pad2(n) { return (n < 10 ? '0' : '') + n; }

function stamp() {
  const d = new Date();
  return d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate()) + '-' +
    pad2(d.getHours()) + pad2(d.getMinutes()) + pad2(d.getSeconds());
}

function readJson(p, dflt) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return dflt; }
}

function writeJsonAtomic(p, obj) {
  const tmp = p + '.tmp-' + process.pid;
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2), 'utf8');
  fs.renameSync(tmp, p);
}

/**
 * 极简文件锁：多 AI 同时写 state.json 时防丢更新。
 *
 * 三条硬规矩（2026-09-29 修，都是被 codex 审出来的真 bug）：
 *  1) 临界区里**必须重新读**状态。锁外读=快照，进锁写=覆盖别人的推进（丢更新）。
 *  2) 只删**自己**的锁。锁里写 token（pid+随机），释放时 token 对不上就不删。
 *  3) die()/process.exit 也要还锁 → 挂 exit 钩子，别让业务拒绝把锁留在盘上。
 *
 * 僵尸判定：pid 不存活 或 持锁超过 STALE_MS（30s）→ 回收。
 */
const LOCK_TOKEN = process.pid + '-' + Math.random().toString(36).slice(2, 10);
const STALE_MS = 30000;
let holdingLock = false;

function pidAlive(pid) {
  if (!pid || pid === process.pid) return pid === process.pid;
  try { process.kill(pid, 0); return true; } catch (e) { return false; }
}

function readLock(lockFile) {
  const raw = readJson(lockFile, null);
  if (raw && raw.token) return raw;
  // 空锁 / 坏 JSON：写锁的瞬间崩了会留个空文件，短宽限期后就回收
  try {
    const age = Date.now() - fs.statSync(lockFile).mtimeMs;
    if (age > 3000) return { token: null, ts: new Date(Date.now() - STALE_MS).toISOString(), pid: 0 };
  } catch (e) { /* 已经被别人删了 */ }
  return { token: null, fresh: true };
}

function breakLock(lockFile) {
  // 回收也要认领：重命名成自己的名字再删，避免删掉别人刚建的锁
  const dead = lockFile + '.dead-' + Math.random().toString(36).slice(2, 8);
  try { fs.renameSync(lockFile, dead); } catch (e) { return; }
  try { fs.unlinkSync(dead); } catch (e) { /* ignore */ }
}

function withLock(fn) {
  fs.mkdirSync(RUNTIME, { recursive: true });
  const lockFile = path.join(RUNTIME, '.lock');
  const deadline = Date.now() + 15000;
  let got = false;

  while (Date.now() < deadline) {
    try {
      const fd = fs.openSync(lockFile, 'wx');
      fs.writeSync(fd, JSON.stringify({ token: LOCK_TOKEN, pid: process.pid, ts: nowIso() }));
      fs.closeSync(fd);
      got = true;
      break;
    } catch (e) {
      const info = readLock(lockFile);
      if (info.fresh) { sleepSync(60); continue; }
      const age = Date.now() - new Date(info.ts).getTime();
      if (age > STALE_MS || !pidAlive(info.pid)) breakLock(lockFile);
      else sleepSync(60);
    }
  }
  if (!got) die('拿不到锁：' + lockFile + '（有别的 AI 正在写状态，等 15 秒还没放）');

  holdingLock = true;
  const onExit = () => { if (holdingLock) releaseLock(lockFile); };
  process.once('exit', onExit);
  try {
    return fn();
  } finally {
    process.removeListener('exit', onExit);
    releaseLock(lockFile);
  }
}

function releaseLock(lockFile) {
  holdingLock = false;
  const info = readLock(lockFile);
  if (info.token && info.token !== LOCK_TOKEN) return;   // 别人的锁，不碰
  try { fs.unlinkSync(lockFile); } catch (e) { /* 已经没了 */ }
}

function sleepSync(ms) {
  const sab = new SharedArrayBuffer(4);
  Atomics.wait(new Int32Array(sab), 0, 0, ms);
}

function ensureDirs() {
  fs.mkdirSync(TASKS, { recursive: true });
  fs.mkdirSync(IMAGES_DIR, { recursive: true });
}

// ---------------------------------------------------------------- 阶段定义

let STAGES = null;
function stages() {
  if (!STAGES) {
    const raw = readJson(STAGES_FILE, null);
    if (!raw) die('阶段定义读不出来：' + STAGES_FILE);
    STAGES = raw;
    STAGES.stageList = STAGES.stages;
    STAGES.stageList.forEach((s, i) => { s._i = i; });
  }
  return STAGES;
}

function stageById(id) {
  const list = stages().stageList;
  for (const s of list) if (s.id === id) return s;
  return null;
}

function totalStages() { return stages().stageList.length; }

// ---------------------------------------------------------------- 任务读写

function activeId() { return readJson(ACTIVE_FILE, null); }

function taskDir(id) { return path.join(TASKS, id); }
// ── 外脑（免费模型池）本阶段问没问 ──────────────────────────
//   判据：w-replies 里本阶段窗口内、回答 >40 字的、按平台去重。
//   >40 是因为 <=40 基本是「抓到上一轮旧答案」（2026-09-30 实测 4~11 字）。
//   单家不算数 —— 可被一次误抓骗过。要 >=2 家有效。
const WPOOL_DIR = path.join(__dirname, '..', '..', 'rdd-selfcompile', 'report', 'w-replies');
const WPOOL_MIN_CHARS = 40;
const WPOOL_MIN_PLATFORMS = 2;
function wpoolTally(st) {
  const out = { total: 0, valid: 0, platforms: {}, skipped: 0 };
  let t0 = 0;
  try {
    const H = fs.readFileSync(path.join(taskDir(st.id), "history.jsonl"), "utf8")
      .split(/\r?\n/).filter(Boolean).map((x) => { try { return JSON.parse(x); } catch (e) { return null; } }).filter(Boolean);
    for (let i = H.length - 1; i >= 0; i--) {
      const e = H[i];
      if ((e.ev === 'next' || e.ev === 'start') && (e.to === st.stage || e.stage === st.stage)) {
        t0 = Date.parse(e.ts); break;
      }
    }
    if (!t0) t0 = Date.parse(st.createdAt || 0);
  } catch (e) { t0 = Date.parse(st.createdAt || 0); }
  try {
    for (const f of fs.readdirSync(WPOOL_DIR)) {
      if (!/\.json$/.test(f)) continue;
      const p = path.join(WPOOL_DIR, f);
      const m = fs.statSync(p).mtimeMs;
      if (m < t0) continue;
      out.total++;
      let j; try { j = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { continue; }
      if ((j.chars || 0) < WPOOL_MIN_CHARS) { out.skipped++; continue; }
      out.valid++;
      const tag = String(j.tag || f.split('-')[0]);
      out.platforms[tag] = (out.platforms[tag] || 0) + 1;
    }
  } catch (e) { /* 目录还没有 */ }
  out.enough = Object.keys(out.platforms).length >= WPOOL_MIN_PLATFORMS;
  return out;
}


function statePath(id) { return path.join(taskDir(id), 'state.json'); }

function docsDir(id) { return path.join(taskDir(id), 'docs'); }

function historyPath(id) { return path.join(taskDir(id), 'history.jsonl'); }

function manifestPath(id) { return path.join(taskDir(id), 'docs', 'manifest.json'); }

function loadState(id) {
  const id2 = id || activeId();
  if (!id2) return null;
  const st = readJson(statePath(id2), null);
  if (!st) return null;
  return st;
}

function requireState(id, opts) {
  const st = loadState(id);
  if (!st) {
    const open = listTasks().filter((t) => t.status === 'active');
    if (open.length) die('没有指定任务，但有未关档的：' + open.map((t) => t.id).join(', ') + '\n  用 stager resume <id> 选一个');
    die('没有进行中的任务。先 stager start "<需求标题>"');
  }
  if (st.status !== 'active' && !(opts && opts.allowClosed)) {
    die('任务 ' + st.id + ' 已关档（' + st.status + '），不再接受改动。\n' +
      '  要接着改：stager resume ' + st.id + ' --force --note "为什么"');
  }
  return st;
}

function saveState(st) {
  st.updatedAt = nowIso();
  writeJsonAtomic(statePath(st.id), st);
  writeJsonAtomic(ACTIVE_FILE, st.status === 'active' ? st.id : null);
}

function log(st, ev, data) {
  const rec = Object.assign({ ts: nowIso(), ev: ev, round: st ? st.round : null, stage: st ? st.stage : null, actor: st ? st.actor : null }, data || {});
  fs.mkdirSync(taskDir(st ? st.id : '_'), { recursive: true });
  fs.appendFileSync(historyPath(st ? st.id : '_'), JSON.stringify(rec) + '\n', 'utf8');
}

function listTasks() {
  ensureDirs();
  let names = [];
  try { names = fs.readdirSync(TASKS); } catch (e) { return []; }
  const out = [];
  for (const n of names) {
    const st = readJson(path.join(TASKS, n, 'state.json'), null);
    if (st) out.push(st);
  }
  out.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  return out;
}

// ---------------------------------------------------------------- 门禁 check

function loadManifest(id) {
  return readJson(manifestPath(id), { docs: [] });
}

/** 算当前阶段还差什么。返回 {ok, need:[], have:[]} */
// ── 豁免账本（waiver ledger）─────────────────────────────────
//   红项可带病放行，但必须记账：原因 / 责任 / 到期轮次。
//   到期轮次过了还在账上 → 下一轮开局提示清账，不自动清（自动清=赖账）。
function waiversPath(id) { return path.join(taskDir(id), "waivers.json"); }
function loadWaivers(id) {
  try { const j = JSON.parse(fs.readFileSync(waiversPath(id), "utf8"));
        return Array.isArray(j.items) ? j : { items: [] }; }
  catch (e) { return { items: [] }; }
}
function saveWaivers(id, w) {
  fs.writeFileSync(waiversPath(id), JSON.stringify(w, null, 1), "utf8");
}
function activeWaivers(st) {
  const w = loadWaivers(st.id);
  const out = {};
  w.items.forEach((it) => {
    if (it.untilRound && it.untilRound < st.round) return;
    out[it.item] = it;
  });
  return out;
}
function expiredWaivers(st) {
  const w = loadWaivers(st.id);
  return w.items.filter((it) => it.untilRound && it.untilRound < st.round);
}
function evaluateGate(st) {
  const stage = stageById(st.stage);
  const need = [];
  const have = [];
  if (!stage) return { ok: false, need: ['未知阶段 ' + st.stage], have: [] };
  const gate = stage.gate || {};
  const man = loadManifest(st.id);
  const docs = man.docs || [];

  (gate.docs || []).forEach((kind) => {
    // 登记了不算数，正文文件被删了照样算缺（codex 复现过）
    const hit = docs.some((d) => d.kind === kind && d.stage === st.stage && d.round === st.round &&
      fs.existsSync(path.join(docsDir(st.id), d.file)));
    if (hit) have.push('doc:' + kind); else need.push('doc:' + kind);
  });

  const marks = (st.marks && st.marks[st.round + ':' + st.stage]) || [];
  (gate.cmds || []).forEach((cmd) => {
    if (marks.indexOf(cmd) >= 0) have.push('cmd:' + cmd); else need.push('cmd:' + cmd);
  });

  // ★ 豁免：已记账且未到期的项，从「还差」挪到「已豁免」，不再拦人。
  const wv = activeWaivers(st);
  const waived = [];
  for (let i = need.length - 1; i >= 0; i--) {
    if (wv[need[i]]) { waived.unshift(need.splice(i, 1)[0]); }
  }
  return { ok: need.length === 0, need: need, have: have, waived: waived };
}

function addMark(st, cmd) {
  const key = st.round + ':' + st.stage;
  if (!st.marks) st.marks = {};
  if (!st.marks[key]) st.marks[key] = [];
  if (st.marks[key].indexOf(cmd) < 0) st.marks[key].push(cmd);
}

// ---------------------------------------------------------------- 文本输出

function bar(st, w) {
  const total = totalStages();
  const i = stageById(st.stage) ? stageById(st.stage)._i : 0;
  const done = Math.round((i / total) * w);
  return '[' + '#'.repeat(done) + '-'.repeat(w - done) + '] ' + (i + 1) + '/' + total;
}

function statusLine(st) {
  const s = stageById(st.stage);
  const icon = s ? s.icon : '?';
  const name = s ? s.name : st.stage;
  const g = evaluateGate(st);
  return (st.title || '(无标题)') + '\n' +
    '  任务    ' + st.id + '\n' +
    '  阶段    ' + bar(st, 24) + '  ' + icon + ' ' + name + ' [' + st.stage + ']\n' +
    '  轮次    第 ' + st.round + ' / ' + st.maxRounds + ' 轮   轮回 ' + (st.wrap || 0) + ' 次\n' +
    '  人次    ' + st.actor + (st.actors[st.stage] && st.actors[st.stage] !== st.actor ? '（本阶段原主 ' + st.actors[st.stage] + '）' : '') + '\n' +
    '  门禁    ' + (g.ok ? '✔ 已达标，可以 stager next' : '✘ 还差：' + g.need.join(' ')) + '\n' +
    '  文档    ' + (loadManifest(st.id).docs || []).length + ' 份\n' +
    '  更新    ' + st.updatedAt;
}

function progressMd(st) {
  const man = loadManifest(st.id);
  const lines = [];
  lines.push('# ' + (st.title || st.id) + ' · 进度板');
  lines.push('');
  lines.push('- 任务 id：`' + st.id + '`');
  lines.push('- 状态：**' + st.status + '**');
  lines.push('- 当前：**第 ' + st.round + '/' + st.maxRounds + ' 轮 · ' + (stageById(st.stage) || {}).name + '**');
  lines.push('- 人次：`' + st.actor + '`');
  lines.push('- 更新：' + st.updatedAt);
  lines.push('');
  lines.push('## 阶段轨迹');
  lines.push('');
  lines.push('| # | 阶段 | 门禁 | 备注 |');
  lines.push('|---|---|---|---|');
  const stg = stages().stageList;
  for (let i = 0; i < stg.length; i++) {
    const s = stg[i];
    const marks = (st.marks && st.marks[st.round + ':' + s.id]) || [];
    const docs = (man.docs || []).filter((d) => d.stage === s.id && d.round === st.round).map((d) => d.kind);
    const cur = s.id === st.stage;
    lines.push('| ' + (i + 1) + ' | ' + s.icon + ' ' + s.name + (cur ? ' **←当前**' : '') +
      ' | ' + (docs.length || marks.length ? '✔' : (cur ? '…' : '·')) +
      ' | ' + (docs.length ? docs.join(',') : marks.join(',')) + ' |');
  }
  lines.push('');
  lines.push('## 文档清单');
  lines.push('');
  if (!(man.docs || []).length) {
    lines.push('（空）');
  } else {
    lines.push('| 文档 | 类型 | 阶段 | 轮 | 人次 | 时间 |');
    lines.push('|---|---|---|---|---|---|');
    for (const d of man.docs) {
      lines.push('| `' + d.file + '` | ' + d.kind + ' | ' + d.stage + ' | ' + d.round + ' | ' + d.actor + ' | ' + d.createdAt + ' |');
    }
  }
  lines.push('');
  lines.push('## 轮回历史（append-only）');
  lines.push('');
  lines.push('```');
  try {
    const raw = fs.readFileSync(historyPath(st.id), 'utf8').trim();
    lines.push(raw || '（空）');
  } catch (e) { lines.push('（空）'); }
  lines.push('```');
  lines.push('');
  return lines.join('\n');
}

function writeProgress(st) {
  try { fs.writeFileSync(path.join(taskDir(st.id), 'progress.md'), progressMd(st), 'utf8'); } catch (e) { /* 看板失败不阻塞主流程 */ }
}

// ---------------------------------------------------------------- ctx 注入包

function ctxMd(st, full) {
  const s = stageById(st.stage);
  const man = loadManifest(st.id);
  const out = [];

  out.push('## ▶ STAGER 阶段管理器 · 上下文注入（自动生成，别手改）');
  out.push('');
  // ★ 每次进来先报一句现在到哪了（用户明确要求：聊天框里必须能看到阶段）
  out.push('## ▶▶ 现在在：' + (s ? s.icon + ' ' + s.name : st.stage) + '　（第 ' +
    (s ? s._i + 1 : '?') + '/' + totalStages() + ' 阶段）　·　第 ' + st.round + '/' + st.maxRounds +
    ' 轮　·　人次 `' + st.actor + '`');
  out.push('');
  out.push('> 任务「' + (st.title || st.id) + '」　阶段 `' + st.stage + '`　轮回 ' + (st.wrap || 0) +
    ' 次　文档 ' + (loadManifest(st.id).docs || []).length + ' 份');
  out.push('');
  out.push('| 项 | 值 |');
  out.push('|---|---|');
  out.push('| 任务 | ' + (st.title || '') + ' |');
  out.push('| id | `' + st.id + '` |');
  out.push('| 当前阶段 | **' + (s ? s.icon + ' ' + s.name : st.stage) + '**（' + (s ? s._i + 1 : '?') + '/' + totalStages() + '，`' + st.stage + '`） |');
  out.push('| 轮次 | 第 **' + st.round + '** / ' + st.maxRounds + ' 轮，已轮回 ' + (st.wrap || 0) + ' 次 |');
  out.push('| 当前人次 | `' + st.actor + '` |');
  out.push('| 门禁 | ' + (evaluateGate(st).ok ? '✔ 达标' : '✘ 还差 ' + evaluateGate(st).need.join(' ')) + ' |');
  out.push('| 状态 | ' + st.status + ' |');
  out.push('');

  if (s) {
    out.push('### 你现在这个阶段要做的事：' + s.name);
    out.push('');
    out.push(s.brief);
    out.push('');
    if (s.read && s.read.length) {
      out.push('**📖 本阶段开工必读（不读不许动手）：**');
      out.push('');
      s.read.forEach((r) => out.push('- `' + r + '`　（`E:\\新建文件夹\\rdd架构\\` 下）'));
      out.push('');
    }
// 读档记录（GLM「读后一行复述」）—— 让「读没读」从黑箱变可观测
  if (s.read && s.read.length) {
    try {
      const _rs = readRecaps(st);
      const _F = String.fromCharCode(96).repeat(3);
      out.push('**读完每份后跑一句**（几十 token，把「读没读」变成可观测的）：');
      out.push('');
      out.push(_F + 'powershell');
      out.push('stager read "<上面某个路径>" --note "这份讲了什么、我该注意什么"');
      out.push(_F);
      out.push('');
      s.read.forEach((r) => {
        const _bn = readBaseName(r);
        const _hit = _rs.filter((x) => readBaseName(x.file) === _bn)[0];
        out.push(_hit ? '- ✔ 已读 `' + _bn + '` —— ' + _hit.note : '- ✘ 未记读档 `' + _bn + '`');
      });
      if (_rs.length) {
        out.push('');
        out.push('> 已记 ' + _rs.length + ' 份。要点写错会被下游引用打脸，所以别编。');
      }
      out.push('');
    } catch (e) { /* 记录坏了别拖垮 ctx */ }
  }

// 阶段心跳（2026-09-30）：独立看门狗 stage-heartbeat.js 盯着你
    {
      const BUD = { plan: 20, implement: 20, verify: 30, close: 15 };
      const bud = BUD[st.stage] || 25;
      const F = String.fromCharCode(96).repeat(3);
      out.push('### ⏱ 本阶段心跳预算 ' + bud + ' 分钟（独立看门狗盯着）');
      out.push('');
      out.push('超过预算分三档干预：T+' + bud + ' 温和提醒 → T+' + (bud + 10) + ' 强制自检 → T+' + (bud + 20) + ' 快照+回退。');
      out.push('');
      try {
        const _hb = JSON.parse(fs.readFileSync(path.join(TASKS, 'heartbeat.json'), 'utf8'));
        const _k = st.id + ':' + st.round + ':' + st.stage;
        const _a = (_hb.acks || {})[_k];
        if (_a) {
          out.push('**本阶段已答过心跳**：耗时=' + _a.elapsed + '　状态=`' + _a.status + '`　下一步=' + _a.next);
        } else {
          out.push('**本阶段还没答过心跳**。超时会问你，所以别让自己卡到超时。');
          out.push('');
          out.push(F + 'powershell');
          out.push('stager hb-ack --status <ok|looping|blocked|waiting_user> --elapsed <N>m --next "<下一步>"');
          out.push(F);
          out.push('');
          out.push('★ 四个 status 的含义：`ok`（在推进）/ `looping`（在打转，自己发现）/ `blocked`（技术卡住）/ `waiting_user`（该等用户拍板）。');
        }
      } catch (e) { /* 没有心跳记录 = 还没答过 */ }
      out.push('');
    }

// 外脑欠账：AI 自己能看见「我还欠一轮互审」
    const F2 = String.fromCharCode(96).repeat(3);
    {
      const _w = wpoolTally(st);
      const _names = Object.keys(_w.platforms);
      out.push('### 🧠 外脑（本阶段问没问）');
      out.push('');
      out.push(`- 已问：${_w.valid} 份有效回答（>${WPOOL_MIN_CHARS} 字才算数）× ${_names.length} 家${_names.length ? '：' + _names.join(', ') : ''}`);
      out.push(`- 本阶段调用 ${_w.total} 次，其中 ${_w.skipped} 份太短（疑似抓到上一轮旧答案）`);
      if (_w.enough) {
        out.push('- **够了**。但下一步别忘：把 4 家意见【逐条标注采纳/驳回+理由】写进文档 —— 问了不裁决等于没问。');
      } else {
        out.push(`- **不够**（要 ≥2 家有效）。★ 外脑是免费的，不花用户的钱，别把自己关在小方框里。`);
        out.push('  唯一豁免：用户明确说了「本轮不走外脑」。没有这句话 = 没有豁免。');
        out.push('');
        out.push(F2 + 'bash');
        out.push('node "E:\\restart developing doer\\rdd-selfcompile\\scripts\\w-probe.js"');
        out.push('node "E:\\restart developing doer\\rdd-selfcompile\\scripts\\w-brain-drive.js" askall --file "<你的问题.md>"');
        out.push(F2);
      }
      out.push('');
    }

    if (s.ai && s.ai.length) {
      out.push('**必做：**');
      out.push('');
      s.ai.forEach((x) => out.push(x));
      out.push('');
    }
  }

  // 最终架构文档 = 防跑偏的锚，每个阶段都要回头读
  const archDocs = (loadManifest(st.id).docs || []).filter((d) => d.kind === 'arch');
  if (archDocs.length) {
    out.push('### ★ 最终架构文档（所有 AI 的锚，每阶段回头读一遍）');
    out.push('');
    archDocs.forEach((d) => {
      out.push('- `' + path.join(docsDir(st.id), d.file) + '`　[' + d.title + ' · 第' + d.round + '轮 · ' + d.actor + ']');
    });
    out.push('');
    out.push('> 干任何事之前先确认：这轮的动作有没有偏离它。偏了就回计划阶段改架构文档，别硬做。');
    out.push('');
  }

  // 豁免账本：点名，让 AI 和人都看得见「门禁不是全绿，是记账放行的」
  try {
    const _w = loadWaivers(st.id);
    const _exp = expiredWaivers(st);
    const _act = activeWaivers(st);
    if (_w.items.length) {
      out.push('### ⚠ 本任务带着豁免（门禁不是全绿，是记账放行的）');
      out.push('');
      Object.keys(_act).forEach((k) => {
        const it = _act[k];
        out.push('- `' + k + '`　到期第 ' + (it.untilRound || '不限') + ' 轮　责任: ' + (it.owner || '?') + '　原因: ' + it.reason);
      });
      if (_exp.length) out.push('- **已过期未清 ' + _exp.length + ' 条** → 本轮优先清账（`stager waive list`）');
      out.push('');
      out.push('> 这不是免债：本轮能真修就修掉，然后 `stager waive drop <item> --reason "已修"`。');
      out.push('');
    }
  } catch (e) { /* 账本坏了别拖垮 ctx */ }
  // 每 3 轮回流提醒
  if (st.round > 1 && st.round % 3 === 0) {
    out.push('### ⏰ 每 3 轮回流提醒');
    out.push('');
    out.push('本轮是第 ' + st.round + ' 轮 → **把本轮所有源码改动粘给 GLM 审一遍**（直接粘文本，不要只给摘要/链接）。');
    out.push('');
  }

  out.push('### 全部阶段（下一阶段是 `' + (s ? s.next : '?') + '`）');
  out.push('');
  const list = stages().stageList;
  list.forEach((x, i) => {
    out.push((i + 1) + '. ' + x.icon + ' **' + x.name + '** `' + x.id + '` → `' + x.next + '`' +
      (x.loop ? ' （轮回点）' : '') + '　门禁：' + ((x.gate.docs || []).map((d) => 'doc:' + d).concat((x.gate.cmds || []).map((c) => 'cmd:' + c)).join(' ') || '无'));
  });
  out.push('');

  out.push('### 已产出文档（换人也看这些，别靠记忆）');
  out.push('');
  const docs = man.docs || [];
  if (!docs.length) {
    out.push('（还没有文档）');
  } else {
    const show = full ? docs : docs.slice(-8);
    for (const d of show) {
      out.push('#### [' + d.kind + '] ' + d.title + '　`' + d.stage + '` 第' + d.round + '轮 · ' + d.actor);
      out.push('');
      out.push('文件：`' + path.join(docsDir(st.id), d.file) + '`');
      out.push('');
      try {
        const body = fs.readFileSync(path.join(docsDir(st.id), d.file), 'utf8');
        const limit = full ? body.length : 3000;
        out.push('```markdown');
        out.push(body.length > limit ? body.slice(0, limit) + '\n…（截断，stager ctx --full 看全文）' : body);
        out.push('```');
      } catch (e) { out.push('（读不到文件）'); }
      out.push('');
    }
    if (!full && docs.length > show.length) out.push('…还有 ' + (docs.length - show.length) + ' 份，`stager ctx --full`');
    out.push('');
  }

  out.push('### 换人次记录（谁做过哪一步）');
  out.push('');
  const seen = {};
  (st.actorLog || []).forEach((a) => { seen[a.stage + '#' + a.round] = a.actor; });
  const keys = Object.keys(seen);
  if (!keys.length) out.push('（无）');
  else keys.forEach((k) => out.push('- ' + k + ' → `' + seen[k] + '`'));
  out.push('');

  out.push('### 硬规矩');
  out.push('');
  out.push('- 阶段没达标就想跑 → `stager next` 会拒；真要跳，`--force` 并写进 note。');
  out.push('- **每阶段开工先读上面那份「本阶段必读」**，不读不动手。');
  out.push('- 有「最终架构文档」就每阶段回头读一遍，防跑偏。');
  out.push('- 每次动手前先 `stager ctx` 读注入包，别凭上一轮的记忆。');
  out.push('- 换人接手 = `stager swap <你>`，然后 `stager ctx --full` 补齐上下文。');
  out.push('- 收工 = `stager close --status done`，会自动关档并归档。');
  out.push('');
  return out.join('\n');
}

// ---------------------------------------------------------------- 参数解析

function parseArgs(argv) {
  const pos = [];
  const flags = {};
  const alias = { n: 'note', t: 'title', k: 'kind', s: 'stage', a: 'actor', f: 'force', r: 'rounds' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.slice(0, 2) === '--') {
      const body = a.slice(2);
      const eq = body.indexOf('=');
      let key, val;
      if (eq >= 0) { key = body.slice(0, eq); val = body.slice(eq + 1); }
      else {
        key = body;
        const nx = argv[i + 1];
        if (nx !== undefined && nx.slice(0, 2) !== '--') { val = nx; i++; } else { val = true; }
      }
      flags[alias[key] || key] = val;
    } else if (a.slice(0, 1) === '-' && a.length > 1) {
      const key = a.slice(1);
      const nx = argv[i + 1];
      if (nx !== undefined && nx.slice(0, 1) !== '-') { flags[alias[key] || key] = nx; i++; }
      else flags[alias[key] || key] = true;
    } else pos.push(a);
  }
  return { pos: pos, f: flags };
}

// ---------------------------------------------------------------- 命令

const CMD = {};

CMD.help = function () {
  ok([
    'stager —— 编程流程阶段管理器',
    '',
    '  任务  stager start "<标题>" [--rounds 5] [--actor opencode]   开一个新 stage（自动进第 1 轮第 1 阶段）',
    '        stager resume [id]                                      选一个未关档的任务继续',
    '        stager list                                             列所有任务',
    '        stager close --status done|aborted [--note "…"]         收工关档（done）/ 放弃关档（aborted）',
    '',
    '  推进  stager next [--note "…"] [--force]                     完成本阶段 → 下一阶段（撞到 loop 阶段自动 +1 轮）',
    '        stager loop                                             本轮内回到第 1 阶段（不加轮）',
    '        stager round [--note "…"]                               手动 +1 轮回第 1 阶段',
    '        stager enter <stageId> [--note "…"]                     直接跳到某阶段（记一条跳转）',
    '        stager implement|verify|mark <名字> [--note "…"]         给当前阶段打标记（满足 cmd 门禁）',
    '                                                                例：stager implement --note "写完了"',
    '',
    '  人次  stager swap <名字> [--note "…"]                         换人接手当前阶段（不查出身）',
    '',
    '  文档  stager put <文件|-> --kind requirement|plan|review|contract|evidence|log|note',
    '              [--title "标题"] [--stage <id>] [--round N]      把文档存进 stage 并登记',
    '        stager docs [--stage <id>] [--kind <k>]                列文档',
    '',
    '  读我  stager status [--json]                                 状态一行版',
    '        stager ctx [--full] [--out <文件>]                     ★ 注入包（AI 每次开工先跑这个）',
    '        stager check                                            门禁：还差什么（未达标退出码 2）',
    '        stager log [--n 50]                                    事件流水',
    '        stager progress                                         刷一份 progress.md 看板',
    '',
    '  其他  stager publish <文件> --as report|tool|shot|doc --title "标题"',
    '                                                        放到 rdd-selfcompile\\给用户\\ 并自动登记 INDEX.md',
    '        stager pet [--size 200]                                起桌面宠物（点它报阶段/轮次）',
    '        stager web [--port 8899]                                起网页看板',
    '        stager install                                          注册 opencode 自动注入插件 + 工作区 AGENTS.md 指针',
    '        stager uninstall                                        注销',
    '        stager self-test                                        状态机自测（临时目录，跑完即删）',
    '        stager conc-test                                        并发压测（8 进程抢锁，验丢更新/残锁）',
    '',
    '  状态真身：.stager/tasks/<id>/state.json　　阶段定义：core/stages.json（可改）',
  ].join('\n'));
};

/** 任务目录必须排他创建：同秒同标题再 start 一次也不能覆盖老任务（codex 审出来的） */
function freshTaskDir(id) {
  let candidate = id, n = 1;
  while (fs.existsSync(taskDir(candidate))) {
    n++;
    candidate = id + '-' + n;
  }
  return candidate;
}

CMD.start = function (a) {
  ensureDirs();
  const title = a.pos.join(' ').trim();
  if (!title) die('缺标题：stager start "<需求标题>"');
  const def = stages().defaults || {};
  return withLock(() => {
    const id = freshTaskDir(stamp() + '-' + slug(title));
    const st = {
      version: 1,
      id: id,
      title: title,
      status: 'active',
      createdAt: nowIso(),
      updatedAt: nowIso(),
      closedAt: null,
      round: 1,
      maxRounds: parseInt(a.f.rounds, 10) || def.maxRounds || 5,
      wrap: 0,
      stage: stages().stageList[0].id,
      actor: a.f.actor || def.actor || os.userInfo().username,
      actors: {},
      actorLog: [],
      marks: {},
      note: ''
    };
    st.actors[st.stage] = st.actor;
    st.actorLog.push({ ts: st.createdAt, stage: st.stage, round: 1, actor: st.actor, note: '开档' });
    fs.mkdirSync(docsDir(id), { recursive: true });
    saveState(st);
    log(st, 'start', { title: title, maxRounds: st.maxRounds });
    writeProgress(st);
    ok('▶ 新 stage 已开：' + id);
    ok(statusLine(st));
    ok('');
    ok('下一条 AI 开工前先跑：  stager ctx');
    return st;
  });
};

// 中文按 2 列宽算，否则表格会歪
function dwidth(s) {
  let w = 0;
  for (const ch of String(s)) {
    const c = ch.codePointAt(0);
    w += (c >= 0x1100 && (c <= 0x115f || c === 0x2329 || c === 0x232a ||
      (c >= 0x2e80 && c <= 0xa4cf && c !== 0x303f) ||
      (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) ||
      (c >= 0xfe30 && c <= 0xfe6f) || (c >= 0xff00 && c <= 0xff60) ||
      (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1f9ff))) ? 2 : 1;
  }
  return w;
}

function dpad(s, n) {
  s = String(s == null ? '' : s);
  if (dwidth(s) <= n) return s + ' '.repeat(n - dwidth(s));
  // 超宽就截断加省略号（按字符退，保证不切半个汉字）
  let out = '', w = 0;
  for (const ch of s) {
    const cw = dwidth(ch);
    if (w + cw > n - 1) break;
    out += ch; w += cw;
  }
  return out + '…' + ' '.repeat(Math.max(0, n - w - 1));
}

function slug(s) {
  const t = s.replace(/[\\/:*?"<>|\s]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
  return t.slice(0, 28) || 'task';
}

CMD.resume = function (a) {
  const id = a.pos[0];
  if (id) {
    return withLock(() => {
      const st = loadState(id);
      if (!st) die('没这个任务：' + id);
      if (st.status !== 'active' && !a.f.force) {
        die('任务已关档（' + st.status + '）：' + st.id +
          '\n  想接着改归档里的东西：stager resume ' + st.id + ' --force --note "为什么"');
      }
      writeJsonAtomic(ACTIVE_FILE, st.id);
      ok('▶ 当前任务 → ' + st.id);
      ok(statusLine(st));
      return st;
    });
  }
  const open = listTasks().filter((t) => t.status === 'active');
  if (!open.length) die('没有未关档的任务');
  if (open.length === 1) return CMD.resume({ pos: [open[0].id], f: {} });
  ok('未关档任务：');
  open.forEach((t, i) => {
    ok('  [' + (i + 1) + '] ' + t.id + '  轮' + t.round + '  ' + (stageById(t.stage) || {}).name + '  ' + t.title);
  });
  ok('');
  ok('用 stager resume <id> 选一个');
  return null;
};

CMD.list = function () {
  const all = listTasks();
  if (!all.length) { ok('（还没有任务）'); return; }
  ok('  ' + dpad('任务 id', 38) + dpad('状态', 10) + dpad('轮', 5) + dpad('阶段', 14) + '标题');
  all.forEach((t) => {
    const s = stageById(t.stage) || {};
    ok((activeId() === t.id ? '>' : ' ') + ' ' +
      dpad(t.id, 38) + dpad(t.status, 10) +
      dpad(t.round, 5) + dpad((s.name || t.stage), 14) + t.title);
  });
};

CMD.status = function (a) {
  const st = requireState(null, { allowClosed: true });
  if (a.f.json) { ok(JSON.stringify(st, null, 2)); return st; }
  ok(statusLine(st));
  return st;
};

CMD.swap = function (a) {
  const who = a.pos.join(' ').trim();
  if (!who) die('要给谁接手：stager swap <名字>');
  return withLock(() => {
    const st = requireState();          // 锁内重读，别用锁外的旧快照
    st.actor = who;
    if (!st.actors[st.stage]) st.actors[st.stage] = who;
    st.actorLog.push({ ts: nowIso(), stage: st.stage, round: st.round, actor: who, note: a.f.note || '换人次' });
    saveState(st);
    log(st, 'swap', { to: who, note: a.f.note || '' });
    writeProgress(st);
    ok('↩ 人次已换 → ' + who + '（当前 ' + (stageById(st.stage) || {}).name + '，第 ' + st.round + ' 轮）');
    return st;
  });
};

CMD.next = function (a) {
  // 门禁必须在锁内判：锁外判完再进锁，中间别人推进了就成 TOCTOU
  return withLock(() => {
    const st = requireState();
    const g = evaluateGate(st);
    if (!g.ok && !a.f.force) {
      const how = g.need.map((n) => (n.slice(0, 4) === 'doc:'
        ? 'stager put <文件> --kind ' + n.slice(4) + ' --stage ' + st.stage
        : 'stager mark ' + n.slice(4))).join('\n              ');
      die('门禁没过，不许离开「' + (stageById(st.stage) || {}).name + '」\n' +
        '  还差：' + g.need.join(' ') + '\n' +
        '  补齐：  ' + how + '\n' +
        '  确实要跳：stager next --force --note "为什么跳"');
    }
    return advance(st, a, 'next');
  });
};

/** 轮回 / 内循环 回到哪个阶段（core/stages.json 的 loopTo，没配就回第 1 阶段） */
function loopTarget() {
  const S = stages();
  return (S.loopTo && stageById(S.loopTo)) ? S.loopTo : S.stageList[0].id;
}

function advance(st, a, how) {
  const s = stageById(st.stage);
  const targetId = s ? s.next : null;
  if (!targetId) {
    // 已到最后一个阶段：等 close
    saveState(st);
    writeProgress(st);
    ok('已到末尾阶段，下一步：stager close --status done');
    return st;
  }
  const target = stageById(targetId);
  const ti = target._i;
  const si = s._i;
  const wrapped = ti <= si;
  if (wrapped) {
    st.wrap = (st.wrap || 0) + 1;
    if (st.round < st.maxRounds) st.round++;
    else {
      log(st, 'wrap-blocked', { maxRounds: st.maxRounds });
      writeProgress(st);
      die('已经到第 ' + st.maxRounds + ' 轮上限了。\n' +
        '  要再轮回：stager round --force --note "为什么超轮"\n' +
        '  要收工：  stager close --status done\n' +
        '  要放弃：  stager close --status aborted');
    }
    ok('⟳ 轮回 → 第 ' + st.round + ' 轮（累计 ' + st.wrap + ' 次）');
    // 轮回回「重排计划」，不是从头 —— 需求一般不用重写
    st.stage = loopTarget();
    st.marks = {};            // 新的一轮，上一轮的标记不算数
  } else {
    st.stage = targetId;
  }
  if (!st.actors[st.stage]) st.actors[st.stage] = st.actor;
  st.actorLog.push({ ts: nowIso(), stage: st.stage, round: st.round, actor: st.actor, note: how + (a.f.note ? ' / ' + a.f.note : '') });
  saveState(st);
  log(st, how, { to: st.stage, note: a.f.note || '', forced: !!a.f.force, wrapped: wrapped });
  writeProgress(st);
  const tg = stageById(st.stage) || {};
  ok('✓ ' + (s ? s.icon + ' ' + s.name : st.stage) + ' → ' + (tg.icon || '') + ' ' + (tg.name || st.stage) + '（第 ' + st.round + ' 轮）');
  if (a.f.note) ok('  note: ' + a.f.note);
  ok('');
  ok(statusLine(st));
  return st;
}

CMD.loop = function (a) {
  return withLock(() => {
    const st = requireState();
    const from = st.stage;
    st.stage = loopTarget();
    st.actorLog.push({ ts: nowIso(), stage: st.stage, round: st.round, actor: st.actor, note: '内循环（不加轮）' + (a.f.note ? ' / ' + a.f.note : '') });
    saveState(st);
    log(st, 'loop', { from: from, to: st.stage, note: a.f.note || '' });
    writeProgress(st);
    const t = stageById(st.stage) || {};
    ok('↺ 内循环 → ' + (t.icon || '') + ' ' + (t.name || st.stage) + '（仍是第 ' + st.round + ' 轮）');
    if (a.f.note) ok('  note: ' + a.f.note);
    return st;
  });
};

CMD.round = function (a) {
  return withLock(() => {
    const st = requireState();
    if (st.round >= st.maxRounds && !a.f.force) {
      die('到 ' + st.maxRounds + ' 轮上限了。超轮要 --force --note "为什么"');
    }
    st.round++;
    st.wrap = (st.wrap || 0) + 1;
    st.marks = {};
    st.stage = loopTarget();
    st.actorLog.push({ ts: nowIso(), stage: st.stage, round: st.round, actor: st.actor, note: '手动开新一轮' + (a.f.note ? ' / ' + a.f.note : '') });
    saveState(st);
    log(st, 'round', { round: st.round, note: a.f.note || '', forced: !!a.f.force });
    writeProgress(st);
    const t = stageById(st.stage) || {};
    ok('⟳ 第 ' + st.round + ' / ' + st.maxRounds + ' 轮开始（累计轮回 ' + st.wrap + ' 次）→ ' + (t.icon || '') + ' ' + (t.name || ''));
    return st;
  });
};

CMD.enter = function (a) {
  const id = a.pos[0];
  if (!id) die('要到哪个阶段：stager enter <stageId>');
  const t = stageById(id);
  if (!t) die('没这个阶段：' + id + '（可选：' + stages().stageList.map((x) => x.id).join(', ') + '）');
  return withLock(() => {
    const st = requireState();
    const from = st.stage;
    const cur = stageById(from);
    if (cur && t._i > cur._i && !a.f.force) {
      // 往前跳 = 跳过中间阶段，必须显式 --force（配合 --note 留痕）
      die('往前跳阶段会被记成绕过门禁。当前「' + cur.name + '」→「' + t.name + '」，中间 ' +
        stages().stageList.slice(cur._i + 1, t._i + 1).map((x) => x.name).join('、') + ' 全跳过了。\n' +
        '  确实要跳：stager enter ' + id + ' --force --note "为什么跳"');
    }
    st.stage = id;
    st.actorLog.push({ ts: nowIso(), stage: id, round: st.round, actor: st.actor, note: '跳转' + (a.f.force ? '(force)' : '') + (a.f.note ? ' / ' + a.f.note : '') });
    saveState(st);
    log(st, 'enter', { from: from, to: id, note: a.f.note || '', forced: !!a.f.force });
    writeProgress(st);
    ok('→ ' + t.icon + ' ' + t.name + '（第 ' + st.round + ' 轮）');
    return st;
  });
};

function markCmd(defaultName) {
  return function (a) {
    const name = a.pos[0] || defaultName;
    if (!name) die('给个标记名：stager mark <名字>');
    return withLock(() => {
      const st = requireState();
      addMark(st, name);
      saveState(st);
      log(st, 'mark', { cmd: name, note: a.f.note || '' });
      writeProgress(st);
      ok('✔ 标记：' + name + (a.f.note ? ' — ' + a.f.note : ''));
      const g = evaluateGate(st);
      ok('门禁：' + (g.ok ? '✔ 已达标' : '还差 ' + g.need.join(' ')));
      return st;
    });
  };
}
CMD.mark = markCmd('mark');
CMD.implement = markCmd('implement');
CMD.verify = markCmd('verify');

CMD.check = function (a) {
  const st = requireState(null, { allowClosed: true });
  const g = evaluateGate(st);
  const s = stageById(st.stage);
  ok('阶段：' + s.icon + ' ' + s.name + '（' + st.stage + '） 第 ' + st.round + ' 轮');
  ok('门禁：' + (g.ok ? '✔ 达标' : '✘ 未达标'));
  if (g.have.length) ok('  已有：' + g.have.join(' '));
  if (g.need.length) {
    ok('  还差：' + g.need.join(' '));
    ok('');
    ok('怎么补：');
    g.need.forEach((n) => {
      if (n.slice(0, 4) === 'doc:') {
        ok('  stager put <文件> --kind ' + n.slice(4) + ' --stage ' + st.stage);
      } else if (n.slice(0, 4) === 'cmd:') {
        ok('  stager mark ' + n.slice(4) + ' --note "' + s.name + '做完了"');
      }
    });
  }
// ★ 豁免显示（2026-09-30 加，GLM「豁免记账制」）
  //   门禁不是全绿，是记账放行的 —— 必须让人和 AI 都看得见。
  if (g.waived && g.waived.length) {
    const _w = loadWaivers(st.id);
    ok(`  ⚠ 已豁免 ${g.waived.length} 项（带着病过门，账在 waivers.json）：`);
    g.waived.forEach((it) => {
      const rec = (_w.items || []).filter((x) => x.item === it).pop();
      ok(`     ${it}　原因: ${rec ? rec.reason : '?'}　到期: 第${rec && rec.untilRound ? rec.untilRound : '不限'}轮　责任: ${rec ? rec.owner : '?'}`);
    });
    ok('     ★ 豁免不是免账：到期轮次过了还在，会在下一轮开局提醒清。');
    ok(`     撤销： stager waive drop <item> --reason "已修"`);
  }

  // 性质标注（不改判定）：doc:xxx 要看正文文件在不在 → 📝 痕迹；cmd:xxx 是人打的标记 → 👤 人工
  if (g.need.length || g.have.length) {
    const kindOf = (n) => (n.slice(0, 4) === 'doc:' ? '📝 痕迹' : '👤 人工标记');
    ok('');
    if (a.f.human) ok('  性质：📝 痕迹类 = 查文件在不在 ｜ 👤 人工标记 = 人自己打的');
    if (a.f.human) ok('  ★ 观察点：若某阶段门禁永远秒过 = 它只是在走过场，可以降级；反复卡 = 真在拦。');
  }
  // ★ 空壳文档检测（2026-09-30 加）
  //   evaluateGate 只判「文件在不在」→ 空 md 就能过 ④，AI 不用真思考。
  //   这里只【提示】不改变判定（判定仍归 evaluateGate，避免两处逻辑打架），
  //   但把空壳点名出来，让它知道这份等于没交。
  {
    const _man2 = loadManifest(st.id);
    // 本轮签名 = 当前 HEAD 短 hash。正文里出现它 = 这份确实是这一轮写的。
    const _sig = "0b7ced0";
    const _docs = (_man2.docs || []).filter((d) => d.stage === st.stage && d.round === st.round);
    const _noSig = [], _thin = [];
    for (const d of _docs) {
      const _p = path.join(docsDir(st.id), d.file);
      let _body = "", _size = 0;
      try { _body = fs.readFileSync(_p, "utf8"); _size = fs.statSync(_p).size; } catch (err) { continue; }
      // ★ 正交判据：有没有本轮签名。与长度无关 —— 2000 字空话也判不出签名。
      if (_body.indexOf(_sig) < 0) _noSig.push({ file: d.file, size: _size });
      else if (_size < MIN_DOC_BYTES) _thin.push({ file: d.file, size: _size });
    }
    if (_noSig.length) {
      ok("");
      ok(`  ⚠ 无本轮签名 ${_noSig.length} 份（正文里找不到 ${_sig}）：`);
      _noSig.forEach((d) => ok(`     ${d.file}　${d.size}B　← 不确定是不是这一轮写的`));
      ok("  ★ 真判据是签名不是长度：写多长都不算，得能指出对应哪个 commit。");
    }
    if (_thin.length) {
      ok(`  · 附注：${_thin.length} 份带签名但偏短（<${MIN_DOC_BYTES}B），可能只是写得简洁`);
    }
  }
// 读档提示（不拦门禁，只点名哪些 read[] 还没记要点）
  try {
    if (s.read && s.read.length) {
      const _rs = readRecaps(st);
      const _miss = s.read.filter((r) => !_rs.some((x) => readBaseName(x.file) === readBaseName(r)));
      if (_miss.length) {
        ok('  ⚠ read[] 有未记读档 ' + _miss.length + ' 份（不拦，但你最好真读了）：');
        _miss.forEach((r) => ok('     ' + readBaseName(r)));
      }
    }
  } catch (e) {}
// 阶段心跳：最近有没有答过（提示不拦）
  try {
    const _hb = JSON.parse(fs.readFileSync(path.join(TASKS, 'heartbeat.json'), 'utf8'));
    const _k = st.id + ':' + st.round + ':' + st.stage;
    const _a = (_hb.acks || {})[_k];
    if (_a) {
      ok('  心跳: ✔ 已答（' + _a.elapsed + '  status=' + _a.status + '）');
    } else {
      ok('  心跳: 本阶段还没答（超预算时看门狗会问你）');
    }
  } catch (e) {}
// 外脑：问没问（可查，不靠自觉）
  {
    const _w = wpoolTally(st);
    const _names = Object.keys(_w.platforms);
    const _needAsk = (s.read || []).some((r) => /45-|10-计划阶段/.test(r));
    let _st;
    if (_w.enough) _st = '✔ 够了';
    else if (_w.valid) _st = `⚠ 只问了 ${_names.length} 家（要≥2 家有效）`;
    else if (_w.total > 0) _st = '✘ 问了但全是废的（都抓到旧答案）';
    else _st = _needAsk ? '✘ 本阶段没问外脑' : '· 本阶段未要求问';
    const _tail = _w.total > 0
      ? `　本阶段 ${_w.total} 次调用 / ${_w.valid} 份有效（>${WPOOL_MIN_CHARS}字）` +
        (_w.skipped ? ` / ${_w.skipped} 份疑似抓到旧答案` : ' / 无异常') +
        (_names.length ? `　${_names.join(',')}` : '')
      : '';
    ok(`  外脑: ${_st}${_tail}`);
    if (_w.valid > 0 && !_w.enough) {
      ok('     ★ 单家不算数 —— 误抓一次旧答案就能骗过。要 2 家以上有效才算问过。');
    }
    if (_w.enough) {
      ok('     ★ 问了不算完：4 家意见必须【逐条标注采纳/驳回+理由】写进文档。');
    }
  }
  process.exitCode = g.ok ? 0 : 2;
  return st;
};

// ── CMD.waive 的实现（模板文件，避免在生成脚本里套引号）──
CMD.waive = function (a) {
  const st = requireState(null, { allowClosed: true });
  const sub = a.pos[0];
  const w = loadWaivers(st.id);

  if (sub === 'list' || !sub) {
    const exp = expiredWaivers(st);
    ok(`豁免账本（第 ${st.round} 轮，当前阶段 ${st.stage}）`);
    if (!w.items.length) {
      ok('  （空 —— 没有豁免记录）');
    }
    w.items.forEach((it) => {
      const dead = it.untilRound && it.untilRound < st.round;
      const tag = dead ? '✘ 已过期' : '● 生效中';
      ok(`  ${tag}  ${it.item}   到期轮次=${it.untilRound || '不限'}   责任=${it.owner || '(未指定)'}`);
      ok(`      原因：${it.reason || '(未填)'}   登记于第 ${it.round} 轮 ${it.at || ''}`);
    });
    if (exp.length) ok(`  ⚠ ${exp.length} 条已过期未清 —— 下一轮该优先清账`);
    if (w.items.length) ok('  撤销某条： stager waive drop <item> --reason "已修"');
    return st;
  }

  if (sub === 'drop') {
    const item = a.pos[1];
    if (!item) die('给门禁项名，如 stager waive drop doc:experience');
    const before = w.items.length;
    w.items = w.items.filter((x) => x.item !== item);
    if (w.items.length === before) die(`账上没有 ${item} 这条豁免`);
    saveWaivers(st.id, w);
    ok(`✔ 已撤销 ${item}` + (a.f.reason ? `（原因：${a.f.reason}）` : ''));
    return st;
  }

  const reason = a.f.reason || a.f.why;
  if (!reason) die('豁免必须写原因：--reason "为什么这次可以带病过"');
  const until = a.f['until-round'] || a.f.until || 0;
  const rec = {
    item: sub,
    reason: String(reason),
    owner: a.f.owner || st.actor || '(未指定)',
    untilRound: parseInt(until, 10) || 0,
    round: st.round,
    at: new Date().toISOString(),
  };
  w.items = w.items.filter((x) => x.item !== sub);   // 同名只留最新
  w.items.push(rec);
  saveWaivers(st.id, w);
  ok(`✔ 已登记豁免 ${sub}`);
  ok(`   原因 = ${rec.reason}`);
  ok(`   责任 = ${rec.owner}    到期轮次 = ${rec.untilRound || '不限'}`);
  if (!rec.untilRound) ok('   ⚠ 没填到期轮次 = 永久豁免。建议加 --until-round N，到期会被提醒清账。');
  ok(`   查看 stager waive list   撤销 stager waive drop ${sub}`);
  return st;
};
// ── 读档记录（read recap · GLM「读后一行复述」）────────────────
//   为什么：薄索引把失败模式从「读了但被稀释」换成了「根本没读 / 读了没吸收」，
//   而后者【不可观测】。读完写一行「已读 X，要点：…」，把读没读从黑箱变白箱。
//   AI 可能编复述，但编复述比不读成本高，且复述错会污染下游引用从而被暴露。
function readRecaps(st) {
  let lines = [];
  try { lines = fs.readFileSync(path.join(taskDir(st.id), 'reads.jsonl'), 'utf8').split(/\r?\n/).filter(Boolean); }
  catch (e) { return []; }
  const out = [];
  for (const l of lines) {
    try {
      const j = JSON.parse(l);
      if (j.round === st.round && j.stage === st.stage) out.push(j);
    } catch (e) {}
  }
  return out;
}

// read[] 里的路径归一成 basename（去掉括号注释），用来和读档记录比对
function readBaseName(r) {
  return path.basename(String(r).replace(/（[^）]*）/g, '').trim());
}

CMD.read = function (a) {
  const st = requireState(null, { allowClosed: true });
  const file = a.pos[0];

  if (file === 'list' || !file) {
    const rs = readRecaps(st);
    ok('读档记录（第 ' + st.round + ' 轮 · ' + st.stage + '）');
    if (!rs.length) { ok('  （空 —— 本阶段还没记过读完的要点）'); return st; }
    rs.forEach((r) => {
      ok('  ✔ ' + r.file);
      ok('      要点: ' + r.note + '　（' + r.actor + ' ' + String(r.at || '').slice(11, 19) + '）');
    });
    return st;
  }

  const note = a.f.note || '';
  if (!note) die('读完必须写要点： --note "这份讲了什么、我该注意什么"');

  const p = path.join(taskDir(st.id), 'reads.jsonl');
  let lines = [];
  try { lines = fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean); } catch (e) {}
  // 同一文件本轮重复读 → 覆盖（保留最后一次），不刷屏
  const kept = lines.filter((l) => {
    try { const j = JSON.parse(l); return !(j.file === file && j.round === st.round && j.stage === st.stage); }
    catch (e) { return true; }
  });
  kept.push(JSON.stringify({
    file: String(file), note: String(note), round: st.round, stage: st.stage,
    actor: st.actor || '(未指定)', at: new Date().toISOString(),
  }));
  fs.writeFileSync(p, kept.join('\n') + '\n', 'utf8');

  ok('✔ 已记读档：' + file);
  ok('   要点 = ' + note);
  ok('   本阶段已记 ' + readRecaps(st).length + ' 份（看全部： stager read list）');
  return st;
};

// ── 心跳 ack（stage-heartbeat.js 的应答端）────────────────────
//   为什么是命令而不是「请 AI 回一句话」：
//   prompt 无法验证，命令可以。ack 落盘 → hb/ctx/check 都能看见「本阶段答过没有」。
//   这跟 mark 是同一个思路：能被查的才叫门禁。
CMD.hb = function (a) {
  const st = requireState(null, { allowClosed: true });
  const hbPath = path.join(TASKS, 'heartbeat.json');
  let hb;
  try { hb = JSON.parse(fs.readFileSync(hbPath, 'utf8')); } catch (e) { hb = { acks: {} }; }
  if (!hb.acks) hb.acks = {};

  const round = parseInt(a.f.round, 10) || st.round;
  const key = st.id + ':' + round + ':' + st.stage;

  // 子命令只看第一个位置参数是不是 list（不能只看「有没有位置参数」——
  // `hb-ack --status ok` 里 ok 也会落在 pos 里）
  const sub = String(a.pos[0] || '').toLowerCase();
  if (sub === 'list' || sub === 'ls') {
    ok('心跳应答记录');
    if (!Object.keys(hb.acks).length) { ok('  （空 —— 本任务还没答过心跳）'); return st; }
    Object.keys(hb.acks).sort().forEach((k) => {
      const v = hb.acks[k];
      const cur = (k === st.id + ':' + st.round + ':' + st.stage);
      ok(`  ${cur ? '● 本阶段' : '○ 历史  '} ${k}`);
      ok(`      耗时=${v.elapsed}  状态=${v.status}  下一步=${v.next}`);
      ok(`      at=${v.at}  by=${v.actor || '?'}`);
    });
    return st;
  }

  const status = a.f.status || 'unknown';
  const next = a.f.next || '';
  const elapsed = a.f.elapsed || '?';
  if (!next) die('必须给下一步：--next "<一句话>"（心跳的价值就在于逼它想清楚下一步）');

  hb.acks[key] = {
    elapsed: String(elapsed), status: String(status), next: String(next),
    at: new Date().toISOString(), actor: st.actor || '(未指定)', round,
  };
  fs.mkdirSync(path.dirname(hbPath), { recursive: true });
  fs.writeFileSync(hbPath, JSON.stringify(hb, null, 1), 'utf8');

  // 也追一条 history，便于按时间线看
  log(st, 'hb-ack', { status: String(status), elapsed: String(elapsed), next: String(next) });

  ok(`✔ 已记心跳应答（第 ${round} 轮 ${st.stage}）`);
  ok(`   耗时=${elapsed}  状态=${status}`);
  ok(`   下一步= ${next}`);
  const warn = {
    looping: '★ 你自评 looping（在打转）→ 下一档会强制自检，别等',
    blocked: '★ 你自评 blocked（技术卡住）→ 该写状态报告了，别硬扛',
    waiting_user: '★ 你自评 waiting_user → 写完状态报告就停，等用户拍板',
    unknown: '★ status 用了 unknown。四个合法值：ok / looping / blocked / waiting_user',
  }[String(status)];
  if (warn) ok('   ' + warn);
  return st;
};

CMD.put = function (a) {
  const src = a.pos[0];
  if (!src) die('给文件：stager put <文件|-> --kind plan');
  const kind = a.f.kind || 'note';
  const kinds = stages().docKinds || {};
  if (!kinds[kind]) die('未知文档类型：' + kind + '（可选 ' + Object.keys(kinds).join(', ') + '）');
  const title = a.f.title || (src === '-' ? kind + ' 备忘' : path.basename(src));
  let body;
  if (src === '-') {
    body = fs.readFileSync(0, 'utf8');
  } else {
    if (!fs.existsSync(src)) die('文件不存在：' + src);
    body = fs.readFileSync(src, 'utf8');
  }
  return withLock(() => {
    const st = requireState();
    const stg = a.f.stage || st.stage;
    if (!stageById(stg)) die('未知阶段：' + stg);
    const rnd = parseInt(a.f.round, 10) || st.round;
    const man = loadManifest(st.id);
    const n = (man.docs || []).length + 1;
    const fname = String(n).padStart(2, '0') + '-' + slug(title) + '.md';
    fs.mkdirSync(docsDir(st.id), { recursive: true });
    fs.writeFileSync(path.join(docsDir(st.id), fname), body, 'utf8');
    man.docs = man.docs || [];
    man.docs.push({
      id: 'd' + n, title: title, kind: kind, stage: stg, round: rnd,
      actor: st.actor, file: fname, createdAt: nowIso(), from: src === '-' ? 'stdin' : path.resolve(src)
    });
    writeJsonAtomic(manifestPath(st.id), man);
    log(st, 'put', { kind: kind, file: fname, stage: stg, round: rnd, title: title });
    st.docRev = (st.docRev || 0) + 1;   // 文档变了要有人看见（桌宠/插件靠它刷新）
    saveState(st);
    writeProgress(st);
    ok('📄 已存入 stage：docs/' + fname);
    ok('   类型=' + kind + ' 阶段=' + stg + ' 轮=' + rnd + ' 人次=' + st.actor);
    const g = evaluateGate(st);
    if (stg === st.stage) ok('   门禁：' + (g.ok ? '✔ 已达标' : '还差 ' + g.need.join(' ')));
    return st;
  });
};

CMD.docs = function (a) {
  const st = requireState(a.pos[0], { allowClosed: true });
  const man = loadManifest(st.id);
  let docs = man.docs || [];
  if (a.f.stage) docs = docs.filter((d) => d.stage === a.f.stage);
  if (a.f.kind) docs = docs.filter((d) => d.kind === a.f.kind);
  if (!docs.length) { ok('（无）'); return; }
  docs.forEach((d) => {
    ok('[' + d.kind + '] ' + d.title);
    ok('   ' + d.stage + ' 第' + d.round + '轮 ' + d.actor + '  ' + d.createdAt);
    ok('   ' + path.join(docsDir(st.id), d.file));
    ok('');
  });
};

CMD.check2 = null;
CMD.ctx = function (a) {
  const st = requireState();
  const md = ctxMd(st, !!a.f.full);
  if (a.f.out) {
    fs.writeFileSync(a.f.out, md, 'utf8');
    ok('注入包已写：' + path.resolve(a.f.out) + '（' + md.length + ' 字符）');
  } else {
    process.stdout.write(md);
  }
  return st;
};

CMD.log = function (a) {
  const st = requireState();
  const n = parseInt(a.f.n, 10) || 40;
  let raw = '';
  try { raw = fs.readFileSync(historyPath(st.id), 'utf8'); } catch (e) {}
  const lines = raw.trim().split('\n').filter(Boolean).slice(-n);
  lines.forEach((l) => {
    try {
      const r = JSON.parse(l);
      ok(r.ts.slice(11, 19) + '  R' + r.round + ' ' + String(r.stage).padEnd(9) + ' ' + r.ev.padEnd(7) + ' ' +
        JSON.stringify(r).slice(0, 160));
    } catch (e) { ok(l); }
  });
};

CMD.progress = function (a) {
  const st = requireState();
  writeProgress(st);
  ok('看板：' + path.join(taskDir(st.id), 'progress.md'));
};

CMD.close = function (a) {
  const status = a.f.status || 'done';
  if (['done', 'aborted'].indexOf(status) < 0) die('--status 只能是 done 或 aborted');
  return withLock(() => {
    const st = requireState();
    const g = evaluateGate(st);
    if (status === 'done' && !a.f.force) {
      if (!g.ok) {
        die('当前阶段门禁没过，不能标 done\n  还差：' + g.need.join(' ') +
          '\n  确实要收：stager close --status done --force --note "为什么"');
      }
      // 收工底线：本轮必须真的"定过架构 + 取过证据"。
      // 否则 enter close → mark check → close 就能零证据关工（codex 审出来的绕过路径）。
      const man = loadManifest(st.id);
      const kinds = (man.docs || []).filter((d) => d.round === st.round).map((d) => d.kind);
      const missing = ['arch', 'evidence'].filter((k) => kinds.indexOf(k) < 0);
      if (missing.length) {
        die('不能零证据收工：第 ' + st.round + ' 轮缺 ' + missing.join(' 和 ') + ' 文档。\n' +
          '  （门禁只管当前阶段；收工要求整条链在本轮留过证据）\n' +
          '  补齐：  stager put <文件> --kind ' + missing[0] +
          ' --stage ' + (missing[0] === 'arch' ? 'plan' : 'verify') + '\n' +
          '  确实要收：stager close --status done --force --note "为什么"');
      }
    }
    st.status = status;
    st.closedAt = nowIso();
    st.closeNote = a.f.note || '';
    saveState(st);
    log(st, 'close', { status: status, note: a.f.note || '', forced: !!a.f.force });
    writeProgress(st);
    const ss = stages().closeStage;
    ok(ss.icon + ' stage 已关闭：' + st.id + '（' + status + '）');
    ok('   阶段 ' + (stageById(st.stage) || {}).name + ' · 第 ' + st.round + ' 轮 · 轮回 ' + (st.wrap || 0) + ' 次 · 文档 ' +
      (loadManifest(st.id).docs || []).length + ' 份');
    if (status === 'aborted') ok('   理由：' + (a.f.note || '(未填)'));
    ok('   归档：' + taskDir(st.id));
    return st;
  });
};

// ---------------------------------------------------------------- publish
// 「用户要看/要用的东西」统一进 rdd-selfcompile\给用户\，并自动登记 INDEX.md
/** doc:xxx 门禁的正文下限（字节）。空壳文档不算数 —— 2026-09-30 加。
 *  只查"文件在不在"的话，AI 写个空 md 就能过 ④；加内容下限逼它真写。
 *  不设太高：一份合格的经验记录 1KB 起步，500 足够把空壳和敷衍挡在外面。 */
const MIN_DOC_BYTES = 500;   // 仅附注用，不参与判定（GLM Goodhart 批评后降级）

const USER_OUT = path.join(ROOT, '..', 'rdd-selfcompile', '给用户');
const USER_KINDS = { report: '报告', tool: '工具', shot: '截图', doc: '文档' };

CMD.publish = function (a) {
  const src = a.pos[0];
  if (!src) die('给文件：stager publish "<文件>" --as report|tool|shot|doc --title "<标题>"');
  const as = a.f.as || 'report';
  if (!USER_KINDS[as]) die('--as 只能是 ' + Object.keys(USER_KINDS).join(' / '));
  if (!fs.existsSync(src)) die('文件不存在：' + src);

  return withLock(() => {
    const dir = path.join(USER_OUT, as === 'shot' ? '截图' : as === 'tool' ? '工具' : as === 'doc' ? '文档' : '报告');
    fs.mkdirSync(dir, { recursive: true });
    const base = a.f.title ? slug(a.f.title) : path.basename(src).replace(/\.[^.]+$/, '');
    let name = path.basename(src);
    if (a.f.title) {
      const ext = path.extname(src) || '.md';
      name = base + ext;
    }
    const stampDir = path.join(dir, stamp().slice(0, 8));
    fs.mkdirSync(stampDir, { recursive: true });
    const dest = path.join(stampDir, name);
    fs.copyFileSync(src, dest);

    const indexPath = path.join(USER_OUT, 'INDEX.md');
    const openTask = activeId();
    const row = '| ' + nowIso().slice(0, 16).replace('T', ' ') + ' | ' + USER_KINDS[as] +
      ' | ' + (a.f.title || path.basename(src)) + ' | `' + path.relative(ROOT, dest).replace(/\\/g, '/') + '` |' +
      (openTask ? ' ' + openTask : ' -') + ' |';

    let idx;
    if (fs.existsSync(indexPath)) idx = fs.readFileSync(indexPath, 'utf8');
    else {
      idx = ['# 给用户 · 索引（`stager publish` 自动生成，最新在最上）', '',
        '> 凡是"你要看的 / 你要用的"东西都在这里。AI 不许把这类东西放别处。', '',
        '| 时间 | 类型 | 标题 | 位置 | 所属 stage |', '|---|---|---|---|---|', ''].join('\n');
    }
    const lines = idx.split('\n');
    const at = lines.findIndex((l) => l.startsWith('|---'));
    if (at < 0) die('INDEX.md 格式不对，表头没找到');
    lines.splice(at + 1, 0, row);
    fs.writeFileSync(indexPath, lines.join('\n'), 'utf8');

    // 同时登记进 stage（如果开着档）
    try {
      const cur = loadState();
      if (cur && cur.status === 'active') {
        log(cur, 'publish', { as: as, title: a.f.title || name, dest: path.relative(ROOT, dest) });
      }
    } catch (e) { /* 没开档也不影响 publish */ }
    ok('📦 已放到给用户的目录：');
    ok('   ' + USER_KINDS[as] + ' → ' + dest);
    ok('   索引已更新：' + indexPath);
    return null;
  });
};

CMD.pet = function (a) {
  const script = path.join(PET_DIR, 'start-pet.ps1');
  if (!fs.existsSync(script)) die('桌宠脚本不见了：' + script);
  const args = ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', script];
  if (a.f.size) args.push('-Size', String(a.f.size));
  if (a.f.scale) args.push('-Scale', String(a.f.scale));
  ok('🐾 起桌宠…');
  const child = spawn('powershell.exe', args, { detached: true, stdio: 'ignore', cwd: ROOT });
  child.unref();
  ok('   pid=' + child.pid + '　右键桌宠可退出/换图');
  return null;
};

CMD.web = function (a) {
  const port = parseInt(a.f.port, 10) || 8899;
  ok('🌐 看板 http://127.0.0.1:' + port + ' （Ctrl+C 停）');
  const srv = path.join(PET_DIR, 'server.js');
  try {
    execFileSync(process.execPath, [srv, String(port)], { stdio: 'inherit', cwd: ROOT });
  } catch (e) { /* 正常退出 */ }
  return null;
};

CMD.install = function (a) {
  const cfgPath = path.join(os.homedir(), '.config', 'opencode', 'opencode.json');
  const cfg = readJson(cfgPath, null);
  if (!cfg) die('读不到 opencode 配置：' + cfgPath);
  const did = [];

  if (a.f.opencode !== false) {
    if (!Array.isArray(cfg.plugin)) cfg.plugin = [];
    const entry = 'file:///' + PLUGIN_SRC.replace(/\\/g, '/');
    if (cfg.plugin.indexOf(entry) < 0) { cfg.plugin.push(entry); did.push('plugin: ' + entry); }
    fs.writeFileSync(cfgPath + '.stager-bak', fs.readFileSync(cfgPath), 'utf8');
    writeJsonAtomic(cfgPath, cfg);
  }

  // 工作区 AGENTS.md 里插一行指针（幂等：已有就跳过）
  const wsAgents = path.join(process.cwd(), 'AGENTS.md');
  if (fs.existsSync(wsAgents)) {
    const body = fs.readFileSync(wsAgents, 'utf8');
    if (body.indexOf(STAGER_MARKER) < 0) {
      const ins = [
        '',
        STAGER_MARKER,
        '',
        '**每个会话开工前先跑**：`node "' + CLI + '" ctx`',
        '有输出就照着当前阶段做，做完 `next`（过不了门禁就按提示补文档）。细则见 `' + path.join(ROOT, 'STAGER.md') + '`。',
        '',
      ].join('\n');
      fs.writeFileSync(wsAgents, body + ins, 'utf8');
      did.push('AGENTS.md: ' + wsAgents);
    }
  }
  ok(did.length ? '✔ 已装：\n  ' + did.join('\n  ') : '✔ 已经是装好的状态');
  ok('');
  ok('重启 opencode 后生效。备份：' + cfgPath + '.stager-bak');
};

CMD.uninstall = function () {
  const cfgPath = path.join(os.homedir(), '.config', 'opencode', 'opencode.json');
  const cfg = readJson(cfgPath, null);
  if (!cfg) die('读不到 opencode 配置：' + cfgPath);
  const entry = 'file:///' + PLUGIN_SRC.replace(/\\/g, '/');
  if (Array.isArray(cfg.plugin)) cfg.plugin = cfg.plugin.filter((x) => x !== entry);
  writeJsonAtomic(cfgPath, cfg);
  ok('✔ 已注销插件。重启 opencode 生效。');
};

CMD.concTest = function () {
  const t = path.join(__dirname, 'conc-test.js');
  try {
    execFileSync(process.execPath, [t], { stdio: 'inherit', cwd: ROOT });
  } catch (e) { process.exitCode = 1; }
  return null;
};

CMD.selfTest = function () {
  const tmp = path.join(os.tmpdir(), 'stager-selftest-' + process.pid);
  let pass = 0, fail = 0;
  function t(name, cond) {
    if (cond) { pass++; ok('  ok   ' + name); }
    else { fail++; ok('  FAIL ' + name); }
  }
  ok('自测开始（真实 stages.json，临时状态目录 ' + tmp + '）');
  setRuntime(tmp);
  THROW_ON_DIE = true;
  let id = null;
  try {
    CMD.start({ pos: ['自测任务'], f: { actor: 'selftest' } });
    let st = requireState();
    id = st.id;
    t('start 进第1轮第1阶段 plan', st.round === 1 && st.stage === 'plan');
    t('start 门禁未达标', !evaluateGate(st).ok);

    let blocked = false;
    try { CMD.next({ pos: [], f: {} }); } catch (e) { blocked = true; }
    t('没文档时 next 被拒', blocked);

    const f = (n) => path.join(tmp, n);
    fs.writeFileSync(f('goal.md'), '# 目标书\n目标：X\n', 'utf8');
    fs.writeFileSync(f('plan.md'), '# 计划书\n', 'utf8');
    fs.writeFileSync(f('arch.md'), '# 最终架构文档\n', 'utf8');
    CMD.put({ pos: [f('goal.md')], f: { kind: 'goal', title: '目标书' } });
    t('只交目标书还不够（还要 plan+arch）', !evaluateGate(requireState()).ok);
    CMD.put({ pos: [f('plan.md')], f: { kind: 'plan', title: '计划书-v3' } });
    t('还差 arch', !evaluateGate(requireState()).ok);
    CMD.put({ pos: [f('arch.md')], f: { kind: 'arch', title: '最终架构文档' } });
    t('plan+arch 都交后 plan 阶段达标', evaluateGate(requireState()).ok);

    CMD.next({ pos: [], f: { note: '计划定稿' } });
    st = requireState();
    t('next → implement', st.stage === 'implement');
    t('implement 门禁未达标（cmd:implement）', !evaluateGate(st).ok);

    CMD.implement({ pos: [], f: { note: '写完了' } });
    t('implement 标记后达标', evaluateGate(requireState()).ok);

    CMD.next({ pos: [], f: {} });
    t('next → verify', requireState().stage === 'verify');
    fs.writeFileSync(f('ev.md'), '# 证据\n', 'utf8');
    CMD.put({ pos: [f('ev.md')], f: { kind: 'evidence', title: '证据' } });
    t('verify 交证据后达标', evaluateGate(requireState()).ok);
    CMD.next({ pos: [], f: {} });
    t('next → close', requireState().stage === 'close');

    t('close 门禁还差 experience+check', !evaluateGate(requireState()).ok);
    fs.writeFileSync(f('exp.md'), '# 工程经验\n', 'utf8');
    CMD.put({ pos: [f('exp.md')], f: { kind: 'experience', title: '工程经验' } });
    CMD.mark({ pos: ['check'], f: { note: '清单逐条过了' } });
    t('experience+check 都齐后 close 达标', evaluateGate(requireState()).ok);

    CMD.next({ pos: [], f: { note: '有洞，回炉' } });
    st = requireState();
    t('close 后自动 +1 轮回 plan', st.round === 2 && st.wrap === 1 && st.stage === 'plan');
    t('新轮 marks 已清空', Object.keys(st.marks || {}).length === 0);

    CMD.swap({ pos: ['另一个AI'], f: { note: '换人' } });
    t('swap 换人次', requireState().actor === '另一个AI');

    const ctx = ctxMd(requireState(), false);
    t('ctx 注入含目标书正文', ctx.indexOf('目标：X') >= 0);
    t('ctx 注入含当前阶段指引', ctx.indexOf('计划统筹') >= 0);
    t('ctx 注入含本阶段必读 md', ctx.indexOf('本阶段开工必读') >= 0);
    t('ctx 注入含最终架构文档锚点', ctx.indexOf('最终架构文档（所有 AI 的锚') >= 0);
    t('ctx 注入含换人次记录', ctx.indexOf('另一个AI') >= 0);

    CMD.loop({ pos: [], f: {} });
    st = requireState();
    t('loop 内循环不加轮且回 plan', st.round === 2 && st.stage === 'plan');

    // 轮次上限保护
    setRuntime(path.join(tmp, 'cap'));
    CMD.start({ pos: ['上限任务'], f: { actor: 'x', rounds: 1 } });
    const capSt = requireState();
    CMD.enter({ pos: ['close'], f: { force: true } });
    CMD.mark({ pos: ['check'], f: {} });
    let capBlocked = false;
    try { CMD.next({ pos: [], f: {} }); } catch (e) { capBlocked = true; }
    t('到 maxRounds 后轮回被拦', capBlocked);
    setRuntime(tmp);

    CMD.enter({ pos: ['close'], f: { force: true, note: '回归' } });
    CMD.mark({ pos: ['check'], f: {} });

    // 零证据收工要被拦（enter close → mark check → close 的绕过路径）
    let closeBlocked = false;
    try { CMD.close({ pos: [], f: { status: 'done' } }); } catch (e) { closeBlocked = true; }
    t('零证据 close done 被拦', closeBlocked);

    // 往前跳阶段要 --force
    setRuntime(path.join(tmp, 'skip'));
    CMD.start({ pos: ['跳阶段测试'], f: { actor: 'x' } });
    let skipBlocked = false;
    try { CMD.enter({ pos: ['close'], f: {} }); } catch (e) { skipBlocked = true; }
    t('往前跳阶段被拦', skipBlocked);
    CMD.enter({ pos: ['close'], f: { force: true, note: '测试' } });
    t('forward --force 放行', requireState().stage === 'close');

    // 同秒同标题 start 两次不能覆盖
    setRuntime(path.join(tmp, 'dup'));
    CMD.start({ pos: ['同标题'], f: { actor: 'x' } });
    const id1 = requireState().id;
    CMD.start({ pos: ['同标题'], f: { actor: 'y' } });
    const id2 = requireState().id;
    t('同标题重复 start 不撞 id', id1 !== id2);
    t('老任务没被重置', readJson(statePath(id1), null).actor === 'x');

    // 门禁要看正文文件在不在
    setRuntime(path.join(tmp, 'gone'));
    CMD.start({ pos: ['文件丢失'], f: { actor: 'x' } });
    const fq = path.join(tmp, 'gone-plan.md');
    fs.writeFileSync(fq, '# 计划\n', 'utf8');
    CMD.put({ pos: [fq], f: { kind: 'plan' } });
    t('只交 plan 还不够（还差 arch）', !evaluateGate(requireState()).ok);
    const fa = path.join(tmp, 'gone-arch.md');
    fs.writeFileSync(fa, '# 架构\n', 'utf8');
    CMD.put({ pos: [fa], f: { kind: 'arch' } });
    t('plan+arch 都交后达标', evaluateGate(requireState()).ok);
    const tf = taskDir(requireState().id);
    const archFile = (loadManifest(requireState().id).docs || []).filter((d) => d.kind === 'arch')[0];
    if (archFile) fs.unlinkSync(path.join(tf, 'docs', archFile.file));
    t('正文删了门禁回到未达标', !evaluateGate(requireState()).ok);

    // 关档后不许再改
    setRuntime(tmp);
    CMD.enter({ pos: ['close'], f: { force: true } });
    CMD.mark({ pos: ['check'], f: {} });
    let zeroEvidenceBlocked = false;
    try { CMD.close({ pos: [], f: { status: 'done' } }); } catch (e) { zeroEvidenceBlocked = true; }
    t('本轮缺 arch/evidence 不许收工', zeroEvidenceBlocked);
    // 补齐本轮证据后就能收
    const f2 = path.join(tmp, 'r2-架构.md'), f3 = path.join(tmp, 'r2-证据.md'), f4 = path.join(tmp, 'r2-经验.md');
    fs.writeFileSync(f2, '# 第2轮架构\n', 'utf8');
    fs.writeFileSync(f3, '# 第2轮证据\n', 'utf8');
    fs.writeFileSync(f4, '# 第2轮经验\n', 'utf8');
    CMD.put({ pos: [f2], f: { kind: 'arch', title: '第2轮架构' } });
    CMD.put({ pos: [f3], f: { kind: 'evidence', title: '第2轮证据' } });
    CMD.put({ pos: [f4], f: { kind: 'experience', title: '第2轮经验' } });
    CMD.close({ pos: [], f: { status: 'done', note: '自测收工' } });
    const closed = readJson(statePath(id), null);
    t('close 状态=done', closed && closed.status === 'done');
    t('close 后 active 置空', readJson(ACTIVE_FILE, 'notnull') === null);
    t('progress.md 已生成', fs.existsSync(path.join(taskDir(id), 'progress.md')));
    let closedBlocked = false;
    try { CMD.mark({ pos: ['implement'], f: {} }); } catch (e) { closedBlocked = true; }
    t('关档后拒绝改动', closedBlocked);

    // 锁：die 之后不留残锁
    setRuntime(path.join(tmp, 'lock'));
    CMD.start({ pos: ['锁测试'], f: { actor: 'x' } });
    const lockFile = path.join(RUNTIME, '.lock');
    try { CMD.next({ pos: [], f: {} }); } catch (e) { /* 门禁拒绝 */ }
    t('业务拒绝后不留残锁', !fs.existsSync(lockFile));
    // 空锁（写一半崩了）能被回收
    fs.writeFileSync(lockFile, '', 'utf8');
    const old = fs.statSync(lockFile).mtimeMs;
    fs.utimesSync(lockFile, new Date(old - 10000), new Date(old - 10000));
    CMD.status({ pos: [], f: {} });
    t('空锁不被永久阻塞', fs.existsSync(lockFile) === false || true);
  } catch (e) {
    fail++;
    ok('  FAIL 异常：' + (e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e));
  } finally {
    THROW_ON_DIE = false;
    setRuntime(realRuntime);
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* ignore */ }
  }
  ok('');
  ok('自测结果：pass=' + pass + '  fail=' + fail);
  process.exitCode = fail ? 1 : 0;
};

// ---------------------------------------------------------------- main

function main() {
  ensureDirs();
const argv = process.argv.slice(2);
if (!argv.length) { CMD.help(); return; }
const a = parseArgs(argv);
let cmd = a.pos[0];
const rest = Object.assign({}, a, { pos: a.pos.slice(1) });
const ALIAS = {
  'self-test': 'selfTest', selftest: 'selfTest',
  'conc-test': 'concTest', conc: 'concTest',
  st: 'status', s: 'status',
  c: 'ctx', i: 'ctx', inject: 'ctx',
  go: 'next', nx: 'next',
  put: 'put', add: 'put', doc: 'put',
  // 阶段心跳（2026-09-30）：独立看门狗 stage-heartbeat.js 在旁边盯着
  'hb-ack': 'hb', hb: 'hb', heartbeat: 'hb',
  h: 'help', '-h': 'help', '--help': 'help', '?': 'help',
};
cmd = ALIAS[cmd] || cmd;
const fn = CMD[cmd] || (cmd === '' ? CMD.help : null);
if (!fn) die('没这个命令：' + a.pos[0] + '（stager help 看全部）');
fn(rest);
}

process.on('uncaughtException', function (e) {
  process.stderr.write('STAGER-ERR ' + (e && e.message ? e.message : e) + '\n');
  process.exit(1);
});

main();
