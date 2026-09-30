'use strict';
// 专查唯一真实验任务：修筐1六项缺陷
const fs = require('fs');
const path = require('path');
const R = 'E:/restart developing doer/stager/.stager/tasks/';
const active = JSON.parse(fs.readFileSync('E:/restart developing doer/stager/.stager/active.json', 'utf8')).replace(/^"|"$/g, '');
const D = path.join(R, active);

console.log('任务: ' + active);
const st = JSON.parse(fs.readFileSync(path.join(D, 'state.json'), 'utf8'));
console.log('\n=== state ===');
console.log('  stage=' + st.stage + '  round=' + st.round + '/' + st.maxRounds + '  wrap=' + (st.wrap || 0));
console.log('  actor=' + st.actor + '  status=' + st.status);
console.log('  marks=' + JSON.stringify(st.marks));
console.log('  建档=' + (st.createdAt || '?') + '  最后动=' + st.updatedAt);

const man = JSON.parse(fs.readFileSync(path.join(D, 'docs/manifest.json'), 'utf8'));
console.log('\n=== 文档时间线（按落盘时间真先后）===');
const rows = man.docs.map((d) => {
  const p = path.join(D, 'docs', d.file);
  const s = fs.statSync(p);
  const head = fs.readFileSync(p, 'utf8').split(/\r?\n/).find((l) => l.trim()) || '';
  return { kind: d.kind, file: d.file, mtime: s.mtime, size: s.size, head: head.slice(0, 60) };
});
rows.sort((a, b) => a.mtime - b.mtime);
rows.forEach((r) => {
  console.log('  ' + r.mtime.toISOString().slice(5, 16).replace('T', ' ') +
    '  [' + r.kind.padEnd(10) + '] ' + (r.size + 'B').padStart(7) + '  ' + r.head);
});

console.log('\n=== 门禁对账 ===');
const S = JSON.parse(fs.readFileSync('E:/restart developing doer/stager/core/stages.json', 'utf8'));
const cur = S.stages.find((x) => x.id === st.stage);
console.log('  当前阶段 ' + cur.id + ' 门禁=' + JSON.stringify(cur.gate));
const kinds = man.docs.map((d) => d.kind);
for (const k of (cur.gate.docs || [])) {
  console.log('    doc:' + k + '  ' + (kinds.includes(k) ? '✔ 有' : '✘ 缺'));
}
for (const c of (cur.gate.cmds || [])) {
  const has = (st.marks || {})[(st.round + ':' + st.stage)];
  console.log('    cmd:' + c + '  (当前阶段标记 ' + (has ? '✔' : '✘ 没有') + ')');
}
console.log('\n  文档 kind 统计: ' + JSON.stringify(kinds.reduce((a, k) => (a[k] = (a[k] || 0) + 1, a), {})));