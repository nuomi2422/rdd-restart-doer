// 只改一条：给"岩浆取黑曜石"这条 PROCEDURE 补上"源方块 vs 流动"的判别。
const fs = require('fs');
const file = process.argv[2];
const lines = fs.readFileSync(file, 'utf8').split('\n');
let changed = 0;
const out = lines.map((line) => {
  if (!line.trim() || !line.includes('岩浆取黑曜石')) return line;
  const o = JSON.parse(line);
  o.description = o.description +
    ' **源方块 vs 流动的岩浆**：只有浇在岩浆源（source）上才生成黑曜石；浇在流动的岩浆上只会变成黑石/石头。' +
    '判别：用 inspect_block 看该方块 state 里的 level —— level=0 才是源；流动的 level>0。' +
    '源方块表面是完全平的、不朝任何方向流动。';
  o.observable_signal =
    '扫描到 lava 但水桶未消耗、黑曜石=0 持续 10 分钟以上；' +
    '或水桶已变空桶而黑曜石仍为 0（说明水浇到了流动岩浆/普通地面，没浇在源方块上）。';
  o.verified_count = 1; // 已实机观测到一次失败（2026-10-29 19:45 空桶、黑曜石 0）
  changed++;
  return JSON.stringify(o);
});
if (!changed) { console.log('no-change'); process.exit(0); }
fs.writeFileSync(file, out.join('\n'), 'utf8');
console.log('changed=' + changed);
