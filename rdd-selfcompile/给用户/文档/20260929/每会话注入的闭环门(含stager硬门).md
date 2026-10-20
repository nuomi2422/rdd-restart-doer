# 闭环门（opencode 每次会话自动注入 · 2026-09-29）

> 本文件由 `opencode.json` 的 `instructions` 注入，**每个会话都在系统提示里**。
> 目的：让"走自编译闭环"变成**默认动作**，而不是靠 AI 记得读文档。

## ① 第 0 件事：开 stage（不许跳过）

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" start "<用户原话目标>" --actor "<你的名字>"
node "D:\rdd\workspace\stager\bin\stager.js" ctx     # 阶段 + 必读 md + 最终架构文档 + 门禁
```

**没开 stage 就动手 = 这一轮作废。** 4 阶段流水线：

```
① 计划统筹 → ② 编码实现 → ③ 游戏验证 → ④ 记录收口
     ↑                                              │
     └──── 有洞：stager next 自动回①并 +1 轮 ────────┘
           全过：stager close --status done → 关档
```

门禁不达标 `stager next` 会拒绝；换人接手 `stager swap <你>` + `stager ctx --full`。
细则：`D:\rdd\workspace\stager\STAGER.md`

## ② 要改代码 / 要进游戏 → 入口只有一个

```powershell
& "D:\rdd\workspace\rdd-selfcompile\scripts\run-mutation.ps1" -Requirement "<需求>" -Module <模块>
```
- **禁止**手写 gradle 构建 jar、禁止手动 `Copy-Item` 到 mods（已被 permission 拦）。
- 单轮闭环全自动：`new-mutation → gen-code → build-jar → deploy → verify → verdict.json`
- 止损循环：`-MaxAttempts N`；只编译不跑游戏：`-SkipLaunch -SkipMcp`
- ⚠️ 改**执行层**（`core/common` 的类）时 `build-jar` 默认模块覆盖不到，
  必须 `:core:neoforge:jar` 并在 `phase-build.json` 写明 `moduleOverride`（留痕，不是绕过）。

## ③ 收工前 → 三个机器门都要过

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" check     # 阶段门禁
node "D:\rdd\workspace\rdd-selfcompile\scripts\loop-gate.js" --since <今天> --keyword <模块> --head <本轮HEAD>
node "D:\rdd\workspace\rdd-selfcompile\scripts\flow-gate.js" --since <今天> --active <开工时的 store active>
```
- 输出 `VERDICT=NOT_DONE` → **不许收工、不许上报完成**，回去补。
- `VERDICT=FLOW_COMPLETE` 才算"走完流程"（那是**盘上实物**说的，不是 AI 自述）。
- 完成动作顺序：`stager close --status done` → 关游戏 → 推远端 → 报证据 → 汇总给用户。

## ④ 模式（三种，不是两种）

| 模式 | 什么时候 | 规矩 |
|---|---|---|
| **人工(1)** | 用户在场 | MC ≤10 分钟/次 |
| **自动(2)** | **用户不说话（默认）** | 默认走这个 |
| **离线(2)** | 用户不在线 | 同上 + 必须开 `every-10min-drive.ps1 -Loop -IntervalSec 600` |

**开游戏默认 2 小时**（`launch-mc.ps1 -AutoStopMinutes 120`）。自动关只是为了防 API 烧光，**不是门禁** —— 关掉还没验完可以重新起。

## ⑤ 每 3 轮 · GLM 源码审

第 3/6/9 轮 `stager ctx` 会自动提醒。把本轮**所有源码改动**粘给 GLM 审一遍（直接粘文本）。

## 接手先看

`D:\rdd\extras\rdd架构\self-compile-handoff.md`（当前状态/红线锚点/待办与未验证/踩坑清单）

