/**
 * goal-drive.mjs —— opencode 插件：架构目标锁的「不许停」执行者
 *
 * 用户诉求（2026-10-07 原话要义）：
 *   「架构文档写完了就放进 stage，AI 依据架构文档的边界一起写；
 *     写到一半自己停了，就拿一个强制性的把它开动；
 *     架构没完成之前不许停，过一会儿又让它自己动；
 *     API 断流了也要让它继续写；
 *     写完了提醒它看边界是不是真的完成，给出证据；
 *     硬性要求不许写文档冒充完成 —— 没完成就一直跑。」
 *
 * 借的是 opencode 自己那套「压缩上下文时往里塞状态」的机制（用户原话：借用 compress 那边的机制）：
 *   · `experimental.session.compacting` —— 压缩前把「目标锁 + 还差哪几条 + 证据要求」塞进去，
 *     于是上下文被砍掉大半之后，边界还在。**这是跨压缩不丢目标的唯一通道。**
 *   · `session.idle`                    —— AI 说完话停下来 = 「写到一半自己停了」→ 自动续一条。
 *   · `session.error`                   —— API 断流/超长/报错 → 按退避续跑。
 *     ★ `MessageAbortedError`（用户自己按了中断）**不续** —— 用户按停的东西自动重开就是打扰
 *       （SendKeys 那两次投诉就是这么来的）。
 *
 * 催跑的判据全在 stager/.stager/goal.json（由 rddharness/bin/goal.js 维护），本插件只读它、
 * 只写两个字段（nudges / sessions）。证据与验收逻辑不在这 —— 那是 goal.js 的活，单一真相。
 *
 * 装：加进 ~/.config/opencode/opencode.json 的 plugin 数组，重启 opencode（配置不热重载）。
 * 关掉整把锁：`node goal.js pause --reason …` / `clear --yes` —— 没有目标锁时本插件完全不动作。
 *
 * 导出必须叫 `server`（PluginModule = { id?, server, tui? }）—— 这条已经在 stager 插件上踩过。
 */

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { createRequire } from 'node:module'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const WORKSPACE = 'E:/restart developing doer'
const GOAL_FILE = process.env.RDD_GOAL_STATE || path.join(WORKSPACE, 'stager', '.stager', 'goal.json')
const GOAL_CLI = 'E:/新建文件夹/rddharness/bin/goal.js'
// ★ 日志跟着状态文件走（或用 RDD_GOAL_LOG 显式指定）。
//   2026-10-07 实测踩到：日志路径写死时，探针把 goal.json 隔离到临时目录，
//   但模拟出来的 kick-ok / error-resume-ok 全写进了**真实日志** ——
//   于是「插件上线了吗」的判据（TL-2026-10-07-01：看当天有没有条目）被假证据污染。
//   隔离状态就必须连日志一起隔离，否则等于没隔离。
const LOG_FILE = process.env.RDD_GOAL_LOG
  || (process.env.RDD_GOAL_STATE
    ? path.join(path.dirname(process.env.RDD_GOAL_STATE), 'goal-drive.jsonl')
    : path.join(HERE, '.state', 'goal-drive.jsonl'))
const MARKER = '## ▶ GOAL-DRIVE · 架构目标锁'

/** 催跑冷却：同一把锁两次自动催跑之间最少隔多久（毫秒） */
const COOLDOWN_MS = 120000
/** 断流续跑的退避序列（秒）：20 → 40 → 80 → 160 → 320 → 600 封顶 */
const BACKOFF_S = [20, 40, 80, 160, 320, 600]

// ── 日志（催跑是自动行为，必须留痕；静默的自动行为最吓人）──
function log(ev, detail) {
  try {
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true })
    fs.appendFileSync(LOG_FILE, JSON.stringify({ at: new Date().toISOString(), ev, ...detail }) + '\n', 'utf8')
  } catch { /* 记不了不阻断主流程，但催跑本身失败会在调用处记 */ }
}

function readGoal() {
  try {
    const g = JSON.parse(fs.readFileSync(GOAL_FILE, 'utf8').replace(/^\uFEFF/, ''))
    return g && typeof g === 'object' ? g : null
  } catch { return null }
}
function writeGoal(g) {
  try {
    g.rev = (g.rev || 0) + 1
    g.updatedAt = new Date().toISOString()
    fs.mkdirSync(path.dirname(GOAL_FILE), { recursive: true })
    const tmp = GOAL_FILE + '.tmp'
    fs.writeFileSync(tmp, JSON.stringify(g, null, 1), 'utf8')
    fs.renameSync(tmp, GOAL_FILE)
    return true
  } catch (e) { log('state-write-fail', { err: String(e.message).slice(0, 200) }); return false }
}

// 同步加载 goal.js：CLI 与插件写的是**同一份 JSON**，两边都要过同一把互斥锁。
// 不加锁的后果（2026-10-07 实测）：两条 prove 并行跑，后写的把先写的整份状态覆盖，
// 一条证据静默消失，而那条 prove 的回执明明是 exit=0「证据已收」。
// 同步 require 而不是动态 import：onChatMessage 是同步钩子，等不了 promise。
const req = createRequire(import.meta.url)
let GOAL = null
try { GOAL = req(GOAL_CLI) } catch (e) { log('goal-require-fail', { err: String(e.message).slice(0, 200) }) }
/** 改状态一律过锁；goal.js 载不到就退化为直接执行（宁可冒险，也不能让插件整个不工作） */
const withLock = (fn) => (GOAL && typeof GOAL.withLock === 'function' ? GOAL.withLock(fn) : fn())
/** 绑定判据：这个会话成功收到过边界注入（在 g.sessions 里）。见 goal-drive.md 第五节 */
function boundTo(g, sessionID) { return !!g && Array.isArray(g.sessions) && g.sessions.includes(sessionID) }
/**
 * ★ 自动驱动只认「一个窗口」：既绑定、又是最近有动静的那个（g.activeSession）。
 *   2026-10-07 用户定的语义：只让有自己边界状态的那个窗口续跑，其他窗口一律不接管 ——
 *   否则每开一个窗口都有一套自动行为在跑，「反倒每个月都停不下来」。
 */
function isActiveWindow(g, sessionID) { return boundTo(g, sessionID) && g.activeSession === sessionID }

/**
 * 催跑文案从 goal.js 取（那边是单一真相，CLI 的 drive 命令打印的也是它）。
 * 取不到就用兜底短文案 —— 插件绝不能因为 import 失败而整个不工作（那会静默失效）。
 */
let NUDGE = null
async function loadNudge() {
  if (NUDGE !== null) return NUDGE
  try {
    const ns = await import(pathToFileURL(GOAL_CLI).href)
    const fn = ns.buildNudge || (ns.default && ns.default.buildNudge)
    if (typeof fn === 'function') { NUDGE = fn; return NUDGE }
    throw new Error('goal.js 里没有 buildNudge 导出')
  } catch (e) {
    log('nudge-import-fail', { err: String(e.message).slice(0, 200) })
    NUDGE = (g, pend) => {
      const p = (pend || g.items.filter((x) => x.status !== 'proved'))
      return [
        '[GOAL-DRIVE 架构目标锁 · 系统自动催跑，不是用户新指令]',
        '架构还没验收完，按边界继续：' + g.title,
        '边界（冻结架构）：' + g.arch,
        '未验收：' + (p.map((x) => x.it ? x.it.id : x.id).join(' ') || '（全部 proved → 跑 goal.js accept）'),
        '每条必须给【跑出来的证据】：node "' + GOAL_CLI + '" prove <id> --cmd "<命令>" --note "<实际是什么>"',
        '全过跑最终验收：node "' + GOAL_CLI + '" accept　（复跑判据，一条不过就继续干）',
        '卡住就留痕：node "' + GOAL_CLI + '" pause --reason "…"',
      ].join('\n')
    }
    return NUDGE
  }
}

/**
 * 快速估算未验收条目。
 * ★ 不在这里实跑判据命令 —— 事件钩子里跑 shell（每条可到 120s）会挂住 opencode 的事件循环。
 *   最终权威是 `goal.js accept` 的逐条复跑，两边读同一份 goal.json。
 */
function quickPending(g) {
  return g.items
    .filter((it) => it.status !== 'proved')
    .map((it) => ({ it, j: { ok: false, why: '还没 prove（跑 goal.js prove ' + it.id + ' … 给证据）' } }))
}

function allProved(g) {
  return g.items.length > 0 && g.items.every((it) => it.status === 'proved')
}

/**
 * 注入的 text part 必须自带 id/sessionID/messageID，**且 messageID 必须是 opencode 自己的 `msg…` 串**。
 * 2026-10-07 真机教训（19 次 `SchemaError: Expected a string starting with "msg", got "" at ["messageID"]`）：
 *   这里的注释本来写着「否则拒存（老坑）」，代码却给了空串 messageID —— 探针也只检查**键存不存在**，
 *   于是 57/0 全绿、真机把每一条边界注入全拒了。★ 探针断言必须对到真实 schema，不是对到「字段齐了」。
 * 拿不到合法 id 就返回 null：调用方跳过注入并留痕，**绝不能推一个注定被拒的 part**（推了等于静默失败）。
 */
function makePart(input, text) {
  const mid = input && input.messageID
  const sid = input && input.sessionID
  if (typeof sid !== 'string' || !sid) return null
  if (typeof mid !== 'string' || !mid.startsWith('msg')) return null
  const rid = () => Math.random().toString(36).slice(2, 10)
  return { id: 'prt_' + rid() + rid() + rid(), sessionID: sid, messageID: mid, type: 'text', text: String(text) }
}

export const GoalDrivePlugin = async ({ client, directory }) => {
  /** 子会话（model-router 那类委派）绝不能催 —— 往委派 prompt 里塞催跑会污染目标模型收到的内容 */
  const childSessions = new Set()
  /** 每个会话已经注入过的状态指纹（防每轮重复刷） */
  const seen = new Map()
  /** 断流续跑的定时器，进程退出自然清掉 */
  const timers = new Set()

  /** 手动催跑的冷却（读写 goal.json 的 nudges 字段，所以重启不丢） */
  function cooldownOk(g) {
    const last = g.nudges && g.nudges.lastAt ? Date.parse(g.nudges.lastAt) : 0
    const cd = (g.nudges && g.nudges.cooldownSec ? g.nudges.cooldownSec * 1000 : COOLDOWN_MS)
    return Date.now() - last >= cd
  }
  function underMax(g) {
    const n = (g.nudges && g.nudges.count) || 0
    const max = (g.nudges && g.nudges.max) || 80
    return n < max
  }

  /**
   * ★ 真正的「把它开动」：直接用 SDK 发一条 prompt（不是往输入框打字 —— SendKeys 投诉两次的教训）。
   * 发之前记账（count+1 / lastAt），失败也记 —— 失败也烧额度，且这样不会因为写状态失败而无限重试。
   */
  async function kick(sessionID, text, why) {
    const g = readGoal()
    if (!g || g.status !== 'active') return false
    // ★ 只催「绑定过这把锁」的会话（用户 2026-10-07 定的语义）：
    //   锁是工作区级的，但 idle 会话可能是另一个窗口在干完全无关的活 ——
    //   往那儿催会让人家永远停不下来。不绑定就不催，日志留 kick-skip。
    if (!isActiveWindow(g, sessionID)) { log('kick-skip', { sessionID, why: why + (boundTo(g, sessionID) ? ':not-active-window' : ':session-not-bound') }); return false }
    if (!cooldownOk(g) || !underMax(g)) {
      log('kick-skip', { sessionID, why: why + ':cooldown-or-max', count: g.nudges && g.nudges.count })
      return false
    }
    // 计数读-改-写必须在锁里：CLI 的 prove/accept 同时在改这份 JSON
    const n = withLock(() => {
      const cur = readGoal()
      if (!cur || cur.status !== 'active' || !isActiveWindow(cur, sessionID)) return null
      if (!cooldownOk(cur) || !underMax(cur)) return null
      cur.nudges = cur.nudges || { count: 0, lastAt: null, max: 80, cooldownSec: 120 }
      cur.nudges.count = (cur.nudges.count || 0) + 1
      cur.nudges.lastAt = new Date().toISOString()
      writeGoal(cur)
      return cur.nudges.count
    })
    if (n === null) { log('kick-skip', { sessionID, why: why + ':lost-race' }); return false }

    try {
      await client.session.prompt({
        path: { id: sessionID },
        query: directory ? { directory } : undefined,
        body: { parts: [{ type: 'text', text }] },
      })
      log('kick-ok', { sessionID, why, n })
      try { await client.tui.showToast({ body: { message: '目标锁催跑 #' + n + '（' + g.title + '）', variant: 'info' } }) } catch { /* toast 可选 */ }
      return true
    } catch (e) {
      log('kick-fail', { sessionID, why, n, err: String(e && e.message ? e.message : e).slice(0, 300) })
      return false
    }
  }

  // ── ① AI 停下来了 → 架构没验收完就把它开动 ─────────────
  async function onIdle(sessionID) {
    const g = readGoal()
    if (!g || g.status !== 'active') { log('idle-skip', { sessionID, why: 'no-goal-or-not-active' }); return }
    if (childSessions.has(sessionID)) { log('idle-skip', { sessionID, why: 'child-session' }); return }

    // 别往委派会话里催：标题前缀 + 有 parentID 都算子会话
    try {
      const r = await client.session.get({ path: { id: sessionID } })
      const info = r && r.data ? r.data : r
      const title = (info && info.title) || ''
      if (info && info.parentID) { childSessions.add(sessionID); log('idle-skip', { sessionID, why: 'parentID', title }); return }
      if (title.startsWith('[model-router')) { childSessions.add(sessionID); log('idle-skip', { sessionID, why: 'router-title', title }); return }
    } catch (e) {
      log('session-get-fail', { sessionID, err: String(e.message).slice(0, 200) })
      // 拿不到会话信息 → 保守：照样催（这是用户要的「不许停」），但记一笔
    }

    // 断流计数在「有一次正常收尾」后归零 —— 说明链路自己恢复了（读-改-写过锁）
    const reset = withLock(() => {
      const cur = readGoal()
      if (!cur || !cur.stream || !cur.stream.count) return false
      cur.stream.count = 0
      cur.stream.lastAt = null
      writeGoal(cur)
      return true
    })
    if (reset) log('stream-reset', { sessionID, note: '收到一次正常 idle，断流计数清零' })

    const build = await loadNudge()
    const pend = quickPending(g)
    const text = build(g, pend)
    await kick(sessionID, text, 'idle')
  }

  // ── ② API 断流 / 报错 → 按退避续写 ────────────────────
  function onError(sessionID, err) {
    const name = (err && err.name) || (err && err.type) || ''
    const msg = String((err && err.message) || err || '').slice(0, 300)

    // 用户自己按的中断不许自动重开 —— 那是打扰，不是断流
    if (name === 'MessageAbortedError') { log('error-aborted-by-user', { sessionID, msg }); return }
    // 鉴权问题重发也没用，反复重发只会刷日志；报一次让用户看见
    if (name === 'ProviderAuthError') {
      log('error-auth', { sessionID, msg })
      try { client.tui.showToast({ body: { message: 'API 鉴权失败，目标锁暂不续跑', variant: 'error' } }) } catch { /* 可选 */ }
      return
    }
    if (!sessionID) { log('error-no-session', { name, msg }); return }

    const g0 = readGoal()
    if (!g0 || g0.status !== 'active') { log('error-skip', { sessionID, why: 'no-goal', name }); return }
    // ★ 只有「绑定过边界状态、且最近有动静的那个窗口」才自动续写（用户 2026-10-07 定的语义）：
    //   其他窗口的断流不接管 —— 全工作区一直接管正是「反倒停不下来」的来源。
    if (childSessions.has(sessionID) || !isActiveWindow(g0, sessionID)) {
      log('error-skip', {
        sessionID,
        why: childSessions.has(sessionID) ? 'child-session' : boundTo(g0, sessionID) ? 'not-active-window' : 'session-not-bound',
        name,
      })
      return
    }

    // 计数读-改-写过锁（CLI 可能正在改同一份状态）
    const counted = withLock(() => {
      const cur = readGoal()
      if (!cur || cur.status !== 'active' || !isActiveWindow(cur, sessionID)) return null
      cur.stream = cur.stream || { count: 0, lastAt: null, max: 6 }
      cur.stream.count = (cur.stream.count || 0) + 1
      cur.stream.lastAt = new Date().toISOString()
      writeGoal(cur)
      return { count: cur.stream.count, max: cur.stream.max || 6 }
    })
    if (!counted) { log('error-skip', { sessionID, why: 'lost-race', name }); return }
    const count = counted.count
    const max = counted.max

    if (count > max) {
      log('error-give-up', { sessionID, name, msg, count, max })
      try { client.tui.showToast({ body: { message: '目标锁：断流重试 ' + count + ' 次仍失败，已停（见 .state/goal-drive.jsonl）', variant: 'error' } }) } catch { /* 可选 */ }
      return
    }

    const wait = (BACKOFF_S[Math.min(count - 1, BACKOFF_S.length - 1)]) * 1000
    log('error-resume-planned', { sessionID, name, msg, count, waitMs: wait })

    const t = setTimeout(async () => {
      timers.delete(t)
      try {
        const fresh = readGoal()
        if (!fresh || fresh.status !== 'active') { log('error-resume-cancelled', { sessionID, why: 'goal-changed' }); return }
        // 到点了再确认一次：这中间用户可能已经 accept / clear，或有别的窗口抢走了「在盯的窗口」
        if (childSessions.has(sessionID) || !isActiveWindow(fresh, sessionID)) {
          log('error-resume-cancelled', { sessionID, why: childSessions.has(sessionID) ? 'child-session' : boundTo(fresh, sessionID) ? 'window-switched' : 'session-unbound' })
          return
        }
        const lines = [
          '[GOAL-DRIVE 断流续写 · 系统自动，不是用户新指令]',
          '上一条回复因 ' + (name || 'API 错误') + ' 中断了（第 ' + count + ' 次，退避 ' + Math.round(wait / 1000) + 's 后重试）。',
          '从断点接着写，不要重来、不要总结已经做完的部分。',
          '边界与未验收条目：' + fresh.arch,
          '继续做完，每完成一条给【跑出来的证据】：node "' + GOAL_CLI + '" prove <id> --cmd "<命令>" --note "<实际是什么>"',
        ]
        await client.session.prompt({
          path: { id: sessionID },
          query: directory ? { directory } : undefined,
          body: { parts: [{ type: 'text', text: lines.join('\n') }] },
        })
        log('error-resume-ok', { sessionID, count, arch: fresh.arch })
      } catch (e) {
        log('error-resume-fail', { sessionID, err: String(e && e.message ? e.message : e).slice(0, 300) })
      }
    }, wait)
    timers.add(t)
  }

  // ── ③ 压缩上下文时把目标锁压进去（用户说的「借 compress 的机制」）──
  async function onCompacting(input, output) {
    const g = readGoal()
    if (!g) return
    // 未绑定 / 不是当前盯的窗口 → 压缩时一个字都不塞：它压根不知道这把锁，塞进去就是往无关任务里塞目标
    if (!isActiveWindow(g, input && input.sessionID)) {
      log('compacting-skip', { sessionID: input && input.sessionID, why: boundTo(g, input && input.sessionID) ? 'not-active-window' : 'session-not-bound' })
      return
    }
    const pend = quickPending(g)
    const lines = [
      '## 目标锁（跨压缩必须保住的状态 —— 压完之后请照它继续，别重新发散）',
      '- 目标：' + g.title,
      '- 架构边界（冻结文档，一切以它为准）：' + g.arch,
      '- 状态：' + g.status + (g.status === 'paused' ? '（' + (g.pauseReason || '') + '）' : ''),
      '- 验收：' + g.items.filter((x) => x.status === 'proved').length + '/' + g.items.length + ' 条 proved；' +
        (pend.length ? '未验收 ' + pend.map((x) => x.it.id).join(' ') : '全部 proved → 跑 goal.js accept'),
      '',
      '硬性规矩：不许用「写了文档 / 我认为完成了」冒充完成。每条必须给跑出来的证据：',
      '  node "' + GOAL_CLI + '" prove <id> --cmd "<命令>" --note "<实际是什么>"',
      '最终验收（复跑判据，全过才算完）：node "' + GOAL_CLI + '" accept',
      '卡住/等用户：node "' + GOAL_CLI + '" pause --reason "…"　恢复：resume',
    ]
    if (pend.length) {
      lines.push('', '未验收条目：')
      for (const x of pend) lines.push('  [' + x.it.id + '] ' + x.it.title + (x.it.how ? '　｜' + x.it.how : ''))
    }
    try { output.context.push(lines.join('\n')) } catch (e) { log('compacting-push-fail', { err: String(e.message).slice(0, 200) }) }
    log('compacting-injected', { sessionID: input && input.sessionID, pending: pend.length })
  }

  // ── ④ 每轮对齐边界（短；stager 的注入是另一套，两份各管各的）──
  function onChatMessage(input, output) {
    const g = readGoal()
    if (!g) return
    if (childSessions.has(input.sessionID)) { log('chat-skip', { sessionID: input.sessionID, why: 'child-session' }); return }
    // 「最近有动静的窗口」= 自动催跑/断流续跑/压缩注入的唯一目标。
    // 已绑定的窗口一发消息就把它认领过来（不然自动驱动会卡在上一个窗口上）。
    if (boundTo(g, input.sessionID) && g.activeSession !== input.sessionID) {
      withLock(() => {
        const cur = readGoal()
        if (cur && cur.activeSession !== input.sessionID) { cur.activeSession = input.sessionID; writeGoal(cur) }
      })
      log('window-focus', { sessionID: input.sessionID, from: g.activeSession || null })
    }
    if (output.parts.some((p) => p.type === 'text' && typeof p.text === 'string' && p.text.includes(MARKER))) {
      log('chat-skip', { sessionID: input.sessionID, why: 'already-marked' })
      return
    }

    // 认领会话：只有拿到过注入的会话才会被催（不知道目标锁的会话不该被自动插话）
    // ★ 指纹只放「AI 需要知道的内容」，不放 rev。
    //   2026-10-07 探针抓到自己咬自己尾巴：第一次注入后本插件会登记会话（写盘 → rev+1），
    //   而指纹里含 rev → 下一轮指纹必变 → 每轮都注入一次 → 上下文膨胀。
    //   rev 是写盘计数器，不是状态；状态是 status / 架构路径 / 条目清单。
    const fp = [g.status, g.arch, g.title, g.items.map((x) => x.id + ':' + x.status).join(',')].join('|')
    if (seen.get(input.sessionID) === fp) { log('chat-skip', { sessionID: input.sessionID, why: 'same-fingerprint' }); return }

    const pend = quickPending(g)
    const proved = g.items.length - pend.length
    const text = [
      MARKER,
      '',
      '- 目标：' + g.title + '　状态 `' + g.status + '`',
      '- 架构边界：`' + g.arch + '`',
      '- 验收进度：' + proved + '/' + g.items.length + ' 条 proved' +
        (g.status === 'accepted' ? '　✅ 已最终验收通过' : '　★ 未验收：' + (pend.map((x) => x.it.id).join(' ') || '（跑 accept 复核）')),
      '- 每完成一条给【跑出来的证据】：`node "' + GOAL_CLI + '" prove <id> --cmd "<命令>" --note "<实际是什么>"`',
      '- 全过做最终验收：`node "' + GOAL_CLI + '" accept`（复跑判据，一条不过就继续干）',
      '- 卡住留痕：`node "' + GOAL_CLI + '" pause --reason "…"`　｜ 状态：`goal.js status`',
      '',
      '> 硬性：不许写文档冒充完成。accept 只认机器复跑的输出。',
      '',
    ].join('\n')

    const part = makePart(input, text)
    if (!part) {
      // 拿不到合法 messageID → 这一轮不注入，也不登记会话（登记了就等于说「它知道这把锁」，
      // 但其实一条都没进它上下文 —— 那会让催跑去打一个根本不知道目标的窗口，2026-10-07 亲历）。
      log('chat-skip', { sessionID: input.sessionID, why: 'no-valid-messageID', messageID: String(input && input.messageID || '') })
      return
    }
    output.parts.push(part)
    seen.set(input.sessionID, fp)
    log('chat-inject', { sessionID: input.sessionID, pending: pend.length, proved, status: g.status })
    // 绑定登记同样过锁（CLI 可能正在写）；同时认领「盯的窗口」
    withLock(() => {
      const cur = readGoal()
      if (!cur) return
      if (!Array.isArray(cur.sessions)) cur.sessions = []
      let touched = false
      if (!cur.sessions.includes(input.sessionID)) {
        cur.sessions = cur.sessions.concat(input.sessionID).slice(-8)
        touched = true
      }
      if (cur.activeSession !== input.sessionID) { cur.activeSession = input.sessionID; touched = true }
      if (touched) writeGoal(cur)
    })
  }

  return {
    event: async ({ event }) => {
      try {
        const p = (event && event.properties) || {}
        if (event.type === 'session.created' && p.info && p.info.parentID) { childSessions.add(p.info.id); return }
        if (event.type === 'session.idle') { await onIdle(p.sessionID); return }
        if (event.type === 'session.error') { onError(p.sessionID, p.error); return }
      } catch (e) {
        log('event-fail', { type: event && event.type, err: String(e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e).slice(0, 400) })
        // ★ 不让插件异常把 opencode 的事件链搞崩 —— 但一定要留痕（失败不静默）
      }
    },
    'experimental.session.compacting': async (input, output) => { await onCompacting(input, output) },
    'chat.message': async (input, output) => { onChatMessage(input, output) },
  }
}

export const server = GoalDrivePlugin
export default GoalDrivePlugin
