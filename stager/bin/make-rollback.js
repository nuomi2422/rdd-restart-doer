'use strict';
/**
 * make-rollback.js — 建「stage 流程可运行」回退点
 * v2 修：① 首次打 tag 时 describe 报错（原脚本没容错）
 *      ② walk 遇到单文件（self-compile-handoff.md 是文件不是目录）
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = 'E:/restart developing doer';
const ARCH = 'E:/新建文件夹/rdd-docs/rdd架构';
const OUT = 'E:/新建文件夹/rdd-docs/rdd存放';
const CFG = 'C:/Users/lenovo/.config/opencode';
const STAMP = new Date().toISOString().replace(/[-:]/g, '').slice(0, 15);
const TAG = 'stager-working-' + STAMP;

const arg = (k, d) => { const i = process.argv.indexOf(k); return i >= 0 ? process.argv[i + 1] : d; };
const note = arg('--note', 'stage 流程实测可运行');
const sh = (cmd, a, o) => execFileSync(cmd, a, Object.assign({ encoding: 'utf8' }, o || {}));

// ── ① git tag ────────────────────────────────────────────────
try {
  const head = sh('git', ['-C', ROOT, 'rev-parse', '--short', 'HEAD']).trim();
  const dirty = sh('git', ['-C', ROOT, 'status', '--porcelain']).trim();
  try { sh('git', ['-C', ROOT, 'describe', '--tags', '--abbrev=0'], { stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch (e) { /* 仓库还没有任何 tag，正常 */ }
  if (dirty) console.log('⚠ 工作区有未提交改动（tag 只标记到 HEAD）:');
  sh('git', ['-C', ROOT, 'tag', '-a', TAG, '-m', note], { stdio: ['ignore', 'pipe', 'ignore'] });
  console.log('✔ git tag: ' + TAG + '  →  ' + head);
} catch (e) {
  console.log('✘ git tag 失败: ' + String(e.message).split('\n')[0]);
}

// ── ② 收齐要打的包（分「相对 ARCH 的」和「绝对路径的」）───
const rel = ['自编译统一版', '_memory'];
// rdd架构 顶层所有 .md（不写死名字，那个日志文件名对不上）
fs.readdirSync(ARCH).filter((f) => f.endsWith('.md')).forEach((f) => rel.push(f));
const abs = [
  ROOT + '/AGENTS.md', ROOT + '/.gitignore',
  ROOT + '/stager/core/stages.json', ROOT + '/stager/STAGER.md', ROOT + '/stager/README.md',
  CFG + '/AGENTS.md', CFG + '/FLOW-MANDATE.md', CFG + '/opencode.json',
];

let files = 0, bytes = 0;
const count = (p) => {
  const st = fs.statSync(p);
  if (st.isDirectory()) {
    for (const e of fs.readdirSync(p)) count(path.join(p, e));
  } else { files++; bytes += st.size; }
};
const missing = [];
rel.forEach((r) => { const p = path.join(ARCH, r); if (fs.existsSync(p)) count(p); else missing.push(p); });
abs.forEach((p) => { if (fs.existsSync(p)) count(p); else missing.push(p); });

console.log('待打包 ' + (rel.length + abs.length) + ' 项 / ' + files + ' 文件 / ' + (bytes / 1048576).toFixed(1) + ' MB');
if (missing.length) { console.log('⚠ 缺: ' + missing.join(', ')); }

fs.mkdirSync(OUT, { recursive: true });
const zip = path.join(OUT, 'RDD-stage流程回退点-' + STAMP + '.zip');
try {
  const args = ['-a', '-c', '-f', zip, '-C', ARCH, ...rel, '-C', ROOT,
    'AGENTS.md', '.gitignore', 'stager/core/stages.json', 'stager/STAGER.md', 'stager/README.md',
    '-C', CFG, 'AGENTS.md', 'FLOW-MANDATE.md', 'opencode.json'];
  sh('tar.exe', args, { stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1048576 });
  console.log('✔ zip: ' + zip);
  console.log('  ' + (fs.statSync(zip).size / 1048576).toFixed(1) + ' MB');
} catch (e) {
  console.log('✘ tar 失败: ' + String(e.message).split('\n')[0]);
}

console.log('');
console.log('══ 回退方法 ══');
console.log('代码/脚本/AGENTS.md:  git -C "' + ROOT + '" checkout ' + TAG);
console.log('规则正文 42 份 md:    用 rdd存放\\RDD-stage流程回退点-' + STAMP + '.zip 解压覆盖');
console.log('图谱 memory.json:     同上（在 _memory\\ 下）');
console.log('看有哪些 tag:        git -C "' + ROOT + '" tag');