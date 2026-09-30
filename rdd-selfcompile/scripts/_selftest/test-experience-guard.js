const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const GUARD = 'E:/restart developing doer/rdd-selfcompile/scripts/experience-guard.js';
const TMP = 'C:/Users/lenovo/AppData/Local/Temp/opencode/guard-test';
fs.rmSync(TMP, { recursive: true, force: true });
fs.mkdirSync(TMP, { recursive: true });

const store = path.join(TMP, 'experience-test.jsonl');
const payload = path.join(TMP, 'seed.json');

let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { pass++; console.log('  [ok]   ' + name); }
  else { fail++; console.log('  [FAIL] ' + name + (detail ? '  <- ' + detail : '')); }
}
function run(args) {
  try { return { code: 0, out: execFileSync('node', [GUARD, ...args], { encoding: 'utf8' }) }; }
  catch (e) { return { code: e.status || 1, out: (e.stdout || '') + (e.stderr || '') }; }
}

// --- 场景 1：正常库，append 种子 -> 应通过 ---
const good = [
  { id: 'fail|原有经验A', type: 'FAILURE', title: '原有经验A' },
  { id: 'ok|原有经验B', type: 'POLICY', title: '原有经验B' },
];
fs.writeFileSync(store, JSON.stringify(good), 'utf8');
fs.writeFileSync(payload, JSON.stringify([{ id: 'fail|新种子', type: 'FAILURE', title: '新种子' }]), 'utf8');
let r = run(['--backup-and-append', store, '--json', payload]);
check('正常库 append 被接受', r.code === 0, r.out.slice(0, 120));
check('条目数 2 -> 3', JSON.parse(fs.readFileSync(store, 'utf8')).length === 3);
check('产生了备份文件', fs.readdirSync(TMP).some(f => f.includes('.pre-append-') && f.endsWith('.bak')));

// --- 场景 2：损坏的库（就是今天出事的那种）-> 必须拒绝 ---
fs.writeFileSync(store, '{"broken": tru', 'utf8');   // 故意不可解析
r = run(['--append', store, '--json', payload]);
check('不可解析的库被拒绝写入', r.code !== 0, 'exit=' + r.code);
check('拒绝时给出明确原因', /REFUSED/.test(r.out), r.out.slice(0, 160));
check('损坏文件未被改写', fs.readFileSync(store, 'utf8') === '{"broken": tru');

// --- 场景 3：顶层不是数组 -> 拒绝 ---
fs.writeFileSync(store, '{"a":1}', 'utf8');
r = run(['--append', store, '--json', payload]);
check('非数组的库被拒绝', r.code !== 0, 'exit=' + r.code);
check('文件未被改写', fs.readFileSync(store, 'utf8') === '{"a":1}');

// --- 场景 4：种子缺 stable id -> 拒绝（否则无法去重，等于盲写）---
fs.writeFileSync(store, JSON.stringify(good), 'utf8');
fs.writeFileSync(payload, JSON.stringify([{ type: 'FAILURE', title: '无 id' }]), 'utf8');
r = run(['--append', store, '--json', payload]);
check('缺 stable id 的种子被拒绝', r.code !== 0, 'exit=' + r.code);
check('库未被污染', JSON.parse(fs.readFileSync(store, 'utf8')).length === 2);

// --- 场景 5：重复种子不产生重复条目（append-only 幂等）---
fs.writeFileSync(payload, JSON.stringify([{ id: 'fail|原有经验A', type: 'FAILURE', title: '原有经验A' }]), 'utf8');
r = run(['--append', store, '--json', payload]);
check('重复 id 不新增条目', JSON.parse(fs.readFileSync(store, 'utf8')).length === 2, r.out.slice(0, 100));

// --- 场景 6：--check 体检 ---
r = run(['--check', store]);
check('--check 通过时 exit 0', r.code === 0, r.out.slice(0, 100));
fs.writeFileSync(store, 'not json at all', 'utf8');
r = run(['--check', store]);
check('--check 遇到坏库 exit != 0', r.code !== 0);

console.log('\n-------------------------------------------');
console.log('PASS=' + pass + '  FAIL=' + fail);
console.log(fail === 0 ? 'GUARD WORKS: 能挡住 2026-09-29 那次数据丢失' : 'GUARD INCOMPLETE');
process.exit(fail === 0 ? 0 : 1);
