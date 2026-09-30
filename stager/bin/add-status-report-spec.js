'use strict';
// 把「状态报告规格」挂进 close 阶段（卡住时 / 收口时必写），并进 read[]
const fs = require('fs');
const P = 'E:/restart developing doer/stager/core/stages.json';
const S = JSON.parse(fs.readFileSync(P, 'utf8'));
const close = S.stages.find((s) => s.id === 'close');
if (!close) { console.log('✘ 找不到 close 阶段'); process.exit(1); }

// 1) read[] 加规格（排第一，那是卡住时要看的）
const SPEC = '自编译统一版/44-状态报告规格.md';
if (!close.read.some((r) => r.includes('44-状态报告规格'))) {
  close.read.unshift(SPEC);
  console.log('✔ close.read 加了 ' + SPEC);
} else console.log('· read 已有');

// 2) ai[] 加指令（插在「① 记录经验」那条之前）
const MARK = '★ 卡在门禁时/收口时：写状态报告（规格见 44-状态报告规格.md）';
if (close.ai.some((x) => x.includes('44-状态报告规格'))) {
  console.log('· ai 已有');
} else {
  const BLOCK = [
    MARK,
    '  触发：①门禁没过且需要用户拍板 ②④收口开始时。其他阶段一切正常 → 不写（否则变噪声）。',
    '  骨架：已完成(带证据) / 顺手修的真缺陷 / 还差N项(请用户拍板·需要什么) / 我没做但已登记的 / 代码状态。',
    '  五条硬要求：①每行有证据 ②区分没做和做了 ③明说差的原因是不是我的问题 ④说清需要什么 ⑤代码状态单列。',
    '  放这个任务自己的 docs\\ 目录，**不要**写进 rdd架构\\自编译统一版\\，**不要**加进任何 read[]。',
  ];
  const i = close.ai.findIndex((x) => /记录：把这次的坑和根因灌进 memory MCP/.test(x));
  if (i < 0) { console.log('✘ 找不到插入点'); process.exit(1); }
  close.ai.splice(i, 0, ...BLOCK);
  console.log('✔ close.ai 插在第 ' + (i + 1) + ' 条之前（' + BLOCK.length + ' 行）');
}

fs.writeFileSync(P, JSON.stringify(S, null, 2) + '\n', 'utf8');
console.log('已写入');
console.log('\n=== close 阶段现在的样子 ===');
console.log('read:'); close.read.forEach((r) => console.log('  - ' + r));
console.log('ai（最后 5 条）:'); close.ai.slice(-5).forEach((a) => console.log('  · ' + a.slice(0, 70)));
