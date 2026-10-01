// stage-heartbeat.js — 阶段心跳与超时干预（独立看门狗进程）
//
// 起因（2026-09-30 用户提出，外部评审称之为「心跳自检 / 看门狗 / 状态锚点重注入」）：
//   **LLM 没有时间感，也没有内部时钟。** 上下文一长就会「迷失在 middle」——
//   我们已经两次亲历：①卡在 verify 阶段忘记写经验 ②为了修门禁工具忘记沉淀。
//   文档写「写进文档≠改掉习惯」，所以这次不写文档，写进程。
//
// 三条设计约束（照外部评审的「防翻车」建议）：
//   ① **独立进程**：不能挂在执行主循环里——主循环死锁时它自己的定时器也失效。
//      本脚本是独立 Node 进程，由 stager-hb.cmd 脱离启动。
//   ② **强制回答，不是强制提问**：光问「你在哪」没用，要它「答」。
//      所以 ack 是一个**命令**（stager hb-ack），落盘可验证 —— 和 mark 一样。
//      没 ack → check 能看见「本阶段还没答过心跳」，这是能查的，不像 prompt 无法验证。
//   ③ **阶梯式干预，不一刀切**：复杂 bug 确实要时间，直接掐断会误杀。
//      T+soft 温和提醒 → T+hard 强制自检 → T+rollback 快照+回退+记经验。
//
// 用法：
//   node stage-heartbeat.js --once                 跑一轮就退出（诊断用）
//   node stage-heartbeat.js --loop --interval 60   常驻看门狗（推荐）
//   node stage-heartbeat.js --loop --dry          只算不注入（先看会不会误报）
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync, spawn } = require('child_process');

const ROOT = 'E:/restart developing doer';
const STAGER = path.join(ROOT, 'stager/bin/stager.js');
const ARCH = 'E:/新建文件夹/rdd架构';
const LOG = path.join(ROOT, 'rdd-selfcompile/selfcompile/heartbeat.log');
const HB_STATE = path.join(ROOT, 'stager/.stager/heartbeat.json');

// ── 参数 ──────────────────────────────────────────────────
const argv = process.argv.slice(2);
const has = (k) => argv.includes(k);
const val = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const LOOP = has('--loop');
const DRY = has('--dry');
const INTERVAL = parseInt(val('--interval', '60'), 10);

// ── 每阶段的预算（分钟）────────────────────────────────────
// 外部评审给的：写代码 20（高强度逻辑计算）/ 游戏验证 30（环境交互+视觉反馈）
const BUDGET = { plan: 20, implement: 20, verify: 30, close: 15 };
const STAGE_CN = { plan: '①计划统筹', implement: '②编码实现', verify: '③游戏验证', close: '④记录收口' };

// 三档：soft=T0（提醒）/ hard=T0+10（强制自检）/ rollback=T0+20（回退）
const SOFT = 0, HARD = 10, ROLLBACK = 20;

function log(s) {
  const line = '[' + new Date().toISOString() + '] ' + s;
  try { fs.mkdirSync(path.dirname(LOG), { recursive: true }); fs.appendFileSync(LOG, line + '\n', 'utf8'); }
  catch (e) { /* 记不了就算了，别拖垮 */ }
  if (!LOOP) console.log(line);
}

// ── 读 stager 状态 ────────────────────────────────────────
function readStagerCtx() {
  try {
    const out = execFileSync(process.execPath, [STAGER, 'ctx'], { encoding: 'utf8', timeout: 30000 });
    return out;
  } catch (e) {
    try {
      // ctx 会在没有活动任务时报错 → 那也算一种状态
      return null;
    } catch (e2) { return null; }
  }
}

function readState() {
  const ACTIVE = path.join(ROOT, 'stager/.stager/active.json');
  let id = null;
  try { id = JSON.parse(fs.readFileSync(ACTIVE, 'utf8')).replace(/^"|"$/g, ''); } catch (e) {}
  if (!id) return null;
  try {
    const st = JSON.parse(fs.readFileSync(path.join(ROOT, 'stager/.stager/tasks', id, 'state.json'), 'utf8'));
    return { id, ...st };
  } catch (e) { return null; }
}

// ── 阶段起点：取 history 里最后一个进入该阶段的 ev ───────────
function stageEntryTime(st) {
  try {
    const L = fs.readFileSync(path.join(ROOT, 'stager/.stager/tasks', st.id, 'history.jsonl'), 'utf8')
      .split(/\r?\n/).filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean);
    for (let i = L.length - 1; i >= 0; i--) {
      const e = L[i];
      if ((e.ev === 'next' || e.ev === 'start') && e.to === st.stage) return Date.parse(e.ts);
      if (e.ev === 'start' && e.stage === st.stage) return Date.parse(e.ts);
    }
    if (L.length) return Date.parse(L[0].ts);
  } catch (e) {}
  return Date.parse(st.updatedAt || st.createdAt || new Date().toISOString());
}

// ── 本阶段是否已答过心跳（ack）─────────────────────────────
function readHbState() {
  try { return JSON.parse(fs.readFileSync(HB_STATE, 'utf8')); }
  catch (e) { return { acks: {} }; }
}
function writeHbState(s) {
  try { fs.mkdirSync(path.dirname(HB_STATE), { recursive: true }); fs.writeFileSync(HB_STATE, JSON.stringify(s, null, 1), 'utf8'); }
  catch (e) {}
}

// ── 注入（复用 every-10min-drive.ps1 的抢焦点+SendKeys 机制）──
function inject(text) {
  if (DRY) { console.log('  [DRY] 本该注入:\n' + text.split('\n').map((l) => '      ' + l).join('\n')); return 'dry'; }
  try {
    const ps = path.join(ROOT, 'rdd-selfcompile/scripts/every-10min-drive.ps1');
    // 它有 -Message 参数；用 -DryRun 先验证窗口能拿到
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps, '-Message', text];
    execFileSync('powershell.exe', args, { encoding: 'utf8', timeout: 60000 });
    return 'sent';
  } catch (e) {
    log('INJECT-FAIL ' + String(e.message).split('\n')[0]);
    return 'fail';
  }
}

// ── 三档文案 ──────────────────────────────────────────────
function msgSoft(st, min, budget) {
  return [
    '[HEARTBEAT 阶段心跳 · 不是用户指令]',
    `你现在在【${STAGE_CN[st.stage] || st.stage}】，已耗时 ${min} 分钟（本阶段预算 ${budget} 分钟）。`,
    '',
    '安静核对三件事，核对完就继续干活，不用回话：',
    '  1) 我有没有越权（做了不属于这个阶段的事）？',
    '  2) 这个阶段的目标到底完成了没有？（不是「做了很多」而是「目标达成」）',
    '  3) 状态打勾了吗？（该 put 文档的 put 了、该 next 的 next 了）',
    '',
    '★ 然后必须答一次心跳（一行命令，不答我会在 T+%HARD 再问一次）：',
    `   node "E:\\restart developing doer\\stager\\bin\\stager.js" hb-ack --stage ${st.stage} --elapsed ${min}m --status <ok|looping|blocked|waiting_user> --next "<下一步一句话>"`,
  ].join('\n');
}

function msgHard(st, min, budget) {
  return [
    '[HEARTBEAT 强制自检 · 不是用户指令]',
    `【${STAGE_CN[st.stage] || st.stage}】已经 ${min} 分钟（预算 ${budget}），进入强制自检。`,
    '',
    '★ 停下当前操作，先回答再继续（继续干不算回答）：',
    '  1. 为什么超时？具体是哪一步卡住了？',
    '  2. 卡住的那个，需要我（用户）决定什么吗？还是纯技术问题？',
    '  3. 如果重来一次，你打算先做什么？',
    '',
    '答完立刻执行：',
    `   node "E:\\restart developing doer\\stager\\bin\\stager.js" hb-ack --stage ${st.stage} --elapsed ${min}m --status <ok|looping|blocked|waiting_user> --next "<下一步>"`,
    '',
    '★ 如果答案是「需要用户决定」→ 就写一份状态报告（规格见 44-状态报告规格.md）然后停下，别硬扛。',
  ].join('\n');
}

// ── 跑一轮 ────────────────────────────────────────────────
function tick() {
  const st = readState();
  if (!st) { log('NO-ACTIVE 没有活动任务，跳过'); return; }
  if (st.status !== 'active') { log('TASK-CLOSED status=' + st.status + '，心跳停'); return; }

  const budget = BUDGET[st.stage] || 25;
  const entry = stageEntryTime(st);
  const min = Math.floor((Date.now() - entry) / 60000);
  const over = min - budget;
  const hb = readHbState();
  const key = st.id + ':' + st.round + ':' + st.stage;
  const acked = !!hb.acks[key];

  console.log('[' + new Date().toISOString().slice(11, 19) + '] 阶段=' + st.stage +
    ' 轮=' + st.round + ' 耗时=' + min + 'min 预算=' + budget + 'min 超=' +
    (over > 0 ? '+' + over : over) + ' 已答心跳=' + (acked ? '是' : '否'));

  if (over < SOFT) return;                    // 还没到点，什么都不做

  // 已经答过 + 还没到 hard → 别重复打扰
  if (acked && over < HARD) { console.log('  （已答心跳，等下一档）'); return; }

  let tier, text;
  if (over < HARD) { tier = 'SOFT'; text = msgSoft(st, min, budget); }
  else if (over < ROLLBACK) { tier = 'HARD'; text = msgHard(st, min, budget); }
  else { tier = 'ROLLBACK'; text = null; }

  if (tier === 'ROLLBACK') {
    // 三档：快照 + 记超时原因 + 轮回计划（不自动 next，先记着让人看见）
    const hbDir = path.join(ROOT, 'stager/.stager/tasks', st.id);
    const snap = path.join(hbDir, 'heartbeat-snapshot-' + Date.now() + '.json');
    try {
      fs.writeFileSync(snap, JSON.stringify({ at: new Date().toISOString(), stage: st.stage, round: st.round, elapsedMin: min, budget, reason: 'timeout>ROLLBACK' }, null, 1), 'utf8');
      console.log('  ★ ROLLBACK 已快照: ' + snap);
    } catch (e) { console.log('  ★ ROLLBACK 快照失败: ' + e.message); }
    // 只记，不自动轮回 —— 自动 next 会毁掉当前轮的工作，让 AI 自己决定
    const msg = [
      '[HEARTBEAT 超时上限 · 不是用户指令]',
      `【${STAGE_CN[st.stage] || st.stage}】已超时 ${min} 分钟（预算 ${budget}，上限 ${budget + ROLLBACK}）。`,
      '',
      '★ 这已经超出容忍范围了。多半是「迷失在局部」（长上下文里打转）。',
      '  已自动快照到：' + snap,
      '',
      '你有两个选择，选一个并执行：',
      '  A) 判定为卡死 → 跑 `stager loop --note "心跳判定超时+<原因>"` 回计划阶段重排',
      '  B) 判定为仍在有效推进 → 跑 hb-ack 带 --status ok --next "<为什么还需要时间>"，本轮放宽到再 +20 分钟',
      '',
      '  node "E:\\restart developing doer\\stager\\bin\\stager.js" hb-ack --stage ' + st.stage + ' --elapsed ' + min + 'm --status <ok|looping|blocked|waiting_user> --next "<...>"',
    ].join('\n');
    const r = inject(msg);
    log('ROLLBACK stage=' + st.stage + ' elapsed=' + min + ' inject=' + r);
    return;
  }

  const r = inject(text);
  log(tier + ' stage=' + st.stage + ' round=' + st.round + ' elapsed=' + min + 'min budget=' + budget + ' inject=' + r);
}

// ── 主 ────────────────────────────────────────────────────
if (LOOP) {
  console.log('stage-heartbeat 常驻看门狗启动');
  console.log('  预算(分): ' + JSON.stringify(BUDGET));
  console.log('  三档: T+' + SOFT + ' 提醒 / T+' + HARD + ' 强制自检 / T+' + ROLLBACK + ' 快照+回退');
  console.log('  轮询: ' + INTERVAL + 's   dry=' + DRY);
  log('START pid=' + process.pid + ' interval=' + INTERVAL + ' dry=' + DRY);
  let n = 0;
  const run = () => {
    n++;
    try { tick(); }
    catch (e) { log('TICK-ERR ' + String(e.message).split('\n')[0]); console.log('  ERR ' + e.message); }
    setTimeout(run, INTERVAL * 1000);
  };
  run();
} else {
  tick();
}