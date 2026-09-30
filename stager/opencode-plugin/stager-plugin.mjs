/**
 * stager-plugin.mjs —— opencode 插件：每轮对话自动把 stager 上下文注入进来
 *
 * 干的事就一件：`chat.message` 时读一遍 stager 状态，把 `ctx` 当成用户消息的一部分贴进去。
 * 于是 AI 每次开口前，系统提示里就带着「现在第几阶段、第几轮、谁在干活、这阶段要干嘛」。
 *
 * 装：stager install    （会往 ~/.config/opencode/opencode.json 的 plugin 数组加一条）
 * 卸：stager uninstall
 *
 * 特点：
 *  - 幂等：同一会话只在第一次注入；之后 AI 自己跑过 `stager next` 就用命令结果，
 *    避免每轮都刷一遍污染上下文。
 *  - 静默：没任务 / 报错 / 第一次读 context 失败，都不打扰用户。
 *  - 轻量：纯 fs 读文件，不 spawn 进程（除非 stager.js 不可读时的兜底）。
 */

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const STAGER_ROOT = path.resolve(HERE, '..')
const CLI = path.join(STAGER_ROOT, 'bin', 'stager.js')
const RUNTIME = path.join(STAGER_ROOT, '.stager')
const ACTIVE = path.join(RUNTIME, 'active.json')
const STAGES_FILE = path.join(STAGER_ROOT, 'core', 'stages.json')
const MARKER = '## ▶ STAGER 阶段管理器 · 上下文注入'

/**
 * 同一进程内：sessionID -> 已经注入过的状态指纹
 * 必须是 per-session，不能用一个全局指纹：A/B 两个会话都拿到 v1，
 * B 先拿到 v2 之后，A 的下一条消息会误判"v2 注入过了"→ A 永远停在旧状态。
 * （codex 复现过这个交错）
 */
const seen = new Map()

function fingerprintOf(st) {
  return [st.id, st.status, st.stage, st.round, st.wrap, st.actor, st.updatedAt, st.docRev || 0].join('|')
}

function loadStages() {
  const raw = readJson(STAGES_FILE, null)
  if (!raw) return null
  raw.stageList = raw.stages.map((s, i) => ({ ...s, _i: i }))
  return raw
}

function fingerprintOf(st, S) {
  return [st.id, st.status, st.stage, st.round, st.wrap, st.actor, st.updatedAt].join('|')
}

/** 自己拼一份注入包（不 spawn 进程，快） */
function buildCtx(st, S) {
  const s = S.stageList.find((x) => x.id === st.stage)
  const man = readJson(path.join(RUNTIME, 'tasks', st.id, 'docs', 'manifest.json'), { docs: [] })
  const docs = man.docs || []

  const key = r => r.round + ':' + r.stage
  const marks = st.marks || {}
  const have = [], need = []
  ;(s?.gate?.docs || []).forEach((k) => {
    ;(docs.some((d) => d.kind === k && d.stage === st.stage && d.round === st.round) ? have : need).push('doc:' + k)
  })
  ;(s?.gate?.cmds || []).forEach((c) => {
    ;((marks[key(st)] || []).includes(c) ? have : need).push('cmd:' + c)
  })

  const L = []
  L.push(MARKER)
  L.push('')
  // ★ 第一行大横幅：用户要求「每次进入阶段就在聊天框报一句到哪个阶段了」
  //   放在最前面，不许折叠、不许藏在表里。
  L.push(`## ▶▶ 现在在：${s ? s.icon + ' ' + s.name : st.stage}　（第 ${s ? s._i + 1 : '?'}/${S.stageList.length} 阶段）　·　第 ${st.round}/${st.maxRounds} 轮　·　人次 \`${st.actor}\``)
  L.push('')
  L.push(st.status !== 'active'
    ? `> ⚠ 任务状态 = ${st.status}。要改东西先 \`stager resume ${st.id} --force\`。`
    : (need.length
      ? `> **门禁 ✘ 还差 ${need.join(' ')}** —— 补齐才能 \`stager next\`。`
      : '> **门禁 ✔ 达标** —— 可以 `stager next` 进下一阶段。'))
  L.push('')
  L.push(`> 任务「${st.title || st.id}」　阶段 \`${st.stage}\`　轮回 ${st.wrap || 0} 次　文档 ${docs.length} 份`)
  L.push('')
  L.push(`| 项 | 值 |`)
  L.push(`|---|---|`)
  L.push(`| 任务 | ${st.title || st.id} |`)
  L.push(`| 阶段 | **${s ? s.icon + ' ' + s.name : st.stage}**（${s ? s._i + 1 : '?'}/${S.stageList.length}，\`${st.stage}\`） |`)
  L.push(`| 轮次 | 第 **${st.round}**/${st.maxRounds} 轮，已轮回 ${st.wrap || 0} 次 |`)
  L.push(`| 人次 | \`${st.actor}\` |`)
  L.push(`| 门禁 | ${need.length ? '✘ 还差 ' + need.join(' ') : '✔ 达标'} |`)
  L.push(`| 文档 | ${docs.length} 份（${[...new Set(docs.map((d) => d.kind))].join(',') || '无'}） |`)
  L.push('')
  L.push('### 阶段流水线（下一阶段 = `' + (s?.next ?? '?') + '`）')
  L.push('')
  S.stageList.forEach((x, i) => {
    L.push(`${i + 1}. ${x.icon} **${x.name}** \`${x.id}\` → \`${x.next}\`${x.loop ? ' （轮回点）' : ''}`)
  })
  L.push('')
  if (s?.ai?.length) {
    L.push(`### 你现在这阶段要做的事：${s.name}`)
    L.push('')
    L.push(s.brief)
    L.push('')
    s.ai.forEach((x) => L.push('- ' + x))
    L.push('')
  }
  L.push('### 这阶段的产出放哪')
  L.push('')
  const kind = (s?.gate?.docs || [])[0] || 'note'
  L.push(`\`\`\`powershell`)
  L.push(`node "${CLI}" put "<你写的文件>" --kind ${kind} --title "<标题>"`)
  L.push(`node "${CLI}" next --note "<一句话>"`)
  L.push(`\`\`\``)
  if (need.some((n) => n.startsWith('cmd:'))) {
    L.push('')
    L.push('门禁还差标记：')
    need.filter((n) => n.startsWith('cmd:')).forEach((n) => {
      L.push(`\`\`\`powershell`)
      L.push(`node "${CLI}" mark ${n.slice(4)} --note "<干了什么>"`)
      L.push(`\`\`\``)
    })
  }
  L.push('')
  L.push('### 换人/接手')
  L.push('')
  L.push(`\`\`\`powershell`)
  L.push(`node "${CLI}" swap "<你的名字>"     # 记一笔谁接的`)
  L.push(`node "${CLI}" ctx --full           # 把历史文档全文注入给你（务必）`)
  L.push('```')
  L.push('')
  L.push('### 硬规矩')
  L.push('')
  L.push('- 门禁没过不许走。真要跳：`next --force --note "为什么"`，会留痕。')
  L.push('- 每阶段开工先 `stager ctx`。**换人接手必须 `ctx --full`** —— 这里注入的是索引，不是文档全文。')
  L.push('- 往前跳阶段要 `enter <stage> --force --note "为什么"`，否则会被拦。')
  L.push('- 产出的东西必须 `put` 进 stage，否则换人断片。')
  L.push('- 收工 = `stager close --status done`；本轮没有 contract + evidence 文档会被拦（零证据不许收工）。')
  L.push('')
  return L.join('\n')
}

/** 兜底：直接问 CLI（万一 stages.json 结构变了） */
function buildCtxViaCli() {
  try {
    return execFileSync(process.execPath, [CLI, 'ctx'], {
      encoding: 'utf8',
      timeout: 8000,
      windowsHide: true,
    }).trim()
  } catch { return '' }
}

export const StagerPlugin = async () => {
  return {
    'chat.message': async (input, output) => {
      // 1) 有没有活
      const id = readJson(ACTIVE, null)
      if (!id) return
      const st = readJson(path.join(RUNTIME, 'tasks', id, 'state.json'), null)
      if (!st || st.status !== 'active') return

      const S = loadStages()
      let body
      if (S) body = buildCtx(st, S)
      else body = buildCtxViaCli()
      if (!body) return

      // 2) 这个会话在同一个状态下注入过了 → 不重复刷（防上下文膨胀）
      const sid = input.sessionID || '_shared'
      const fp = fingerprintOf(st)
      if (seen.get(sid) === fp) return

      // 3) 别重复贴同样的东西
      if (output.parts.some((p) => p.type === 'text' && typeof p.text === 'string' && p.text.includes(MARKER))) return

      // 4) 太长就退一步：只给一行摘要（S 为 null 时 briefSummary 不可用，给纯文本兜底）
      let text
      if (body.length > 2200) text = S ? briefSummary(st, S) : shortFallback(st, body)
      else text = body

      output.parts.push({ type: 'text', text })
      seen.set(sid, fp)
    },
  }
}

function shortFallback(st, body) {
  return [MARKER, '', `> 上下文太长，精简注入：\`\`\`stager ctx --full\`\`\` 看全文。`, '', body.slice(0, 700), ''].join('\n')
}

function briefSummary(st, S) {
  const s = S.stageList.find((x) => x.id === st.stage)
  return [
    MARKER,
    '',
    `> 上下文已注入过，这里只给精简版。要全文自己跑 \`node "${CLI}" ctx --full\`。`,
    '',
    `**${s ? s.icon + ' ' + s.name : st.stage}** · 第 ${st.round}/${st.maxRounds} 轮 · 人次 \`${st.actor}\` · 任务「${st.title || ''}」`,
    s?.ai?.length ? s.ai.map((x) => '- ' + x).join('\n') : '',
    '',
  ].join('\n')
}

export default StagerPlugin
