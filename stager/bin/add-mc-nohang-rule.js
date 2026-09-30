'use strict';
// 把「起游戏必卡死」写进 ③游戏验证 阶段（用户 2026-09-30 要求：常常有 AI 卡在这）
const fs = require('fs');
const P = 'E:/restart developing doer/stager/core/stages.json';
const S = JSON.parse(fs.readFileSync(P, 'utf8'));
const v = S.stages.find((s) => s.id === 'verify');
if (!v) { console.log('✘ 找不到 verify'); process.exit(1); }

// 插到「动手前先查经验库」那条之后（那是第一条）
const AFTER = v.ai.findIndex((x) => /memory_search_nodes/.test(x));
if (v.ai.some((x) => x.includes('起游戏必卡死') || x.includes('禁止前台等'))) {
  console.log('· 已存在，跳过');
} else {
  const BLOCK = [
    '',
    '★★ 起游戏：三条硬规矩（2026-09-30 用户两次当场纠正，写进规则）★★',
    '  ① 先查是不是已经在跑：mc-instance.ps1 的 Test-RddMcRunning / Get-RddMcProcess。',
    '     ★ 游戏常常已经开着（用户自己起的）—— 查完在跑就【绝对不要再碰启动】，直接往下做。',
    '  ② 要起，只准这一个动作（脱离，不等）：',
    '       Start-Process powershell -ArgumentList \'-NoProfile -ExecutionPolicy Bypass -File "E:\\restart developing doer\\rdd-selfcompile\\scripts\\launch-mc.ps1" -Instance gpt -AutoStopMinutes 10\' -WindowStyle Minimized',
    '  ③ 【禁止】在 shell 里前台等任何超过 10 秒的东西。起完立刻返回，下一条命令再查状态。',
    '',
    '  ⚠ 已知的两种假象，别顺着它查下去：',
    '    · 「java 进程一直是 0」→ 可能 launch-mc 根本没被成功调用（参数绑定失败），不是 OOM、不是 mod 崩。',
    '      真因见 mc-instance.ps1:65-83（$args 是保留自动变量 + @(...) 按位置传参 → 游戏从没启动）。',
    '    · 「屏幕黑了/加载不动」→ 先查内存：FreePhysicalMemory < 1200MB 就是不够，',
    '      直接告诉用户「关点浏览器」，不要改代码（今天已经因此误判成 JPMS 冲突浪费一轮）。',
    '  ★ 判断依据要分清「命令 success」和「事情发生了」：起没起看实际 java 进程 + latest.log 增长，',
    '    不是看脚本返回成功。',
  ];
  v.ai.splice(AFTER + 1, 0, ...BLOCK);
  console.log('✔ verify.ai 插入 ' + BLOCK.length + ' 行（在第 ' + (AFTER + 1) + ' 条之后）');
}
fs.writeFileSync(P, JSON.stringify(S, null, 2) + '\n', 'utf8');
console.log('已写入');
