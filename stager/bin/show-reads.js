'use strict';
// 看那个 AI 到底读了什么、要点写得对不对
const fs = require('fs');
const path = require('path');
const T = 'E:/restart developing doer/stager/.stager/tasks/';
const files = [];
for (const d of fs.readdirSync(T)) {
  const f = path.join(T, d, 'reads.jsonl');
  if (!fs.existsSync(f)) continue;
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/).filter(Boolean);
  if (lines.length) files.push({ task: d, lines });
}
for (const g of files) {
  console.log('══ 任务: ' + g.task);
  const st = JSON.parse(fs.readFileSync(path.join(T, g.task, 'state.json'), 'utf8'));
  console.log('   阶段=' + st.stage + ' 轮=' + st.round);
  g.lines.forEach((l) => {
    const j = JSON.parse(l);
    console.log('   R' + j.round + ' ' + j.stage + '  ' + path.basename(j.file));
    console.log('      要点: ' + j.note);
  });
  console.log('');
}
// 心跳应答去哪了
const hb = path.join(T, 'heartbeat.json');
console.log('══ heartbeat.json 在: ' + (fs.existsSync(hb) ? hb : '不存在'));
if (fs.existsSync(hb)) {
  const j = JSON.parse(fs.readFileSync(hb, 'utf8'));
  console.log('   应答条数: ' + Object.keys(j.acks || {}).length);
  Object.keys(j.acks || {}).forEach((k) => {
    const v = j.acks[k];
    console.log('     ' + k + '  status=' + v.status + '  elapsed=' + v.elapsed);
    console.log('        next=' + v.next);
  });
}