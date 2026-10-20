# ▶ STAGER.md · AI 开工第一件事（读完这段你就知道怎么干了）

> 这个文件是给 **AI** 看的，不是给人看的。人看的去 `README.md`。
> 装法：`stager install`（已装的话，opencode 每次会话会自动把 `ctx` 注入进来）。

---

## 0 · 你现在的处境

**先跑这一条，别猜：**

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" ctx
```

三种结果，三种反应：

| `ctx` 的输出 | 说明 | 你该做什么 |
|---|---|---|
| 有内容（有 `## ▶ STAGER` 表） | 有人在干活，你接了活 | **照第 2 节做**，别问用户"要做什么" |
| `STAGER-ERR 没有进行中的任务` | 现在没活 | 干用户直接交代的事就行；用户说的是"做/改/加"这种正经开发活 → 先 `stager start "<标题>"` 开档 |
| 其他报错 | 状态机坏了 | 念给用户，别自己脑补绕过 |

如果 opencode 装了插件，上面这段 `ctx` 会被**自动注入**在你的上下文里（表头是 `## ▶ STAGER 阶段管理器 · 上下文注入`）。
看到那张表 = 有活，按表干；看不到 = 没活，正常响应用户。

---

## 1 · 换人次（你换了模型/新开会话/人接手）

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" swap "<你的名字>"
node "D:\rdd\workspace\stager\bin\stager.js" ctx --full
```

- `swap` 记一笔"谁接的哪一步"，不查出身，谁都能接。
- `ctx --full` 把**前面所有阶段产出的文档全文**注入给你 —— 换人后不靠记忆靠注入。
- 名字建议写成 `模型/角色`，比如 `opencode/gpt-6-astra`、`codex`、`glm-web`、`kimi-web`、`claude`。

---

## 2 · 干当前阶段的活

`ctx` 里有一段 **「你现在这个阶段要做的事」**，那就是你本轮的全部任务。别多做，别少做。

通用四步：

1. **读** —— `ctx`（已注入就别重复跑）→ 上一阶段的文档已经在里面
2. **做** —— 严格按阶段要求产出
3. **存** —— 产出的文档必须存进 stage：
   ```powershell
   node "...stager.js" put "<文件路径>" --kind plan --title "计划书 v1"
   ```
4. **推进** —— `next`（门禁没过会拒你，按它给的命令补）

**阶段与文档类型对照**（`--kind` 只能用这些）：

| 阶段 | 门禁要求 | 动作 |
|---|---|---|
| 🗺️ 计划统筹 `plan` | --kind plan  +  --kind arch | 目标分流 → 写计划（GPT-6 默认不用，只在大批量/超长任务开头用一次抓方向）→ W 池互审 → 冻结「最终架构文档」 |
| ⚙️ 编码实现 `implement` | mark implement | 按最终架构文档写码 |
| 🧪 游戏验证 `verify` | --kind evidence | 拿证据说话 |
| 🎉 记录收口 `close` | --kind experience  +  mark check | 记录经验 → 查门禁 → 判定收工还是回炉 |

---

## 3 · 轮回（轮次）

- 撞到 `iterate` 再 `next` → **自动回到 `plan` 并 +1 轮**（这叫"轮回"），并且**上一轮的标记全部作废**
- 轮次到上限（默认 5）会被拦；真要超：`stager round --force --note "为什么超"`
- 只是想重排计划、轮次不变：`stager loop`（也回 `plan`）
- **别手动跳阶段**。要跳只能 `enter <stageId> --force --note "为什么"`（不 force 会被拦）

---

## 4 · 收工 = 关档

```powershell
node "...stager.js" mark check --note "契约 7 条全过"
node "...stager.js" close --status done --note "一句话结论"
```

**关档有底线**：本轮必须有 `contract` 和 `evidence` 两份文档，否则 `close` 拒绝
（防"跳到复审阶段打个标记就零证据关工"）。真要跳：`--force --note "为什么"`。

关档后这个 stage 不再接受任何改动（`status`/`ctx`/`docs` 仍可读）。
想接着改归档里的东西：`stager resume <id> --force --note "为什么"`。

---

## 5 · 硬规矩（这几条是 stager 存在的理由，别绕过）

1. **不许跳阶段**：门禁没过 `next` 会拒绝；往前跳 `enter` 也要 `--force` + `--note` 留痕。
2. **不许靠记忆跨阶段**：每阶段开工先 `ctx`，尤其换人之后必须 `ctx --full`。
3. **不许不落文档就推进**：阶段产出的东西必须在 `docs/` 里（`put`），否则换人就断片。
4. **不许无证据说完成**：验证阶段的 `evidence` 文档要有命令 + 关键输出 + 时间戳。
5. **不许零证据关档**：本轮没有 `contract` + `evidence` 文档，`close --status done` 会拒。
6. **不许手改状态**：`.stager/**/state.json` 是机器写出来的，你手改它下次 `next` 就对不上了。
7. **不许关档了还说"在跑"**：`close` 是终点，关完就停，别继续在旧 stage 上加活。

> 多 AI 同时干同一个 stage 是允许的（每次改动都在文件锁里重读状态，不会互相覆盖）。
> 但**别让两个 AI 同时改同一个阶段**——`swap` 一次只算一个人。

---

## 6 · 全部命令

```powershell
node "D:\rdd\workspace\stager\bin\stager.js" help
```

（也可以把 `stager\bin` 加进 PATH，然后 `stager ctx` / `stager.cmd ctx`。）

阶段定义改 `D:\rdd\workspace\stager\core\stages.json`，改完立刻生效（不用改代码）。
