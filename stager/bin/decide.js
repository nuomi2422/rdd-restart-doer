/**
 * decide.js —— stager 的「决策收件箱」引擎（纯函数，不碰 stager.js 的锁）
 *
 * 干的事：把「AI 遇到需要人拍板的事」变成一个**可点击的窗口 + 一份落盘的文档**。
 *
 *   AI 侧  stager decide add "<标题>" --risk high-arch --why "为什么必须你定" --opt "A|标签|推荐|后果" --opt "B|..."
 *   人侧  看板（stager web，8899）上的「决策收件箱」按钮 → 弹窗 → 点一个选项
 *   存   选完立刻写 docs/NN-决策-<id>-<slug>.md + 登记 manifest（kind=decision）
 *   AI   下次开口被告知「用户已决策：D-1 选了 A」，附文档路径
 *
 * ★ 为什么要单独一个文件：stager.js 已经有 1860 行，再塞进去只会更难读。
 *   这里只管读写 decisions.json 和策略判据，**加锁/状态机留在 stager.js**。
 *   注意 pet/server.js（看板）会在**另一个进程**里直接调 resolve()，
 *   所以所有写都是「tmp + rename」原子替换，不依赖 stager 的 .lock。
 *
 * ★ 最重要的一条设计决定（2026-10-05 用户定）：
 *   **只有极高架构决策和高风险才许问用户；简单机械的技术性问题一律自己定。**
 *   这不是建议，是 add() 里的硬拦 —— 命中 neverEscalate 的关键词直接 die，
 *   并把它自己该做的建议打出来。--force 能强行入队，但会被标 forced、
 *   在看板上显示 ⚠，在文档里也会留痕。**不许悄悄问。**
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const RUNTIME = path.join(ROOT, '.stager');
const TASKS = path.join(RUNTIME, 'tasks');
const POLICY_FILE = path.join(ROOT, 'core', 'decide-policy.json');
const ACTIVE_FILE = path.join(RUNTIME, 'active.json');

const RISKS = ['high-arch', 'high-risk'];

function readJson(p, dflt) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return dflt; } }

/** tmp 名带 pid+随机 —— 看板和 CLI 可能是两个进程同时在写，用同一个 tmp 名会互相踩。 */
function writeJsonAtomic(p, obj) {
  const tmp = p + '.tmp-' + process.pid + '-' + Math.random().toString(36).slice(2, 8);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2), 'utf8');
  try { fs.renameSync(tmp, p); }
  catch (e) { try { fs.unlinkSync(tmp); } catch (_) { /* ignore */ } throw e; }
}

function loadPolicy() {
  const p = readJson(POLICY_FILE, null);
  if (!p || !p.neverEscalate || !p.risks) {
    throw new Error('决策策略读不到：' + POLICY_FILE + '\n  这是「什么才配问用户」的唯一真源，不能缺。');
  }
  return p;
}

function activeId() { return readJson(ACTIVE_FILE, null); }
function taskDir(id) { return path.join(TASKS, id); }
function decisionsPath(id) { return path.join(taskDir(id), 'decisions.json'); }
function docsDir(id) { return path.join(taskDir(id), 'docs'); }
function manifestPath(id) { return path.join(docsDir(id), 'manifest.json'); }

function load(id) {
  const j = readJson(decisionsPath(id), null);
  return (j && Array.isArray(j.items)) ? j : { items: [] };
}

function save(id, box) { writeJsonAtomic(decisionsPath(id), box); }

function nextId(box) {
  let max = 0;
  for (const it of box.items) {
    const m = /^D-(\d+)$/.exec(String(it.id || ''));
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  return 'D-' + (max + 1);
}

/** 「列了几个待决策」—— 看板按钮上的红点数字就取这个 */
function pending(id) { return load(id).items.filter((x) => x.status === 'pending'); }

function get(id, did) { return load(id).items.find((x) => x.id === did) || null; }

// ---------------------------------------------------------------- 判据

/**
 * 这件事配不配问用户？
 * 返回 { escalate, risk, matched[], stakes[], conflict, advice[] }
 *
 * ★ 两层判据，顺序不能反（2026-10-05 踩过）：
 *   先看 riskSignals（客观高风险：删东西/动钱/跨仓改契约/不可逆）→ 命中就【放行】。
 *   没命中风险信号，才看 neverEscalate（机械性问题）→ 命中就【拦下】。
 *
 *   为什么风险信号优先：纯关键词匹配会误杀用户最想拍板的题。
 *   「这三个模块要不要合并成一个」含「合并」、「重构边界怎么划」含「重构」——
 *   那是极高架构决策，不能因为用词像机械题就拦掉。客观风险比主观措辞可靠。
 *   两者都命中 → 放行，但标 conflict=true，文档和看板会显示 ⚠ 提醒人确认。
 *
 * ★ matched 非空 = 命中「绝对不许问」。这是拦人用的，不是提示用的。
 */
function judge(title, why, policy) {
  const text = [title, why || ''].join(' ');
  const scan = (pats) => {
    const out = [];
    for (const p of pats) {
      let re;
      try { re = new RegExp(p.re, 'i'); } catch (e) { continue; }
      if (re.test(text)) out.push({ what: p.what, re: p.re, risk: p.risk });
    }
    return out;
  };
  const stakes = scan((policy.riskSignals && policy.riskSignals.patterns) || []);
  const matched = scan(policy.neverEscalate.patterns);
  const escalate = stakes.length > 0 || matched.length === 0;
  return {
    escalate: escalate,
    risk: stakes.length ? stakes[0].risk : null,
    stakes: stakes,
    matched: matched,
    conflict: stakes.length > 0 && matched.length > 0,
    advice: policy.requireBeforeAsking || [],
  };
}

// ---------------------------------------------------------------- 入队

/**
 * 加一条待决策。
 * opts: { id, title, risk, why, context, options:[{id,label,recommended,consequence}], actor, forced, round, stage }
 *
 * 抛错而不是返回 false —— 调用方（CLI / 看板）直接把 message 打给用户看。
 * 错误文案必须说清「为什么被拒 + 你自己该做什么」，不能只说「不许问」。
 */
function add(id, opts) {
  const policy = loadPolicy();
  const title = String(opts.title || '').trim();
  if (!title) throw new Error('没有标题。stager decide add "<要你拍板的那件事>"');
  const why = String(opts.why || '').trim();
  const risk = String(opts.risk || '');
  const forced = !!opts.forced;

  const j = judge(title, why, policy);
  if (!j.escalate && !forced) {
    const whys = j.matched.map((m) => '· ' + m.what + '（匹配 /' + m.re + '/）').join('\n');
    const adv = j.advice.map((a, i) => (i + 1) + ') ' + a).join('\n');
    const e = new Error([
      '✘ 这件事不该问用户 —— 已拦下。命中「绝对不许问」：',
      whys,
      '',
      '「' + title + '」属于机械性技术问题，你自己定，然后写进文档说明你定了什么、为什么。',
      '',
      '★ 问用户之前必须先做完这些：',
      adv,
      '',
      '确实要问（认为我判错了）：加 --force，会被标 forced 并在看板上显示 ⚠，决策文档里也会留痕。',
      '★ 或者先判一下：stager decide why "' + title + '"',
    ].join('\n'));
    e.code = 'DECIDE_NEVER_ESCALATE';
    e.matched = j.matched;
    throw e;
  }

  if (!RISKS.includes(risk)) {
    const hint = j.risk ? ('（判据推测你大概该用 --risk ' + j.risk + '，但请自己确认）') : '';
    const e = new Error('必须写 --risk，取值只有 ' + RISKS.join(' | ') + '（其它类别一律不许问用户）。' + hint + '\n' +
      '  high-arch = 极高架构决策：定了之后很难回滚，别的设计都要跟着改\n' +
      '  high-risk = 高风险：做错了会丢东西 / 花钱 / 动安全 / 影响用户');
    e.code = 'DECIDE_BAD_RISK';
    throw e;
  }
  if (why.length < 10) {
    const e = new Error('--why 太短。用户凭什么判断？至少写清：影响面 / 两条路的代价 / 不决定会怎样。');
    e.code = 'DECIDE_WHY_TOO_SHORT';
    throw e;
  }

  const options = (opts.options || []).filter((o) => o && o.label);
  if (options.length < 2) {
    const e = new Error('至少给 2 个选项。只列一个选项等于没让人选 —— 那是你已经决定了，不需要问。');
    e.code = 'DECIDE_NEEDS_2_OPTIONS';
    throw e;
  }
  const withId = options.map((o, i) => ({
    id: o.id || String.fromCharCode(65 + i),
    label: String(o.label),
    recommended: !!o.recommended,
    consequence: String(o.consequence || ''),
  }));

  const box = load(id);
  const now = new Date().toISOString();
  const item = {
    id: nextId(box),
    title: title,
    risk: risk,
    riskLabel: (policy.risks[risk] || {}).label || risk,
    why: why,
    context: String(opts.context || ''),
    options: withId,
    status: 'pending',
    raisedBy: opts.actor || 'ai',
    raisedAt: now,
    stage: opts.stage || null,
    round: opts.round != null ? opts.round : null,
    forced: forced || undefined,
    conflict: j.conflict || undefined,   // 同时命中风险信号和机械措辞 → 文档/看板显示 ⚠
    soundedMechanical: j.matched.length ? j.matched.map((m) => m.what) : undefined,
  };
  box.items.push(item);
  save(id, box);
  return item;
}

// ---------------------------------------------------------------- 落盘成文档

function slug(s) {
  // 和 stager.js 的 slug 保持同一套口径：只留安全字符，中文保留（Windows 文件名合法）
  return String(s).replace(/[\\/:*?"<>|]/g, '').replace(/\s+/g, '-').slice(0, 60) || 'untitled';
}

function renderDoc(item, policy) {
  const L = [];
  L.push('# 决策 ' + item.id + ' · ' + item.title);
  L.push('');
  L.push('> 由 stager 决策收件箱自动落盘（用户在看板上点的）。**这条是决策记录，不是过程文档。**');
  L.push('');
  L.push('| 项 | 值 |');
  L.push('|---|---|');
  L.push('| 决策 id | `' + item.id + '` |');
  L.push('| 类别 | **' + (item.riskLabel || item.risk) + '**（`' + item.risk + '`） |');
  L.push('| 提出 | ' + (item.raisedBy || 'ai') + '　' + (item.raisedAt || '').replace('T', ' ').slice(0, 19) + ' |');
  if (item.stage) L.push('| 阶段 / 轮 | ' + item.stage + ' / ' + (item.round != null ? item.round : '?') + ' |');
  L.push('| 提出时状态 | ' + (item.status === 'resolved' ? '✔ 用户已拍板' : item.status) + ' |');
  if (item.forced) L.push('| ⚠ 强制入队 | 是（AI 认为我判错了，用 --force 硬塞进来的） |');
  if (item.conflict) {
    L.push('| ⚠ 措辞像机械题 | 命中了「绝对不许问」里的：' + (item.soundedMechanical || []).join('、') + ' —— 但也命中了客观风险信号，所以放行了。**请你确认它真有这么高风险。** |');
  }
  L.push('');
  L.push('## 为什么要你决定');
  L.push('');
  L.push(item.why);
  L.push('');
  if (item.context) {
    L.push('## 背景');
    L.push('');
    L.push(item.context);
    L.push('');
  }
  L.push('## 当时的选项');
  L.push('');
  item.options.forEach((o) => {
    const mark = item.chosen === o.id ? ' ← **★ 用户选了这个**' : '';
    L.push('### ' + o.id + '. ' + o.label + (o.recommended ? '　（AI 推荐）' : '') + mark);
    L.push('');
    L.push(o.consequence || '（没写后果 —— 这是 AI 该补的）');
    L.push('');
  });
  if (item.status === 'resolved') {
    L.push('## 用户的决定');
    L.push('');
    L.push('**选了 `' + item.chosen + '` · ' + (item.chosenLabel || '') + '**　于 ' +
      (item.resolvedAt || '').replace('T', ' ').slice(0, 19));
    L.push('');
    if (item.note) { L.push('补充说明：' + item.note); L.push(''); }
    L.push('> ★ AI 的义务：这条决定**覆盖你之前的任何倾向**。除非发现事实与决策时的假设不符，不要再改主意；');
    L.push('> 如果确实必须改，先说明「哪一条假设不成立了」，再重新走一次 `stager decide add`。');
    L.push('');
  }
  L.push('---');
  L.push('');
  L.push('_由 `stager decide` 落盘 · 策略真源 `core/decide-policy.json`_');
  return L.join('\n') + '\n';
}

/**
 * 用户拍板 → 立刻存成文档 + 登记 manifest。
 * 返回 { ok, docPath, file, item }；不在队列 / 不是 pending 时返回 { ok:false, why }（不抛 —— 看板要显示原因）。
 */
function resolve(id, did, choice, note, actor) {
  const box = load(id);
  const item = box.items.find((x) => x.id === did);
  if (!item) return { ok: false, why: '队列里没有 ' + did + ' 这条（可能已经被人选过了 —— 刷新看看）' };
  if (item.status !== 'pending') {
    return { ok: false, why: did + ' 已经是「' + item.status + '」状态，不能再选。刷新看看是不是别人已经拍过板了。' };
  }
  const opt = item.options.find((o) => o.id === choice);
  if (!opt) {
    return { ok: false, why: '选项 ' + choice + ' 不存在。这条有：' + item.options.map((o) => o.id).join(' / ') };
  }

  item.status = 'resolved';
  item.chosen = opt.id;
  item.chosenLabel = opt.label;
  item.note = String(note || '');
  item.resolvedAt = new Date().toISOString();
  item.resolvedBy = actor || 'user';

  // 文档 + manifest：跟 stager put 同一套约定（NN-<slug>.md，登记进 manifest.json）
  const man = readJson(manifestPath(id), { docs: [] });
  man.docs = man.docs || [];
  const n = man.docs.length + 1;
  const fname = String(n).padStart(2, '0') + '-决策-' + item.id + '-' + slug(item.title) + '.md';
  fs.mkdirSync(docsDir(id), { recursive: true });
  fs.writeFileSync(path.join(docsDir(id), fname), renderDoc(item, loadPolicy()), 'utf8');
  man.docs.push({
    id: 'd' + n, title: '决策 ' + item.id + ' · ' + item.title, kind: 'decision',
    stage: item.stage || null, round: item.round != null ? item.round : null,
    actor: item.resolvedBy, file: fname, createdAt: item.resolvedAt, from: 'decide-inbox',
  });
  writeJsonAtomic(manifestPath(id), man);

  save(id, box);
  return { ok: true, docPath: path.join(docsDir(id), fname), file: fname, item: item };
}

/** 撤回：人说不算（AI 提错了 / 前提变了）。也留痕。 */
function dismiss(id, did, reason, actor) {
  const box = load(id);
  const item = box.items.find((x) => x.id === did);
  if (!item) return { ok: false, why: '队列里没有 ' + did };
  item.status = 'dismissed';
  item.note = String(reason || '');
  item.resolvedAt = new Date().toISOString();
  item.resolvedBy = actor || 'user';
  save(id, box);
  return { ok: true, item: item };
}

/**
 * 「用户已决策」的通知单 —— 给 AI 看的。
 * ★ since 参数是 ISO 时间：只报「上次问完之后才解决掉的」，避免每轮重复报同一件事。
 */
function resolvedSince(id, since) {
  const t = since ? Date.parse(since) : 0;
  return load(id).items.filter((x) => x.status === 'resolved' && (!t || Date.parse(x.resolvedAt || 0) > t));
}

// ---------------------------------------------------------------- 渲染（CLI 用）

function renderMd(id, only) {
  const box = load(id);
  const items = only ? box.items.filter((x) => x.status === only) : box.items;
  const L = [];
  if (!items.length) {
    L.push(only === 'pending' ? '（没有待决策）' : '（空）');
    return L.join('\n');
  }
  items.forEach((it) => {
    const tag = it.status === 'pending' ? '● 待决策' :
      it.status === 'resolved' ? '✔ 已定' : '✘ 已撤回';
    L.push(tag + '  ' + it.id + '  [' + (it.riskLabel || it.risk) + ']' + (it.forced ? ' ⚠强制入队' : '') + '  ' + it.title);
    L.push('    为什么必须你定：' + it.why);
    it.options.forEach((o) => {
      L.push('      ' + o.id + (o.recommended ? ' ★推荐' : '     ') + ' ' + o.label +
        (o.consequence ? '　→ ' + o.consequence : '') + (it.chosen === o.id ? '　← 已选' : ''));
    });
    if (it.note) L.push('    补充：' + it.note);
    L.push('');
  });
  return L.join('\n');
}

module.exports = {
  ROOT: ROOT,
  RISKS: RISKS,
  POLICY_FILE: POLICY_FILE,
  loadPolicy: loadPolicy,
  activeId: activeId,
  load: load,
  save: save,
  pending: pending,
  get: get,
  judge: judge,
  add: add,
  resolve: resolve,
  dismiss: dismiss,
  resolvedSince: resolvedSince,
  renderMd: renderMd,
  slug: slug,
};