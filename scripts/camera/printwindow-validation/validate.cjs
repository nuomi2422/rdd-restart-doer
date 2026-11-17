'use strict';
const fs=require('fs'),path=require('path'),{spawn}=require('child_process');
const base=__dirname,recorder=path.resolve(base,'../long-record.cjs');
const root=path.join(base,'suite-'+new Date().toISOString().replace(/[:.]/g,'-'));
fs.mkdirSync(root);
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const touch=p=>fs.writeFileSync(p,'test-owned-only\n');
function job(exe,args,log){const fd=fs.openSync(log,'wx');const p=spawn(exe,args,{stdio:['ignore',fd,fd],windowsHide:true});let done=false;const end=new Promise(resolve=>p.on('close',(code,signal)=>{done=true;fs.closeSync(fd);resolve({code,signal,pid:p.pid})}));return {p,end,get done(){return done}};}
async function until(fn,ms=20000){const t=Date.now();while(!fn()){if(Date.now()-t>ms)throw Error('timeout waiting');await delay(100);}}
const summary=[];
async function test(name,seconds,action,options={}) {
 const dir=path.join(root,name);fs.mkdirSync(dir);const owned=job('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(base,'owned-neutral.ps1'),'-Dir',dir],path.join(dir,'fixture.log'));
 try {
  await until(()=>fs.existsSync(path.join(dir,'fixture.json'))||owned.done);
  if(owned.done) throw Error('fixture failed: '+dir);
  const identity=JSON.parse(fs.readFileSync(path.join(dir,'fixture.json'))),stop=path.join(dir,'STOP');
  const args=[recorder,'--print-window','--pid',String(identity.pid),'--hwnd',identity.hwnd,'--title',identity.title,'--fps','8','--seconds',String(seconds),'--output-root',dir,'--stop-file',stop];
  const recording=job(process.execPath,args,path.join(dir,'recorder.log'));
  await until(()=>fs.readdirSync(dir).some(n=>n.startsWith('continuous-'))||recording.done);
  const run=path.join(dir,fs.readdirSync(dir).find(n=>n.startsWith('continuous-')));
  await until(()=>fs.existsSync(path.join(run,'frames.csv'))||recording.done);
  if(action) await action({dir,run,stop,owned,recording});
  const terminal=await recording.end;
  const data=JSON.parse(fs.readFileSync(path.join(run,'terminal.json'),'utf8'));
  const row={name,dir,run,args,process:terminal,code:data.code,accounting:data.accounting,parts:data.parts};summary.push(row);
  fs.writeFileSync(path.join(root,'summary.json'),JSON.stringify(summary,null,2));console.log(JSON.stringify(row));
 } finally {if(!owned.done)touch(path.join(dir,'close'));await owned.end;}
}
(async()=>{
 await test('duration25-covered',25,async({dir})=>{await delay(4500);touch(path.join(dir,'cover'));});
 await test('stopfile-early',25,async({dir,stop})=>{await delay(5000);touch(stop);});
 await test('slow-owned',8,async({dir})=>{touch(path.join(dir,'slow'));});
 await test('sourceinvalid-closed',25,async({dir})=>{await delay(2500);touch(path.join(dir,'close'));});
 await test('sourceinvalid-resized',25,async({dir})=>{await delay(2500);touch(path.join(dir,'resize'));});
 await test('sourceinvalid-minimized',25,async({dir})=>{await delay(2500);touch(path.join(dir,'minimize'));});
 await test('blank-rejected',25,async({dir})=>{await delay(2500);touch(path.join(dir,'blank'));});
 console.log(JSON.stringify({event:'suite-complete',root,summary:path.join(root,'summary.json')}));
})().catch(e=>{console.error(e);process.exitCode=1});
