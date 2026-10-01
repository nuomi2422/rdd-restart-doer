'use strict';
// stager 现状总览：命令 / 新机制 / 当前状态
const fs = require('fs');
const path = require('path');
const ROOT = 'E:/restart developing doer';
const BIN = ROOT + '/stager/bin/stager.js';
const T = ROOT + '/stager/.stager/';

const src = fs.readFileSync(BIN, 'utf8');
const cmds = [...new Set([...src.matchAll(/^CMD\.([A-Za-z0-9_]+)\s*=/gm)].map((m) => m[1]))].sort();

console.log('══ stager 命令（' + cmds.length + ' 个）══');
const ALIAS = {
  start: '开任务', resume: '接未关档', list: '列全部', close: '关档',
  next: '下一阶段', loop: '本轮回①', round: '手动+1轮', enter: '跳阶段',
  implement: '打标记(=verify|mark)', mark: '打标记', swap: '换人次',
  put: '存文档', docs: '列文档', status: '状态', ctx: '注入包', check: '门禁',
  log: '事件流', progress: '看板', publish: '放到用户目录', pet: '起桌宠',
  web: '起看板', install: '注册插件', uninstall: '注销', selfTest: '自测', concTest: '并发测',
  hb: '★心跳应答', read: '★读后复述', waive: '★豁免记账',
};
cmds.forEach((c) => console.log('  ' + c.padEnd(11) + (ALIAS[c] || '')));

console.log('');
console.log('══ 门禁（stager.js 内置 + 外挂）══');
['stager check            → 阶段门禁（doc/cmd/豁免/空壳签名/外脑/读档/心跳）',
 'rdd-selfcompile/scripts/flow-gate.js  → 自编译闭环（sha/回滚点/phase 记录）',
 'rdd-selfcompile/scripts/loop-gate.js  → 九步流 20 项',
 'rdd-selfcompile/scripts/verify.ps1   → 证据 VERIFIED 判定'].forEach((l) => console.log('  ' + l));

console.log('');
console.log('══ 配套脚本 ══');
[
  'rdd-selfcompile/scripts/w-probe.js           W池主动探针（4家可用性）',
  'rdd-selfcompile/scripts/w-brain-drive.js      浏览器直驱（--file 修传参）',
  'rdd-selfcompile/scripts/codex-visible.js     codex 看得见进度',
  'rdd-selfcompile/scripts/adversarial-review.js 独立对抗审计',
  'rdd-selfcompile/scripts/stage-heartbeat.js   独立心跳看门狗（已加总闸式默认关）',
  'rdd-selfcompile/scripts/run-mutation.ps1     唯一改码入口',
  'rdd-selfcompile/scripts/autostart-dev.ps1     开机自启（watchdog 已改默认不起）',
].forEach((l) => console.log('  ' + l));

console.log('');
console.log('══ 当前状态 ══');
let act = null;
try { act = JSON.parse(fs.readFileSync(T + 'active.json', 'utf8')); } catch (e) {}
if (!act) console.log('  active = 无（没有进行中的 stage）');
else {
  const d = path.join(T, 'tasks', act);
  const st = JSON.parse(fs.readFileSync(path.join(d, 'state.json'), 'utf8'));
  const man = JSON.parse(fs.readFileSync(path.join(d, 'docs/manifest.json'), 'utf8'));
  console.log('  任务: ' + act.slice(0, 60));
  console.log('  ' + st.stage + '  第 ' + st.round + '/' + st.maxRounds + ' 轮  轮回 ' + (st.wrap || 0) + '  ' + st.actor);
  const kinds = man.docs.reduce((a, k) => (a[k.kind] = (a[k.kind] || 0) + 1, a), {});
  console.log('  文档 ' + man.docs.length + ' 份: ' + JSON.stringify(kinds));
  const rd = path.join(d, 'reads.jsonl');
  if (fs.existsSync(rd)) console.log('  读档记录: ' + fs.readFileSync(rd, 'utf8').split('\n').filter(Boolean).length + ' 条');
  console.log('  最后动: ' + String(st.updatedAt).slice(0, 19).replace('T', ' '));
}

console.log('');
console.log('══ 回退点 ══');
const { execFileSync } = require('child_process');
console.log('  ' + execFileSync('git', ['-C', ROOT, 'tag', '-l'], { encoding: 'utf8' }).trim().split('\n').map((t) => '  ' + t).join('\n').slice(3));