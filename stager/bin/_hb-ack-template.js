// ── 心跳 ack（stage-heartbeat.js 的应答端）────────────────────
//   为什么是命令而不是「请 AI 回一句话」：
//   prompt 无法验证，命令可以。ack 落盘 → hb/ctx/check 都能看见「本阶段答过没有」。
//   这跟 mark 是同一个思路：能被查的才叫门禁。
CMD.hb = function (a) {
  const st = requireState(null, { allowClosed: true });
  const hbPath = path.join(TASKS, 'heartbeat.json');
  let hb;
  try { hb = JSON.parse(fs.readFileSync(hbPath, 'utf8')); } catch (e) { hb = { acks: {} }; }
  if (!hb.acks) hb.acks = {};

  const round = parseInt(a.f.round, 10) || st.round;
  const key = st.id + ':' + round + ':' + st.stage;

  if (a.pos[0] === 'list' || !a.pos[0]) {
    ok('心跳应答记录');
    if (!Object.keys(hb.acks).length) { ok('  （空 —— 本任务还没答过心跳）'); return st; }
    Object.keys(hb.acks).sort().forEach((k) => {
      const v = hb.acks[k];
      const cur = (k === st.id + ':' + st.round + ':' + st.stage);
      ok(`  ${cur ? '● 本阶段' : '○ 历史  '} ${k}`);
      ok(`      耗时=${v.elapsed}  状态=${v.status}  下一步=${v.next}`);
      ok(`      at=${v.at}  by=${v.actor || '?'}`);
    });
    return st;
  }

  const status = a.f.status || 'unknown';
  const next = a.f.next || '';
  const elapsed = a.f.elapsed || '?';
  if (!next) die('必须给下一步：--next "<一句话>"（心跳的价值就在于逼它想清楚下一步）');

  hb.acks[key] = {
    elapsed: String(elapsed), status: String(status), next: String(next),
    at: new Date().toISOString(), actor: st.actor || '(未指定)', round,
  };
  fs.mkdirSync(path.dirname(hbPath), { recursive: true });
  fs.writeFileSync(hbPath, JSON.stringify(hb, null, 1), 'utf8');

  // 也追一条 history，便于按时间线看
  log(st, 'hb-ack', { status: String(status), elapsed: String(elapsed), next: String(next) });

  ok(`✔ 已记心跳应答（第 ${round} 轮 ${st.stage}）`);
  ok(`   耗时=${elapsed}  状态=${status}`);
  ok(`   下一步= ${next}`);
  const warn = {
    looping: '★ 你自评 looping（在打转）→ 下一档会强制自检，别等',
    blocked: '★ 你自评 blocked（技术卡住）→ 该写状态报告了，别硬扛',
    waiting_user: '★ 你自评 waiting_user → 写完状态报告就停，等用户拍板',
    unknown: '★ status 用了 unknown。四个合法值：ok / looping / blocked / waiting_user',
  }[String(status)];
  if (warn) ok('   ' + warn);
  return st;
};