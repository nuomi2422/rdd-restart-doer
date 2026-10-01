'use strict';
// repo-status.js —— 套娃仓库状态面板（只读，一个命令看清「哪个是真源 / 推没推 / 脏不脏」
//
// 为什么需要它：外层 .gitignore 排掉了套娃仓库（提交只会存成 gitlink 指针，
// 克隆外层拿不到内容）。代价是**外层 git 完全看不见内层的改动**——
// stager 门禁和 loop-gate 的「本轮有按模块 commit」判据都建立在外层 git 上，
// 于是内层改了什么只能靠人记。这里一次输出全部。
//
// 只读：本脚本不写任何文件、不动任何 git 状态。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');

// 已知套娃仓库。merged=true = 它的历史已并进外层（numen），其余是 vendored 上游。
const REPOS = [
  { rel: '.', label: '外层工作台', note: 'stager 流程层 / 门禁 / 外脑池' },
  { rel: 'minecraft-numen', label: 'Numen 源码', note: '★真源：全部游戏代码' },
  { rel: 'rdd-selfcompile/ai-bridge', label: 'AI Bridge', note: '改上游 SoulChildTc/ai-bridge' },
  { rel: 'rdd-monitor-publish-20260913', label: '监测台', note: '改上游 Asumi-Nishiki/…-HeartPact' },
  { rel: 'mc-openclaw-controller', label: 'OpenClaw 控制器', note: '★已弃用，改 mineflayer-mcp' },
  { rel: 'voyager', label: 'Voyager', note: '纯参考，只读借鉴不搬代码' },
];

function git(cwd, args) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch (e) {
    return null;
  }
}

function rel(p) { return p.replace(/\\/g, '/'); }

function inspect(cwd, spec) {
  if (!fs.existsSync(path.join(cwd, '.git'))) {
    return { rel: spec.rel, label: spec.label, note: spec.note, missing: true };
  }
  const status = git(cwd, ['status', '--porcelain']) || '';
  const dirty = status ? status.split('\n') : [];
  const branch = git(cwd, ['rev-parse', '--abbrev-ref', 'HEAD']);
  const upstream = git(cwd, ['rev-parse', '--abbrev-ref', '@{u}']);
  const nCommits = git(cwd, ['rev-list', '--count', 'HEAD']);
  const tags = git(cwd, ['tag']);
  const remotes = git(cwd, ['remote']);
  const remList = remotes ? remotes.split('\n') : [];
  // 推没推：upstream 存在时比它，否则退化成「有远程但本分支没跟踪」
  let unpushed = null;
  if (upstream) {
    const range = git(cwd, ['log', '--oneline', upstream + '..HEAD']);
    unpushed = range ? range.split('\n').length : 0;
  }
  return {
    rel: spec.rel, label: spec.label, note: spec.note, branch, upstream,
    nCommits: nCommits || '?', nTags: tags ? tags.split('\n').filter(Boolean).length : 0,
    dirty, nDirty: dirty.length, remList, unpushed,
    head: git(cwd, ['log', '-1', '--format=%h %ad %s', '--date=short']),
    // 浅克隆：本地缺祖先对象 → push 被远端拒（did not receive expected object），
    // 而本地一切正常。不查这个字段就找不到原因（本次就踩了）。
    shallow: git(cwd, ['rev-parse', '--is-shallow-repository']) === 'true',
  };
}

const rows = REPOS.map((s) => inspect(path.join(ROOT, s.rel), s));

// ── 输出 ──────────────────────────────────────────────────────────
const L = (s = '') => console.log(s);
L('════════ 套娃仓库状态面板（只读） ════════');
L('根：' + ROOT);
L('');

let anyDirty = 0, anyUnpushed = 0, noRemote = 0;
for (const r of rows) {
  if (r.missing) { L('▫ ' + r.label.padEnd(16) + '（不是 git 仓库，跳过：' + r.rel + '）'); continue; }
  const flags = [];
  if (r.nDirty) { flags.push('脏 ' + r.nDirty); anyDirty += r.nDirty; }
  if (r.unpushed === null) flags.push('无 upstream');
  else if (r.unpushed > 0) { flags.push('★未推 ' + r.unpushed); anyUnpushed += r.unpushed; }
  if (!r.remList.length) { flags.push('★无远程=无备份'); noRemote++; }
  if (r.shallow) flags.push('★浅克隆(推不上去，先 git fetch --unshallow)');

  L('● ' + r.label.padEnd(16) + ' ' + (r.rel === '.' ? '(外层)' : r.rel));
  L('    ' + r.note);
  L('    分支 ' + r.branch + '  提交 ' + r.nCommits + '  标签 ' + r.nTags +
    (r.upstream ? '  跟踪 ' + r.upstream : '  ★没设远程跟踪'));
  L('    HEAD ' + (r.head || '?').slice(0, 96));
  L('    远程 ' + (r.remList.length ? r.remList.join(', ') : '★ 无'));
  L('    状态 ' + (flags.length ? flags.join('  ') : '✔ 干净、已推'));
  if (r.nDirty) {
    r.dirty.slice(0, 8).forEach((d) => L('        ' + d.slice(0, 104)));
    if (r.nDirty > 8) L('        … 还有 ' + (r.nDirty - 8) + ' 项');
  }
  L('');
}

L('────────────────────────────────────────');
L('合计：未提交 ' + anyDirty + ' 项' +
  (anyUnpushed ? '　★未推送 ' + anyUnpushed + ' 个 commit' : '　未推送 0') +
  (noRemote ? '　★' + noRemote + ' 个仓库完全没有远程（只存在本盘）' : ''));
L('');
L('读法：');
L('  · 「真源」= minecraft-numen，全部游戏代码在那儿；外层只管流程与门禁。');
L('  · 未提交项多的仓库 = 半成品风险最高的地方，先提交或明确弃用。');
L('  · ★无远程 = 一次磁盘故障就没了，优先补远程。');
L('  · numen 的改动**不进外层 git**，所以 stager/loop-gate 的 commit 判据看不见它——');
L('    要跨仓库对账时看这里，不要只看外层 git log。');
