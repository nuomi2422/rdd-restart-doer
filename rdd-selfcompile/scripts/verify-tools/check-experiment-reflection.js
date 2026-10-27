#!/usr/bin/env node
/**
 * check-experiment-reflection.js —— 实验台「反思与提醒」体检（Q18 的执行体）
 *
 * 为什么要有它（2026-10-27 主人指示）:
 *   「给 harness 门禁退游戏的时候，加一个门禁提示，就是可以给实验台写新的工具，
 *    并且写实验台实验数据的反思和提醒」
 *
 * 主人的意思有两条，本脚本只做**只读体检**，不替人写：
 *   ① **实验台可以长新工具**：跑完一轮实验，如果外面缺一个观测/切片/对照的手段，
 *      该补的是「实验台工具」而不是手工重复劳动。判据 = 已有的 exp-* / bench / mf-observer
 *      清单 + 本轮有没有新增；
 *   ② **实验数据的反思要落地**：每轮实验的数据（journal / learn-summary / verdict.json）
 *      必须配一份「人话反思」——这轮看到了什么、哪里反直觉、下一步改什么。
 *      判据 = 本轮修改过的实验产物里，有没有对应日期的反思文档（rdd存放 或 experiments/notes）。
 *
 * 设计纪律（与 check-evidence-anchor / check-debt-rollup 同族）:
 *   - **只读**：不写任何文件；输出 JSON 给门禁聚合。
 *   - **不冒充判断**：缺反思 = warn，不 BLOCK（实验可能还在跑；制造假红比漏报更糟）。
 *   - **诚实边界**：找不到数据目录 = unknown，不折成「没做」。
 *
 * 用法:
 *   node check-experiment-reflection.js            # 人读
 *   node check-experiment-reflection.js --json     # 机读（门禁用）
 *   node check-experiment-reflection.js --since 2026-10-27
 * 退出码: 0=有反思或无新数据; 1=有新实验数据但没有反思(warn); 2=环境/输入错误
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', '..', '..');   // D:\rdd
const HARNESS = path.join(ROOT, 'harness', 'rdd-harness');
const EXPERIMENTS = path.join(HARNESS, 'experiments');
const DOCS_REPORT = path.join(ROOT, 'docs', 'rdd-docs', 'rdd存放');
const DOCS_UNIFIED = path.join(ROOT, 'docs', 'rdd-docs', 'rdd架构', '自编译统一版');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i > -1 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}

function mtime(p) {
  try { return fs.statSync(p).mtimeMs; } catch { return 0; }
}

function listDir(p) {
  try { return fs.readdirSync(p); } catch { return null; }
}

function walk(dir, depth, out) {
  out = out || [];
  if (depth < 0) return out;
  const names = listDir(dir);
  if (!names) return out;
  for (const n of names) {
    const full = path.join(dir, n);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    if (st.isDirectory()) walk(full, depth - 1, out);
    else out.push(full);
  }
  return out;
}

/** 实验台工具清单：bin 下的 exp-* / bench / mf-observer / exp-runner 这一族。 */
function benchTools() {
  const bin = path.join(HARNESS, 'bin');
  const names = listDir(bin) || [];
  return names
    .filter((n) => /\.js$/.test(n))
    .filter((n) => /^(exp-|bench|mf-observer|snapshot-world|selfcompile-drain)/.test(n))
    .sort();
}

/** 本轮（since 之后）动过的实验产物。 */
function freshArtifacts(sinceMs) {
  const files = walk(EXPERIMENTS, 3, []).filter((f) => mtime(f) >= sinceMs);
  return files.map((f) => path.relative(HARNESS, f)).sort();
}

/** 反思文档候选：rdd存放 下一句话/复盘，或 experiments/notes。 */
function reflections(sinceMs) {
  const out = [];
  for (const dir of [DOCS_REPORT, path.join(EXPERIMENTS, 'notes'), DOCS_UNIFIED]) {
    const names = listDir(dir);
    if (!names) continue;
    for (const n of names) {
      if (!/\.md$/.test(n)) continue;
      if (!/(反思|复盘|实验|verdict|reflect|retro|一句话|一页纸)/i.test(n)) continue;
      const full = path.join(dir, n);
      if (mtime(full) >= sinceMs) out.push(path.relative(ROOT, full));
    }
  }
  return out.sort();
}

function main() {
  const sinceStr = arg('since', new Date().toISOString().slice(0, 10));
  const sinceMs = Date.parse(sinceStr + 'T00:00:00Z');
  if (Number.isNaN(sinceMs)) {
    console.error(JSON.stringify({ ok: false, code: 'BAD_INPUT', error: 'bad --since' }));
    process.exit(2);
  }

  const hasExperiments = listDir(EXPERIMENTS) !== null;
  const tools = benchTools();
  const fresh = hasExperiments ? freshArtifacts(sinceMs) : [];
  const notes = reflections(sinceMs);

  const verdict = {
    ok: true,
    since: sinceStr,
    benchTools: tools.length,
    freshArtifacts: fresh.slice(0, 12),
    freshArtifactCount: fresh.length,
    reflections: notes.slice(0, 8),
    reflectionCount: notes.length,
    // 三条人话提醒（不冒充判断，只摆在面前）
    reminders: [
      '① 这轮实验缺的观测手段，该补成**实验台工具**（harness/bin/exp-*、bench）而不是手工重复；' +
      '新工具要能一条命令复现，带 --help 与自测',
      '② 每轮数据必须配一份**人话反思**：看到了什么 / 哪里反直觉 / 下一步改哪个变量；' +
      '数字进 journal，判断进反思，两者别混',
      '③ 反思里写清「这轮**证伪**了什么」——只写"有效/无效"不算，要说清哪个假设被数据推翻了',
    ],
  };

  if (!hasExperiments) {
    verdict.severity = 'unknown';
    verdict.why = `实验目录不存在（${EXPERIMENTS}）—— 没跑过实验，不折成"没写反思"`;
  } else if (fresh.length > 0 && notes.length === 0) {
    verdict.ok = false;
    verdict.severity = 'warn';
    verdict.why = `本轮有 ${fresh.length} 个实验产物更新，但没找到同时段的反思文档 —— 数据有了、反思没落`;
  } else if (fresh.length === 0) {
    verdict.severity = 'skip';
    verdict.why = '本轮没有实验产物更新（没跑实验，跳过）';
  } else {
    verdict.severity = 'pass';
    verdict.why = `本轮产物 ${fresh.length} 个、反思 ${notes.length} 篇`;
  }

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(verdict, null, 2));
  } else {
    console.log(`实验台反思体检 @ ${sinceStr}`);
    console.log(`  实验台工具：${verdict.benchTools} 个（${tools.slice(0, 6).join(', ')}…）`);
    console.log(`  本轮实验产物：${verdict.freshArtifactCount} 个`);
    if (fresh.length) fresh.slice(0, 5).forEach((f) => console.log(`    - ${f}`));
    console.log(`  本轮反思：${verdict.reflectionCount} 篇`);
    if (notes.length) notes.slice(0, 5).forEach((f) => console.log(`    - ${f}`));
    console.log(`  结论：${verdict.severity} —— ${verdict.why}`);
    console.log('  提醒：');
    verdict.reminders.forEach((r) => console.log('    ' + r));
  }
  process.exit(verdict.ok ? 0 : 1);
}

main();
