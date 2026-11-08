/** 无MCP客户端时的同核入口。2026-11-06：避免接入前无法验证。
 * 用法：node cli.mjs arch_focus taskchain；其余参数可用JSON对象。
 * 不写事实、不启动游戏；错误非零退出。
 */
import { Architecture } from './core.mjs';
import { graphFile,knowledgeRoot } from './config.mjs';
try {
 const argv=process.argv.slice(2).filter(a=>!a.startsWith('--'));
 const name=argv[0] || 'arch_overview', raw=argv[1];
 const args=raw ? raw.startsWith('{') ? JSON.parse(raw) : name==='arch_search'?{query:raw}:{focus:raw} : {};
 console.log(JSON.stringify(new Architecture(graphFile,knowledgeRoot).call(name,args),null,2));
} catch(e) { console.error(e.message); process.exitCode=1; }
