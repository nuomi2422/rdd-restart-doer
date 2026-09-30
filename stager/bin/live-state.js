'use strict';
// 实时读任务状态 + 找操作历史（AI 是怎么从 verify 走到 plan 的）
const fs = require('fs');
const path = require('path');
const T = 'E:/restart developing doer/stager/.stager/';
const active = JSON.parse(fs.readFileSync(T + 'active.json', 'utf8')).replace(/^"|"$/g, '');
const D = path.join(T, 'tasks', active);

const st = JSON.parse(fs.readFileSync(path.join(D, 'state.json'), 'utf8'));
console.log('=== 当前 state（实时）===');
console.log('  stage   = ' + st.stage);
console.log('  round   = ' + st.round + '/' + st.maxRounds);
console.log('  wrap    = ' + (st.wrap || 0));
console.log('  status  = ' + st.status);
console.log('  marks   = ' + JSON.stringify(st.marks));
console.log('  最后改动 = ' + st.updatedAt);

console.log('\n=== 任务目录里所有文件（看有没有日志/history）===');
const walk = (d, pre) => {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    const s = fs.statSync(p);
    if (s.isDirectory()) walk(p, pre + f + '/');
    else console.log('  ' + s.mtime.toISOString().slice(5, 16).replace('T', ' ') + '  ' + (pre + f));
  }
};
walk(D, '');

console.log('\n=== stager 根目录（找全局日志）===');
fs.readdirSync(T).forEach((f) => {
  const p = path.join(T, f);
  const s = fs.statSync(p);
  console.log('  ' + (s.isDirectory() ? 'd ' : 'f ') + f + (s.isDirectory() ? '' : '  ' + s.size + 'B'));
});
for (const f of ['log.jsonl', 'history.jsonl', 'events.jsonl', '.log']) {
  const p = path.join(T, f);
  if (fs.existsSync(p)) {
    console.log('\n=== ' + f + ' 最后 15 行 ===');
    fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean).slice(-15).forEach((l) => console.log('  ' + l.slice(0, 160)));
  }
}