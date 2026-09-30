# rdd 存放处新增的快捷方式（2026-09-30）

放在 **`E:\restart developing doer\rdd-selfcompile\`** 根目录，双击就能用。

## 桌宠小人

| 文件 | 干什么 |
|---|---|
| **`stager-pet.bat`** | **起桌宠**。已经在跑就报「已在运行，不重复启动」，**不会叠出两只** |
| **`stop-stager-pet.bat`** | 关桌宠 |

配套实现：`E:\restart developing doer\stager\pet\pet-launch.ps1`

```
点它   = 看阶段 / 轮次 / 轮回 / 人次 / 门禁
拖它   = 换位置（记在 pet\pet-pos.json）
右键   = 换图 / 按表情指定图片 / 打开 stage 目录 / 退出
托盘   = 也有一份菜单
```

## 网页看板

| 文件 | 干什么 |
|---|---|
| **`stager-dashboard.bat`** | 起看板 http://127.0.0.1:8899/ 并自动开浏览器。已在跑就直接开浏览器，不重复起 |
| **`stop-stager-web.bat`** | 关看板 |

## 退出码有意义

| 码 | 意思 |
|---|---|
| 0 | 成功（已启动 / 本来就在跑 / 已关掉） |
| 1 | 失败（脚本不见了 / 起不来 / 端口还有人占着） |

---

## 踩了三个坑（下次别重踩）

### 1 · `.bat` 里绝对不能有中文

第一版 .bat 里写了中文 `echo 看板已在运行，直接开浏览器`，结果：

```
'灏辩洿鎺ュ紑娴忎祻鍣' is not recognized as an internal or external command
'tart' is not recognized          <- start 的 s 被吃了
'et' is not recognized            <- set 的 s 被吃了
```

**真因**：cmd.exe 用旧代码页（GBK）算字节偏移，`chcp 65001` 只影响输出不影响它的文件指针。
碰到多字节字符后**指针和行首错位**，之后每一行的首字符都被吃掉。
`chcp 65001` 在第 2 行也救不了。

**对策**：`.bat` **全 ASCII**，中文全搬到 `.ps1` 里（PS 5.1 对 UTF-8 处理正常）。
现有的 `stager\stager.bat` 和 `启动桌宠.bat` 也有这个隐患，只是报错行恰好是无害的 echo。

### 2 · `Start-Process -ArgumentList` 不给含空格的路径加引号

```powershell
# 错的 —— 桌宠静默起不来
Start-Process powershell.exe -ArgumentList @('-File', 'E:\restart developing doer\stager\pet\start-pet.ps1')
#                                    从 "restart" 那里就断了 ↓
```

**对策**：自己拼整条命令行并手工加引号：
```powershell
$argLine = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Size {1}' -f $PetScript, $Size
Start-Process -FilePath $psExe -ArgumentList $argLine
```

### 3 · `.ps1` 必须 UTF-8 BOM

新建 `pet-launch.ps1` 时没加 BOM，PS 5.1 按 ANSI 读 →
```
'[OK] 桌宠已关。' 位置有语法错：Array index expression is missing
The string is missing the terminator
```
**对策**：写完立刻加 BOM（`stager\bin\fix-ps1-bom.js` 就是干这个的）。
这跟 handoff 里早就记的「PS 5.1 按 ANSI 读无 BOM 的 UTF-8」是同一条。

---

## 顺带查清的一件事

`stager web` 会**派生子进程**：

```
node bin\stager.js web  (pid 21040)
  └─ node pet\server.js 8899   (pid 21560)  ← 真正占 8899 的
```

第一版 stop 脚本只杀 21560，我以为会留孤儿 21040。
**实测杀掉子进程后父进程会自己退**（`execFileSync` 抛异常 → `CMD.web` catch 掉 → 进程结束），
所以只扫端口就够，不用杀进程树。已验证零残留。
