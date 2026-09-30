/**
 * 把 STAGER.md 的阶段表按 core/stages.json 重新生成（防止文档和真源不同步）。
 * 用法：node sync-stager-doc.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const S = JSON.parse(fs.readFileSync(path.join(ROOT, 'core', 'stages.json'), 'utf8'));
const P = path.join(ROOT, 'STAGER.md');

function gateText(x) {
  const g = [];
  if (x.gate && x.gate.docs) x.gate.docs.forEach((d) => g.push('--kind ' + d));
  if (x.gate && x.gate.cmds) x.gate.cmds.forEach((d) => g.push('mark ' + d));
  return g.join('  +  ') || '无';
}

const rows = S.stages.map((x) =>
  '| ' + x.icon + ' ' + x.name + ' `' + x.id + '` | ' + gateText(x) + ' | ' + String(x.brief).split('。')[0] + ' |'
).join('\n');

const table = '| 阶段 | 门禁要求 | 动作 |\n|---|---|---|\n' + rows;

let t = fs.readFileSync(P, 'utf8');
const before = t;
t = t.replace(/\| 阶段 \| 门禁要求 \| 动作 \|\n\|---\|---\|---\|\n[\s\S]*?(?=\n\n)/, table);
if (t === before) {
  console.log('STAGER.md 阶段表：已是最新的（没找到可替换的旧表）');
} else {
  fs.writeFileSync(P, t, 'utf8');
  console.log('STAGER.md 阶段表已按 core/stages.json 同步（' + S.stages.length + ' 阶段）');
}
