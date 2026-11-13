'use strict';
// 2026-11-13: actual CLI, temporary ZIPs only. No game, datagen, release or live writes.
// Freeze standalone compatibility, exact registered embedded API discovery, and false-positive rejection.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const {spawnSync} = require('node:child_process');
const cli = path.join(__dirname, 'check-jar-lang.js');
const wanted = ['assets/numen_api/lang/en_us.json','assets/numen_api/lang/zh_cn.json'];
const innerPath = 'META-INF/jarjar/com.dwinovo.numen.api.numen_api-neoforge-test.jar';
// Same minimal ZIP fixture format used by classrefs selftest; CRCs are not under test.
function zip(entries, deflate=false) {
  const local=[], central=[]; let offset=0;
  for(const [name,value] of entries) {
    const n=Buffer.from(name), raw=Buffer.isBuffer(value)?value:Buffer.from(value);
    const data=deflate?zlib.deflateRawSync(raw):raw, method=deflate?8:0;
    const lh=Buffer.alloc(30), cd=Buffer.alloc(46);
    lh.writeUInt32LE(0x04034b50);lh.writeUInt16LE(20,4);lh.writeUInt16LE(method,8);
    lh.writeUInt32LE(data.length,18);lh.writeUInt32LE(raw.length,22);lh.writeUInt16LE(n.length,26);
    cd.writeUInt32LE(0x02014b50);cd.writeUInt16LE(20,4);cd.writeUInt16LE(20,6);cd.writeUInt16LE(method,10);
    cd.writeUInt32LE(data.length,20);cd.writeUInt32LE(raw.length,24);cd.writeUInt16LE(n.length,28);cd.writeUInt32LE(offset,42);
    local.push(lh,n,data);central.push(cd,n);offset+=30+n.length+data.length;
  }
  const cd=Buffer.concat(central), end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(cd.length,12);end.writeUInt32LE(offset,16);
  return Buffer.concat([...local,cd,end]);
}
function api(names=wanted) {return zip(names.map(n=>[n,'{}']),true);}
function outer(inner=api(), registered=innerPath) {
  const metadata={jars:[{identifier:{group:'com.dwinovo.numen.api',artifact:'numen_api-neoforge'},path:registered}]};
  return zip([['META-INF/jarjar/metadata.json',JSON.stringify(metadata)],[innerPath,inner]],true);
}
function fixture(t) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'lang-guard-'));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  return {dir, put(name,data){const p=path.join(dir,name);fs.writeFileSync(p,data);return p;},run(args=[]) {
    const r=spawnSync(process.execPath,[cli,'--dir',dir,'--json',...args],{encoding:'utf8'});
    assert.equal(r.error,undefined);
    let out;try{out=JSON.parse(r.stdout);}catch{assert.fail('CLI must return JSON: '+r.stdout+r.stderr);}
    return {exit:r.status,out};
  }};
}
function check(r,exit,state) {assert.equal(r.exit,exit,JSON.stringify(r.out));assert.equal(r.out.state,state);assert.equal(r.out.ok,exit===0);}
test('standalone API with both entries remains OK',t=>{const f=fixture(t);f.put('numen_api-neoforge-test.jar',api());check(f.run(),0,'OK');});
test('standalone missing translation remains MISSING_LANG',t=>{const f=fixture(t);f.put('numen_api-neoforge-test.jar',api([wanted[0]]));check(f.run(),1,'MISSING_LANG');});
test('filename strings in another entry are not translations',t=>{const f=fixture(t);f.put('numen_api-neoforge-test.jar',zip([['decoy.class',wanted.join(' ')] ]));check(f.run(),1,'MISSING_LANG');});
test('registered deflated embedded API is discovered',t=>{const f=fixture(t);f.put('numen-neoforge-test.jar',outer());const r=f.run();check(r,0,'OK');assert.equal(r.out.entryJar,innerPath);});
test('embedded missing translations is FAIL not ENV',t=>{const f=fixture(t);f.put('numen-neoforge-test.jar',outer(api([])));check(f.run(),1,'MISSING_LANG');});
test('explicit core jar resolves registered API',t=>{const f=fixture(t);const p=f.put('numen-neoforge-test.jar',outer());const r=f.run(['--jar',p]);check(r,0,'OK');assert.equal(r.out.entryJar,innerPath);});
test('unregistered embedded file is not a loaded API',t=>{const f=fixture(t);f.put('numen-neoforge-test.jar',zip([[innerPath,api()]]));check(f.run(),3,'ENV');});
test('registered missing inner path is ENV',t=>{const f=fixture(t);f.put('numen-neoforge-test.jar',outer(api(),'META-INF/jarjar/missing.jar'));check(f.run(),3,'ENV');});
test('registered parent traversal is ENV',t=>{const f=fixture(t);f.put('numen-neoforge-test.jar',outer(api(),'META-INF/jarjar/../outside.jar'));check(f.run(),3,'ENV');});
test('malformed jar returns JSON ENV',t=>{const f=fixture(t);f.put('numen_api-neoforge-test.jar',Buffer.from('not a zip'));check(f.run(),3,'ENV');});
test('multiple standalone APIs are ambiguous',t=>{const f=fixture(t);f.put('numen_api-neoforge-a.jar',api());f.put('numen_api-neoforge-b.jar',api());check(f.run(),3,'ENV');});
test('standalone and embedded together are ambiguous',t=>{const f=fixture(t);f.put('numen_api-neoforge-test.jar',api());f.put('numen-neoforge-test.jar',outer());check(f.run(),3,'ENV');});
test('no provider returns ENV',t=>{check(fixture(t).run(),3,'ENV');});
