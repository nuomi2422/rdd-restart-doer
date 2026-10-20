# stager · 编程流程阶段管理器

> 给一堆 AI 用的"流程监工"。它记三件事：**现在在第几阶段、第几轮、谁在干活**。
> AI 每次开工先读它一眼就自动知道自己该干什么；干完打标记推进；做完了关档。
> 桌面上还蹲一只小宠物，点一下就报进度。

```
stager start "<需求标题>"      ← 开档（自动进第1轮第1阶段）
stager ctx                     ← ★ AI 每次开工先跑这个（注入包）
   ...干当前阶段的活...
stager put "<文件>" --kind plan ← 产出存进 stage
stager next                    ← 推进（门禁没过会拒绝）
   ...撞到复审阶段就自动 +1 轮回计划...
stager close --status done      ← 关档
```

---

## 1 · 装 / 跑

```powershell
$env:ST = "D:\rdd\workspace\stager"

# 看全部命令
node "$env:ST\bin\stager.js" help

# 让 AI 每次会话自动知道自己在哪
node "$env:ST\bin\stager.js" install
#   → 往 ~/.config/opencode/opencode.json 的 plugin 加一条（备份 .stager-bak）
#   → 在当前工作区 AGENTS.md 追加一段指针
# 重启 opencode 后生效

# 装完卸掉
node "$env:ST\bin\stager.js" uninstall
```

嫌路径长：把 `D:\rdd\workspace\stager\bin` 加进 PATH，之后直接
`stager ctx`（PowerShell 里是 `stager.cmd ctx`），或者 `& "$env:ST\bin\stager.ps1" ctx`。

---

## 2 · 阶段流水线

| # | 阶段 | id | 门禁（不达标不许走） | 表情 |
|---|---|---|---|---|
| 1 | 📥 需求接入 | `intake` | 1 份 `requirement` 文档 | 招手 |
| 2 | 🗺️ 计划拆解 | `plan` | 1 份 `plan` 文档 | 疑惑 |
| 3 | 🔍 外脑审核 | `review` | 1 份 `review` 文档 | 生气 |
| 4 | 📜 契约定稿 | `contract` | 1 份 `contract` 文档 | 无语 |
| 5 | ⚙️ 编码实现 | `implement` | `stager implement` 标记 | 平静 |
| 6 | 🧪 验证取证 | `verify` | 1 份 `evidence` 文档 | 惊讶 |
| 7 | 🔁 复审回归 | `iterate` | `stager mark check` 标记 | 大哭 |

`iterate` 走 `next` → **自动回到 `plan` 并 +1 轮**（这就是"轮回"）。
全过就 `stager close --status done` 关档。

**改流程**：编辑 `core\stages.json`，加阶段、改门禁、改名字都成，改完立刻生效。

---

## 3 · 轮次 / 轮回

| 概念 | 含义 | 命令 |
|---|---|---|
| 轮次 round | 第几遍完整流水线，1..maxRounds（默认 5） | `stager round` 手动 +1 |
| 轮回 wrap | 一共回环过几次（`iterate` 每过一次 +1） | 看 `stager status` |
| 内循环 loop | 轮次不变，回 `plan` 重排 | `stager loop` |

- 轮回回到 **`plan`**（`core/stages.json` 的 `loopTo`），不是从头 —— 需求一般不用重写
- 新一轮会**清空上一轮的所有 `marks`**（避免拿上一轮的"已实现/已检查"混过新计划）
- 到 `maxRounds` 后还想轮回会被拦，必须 `stager round --force --note "为什么超"`

---

## 4 · 换人次（谁都能接）

```powershell
stager swap "codex"              # 记一笔：codex 接了当前阶段
stager ctx --full                # 把历史文档全文注入给接手的人
```

- 不查出身，任何人/任何模型都能接任何阶段。
- 每次换手都进 `history.jsonl` 和 `progress.md`，事后查得到。
- 建议名字写成 `模型/角色`：`opencode/gpt-6-astra`、`codex`、`glm-web`、`kimi-web`。

---

## 5 · 文档都放在哪

```
.stager/
├── active.json                      ← 当前是哪个任务
└── tasks/
    └── 20260929-233000-你的标题/
        ├── state.json               ← 唯一真身：阶段/轮次/人次/状态
        ├── history.jsonl            ← append-only 事件流水
        ├── progress.md              ← 人看的进度看板（自动刷）
        └── docs/
            ├── manifest.json        ← 文档登记表（类型/阶段/轮/人次）
            ├── 01-xxx.md            ← 需求书
            ├── 02-xxx.md            ← 计划书
            └── ...
```

文档类型（`--kind`）：`requirement` `plan` `review` `contract` `evidence` `log` `note`

`stager ctx` 注入包会**把文档正文带进 AI 上下文**（默认每份截 3000 字，
`--full` 给全文），所以换人不用重新读一遍历史。

---

## 6 · 桌面宠物 🐾

```powershell
stager pet                  # 起桌宠（默认 200px）
stager pet --size 260       # 换大小
```

- 阶段变了**自动换表情图**
- **点一下**弹气泡：阶段 / 第几轮 / 轮回几次 / 人次 / 门禁还差什么
- **拖动**换位置（记在 `pet\pet-pos.json`）
- **右键**：报状态 / 刷新 / 随机换图 / 按表情指定图片 / 打开 stage 目录 / 退出
- 系统托盘也有一份菜单
- 没放图时会画个占位小团子，不白屏

**放图**：把你那 9 张丢进 `pet\images\`，命名见
[`pet\images\README.md`](pet/images/README.md)。放完右键刷新。

---

## 7 · 网页看板

```powershell
stager web --port 8899       # http://127.0.0.1:8899/
```

宠物大图 + 阶段进度条 + 文档清单，1.5s 自动刷新。看板**只读**（改状态用 CLI，
免得浏览器误点把状态搞乱）。手机连同网段也能看。

---

## 8 · 门禁是真的会拦

```powershell
stager next
# STAGER-ERR 门禁没过，不许离开「计划拆解」
#   还差：doc:plan
#   补齐：  stager put <文件> --kind plan --stage plan
#   确实要跳：stager next --force --note "为什么跳"
```

`--force` 能跳，但会连理由一起进 `history.jsonl`，事后翻得到。

三条额外的硬底线（都是评审逼出来的）：

| 底线 | 拦什么 | 绕过 |
|---|---|---|
| 门禁认正文文件 | 文档登记在 manifest 但正文被删 → 仍算缺 | 重新 `put` |
| 往前跳阶段要理由 | `stager enter <后段阶段>` 被拦 | `--force --note` |
| 收工要有证据 | 本轮缺 `contract` 或 `evidence` → `close --status done` 拒 | `--force --note` |
| 关档即冻结 | 已关档的任务拒绝一切改动 | `resume <id> --force --note` |

---

## 9 · 自测

```powershell
stager self-test     # 状态机 31 项（临时目录跑完整链，跑完即删）
stager conc-test     # 并发压测：8 进程抢锁，验丢更新 / 残锁
```

`conc-test` 是真开 8 个子进程同时 `swap` / `mark` / `next`，然后数
`actorLog` 和 `marks` 有没有丢条目、`stage` 有没有被偷推进、`.lock` 有没有残留。
改完 `stager.js` 两个都跑。

---

## 12 · 已知的坑（自己踩过的）

| 坑 | 症状 | 结论 |
|---|---|---|
| PowerShell 5.1 按 ANSI 读无 BOM 的 UTF-8 | 中文全变乱码 + 语法错 | `.ps1` 必须写 UTF-8 **BOM** |
| WPF `Topmost=True` 会被全屏窗口压下去 | 桌宠钻进终端后面 | 每 2 秒 `SetWindowPos(HWND_TOPMOST)` 重新顶 |
| `@($null)` 是一个含 null 的数组 | 门禁凭空多出「缺  标记」 | 遍历前先 `Where-Object { $_ }` |
| `SizeToContent` + 固定 Width 冲突 | 气泡被窗口窄度卡住，文字换行改变宠物位置 | 用 `SizeToContent`，宠物 `HorizontalAlignment=Right` |
| `x:Name` 写成 `x:Name` / 和参数重名 | XAML 加载失败 / 参数被覆盖 | 元素名别撞参数名（`$Bubble` → `$ShowBubble`） |
| `System.Windows.Media.Brushes::FromArgb` | MethodNotFound | 用 `SolidColorBrush` + `Media.Color::FromRgb` |

---

## 10 · 目录

```
stager/
├── STAGER.md              ← 给 AI 看的（install 后进每会话上下文）
├── README.md              ← 你在读的
├── stager.bat             ← 双击进控制台（doskey 好了 stager 一句话）
├── 启动桌宠.bat            ← 双击起桌宠
├── bin/
│   ├── stager.js          ← 全部逻辑（单文件，零依赖）
│   ├── conc-test.js       ← 并发压测
│   ├── stager.cmd         ← cmd 包装
│   └── stager.ps1         ← PowerShell 包装
├── core/
│   └── stages.json        ← ★ 阶段定义（改流程改这里）
├── opencode-plugin/
│   └── stager-plugin.mjs  ← opencode 插件，每轮自动注入 ctx
├── pet/
│   ├── start-pet.ps1      ← WPF 桌宠
│   ├── server.js          ← 网页看板后端
│   ├── index.html         ← 网页看板前端
│   ├── images/            ← ★ 放 9 张表情图
│   └── pet-pos.json       ← 桌宠位置/换图偏好（自动生成）
└── .stager/               ← 运行时状态（自动生成，别手改）
```

---

## 11 · 和现有那套的关系

stager 是**通用流程层**，不绑定 Numen / MC。它管"阶段-轮次-人次-文档-门禁"，
具体每阶段干什么由 AI 读 `STAGER.md` + `core\stages.json` 决定。

要接到 RDD 那套上，把 `core\stages.json` 的阶段换成
`loop-gate.js` / `flow-gate.js` 的门禁内容即可 —— 门禁本来就是"这个阶段要产出什么"，
不是"跑哪个脚本"。
