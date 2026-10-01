// 备份 opencode.json（2026-09-30）
// 为什么不能靠 git：体检发现里面有 2 个真实 API key
//   provider.openrouter.options.apiKey = sk-or-v1-...
//   provider.moyuu.options.apiKey     = sk-z2Rn...
// 进了 git 就是密钥公开。只能放本机 + 定期快照。
'use strict';
const fs = require('fs');
const path = require('path');

const CFG = 'C:/Users/lenovo/.config/opencode/opencode.json';
const OUT_DIR = 'E:/新建文件夹/rdd-docs/rdd存放/配置备份';
const STAMP = new Date().toISOString().replace(/[-:]/g, '').slice(0, 15);
const raw = fs.readFileSync(CFG, 'utf8');
fs.mkdirSync(OUT_DIR, { recursive: true });

const out = path.join(OUT_DIR, 'opencode-' + STAMP + '.json');
fs.writeFileSync(out, raw, 'utf8');

// 也留一份 latest（方便直接对比）
fs.writeFileSync(path.join(OUT_DIR, 'opencode-latest.json'), raw, 'utf8');

// 顺带体检有没有密钥，提醒别把备份目录提交进 git
const j = JSON.parse(raw);
const secrets = [];
Object.keys(j.provider || {}).forEach((k) => {
  const o = (j.provider[k] || {}).options || {};
  if (o.apiKey) secrets.push(k);
});

console.log('✔ 已备份: ' + out + '  (' + (raw.length / 1024).toFixed(1) + ' KB)');
console.log('✔ latest:  ' + path.join(OUT_DIR, 'opencode-latest.json'));
console.log('');
console.log('⚠ 该目录含 ' + secrets.length + ' 个 provider 的 API key（' + secrets.join(', ') + '）');
console.log('  → 别提交进 git。已确保 .gitignore 没覆盖它，但 E:\\新建文件夹 也不在本仓。');
console.log('');
console.log('回退方法：把 opencode-latest.json 复制回 ~/.config/opencode/opencode.json，重启 opencode。');

// 顺手查一下 gitignore 有没有误伤这个目录
try {
  const ig = fs.readFileSync('E:/restart developing doer/.gitignore', 'utf8');
  const bad = ig.split(/\r?\n/).filter((l) => l.trim() && /配置备份|opencode-/.test(l));
  console.log(bad.length ? '  ★ .gitignore 里有相关规则: ' + bad.join(', ') : '  ✔ .gitignore 没误伤');
} catch (e) {}