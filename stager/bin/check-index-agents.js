'use strict';
// 只报真问题：标题被吞 + 路径缺失 + 奇怪的 ? 字符
const fs = require('fs');
const FENCE = '```';
let bad = 0;

for (const f of ['D:/rdd/workspace/AGENTS.md', 'D:/rdd/docs/rdd-docs/rdd架构/自编译统一版/10-计划阶段.md']) {
  const t = fs.readFileSync(f, 'utf8');
  const L = t.split(/\r?\n/);
  const name = f.split('/').pop();
  console.log('════ ' + name);

  // 1) 代码块内不许有 # 标题（= 闭合漏了）
  let open = -1, openLang = '';
  L.forEach((l, i) => {
    const s = l.trim();
    if (s.startsWith(FENCE)) {
      if (open < 0) { open = i; openLang = s.slice(3) || '(无语言)'; }
      else { open = -1; openLang = ''; }
    } else if (open >= 0 && /^#{1,4}\s/.test(l)) {
      // powershell/text 块里出现 # 注释是正常的，只有 markdown 块里出现标题才是吞了
      const suspicious = /^(bash|text|无语言|\(无语言\))/.test(openLang) || openLang === '';
      if (suspicious) {
        console.log('  ✘ 第 ' + (i + 1) + ' 行「' + s.slice(0, 32) + '」被包在 ```' + openLang + ' 块里（第 ' + (open + 1) + ' 行开的没关）');
        bad++;
      }
    }
  });

  // 2) 路径存在性
  [...new Set([...t.matchAll(/D:\\rdd\\docs\\rdd-docs\\rdd架构\\自编译统一版\\[^\s（`]+\.md/g)].map((m) => m[0].replace(/\\/g, '/')))].forEach((p) => {
    if (!fs.existsSync(p)) { console.log('  ✘ 文件不存在: ' + p); bad++; }
  });

  // 3) 坏字符 ?  出现在框线里
  L.forEach((l, i) => {
    if (/[├└│─]\?/.test(l)) { console.log('  ✘ 第 ' + (i + 1) + ' 行框线坏字符: ' + l.trim().slice(0, 30)); bad++; }
  });

  // 4) 标题当路径抄
  L.forEach((l, i) => {
    if (/^\s*#\s+\d+.*[（(].*）/.test(l) && !/^#{1,4}\s/.test(l)) { console.log('  ✘ 第 ' + (i + 1) + ' 行像标题不是路径'); bad++; }
  });

  console.log('  —— 该文件检查完毕');
  console.log('');
}
console.log(bad === 0 ? '★ 真问题：0' : '★ 真问题：' + bad + ' 处');
