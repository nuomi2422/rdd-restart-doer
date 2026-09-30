'use strict';
/**
 * 修 w-brain-drive.js 的「问题传不全」
 *
 * 根因：:355 `const [,, cmd, a1, a2] = process.argv` 只取固定位置。
 *   askall "完整问题"      → argv[3] 拿到完整 ✔
 *   askall 完整问题 有空格  → argv[3]="完整问题"，argv[4]="有空格" → a1 只有前半截 ★
 *   askall 含换行的代码块   → 只剩第一行 ★
 *   PS 单双引号/反引号/$ 还会在传参前被展开（见 AGENTS.md 第6条那两条坑）
 *
 * 修法（都向后兼容，不破坏现有调用）：
 *   ① 新增 --file <路径>：问题从文件读，绕开一切 shell 引号规则（最稳，推荐长问题/代码块用）
 *   ② ask <平台> <问题…>：把 argv[3..] 全部用空格拼回（未加引号时不再丢）
 *   ③ askall <问题…>：同上，argv[3..] 全拼
 *   ④ 仍支持直接传字符串（老用法不变）
 */
const fs = require('fs');
const P = 'E:/restart developing doer/rdd-selfcompile/scripts/w-brain-drive.js';
let t = fs.readFileSync(P, 'utf8');
const before = t;

// ① 替换参数解析那行
const OLD = "const [,, cmd, a1, a2] = process.argv;";
const NEW = [
  "const argvRest = process.argv.slice(2);",
  "const cmd = argvRest[0];",
  "// ★ 2026-09-30 修「问题传不全」：原来只取 argv[3]/argv[4]，",
  "//   问题里有空格没加引号 → 只剩前半截；含换行的代码块 → 只剩第一行。",
  "//   现在：(a) 支持 --file <路径> 从文件读；(b) 其余参数用空格拼回，不丢。",
  "const rest = argvRest.slice(1);",
  "let a1 = rest[0];",
  "let a2 = rest.slice(1).join(' ');",
  "if (a1 === '--file' || a1 === '-f') {",
  "  const fp = rest[1];",
  "  if (!fp || !fs.existsSync(fp)) {",
  "    console.log(JSON.stringify({ ok: false, why: 'file not found: ' + fp }));",
  "    process.exit(1);",
  "  }",
  "  const body = fs.readFileSync(fp, 'utf8').trim();",
  "  // --file 之后可能还有平台名（ask 模式）：node x.js ask --file q.txt glm",
  "  const tail = rest.slice(2).filter(Boolean);",
  "  a1 = tail[0] || '';",
  "  a2 = body;",
  "} else if (cmd === 'ask') {",
  "  // ask <平台> <问题…>  → 问题 = rest.slice(1) 全拼（原来只取 rest[1]）",
  "  a1 = rest[0];",
  "  a2 = rest.slice(1).join(' ');",
  "} else {",
  "  // askall <问题…>  → 问题 = rest 全拼",
  "  a1 = rest.join(' ');",
  "  a2 = '';",
  "}",
].join('\n');

if (!t.includes(OLD)) {
  console.log('✘ 没找到那行：' + OLD);
  process.exit(1);
}
t = t.replace(OLD, NEW);

// ② 用法说明补 --file
t = t.replace(
  "//   node w-brain-drive.js askall \"问题文本\"            → 依次问 GLM/Qwen/Kimi 三家并汇总",
  "//   node w-brain-drive.js askall \"问题文本\"            → 依次问 GLM/Qwen/Kimi 三家并汇总\n" +
  "//   node w-brain-drive.js askall --file q.txt          → ★ 问题从文件读（长文本/代码块用这个）\n" +
  "//   node w-brain-drive.js ask glm --file q.txt         → ★ 单家 + 文件"
);

if (t !== before) {
  fs.writeFileSync(P, t, 'utf8');
  console.log('✔ 已写入');
} else {
  console.log('★ 没变化');
}