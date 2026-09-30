# 桌宠图片放这里

**把你那 9 张 Q 版图按下面文件名丢进这个目录，桌宠立刻按阶段换表情。**
支持 `.png`（推荐，透明底）/ `.jpg` / `.webp` / `.gif`，正方形 512×512 以上最稳。

## 文件名 ↔ 表情 ↔ 阶段

| 文件名 | 表情 key | 表情 | 用在哪个阶段 |
|---|---|---|---|
| `01-cry.png` | `cry` | 大哭 | 🔁 复审回归 iterate（发现洞了） |
| `02-angry.png` | `angry` | 叉腰生气 | 🔍 外脑审核 review（在挑刺） |
| `03-speechless.png` | `speechless` | 无语 | 📜 契约定稿 contract（被审核挑得没话说） |
| `04-shock.png` | `shock` | 惊讶 | 🧪 验证取证 verify（结果出来了） |
| `05-shy.png` | `shy` | 害羞 | 空闲 / 没有进行中的 stage |
| `06-confused.png` | `confused` | 疑惑 | 🗺️ 计划拆解 plan（在想怎么拆） |
| `07-happy-wave.png` | `wave` | 招手 | 📥 需求接入 intake（新活来了） |
| `08-laugh.png` | `laugh` | 大笑 | 🎉 收工关档 close（做完了） |
| `09-calm.png` | `calm` | 平静 | ⚙️ 编码实现 implement（埋头写码） |

## 命名对不上也行

- 文件名只要是 `*.png` 就行。桌宠会**按文件名排序**依次配给
  `cry → angry → speechless → shock → shy → confused → wave → laugh → calm`。
  所以按你发图顺序命名 `01..09` 就一定对。
- 配好之后在桌宠上**右键 → 🎨 按表情指定图片**，可以单独换某张。
  选中的会记到 `pet\pet-pos.json`，下次还在。
- 没有图时会画一个占位小团子（不白屏），所以**先跑起来再放图**也行，放完
  右键 → 刷新 就换上。

## 改表情对应关系

`..\core\stages.json`：

- `stages[].expr` —— 这个阶段用哪个表情
- `expressions` —— 表情 key → 哪个文件名
- `expressionOrder` —— 兜底配对顺序

改完重启桌宠（或右键刷新）。
