# check-runtime-deployment · 源码改了，jar 部署了吗

> **干什么**：比对「该模块最后一次改**源码集**（`src/*/java`，含 `src/client/java`）的提交时间」与
> 「部署到实例的 jar 的 `LastWriteTime`」。jar 更早 = **源码领先运行时** = 假完成。
>
> **为什么需要**：2026-10-01 出了一次真实的假完成 ——
> RL-19 在文档里写「已改」、测试全绿，但部署的 jar 比提交早 **56 小时**。
> **源码改了 ≠ 游戏里变了**，中间隔着 编译 → 部署 jar → 重启游戏。

## 怎么调

```powershell
# 默认扫 gpt 生产实例 + test 实例
node .\check-runtime-deployment.js

# 只扫生产实例
node .\check-runtime-deployment.js --mods "D:\rdd\mc\The Best of Twilight Forest\mods"

# 换个源码仓库/实例
node .\check-runtime-deployment.js --src "<minecraft-numen 路径>" --mods "<mods 目录>" --mods "<另一个>"
```

**退出码**：`0` 全部已部署 ｜ `2` 有源码领先于 jar ｜ `3` 环境错。
可当证据用（`run-mutation.ps1 -CollectEvidence`）。

## ★ 判据为什么不是「看最新提交时间」

第一版我直接比「模块最后一次提交 vs jar 时间」，**结果满屏假警报**：

| 误报 | 真相 |
|---|---|
| `rdd-core` 领先 9 小时 | 那次提交改了 **6 个 `*Test.java`，main 一行没动** → jar 本来就不需要重部署 |
| `learner` 领先 0 小时 | 提交后 3 分钟就构建了，**在 30 分钟容差内** |
| `AC jar 比源码新 584h` | jar 是复制过去的，保留了旧时间戳（无害） |

**所以核心判据必须是「最后一次改源码集的提交」**，不是「最后一次提交」。（2026-10-21 扩过视野：原来只认 `src/main/java`，导致 `api/common/src/client/java` —— 整个客户端大脑 `EntityAgentLoop` —— 的改动不在判据里，改完仍报 DEPLOYED。实测旧判据在 `api/common` 上取到 10-09 的提交，新判据取到 10-20 的 `af0889e6`。）
这个区分是本工具的全部价值 —— 分错了就会让人去部署根本不用部署的东西。

## 它能证明什么、不能证明什么

| ✅ 能证明 | ❌ 不能证明 |
|---|---|
| jar 的时间戳晚于该模块最后改动 | **游戏在跑这个 jar**（可能跑的是别的实例） |
| 源码里的改动「按时间」应该已经进去了 | **jar 内容真的对**（时间戳可能骗人） |
| 哪些模块该重新部署 | **行为真的生效**（要实机验） |

> **时间戳是弱证据。** 想确凿证明「新版生效了」，解包 jar 找新写的特征字符串：
> ```powershell
> # 例：RL-19 写了「外层专用」，旧版是「只创建审计目录」
> Add-Type -AssemblyName System.IO.Compression.FileSystem
> [System.IO.Compression.ZipFile]::ExtractToDirectory("<jar>", "$env:TEMP\jarx")
> $c = [System.IO.File]::ReadAllBytes("$env:TEMP\jarx\<类路径>.class")
> [System.Text.Encoding]::UTF8.GetString($c) -match "外层专用"
> ```

## 两种「假阳性」与修法（都是实测踩出来的）

判据用「提交时间 vs jar mtime」做代理，代理会漏两种真实情形：

| # | 情形 | 症状 | 修法（已落） |
|---|---|---|---|
| 1 | **客户端源码集不在视野里** | 改了 `api/common/src/client/java` 的 `EntityAgentLoop`，检查仍说 `DEPLOYED` | 判据从「只认 `src/main/java`」扩成 `src/<sourceSet>/java`（2026-10-21，#100） |
| 2 | **先部署、后提交** | 部署用工作区构建，提交晚 3 小时 → mtime < 提交时间 → 报「源码领先 3 小时」，但 jar 里就是同一份代码（两次部署 sha 都是 `A7F54E13`，可重复构建下内容相同→部署脚本跳过拷贝→mtime 不更新） | 加「**内容证明**」：当前 jar 的 sha256 若在 `deploy-ledger.jsonl` 里有一条**晚于本次提交**的记录，就判 `OK` 并注明原因（2026-10-21，#108） |

> 修法 2 不是放松判据：要求 **sha 完全相等** 且 **部署记录时间 ≥ 提交时间**；
> 读不到流水一律按「没证明」处理，不假装 OK。
> 教训：**判据用代理（时间戳）时，必须把代理会漏的真实顺序写下来**，否则每次都会有人（包括我）被它误伤。
> 2026-10-01 RL-19 就是这么验出「jar 里是旧文案」的。

## ★ 跨模块依赖（2026-10-30 新增）：上游改了，下游 jar 得知道

`api/common` 删掉一个类、插件 jar 却是**在这之前**编的 → 运行时直接崩（2026-10-30 H10：
`IToolSpec is null`）。原来的判据只看「本模块自己的源码改没改」，对这种情况完全瞎。

现在多一段 `UPSTREAM`：按各 `build.gradle` 的 `compileOnly` / `api project(...)` 建依赖图
（`plugins/rdd ← core/common, api/common, ai, ui` 等），只要**上游目录最后一次改源码**
（排除 `src/test/` 与 `*Test.java`）晚于本 jar 且部署流水无法证明之后重部署过，就报
「需重建评估」。

```
✔ numen-plugin-rdd-…jar   jar 10-30 08:48   jar 已包含最新 main 改动
   ↳ 【需重建评估】api/common 在 10-30 14:15 改过（3472352），比本 jar 新 5h
```

**默认只警告、不改变退出码。** 理由（实测，不是猜）：2026-10-30 api/common 改了一次，
8 个插件 jar **全部**「更旧」—— 时间图只证明「上游动过」，不证明「这个 jar 真用到了被改的东西」。
若默认按硬门禁算，等于每次 api 改动都要重打全部插件，几天内就会被忽略。

需要硬判时加 `--strict-upstream`（上游变更也算 STALE，exit 2）。它保证的是
「**你不能声称这些 jar 与当前 API 一致**」，不是「它们一定崩」。

> ★ 已知缺口（`registry.knownGaps[UPSTREAM-CLASS-CHECK]`）：真正的判据是**类级核对** ——
> 解 jar 常量池，把 `com/dwinovo/numen/` 的引用与当前 api/core jar 的类集合比对，
> 输出「引用但不存在」的清单。那才是 H10 的精确反例；时间图只是代理。

## ⚠️ 已知局限

1. **模块映射写死在文件头**（`JAR_TO_MODULE`）。新增插件要手动加一条，
   否则该 jar 会被静默跳过（输出里看不到它）。
2. **`numen-neoforge` 映射到 `core/common`** —— 模组本体一个大 jar 含所有 core 代码，
   但 `api/common` 是单独的 jar。改 `core/common` 时两个 jar 都可能要重打。
3. **不检查「游戏是否在跑」** —— jar 更新了但没重启游戏，一样不生效。
   这一项要靠 `14-运维手册` 的判据（java 进程 / latest.log / session.lock）。

## 建议接到哪里

- **每轮收口**（`stager close` 前）：`VERDICT=STALE` 就不许写「已改完」，
  先部署 + 重启 + 实机，再收。
- **文档里标「已改」之前**：先跑一遍，把结果连同 jar 时间一起写进 evidence。

> **这条比任何文档纪律都硬** —— 因为它查的是**事实**（文件时间戳），
> 不是**声明**（文档写了什么）。文档可以是错的，时间戳不会说谎。