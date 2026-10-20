# packaging · 离线编译包生成

把「源码 + 全部 Gradle 缓存（含 Minecraft 反编译工件）+ JDK + Gradle 发行版」打成一个包，
让别人（或清空缓存后的自己）解压后**不联网**就能 `gradle --offline` 编译出 jar，
跳过「先联网下载 MC 工件 / moddev / loom 缓存」这一步。

## 生成

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\make-offline-bundle.ps1
```

默认：staging 到 `D:\numen-offline-bundle`，压缩成 `D:\numen-offline-bundle.7z`。

| 参数 | 作用 |
|---|---|
| `-Staging <dir>` | staging 目录（默认 `D:\numen-offline-bundle`） |
| `-Archive <file>` | 输出 7z 路径 |
| `-IncludeRuntimeAssets` | 一并打 `caches\minecraft`（离线 `runClient` 用；不加则只够编译） |
| `-Skip7z` | 只 staging 不压缩 |

## 组成与体积（实测）

| 组成 | 源 | 体积 |
|---|---|---|
| `src\` | `minecraft-numen\`（去 .git/build/runs） | ~0.15 GB |
| `gradle-home\caches\neoformruntime` | `D:\rdd\.gradle\caches\neoformruntime` | ~1.37 GB |
| `gradle-home\caches\modules-2` | `D:\rdd\.gradle\caches\modules-2` | ~0.30 GB |
| `gradle-home\caches\fabric-loom` | `D:\rdd\.gradle\caches\fabric-loom` | ~0.25 GB |
| `gradle-9.2.0\` | 离线发行版 | ~0.14 GB |
| `jdk\jdk-21.0.11+10\` | 便携 JDK21 | ~0.32 GB |
| **合计** | | **~2.41 GB**（7z `-mx=1` 后 **2.05 GB**，8025 文件） |

> 2026-10-18 实测产物：`D:\numen-offline-bundle.7z`，SHA256 `A0F669838BEEA508877FF0E8B1063AE171CD84BBA59E7916FC44B890964060C0`。

## 恢复与验证

1. 解压到目标位置（**建议放在空间充裕的盘**）。
2. `build-offline.cmd clean assemble`（可断网）。
3. 判据：退出码 0；日志无 `Downloading / Could not resolve / Failed to setup Minecraft / No cached version`；
   第二次运行 20s 内 `BUILD SUCCESSFUL`（证明是 up-to-date，不是重新下载）。

## 设计要点（为什么这样切）

- **只带 `fabric-loom` / `neoformruntime` / `modules-2`**：前两者是「moddev / loom 处理 MC 的中间产物」，
  是离线 setup 的命门；`modules-2` 是所有 Maven 依赖。
- **丢掉 `caches\9.2.0` / `build-cache-1` / `daemon` / `workers`**：以绝对路径为键，跨机 100% miss，纯体积。
- **`gradle-home\gradle.properties` 重写为无代理**；`build-offline.cmd` 再把 HTTP 指到死端口，保证联网必显式失败。
- **`src\gradle.properties` 去掉 `org.gradle.java.home` 绝对路径**，改由 `build-offline.cmd` 的 `JAVA_HOME` 提供。
- **不带各模块 `build\`**：含绝对路径 + 旧 classpath 快照，会干扰 up-to-date 判定甚至造成「假成功」。

## 已知边界

- 缓存里的部分元数据（`modules-2\metadata-*`）可能带生成机的绝对路径；本包**实测在别的盘符/路径下离线编译通过**，
  但换机后第一次仍可能重跑部分 transform（功能不受影响）。
- 代理相关的可移植性改动集中在三处，见外层 `README.md` 第六节。
