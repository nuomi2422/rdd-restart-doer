// legacy-hang.js -- 修复前 post() 的原样复刻（无 setTimeout、无 AbortController、
// 无 run deadline）。仅用于**证明因果**：旧实现在"端口 LISTEN 但永不响应"
// （= 游戏正在关闭）时会永久挂死，node 永不退出。
//
// 它只应由 test-mcp-timeout.js 以"必须在 N 秒内被 kill"的判据调用。
// 判据成立 = 修复确实消除了一个真实的挂死，而不是我以为的。
const http = require('http');

const HOST = '127.0.0.1';
const PORT = parseInt(process.env.NUMEN_MCP_PORT || '18765', 10);
const TOKEN = 'selftest';

function post(body, sid) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = {
      'Authorization': 'Bearer ' + TOKEN,
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Content-Length': Buffer.byteLength(data),
    };
    if (sid) headers['Mcp-Session-Id'] = sid;
    const req = http.request({ host: HOST, port: PORT, path: '/mcp', method: 'POST', headers }, (r) => {
      const chunks = [];
      r.on('data', (c) => chunks.push(c));
      r.on('end', () => resolve({ status: r.statusCode, sid: r.headers['mcp-session-id'], text: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

(async () => {
  const init = await post({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'legacy', version: '0' } } });
  console.log('UNEXPECTED_RETURN ' + JSON.stringify(init).slice(0, 120));
})();
