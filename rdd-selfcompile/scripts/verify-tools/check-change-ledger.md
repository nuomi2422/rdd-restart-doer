# `check-change-ledger.js` —— 台账可核（台账 vs git log）

> 用途：`rdd存放/改动台账-*.md` 里列的提交，和仓库里真实存在的提交**对不对得上**。
> 手写的表会腐化 —— 漏记一个提交、写错一个 sha，读的人就会以为「这份表是全的」。

## 怎么调

```powershell
# 1) 先导出（范围按台账口径自己定）
git -C D:\rdd\workspace\minecraft-numen log --since "2026-10-20 19:00" --pretty=format:%h > D:\rdd\workspace\.tmp\gitlog.txt

# 2) 比对
node verify-tools\check-change-ledger.js --log D:\rdd\workspace\.tmp\gitlog.txt

# 指定别的台账 / 机器可读 / 自测
node verify-tools\check-change-ledger.js --log ... --ledger <台账.md> --json
node verify-tools\check-change-ledger.js --selftest
```

退出码：`0` 一致 / `1` 有漏记或幻影 id / `2` 用法或环境错。

## 为什么不让工具自己调 git

本机沙箱下 node 的 `child_process` **捕获输出会 EPERM**（管道被禁）。所以这一步刻意拆成
「先导出 → 再比对」，工具本身只做纯文本处理 —— 也顺带让它可单测。

## 它抓什么

| 结果 | 含义 |
|---|---|
| `INCOMPLETE` | 仓库里有、台账**没记**（表不完整） |
| `PHANTOM` | 台账写了、仓库里**找不到**（写错 sha，或者编的） |
| `OK` | 覆盖一致 |

## 实跑记录（2026-10-21）

- 首次真跑：`INCOMPLETE` —— 漏了同日 19:00–22:30 的 **10 个提交**（G1c ~ G4a），已补进台账 §7；
- 同时报了一个 `PHANTOM`（`0547d7d`）—— 查出来是**工具自身的 bug**：PowerShell 的 `>` 写的是
  **UTF-16LE**，按 UTF-8 读会得到乱码 + 首行带 `\uFEFF`，于是第一行永远匹配不上。
  已修（`readTextSmart`：认 BOM 并剥掉）；
- 修完后：**覆盖 30/30，`VERDICT=OK`**。

> 这两次都是「工具第一次真跑就抓到真问题」的典型：一次是台账缺内容，一次是工具自己读错编码。
> 所以每个 verify-tool 都带 `--selftest`，但也**必须**对真实数据跑一次 —— 自测用不到编码这条路径。
