'use strict';
/**
 * Deployment CLI regression using real git histories and a valid empty jar (2026-11-07).
 * WHY: d1d0603 changed tests only, but own-module lookup forgot excludeTests and blocked launch.
 * Run: node --test check-runtime-deployment.test.js. No game, Gradle, live jar or approval changes.
 * We test the actual CLI rather than exporting a second source-change classifier.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync, spawnSync} = require('node:child_process');
const cli = path.join(__dirname, 'check-runtime-deployment.js');

function fixture(t, changed) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'deployment-input-test-'));
  t.after(() => fs.rmSync(root, {recursive:true, force:true}));
  const repo=path.join(root,'repo'), mods=path.join(root,'mods');
  fs.mkdirSync(repo);fs.mkdirSync(mods);
  function git(args,date) {
    return execFileSync('git',['-C',repo,...args],{encoding:'utf8',env:{...process.env,
      GIT_AUTHOR_DATE:date,GIT_COMMITTER_DATE:date}});
  }
  git(['init'],'2020-01-01T00:00:00Z');
  git(['config','user.email','test@local'],'2020-01-01T00:00:00Z');
  git(['config','user.name','deployment-test'],'2020-01-01T00:00:00Z');
  function commit(file,date) {
    const full=path.join(repo,'plugins/acx',file);fs.mkdirSync(path.dirname(full),{recursive:true});
    fs.writeFileSync(full,'fixture '+date);git(['add','.'],date);git(['commit','-m','fixture'],date);
  }
  commit('src/main/java/Production.java','2020-01-01T00:00:00Z');
  commit(changed,'2020-01-03T00:00:00Z');
  const jar=path.join(mods,'numen-plugin-acx-fixture.jar');
  const zip=Buffer.alloc(22);zip.writeUInt32LE(0x06054b50);fs.writeFileSync(jar,zip);
  fs.utimesSync(jar,new Date('2020-01-02T00:00:00Z'),new Date('2020-01-02T00:00:00Z'));
  return spawnSync(process.execPath,[cli,'--src',repo,'--mods',mods],{encoding:'utf8'});
}
for (const file of ['src/test/java/OnlyTest.java','src/test/resources/fixture.ac']) {
  test('test-only change does not stale jar: '+file,t=>{
    const r=fixture(t,file);assert.equal(r.status,0,r.stdout+r.stderr);assert.match(r.stdout,/VERDICT=DEPLOYED/);
  });
}
for (const file of ['src/main/java/Production.java','src/main/java/ProductionTest.java','src/client/java/Client.java',
    'src/main/resources/assets/lang.json','src/client/resources/assets/client.json',
    'src/main/resources/acx-lib/stable/script.ac','build.gradle']) {
  test('production input remains stale: '+file,t=>{
    const r=fixture(t,file);assert.equal(r.status,2,r.stdout+r.stderr);assert.match(r.stdout,/VERDICT=STALE/);
  });
}
