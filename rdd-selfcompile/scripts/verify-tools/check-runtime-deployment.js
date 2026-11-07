#!/usr/bin/env node
'use strict';
/*
 * check-runtime-deployment.js
 * 查「源码改了但没编译部署」—— 游戏里跑的还是旧版。
 *
 * 为什么需要：2026-10-01 出了个假完成 —— RL-19 在文档里写「已改」，
 *   但部署的 jar 比提交早 2 天多。**源码改了 ≠ 游戏里变了。**
 *   中间隔着：编译 → 部署 jar → 重启游戏。
 *
 * ★ 判据不能只看时间（第一版就错在这）：
 *   改了 6 个 *Test.java，main 一行没动 → jar 不需要重新部署。
 *   所以核心判据是「该模块最后一次**改 main 源码**的提交时间」，
 *   不是「最后一次提交时间」。
 *
 * 退出码：0 = 全部已部署 / 2 = 有源码领先于 jar / 3 = 环境错
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const CLASSREFS = require('./classrefs.js');

const EXIT_OK = 0;
const EXIT_STALE = 2;
const EXIT_USAGE = 3;

// jar 构建发生在 commit 之后几分钟是正常的，30 分钟内不算「没部署」
const TOLERANCE_MS = 30 * 60 * 1000;

// 部署流水（H4）：用来做「内容证明」——见 ledgerProvesRedeployed 的注释。
const LEDGER = 'D:\\rdd\\workspace\\rdd-selfcompile\\report\\deploy-ledger.jsonl';

const DEFAULT_SRC = 'D:\\rdd\\workspace\\minecraft-numen';
// ★ 只扫 live（= gpt 实例 = D:\rdd\mc\The Best of Twilight Forest）。
//   用户 2026-10-01 确认：现在只用 live，instances\test 已不再使用 → 不计入债。
//   test 目录仍在磁盘上，要查就显式 --mods <路径> 或 --all-instances。
const DEFAULT_MODS = [
  'D:\\rdd\\mc\\The Best of Twilight Forest\\mods',   // ← live（唯一在用）
];
const TEST_MODS = 'D:\\rdd\\workspace\\rdd-selfcompile\\instances\\test\\mods';

/**
 * 跨模块依赖图：每个 jar **编译期看到的**上游源码目录（来自各 build.gradle 的
 * compileOnly / api project(...)；2026-10-30 逐条核对过）。
 *
 * <p><b>为什么需要它</b>（2026-10-30 H10 事故）：`api/common` 删掉一个类，
 * 插件 jar 是**在这之前**编的，运行时直接 `IToolSpec is null` / NoClassDefFound 崩掉。
 * 原来的判据只看「本模块自己的源码改没改」，对这种情况完全瞎 —— 上游变了它照样报 DEPLOYED。
 *
 * <p><b>这个判据会过度报警，必须知道</b>：它只证明「上游在本 jar 之后改过」，
 * **不证明**这个 jar 真的用到了被改的东西。实测 2026-10-30：api/common 最后一次
 * 源码改动（3472352）之后，8 个插件 jar 全部「更旧」—— 若当成硬门禁，等于每次
 * api 改动都要重打全部插件。所以默认只报 `UPSTREAM`（WARN 级、不改变退出码），
 * 由 `--strict-upstream` 显式开启硬判；类级精确核对（只比真正被引用的类还在不在）
 * 另立一批，判据写进 registry 的 open 项。
 */
const UPSTREAM = {
  // 插件走 numen-plugin 约定：compileOnly 瘦 apiJar(:api:neoforge，内容=api:common+ai+ui) + ai + ui
  'numen-plugin-rdd': ['core/common', 'api/common', 'ai', 'ui'],
  'numen-plugin-selfcompile': ['api/common', 'ai', 'ui'],
  'numen-plugin-learner': ['api/common', 'ai', 'ui', 'rdd-core'],
  'numen-plugin-acx': ['api/common', 'ai', 'ui'],
  'numen-plugin-experience': ['api/common', 'ai', 'ui'],
  // camera 只依赖 MC + mixin，不 import 任何 numen 类型（见 plugins/camera/build.gradle 注释）
  'numen-plugin-camera': [],
  'numen_api': ['ai', 'ui'],          // api-loader.gradle 把 ai/ui 的类平铺进发行 jar
  'numen-neoforge': ['api/common'],   // multiloader-loader 把 core:common 源码编进来
};

/** jar 文件名主干 → git 源码目录（按依赖关系配对） */
const JAR_TO_MODULE = {
  'numen-plugin-rdd': { dirs: ['plugins/rdd', 'rdd-core'], label: 'RDD 插件(+rdd-core)' },
  'numen-plugin-selfcompile': { dirs: ['plugins/selfcompile'], label: '自编译插件' },
  'numen-plugin-learner': { dirs: ['plugins/learner'], label: '学习者插件' },
  'numen-plugin-acx': { dirs: ['plugins/acx'], label: 'ACX 插件' },
  'numen-plugin-experience': { dirs: ['plugins/experience'], label: '经验插件' },
  'numen_api': { dirs: ['api/common', 'ai'], label: 'NumenApi + ai' },
  'numen-neoforge': { dirs: ['core/common'], label: '模组本体' },
};

function git(repo, args) {
  try {
    return execFileSync('git', ['-C', repo, ...args], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000,
    });
  } catch (e) { return ''; }
}

/**
 * 该目录最后一次改「会进 jar 的源码」的提交时间（null = 从没改过 / 目录不存在）。
 *
 * <p><b>2026-10-21 扩了视野</b>（#099 的债）：原来只认 `src/main/java`，于是
 * `api/common/src/client/java`（整个客户端大脑 `EntityAgentLoop`）的改动**不在判据里** ——
 * 实测：改完 `EntityAgentLoop` 跑本检查，仍然报 `VERDICT=DEPLOYED`。那是最坏的一种假绿：
 * 判据本身漏了一块，而报告说「已部署」。
 *
 * <p>现在认任何 `src/<sourceSet>/java`（main / client / 以及将来新增的源集）。
 */
function lastMainChange(repo, dir, opts) {
  const excludeTests = !!(opts && opts.excludeTests);
  // 2026-11-07: resources (including packaged AC scripts) are production inputs too.
  // Do not exempt scripts by extension; src/main/resources/acx-lib/*.ac still makes a jar stale.
  const LOOKS_LIKE_SOURCE = /src[\\/][^\\/]+[\\/](?:java|resources)[\\/]|(?:^|[\\/])build\.gradle(?:\.kts)?$/;
  // 上游判据要更保守：只改测试绝不该要求重建（否则一条测试提交会把所有插件判成要重建）
  const IS_TEST = /src[\\/]test[\\/]/; // A production class named *Test.java still ships.
  const passes = [['-n', '30'], ['-n', '200']];
  for (const extra of passes) {
    const raw = git(repo, ['log', '--format=%H|%ct', '--name-only', ...extra, '--', dir]);
    if (!raw) continue;
    let cur = null;
    for (const line of raw.split(/\r?\n/)) {
      const m = line.match(/^([0-9a-f]{40})\|(\d+)$/);
      if (m) { cur = { sha: m[1], ts: parseInt(m[2], 10) * 1000 }; continue; }
      if (!cur) continue;
      if (!LOOKS_LIKE_SOURCE.test(line)) continue;
      if (excludeTests && IS_TEST.test(line)) continue;
      return cur;   // 第一个动过源码集的提交
    }
  }
  return null;
}

/**
 * 「内容证明」：当前部署的 jar 的 sha256，是否在 deploy-ledger 里有一条 `at` 晚于提交时间的记录。
 *
 * <p>为什么需要它：`deploy.ps1` 遇到内容相同的 jar 会跳过拷贝（好设计——可重复构建下 sha 不变），
 * 但这样一来 mtime 就停在**上一次**拷贝的时刻。而「先部署、后提交」的顺序会让
 * mtime < 提交时间 → 判据说「源码领先 3 小时」，可 jar 里明明是同一份代码。
 * 实测踩过两次（`…-s107` 与 `…-s107-redeploy` 两次部署 sha 都是 A7F54E13）。
 *
 * <p>判据不放松成「有记录就行」：必须 **sha 完全相等** 且 **记录时间 ≥ 提交时间**。
 */
function ledgerProvesRedeployed(jarFullPath, jarFileName, commitTs) {
  try {
    const crypto = require('crypto');
    const sha = crypto.createHash('sha256').update(fs.readFileSync(jarFullPath)).digest('hex').toUpperCase();
    if (!fs.existsSync(LEDGER)) return false;
    const lines = fs.readFileSync(LEDGER, 'utf8').split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      let row;
      try { row = JSON.parse(line); } catch { continue; }
      if (!row || row.jar !== jarFileName) continue;
      if (String(row.sha || '').toUpperCase() !== sha) continue;
      const at = Date.parse(row.at);
      if (!Number.isFinite(at)) continue;
      if (at + TOLERANCE_MS >= commitTs) return true;
    }
    return false;
  } catch {
    return false;   // 读不到就按「没证明」处理，不假装 OK
  }
}

function fmt(ts) {  const d = new Date(ts);
  const p = n => String(n).padStart(2, '0');
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function main() {
  const args = process.argv.slice(2);
  let src = DEFAULT_SRC, modsDirs = [];
  let strictUpstream = false;
  let noClass = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--src') src = args[++i];
    else if (args[i] === '--mods') modsDirs.push(args[++i]);
    else if (args[i] === '--strict-upstream') strictUpstream = true;
    else if (args[i] === '--no-class') noClass = true;
    else if (args[i] === '--help' || args[i] === '-h') {
      console.log(`用法：node check-runtime-deployment.js [--src <minecraft-numen 路径>] [--mods <实例 mods 目录>] [--strict-upstream] [--no-class]

  --src              Java 源码仓库（默认 minecraft-numen）
  --mods             实例 mods 目录，可重复。默认只扫 live（唯一在用）
  --strict-upstream  上游依赖变更也按 STALE 处理（默认只报 UPSTREAM 警告，不改变退出码）
  --no-class         跳过类级核对（默认跑；实测全部 jar 约 0.2s）

判据①（本模块）：该 jar 对应模块「最后一次改源码集的提交时间」 vs jar 的 LastWriteTime
  jar 更早 → 源码领先运行时，游戏里跑的是旧版
  只改测试（main 一行没动）→ 不算债
判据②（跨模块时间图，2026-10-30 新增）：上游目录最后一次改源码晚于本 jar → 报 UPSTREAM
  「需重建评估」。它只证明「上游动过」，不证明「这个 jar 真用到了被改的东西」；默认不改变退出码。
判据③（跨模块类级核对，2026-10-30 新增）：解 jar 常量池，列出插件引用到的 numen 类，
  与当前 mods 里真正投放的 jar 的类集合比对。**引用但不存在 = 一定 NoClassDefFoundError**，
  所以它默认就是硬判据（exit 2）—— 这是 H10 事故的真判据，时间图只是代理。

退出码：0 全部已部署 / 2 有源码领先、或有引用不到的类（或 --strict-upstream 下有上游变更）/ 3 环境错`);
      process.exit(EXIT_OK);
    }
  }
  if (!fs.existsSync(src)) { console.error(`源码仓库不存在: ${src}`); process.exit(EXIT_USAGE); }
  if (!modsDirs.length) modsDirs = DEFAULT_MODS.filter(d => fs.existsSync(d));
  if (!modsDirs.length) { console.error('没找到任何 mods 目录，用 --mods 指定'); process.exit(EXIT_USAGE); }

  // 预取所有模块的「最后改 main 时间」
  const modules = {};
  for (const [jar, info] of Object.entries(JAR_TO_MODULE)) {
    let latest = null;
    for (const d of info.dirs) {
      const c = lastMainChange(src, d, { excludeTests: true });
      if (c && (!latest || c.ts > latest.ts)) latest = { ...c, dir: d };
    }
    modules[jar] = { ...info, latest };
  }

  // 预取上游目录的「最后改源码（排除测试）时间」—— 同一次运行里多个 jar 共用，别重复跑 git
  const upstreamDirs = [...new Set(Object.values(UPSTREAM).flat())];
  const upstreamTimes = {};
  for (const d of upstreamDirs) {
    upstreamTimes[d] = lastMainChange(src, d, { excludeTests: true });
  }

  const stale = [];
  const upstreamWarn = [];
  const classStale = [];
  const rows = [];

  console.log('');
  console.log('════ 运行时部署检查（源码改了 vs jar 部署了没）════');
  console.log(`源码仓库 : ${src}`);
  console.log(`判据     : 该模块最后一次改生产 Java/资源/构建输入（排除测试）的提交时间 vs jar LastWriteTime`);
  console.log(`           （只改测试 → 不算债；这是第一版的错判点）`);
  console.log(`跨模块   : ${strictUpstream ? '严格模式（上游变更 = STALE）' : '上游变更只报 UPSTREAM 警告，不改变退出码'}`);
  console.log('');

  for (const modsDir of modsDirs) {
    const tag = modsDir.includes('instances\\test') ? 'test 实例' : 'live';
    console.log(`── ${tag}：${modsDir}`);
    const files = fs.readdirSync(modsDir).filter(f => f.startsWith('numen') && f.endsWith('.jar'));
    if (!files.length) { console.log('   （无 numen jar）\n'); continue; }

    for (const f of files.sort()) {
      const jarKey = Object.keys(JAR_TO_MODULE).find(k => f.startsWith(k));
      if (!jarKey) continue;
      const full = path.join(modsDir, f);
      const jarTs = fs.statSync(full).mtimeMs;
      const m = modules[jarKey];
      const srcTs = m.latest ? m.latest.ts : null;

      let verdict, detail;
      if (!srcTs) {
        verdict = '?';
        detail = '源码仓库里没找到这个模块（模块映射可能过期）';
      } else if (jarTs + TOLERANCE_MS >= srcTs) {
        // 容差 30 分钟：git 提交时间戳取自 commit 时刻，jar 构建发生在其后，
        // 差几分钟是正常的。不设容差会满屏「领先 0 小时」的假警报。
        verdict = 'OK';
        const h = Math.round((jarTs - srcTs) / 3600000);
        detail = h >= 1 ? `jar 比源码还新 ${h}h` : 'jar 已包含最新 main 改动';
      } else if (ledgerProvesRedeployed(full, f, srcTs)) {
        // ★ 2026-10-21 补的第三条路（假阳性修复，见 check-runtime-deployment.md §「两种假阳性」）：
        // mtime 只是「最后一次拷贝的时刻」，而部署脚本遇到**内容相同**的 jar 会跳过拷贝
        // （可重复构建 + 同一份源码 = 同一个 sha）。于是「先部署、后提交」这种顺序会被判成
        // 「源码领先 3 小时」，可 jar 里明明是同一份代码 —— 实测两次。
        // 判据改成「内容证明」：当前 jar 的 sha256，在 deploy-ledger 里有一条**晚于本次提交**的记录。
        verdict = 'OK';
        detail = 'jar 内容与提交后重新部署的一致（sha 见 deploy-ledger；mtime 因内容相同未更新）';
      } else {
        const gapH = (srcTs - jarTs) / 3600000;
        verdict = 'STALE';
        detail = gapH >= 1
          ? `★ 源码领先 **${Math.round(gapH)} 小时**（最后改 main：${m.latest.sha.slice(0, 7)} @ ${fmt(srcTs)}，在 ${m.latest.dir}）`
          : `★ 源码领先 **${Math.round(gapH * 60)} 分钟**（最后改 main：${m.latest.sha.slice(0, 7)} @ ${fmt(srcTs)}，在 ${m.latest.dir}）`;
        stale.push({ modsDir, tag, jar: f, gapH, detail, label: m.label });
      }
      rows.push({ tag, jar: f, jarTs, srcTs, verdict, detail, label: m.label, module: m.latest ? m.latest.dir : '?' });
      const mark = verdict === 'OK' ? '✔' : verdict === 'STALE' ? '✘' : '?';
      console.log(`   ${mark} ${f.padEnd(48)} jar ${fmt(jarTs)}   ${detail}`);

      // ── 判据②：跨模块。本 jar 自己的源码没落后，但它编译时看到的上游后来又改了 ──
      // 只在「本模块 OK」时才查：本模块已 STALE 的话，重建它就会顺带解决上游问题。
      if (verdict === 'OK') {
        for (const up of (UPSTREAM[jarKey] || [])) {
          const u = upstreamTimes[up];
          if (!u) continue;
          if (jarTs + TOLERANCE_MS >= u.ts) continue;              // 上游改动在本 jar 之前
          if (ledgerProvesRedeployed(full, f, u.ts)) continue;     // 流水证明改动之后重新部署过
          const gapH = (u.ts - jarTs) / 3600000;
          upstreamWarn.push({
            modsDir, tag, jar: f, upstream: up, gapH,
            detail: `上游 ${up} 在 ${fmt(u.ts)} 改过（${u.sha.slice(0, 7)}），比本 jar 新 ${Math.round(gapH)} 小时`,
          });
          console.log(`      ↳ 【需重建评估】${up} 在 ${fmt(u.ts)} 改过（${u.sha.slice(0, 7)}），比本 jar 新 ${Math.round(gapH)}h`);
        }
      }
    }

    // ── 判据③：类级核对（2026-10-30）。这是 H10 的**真判据**，不是代理。 ──
    // 「这个 jar 真正引用的类，当前 mods 里还在不在」：在 → 与当前 API 相容（时间图那条警告就可以不看）；
    // 不在 → 一定 NoClassDefFoundError，硬 STALE，不需要任何猜测。
    // 成本实测 ~0.2s/全部 jar（9 个文件、~1800 类），所以默认就跑；--no-class 可跳过。
    if (!noClass) {
      try {
        const cr = CLASSREFS.check(modsDir);
        if (cr.missing.length) {
          console.log(`   ✘ 类级核对：${cr.missing.length} 条引用指向不存在的类`);
          for (const m of cr.missing.slice(0, 8)) console.log(`        └─ ${m.jar} → ${m.cls}`);
          for (const m of cr.missing) classStale.push({ modsDir, tag, ...m });
        } else {
          const totalRefs = cr.jars.reduce((a, j) => a + j.refs, 0);
          console.log(`   ✔ 类级核对：${cr.jars.length} 个 jar、${totalRefs} 条 numen 引用，全部能解析到实现类`);
        }
      } catch (e) {
        console.log(`   ? 类级核对跑不起来（${String(e.message).slice(0, 80)}）—— 这是环境问题，不冒充通过`);
      }
    }
    console.log('');
  }

  console.log('─'.repeat(70));

  // 类级缺失是**硬**的：引用了不存在的类一定会崩，不需要任何解释
  if (classStale.length) {
    console.log(`VERDICT=STALE  ${classStale.length} 条引用指向当前 mods 里不存在的类（一定 NoClassDefFoundError）：`);
    for (const m of classStale) {
      console.log(`   · [${m.tag}] ${m.jar} → ${m.cls}`);
      console.log(`     修：run-mutation.ps1 -Requirement "<按当前 API 重建 ${m.jar}>" -Module <对应模块>  → 重启游戏`);
    }
    console.log('');
    console.log('★ 这就是 2026-10-30 H10 的形态：api/common 删了类、插件 jar 还是旧编译。');
    console.log('  每一条都是确定会崩的引用，不是「可能」—— 在修好前不许起游戏。');
    process.exit(EXIT_STALE);
  }

  // 跨模块结果单列：它和「本模块落后」是两种债，混在一起报会让人以为 jar 是旧的
  if (upstreamWarn.length) {
    console.log(`UPSTREAM   ${upstreamWarn.length} 项「上游比 jar 新」（需重建评估，${strictUpstream ? '严格模式 → 计入失败' : '默认不拦'}）：`);
    console.log('   ★ 它只说明「上游动过」，不证明这个 jar 真用到了被改的东西。');
    console.log('     「真的会不会崩」看上面的**类级核对**：引用但不存在 = 一定崩（那是硬判据，默认就拦）。');
    for (const w of upstreamWarn) {
      console.log(`   · [${w.tag}] ${w.jar.padEnd(46)} ← ${w.upstream}（${Math.round(w.gapH)}h）`);
    }
    console.log('');
  }

  if (strictUpstream && upstreamWarn.length) {
    console.log(`VERDICT=STALE  --strict-upstream：${upstreamWarn.length} 个 jar 的上游源码比它新，按失败处理`);
    for (const w of upstreamWarn) {
      console.log(`   · [${w.tag}] ${w.jar} ← ${w.upstream}（${Math.round(w.gapH)}h）`);
      console.log(`     修：run-mutation.ps1 -Requirement "<按新 API 重建 ${w.jar}>" -Module <对应模块>  → 重启游戏`);
    }
    console.log('');
    console.log('★ 严格模式会过度报警：上游改动不必然导致所有插件都要重编，');
    console.log('  它保证的是「你不能声称这些 jar 与当前 API 一致」。类级精确核对另立一批。');
    process.exit(EXIT_STALE);
  }

  if (!stale.length) {
    console.log('VERDICT=DEPLOYED  所有模块的 main 改动都已进 jar'
      + (upstreamWarn.length ? `（另有 ${upstreamWarn.length} 项上游需重建评估，未计为失败）` : ''));
    if (upstreamWarn.length && strictUpstream) {
      // 严格模式下不该走到这里（下面会先 exit），留一行防御
      console.log('★ --strict-upstream 已开启：上游变更应计为失败，这里出现说明判据有缺口');
    }
    console.log('');
    console.log('⚠️ 这只证明「jar 是新的」，不证明「游戏在跑这个 jar」——');
    console.log('   还要确认：① 游戏启动过（jar 改了要重启才生效）');
    console.log('            ② 加载的是这个目录（不是别的实例）');
    console.log('   要更强的话：解包 jar 找新写的特征字符串，见说明文档「怎么验真的生效了」。');
    process.exit(EXIT_OK);
  }

  console.log(`VERDICT=STALE  ${stale.length} 个 jar 的源码领先于部署：`);
  for (const s of stale) {
    console.log(`   · [${s.tag}] ${s.jar}`);
    console.log(`     ${s.detail}`);
    console.log(`     修：run-mutation.ps1 -Requirement "<部署 XX>" -Module <模块>  → 重启游戏`);
  }
  if (upstreamWarn.length) {
    console.log('');
    console.log(`   （另有 ${upstreamWarn.length} 项上游需重建评估，见上面 UPSTREAM 段）`);
  }
  console.log('');
  console.log('★ 这就是「假完成」的形态：源码改了、测试绿了、文档写了「已改」，');
  console.log('  但游戏里跑的还是旧版 —— 用户看到的是没生效的行为。');
  process.exit(EXIT_STALE);
}

main();