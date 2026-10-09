# 变更记录 · click_gui

> 变更 ID：`mutation-2026-09-17T23-44-41.730108700Z-92a357df`
> 提出方：游戏内智能体（assist 模式下自主诊断 + `selfcompile_request`）
> 实现方：外部自编译系统（开发工具窗口）
> 日期：2026-09-18

## 1. 需求（智能体原话，未改写）

> 缺少"点击GUI按钮"的能力：附魔台(`EnchantmentMenu`)的附魔选项是**按钮而非物品槽**，
> `interact_at` 只能对准世界方块、`transfer` 只能操作槽位，因此无法按下附魔选项，
> 目标成就 `minecraft:story/enchant_item` 卡死。
> 需要一个可对**已打开GUI的按钮/选项**执行点击的能力（例如 `click_gui` / `click_menu_button`，
> 参数：按钮索引0-2或屏幕坐标），最好能通用到其他菜单按钮（**铁砧、织布机、村民交易**等）。

## 2. 缺口是否真实（实现前的核对）

真实。打开的菜单里有两类可交互对象：

| 类别 | 是什么 | 既有工具 |
|---|---|---|
| 槽位 | 物品 | `transfer` |
| **按钮 / 选项** | 动作（屏幕上画成可点控件） | **无 ← 缺口** |

原版把后者统一走 `AbstractContainerMenu#clickMenuButton(player, index)`。
在补上之前，模型能打开并读懂这类菜单，但按不下任何东西 —— 凡是要靠菜单动作达成的目标都会走到死路。

## 3. 做了什么

| 文件 | 改动 |
|---|---|
| `core/.../tools/interact/ClickGuiTool.java` | 新增工具 `click_gui`（参数 `button`：0 起的档位索引） |
| `core/.../tools/GuiOps.java` | 新增 `clickMenuButton(self, index)` 实现 |
| `core/.../NumenCore.java` | `ToolRegistry.register(new ClickGuiTool())` |

设计要点：

- 走原版统一入口 `clickMenuButton`，因此**天生通用**：附魔三档 / 村民交易 / 织布机图案 / 切石机配方 / 信标能力。
- **拒绝时不吞不装**：未开站点 GUI、索引越界、材料不足（附魔台要槽里有青金石且 XP 等级够）、档位未就绪 —— 一律返回明确失败并给出复查指引，不假装成功。
- 与既有工具的分工写进 description：**开站(`interact_at`) → 读菜单(`inspect_gui`) → 备料(`transfer`) → 按档位(`click_gui`)**。

## 4. 提交

```
946dbe4e  [core] 新增 click_gui：按下菜单按钮/选项（自编译闭环的第一件真产物）
```

## 5. 验收（全部通过，2026-09-18 07:53）

| # | 验收项 | 层级 | 结果 |
|---|---|---|---|
| 1 | 编译通过 | 已编译 | ✅ `:core:neoforge:build` BUILD SUCCESSFUL |
| 2 | jar 已部署到游戏 mods | 已部署 | ✅ sha256 `6CC3CE99…` |
| 3 | `click_gui` 出现在工具表 | 宿主加载 | ✅ 工具数 54 → **55**（`registered 55 tool(s)`）；`find_tools {select:click_gui}` 能展开其完整定义 |
| 4 | 智能体能调用它 | 运行时接线 | ✅ 未开 GUI 时按设计返回明确失败；AI 按四步流程调用成功 |
| 5 | 世界效果 | 世界效果 | ✅ `{"success":true,"message":"pressed menu button 0…"}` → 附魔成就达成 → RDD 确认 s6 完成 + 一级目标完成 |

### 真机原始证据（07:53）

```
07:53:02  interact_at                 右键附魔台打开
07:53:08  find_tools [inspect_gui, transfer, click_gui]
07:53:12  inspect_gui                 读菜单
07:53:16  transfer {from:37,to:0}     备料
07:53:19  dispatch click_gui {"button": 0}
07:53:20  tool_result → {"success":true,"message":"pressed menu button 0 on EnchantmentMenu"}
07:53:20  [rdd] 二级目标完成: primary-c29c5c40-3-s6
07:53:20  [rdd] 一级目标完成: 普通附魔台阶段
07:53:38  load_skill world_atlas —— 自主进入下一阶段
```

### 需求侧的完整链条（可追溯）

```
真实能力缺口 → AI 自诊断 + selfcompile_request（本工作区）
→ experience_learn(TOOL_DEFECT) → experience_verify(→ VERIFIED)
→ 外部开发工具接单实现 → 编译 → 部署 → AI find_tools 自主发现
→ 按四步流程调用 → 世界效果达成 → 任务链推进
```

> 证据分级原则：只能声明确实跑到的层级，不拿上一层冒充下一层（**编译通过 ≠ 能力存在**）。
