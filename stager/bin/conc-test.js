'use strict';
/**
 * 并发压测：验证「锁内重读」真的防住了丢更新。
 *
 * 关键：必须**真并发**（spawn 后一起等），串行 execFileSync 只能测顺序不能测竞态。
 * 三件事同时验：
 *   ① 8 个进程同时 swap   → actorLog 不能少（少 = 丢更新）
 *   ② 8 个进程同时 mark   → marks 不能少
 *   ③ 8 个进程同时 next   → 门禁没过时状态不能被偷推进
 * 外加：残锁检查
 */

const { execFileSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const CLI = path.join(__dirname, 'stager.js');
const tmp = path.join(os.tmpdir(), 'stager-conc-' + process.pid);
const env = Object.assign({}, process.env, { STAGER_RUNTIME: tmp });

function run(args) {
  try { return execFileSync(process.execPath, [CLI].concat(args), { env, encoding: 'utf8', windowsHide: true }); }
  catch (e) { return ''; }
}

/** 真并发：n 个子进程同一瞬间打同一个命令，全部返回才算完 */
function runParallel(n, argMaker) {
  return Promise.all(Array.from({ length: n }, (_, i) => new Promise((res) => {
    const p = spawn(process.execPath, [CLI].concat(argMaker(i)), { env, windowsHide: true, stdio: 'ignore' });
    p.on('close', () => res());
  })));
}

function readState(id) {
  return JSON.parse(fs.readFileSync(path.join(tmp, 'tasks', id, 'state.json'), 'utf8'));
}
function markKey(st) { return st.round + ':' + st.stage; }

(async () => {
  fs.rmSync(tmp, { recursive: true, force: true });
  run(['start', '并发压测任务', '--rounds', '9', '--actor', 'init']);
  const active = JSON.parse(fs.readFileSync(path.join(tmp, 'active.json'), 'utf8'));
  console.log('task=' + active);
  const t0 = Date.now();

  // ① 8 个进程同时 swap（换人次）—— 每次都 append actorLog，缺锁就会丢
  await runParallel(8, (i) => ['swap', 'ai-' + i]);
  let st = readState(active);
  const swaps = st.actorLog.filter((x) => /换人次/.test(x.note || '')).length;
  console.log('swap ×8 并发 → actorLog ' + swaps + ' 条 ' + (swaps === 8 ? '✔ 没丢' : '✘ 丢了 ' + (8 - swaps) + ' 条'));

  // ② 8 个进程同时 mark
  await runParallel(8, (i) => ['mark', 'm' + i]);
  st = readState(active);
  const m = (st.marks[markKey(st)] || []).length;
  console.log('mark ×8 并发 → marks ' + m + ' 个 ' + (m === 8 ? '✔ 没丢' : '✘ 丢了 ' + (8 - m) + ' 个')
    + '  [key=' + markKey(st) + ']');

  // ③ 8 个进程同时 next（门禁没过的会被拒，状态不许变）
  const before = readState(active);
  await runParallel(8, () => ['next']);
  st = readState(active);
  const same = st.stage === before.stage && st.round === before.round;
  console.log('next ×8 并发（门禁未过）→ 仍是 ' + st.stage + ' 第' + st.round + '轮 ' + (same ? '✔ 没人偷跑' : '✘ 状态被改'));

  // ④ 8 个进程同时 put（文档入库，manifest 不能互相覆盖）
  const f = path.join(tmp, 'p.md');
  fs.writeFileSync(f, '# 文档\n', 'utf8');
  await runParallel(8, () => ['put', f, '--kind', 'note', '--title', '并发文档']);
  st = readState(active);
  const man = JSON.parse(fs.readFileSync(path.join(tmp, 'tasks', active, 'docs', 'manifest.json'), 'utf8'));
  const n = (man.docs || []).length;
  console.log('put ×8 并发 → manifest ' + n + ' 份 ' + (n === 8 ? '✔ 没互相覆盖' : '✘ 覆盖了 ' + (8 - n) + ' 份'));

  // 残锁
  console.log('残锁：' + (fs.existsSync(path.join(tmp, '.lock')) ? '✘ 还在' : '✔ 没有'));

  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('耗时 ' + (Date.now() - t0) + 'ms');
  const pass = swaps === 8 && m === 8 && same && n === 8 && !fs.existsSync(path.join(tmp, '.lock'));
  process.exitCode = pass ? 0 : 1;
})();
