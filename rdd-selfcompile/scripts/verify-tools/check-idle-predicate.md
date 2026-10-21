# `check-idle-predicate.js` —— H1：「身体空闲」判断只许有一处

> 用途：`G3e-2-批次卡.md` §3 的 **H1** 判据的机检实现。
> 为什么需要：签发 SafePoint = 宣称「此刻身体停着」。若 A 处按「槽里没任务」判、B 处按「不在等模型」判，
> 就会出现「凭据说停着、实际在跑」——那正是 G3e 这一批要消灭的事故形态。靠「记得别写第二套」不成立。

## 怎么调

```powershell
# 扫一次（今天应为 OK：G3e-2 还没施工，全仓没有这套组合）
node verify-tools\check-idle-predicate.js

# 自测（6 条：只一个信号 / 两信号违规 / 允许清单 / 定义处豁免 / 只在注释里 / 真扫仓库）
node verify-tools\check-idle-predicate.js --selftest

# 机器可读
node verify-tools\check-idle-predicate.js --json
```

退出码：`0` 合规 / `1` 发现第二套判据 / `2` 环境或用法错。

## 判定规则

**违规** = 宿主代码里（`plugins/` 与 `api/common/src/client/`）**同一个文件**同时出现：

- `currentTaskFor(` —— 「槽里有没有任务」
- `isAwaitingLlmResponse()` 或 `isBusy()` —— 「是否在轮中/等模型」

**不算违规**：

| 情形 | 原因 |
|---|---|
| `RddSafePointIssuer.java`（允许清单） | 唯一的实现处 |
| `EntityAgentLoop.java` / `CompanionTickDispatcher.java`（定义处豁免） | 它们是**信号的生产者**，不是消费者 |
| 只用其中一个信号 | 不构成综合判断 |
| 只在注释里提到 | 扫描前会去掉行注释与块注释 |

## 为什么现在跑也是 OK

`G3e-2` 还没施工，全仓 **485 个宿主源文件**里没有「两个信号出现在同一文件」的组合 —— 这正是 H1 要守住的状态。
施工后 `RddSafePointIssuer` 会出现，它在允许清单里，所以仍应 OK；**若哪天有人图省事在别处再写一套，这条会直接报出来**。

## 没接进门禁（故意的）

它是 **G3e-2 的批内判据**，不属于 preflight/postflight 的常驻检查：
- 施工前跑一次，确认「起点是干净的」；
- 施工后跑一次，确认「没有第二套」。

要长期守着的话，最省事的做法是等 G3e-2 落地后把它接进 postflight 的 Q 段 —— 那时它的误报率已经有实机数据了。
