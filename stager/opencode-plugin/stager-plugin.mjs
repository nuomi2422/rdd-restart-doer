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

/** 同一进程内：sessionID -> 已经注入过的状态指纹（per-session 的理由见 fingerprintOf） */
const seen = new Map()

/**
 * 注入正文超过这个长度就退化成精简版。
 * 2026-10-02：原值 2200。而当时 plan 的 ai[] 有 2654 字符 → 三个阶段**每次都被砍**，
 *   砍完的版本又没有 read[]，于是「必读哪几份 md」静默消失。
 *   后来 ai[] 按用户裁定瘦到 1200~1650，全量正文最长约 1.8K，阈值降到 2500 留余量。
 */
const MAX_CTX_CHARS = 2500

/** 读 JSON，坏文件不炸（注入是锦上添花，绝不能把用户的对话搞崩） */
function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')) }
  catch { return fallback }
}

/**
 * 状态指纹：变了才重新注入。
 * 同一进程内 sessionID -> 已注入的指纹。必须 per-session，不能用全局指纹：
 * A/B 两个会话都拿到 v1，B 先拿到 v2 之后，A 的下一条消息会误判「v2 注入过了」
 * → A 永远停在旧状态。（codex 复现过这个交错）
 * docRev 必须在里面：put 了新文档之后要重新注入，否则 AI 看到的还是旧文档清单。
 */
function fingerprintOf(st) {
  return [st.id, st.status, st.stage, st.round, st.wrap, st.actor, st.updatedAt, st.docRev || 0].join('|')
}

function loadStages() {
  const raw = readJson(STAGES_FILE, null)
  if (!raw) return null
  raw.stageList = raw.stages.map((s, i) => ({ ...s, _i: i }))
  return raw
}

/**
 * 门禁现状：这阶段还差什么 + 已交文档清单。
 * buildCtx 和 briefSummary 共用 —— ★ 精简版也必须带上门禁和 read[]，
 * 否则一旦正文超阈值被砍，AI 就既不知道还差什么、也不知道该读哪几份。
 */
function gateState(st, s) {
  const man = readJson(path.join(RUNTIME, 'tasks', st.id, 'docs', 'manifest.json'), { docs: [] })
  const docs = man.docs || []
  const marks = st.marks || {}
  const have = [], need = []
  ;(s?.gate?.docs || []).forEach((k) => {
    ;(docs.some((d) => d.kind === k && d.stage === st.stage && d.round === st.round) ? have : need).push('doc:' + k)
  })
  ;(s?.gate?.cmds || []).forEach((c) => {
    ;((marks[st.round + ':' + st.stage] || []).includes(c) ? have : need).push('cmd:' + c)
  })
  return { docs, have, need }
}

/**
 * 这阶段必读的 md。
 * ★ 2026-10-02：这段曾经「不存在」，但 AGENTS.md 写着「不读不许动手」——
 *   自动注入里从来没带过这份清单，纯靠 AI 自己记得去跑 stager ctx。
 *   后按用户裁定（AGENTS.md 本身就是索引）从注入里撤掉，改为 `stager ctx` 提供。
 *   留这个函数是因为 read[] 条目带中文括号补注（如 `01-工程规范.md（必看第二节…）`），
 *   括号是提示不是文件名 —— 谁要渲染 read[] 都得先剥掉，否则拼出的路径不存在。
 */
function readLines(s, S) {
  if (!s?.read?.length) return []
  const L = [`### ★ 这阶段必读（不读不许动手，${s.read.length} 份）`, '']
  for (const raw of s.read) {
    const rel = String(raw).split(/[（(【]/)[0].trim()
    const full = S?.docsRoot ? path.join(S.docsRoot, rel) : null
    L.push(full ? `- ${rel}\n  \`${full}\`` : `- ${rel}`)
  }
  L.push('')
  return L
}

/** 自己拼一份注入包（不 spawn 进程，快） */
function buildCtx(st, S) {
  const s = S.stageList.find((x) => x.id === st.stage)
  const { docs, need } = gateState(st, s)

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
  // ★ 2026-10-02 大瘦身：以前这里还塞「阶段流水线表 + read[] 必读清单 + 硬规矩 5 条」，
  //   加上 ai[] 一次注入 3~4K 字符 —— 而当时的 AGENTS.md 第 1 条早就把阶段/必读/门禁全写了，
  //   opencode 每轮自动注入 AGENTS.md，等于同一份内容每轮读两遍，纯浪费。
  //   现在只留「细则文件里没有的活状态」：现在在哪个阶段、门禁差什么、文档几份。
  // ★ 2026-10-04：AGENTS.md 已瘦身，不再承载 stage 流 —— 细则改指向 rddharness\stage.md。
  L.push(`★ **细则只读 \`E:\\新建文件夹\\rddharness\\stage.md\`**（四阶段流水线/阶段必读/机器门/完成动作）—— AGENTS.md 2026-10-04 起只留工程纪律与杂项。下面只列本阶段增量。`)
  L.push('')
  if (s?.ai?.length) {
    s.ai.forEach((x) => L.push('- ' + x))
    L.push('')
  }
  L.push('### 这阶段的产出放哪')
  L.push('')
  const kind = (s?.gate?.docs || [])[0] || 'note'
  L.push(`\`\`\`powershell`)
  L.push(`node "${CLI}" put "<你写的文件>" --kind ${kind} --title "<标题>"`)
  L.push(`node "${CLI}" next --note "<一句话>"`)
  L.push('```')
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
  L.push(`换人接手：\`node "${CLI}" ctx --full\`（把历史文档全文注入，务必）｜ 往前跳阶段：\`enter <stage> --force --note "为什么"\``)
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

      // 4) 太长就退一步：精简版（S 为 null 时 briefSummary 不可用，给纯文本兜底）
      let text
      if (body.length > MAX_CTX_CHARS) text = S ? briefSummary(st, S) : shortFallback(st, body)
      else text = body

      output.parts.push({ type: 'text', text })
      seen.set(sid, fp)
    },
  }
}

function shortFallback(st, body) {
  return [MARKER, '', `> 上下文太长，精简注入：\`\`\`stager ctx --full\`\`\` 看全文。`, '', body.slice(0, 700), ''].join('\n')
}

/**
 * 精简版：砍掉 ai[] 增量与产出放哪，只留「现在在哪 + 门禁差什么」。
 * （2026-10-02：曾经这版只给横幅 + ai[]，把 read[] 整个丢了；
 *   现在 read[] 本来就不在注入里了 —— 细则由 AGENTS.md 第 1 条承担，
 *   所以砍掉 ai[] 不会丢必读清单，只丢本阶段增量，AI 自己跑 `stager ctx` 能补。）
 */
function briefSummary(st, S) {
  const s = S.stageList.find((x) => x.id === st.stage)
  const { docs, need } = gateState(st, s)
  return [
    MARKER,
    '',
    `## ▶▶ 现在在：${s ? s.icon + ' ' + s.name : st.stage}　（第 ${s ? s._i + 1 : '?'}/${S.stageList.length} 阶段）　·　第 ${st.round}/${st.maxRounds} 轮　·　人次 \`${st.actor}\``,
    '',
    need.length ? `> **门禁 ✘ 还差 ${need.join(' ')}** —— 补齐才能 \`stager next\`。` : '> **门禁 ✔ 达标** —— 可以 `stager next` 进下一阶段。',
    `> 任务「${st.title || st.id}」　轮回 ${st.wrap || 0} 次　已交文档 ${docs.length} 份`,
    '',
    `★ 细则只读 \`E:\\新建文件夹\\rddharness\\stage.md\`。本阶段增量：\`node "${CLI}" ctx\`。`,
    '',
  ].join('\n')
}

export { buildCtx, briefSummary, MAX_CTX_CHARS }
export default StagerPlugin

/**
 * ★ opencode 真正认的是这个导出名。
 *
 * 2026-10-02 实测踩坑：文件里已经有 `export default StagerPlugin`，但 opencode 启动日志仍然
 *   ERROR failed to load plugin ... error="Plugin export is not a function"
 * 原因在官方类型定义 `PluginModule = { id?: string; server: Plugin; tui?: never }`
 *   （`~/.config/opencode/node_modules/@opencode-ai/plugin/dist/index.d.ts`）
 * —— 加载器只取 `mod.server`，**`default` 和任何自定义命名导出它都不看**。
 *
 * 教训：上一次的探针写的是「import 进来再手动调 `StagerPlugin`」，绕过了加载器的取值逻辑，
 *   所以探针全绿而 opencode 照样加载失败。
 *   ★ 验插件必须验「mod.server 是不是函数」，不是验「我导出的函数能不能跑」。
 */
export const server = StagerPlugin
