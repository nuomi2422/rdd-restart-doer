// ── 读档记录（read recap · GLM「读后一行复述」）────────────────
//   为什么：薄索引把失败模式从「读了但被稀释」换成了「根本没读 / 读了没吸收」，
//   而后者【不可观测】。读完写一行「已读 X，要点：…」，把读没读从黑箱变白箱。
//   AI 可能编复述，但编复述比不读成本高，且复述错会污染下游引用从而被暴露。
function readRecaps(st) {
  let lines = [];
  try { lines = fs.readFileSync(path.join(taskDir(st.id), 'reads.jsonl'), 'utf8').split(/\r?\n/).filter(Boolean); }
  catch (e) { return []; }
  const out = [];
  for (const l of lines) {
    try {
      const j = JSON.parse(l);
      if (j.round === st.round && j.stage === st.stage) out.push(j);
    } catch (e) {}
  }
  return out;
}

// read[] 里的路径归一成 basename（去掉括号注释），用来和读档记录比对
function readBaseName(r) {
  return path.basename(String(r).replace(/（[^）]*）/g, '').trim());
}

CMD.read = function (a) {
  const st = requireState(null, { allowClosed: true });
  const file = a.pos[0];

  if (file === 'list' || !file) {
    const rs = readRecaps(st);
    ok('读档记录（第 ' + st.round + ' 轮 · ' + st.stage + '）');
    if (!rs.length) { ok('  （空 —— 本阶段还没记过读完的要点）'); return st; }
    rs.forEach((r) => {
      ok('  ✔ ' + r.file);
      ok('      要点: ' + r.note + '　（' + r.actor + ' ' + String(r.at || '').slice(11, 19) + '）');
    });
    return st;
  }

  const note = a.f.note || '';
  if (!note) die('读完必须写要点： --note "这份讲了什么、我该注意什么"');

  const p = path.join(taskDir(st.id), 'reads.jsonl');
  let lines = [];
  try { lines = fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean); } catch (e) {}
  // 同一文件本轮重复读 → 覆盖（保留最后一次），不刷屏
  const kept = lines.filter((l) => {
    try { const j = JSON.parse(l); return !(j.file === file && j.round === st.round && j.stage === st.stage); }
    catch (e) { return true; }
  });
  kept.push(JSON.stringify({
    file: String(file), note: String(note), round: st.round, stage: st.stage,
    actor: st.actor || '(未指定)', at: new Date().toISOString(),
  }));
  fs.writeFileSync(p, kept.join('\n') + '\n', 'utf8');

  ok('✔ 已记读档：' + file);
  ok('   要点 = ' + note);
  ok('   本阶段已记 ' + readRecaps(st).length + ' 份（看全部： stager read list）');
  return st;
};