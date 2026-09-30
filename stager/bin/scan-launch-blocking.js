'use strict';
// 找 launch-mc.ps1 哪里会阻塞（只读，不执行）
const fs = require('fs');
const p = 'E:/restart developing doer/rdd-selfcompile/scripts/launch-mc.ps1';
const L = fs.readFileSync(p, 'utf8').split(/\r?\n/);
L.forEach((l, i) => {
  if (/pause|Start-Sleep|Wait-|Read-Host|Start-Process|cmd \/c|\$args|while\s*\{|AutoStopMinutes/.test(l)) {
    console.log(String(i + 1).padStart(3) + '| ' + l.trim().slice(0, 96));
  }
});