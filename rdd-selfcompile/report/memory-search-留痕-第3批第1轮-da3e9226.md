# 经验库检索留痕 · 第3批第1轮（死因结构化）· 签名 `da3e9226`

> 时间 2026-10-01 10:47-10:55 ｜ 阶段 verify/close ｜ 人次 `stealth-space-bunny`
> 说明：本文件是 `06-检查清单`「过程中」第 ④ 项「经验库检索 —— 遇问题先 `search_nodes` 定向取经验」的落盘留痕。
> **只写不查 = 记了但没受益**，所以下面记录实际检索动作与结果。

---

## 1 · 实际检索动作

| # | query | 命中 | 判读 |
|---|---|---|---|
1 | `死因 death cause 经验 触发` | **0** | ⚠️ 以为图谱里没有死因相关经验 |
2 | `限流 token 上下文 窗口` | **0** | ⚠️ 以为图谱里没有上下文限流相关经验 |
3 | `死因 death cause 经验 触发`（重复确认） | **0** | 仍 0 |
4 | `flow-gate`（英文标识符） | **6 条** | ✅ 正常命中 |
5 | `read_graph`（全量） | **图谱很大**（输出被截断，落盘 `tool-output\tool_0f713d312001i7D18ggMDLRo27`，含大量 09-27~09-30 的实体） | 图谱**不是空的** |

## 2 · ★ 结论：不是「没记录」，是「搜不到」

`memory_search_nodes` 对**中文 query 返回空**，对**英文 / 标识符类 query 正常命中**。
前两次搜「死因」「限流」都归零，若就此收手，就会写下「经验库里没有相关经验」——
**而实际上图谱里有大量记录**（`read_graph` 一读就知道）。

**又一次「读取时没按正确方式」这族错误**（今天第 5 次：Gson 转义、JSON.parse 兜底、`injected` 字段名、
`启动器阻塞`、本次「中文 query 搜不到」）。

## 3 · 从图谱里捞到、且**真的影响了本轮判断**的经验

| 实体 | 对本轮的作用 |
|---|---|
`lesson/flow-gate-must-check-artifacts-not-docs` | 提醒我门禁只查盘上实物，不查「读没读过文档」→ 所以我去跑了三门机器门而不是自认为走过 |
`gate-that-passes-fake-success-is-worse-than-no-gate` | 提醒我**门禁自己会骗人**，误判的门禁会被忽略 → 所以我去看它的判据实现（`loop-gate.js:201-215, 257-267`）而不是盲目按提示改 |
`lesson/reflex-priority-registration-order-is-a-death-safety-surface` | ★ **高度相关**：反射注册号小的先问，改高优先级的 `canRun` 会压掉后面所有救命链（当年我把摔落自救的收水窗口从 20 刻拉到 200 刻，压掉了换气/窒息/岩浆/自卫约 10 秒，岩浆洞里足以致死）。→ **本轮我改的 `markDead` 顺序是同类风险**（动 `onDeath` 链上的语句顺序），所以我专门验了「顺序修没副作用」（A3：再调返回「她刚死了,正在复活途中」，链路正常） |
`pitfall/gate-nature-labels-must-not-reach-ai-context` | 提醒门禁输出的「性质标签」不该进 AI 上下文（等于给执行者一张「哪些能糊弄」的地图）→ 所以我复跑门禁时只取 `BLOCK/VERDICT/PASS=`，不看它的分级标签 |
`fact/other-ai-wpool-usage-20261001` | 记录了另一个窗口当天 0 次外脑 → **强化了我本轮「外脑必须真问」的判断**（我实际问了，4 家 3 有效 1 失效） |
`issue/in-game-llm-402-blocks-all-game-verification` | 「它不动」先查 401/402/5xx → 本轮我先确认游戏真起来了（java 进程 + latest.log 在写 + `<carry>` 在刷新）才动手 |

## 4 · 给下一个人的检索建议

1. **搜经验库用英文标识符 / 类名**，别用中文自然语言。已知命中良好的 key 样式：
   `flow-gate`、`negotiation`、`replan`、`companion`、模块名、类名片段。
2. 中文 query 返回空时**不要**直接下结论「没有这条经验」—— 先 `read_graph` 看规模，
   或换一个英文 token 再搜。
3. `read_graph` 输出会很大（本次被截断到 147KB+），别整读，用 `search_nodes` 精确命中，
   必要时委托 explore agent 处理落盘文件。

## 5 · 本轮结论

- **查了**（3 次中文全 0、1 次英文命中 6 条、1 次全量 read_graph 确认规模）
- **捞到了**（6 条，其中 `reflex-priority-registration-order` 直接影响了我对顺序修的风险评估）
- **落盘**（本文件）
- **顺带发现**：`memory_search_nodes` 中文检索失效，是一个待修的工具缺陷（暂未改 `memory.json` 或服务端逻辑，因不属于本轮范围）
