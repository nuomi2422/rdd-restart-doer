// ── CMD.waive 的实现（模板文件，避免在生成脚本里套引号）──
CMD.waive = function (a) {
  const st = requireState(null, { allowClosed: true });
  const sub = a.pos[0];
  const w = loadWaivers(st.id);

  if (sub === 'list' || !sub) {
    const exp = expiredWaivers(st);
    ok(`豁免账本（第 ${st.round} 轮，当前阶段 ${st.stage}）`);
    if (!w.items.length) {
      ok('  （空 —— 没有豁免记录）');
    }
    w.items.forEach((it) => {
      const dead = it.untilRound && it.untilRound < st.round;
      const tag = dead ? '✘ 已过期' : '● 生效中';
      ok(`  ${tag}  ${it.item}   到期轮次=${it.untilRound || '不限'}   责任=${it.owner || '(未指定)'}`);
      ok(`      原因：${it.reason || '(未填)'}   登记于第 ${it.round} 轮 ${it.at || ''}`);
    });
    if (exp.length) ok(`  ⚠ ${exp.length} 条已过期未清 —— 下一轮该优先清账`);
    if (w.items.length) ok('  撤销某条： stager waive drop <item> --reason "已修"');
    return st;
  }

  if (sub === 'drop') {
    const item = a.pos[1];
    if (!item) die('给门禁项名，如 stager waive drop doc:experience');
    const before = w.items.length;
    w.items = w.items.filter((x) => x.item !== item);
    if (w.items.length === before) die(`账上没有 ${item} 这条豁免`);
    saveWaivers(st.id, w);
    ok(`✔ 已撤销 ${item}` + (a.f.reason ? `（原因：${a.f.reason}）` : ''));
    return st;
  }

  const reason = a.f.reason || a.f.why;
  if (!reason) die('豁免必须写原因：--reason "为什么这次可以带病过"');
  const until = a.f['until-round'] || a.f.until || 0;
  const rec = {
    item: sub,
    reason: String(reason),
    owner: a.f.owner || st.actor || '(未指定)',
    untilRound: parseInt(until, 10) || 0,
    round: st.round,
    at: new Date().toISOString(),
  };
  w.items = w.items.filter((x) => x.item !== sub);   // 同名只留最新
  w.items.push(rec);
  saveWaivers(st.id, w);
  ok(`✔ 已登记豁免 ${sub}`);
  ok(`   原因 = ${rec.reason}`);
  ok(`   责任 = ${rec.owner}    到期轮次 = ${rec.untilRound || '不限'}`);
  if (!rec.untilRound) ok('   ⚠ 没填到期轮次 = 永久豁免。建议加 --until-round N，到期会被提醒清账。');
  ok(`   查看 stager waive list   撤销 stager waive drop ${sub}`);
  return st;
};