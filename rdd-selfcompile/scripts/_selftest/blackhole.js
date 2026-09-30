// blackhole.js -- 复现"游戏正在关闭"的假死端点：端口正常 LISTEN、连接也接受，
// 但永不回任何字节。Node http.request 无超时会在这里永久挂死。
// 用法: node blackhole.js <port> [holdMs]
const net = require('net');
const port = parseInt(process.argv[2] || '18765', 10);
const holdMs = parseInt(process.argv[3] || '300000', 10);
const held = [];
const srv = net.createServer((sock) => {
  held.push(sock);
  sock.on('error', () => {});
});
srv.listen(port, '127.0.0.1', () => {
  console.log('BLACKHOLE_LISTEN ' + port);
});
setTimeout(() => {
  for (const s of held) { try { s.destroy(); } catch (e) {} }
  srv.close(() => process.exit(0));
}, holdMs).unref();
