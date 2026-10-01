#!/usr/bin/env node
/**
 * 建 E:\新建文件夹\rddharness —— 快捷启动集合（2026-10-01 用户要求）
 *
 * 目的：用户说「以后我也好方便启动」—— 所有要双击的东西收在一处。
 * 只做【复制】，原件留在原位（单一真源），这里当启动台。
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const DEST = 'E:/新建文件夹/rddharness';
const R = 'E:/restart developing doer';

const ITEMS = [
  { file: 'stager-pet.bat', from: R + '/rdd-selfcompile/stager-pet.bat', what: '起桌宠（已开就不重复开）', stop: 'stop-stager-pet.bat' },
  { file: 'stop-stager-pet.bat', from: R + '/rdd-selfcompile/stop-stager-pet.bat', what: '关桌宠' },
  { file: 'stager-heartbeat.bat', from: R + '/rdd-selfcompile/stager-heartbeat.bat', what: '起心跳看门狗（阶段超时会问 AI 要答案）' },
  { file: 'stager-dashboard.bat', from: R + '/rdd-selfcompile/stager-dashboard.bat', what: '起网页看板 8899' },
  { file: 'stop-stager-web.bat', from: R + '/rdd-selfcompile/stop-stager-web.bat', what: '关网页看板' },
  { file: 'stager.bat', from: R + '/stager/stager.bat', what: 'stager 控制台（status/ctx/check/next）' },
  { file: 'monitoring-autostart.bat', from: R + '/rdd-selfcompile/scripts/autostart-dev.ps1', what: '监测台 8776 + watchdog + AI Bridge 浏览器' },
];

fs.mkdirSync(DEST, { recursive: true });
console.log('建在: ' + DEST);
console.log('');

let n = 0;
for (const it of ITEMS) {
  const src = it.from;
  if (!fs.existsSync(src)) { console.log('  ✘ 缺源: ' + it.file); continue; }
  const dst = path.join(DEST, it.file);
  fs.copyFileSync(src, dst);
  // .ps1 直接双击不会执行（默认关联是编辑器）→ 给它配一个同名 .bat 包装
  console.log('  ✔ ' + it.file.padEnd(28) + it.what);
  n++;
}
console.log('');
console.log('共 ' + n + ' 个');

// ── monitoring 的 .ps1 加 .bat 包装（双击能跑）────────────────
const PS1_BAT = [
  '@echo off',
  'chcp 65001 >nul',
  'title RDD Monitoring Autostart',
  'echo Starting monitoring station + watchdog + AI Bridge browser...',
  'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\\restart developing doer\\rdd-selfcompile\\scripts\\autostart-dev.ps1"',
  'echo.',
  'echo Done. Monitoring: http://127.0.0.1:8776/',
  'ping -n 4 127.0.0.1 >nul',
  'exit /b 0',
  '',
].join('\r\n');
fs.writeFileSync(path.join(DEST, 'run-autostart.bat'), PS1_BAT, 'utf8');
console.log('  ✔ run-autostart.bat            （.ps1 的双击包装）');

console.log('');
console.log('下一步：写总菜单 + 说明');