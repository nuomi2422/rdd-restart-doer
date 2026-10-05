/**
 * model-router.mjs —— opencode 插件：AI 自己挑模型 + 每个模型每小时限额
 *
 * 干两件事：
 *  1) 注册一个工具 `model_router`，AI 遇到难问题就调它把活派给更强的模型（默认 gpt-6-sol / astra，
 *     稍难的问题先问 DeepSeek），拿到方案后自己（免费档）继续写代码。
 *  2) 读 model-budget.json 给每个模型算「本地整点桶」配额，超了自动降级到下一档，
 *     全部超完就**明确报错**（不静默、不假装成功）。
 *
 * 装：把下面这行加进 ~/.config/opencode/opencode.json 的 plugin 数组，然后重启 opencode（配置不热重载）
 *   "plugin": ["file:///E:/restart developing doer/opencode-plugin/model-router.mjs"]
 *
 * ★ 为什么要开子会话而不是直接改当前会话的模型：
 *   opencode 的 `chat.params` 钩子能改 temperature / maxOutputTokens，但**改不了 model**（官方类型
 *   定义 Hooks["chat.params"].output 里只有那 5 个字段）。会话的模型由发 prompt 时带的
 *   model 决定（SDK SessionPromptData.body.model = {providerID, modelID}）。
 *   所以「换模型」唯一可靠的姿势就是：用 SDK 自己发一条带 model 的 prompt。
 *   为了不在当前正在生成的回合里插一条同会话消息（会和外层回合抢状态），本插件开**子会话**
 *   （parentID = 当前会话），子会话跑完后把正文作为工具输出交回外层。外层上下文一个 token 都不乱。
 *
 * ★ opencode 只认导出名 `server`（PluginModule = { id?, server: Plugin, tui?: never }）。
 *   2026-10-02 已在 stager 插件上踩过一次：导出了 default 却被判 "Plugin export is not a function"。
 */

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const BUDGET_FILE = path.join(HERE, 'model-budget.json')
const STATE_DIR = path.join(HERE, '.state')
const USAGE_FILE = path.join(STATE_DIR, 'model-usage.json')

/**
 * zod 必须从 opencode 自己的 node_modules 里取。
 * 本文件住在工作区（要进 git），Node 从这里往上找不到 ~/.config/opencode/node_modules/zod。
 * 用 createRequire 挂在 opencode 的 package.json 上，是跟着配置目录走的最短路径。
 */
const requireFromOpencode = createRequire(path.join(os.homedir(), '.config', 'opencode', 'package.json'))
const { z } = requireFromOpencode('zod')

const MARKER = '## ▶ 模型路由 · model-router'

/** 委派中的子会话。防止子会话里的模型再调 model_router 自己套自己（无限递归）。 */
const inFlight = new Set()

/**
 * ★ 被本插件开出来的子会话（永远要用完）。
 *   用途不是防递归 —— 递归已经由 inFlight 拦了 —— 而是**不让 chat.message 往子会话里注入**。
 *   2026-10-05 首次真机委派就踩到：子会话是全新 session，chat.message 照样触发，
 *   于是我这段「模型路由 + 额度表」被拼在了**委派 prompt 的最前面**，
 *   目标模型第一眼看到的是额度表而不是问题；deepseek 那次返回空正文，很可能就是这么来的。
 *   子会话的注入对谁都没用 —— 它只活一轮，没人会在第二轮问它额度。
 */
const childSessions = new Set()

/**
 * ★ 注入的 text part 必须自带 id / sessionID / messageID，否则 opencode 存不下去。
 *
 * 2026-10-05 实测（首跑就抓到，日志里一片 ERROR）：
 *   `invalid user part before save ... SchemaError: Missing key at ["id"] / ["sessionID"] / ["messageID"]`
 *   —— push 一个光秃秃的 `{type:'text', text}` 进去，opencode 在落库前校验就拒了。
 *   症状很阴险：**当轮模型看得到**（所以你以为它在起作用），但**不写进历史**，
 *   下一轮就没了；日志里只有一条条 ERROR，没人翻。
 *   （stager-plugin.mjs 是同一个写法，它注入的 ctx 大概也有同样的毛病 —— 但我没查过，不下结论。）
 *
 * part id 用 opencode 自己的前缀风格 `prt_` + 30 位小写 base36。
 * 拿不准格式时宁可多带字段 —— 多带的会被 zod 剥掉，少带的会被整条拒掉。
 */
function makePart(input, text) {
  const rid = () => Math.random().toString(36).slice(2, 10)
  return {
    id: 'prt_' + rid() + rid() + rid(),
    sessionID: input.sessionID,
    messageID: input.messageID || '',
    type: 'text',
    text: String(text),
  }
}

/** 同一个进程内：sessionID -> 已经注入过的状态指纹（同一小时同一额度状态只注入一次） */
const injected = new Map()

// ============================================================
// 配置 / 状态
// ============================================================

const FALLBACK = {
  version: 1,
  defaultTimeoutMs: 900000,
  contextMessages: 12,
  contextChars: 6000,
  maxReturnChars: 12000,
  escalateOrder: ['deepseek', 'sol', 'astra'],
  tiers: [
    { id: 'free', label: '免费档', model: { providerID: 'opencode', modelID: 'big-pickle' } },
    { id: 'deepseek', label: 'DeepSeek', model: null, matchModels: ['deepseek'], preferProviders: ['openrouter'] },
    { id: 'sol', label: 'gpt-6-sol', model: { providerID: 'moyuu', modelID: 'gpt-6-sol' } },
    { id: 'astra', label: 'gpt-6-astra', model: { providerID: 'moyuu', modelID: 'gpt-6-astra' } },
  ],
  hourly: {},
  planModeToolsOff: ['write', 'edit', 'patch', 'apply_patch', 'bash', 'task', 'todowrite', 'todoread'],
}

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')) }
  catch { return fallback }
}

/** 配置文件读坏了不能把对话搞崩，但也不能默默用默认值 —— 打一行 stderr。 */
function loadBudget() {
  const b = readJson(BUDGET_FILE, null)
  if (!b || !Array.isArray(b.tiers)) {
    console.error('[model-router] model-budget.json 读不到或格式不对，本轮用内置兜底额度。file=' + BUDGET_FILE)
    return { ...FALLBACK }
  }
  return { ...FALLBACK, ...b }
}

/** 本地整点桶 key，例如 2026-10-05T14。整点一到自动换一个空桶 = 自动清零。 */
function hourKey(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}`
}

function loadUsage() {
  const u = readJson(USAGE_FILE, null)
  if (!u || typeof u !== 'object') return { hours: {} }
  if (!u.hours) u.hours = {}
  return u
}

/** 写状态：先写临时文件再 rename，避免进程被杀时留下半个 JSON（半个 JSON = 额度账丢失 = 门禁形同虚设）。 */
function saveUsage(u) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true })
    const tmp = USAGE_FILE + '.tmp'
    fs.writeFileSync(tmp, JSON.stringify(u, null, 2))
    fs.renameSync(tmp, USAGE_FILE)
  } catch (e) {
    console.error('[model-router] 用量状态写不进去（额度会不准）：' + e.message)
  }
}

function bucket(u, hk, tier) {
  const h = (u.hours[hk] = u.hours[hk] || {})
  const t = (h[tier] = h[tier] || { ms: 0, calls: 0, chars: 0, errors: 0 })
  if (typeof t.ms !== 'number') t.ms = 0
  if (typeof t.calls !== 'number') t.calls = 0
  if (typeof t.chars !== 'number') t.chars = 0
  if (typeof t.errors !== 'number') t.errors = 0
  return t
}

/** 只保留最近 8 个整点桶，别让状态文件无限长。 */
function prune(u, hk) {
  const keys = Object.keys(u.hours).sort()
  while (keys.length > 8) delete u.hours[keys.shift()]
  if (!u.hours[hk]) return
}

// ============================================================
// 额度判据
// ============================================================

function tierOf(cfg, id) { return cfg.tiers.find((t) => t.id === id) || null }

/**
 * 这一档现在还能用吗？不能就返回一句「为什么不能」——这句话会原样进工具输出，
 * AI 和用户都能看到。额度门禁必须**响**，静默降级等于骗人。
 */
function check(cfg, usage, hk, tierId) {
  const t = tierOf(cfg, tierId)
  if (!t) return { ok: false, why: `没有这一档：${tierId}。可用档位 = ${cfg.tiers.map((x) => x.id).join(' / ')}` }
  const lim = cfg.hourly?.[tierId]
  if (!lim) return { ok: false, why: `model-budget.json 的 hourly 里没有 ${tierId} 这一档 —— 不允许调（怕漏配＝无限花钱）。加一行 hourly.${tierId} 才会启用。` }
  if (lim.enabled === false) return { ok: false, why: `${tierId} 在 model-budget.json 里被 enabled=false 关掉了。` }

  const used = bucket(usage, hk, tierId)
  const mins = used.ms / 60000
  if (lim.maxMinutesPerHour != null && mins >= lim.maxMinutesPerHour) {
    return { ok: false, why: `${tierId} 本小时已用 ${mins.toFixed(1)} 分钟，达到上限 ${lim.maxMinutesPerHour} 分钟（本小时桶 ${hk}）。` }
  }
  if (lim.maxCallsPerHour != null && used.calls >= lim.maxCallsPerHour) {
    return { ok: false, why: `${tierId} 本小时已调 ${used.calls} 次，达到上限 ${lim.maxCallsPerHour} 次（桶 ${hk}）。` }
  }
  if (lim.maxCharsPerHour != null && used.chars >= lim.maxCharsPerHour) {
    return { ok: false, why: `${tierId} 本小时已产出 ${used.chars} 字符，达到上限 ${lim.maxCharsPerHour}（桶 ${hk}）。` }
  }
  return { ok: true, used, lim, remaining: remainingText(lim, used) }
}

function remainingText(lim, used) {
  const out = []
  if (lim.maxMinutesPerHour != null) out.push(`${Math.max(0, lim.maxMinutesPerHour - used.ms / 60000).toFixed(1)}/${lim.maxMinutesPerHour} 分钟`)
  if (lim.maxCallsPerHour != null) out.push(`${Math.max(0, lim.maxCallsPerHour - used.calls)}/${lim.maxCallsPerHour} 次`)
  if (lim.maxCharsPerHour != null) out.push(`${Math.max(0, lim.maxCharsPerHour - used.chars)}/${lim.maxCharsPerHour} 字符`)
  return out.length ? out.join('，') : '不限'
}

/** 额度总表。status / 注入正文 / 报错文案共用一份口径。 */
function table(cfg, usage, hk) {
  return cfg.tiers.map((t) => {
    const lim = cfg.hourly?.[t.id]
    const used = bucket(usage, hk, t.id)
    const st = !lim ? '未配置(禁用)' : lim.enabled === false ? '已关' : check(cfg, usage, hk, t.id).ok ? '可用' : '超限'
    return `- \`${t.id}\` ${t.label} —— ${st}｜已用 ${(used.ms / 60000).toFixed(1)} 分钟 / ${used.calls} 次${used.errors ? ` / 失败 ${used.errors}` : ''}｜本小时额度 ${lim ? remainingText(lim, used) : '—'}`
  })
}

/** auto：从便宜到贵找第一个还有额度的。找不到就把每一档的理由全部抛出来。 */
function pick(cfg, usage, hk, requested) {
  if (requested && requested !== 'auto') {
    const r = check(cfg, usage, hk, requested)
    return { tier: r.ok ? requested : null, why: r.ok ? null : r.why }
  }
  const tried = []
  for (const id of cfg.escalateOrder) {
    const r = check(cfg, usage, hk, id)
    if (r.ok) return { tier: id, why: null, skipped: tried }
    tried.push(r.why)
  }
  return { tier: null, why: `本小时所有档位都用完了，降级链 = ${cfg.escalateOrder.join(' → ')}：\n${tried.map((x) => '  ✗ ' + x).join('\n')}`, skipped: tried }
}

// ============================================================
// 模型解析
// ============================================================

/** match 项支持普通子串（忽略大小写）或 "/正则/flags"。 */
function matches(id, pats) {
  return (pats || []).some((p) => {
    const m = /^\/(.*)\/([gimsuy]*)$/.exec(String(p))
    if (m) return new RegExp(m[1], m[2]).test(id)
    return id.toLowerCase().includes(String(p).toLowerCase())
  })
}

/**
 * 解析成 {providerID, modelID}。
 * model 字段写死了就直接用；写 null 就现场从 provider.list() 里按 matchModels 找。
 * 找不到 → 抛错并把「所有可用模型 id（截断）」列出来，绝不静默换一个凑合的。
 */
async function resolveModel(client, cfg, tierId) {
  const t = tierOf(cfg, tierId)
  if (t.model) return { model: t.model, via: 'model-budget.json 写死' }

  let all = []
  try {
    const res = await client.provider.list()
    all = res?.data?.all || []
  } catch (e) {
    throw new Error(`拉 provider 列表失败，无法解析 ${tierId} 的模型：${e.message}`)
  }

  const preferP = t.preferProviders || []
  const preferM = t.preferModelIds || []
  const cands = []
  for (const p of all) {
    for (const mid of Object.keys(p.models || {})) {
      if (!matches(mid, t.matchModels)) continue
      let score = 0
      if (preferP.includes(p.id)) score += 1000
      if (preferM.some((x) => mid.toLowerCase().includes(String(x).toLowerCase()))) score += 500
      if (mid.includes(':free')) score -= 50
      cands.push({ providerID: p.id, modelID: mid, score })
    }
  }
  if (!cands.length) {
    const have = all.flatMap((p) => Object.keys(p.models || {}).map((m) => p.id + '/' + m))
    throw new Error(
      `解析不到 ${tierId} 的模型：匹配规则 matchModels=${JSON.stringify(t.matchModels)} 在已配置的 provider 里一个都没命中。\n` +
      `当前可用模型共 ${have.length} 个，前 40 个：\n${have.slice(0, 40).map((x) => '  ' + x).join('\n') || '  （一个都没有 —— provider 是不是没配 key？）'}\n` +
      `修法二选一：① 在 opencode.json 配上有该模型的 provider；② 把 model-budget.json 里 tiers.${tierId}.matchModels 改成实际存在的 id 子串。`
    )
  }
  cands.sort((a, b) => b.score - a.score || a.modelID.localeCompare(b.modelID))
  return { model: { providerID: cands[0].providerID, modelID: cands[0].modelID }, via: `按 matchModels 现场解析（${cands.length} 个候选，取分最高）`, candidates: cands.slice(0, 6) }
}

// ============================================================
// 正文抽取 / 上下文打包
// ============================================================

function textOf(parts) {
  return (parts || [])
    .filter((p) => p.type === 'text' && typeof p.text === 'string')
    .map((p) => p.text)
    .join('\n')
    .trim()
}

/**
 * ★ 取正文，取不到就说清楚「到底返回了什么」，别只说「空的」。
 *
 * 为什么不用 textOf 一把梭：2026-10-05 首跑真机委派，deepseek 返回空正文。
 * 当时我只报了「parts 里没有 text」，等于把诊断成本推给下一次 —— 而下一次还要再烧一次额度。
 * 推理型模型（r1 / o 系列 / GLM 的思考模式）常常只吐 reasoning 就到头了，
 * 这时候**它其实说了话**，只是在 reasoning 字段里。所以：
 *   ① 先 text；② 空则收 reasoning；③ 还空 → 把 part 类型和长度列出来。
 * 这样下一次失败**一次就能定位**，这才是「失败要响」的真意思。
 */
function extract(parts) {
  const t = textOf(parts)
  if (t) return { text: t, from: 'text' }
  const reasoning = (parts || [])
    .filter((p) => (p.type === 'reasoning' || p.type === 'thinking') && typeof (p.text || p.thinking) === 'string')
    .map((p) => p.text || p.thinking)
    .join('\n')
    .trim()
  if (reasoning) return { text: reasoning, from: 'reasoning-only（这个模型只吐了思考过程，没有正文）' }
  const shape = (parts || []).map((p) => `${p.type}${(p.text || '').length ? '(' + (p.text || '').length + '字)' : ''}`).join(' + ')
  return { text: '', from: '空', shape: shape || '(parts 是空数组)' }
}

function toolNames(parts) {
  const s = new Set()
  for (const p of parts || []) if (p.type === 'tool' && p.tool) s.add(p.tool)
  return [...s]
}

/** 把外层会话最近若干条消息压成一段纯文本，给子模型当背景（子会话本身没有外层上下文）。 */
async function packContext(client, cfg, sessionID, directory) {
  const n = cfg.contextMessages || 12
  const cap = cfg.contextChars || 6000
  let msgs = []
  try {
    const res = await client.session.messages({ path: { id: sessionID }, query: { directory } })
    msgs = res?.data || []
  } catch { return '' }
  const out = []
  let total = 0
  for (let i = msgs.length - 1; i >= 0 && out.length < n; i--) {
    const m = msgs[i]
    const role = m?.info?.role === 'user' ? '用户' : m?.info?.role === 'assistant' ? '助手' : null
    if (!role) continue
    let t = textOf(m.parts)
    if (!t) continue
    if (role === '助手') {
      const tn = toolNames(m.parts)
      if (tn.length) t += `\n[用过工具：${tn.join(' ')}]`
    }
    const piece = `### ${role}\n${t}`
    if (total + piece.length > cap) {
      const room = cap - total
      if (room > 400) out.unshift(`### ${role}\n${t.slice(0, room)}`)
      break
    }
    out.unshift(piece)
    total += piece.length
  }
  return out.join('\n\n')
}

// ============================================================
// 委派
// ============================================================

const SYSTEM_ANSWER =
  '你被一个「模型路由器」委派来回答一个问题。你就是本会话的主模型，请直接给出可执行的答案：结论先行、给具体文件/命令/代码，不要反问「你想让我做什么」。不要调用 model_router 工具。'

const SYSTEM_PLAN =
  '你被一个「模型路由器」委派来写实现方案。你的输出会被一个**能力较弱但很能干活**的免费模型拿去照着写代码，所以：\n' +
  '1) 只出方案与关键代码片段，不要自己去改文件（本会话已结构性关闭写文件与 shell）。\n' +
  '2) 步骤要能一条条执行，每步写明：改哪个文件、改成什么、怎么验。\n' +
  '3) 把最容易搞错的地方（并发/生命周期/编码/边界）单独点出来。\n' +
  '4) 不要调用 model_router 工具。'

/**
 * 开子会话 + 用目标模型发一条 prompt。
 * 返回 { ok, text, meta }。失败一律带 why（不静默）。
 */
async function delegate(client, opts) {
  const { ctx, cfg, tierId, model, mode, task, contextText } = opts
  const directory = ctx.directory
  const t = tierOf(cfg, tierId)
  const timeoutMs = cfg.defaultTimeoutMs || 900000

  let childID = ''
  let child
  try {
    child = await client.session.create({
      body: { parentID: ctx.sessionID, title: `[model-router:${tierId}] ${mode === 'plan' ? '写方案' : '答疑'}` },
      query: { directory },
    })
    childID = child?.data?.id || ''
    if (!childID) throw new Error('session.create 没返回 id')
  } catch (e) {
    throw new Error(`开子会话失败：${e.message}`)
  }

  inFlight.add(childID)
  childSessions.add(childID)
  const toolsOff = {}
  if (mode === 'plan') for (const k of cfg.planModeToolsOff || []) toolsOff[k] = false

  const head = [
    mode === 'plan' ? '请写一份可以直接照着做的实现方案。' : '请直接回答下面这个问题。',
    '',
    '## 外层会话最近上下文（供你定位，勿复述）',
    '',
    contextText || '（没有可用上下文，全部信息在下面这段任务描述里）',
    '',
    '## 本次任务',
    '',
    task,
    '',
    '## 输出要求',
    '',
    mode === 'plan'
      ? '- 方案 + 关键代码片段 + 分步执行清单 + 易错点。不要客套，不要总结你做了什么。'
      : '- 结论先行，3~15 行。给出可直接粘贴的代码/命令。不要客套。',
  ].join('\n')

  const t0 = Date.now()
  let timedOut = false
  const run = client.session.prompt({
    path: { id: childID },
    query: { directory },
    body: {
      model,
      system: mode === 'plan' ? SYSTEM_PLAN : SYSTEM_ANSWER,
      parts: [{ type: 'text', text: head }],
      ...(Object.keys(toolsOff).length ? { tools: toolsOff } : {}),
    },
  })

  let res
  try {
    res = await Promise.race([
      run,
      new Promise((_, rej) => setTimeout(() => { timedOut = true; rej(new Error(`超时 ${Math.round(timeoutMs / 1000)} 秒`)) }, timeoutMs)),
    ])
  } catch (e) {
    // 超时/失败都要中止子会话，否则它还在后台烧额度
    try { await client.session.abort({ path: { id: childID }, query: { directory } }) } catch { /* 尽力而为 */ }
    inFlight.delete(childID)
    return { ok: false, ms: Date.now() - t0, chars: 0, childID, why: `${tierId}（${model.providerID}/${model.modelID}）${timedOut ? '超时' : '调用失败'}：${e.message}` }
  }
  inFlight.delete(childID)

  const ms = Date.now() - t0
  const parts = res?.data?.parts || []
  const got = extract(parts)
  let text = got.text
  const err = res?.data?.info?.error
  if (err) {
    return { ok: false, ms, chars: text.length, childID, why: `${tierId}（${model.providerID}/${model.modelID}）返回错误：${err.name || ''} ${err.data?.message || JSON.stringify(err)}` }
  }
  if (!text) {
    return {
      ok: false, ms, chars: 0, childID,
      why: `${tierId}（${model.providerID}/${model.modelID}）返回了空正文 —— **不当成成功**。\n` +
        `  parts 的实际构成：${got.shape}\n` +
        `  子会话：${childID}（可以进去看它到底干了什么）\n` +
        `  两种常见原因：① 这是个推理型模型，思考完就到头了没吐正文（换非 reasoning 模型或加大 maxOutputTokens）；\n` +
        `                ② 它把话都写进工具调用里去了，但 plan 模式把工具全关了。\n` +
        `  先看 status 确认额度，然后换个档位试（--force 不适用于这里）。`,
    }
  }

  const cap = cfg.maxReturnChars || 12000
  const clipped = text.length > cap
  if (clipped) text = text.slice(0, cap) + `\n\n…（超长已截断，原文 ${text.length} 字符，子会话 ${childID} 里还有全文）`

  const tn = toolNames(parts)
  const meta = [`档位 \`${tierId}\` = \`${model.providerID}/${model.modelID}\`（${t?.label || ''}）`, `耗时 ${(ms / 1000).toFixed(1)}s`, `子会话 \`${childID}\``]
  if (got.from !== 'text') meta.push(`⚠ 正文取自 ${got.from}`)
  if (tn.length) meta.push(`子模型用过的工具：${tn.join(' ')}`)

  return { ok: true, text, ms, chars: text.length, childID, clipped, meta }
}

// ============================================================
// 插件
// ============================================================

const TOOL_DESC = [
  '把一个难题派给更强的模型，然后把它的答案/方案原样拿回来继续干活（默认先问 DeepSeek，再 gpt-6-sol，最后 gpt-6-astra）。',
  '',
    '什么时候用：',
    '- 稍微有点难：一个文件说不清、要跨 3 个以上文件、或方案有明显取舍 —— 先 mode=plan 让 DeepSeek 出方案。',
    '- 难的代码 / 架构决策 / 深度审查 —— mode=plan to=sol 或 to=astra。',
    '- 纯粹的疑难问答（“这段为什么报错 / 这个 API 怎么用”）—— mode=ask to=deepseek。',
    '',
    '怎么用（重要）：',
    '- 只把「想清楚」外包出去，**写代码留在免费档自己写**。拿到方案就自己动手，不要把整个实现也派出去。',
    '- action=back（或 to=free）表示你已经切回免费档继续写，它只回一条策略提醒，不发请求。',
    '- 每个模型有每小时额度，超了插件会自动降级；全用完会明确报错，不会假装成功。',
    '- 子会话里不要再调本工具（插件已结构性拦截）。',
  ].join('\n')

export const ModelRouterPlugin = async ({ client }) => {
  return {
    tool: {
      model_router: {
        description: TOOL_DESC,
        args: {
          action: z.enum(['plan', 'ask', 'status', 'back']).default('plan')
            .describe('plan=让它写可照做的方案（推荐）；ask=让它直接答疑；status=看额度表；back=标记已切回免费档'),
          to: z.string().optional()
            .describe('目标档位：free / deepseek / sol / astra，或 auto（默认 auto = 按 deepseek→sol→astra 找第一个还有额度的）。一般不填，让插件自己挑。'),
          task: z.string().optional()
            .describe('要派出去的问题 / 需求。写清楚：目标是什么、已试过什么、卡在哪、涉及哪些文件。'),
          context: z.string().optional().describe('传 none 可以不带外层会话上下文，只给 task。默认带最近若干条。'),
        },
        async execute(args, ctx) {
          const cfg = loadBudget()
          const usage = loadUsage()
          const hk = hourKey()
          prune(usage, hk)

          if (inFlight.has(ctx.sessionID)) {
            // 子会话里又调了 —— 这是自己套自己，直接拒
            return { title: '拒绝', output: '你是被 model_router 委派出来的子会话，不能再委派。请直接回答外层给你的任务。' }
          }

          const action = args.action || 'plan'

          if (action === 'status') {
            const t = tierOf(cfg, args.to || '')
            if (args.to && t) {
              const c = check(cfg, usage, hk, t.id)
              return { title: `额度 ${t.id}`, output: `${t.label}\n状态：${c.ok ? '可用' : '不可用 —— ' + c.why}\n本小时（桶 ${hk}）：${c.ok ? c.remaining : '—'}\n\n全部档位：\n${table(cfg, usage, hk).join('\n')}` }
            }
            return { title: '额度总表', output: `本小时桶 \`${hk}\`（本地整点，到点自动清零）\n\n${table(cfg, usage, hk).join('\n')}` }
          }

          if (action === 'back' || args.to === 'free') {
            injected.delete(ctx.sessionID) // 让下一轮重新注入一次策略提醒
            return {
              title: '已回免费档',
              output: [
                '已记下：你回到**免费档**继续写代码。',
                '',
                '分工是固定的：**难的只是「想清楚」，难的从来不是「敲代码」**。',
                '所以：拿到方案后自己动手实现、写测试、跑门禁；不要把实现本身也派出去。',
                '',
                '下次真遇到想不清楚的（跨 3+ 文件 / 有取舍 / 报错看不懂），再 `model_router` 一次。',
              ].join('\n'),
            }
          }

          if (!args.task || !String(args.task).trim()) {
            return { title: '缺参数', output: '`task` 是空的 —— 没有要派出去的问题我什么也做不了。把你卡住的点写清楚（目标 / 已试过 / 卡在哪 / 涉及哪些文件），再调一次。' }
          }

          const picked = pick(cfg, usage, hk, args.to)
          if (!picked.tier) {
            return {
              title: '额度用完',
              output: [
                '**没能派出去。** 本小时额度全部用完，且我不会假装成功。',
                '',
                picked.why,
                '',
                '你可以选：① 等下一个整点（桶会自动清零）；② 调高 model-budget.json 里 hourly 的上限；③ 自己硬写。',
              ].join('\n'),
            }
          }

          let resolved
          try {
            resolved = await resolveModel(client, cfg, picked.tier)
          } catch (e) {
            return {
              title: '模型解析失败',
              output: [
                '**没能派出去：目标模型解析不出来。** 我不会随便换一个模型凑合。',
                '',
                e.message,
              ].join('\n'),
            }
          }

          const contextText = args.context === 'none' ? '' : await packContext(client, cfg, ctx.sessionID, ctx.directory)

          let r
          try {
            r = await delegate(client, { ctx, cfg, tierId: picked.tier, model: resolved.model, mode: action === 'plan' ? 'plan' : 'ask', task: String(args.task), contextText })
          } catch (e) {
            r = { ok: false, ms: 0, chars: 0, why: `委派过程抛异常：${e.message}` }
          }

          // 无论成功失败都记账：失败同样花了额度，不记就是让门禁漏账
          const b = bucket(usage, hk, picked.tier)
          b.ms += r.ms || 0
          b.calls += 1
          b.chars += r.chars || 0
          if (!r.ok) b.errors += 1
          saveUsage(usage)

          ctx.metadata?.({ title: `model_router ${picked.tier}`, metadata: { tier: picked.tier, model: `${resolved.model.providerID}/${resolved.model.modelID}`, ms: r.ms, ok: !!r.ok, childSession: r.childID } })

          if (!r.ok) {
            return {
              title: '委派失败',
              output: [
                `**${picked.tier} 这一档没成，不要当成已经拿到答案。**`,
                '',
                r.why,
                '',
                `已记账：${picked.tier} 本小时累计 ${(b.ms / 60000).toFixed(1)} 分钟 / ${b.calls} 次（失败也占额度）。`,
                '接下来：自己写，或换下一档重试（换档要先看 status）。',
              ].join('\n'),
            }
          }

          return {
            title: `${picked.tier} 已返回`,
            output: [
              `> ${r.meta.join('　·　')}`,
              ...(picked.skipped?.length ? [`> 更便宜的档位本小时已用完所以跳过：${picked.skipped.join(' / ')}`] : []),
              ...(resolved.via ? [`> 模型解析：${resolved.via}`] : []),
              '',
              r.text,
              '',
              '---',
              `**现在轮到你（免费档）动手。** 按上面的方案写代码、写测试、跑门禁；不要把实现也派出去。写完记得按工程纪律精确 add + 提交。`,
              `本小时额度：${picked.tier} 剩 ${(check(cfg, usage, hk, picked.tier).remaining || '—')}。`,
            ].join('\n'),
          }
        },
      },
    },

    /**
     * 每小时注入一次策略 + 额度快照。
     * 指纹 = 小时桶 + 三档是否还有额度 → 额度状态变了才重新注入，平时不刷屏。
     */
    'chat.message': async (input, output) => {
      // ★ 跳过本插件开出来的子会话 —— 往委派 prompt 里塞额度表，目标模型第一眼看到的是额度表。
      if (childSessions.has(input.sessionID)) return
      const cfg = loadBudget()
      const usage = loadUsage()
      const hk = hourKey()
      prune(usage, hk)
      const sid = input.sessionID || '_shared'
      const here = input.model ? `${input.model.providerID}/${input.model.modelID}` : '未知'
      const state = cfg.escalateOrder.map((id) => (check(cfg, usage, hk, id).ok ? 1 : 0)).join('')
      const fp = `${hk}|${state}|${here}`
      if (injected.get(sid) === fp) return
      if (output.parts.some((p) => p.type === 'text' && typeof p.text === 'string' && p.text.includes(MARKER))) return

      const lines = [
        MARKER,
        '',
        `本会话当前模型 \`${here}\`　·　本小时桶 \`${hk}\`（整点自动清零）`,
        '',
        '**你是免费档主力。分工固定：你负责敲代码，想不清楚的时候才外包「思考」。**',
        '',
        '- 稍微有点难（一个文件说不清 / 要跨 3 个以上文件 / 方案有取舍 / 报错看不懂）→ `model_router`，它默认先问 **DeepSeek**。',
        '- 难的代码、架构决策、深度审查 → `model_router`，指定 `to=sol`（gpt-6-sol）或 `to=astra`（gpt-6-astra）。',
        '- 拿到方案后**自己写代码**。写完 `model_router action=back` 标记已回免费档。',
        '- 每个模型有**每小时上限**，超了自动降级，全用完会明确报错 —— 别反复重试烧额度。',
        '',
        '本小时额度：',
        ...table(cfg, usage, hk),
        '',
      ]
      output.parts.push(makePart(input, lines.join('\n')))
      injected.set(sid, fp)
    },
  }
}

export const server = ModelRouterPlugin
export default ModelRouterPlugin
export { hourKey, loadBudget, check, pick, table, matches, extract, makePart }
