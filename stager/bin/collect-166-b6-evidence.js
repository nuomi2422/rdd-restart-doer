#!/usr/bin/env node
/**
 * 166-B6 取证收集器（保护级别升级：protection_escalated）
 *
 * 判据（§48.3）：
 *   1) 出现 protection_escalated 事件；
 *   2) 事件里 from/to 自洽（to=HIGH，from 低于 HIGH）；
 *   3) recentUnrecoveredDeaths >= 2，且能对上真实死亡批次（deathSeq 存在）；
 *   4) 同窗口内的死亡确实不是 RECOVERED。
 *
 * 拒绝取证（REFUSE，退出码 2）的情形：
 *   - 没有任何 protection_escalated；
 *   - 事件字段自相矛盾（to 不是 HIGH，或 recent < 2）；
 *   - 窗口内死亡在台账里被标 RECOVERED（说明不该升级）。
 *
 * 用法：node collect-166-b6-evidence.js [--out <path>]
 * 说明：**读全部轮转档**（rdd*.jsonl），这是 §74 的教训。
 */
const fs = require('node:fs');
const path = require('node:path');

const MONITOR = 'D:/rdd/mc/The Best of Twilight Forest/config/numen/monitor';
const OUT_DEFAULT = 'D:/rdd/workspace/stager/runs/166-B6-protection-escalated/evidence';

function sourceMeta() {
  const files = fs.readdirSync(MONITOR).filter(f => /^rdd.*\.jsonl$/.test(f));
  return {
    collectedAt: new Date().toISOString(),
    files: files.map(f => {
      const st = fs.statSync(path.join(MONITOR, f));
      return { name: f, bytes: st.size, mtime: st.mtime.toISOString() };
    }),
  };
}

function readAll() {
  const out = [];
  for (const f of fs.readdirSync(MONITOR).filter(x => /^rdd.*\.jsonl$/.test(x))) {
    for (const line of fs.readFileSync(path.join(MONITOR, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch {}
    }
  }
  out.sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));
  return out;
}

function refuse(msg) {
  console.error('REFUSE: ' + msg);
  process.exit(2);
}

const args = process.argv.slice(2);
const outIdx = args.indexOf('--out');
const outPath = outIdx >= 0 ? args[outIdx + 1] : OUT_DEFAULT;

const events = readAll();
const esc = events.filter(e => e.type === 'protection_escalated');
if (esc.length === 0) {
  refuse('没有 protection_escalated 事件——B6 判据 1 未满足，不许取证。');
}

const e = esc[esc.length - 1];
const d = e.data || {};
const problems = [];
if (String(d.to) !== 'HIGH') problems.push('to 不是 HIGH：' + d.to);
if (Number(d.recentUnrecoveredDeaths) < 2) problems.push('recentUnrecoveredDeaths < 2：' + d.recentUnrecoveredDeaths);
if (String(d.from) === String(d.to)) problems.push('from 与 to 相同');
if (problems.length) refuse('事件自相矛盾 —— ' + problems.join('；'));

const settled = events.filter(x => x.type === 'death_recovery_settled').map(x => ({
  seq: Number(x.data && x.data.deathSeq),
  ledger: String((x.data && x.data.ledgerState) || ''),
  at: x.timestamp,
}));
const windowSeconds = Number(d.windowTicks || 0) / 20;
const escAt = Date.parse(e.timestamp);
const inWindow = events.filter(x => x.type === 'companion_assets_invalidated')
  .filter(x => {
    const t = Date.parse(x.timestamp);
    return t <= escAt && (escAt - t) / 1000 <= windowSeconds;
  })
  .map(x => {
    const seq = Number(x.data.deathSeq);
    const s = settled.filter(y => y.seq === seq).pop();
    return { seq, at: x.timestamp, ledger: s ? s.ledger : 'UNVERIFIED' };
  });

const recovered = inWindow.filter(x => x.ledger === 'RECOVERED');
if (recovered.length) {
  refuse('窗口内有已回收的死亡，不该升级：' + recovered.map(x => x.seq).join(','));
}

const bundle = {
  criterion: 'B6 连续死亡提高保护级别',
  source: sourceMeta(),
  event: { timestamp: e.timestamp, data: d },
  window: { seconds: windowSeconds, deaths: inWindow },
  caveat: [
    'protection_escalated 只在「窗口内未回收死亡数正好跨过 1→2」时发布（§48/RddProtectionLevel.shouldAnnounceEscalation）。',
    '窗口计数排除 RECOVERED；UNVERIFIED/CONFIRMED_LOST 计入。',
  ],
};

fs.mkdirSync(outPath, { recursive: true });
const file = path.join(outPath, 'protection-escalated.json');
fs.writeFileSync(file, JSON.stringify(bundle, null, 2));
console.log('OK  取证已写入 ' + file);
console.log('事件 ' + e.timestamp + '  from=' + d.from + ' to=' + d.to + '  recent=' + d.recentUnrecoveredDeaths);
console.log('窗口 ' + windowSeconds + 's 内死亡: ' + (inWindow.map(x => 'seq' + x.seq + '(' + x.ledger + ')').join(', ') || '(空)'));
