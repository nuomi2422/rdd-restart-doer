/** 离线契约与真实stdio协议测试。2026-11-06：存在工具不等于客户端可用。
 * 用法：node --test test.mjs；不连接游戏，不改生产图谱。
 * 临时夹具只在系统临时目录创建；各客户端finally关闭。
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Architecture,hash } from './core.mjs';
import { graphFile,knowledgeRoot,sdk } from './config.mjs';
const arch=()=>new Architecture(graphFile,knowledgeRoot);
test('总览保留目标与三线',()=>{const r=arch().call('arch_overview');assert.equal(r.anchor.id,'goal');assert.equal(r.truncated,false);assert.equal(r.result.children.length,3);});
test('任务联想到资产、基建与执行',()=>{const r=arch().call('arch_focus',{focus:'taskchain',maxChars:40000});assert.equal(r.truncated,false);assert(r.result.related.some(x=>x.node.id==='settlement'));assert(r.result.children.some(x=>x.id==='rdd'));});
test('分层路径与横向原因',()=>{const r=arch().call('arch_focus',{focus:'assets',maxChars:40000});assert.deepEqual(r.result.breadcrumb.map(x=>x.id),['goal','taskchain','rdd','assets']);assert(r.result.related.some(x=>x.node.id==='settlement'&&x.via.why));});
test('冲突并列，不冒充已验',()=>{const r=arch().call('arch_status',{focus:'worldstate'});assert.equal(r.result.nodes[0].assessment,'conflicting_reports');assert.equal(r.result.nodes[0].status.effect,'unproven');});
test('下一步只是建议',()=>{assert.equal(arch().call('arch_next',{focus:'experience'}).result.candidates[0].kind,'inference_not_decision');});
test('语义别名词项可搜',()=>{assert(arch().call('arch_search',{query:'备用装备'}).result.matches.some(x=>x.id==='settlement'));});
test('空白搜索不匹配全图',()=>{assert.equal(arch().call('arch_search',{query:' 不存在999 '}).result.matches.length,0);});
test('默认状态保留状态而非仅名单',()=>{const r=arch().call('arch_status');assert.equal(r.truncated,false);assert(r.result.nodes.every(n=>n.status&&n.assessment));});
test('小预算仍留冲突与分页',()=>{const r=arch().call('arch_focus',{focus:'worldstate',maxChars:2000});assert.equal((r.result.summary||r.result.focus).assessment,'conflicting_reports');const s=arch().call('arch_source',{sourceId:'rdd',lineCount:100,maxChars:2000});assert.equal(s.result.source.id,'rdd');assert(s.result.lines.length>0);assert.equal(s.result.nextLine,s.result.startLine+s.result.lines.length);assert(JSON.stringify(s).length<=2000);});
test('按行分页来源',()=>{const r=arch().call('arch_source',{sourceId:'rdd',startLine:15,lineCount:3});assert.equal(r.result.lines[0].line,15);assert.equal(r.result.lines.length,3);assert.equal(r.result.nextLine,18);});
test('小预算保留目标，不截坏JSON',()=>{for(const tool of ['arch_overview','arch_focus','arch_status']){const r=arch().call(tool,{maxChars:2000});assert(JSON.stringify(r).length<=2000);assert.equal(r.anchor.id,'goal');}});
test('未知与坏参数不静默成功',()=>{assert.throws(()=>arch().call('arch_focus',{focus:'missing'}));assert.throws(()=>arch().call('arch_focus',{depth:5}));assert.throws(()=>arch().call('arch_search',{query:''}));assert.throws(()=>arch().call('arch_source',{sourceId:'../../secret'}));});
test('提案不写入也不自授主人身份',()=>{const before=fs.readFileSync(graphFile,'utf8');const r=arch().call('arch_propose',{focus:'goal',text:'补充想法'});assert.equal(r.result.persisted,false);assert.equal(r.result.proposal.kind,'unconfirmed_proposal');assert.equal(fs.readFileSync(graphFile,'utf8'),before);});
test('变动、缺失来源及层级环被识别',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'rdd-arch-test-')), source=path.join(root,'s.md'), file=path.join(root,'g.json');
 try {fs.writeFileSync(source,'one');const graph={root:'g',sources:[{id:'s',path:'s.md',sha256:hash('one')}],nodes:[{id:'g',title:'g',purpose:'g',sources:['s']}],edges:[]};fs.writeFileSync(file,JSON.stringify(graph));const a=new Architecture(file,root);assert.equal(a.call('arch_focus').result.focus.assessment,'document_report_only');fs.writeFileSync(source,'two');assert.equal(a.call('arch_focus').result.focus.assessment,'needs_recheck');fs.unlinkSync(source);assert.equal(a.call('arch_focus').result.focus.assessment,'needs_recheck');graph.nodes[0].parent='g';fs.writeFileSync(file,JSON.stringify(graph));assert.throws(()=>a.call('arch_overview'),/层级循环/);
 }finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('真实MCP握手、工具、资源与错误', {timeout:15000}, async()=>{
 const {Client}=await sdk('client/index.js'),{StdioClientTransport}=await sdk('client/stdio.js');
 const client=new Client({name:'architecture-contract-test',version:'1.0.0'});
 const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('./server.mjs',import.meta.url))],stderr:'inherit'});
 try {await client.connect(transport);const list=await client.listTools();assert.equal(list.tools.length,7);const overview=await client.callTool({name:'arch_overview',arguments:{}});assert(!overview.isError);assert.equal(JSON.parse(overview.content[0].text).anchor.id,'goal');const bad=await client.callTool({name:'arch_focus',arguments:{focus:'no-such-node'}});assert.equal(bad.isError,true);const resources=await client.listResources();assert.equal(resources.resources.length,1);const r=await client.readResource({uri:'architecture://overview'});assert.equal(JSON.parse(r.contents[0].text).anchor.id,'goal');}finally{await client.close();await transport.close();}
});
