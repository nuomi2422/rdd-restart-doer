'use strict';
/**
 * 加「检索侧」：目前经验库是「只写不读」——
 *   写侧有规则（AGENTS.md:96「① 记录经验 → 灌进 memory MCP」）
 *   检索侧没有任何规则叫 AI 去查 → 库里有 40+ 条真经验，但我一整轮一次都没主动查过。
 * 修法：每个阶段 ai[] 开头加一句「动手前先查经验库」，不写新代码，只改数据。
 */
const fs = require('fs');
const P = 'E:/restart developing doer/stager/core/stages.json';
const S = JSON.parse(fs.readFileSync(P, 'utf8'));

const PROBE = [
  '★ 动手前先查经验库（memory MCP 只写不读，必须自己开）：',
  '  memory_search_nodes("<本阶段关键词>")  —— 关键词按阶段换：',
  '    plan=计划/架构/互审  implement=改码/模块/gradle/接口  verify=验证/卡死/假成功/巡检  close=收工/清理/经验',
  '  查到相关条目 → 先读完再动手，别重复踩；查不到 → 照常做，收工时写进去（④第①步）。',
];

let n = 0;
for (const st of S.stages) {
  if (st.ai && st.ai[0] && st.ai[0].includes('memory_search_nodes')) { console.log('  已有，跳过: ' + st.id); continue; }
  st.ai.unshift(...PROBE);
  n++;
  console.log('  ✔ ' + st.id + ' 加了检索侧');
}
fs.writeFileSync(P, JSON.stringify(S, null, 2) + '\n', 'utf8');
console.log('共改 ' + n + ' 个阶段');
