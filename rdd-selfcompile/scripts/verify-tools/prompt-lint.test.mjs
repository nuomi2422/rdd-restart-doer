import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// 2026-11-11: user removed global instructions; missing optional globals must not
// block project startup, while existing invalid globals and required inputs still fail.
const cli = fileURLToPath(new URL('./prompt-lint.js', import.meta.url));
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'prompt-lint-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const [name, text] of Object.entries({
    'machine-AGENTS.md': '# DSH 用户全局指令\n',
    'workspace-AGENTS.md': '# RDD 项目入口\n',
    'pointers.md': '# RDD 按需指针目录\n',
    'goal.md': '# 外层编码 AI Goal 提示词\n',
    'proposals.md': '# 候选\n',
  })) fs.writeFileSync(path.join(dir, name), text);
  return dir;
}
function run(dir) {
  const result = spawnSync(process.execPath, [cli], { encoding: 'utf8', env: { ...process.env, PROMPT_LINT_FIXTURE: dir } });
  assert.ifError(result.error);
  return result;
}
test('deleted user-global instructions are explicitly skipped, not recreated', t => {
  const dir = fixture(t);
  fs.unlinkSync(path.join(dir, 'machine-AGENTS.md'));
  const result = run(dir);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /SKIP.*machine-AGENTS/);
  assert.equal(fs.existsSync(path.join(dir, 'machine-AGENTS.md')), false);
});
test('required project input remains mandatory', t => {
  const dir = fixture(t);
  fs.unlinkSync(path.join(dir, 'workspace-AGENTS.md'));
  const result = run(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /workspace-AGENTS.*cannot read/);
});
test('present invalid globals are still checked', t => {
  const dir = fixture(t);
  fs.writeFileSync(path.join(dir, 'machine-AGENTS.md'), '# wrong marker\n');
  const result = run(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /machine-AGENTS.*missing required marker/);
});
test('read errors other than missing file are not waived', t => {
  const dir = fixture(t);
  const globalPath = path.join(dir, 'machine-AGENTS.md');
  fs.unlinkSync(globalPath);
  fs.mkdirSync(globalPath);
  const result = run(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /machine-AGENTS.*cannot read/);
});
