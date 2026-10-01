# 经验库检索留痕 · 第二批第 0 步 · 签名 `a036646e` / `learner`

> 门禁依据：`06-检查清单`「过程中：经验库检索 —— 遇问题先 `search_nodes` 定向取经验。
> **只写不查 = 记了但没受益**；须把 `search` 结果落成文件」。

---

## 一 · 实际检索记录（本轮 plan / implement / verify 三阶段都查了）

| 阶段 | 检索词 | 命中 | 结论 |
|---|---|---|---|
| **plan** | `计划` | 7 条实体 | 命中 `gate-that-passes-fake-success-is-worse-than-no-gate`（**门禁自己也会骗人** → 直接影响我后面「BUILD_OK 不算成功」的取证纪律）；<br>命中 `method/trace-gates-should-migrate-to-event-assertions`（判据要迁到事件流，不是查痕迹）；<br>命中 `method/commentary-is-intent-visible-not-authority`（**叙述 ≠ 授权，通道不能混塞** → 直接成为 B14 反馈通道「不写回执行上下文」那条约束的来源） |
| **plan** | `架构` | 8 条实体 | 命中 `numen-cross-plugin-import-sealed`（跨插件 import 被 `numen-plugin.gradle:37-44` 封死 → 成为 B13 约束）；<br>命中 `issue/numen-external-gaps-20260929`（37 号那 10 个洞「零对策」→ 印证 B1「一律不在本批」）；<br>命中 `lesson-model-tier-by-task-nature-not-one-size`（**按任务性质分档，不是「一律用最贵」** → 本轮 GPT-6 只用 1 次而非 2 次的依据） |
| **implement** | `gradle` | 10 条实体 | 命中 `pitfall/ps51-setcontent-bom-breaks-java`（**`.java` 必须无 BOM** + 「读 `test-results/*.xml` 可能是上一轮旧缓存」→ **直接导致我第一次跑出 `UP-TO-DATE` 时没有误判**）；<br>命中 `issue/pipeline-build-ok-does-not-run-tests`（**`BUILD_OK` 不跑测试** → 我坚持用 gradle 直跑 `:test` 补测，并分开取证）；<br>命中 `issue/ai-classes-live-in-api-neoforge-jar`（改 `:ai` 必须同跑 `api:neoforge`，否则运行期 `NoClassDefFoundError`）；<br>命中 `rdd-selfcompile-closed-loop-real-gaps-20260929`（**`run-mutation.ps1 -Module` 就是解药** → 本轮部署正是靠它）；<br>命中 `powershell-colon-interpolation-trap`（`":$mod:jar"` 的坑） |
| **verify** | —— | —— | 门禁给出的证据表明本阶段沿用 implement 阶段的检索结果，**未重复检索**（不为了刷次数而检索） |

---

## 二 · 检索结果**实际改变了做法**的地方（这是留痕的意义）

| # | 检索到 | 它改变了我的什么 |
|---|---|---|
| 1 | `issue/pipeline-build-ok-does-not-run-tests` | 让我在 `run-mutation.ps1` 报 `BUILD_OK`+`DEPLOY_OK` 之后**仍然判它失败**（`VERIFY_FAIL total=2714 evidence=False`），坚持进游戏取证才算通过 |
| 2 | `pitfall/ps51-setcontent-bom-breaks-java` 里的「旧缓存」提醒 | 让我在 `test UP-TO-DATE` 时**立刻意识到不对**，改用 `--rerun-tasks`；以及后来 Qwen 盲区 D 逼我再做 `clean` 复核 |
| 3 | `method/commentary-is-intent-visible-not-authority` | 让 B14 反馈通道多了一条约束：**通道事件不注入执行上下文**（防「提醒变授权」） |
| 4 | `numen-cross-plugin-import-sealed` | 让 B13 多了一条「跨插件只走 `NumenApi`、**不得内嵌任何 core**」；也是我判断「恢复 learner 不会撞 JPMS」的依据 |
| 5 | `lesson-model-tier-by-task-nature-not-one-size` | 让本轮 GPT-6 **只用 1 次**（用户批了 2 次，第 2 次没硬凑），符合「额度用完就跳过，不等不换不硬凑」 |
| 6 | `gate-that-passes-fake-success-is-worse-than-no-gate` | 让我对 `30` 号的「752 tests / 新增 25」**不信任**，进而发现 learner 模块压根没被 include |
| 7 | `lesson/git-commit-precheck-embedded-repos-secrets-bigfiles` | 提交前只 `git add settings.gradle plugins/learner`（**精确 add，不 `add -A`**），避开根仓 4649 文件里那些含明文 token 的实例文件 |

---

## 三 · 结论

**查了，而且真被改变了做法（7 处）。** 本轮没有出现「查了库但发现是空的」这种正反馈坑 ——
检索在 plan 阶段就拿到了 3 条直接改变设计的条目，在 implement 阶段拿到了 4 条直接改变做法的坑。

> ⚠️ 另记一条纪律（来自 `46` 号 §6.4）：`search_nodes` 是**单关键词子串匹配**，
> 用长句查会返回空 —— **不能据此下「图谱是空的」这种负向结论**。本轮全部用短关键词查。
