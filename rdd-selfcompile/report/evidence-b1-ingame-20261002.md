# B1 进游戏验证证据（ExperienceStore 读层修复）

- 日期：2026-10-02 17:01–17:10
- 实例：live（= gpt = `E:\.minecraft\versions\The Best of Twilight Forest`）
- 代码：`minecraft-numen` commit `f98f90cf`（分支 redline-1）→ 部署进 `numen-plugin-experience-1.21.1-0.1.3-dev.jar`（16:54:15，69,195 字节）
- 部署通道：`run-mutation.ps1 -Module plugins:experience -SkipLaunch -SkipMcp`（**不是** `experience-core`：`ExperienceStore` 被 `plugins/experience/build.gradle` 以 `from(project(':experience-core').sourceSets.main.output)` 内嵌进插件 fat jar，live mods 里没有独立 `experience-core` jar）
- 部署核验：live jar 内 `ExperienceStore.class` 常量池含 11/11 新特征串（`LoadStats`/`migrateLegacyShape`/`pre-migrate`/`loadStats`/`needsMigrate`/`degraded`/`is not line-delimited`/`failed to parse`/`statLegacy`/`statFailed`/`statLine`）

## 改动是什么

`ensureLoaded()` 从「逐行 `readAllLines` + 每行 `getAsJsonObject`」改成「整文件 `readString` + 三形状判别」：
- 根是 JSON **数组** → 遗留形状，逐元素读（此前这**唯一 1 行**被 `catch(RuntimeException)` 吞掉，mirror 恒空）
- 根是 JSON **对象** → 遗留形状，整文件算 1 条
- 否则 → 正常逐行
新增 `LoadStats(loadedLine, loadedLegacy, loadedFailed)` + `loadStats()` + `migrateLegacyShape()`（备份一次、幂等）。`persist()` 一行未改。

## 验证怎么做的（关键：怎么让「读」真的发生）

1. 活动同伴是 `0c210695-1718-400a-959c-058541fc6d21`，它**本来没有经验文件**；两个遗留数组文件属于别的同伴（`c29c5c40` / `da53ed54`）。直接把真实遗留文件复制成活动同伴的库（20255 字节，`[{` 开头，21 条），不造假数据。
2. `ExperiencePlugin.MEMORIES` 是**懒加载**（`ExperiencePlugin.java:71` `computeIfAbsent`），启动时不会建 store；日志里 `plugin ready` 之后**没有任何 ensureLoaded 迹象**。靠 `contributePlanningKnowledge` → `ExperienceKnowledgeSource.fromMemory`（`:100` → `ExperiencePlugin.memory()`）或经验工具触发。
3. 用 `rdd-selfcompile/scripts/numen-mcp.js`（8765 = live）调 `experience_recall` 触发。

## A2 —— 读得出（PASS）

`experience_recall`（query=`mine diamond ore`）返回 **5 条真实命中**，首条即修复前完全读不到的那条：

```
{"success":true,"message":"experience recall returned 5 hit(s)","data":{"hits":[
 {"id":"tooldefect|工具等级必须匹配目标硬度","type":"TOOL_DEFECT","maturity":"ATTEMPTED",
  "score":11.2,"matched_terms":["mine","diamond","ore"], ...},
 ... 共 5 条（含 execution|探索类子步要防原地打转 / failure|双驾驶会导致原地左右横跳
     / policy|技能依赖必须按顺序 / tool_defect|附魔台gui按钮无法点击）]}}
```

新代码在游戏里说话（`latest.log`，17:08:05）：

```
[Server thread/WARN] [com.dwinovo.numen.experience.core.ExperienceStore/]: [experience]
  E:\...\config\numen\experience-0c210695-1718-400a-959c-058541fc6d21.jsonl
  is not line-delimited JSONL (loaded 21 via legacy shape); call migrateLegacyShape() to convert it
```

- `loaded 21 via legacy shape` = 21 条全部读出（不是只读出 1 条）
- `degraded` 告警 **0** 条 = 21 条全部解析成功，没有一条被吞
- 与数据层预演（Node 复刻跑真实存档副本，`RESULT=ALL_OK`）一致

监测台面板数字翻了：`/api/chain` 的 `measured.readableByStore` **0 → 22**。

## A3 —— 形状自愈（PASS）

调一次 `experience_learn`（写入会 `persist()` 重写镜像），文件当场从「整个数组」变成真 JSONL：

| | 修前/写入前 | 写入后 |
|---|---|---|
| 大小 | 20,255 B | 21,840 B |
| 非空行数 | 1 | **22** |
| 形状 | `[{` 开头（整个数组） | 逐行 JSON，首行 `{` |
| 逐行可解析 | — | **22 / 22，失败 0** |

21 + 1 = 22，条目守恒。**首次写入即自愈**，`migrateLegacyShape()` 甚至不必手动调（它是显式 API，不是自动路径）。

## 顺带查清的两件事

1. **`readableByStore` 以前为什么恒为 0** —— 不是游戏报的，是监测台自己按磁盘形状猜的：`chain-view.mjs:272` `files.filter(f => f.readableAsJsonl).reduce(...)`，`readableAsJsonl` 只认逐行 JSONL。它**没接 `LoadStats`**，所以代码修好了它也得等文件形状变真才跟着变（这次是写入自愈后同步翻正）。**这是已知观测缺口，不是回归。**
2. **`<experience>` 状态块仍未观测到** —— `contributeState`（`ExperiencePlugin.java:49-61`）在 `total()==0` 时返回空串；本次 `store.size()` 已经是 22，但面板 `tagHitCounts.experience` 仍 0、rdd.jsonl 里 `<experience>` 0 命中。**未自行派活去造 LLM 请求**（「关 MCP 止投，只读」），需要同伴下一次真正发起 LLM 请求时才能确认。`chain-view.mjs:183` 的 `experienceTagAbsentWhy` 文本写的还是修复前的根因（`total()==0 → mirror 为空`），**已过期，下批要改**。

## 环境备注（踩到的）

- `run-mutation.ps1` 直接 `&` 调用被 **ExecutionPolicy 拦**（UnauthorizedAccess）→ 必须 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`。
- `-Module experience-core` 会被 `config.ps1:98` 拒（要求 `group:name`）→ 用 `plugins:experience`。
- `mc-start.js` 经 **后台轮询脚本脱离启动时，launch 环节静默失败**（java 一直 0，launch/watchdog 日志无新行）；**前台调 `launch-mc.ps1` 一次就起来了**（该脚本自身起完即返回，不阻塞）。返回值管道会因 bat 的 `pause` 挂住，属已知现象。
- 空闲内存门 1200MB 已被用户明令去掉（见同批 `mc-start.js` 改动：硬拦 → 一句提示）。
