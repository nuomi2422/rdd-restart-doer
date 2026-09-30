// test-free-models.js -- 对比 OpenRouter 免费模型的**工具调用**可靠性（游戏内 AI 的命门）。
// 判据不只看 HTTP 200：要看 finish_reason 是否为 tool_calls、函数名对不对、参数是否合法，
// 再加一个"参数保真"用例（要它填对具体数字与字符串），因为工具调用常见病是参数乱填。
const https = require('https');
const fs = require('fs');

function key() {
  try {
    const j = JSON.parse(fs.readFileSync('C:\\Users\\lenovo\\.config\\opencode\\opencode.json', 'utf8'));
    return (j.provider && j.provider.openrouter && j.provider.openrouter.options && j.provider.openrouter.options.apiKey) || '';
  } catch (e) { return ''; }
}
const KEY = process.env.OPENROUTER_API_KEY || key();

const CANDIDATES = [
  'stealth/space-bunny-alpha',
  'nvidia/nemotron-3.5-lightning:free',
  'nvidia/nemotron-3-super-120b-a12b:free',
  'qwen/qwen3.8-27b:free',
  'google/gemma-4-31b-it:free',
  'thinkingmachines/inkling:free',
  'openrouter/free',
];

const TOOLS = [
  { type: 'function', function: { name: 'get_self_status', description: 'Read body condition: hp, hunger, position, dimension.', parameters: { type: 'object', properties: {}, required: [] } } },
  { type: 'function', function: { name: 'mine', description: 'Mine blocks of the given type nearby.', parameters: { type: 'object', properties: { block: { type: 'string', description: 'namespaced block id' }, count: { type: 'integer' } }, required: ['block', 'count'] } } },
  { type: 'function', function: { name: 'goto', description: 'Travel to a destination.', parameters: { type: 'object', properties: { x: { type: 'number' }, y: { type: 'number' }, z: { type: 'number' } }, required: ['x', 'y', 'z'] } } },
];

// 用例 A：该调 get_self_status（无参数工具）
const CASE_A = [
  { role: 'system', content: 'You are a Minecraft companion. Act by calling tools. Never answer in prose when a tool can answer.' },
  { role: 'user', content: '你现在在哪、血量多少？用工具查。' },
];
// 用例 B：参数保真 —— 必须精确填 block=minecraft:iron_ore, count=64
const CASE_B = [
  { role: 'system', content: 'You are a Minecraft companion. Act by calling tools. Never answer in prose when a tool can answer.' },
  { role: 'user', content: '去挖 64 个铁矿（minecraft:iron_ore）。' },
];

function post(model, messages) {
  return new Promise((resolve) => {
    const body = JSON.stringify({ model, messages, tools: TOOLS, tool_choice: 'auto', temperature: 0 });
    const t0 = Date.now();
    const rq = https.request({
      host: 'openrouter.ai', path: '/api/v1/chat/completions', method: 'POST',
      headers: { Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    }, (r) => {
      const c = []; r.on('data', b => c.push(b));
      r.on('end', () => {
        const ms = Date.now() - t0;
        const t = Buffer.concat(c).toString('utf8');
        let j = null; try { j = JSON.parse(t); } catch (e) {}
        resolve({ ms, status: r.statusCode, j, raw: t });
      });
    });
    rq.on('error', (e) => resolve({ ms: Date.now() - t0, err: e.message }));
    rq.setTimeout(120000, () => rq.destroy(new Error('timeout 120s')));
    rq.write(body); rq.end();
  });
}

function verdict(res, wantTool, wantArgs) {
  if (res.err) return 'ERR ' + res.err;
  if (!res.j) return 'BADJSON ' + (res.raw || '').slice(0, 90);
  if (res.j.error) return 'API_ERR ' + JSON.stringify(res.j.error).slice(0, 110);
  const ch = (res.j.choices || [])[0];
  if (!ch) return 'NO_CHOICE';
  const m = ch.message || {};
  const tc = (m.tool_calls || [])[0];
  const parts = [];
  parts.push('finish=' + ch.finish_reason);
  if (!tc) {
    parts.push('NO_TOOLCALL');
    parts.push('content=' + String(m.content || '').replace(/\s+/g, ' ').slice(0, 60));
    return parts.join(' ');
  }
  const fn = tc.function || {};
  parts.push('tool=' + fn.name);
  if (wantTool && fn.name !== wantTool) parts.push('WRONG_TOOL(want ' + wantTool + ')');
  let args = null; try { args = JSON.parse(fn.arguments || '{}'); } catch (e) { parts.push('ARGS_UNPARSEABLE'); }
  if (args && wantArgs) {
    for (const [k, v] of Object.entries(wantArgs)) {
      const got = args[k];
      const ok = String(got) === String(v);
      parts.push(k + '=' + JSON.stringify(got) + (ok ? '' : ' EXPECTED ' + JSON.stringify(v)));
    }
  } else if (args) {
    parts.push('args=' + JSON.stringify(args).slice(0, 70));
  }
  return parts.join(' ');
}

(async () => {
  console.log('model'.padEnd(46) + ' | caseA(无参工具)'.padEnd(46) + ' | caseB(参数保真)');
  console.log('-'.repeat(160));
  for (const m of CANDIDATES) {
    const a = await post(m, CASE_A);
    const aV = verdict(a, 'get_self_status', null);
    await new Promise(r => setTimeout(r, 700));
    const b = await post(m, CASE_B);
    const bV = verdict(b, 'mine', { block: 'minecraft:iron_ore', count: 64 });
    const cost = (a.j && a.j.usage && a.j.usage.cost != null) ? a.j.usage.cost : '?';
    console.log(m.padEnd(46) + ' | ' + (aV + ' [' + a.ms + 'ms cost=' + cost + ']').padEnd(46) + ' | ' + bV + ' [' + b.ms + 'ms]');
  }
})();
