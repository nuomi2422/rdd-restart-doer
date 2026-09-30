// ── 读档记录（read recap · GLM「读后一行复述」）────────────────
//   为什么：薄索引把失败模式从「读了但被稀释」换成了「根本没读 / 读了没吸收」，
//   而后者【不可观测】。读完写一行「已读 X，要点：…」，把读没读从黑箱变白箱。
//   AI 可能编复述，但编复述比不读成本高，且复述错会污染下游引用从而被暴露。
CMD.read = function (a) {
  const st = requireState(null, { allowClosed: true });
  const file = a.pos[0];
  if (!file) die('给文件： stager read <文件路径> --note "要点一句话"');
  const note = a.f.note || a.f.要点 || '';
  const p = path.join(taskDir(st.id), 'reads.jsonl');
  const rec = {
    file: String(file),
    note: String(note || '(没写要点)'),
    round: st.round,
    stage: st.stage,
    actor: st.actor || '(未指定)',
    at: new Date().toISOString(),
  };
  let lines = [];
  try { lines = fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean); } catch (e) {}
  // 同一文件本轮重复读 → 覆盖（保留最后一次），不刷屏
  const kept = lines.filter((l) => {
    try { const j = JSON.parse(l); return !(j.file === rec.file && j.round === rec.round && j.stage === rec.stage); }
    catch (e) { return true; }
  });
  kept.push(JSON.stringify(rec));
  fs.writeFileSync(p, kept.join('\n') + '\n', 'utf8');
  ok(`✔ 已记读档：${rec.file}`);
  ok(`   要点 = ${rec.note}`);
  ok(`   本阶段已记 ${readRecaps(st).length} 份（查全部： stager read list）`);
  if (!note) ok('   ⚠ 没写要点 —— 复述的价值在「要点」那一句，空记等于没记。');
  return st;
};

// 本轮本阶段已记的读档
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