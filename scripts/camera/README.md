# 固定窗口连续录制（PrintWindow 薄输入）

将 2026-11-17 已完成的长录工具纳入现有 workspace：两份生产脚本及三个自建测试均按冻结原字节迁入，不改行为、不接新服务、不安装依赖。保留原临时副本供当前 driver 使用；不替换 numencam 的游戏内 PNG 录制、机位或牵引控制。

## 入口与运行

- [long-record.cjs](<long-record.cjs>)：Node 编排固定 ffmpeg，libx264 / 4 Mbps / MPEG-TS 60 秒分段（synthetic 模式 4 秒）；PrintWindow 默认 8fps，支持 1–30fps、1–10800 秒。
- [printwindow-producer.ps1](<printwindow-producer.ps1>)：同目录相对 helper，Windows PowerShell 5.1 / System.Drawing / 内嵌 C#，UTF-8 BOM 必须保留。
- 依赖既有 `D:/rdd/tools/node/node.exe`（本次语法检查 v22.23.3）、`powershell.exe` 和 `D:/rdd/tools/ffmpeg/bin/ffmpeg.exe`；测试解码使用同目录 ffprobe。不启动 Minecraft、不切机位或焦点。

以下仅为用法；由唯一 driver 先设置其已确认的 `$targetPid`，不得模糊按标题搜索或借用旧 PID/HWND。长录应放受管后台 job，并收取最终输出；本次迁移未执行：

```powershell
$target = Get-Process -Id $targetPid -ErrorAction Stop
$hwnd = $target.MainWindowHandle.ToInt64().ToString()
$title = $target.MainWindowTitle
if ($hwnd -eq '0' -or -not $title) { throw 'No exact main window identity' }
$stop = Join-Path 'C:/rdd-footage' ('STOP-' + [guid]::NewGuid().ToString('N'))
& 'D:/rdd/tools/node/node.exe' 'D:/rdd/workspace/scripts/camera/long-record.cjs' --print-window --pid $targetPid --hwnd $hwnd --title $title --fps 8 --seconds 25 --output-root 'C:/rdd-footage' --stop-file $stop
```

提前停只创建 started 回执中的**精确绝对 stopFile**（不得覆盖预存 StopFile）；到时或收到 SIGINT/SIGTERM 同样请求 producer 停止并关闭 stdout → EOF → ffmpeg 封盘。PrintWindow 模式使用 `-nostdin`，**绝不向 raw BGRA 写 `q`**。保留的非 PrintWindow 分支是独立显式 legacy gdigrab / synthetic，不是失败 fallback；legacy 的 stdin `q` 仅留作兼容，不用于 MC。

## 安全与时间含义

- PrintWindow(flags=2) 只抓传入 HWND，每次采样前后校验 PID、精确 title、可见/非最小化及固定尺寸。失效、resize、minimize、hung 或网格全同 blank 拒绝后报失败并 EOF，不抓桌面、不换窗口、不抢前台。启动时 DWM 不可用才固定用 GetWindowRect；不切换采集源。
- 一个持久 producer 复用 Bitmap/Graphics/两块缓冲；stdout 仅 BGRA，stderr 诊断，经 Node 有界背压送 ffmpeg，无逐帧 PNG 落盘。无音轨（`-an`），不录系统声或麦克风。
- 初始预算沿原 4Mbps 估算 +15% +2GiB；PrintWindow 运行中每 250ms 核 2GiB 余量，低于余量请求 EOF 并标失败。
- **CFR 8fps ≠ 每秒 8 个新样本**。frames.csv 每输出帧保留媒体时间、真实 sample ID/UTC、capture/write 单调起止、held_previous、late_ms、SHA256 和 kind。慢捕获补前一真实样本，不插帧；首次迟到标 initial-backfill、尾部标 tail-hold。终态记录 frames / captureSamples / adjacent distinct/identical / held / late 与延迟。
- 正常媒体时长按采样墙钟向上取整至一帧；源失败只封已有有效内容。segments.csv 是 muxer 时间戳范围，8fps B 帧尾 end 可比 probe duration 多 0.250s，不当墙钟总长；时长及新鲜度应合看 frames.csv、producer-terminal.json、terminal.json 和 ffprobe/decode。Node 总 code 非零不能只凭 ffmpeg code=0 写通过。

## 自建复现与证据边界

仅三个测试源码：[owned-neutral.ps1](<printwindow-validation/owned-neutral.ps1>)、[validate.cjs](<printwindow-validation/validate.cjs>)、[verify.cjs](<printwindow-validation/verify.cjs>)。保持子目录布局后 `../long-record.cjs`、fixture helper 和固定 ffmpeg 路径无需适配。validate 只新建自己的无激活计数窗/遮挡窗并自然关闭，生成本地 suite-*；verify 全流解码，仅适用于该 640×360 计数器夹具，不是任意 MC 视频验收器。两者会写日志/结果且使用独占新日志名，不应重复 verify 同一套件。

```powershell
# 仅供以后有需要时复现；本次不运行、不起窗。
& 'D:/rdd/tools/node/node.exe' 'D:/rdd/workspace/scripts/camera/printwindow-validation/validate.cjs'
& 'D:/rdd/tools/node/node.exe' 'D:/rdd/workspace/scripts/camera/printwindow-validation/verify.cjs' '<suite-complete 回执中的 root>'
```

已有自建中性窗有限实测：25s 动态/遮挡、约5s StopFile、慢 paint 的 CFR held，以及 close/resize/minimize/blank 预期失败封盘；7 条全流 decode=0。原证仅留本地临时目录，视频、results、raw、凭据及配置备份不入库。迁移本身只查 Node 语法、PowerShell 解析、原字节 SHA256/BOM、相对路径及 Git diff，不重复套件、不启动 MC。

父会话交接称真 MC 曾录到约 722 秒；本次未亲验原片/运行原证，**不据此宣称安身立命完整通过、小时级稳定或原生 GPU 持续新鲜通过**。同步 PrintWindow 调用或编码背压永久挂起时，未引入强杀/watchdog，不能保证硬截止；blank 只是约 20×20 网格同色拒绝，并非智能黑屏识别。

冻结生产 SHA256（工作树及 Git blob 均应一致；[局部属性](<.gitattributes>) 防止 autocrlf 改脚本字节）：

- [long-record.cjs](<long-record.cjs>)：`cf187d2bea11cbf12332d0732df448d06178b1a6211fa992982a1434b06cdf9c`
- [printwindow-producer.ps1](<printwindow-producer.ps1>)（BOM）：`9cbb11bfc14d2c537d99534f52d91abb26cdb811d27f5d32e2bf32dcd643d6b3`
