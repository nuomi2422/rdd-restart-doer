'use strict';
// 1) 撤回塞进 stages.json 的那 15 行（规矩该在 12-进游戏验证工具集.md，不是索引里）
const fs = require('fs');
const P = 'E:/restart developing doer/stager/core/stages.json';
const S = JSON.parse(fs.readFileSync(P, 'utf8'));
const v = S.stages.find((s) => s.id === 'verify');
const i = v.ai.findIndex((x) => x.includes('起游戏：三条硬规矩'));
if (i < 0) { console.log('· stages.json 里没找到（可能已撤回）'); }
else {
  // 从那行删到下一个空行之后（整块）
  let j = i;
  while (j < v.ai.length && !/memory_search_nodes|记录：把这次的坑/.test(v.ai[j]) && j - i < 20) {
    if (v.ai[j] === '' && j > i + 1) break;
    j++;
  }
  const removed = v.ai.splice(i, j - i);
  fs.writeFileSync(P, JSON.stringify(S, null, 2) + '\n', 'utf8');
  console.log('✔ 从 verify.ai 撤回 ' + removed.length + ' 行');
}
