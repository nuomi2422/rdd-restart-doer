#!/usr/bin/env node
/**
 * make-rollback.js — 建「stage 流程可运行」回退点（2026-09-30）
 *
 * 为什么需要：E:\restart developing doer 是 git 仓（已有 4 个 commit），
 *   但 **E:\新建文件夹\rdd架构\ 不是仓库** —— 42 份「每阶段必读」的 md 零版本控制。
 *   改坏了没法回退。今天已实测过这个风险：loop-gate 的 INSPECTION 指向
 *   特殊模式/进游戏巡检规范与异常记录.md，那目录被移走后该项永远 block。
 *
 * 所以要两样：
 *   ① 主仓打 git tag（stager + AGENTS.md + 门禁脚本，git 已管）
 *   ② 规则正文打 zip（42 份 md + stages.json + AGENTS双份），落到 rdd存放（用户区）
 *
 * 用法：node make-rollback.js [--note "说明"] [--no-tag]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = 'E:/restart developing doer';
const ARCH = 'E:/新建文件夹/rdd架构';
const OUT = 'E:/新建文件夹/rdd存放';
const STAMP = new Date().toISOString().replace(/[-:]/g, '').slice(0, 15);
const TAG = 'stager-working-' + STAMP;

const arg = (k, d) => {
  const i = process.argv.indexOf(k);
  return i >= 0 ? process.argv[i + 1] : d;
};
const note = arg('--note', 'stage 流程实测可运行：四阶段走通/轮回机制首次触发验证通过/门禁拦4次全对/空壳检测生效/W池探针4-4');

// ── ① 主仓打 tag ────────────────────────────────────────────
if (!process.argv.includes('--no-tag')) {
  try {
    const head = execFileSync('git', ['-C', ROOT, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
    const dirty = execFileSync('git', ['-C', ROOT, 'status', '--porcelain'], { encoding: 'utf8' }).trim();
    if (dirty) {
      console.log('⚠ 工作区有未提交改动，先提交再打 tag：');
      dirty.split('\n').slice(0, 10).forEach((l) => console.log('    ' + l));
      console.log('');
    } else {
      const d = execFileSync('git', ['-C', ROOT, 'describe', '--tags', '--abbrev=0'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
      if (!d) { /* 第一个 tag */ }
      execFileSync('git', ['-C', ROOT, 'tag', '-a', TAG, '-m', note], { stdio: 'inherit' });
      console.log('✔ git tag: ' + TAG + '  →  ' + head + (dirty ? '  (有未提交改动，tag 只标记到 HEAD)' : ''));
    }
  } catch (e) {
    console.log('✘ git tag 失败: ' + String(e.message).split('\n')[0]);
  }
}

// ── ② 规则正文 zip（零版本控制的那半边）────────────────────
const items = [];
const push = (p) => { if (fs.existsSync(p)) items.push(path.relative(ARCH, p).replace(/\\/g, '/')); };

push(ARCH + '/自编译统一版');
push(ARCH + '/self-compile-handoff.md');
push(ARCH + '/更新日志.md');
push(ARCH + '/_memory');                       // ★ 图谱本体（50+ 条经验）
push(ROOT + '/AGENTS.md');
push(ROOT + '/.gitignore');
push(ROOT + '/stager/core/stages.json');
push(ROOT + '/stager/STAGER.md');
push(ROOT + '/stager/README.md');
const cfgDir = 'C:/Users/lenovo/.config/opencode';
for (const f of ['AGENTS.md', 'FLOW-MANDATE.md', 'opencode.json']) push(cfgDir + '/' + f);

// 统计
let files = 0, bytes = 0;
const walk = (base, rel) => {
  const abs = path.join(ARCH, rel);
  for (const e of fs.readdirSync(abs)) {
    const r = rel ? rel + '/' + e : e;
    const full = path.join(ARCH, r);
    if (fs.statSync(full).isDirectory()) walk(base, r);
    else { files++; bytes += fs.statSync(full).size; }
  }
};
items.forEach((i) => walk(ARCH, i));

const listFile = path.join(process.env.TEMP, 'rb-files.txt');
fs.writeFileSync(listFile, items.join('\n'), 'utf8');

fs.mkdirSync(OUT, { recursive: true });
const zip = path.join(OUT, 'RDD-stage流程回退点-' + STAMP + '.zip');
// 用 tar（Windows 自带）代替 Compress-Archive：中文名跨盘符更稳
try {
  execFileSync('tar.exe', ['-a', '-c', '-f', zip, '-C', ARCH, '-C', ROOT, '-C', path.dirname(cfgDir),
    ...items.flatMap((i) => {
      // 绝对路径的项直接给；相对 ARCH 的项已由 -C 处理
      return i.includes(':') ? [i] : [i];
    })], { stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
} catch (e) {
  console.log('✘ tar 失败: ' + String(e.message).split('\n')[0]);
  console.log('  手工等价命令见下方');
}

console.log('');
console.log('待打包 ' + items.length + ' 项 / ' + files + ' 文件 / ' + (bytes / 1024 / 1024).toFixed(1) + ' MB');
console.log('清单: ' + listFile);
console.log('目标 zip: ' + zip + (fs.existsSync(zip) ? '  ✔ ' + (fs.statSync(zip).size / 1024 / 1024).toFixed(1) + ' MB' : '  ✘ 没生成'));
console.log('');
console.log('项:');
items.forEach((i) => console.log('  ' + i));