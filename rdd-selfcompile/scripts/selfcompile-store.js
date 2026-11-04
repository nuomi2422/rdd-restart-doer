// selfcompile-store.js -- 模块化回滚存储管理（按 self-compile-rollback.md 契约实装）
// store: D:\rdd\workspace\rdd-selfcompile\selfcompile\{mutations,candidates,stable,archive}\ + active.json
// 用法:
//   node selfcompile-store.js status
//   node selfcompile-store.js promote -m rdd -v <ver> -jar <path> [--state VERIFIED|CANDIDATE] [--note "..."] [--parent <commit>]
//   node selfcompile-store.js rollback -m rdd [-v <ver>] [--deploy <instance:gpt|test>]
// H1-min 收敛：rollback --deploy 不再自己 copy，改为调用 deploy.ps1；active 在部署成功后合并最新并原子替换。
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const STORE = 'D:\\rdd\\workspace\\rdd-selfcompile\\selfcompile';
const ACTIVE = path.join(STORE, 'active.json');

function readJson(p) { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); }
function readActive() {
  if (!fs.existsSync(ACTIVE)) return { schema_version: 1, modules: {}, updatedAt: new Date().toISOString() };
  return readJson(ACTIVE);
}
function writeActive(j) {
  j.updatedAt = new Date().toISOString();
  const tmp = ACTIVE + '.tmp-' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(j, null, 2), 'utf8');
  fs.renameSync(tmp, ACTIVE);
}
function arg(name, def) { const i = process.argv.indexOf(name); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def; }
function stableVersions(m) {
  const d = path.join(STORE, 'stable', m);
  if (!fs.existsSync(d)) return [];
  return fs.readdirSync(d).filter(n => fs.statSync(path.join(d, n)).isDirectory()).map(v => {
    let man = {}; try { man = readJson(path.join(d, v, 'manifest.json')); } catch (e) {}
    return { version: v, state: man.state || '?', note: man.note || '' };
  });
}

const cmd = process.argv[2] || 'status';
const m = arg('-m');

if (cmd === 'status') {
  const j = readActive();
  console.log('== active.json ==');
  for (const [mod, e] of Object.entries(j.modules || {})) console.log('  ' + mod + ': version=' + e.version + ' state=' + e.state + ' jar=' + e.jar + ' note=' + (e.note || ''));
  if (!Object.keys(j.modules || {}).length) console.log('  (no active modules)');
  console.log('== stable versions ==');
  const mods = fs.existsSync(path.join(STORE, 'stable')) ? fs.readdirSync(path.join(STORE, 'stable')).filter(d => fs.statSync(path.join(STORE, 'stable', d)).isDirectory()) : [];
  for (const mod of mods) { const vs = stableVersions(mod); console.log('  ' + mod + ': ' + vs.map(v => v.version + '[' + v.state + ']').join(', ')); }
  process.exit(0);
}

if (!m) { console.error('need -m <module>'); process.exit(2); }

if (cmd === 'promote') {
  const v = arg('-v'), jar = arg('-jar');
  const state = arg('--state', 'VERIFIED');
  const note = arg('--note', '');
  const parent = arg('--parent', '');
  if (!v || !jar) { console.error('promote needs -v <version> -jar <path>'); process.exit(2); }
  if (!fs.existsSync(jar)) { console.error('jar not found: ' + jar); process.exit(2); }
  const dest = path.join(STORE, 'stable', m, v);
  fs.mkdirSync(dest, { recursive: true });
  const jarName = path.basename(jar);
  fs.copyFileSync(jar, path.join(dest, jarName));
  const man = { module: m, version: v, state, jar: jarName, parent_commit: parent, note, registeredAt: new Date().toISOString() };
  fs.writeFileSync(path.join(dest, 'manifest.json'), JSON.stringify(man, null, 2), 'utf8');
  console.log('promoted ' + m + '@' + v + ' (' + state + ') -> ' + dest);
  if (state === 'VERIFIED') {
    const latest = readActive();
    latest.modules[m] = { version: v, state, jar: path.join(dest, jarName), parent_commit: parent, note, activatedAt: new Date().toISOString() };
    writeActive(latest);
    console.log('active.json: ' + m + ' -> ' + v);
  } else {
    console.log('(CANDIDATE: not set active)');
  }
  process.exit(0);
}

if (cmd === 'rollback') {
  const j = readActive();
  const cur = j.modules[m] ? j.modules[m].version : null;
  const vs = stableVersions(m).filter(x => x.state === 'VERIFIED');
  if (!vs.length) { console.error('no VERIFIED versions for ' + m); process.exit(1); }
  let target = arg('-v');
  if (!target) {
    const cands = vs.filter(x => x.version !== cur);
    if (!cands.length) { console.error('only current (' + cur + ') is VERIFIED; nothing to roll back to'); process.exit(1); }
    target = cands[cands.length - 1].version;
  }
  if (!vs.find(x => x.version === target)) { console.error('version ' + target + ' is not VERIFIED for ' + m); process.exit(1); }
  const stableDir = path.join(STORE, 'stable', m, target);
  const man = readJson(path.join(stableDir, 'manifest.json'));
  const jarPath = path.join(stableDir, man.jar);
  const deploy = arg('--deploy');
  if (deploy) {
    // 收敛：mods 只由 deploy.ps1 写；这里不再自己 copy。
    const ps = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'deploy.ps1'), '-Instance', deploy, '-JarPath', jarPath, '-JarName', man.jar], { encoding: 'utf8' });
    if (ps.status !== 0) {
      console.error('rollback deploy failed: ' + ((ps.stdout || '') + (ps.stderr || '')).trim());
      process.exit(ps.status || 1);
    }
    console.log('deployed via deploy.ps1: ' + man.jar);
  } else {
    console.log('(not deployed; add --deploy gpt|test to deploy via deploy.ps1)');
  }
  const latest = readActive();
  latest.modules[m] = { version: target, state: 'VERIFIED', jar: jarPath, note: man.note, activatedAt: new Date().toISOString() };
  writeActive(latest);
  console.log('rollback: ' + m + ' ' + cur + ' -> ' + target);
  console.log('active jar: ' + jarPath);
  process.exit(0);
}

console.error('unknown cmd ' + cmd);
process.exit(2);
