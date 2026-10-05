/**
 * server.js —— stager 网页看板（零依赖 node:http）
 *
 *   node pet\server.js 8899     →  http://127.0.0.1:8899/
 *
 * 桌宠的网页版：宠物大图 + 阶段进度条 + 轮次 + 人次 + 门禁 + 文档清单。
 * 轮询 /api/state（1.5s），阶段变了自动换图。
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const PORT = parseInt(process.argv[2], 10) || 8899;
const PET = __dirname;
const ROOT = path.resolve(PET, '..');
// 决策引擎是纯函数模块，所有写都是 tmp+rename 原子替换 —— 所以看板能在**另一个进程**里
// 直接调 resolve()，不需要（也不该）去抢 stager.js 的 .lock。
const DECIDE = require(path.join(ROOT, 'bin', 'decide.js'));
const RUNTIME = path.join(ROOT, '.stager');
const IMAGES = path.join(PET, 'images');
const STAGES_FILE = path.join(ROOT, 'core', 'stages.json');

function readJson(p, d) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return d; } }

const TASKS_OF = (id) => path.join(RUNTIME, 'tasks', id);

function snapshot() {
  const def = readJson(STAGES_FILE, { stages: [], expressions: {}, expressionOrder: [] });
  const list = (def.stages || []).map((s, i) => Object.assign({}, s, { _i: i }));
  const files = fs.existsSync(IMAGES)
    ? fs.readdirSync(IMAGES).filter((n) => /\.(png|jpe?g|webp|gif)$/i.test(n)).sort()
    : [];
  const exprMap = {};
  const order = def.expressionOrder && def.expressionOrder.length
    ? def.expressionOrder
    : Object.keys(def.expressions || {});
  for (const e of order) {
    const meta = (def.expressions || {})[e];
    if (meta && meta.file && files.indexOf(meta.file) >= 0) exprMap[e] = meta.file;
  }
  if (files.length >= order.length && order.length) {
    for (let i = 0; i < order.length; i++) if (!exprMap[order[i]]) exprMap[order[i]] = files[i];
  }
  for (const e of order) if (!exprMap[e] && files.length) exprMap[e] = files[0];

  const id = readJson(path.join(RUNTIME, 'active.json'), null);
  let st = id ? readJson(path.join(RUNTIME, 'tasks', id, 'state.json'), null) : null;
  let docs = [];
  let need = [], have = [];
  if (st) {
    const man = readJson(path.join(RUNTIME, 'tasks', st.id, 'docs', 'manifest.json'), { docs: [] });
    docs = man.docs || [];
    const s = list.find((x) => x.id === st.stage) || {};
    const g = s.gate || {};
    for (const k of g.docs || []) {
      (docs.some((d) => d.kind === k && d.stage === st.stage && d.round === st.round) ? have : need).push('doc:' + k);
    }
    const key = st.round + ':' + st.stage;
    const marks = (st.marks || {})[key] || [];
    for (const c of g.cmds || []) (marks.indexOf(c) >= 0 ? have : need).push('cmd:' + c);
  }
  return {
    ok: true,
    now: new Date().toISOString(),
    stages: list,
    order: order,
    exprMap: exprMap,
    images: files,
    activeId: id,
    state: st,
    docs: docs.map((d) => ({ title: d.title, kind: d.kind, stage: d.stage, round: d.round, actor: d.actor, createdAt: d.createdAt, file: d.file })),
    gate: { ok: need.length === 0, need: need, have: have },
  };
}

const PAGE = fs.readFileSync(path.join(PET, 'index.html'), 'utf8');

/** 决策收件箱要的东西：待决策列表 + 已定列表 + 策略摘要。给看板弹窗用。 */
function decisionsView() {
  const id = readJson(path.join(RUNTIME, 'active.json'), null);
  if (!id) return { ok: true, activeId: null, policy: safePolicy(), pending: [], resolved: [] };
  let box = { items: [] };
  try { box = DECIDE.load(id); } catch (e) { /* 队列坏掉不该让看板整个挂 */ }
  const brief = (it) => ({
    id: it.id, title: it.title, risk: it.risk, riskLabel: it.riskLabel, why: it.why,
    context: it.context, options: it.options, status: it.status, forced: !!it.forced,
    conflict: !!it.conflict, soundedMechanical: it.soundedMechanical || null,
    raisedBy: it.raisedBy, raisedAt: it.raisedAt, stage: it.stage, round: it.round,
    chosen: it.chosen || null, chosenLabel: it.chosenLabel || null, note: it.note || '',
    resolvedAt: it.resolvedAt || null,
  });
  return {
    ok: true,
    activeId: id,
    policy: safePolicy(),
    pending: box.items.filter((x) => x.status === 'pending').map(brief),
    resolved: box.items.filter((x) => x.status !== 'pending').slice(-10).map(brief),
  };
}

/** 策略读不出来不能让看板 500 —— 返回一个「读不到」的对象，由前端明说。 */
function safePolicy() {
  try {
    const p = DECIDE.loadPolicy();
    return {
      ok: true,
      risks: Object.keys(p.risks).map((k) => ({ id: k, label: p.risks[k].label, means: p.risks[k].means })),
      never: (p.neverEscalate.patterns || []).map((x) => x.what),
      before: p.requireBeforeAsking || [],
    };
  } catch (e) {
    return { ok: false, why: e.message };
  }
}

function readBody(req) {
  return new Promise((resolve) => {
    let b = '';
    req.on('data', (c) => { b += c; if (b.length > 1e6) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(b || '{}')); } catch (e) { resolve(null); } });
  });
}

function send(res, code, obj) {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  const u = url.parse(req.url);
  if (u.pathname === '/api/state') {
    const s = snapshot();
    const d = decisionsView();
    s.decide = { pendingCount: d.pending.length, resolvedCount: d.resolved.length };
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(JSON.stringify(s));
  }
  // 决策收件箱：待决策 + 已定 + 策略
  if (u.pathname === '/api/decisions') {
    return send(res, 200, decisionsView());
  }
  // 用户拍板
  if (u.pathname === '/api/decide' && req.method === 'POST') {
    readBody(req).then((body) => {
      if (!body || !body.id) return send(res, 400, { ok: false, why: '请求体不对：要 { id, choice, note }' });
      const id = readJson(path.join(RUNTIME, 'active.json'), null);
      if (!id) return send(res, 409, { ok: false, why: '没有进行中的 stage 任务（.stager/active.json 是空的）' });
      const action = body.action === 'dismiss' ? 'dismiss' : 'resolve';
      const r = action === 'dismiss'
        ? DECIDE.dismiss(id, body.id, body.note || '', 'user')
        : DECIDE.resolve(id, body.id, body.choice, body.note || '', 'user');
      if (!r.ok) return send(res, 409, r);
      // docRev +1：让 opencode 插件下一轮看到「用户已决策」
      const sp = path.join(TASKS_OF(id), 'state.json');
      const stt = readJson(sp, null);
      if (stt) { stt.docRev = (stt.docRev || 0) + 1; stt.updatedAt = new Date().toISOString(); fs.writeFileSync(sp + '.tmp-' + process.pid, JSON.stringify(stt, null, 2), 'utf8'); fs.renameSync(sp + '.tmp-' + process.pid, sp); }
      return send(res, 200, { ok: true, action: action, docPath: r.docPath || null, file: r.file || null, item: r.item, decidedCount: decisionsView().resolved.length });
    });
    return;
  }
  if (u.pathname.indexOf('/img/') === 0) {
    const name = decodeURIComponent(u.pathname.slice(5));
    const p = path.join(IMAGES, name);
    if (p.indexOf(IMAGES) !== 0 || !fs.existsSync(p)) { res.writeHead(404); return res.end('no'); }
    const ext = path.extname(p).toLowerCase();
    const ct = ext === '.png' ? 'image/png' : ext === '.webp' ? 'image/webp' : ext === '.gif' ? 'image/gif' : 'image/jpeg';
    res.writeHead(200, { 'content-type': ct, 'cache-control': 'no-store' });
    return res.end(fs.readFileSync(p));
  }
  if (u.pathname === '/' || u.pathname === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(PAGE);
  }
  res.writeHead(404); res.end('no');
});

server.listen(PORT, '127.0.0.1', () => {
  process.stdout.write('stager 看板已起：http://127.0.0.1:' + PORT + '/\n');
  process.stdout.write('Ctrl+C 停。\n');
});
