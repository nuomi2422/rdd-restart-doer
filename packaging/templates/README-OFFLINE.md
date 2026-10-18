# numen-offline-bundle · 解压即编译（不联网）

> 由 `packaging\make-offline-bundle.ps1` 生成。源码 commit：`@@COMMIT@@`　生成时间：`@@DATE@@`

这个包把编译 Numen 需要的一切都带上了：**源码 + Gradle 缓存（含 Minecraft 反编译工件）+ 离线 Gradle 发行版 + 便携 JDK21**。
解压后 **不需要联网**，直接编译出 jar。

## 快速开始

```bat
build-offline.cmd clean assemble
```

产物在各模块 `build\libs\` 下，例如 `src\core\neoforge\build\libs\numen-neoforge-*.jar`。

只想验某一个模块：

```bat
build-offline.cmd :plugins:rdd:jar
build-offline.cmd :core:neoforge:build
```

## 目录

```text
build-offline.cmd            启动器（设好 GRADLE_USER_HOME / JAVA_HOME，跑 gradle --offline）
src\                         minecraft-numen 源码（不含 .git / build / runs）
gradle-home\                 GRADLE_USER_HOME 快照（caches\fabric-loom, neoformruntime, modules-2）
gradle-9.2.0\                离线 Gradle 发行版（不依赖 wrapper 下载）
jdk\jdk-21.0.11+10\          便携 JDK21
```

## 它为什么能离线

- `gradle-home\caches\neoformruntime\` 与 `fabric-loom\` 里已经有 **NeoForm / Fabric loom 处理 MC 的全部中间产物**，
  所以 moddev / loom 的「setup Minecraft」阶段**不会联网**。
- `gradle-home\caches\modules-2\` 里有全部 Maven 依赖（neoforge userdev、fabric-loader、junit、lwjgl…）。
- `gradle-home\gradle.properties` 里**没有代理**；`build-offline.cmd` 又把 HTTP 指到死端口 `127.0.0.1:1`，
  保证万一要联网也是**立刻显式失败**，不会静默挂起。

## 注意

- **不要把 `gradle-home` 指到别处**，也不要把本文件夹搬到另一个盘符后再指望 Gradle 复用本机别处的缓存 ——
  本包自带缓存，只需用它自己的 `gradle-home`。
- 首次运行会重跑部分 Gradle transform（约几分钟），之后第二次就快（up-to-date）。
- 想离线起 dev 客户端（`runClient`）还需资产缓存；本包默认**不含**，需要时用
  `make-offline-bundle.ps1 -IncludeRuntimeAssets` 重新生成。
- 判据：断网跑 `build-offline.cmd clean assemble` 退出码 0，且日志里
  `Downloading / Could not resolve / Failed to setup Minecraft / No cached version` 均为 0 次。
