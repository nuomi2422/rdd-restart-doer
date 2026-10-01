'use strict';
// 找这段注入的真正来源（进程已杀但还在发 → 源头另有其人）
const fs = require('fs');
const path = require('path');
const NEEDLE = '纯文字回复等于这一轮白干';
const ALT = ['不要只回话', '白干', 'WATCHDOG/self-drive'];

const ROOTS = [
  'E:/restart developing doer',
  'E:/新建文件夹/rdd架构',
  'C:/Users/lenovo/.config/opencode',
];
const SKIP = /\\(node_modules|\.git|\.gradle|build|\.stager|_废弃|给用户|文档|报告)\\?/;

let hits = 0;
for (const R of ROOTS) {
  if (!fs.existsSync(R)) continue;
  const walk = (d, depth) => {
    if (depth > 6) return;
    let items = [];
    try { items = fs.readdirSync(d); } catch (e) { return; }
    for (const it of items) {
      const p = path.join(d, it);
      let st;
      try { st = fs.statSync(p); } catch (e) { continue; }
      if (st.isDirectory()) { if (!SKIP.test(p)) walk(p, depth + 1); continue; }
      if (!/\.(ps1|js|mjs|json|md|txt|cmd|bat|ts)$/i.test(it)) continue;
      if (st.size > 4 * 1024 * 1024) continue;
      let body = '';
      try { body = fs.readFileSync(p, 'utf8'); } catch (e) { continue; }
      if (body.indexOf(NEEDLE) >= 0 || ALT.every((a) => body.indexOf(a) >= 0)) {
        console.log('★ 命中: ' + p);
        body.split(/\r?\n/).forEach((l, i) => {
          if (l.indexOf(NEEDLE) >= 0 || ALT.some((a) => l.indexOf(a) >= 0)) {
            console.log('    行' + (i + 1) + ': ' + l.trim().slice(0, 150));
          }
        });
        hits++;
      }
    }
  };
  walk(R, 0);
}
console.log('');
console.log(hits === 0 ? '没在磁盘上找到 —— 说明是运行时拼出来的（脚本里各句分开拼）' : '共 ' + hits + ' 处');