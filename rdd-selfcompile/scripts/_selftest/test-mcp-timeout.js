// test-mcp-timeout.js -- 自检：证明"游戏正在退出(端口活着但永不响应)"时，
// MCP 调用脚本会**快速失败退出**，而不是永久挂死拖垮上层 shell。
//
// 背景（2026-09-28 实锤根因）：numen-mcp.js / redline-watch.js 的 post() 用
// http.request 且从未设置超时。Node 的 http.request 默认永不超时；游戏关闭中途
// 8765 仍在 listen 却不再应答 -> 'end' 与 'error' 都不触发 -> Promise 永不
// settle -> node 进程永不退出 -> 调用它的 shell 永远等不到 EOF（"游戏退了之后
// 那个 shell 命令就卡住了"）。
//
// 验收判据（两条都要满足）：
//   1. 退出码非 0（快速失败，不是假装成功）
//   2. 耗时 < 阈值（说明超时真的生效，而不是等系统回收）
// 阈值 = 该脚本的 NUMEN_MCP_RUN_DEADLINE_MS + 宽限。
//
// 用法: node test-mcp-timeout.js
const cp = require('child_process');
const path = require('path');

const SCRIPTS = path.join(__dirname, '..');
const PORT = 18765;
const CALL_TIMEOUT_MS = 3000;   // 故意调小，让自检跑得快
const WIDE = 25;                // 宽限倍数

const cases = [
  { name: 'numen-mcp.js', script: 'numen-mcp.js', args: ['list'], deadline: 30000 },
  { name: 'redline-watch.js', script: 'redline-watch.js', args: ['rdd'], deadline: 25000 },
  { name: 'task-efficiency-watch.js', script: 'task-efficiency-watch.js', args: ['rdd', '--once', '--tag', 'selftest'], deadline: 25000 },
];

function runBlackhole() {
  const p = cp.spawn(process.execPath, [path.join(__dirname, 'blackhole.js'), String(PORT), '120000'], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return new Promise((res) => {
    let buf = '';
    p.stdout.on('data', (d) => {
      buf += d.toString();
      if (buf.includes('BLACKHOLE_LISTEN')) res(p);
    });
    setTimeout(() => res(p), 3000);
  });
}

(async () => {
  const bh = await runBlackhole();
  await new Promise((r) => setTimeout(r, 300));

  let pass = 0, fail = 0;
  for (const c of cases) {
    const env = Object.assign({}, process.env, {
      NUMEN_MCP_PORT: String(PORT),
      NUMEN_MCP_TIMEOUT_MS: String(CALL_TIMEOUT_MS),
      NUMEN_MCP_RUN_DEADLINE_MS: String(c.deadline),
      NUMEN_RUN_TAG: 'selftest',
    });
    const t0 = Date.now();
    let code = null, output = '';
    try {
      const r = cp.spawnSync(process.execPath, [path.join(SCRIPTS, c.script)].concat(c.args), {
        env, encoding: 'utf8', timeout: c.deadline * WIDE, killSignal: 'SIGKILL',
      });
      code = r.status; output = (r.stdout || '') + (r.stderr || '');
    } catch (e) {
      output = 'SPAWN_THROW ' + e.message;
    }
    const ms = Date.now() - t0;
    const nonzero = code !== 0;
    const fast = ms < c.deadline * WIDE;
    // 防假通过：必须确认请求真的打到了黑洞端口，并且是"靠超时脱身"而不是
    // "连接被拒/打错端口"蒙混过关。只看 exit!=0 会漏掉整类无效测试。
    const usedTarget = output.indexOf('127.0.0.1:' + PORT) >= 0;
    const viaTimeout = /MCP_TIMEOUT|MCP_SOCKET_TIMEOUT/.test(output);
    const ok = nonzero && fast && usedTarget && viaTimeout;
    if (ok) { pass++; } else { fail++; }
    console.log(
      (ok ? 'PASS' : 'FAIL') + ' ' + c.name +
      ' exit=' + code + ' elapsed=' + ms + 'ms bound=' + (c.deadline * WIDE) + 'ms' +
      ' nonzero=' + nonzero + ' fast=' + fast + ' usedTarget=' + usedTarget + ' viaTimeout=' + viaTimeout
    );
    const firstLine = (output || '').trim().split(/\r?\n/).filter(Boolean)[0] || '(no output)';
    console.log('     msg: ' + firstLine.slice(0, 160));
  }

  // 因果证明：修复前的实现（legacy-hang.js）在同一条件下必须**无法自行退出**，
  // 只能被外部 kill。如果它居然自己退出了，说明这个根因判断是错的，需要重查。
  const LEGACY_BOUND_MS = 8000;
  const lt0 = Date.now();
  let lStatus = null, lOut = '';
  try {
    const r = cp.spawnSync(process.execPath, [path.join(__dirname, 'legacy-hang.js')], {
      env: Object.assign({}, process.env, { NUMEN_MCP_PORT: String(PORT) }),
      encoding: 'utf8', timeout: LEGACY_BOUND_MS, killSignal: 'SIGKILL',
    });
    lStatus = r.status; lOut = (r.stdout || '') + (r.stderr || '');
  } catch (e) { lOut = 'SPAWN_THROW ' + e.message; }
  const lMs = Date.now() - lt0;
  const legacyHung = (lStatus === null || lStatus === 'SIGKILL' || /ETIMEDOUT/.test(lOut)) && lOut.indexOf('UNEXPECTED_RETURN') < 0;
  if (legacyHung) { pass++; } else { fail++; }
  console.log(
    (legacyHung ? 'PASS' : 'FAIL') + ' legacy-hang.js (causation)' +
    ' exit=' + lStatus + ' elapsed=' + lMs + 'ms bound=' + LEGACY_BOUND_MS + 'ms' +
    ' -> 旧实现确实挂死，修复确实消除了真实挂死'
  );

  try { bh.kill('SIGKILL'); } catch (e) {}
  console.log('SELFTEST_RESULT pass=' + pass + ' fail=' + fail);
  process.exit(fail === 0 ? 0 : 1);
})();