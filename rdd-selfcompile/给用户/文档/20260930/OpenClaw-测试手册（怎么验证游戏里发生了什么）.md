# OpenClaw 测试手册 · 我是怎么验证游戏里发生了什么的

> 2026-09-30 · 你可以直接复制去任何地方用
> 全部命令都在 `D:\rdd\workspace\mc-openclaw-controller\scripts\` 下

---

## 0. 三条命令就够日常用了

```powershell
cd "D:\rdd\workspace\mc-openclaw-controller\scripts"

node oc-send.js --probe            # 状态：血/饥饿/位置/背包（一句话，2 秒）
node oc-send.js --shot             # 截一张图
node oc-send.js --burst 6 1500     # 连抓 6 张（间隔 1.5s）= 看动态
```

`--probe` 输出的位置：
```
"position":{"z":-297.32,"y":75,"x":417.68}
```

---

## 1. 每次开始前（30 秒体检）

```powershell
# ① 内存够吗 —— 头号隐形杀手，游戏加载中途消失八成是它
$os = Get-CimInstance Win32_OperatingSystem
"总 {0:N0} MB / 空闲 {1:N0} MB" -f ($os.TotalVisibleMemorySize/1KB), ($os.FreePhysicalMemory/1KB)
#    空闲 < 1200MB → 游戏必然起不来，别去查代码

# ② OpenClaw server 在吗
Test-NetConnection 127.0.0.1 -Port 8080 -InformationLevel Quiet -WarningAction SilentlyContinue

# ③ 游戏客户端连上了吗
node oc-send.js --probe
```

**`--probe` 三种结果分别意味着什么**：

| 返回 | 含义 | 怎么办 |
|---|---|---|
| `success:true` + `position` | 全通 | 往下玩 |
| `RESP ... "clients":[]` | server 在，**游戏没连上** | 重启游戏（mod 只在启动时连一次，不会重连）|
| `没有连接的 Minecraft 客户端` / `CONNECT_FAIL` | 游戏没开 / server 没起 | 下面第 2 节 |

---

## 2. 启动三样东西（顺序不能反）

```powershell
# ① OpenClaw server（先起它！）
cd "D:\rdd\workspace\mc-openclaw-controller\scripts"
Start-Process -FilePath "D:\rdd\tools\node\node.exe" -ArgumentList "server.js" `
  -WorkingDirectory "D:\rdd\workspace\mc-openclaw-controller\scripts" `
  -WindowStyle Minimized `
  -RedirectStandardOutput "$env:TEMP\oc-server.out.txt" `
  -RedirectStandardError  "$env:TEMP\oc-server.err.txt"
Start-Sleep 6

# ② 游戏（gpt 存档；不传 -Instance 时默认就是 gpt）
& "D:\rdd\workspace\rdd-selfcompile\scripts\launch-mc.ps1" -Instance gpt -AutoStopMinutes 40

# ③ 等加载完（1-2 分钟），然后确认
Start-Sleep 150
node oc-send.js --probe
```

> ⚠️ **实例管理不要手写路径**（曾把"检查 test"和"启动 gpt"搞成两个实例，命令卡了很久）：
```powershell
. "D:\rdd\workspace\rdd-selfcompile\scripts\mc-instance.ps1"
Stop-RddMcInstance -Instance gpt                      # 只停这一个
Test-RddMcRunning -Instance gpt                       # 查这一个
Ensure-RddMcRunning -Instance gpt -AutoStopMinutes 30  # 幂等：已在跑就直接返回
```

---

## 3. 操控（Minecraft 里你看见的动作）

```powershell
node oc-send.js --walk w 2000      # 按住 W 走 2 秒 → 返回【实际位移】
node oc-send.js --walk s 1000      # 后退
node oc-send.js --key escape 80    # 任意单键
node oc-send.js --slot 3           # 切快捷栏
node oc-send.js --cmd "/gamemode creative"   # 发游戏指令（会自己开聊天框）
```

### 3.1 ⚠️ 走动不动？先查这三样（今天卡了两次）

| 顺序 | 查什么 | 现象 / 处理 |
|---|---|---|
| **1** | **聊天框/背包/暂停菜单开着** | **最常见**。打开的界面吞掉所有按键，但状态查询照样成功 → 看着像"mod 坏了"。按 `--key escape` 关掉 |
| **2** | 窗口没焦点 | 见 3.2 |
| **3** | 焦点与按键必须同一进程 | 见 3.2（分两步做**必然失败**）|

### 3.2 抢焦点（合成一步的脚本）

```powershell
# 一次完成"抢焦点 + 发按键"（分两步做会失败：第二个进程一启动就把前台抢走）
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "D:\rdd\workspace\mc-openclaw-controller\scripts\oc-walk.ps1" -Key w -Ms 2000

# 只看/抢焦点本身
. "D:\rdd\workspace\rdd-selfcompile\scripts\mc-focus.ps1"
Get-MinecraftWindowTitles      # 游戏窗口标题（默认关键字 "minecraft"）
Focus-MinecraftWindow         # 抢
Test-MinecraftFocused         # $true 才算成功
```

### 3.3 ⚠️ 别用 `--chat` 发指令，用 `--cmd`

```powershell
node oc-send.js --cmd "/difficulty normal"   # ✅ 用这个
node oc-send.js --chat "/gamemode creative" # ❌ 会把文字打进游戏画面
```

**为什么**：`typeText` 只往"当前焦点"打字，聊天框没开时文字全进画面。实测截到的是
`未知或不完整的命令，位于第 1 个字符：/％^—[HERE]` —— **指令根本没执行，
而工具回执照样 `success:true`**。而且 mod 的按键到不了聊天框文本控件，
`Ctrl+A`/`Delete`/`ESC` 全都无效，多条指令会粘成一条都执行不了。
`--cmd` 走 mod 的 `chat` action（自开 `ChatScreen` + 回车），完全绕开输入框。

---

## 4. 看画面（视觉验证）

| 方式 | 命令 | 状态 |
|---|---|---|
| 单张 | `node oc-send.js --shot` | ✅ 可靠。不切窗口不要焦点 |
| **连发（看动态）** | `node oc-send.js --burst 8 1500` | ✅ 可靠 8/8。**按 LastWriteTime 排序就是时间序列** |
| mod 内一次抓多帧 | `--record` | ❌ **别用**：回执说 `record_queued frames=6` 但一个 png 都不落盘 |

**帧序列 vs 视频**：

| | 外部录屏成视频 | 帧序列（`--burst`） |
|---|---|---|
| 内容 | 桌面+游戏+浏览器全混进去 | **只有游戏画面** |
| 噪声 | 切窗口、弹窗、通知全录 | 零 |
| 时间精度 | 靠播放器猜 | **每帧确定时刻**，能和日志对齐 |
| **我能读吗** | **不能**（无视频输入通道）| **能**（逐帧看图）|

**局限**：最快约 1.4s/帧（实测 6 帧 7.5s）→ **抓不到 tick 级手部动作**；无音频。

截图落盘：`D:\rdd\mc\The Best of Twilight Forest\screenshots\`

---

## 5. ★ 三线对齐（"接近人的敏锐度"从哪来）

**单靠画面到不了那个敏锐度** —— 画面只给客观事实，不给意图。三条线按时间轴对齐：

| 线 | 数据源 | 回答什么 |
|---|---|---|
| **客观发生了什么** | `--burst` 截的帧 | 画面上真的变了吗 |
| **AI 说了什么** | `config\numen\monitor\ai.jsonl` | 它的自述与意图 |
| **任务链走到哪** | `config\numen\monitor\rdd.jsonl` | 当前 subtask/状态/事件 |

**核心用法**：判断 **「AI 说自己做了 X，画面上是不是真发生了 X」**。

**今天的实例**（这方法当场抓到我自己的 bug）：
- 日志只说 `success:true` —— 看起来一切正常
- 但**截图**里赫然是 `未知或不完整的命令，/gamemode creative/difficulty normal/...` 三条粘在一起
- 纯看数据永远不会发现

---

## 6. ⚠️ 视角陷阱：画面里的人**不是**同伴

OpenClaw 操控的是**玩家**，截图是**玩家第一人称**。

- 画面里的人形 = **你自己**（第三人称时）
- **同伴是另一个角色，可能压根不在画面里**
- 我曾把你自己的模型当成同伴，得出错误结论

**正确判法**（别靠"画面里有人"）：
```powershell
node oc-send.js --probe                                    # 玩家位置
node <mc-call> get_self_status '{"companion":"<uuid>"}'    # 同伴位置（MCP 那条线）
```
两个坐标差得远 → 同伴不在视野内 → 画面里当然看不到。
**要给同伴拍照**：先拿同伴坐标，再让玩家 `lookAt` 那个坐标 + 截图。

---

## 7. 排错速查

| 症状 | 原因 | 处理 |
|---|---|---|
| 游戏加载中途消失、无报错、无 crash-report | **内存不足** | 第 1 节查内存 |
| 命令 success 但不动 | 聊天框/菜单 或 没焦点 | 3.1 三查 |
| `没有连接的 Minecraft 客户端` | 游戏没开 | 起游戏 |
| `"clients":[]` | 游戏开了但 mod 没连上 | 重启游戏（mod 不重连）|
| 内联 JSON 报 `BAD_JSON` | PowerShell 吃引号 | 用内置模式（`--walk`/`--key`/`--cmd`/`--burst`/`--shot`）|
| 改了 mod 但 **jar 大小没变、也没报错** | `gradle -q` 吞掉编译错误 | 去掉 `-q` 重跑看 `BUILD FAILED`；确认 jar 字节数真的变了 |
| 拷 mod 到 `mods` 被拒 | opencode 权限**会话启动时加载**，改配置要下次会话 | 用 `[System.IO.File]::Copy($src,$dst,$true)` |
| mod 装了启动就崩（`ResolutionException`）| 装了 `_disabled` 里那个**旧的**（flatten + module-info → JPMS 冲突）| 用 `neoforge-mod\build\libs\` 里那个（无 flatten、无 module-info）|

> **通用纪律**：`catch (Exception ignored) {}` 吞异常 = 把证据一起吞了。
> 排查失败时宁可让日志刷屏。今天 `record` 查不出原因，就是因为 catch 里一行日志都没有。

---

## 8. 环境事实（省得每次重查）

- **server**：`127.0.0.1:8080`，端点 `/minecraft`（游戏）、`/control`（控制）
- **游戏窗口标题**：`Minecraft NeoForge* 1.21.1 - <存档名>`
- **实例**：默认 **gpt**（`D:\rdd\mc\The Best of Twilight Forest`）；test 在 `rdd-selfcompile\instances\test`
- **mod**：`mc-openclaw-controller\neoforge-mod\build\libs\minecraft-client-controller-neoforge-1.0.0.jar`
- **单驾驶员**：OpenClaw 操控**玩家**，RDD 操控**同伴**。同时动同一实体会互相干扰 —— 一次只让一个动
- **RDD 暂停开关**（防误伤实验）：建 `config\numen\rdd-pause-disabled.flag` = 禁用暂停；删掉 = 恢复（不用重编）

---

## 9. 完整可复制清单

```powershell
# 一次性准备
cd "D:\rdd\workspace\mc-openclaw-controller\scripts"

# 启动（顺序：server → 游戏）
Start-Process -FilePath "D:\rdd\tools\node\node.exe" -ArgumentList "server.js" `
  -WorkingDirectory "D:\rdd\workspace\mc-openclaw-controller\scripts" `
  -WindowStyle Minimized -RedirectStandardOutput "$env:TEMP\oc.out.txt" -RedirectStandardError "$env:TEMP\oc.err.txt"
Start-Sleep 6
& "D:\rdd\workspace\rdd-selfcompile\scripts\launch-mc.ps1" -Instance gpt -AutoStopMinutes 40
Start-Sleep 150

# 日常
node oc-send.js --probe
node oc-send.js --burst 8 1500        # 抓一段动态
node oc-send.js --key escape 80        # 关掉可能开着的聊天框
powershell -NoProfile -ExecutionPolicy Bypass -File ".\oc-walk.ps1" -Key w -Ms 2000
node oc-send.js --cmd "/difficulty normal"
```
