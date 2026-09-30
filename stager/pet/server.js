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
const RUNTIME = path.join(ROOT, '.stager');
const IMAGES = path.join(PET, 'images');
const STAGES_FILE = path.join(ROOT, 'core', 'stages.json');

function readJson(p, d) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return d; } }

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

const server = http.createServer((req, res) => {
  const u = url.parse(req.url);
  if (u.pathname === '/api/state') {
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(JSON.stringify(snapshot()));
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
