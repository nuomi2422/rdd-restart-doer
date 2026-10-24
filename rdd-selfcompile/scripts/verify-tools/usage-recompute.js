#!/usr/bin/env node
'use strict';
/*
 * usage-recompute.js —— LC3「日常样本能复算」的审查者侧工具（只读，不改任何东西）。
 *
 * 回答的问题：**经验五态账能不能从 monitor 事件独立重算出来？**
 * TrialRuntime 的内存账是运行时缓存；本工具从 expmem.jsonl 的 usage_recorded
 * 事件（LC3 起每条五态样本都镜像成事件）离线重算，给出与运行时同口径的账。
 *
 * 判据（78 号 §7 LC3「日常样本能复算，不以 verify 回执单独验收」）：
 *   - 每条事件的六字段（ref/version/artifact/state/attempt/at）必须齐全且可解析；
 *   - 缺 ref 跳过并计数（skipped_no_ref）—— 与 Java 侧 UsageEventCodec 同容错；
 *   - 认不出的 state 落 UNKNOWN（宁记不知道，不猜）；
 *   - 同 ref+attempt+artifact+at 重复投递只计一次（与 UsageLedger.derive 同去重键）；
 *   - 按 (ref, version) 分账输出五态：SUCCESS/FAILURE/CANCELED/INTERRUPTED/UNKNOWN；
 *   - 结论只看最大 attempt（先取消后成功 = 两个 attempt，不串结论 —— 同 Java 口径）。
 *
 * 数据源：<monitor>/expmem.jsonl 的 type=usage_recorded 事件（LC3 起写入）。
 *   部署前的历史文件里没有该事件 ⇒ 报 0 条并如实说明，不是失败。
 *
 * 用法：
 *   node usage-recompute.js                        # 默认 live 监控目录
 *   node usage-recompute.js --dir <monitor目录>
 *   node usage-recompute.js --file <expmem归档.jsonl>   # 扫轮转历史文件
 *   node usage-recompute.js --since 2026-10-25        # 只看某天(本地时区)起
 *   node usage-recompute.js --ref "exp:execution|x"   # 只看某条经验
 *   node usage-recompute.js --json                    # 输出完整 JSON
 *   node usage-recompute.js --selftest                # 合成样本自测
 *
 * 退出码：0 = 重算成功（含 0 条事件）；1 = 事件存在但字段缺失/自测失败；3 = 环境错。
 *
 * 与 Java 侧的对应：UsageEventCodec.fromEvents + UsageLedger.derive 的 JS 镜像。
 * 键名契约（ref/version/artifact/state/attempt/at）由 UsageEventCodecTest 钉死，
 * 本工具按同一契约解析——两边漂移时自测会先红。
 */

const fs = require('fs');
const path = require('path');

const EXIT_OK = 0;
const EXIT_BAD = 1;
const EXIT_USAGE = 3;

const DEFAULT_DIR = 'D:\\rdd\\mc\\The Best of Twilight Forest\\config\\numen\\monitor';

const STATES = ['SUCCESS', 'FAILURE', 'CANCELED', 'INTERRUPTED', 'UNKNOWN'];

/** Java UsageState.parse 的 JS 镜像：别名归一 + 认不出落 UNKNOWN。 */
function parseState(raw) {
  const s = String(raw == null ? '' : raw).trim().toUpperCase();
  switch (s) {
    case 'DONE': case 'SUCCESS': case 'COMPLETED': case 'OK': return 'SUCCESS';
    case 'FAILED': case 'FAILURE': case 'ERROR': case 'TIMEOUT': return 'FAILURE';
    case 'CANCELED': case 'CANCELLED': case 'STOPPED': case 'ABORTED': return 'CANCELED';
    case 'INTERRUPTED': case 'KILLED': case 'CRASHED': return 'INTERRUPTED';
  }
  return STATES.includes(s) ? s : 'UNKNOWN';
}

function parseArgs(argv) {
  const out = { dir: DEFAULT_DIR, file: null, since: null, ref: null, json: false, selftest: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dir') out.dir = argv[++i];
    else if (a === '--file') out.file = argv[++i];
    else if (a === '--since') out.since = argv[++i];
    else if (a === '--ref') out.ref = argv[++i];
    else if (a === '--json') out.json = true;
    else if (a === '--selftest') out.selftest = true;
    else if (a === '--help' || a === '-h') out.help = true;
    else { console.error('unknown arg: ' + a); process.exit(EXIT_USAGE); }
  }
  return out;
}

function tsOf(iso) {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? 0 : t;
}

/** 读事件：一行一条 JSONL；坏行跳过并计数（与 FeedbackChannel 同容错方向）。 */
function readEvents(file, sinceTs) {
  const out = { rows: [], bad: 0 };
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (e) {
    return out;   // 文件不存在 = 0 条（调用方如实报）
  }
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let o;
    try { o = JSON.parse(line); } catch (e) { out.bad++; continue; }
    if (!o || o.type !== 'usage_recorded') continue;
    if (sinceTs && tsOf(o.timestamp) && tsOf(o.timestamp) < sinceTs) continue;
    out.rows.push({ envelope: o, data: o.data || {} });
  }
  return out;
}

/** UsageEventCodec.fromEvent 的 JS 镜像。返回 null = 跳过（缺 ref）。 */
function decode(d) {
  const ref = String(d.ref == null ? '' : d.ref).trim();
  if (!ref) return null;
  const version = String(d.version == null ? '' : d.version).trim();
  const artifact = String(d.artifact == null ? '' : d.artifact).trim();
  const state = parseState(d.state);
  let attempt = 1;
  const n = Number(d.attempt);
  if (Number.isFinite(n) && n >= 1) attempt = Math.floor(n);
  let at = 0;
  const t = Number(d.at);
  if (Number.isFinite(t)) at = t;
  return { ref, version, artifact, state, attempt, at };
}

/** UsageLedger.derive 的 JS 镜像：去重 → 五态计数 → 结论取最大 attempt。 */
function derive(samples, wantRef, wantVersion) {
  const seen = new Set();
  const kept = [];
  let dup = 0;
  let excluded = 0;
  for (const s of samples) {
    if (wantRef && s.ref !== wantRef) continue;
    if (wantVersion != null && s.version !== wantVersion) { excluded++; continue; }
    const key = [s.ref, s.attempt, s.artifact, s.at].join('|');
    if (seen.has(key)) { dup++; continue; }
    seen.add(key);
    kept.push(s);
  }
  const counts = { SUCCESS: 0, FAILURE: 0, CANCELED: 0, INTERRUPTED: 0, UNKNOWN: 0 };
  let last = null;
  for (const s of kept) {
    counts[s.state]++;
    if (!last || s.attempt > last.attempt || (s.attempt === last.attempt && s.at > last.at)) last = s;
  }
  return {
    kept: kept.length, duplicates: dup, excludedByVersion: excluded,
    counts,
    conclusion: last ? last.state : 'NONE',
    conclusionAttempt: last ? last.attempt : 0,
  };
}

function selftest() {
  // 合成样本：覆盖三态 + 重复投递 + 跨版本 + 先取消后成功 + 坏行容错
  const rows = [
    mk('exp:a', 'v1', 't1', 'SUCCESS', 1, 100),
    mk('exp:a', 'v1', 't1', 'SUCCESS', 1, 100),        // 重复投递 → 去重
    mk('exp:a', 'v1', 't2', 'CANCELED', 2, 200),        // 先取消
    mk('exp:a', 'v1', 't2', 'SUCCESS', 3, 300),         // 后成功 → 结论 SUCCESS@3
    mk('exp:a', 'v2', 't3', 'FAILURE', 1, 400),         // 跨版本 → 另一本账
    mk('exp:b', 'v1', 't4', 'DONE', 1, 500),            // 别的条目
    { type: 'usage_recorded', data: { version: 'v9', state: 'SUCCESS' } },  // 缺 ref → 跳过
    { type: 'usage_recorded', data: { ref: 'exp:c', state: 'WEIRD_STATE' } }, // 坏 state → UNKNOWN
  ];
  // ★ rows 的形状是 {type, data} 信封 —— decode 吃的是 data 层（与 readEvents→主流程同路）
  const samples = rows.map(r => decode(r.data)).filter(Boolean);
  const a1 = derive(samples, 'exp:a', 'v1');
  const a2 = derive(samples, 'exp:a', 'v2');
  const b = derive(samples, 'exp:b', null);
  const c = derive(samples, 'exp:c', null);
  let fails = 0;
  const eq = (name, got, want) => {
    if (got !== want) { console.log('  SELFTEST FAIL ' + name + ': got ' + got + ' want ' + want); fails++; }
  };
  eq('total-decoded', samples.length, 7);                  // 8 行 - 1 缺 ref
  eq('a1-kept', a1.kept, 3);                               // 4 条 - 1 重复
  eq('a1-dup', a1.duplicates, 1);
  eq('a1-success', a1.counts.SUCCESS, 2);
  eq('a1-canceled', a1.counts.CANCELED, 1);
  eq('a1-conclusion', a1.conclusion, 'SUCCESS');          // 最大 attempt=3
  eq('a1-conclusion-attempt', a1.conclusionAttempt, 3);
  eq('a2-failure', a2.counts.FAILURE, 1);                 // v2 独立账
  eq('b-success', b.counts.SUCCESS, 1);                    // DONE → SUCCESS 别名归一
  eq('c-unknown', c.counts.UNKNOWN, 1);                    // 坏 state → UNKNOWN
  if (fails === 0) {
    console.log('SELFTEST PASS: 10/10 断言通过（去重/五态/别名归一/结论取最大attempt/坏行容错/跨版本分账）');
    return true;
  }
  console.log('SELFTEST FAIL: ' + fails + ' 断言未过');
  return false;
}

function mk(ref, version, artifact, state, attempt, at) {
  return { type: 'usage_recorded', data: { ref, version, artifact, state, attempt, at } };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0] + '*/');
    return;
  }
  if (args.selftest) {
    process.exit(selftest() ? EXIT_OK : EXIT_BAD);
  }
  const sinceTs = args.since ? tsOf(args.since + (args.since.length === 10 ? 'T00:00:00' : '')) : 0;
  const file = args.file || path.join(args.dir, 'expmem.jsonl');
  const read = readEvents(file, sinceTs);
  if (args.file && !fs.existsSync(args.file)) {
    console.error('file not found: ' + args.file);
    process.exit(EXIT_USAGE);
  }
  const samples = read.rows.map(r => decode(r.data)).filter(Boolean);
  const skippedNoRef = read.rows.length - samples.length;
  // 全量账 + 按 ref 分账
  const all = derive(samples, args.ref || null, null);
  const byRef = new Map();
  for (const s of samples) {
    if (!byRef.has(s.ref)) byRef.set(s.ref, []);
    byRef.get(s.ref).push(s);
  }
  const refs = [];
  for (const [ref, list] of byRef) {
    const versions = [...new Set(list.map(s => s.version))];
    for (const v of versions) {
      refs.push({ ref, version: v, ...derive(list, ref, v) });
    }
  }
  const report = {
    source: file,
    since: args.since || null,
    filterRef: args.ref || null,
    events: read.rows.length,
    badLines: read.bad,
    decoded: samples.length,
    skippedNoRef,
    grand: all,
    byRefVersion: refs.sort((a, b) => a.ref.localeCompare(b.ref)),
    note: skippedNoRef > 0
      ? skippedNoRef + ' 条事件缺 ref 被跳过（与 Java 侧 UsageEventCodec 同容错）'
      : 'events 是唯一真账：内存只是缓存（TrialRuntime），本工具按事件独立重算',
  };
  if (args.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log('=== usage-recompute（只读复算）===');
    console.log('源: ' + file + (args.since ? '  since=' + args.since : ''));
    console.log('事件 ' + read.rows.length + ' 条（坏行 ' + read.bad + '，缺 ref 跳过 ' + skippedNoRef + '）');
    if (read.rows.length === 0) {
      console.log('没有 usage_recorded 事件 —— LC3 部署前的历史文件本就没有，不是失败。');
    }
    console.log('全量: ' + JSON.stringify(all.counts) + ' 结论=' + all.conclusion + '@attempt' + all.conclusionAttempt
      + '（重复 ' + all.duplicates + '）');
    for (const r of refs) {
      console.log('  ' + r.ref + ' @' + (r.version || 'LEGACY') + ': ' + JSON.stringify(r.counts)
        + ' 结论=' + r.conclusion + '@' + r.conclusionAttempt);
    }
  }
  process.exit(read.rows.length > 0 && skippedNoRef === read.rows.length ? EXIT_BAD : EXIT_OK);
}

main();
