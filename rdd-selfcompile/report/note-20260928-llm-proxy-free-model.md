# 本地 LLM 代理 → OpenRouter 免费模型（2026-09-28 夜 · 先不部署，已验证可行）

> 用户要求：「写一个服务端，先不部署，看一下能不能让游戏内的两个 AI 都用这个免费的模型；
> 当然肯定要瘦身的；顺便查一下为什么（上下文这么大）」

---

## 一、先回答"为什么"：`ctx: 512000` 把闸门放开了

`E:\.minecraft\versions\The Best of Twilight Forest\config\numen\providers.json`：

```json
{ "entries": [ { "id": "prov_1a051f74a34_0", "name": "SRE",
    "provider": "deepseek", "model": "deepseek-v4-flash",
    "api_key": "<REDACTED>", "ctx": 512000 } ] }
```

对照 `providers.json.bak-before-ctx-20260918`：**同一份配置，但没有 `ctx` 字段**。

**结论**：`ctx=512000` 是 **2026-09-18** 加上去的。游戏据此认为上下文上限是 512k，
于是**永不裁剪**，单次请求一路涨到实测 **`tokens=206987/158`（≈207k）**。烧钱就是这个原因。
（该字段本身没写错——512k 是 DeepSeek 的宣称上限；但"上限很大"不等于"每次都该塞满"。）

## 二、免费模型的真名与可用性（实测）

| 项 | 值 |
|---|---|
| OpenRouter 模型 id | **`stealth/space-bunny-alpha`** |
| context | 1,000,000 |
| 价格 | `prompt=0 / completion=0` → **真免费** |
| 实测 usage | `cost: 0`（多次确认）|

## 三、游戏怎么指向本地代理：`baseUrl` 是逐条可配的

从 `numen_api-neoforge` 的 `agent/llm/ProviderLibrary$Entry.class` 里抽出的字段表：

```
id;name;provider;model;apiKey;baseUrl;reasoningEffort;proxy;ctx
```

**`baseUrl` 与 `proxy` 都是每条 entry 自己的字段** → 新加一条 `provider="openai"` +
`baseUrl=http://127.0.0.1:8790/v1` 就能把游戏接到本地代理上，**不用改 hosts、不用 TLS 拦截**。

> 注：游戏内只有 **1 个同伴实体**（`rdd`），但 LLM 消费者有两个 —— **同伴大脑**与
> **RDD 规划器**（日志里 `[rdd] nudge` 由规划器单独发出）。二者都读同一份 `providers.json`，
> 所以**一条配置即可覆盖两个**。

## 四、代理 `scripts\llm-proxy.js`（已写、已测、未部署）

做的事：接 OpenAI 兼容 `POST /v1/chat/completions` → **上下文瘦身** → 转投 OpenRouter
`stealth/space-bunny-alpha` → 原样回包（含 SSE 流式透传）。

### 瘦身的核心难点：不能拆散 tool_calls 与它的 tool 回应
OpenAI 协议要求 `assistant(tool_calls)` 后面必须紧跟它对应的**每一条** `tool` 消息
（`tool_call_id` 要对上）。逐条丢会把它们拆散 → 上游直接 400。
所以按**"组"**丢：一个组 = 一条普通消息，或「带 tool_calls 的助手 + 其后全部 tool 回应」，
**只整组丢，永不产生孤儿**。

### 实测（三项全过）

| # | 测什么 | 结果 |
|---|---|---|
| T1 | 普通对话 | `cost=0`，回「代理可用」；`model=stealth/space-bunny-alpha` |
| T2 | **工具调用**（关键：游戏内 AI 全靠它）| `finish_reason=tool_calls`，正确返回 `get_self_status(arguments={})`，`cost=0` |
| T3 | **瘦身** 726,645 字符 / 62 条消息 | `est 181,461 → 54,495 tok`（丢 21 组）；上游 **HTTP 200**、正常回"继续"、**无 400** → tool 配对完整；实际计费 `prompt_tokens=27,859` |

### 已知风险与已加对策
免费模型上游会抖：实测出现过 **HTTP 200 但 body 是**
`{"message":"Provider returned an empty response","code":502,"error_type":"provider_unavailable"}`。
**按状态码判不出来（它是 200），必须看内容**。已在 `shouldRetry()` 里同时判状态码与内容
（`provider_unavailable` / `empty response` / 429 / 5xx），`PROXY_RETRIES`（默认 3）次退避重试。

### 环境变量
`PROXY_PORT`(8790) / `PROXY_TARGET_MODEL`(stealth/space-bunny-alpha) /
`PROXY_MAX_INPUT_TOKENS`(60000，0=不瘦身) / `PROXY_KEEP_RECENT`(12) /
`PROXY_RETRIES`(3) / `PROXY_LOG_TOKENS`(1) / `OPENROUTER_API_KEY`

## 五、待批准后再做的部署动作（本轮**未做**）

1. 确认代理常开（现在是通过临时 cmd 起的，重启就没了）——需并入 `autostart-dev.ps1` 或做成计划任务
2. 在 `providers.json` 的 `entries` 里**新增**一条（不动现有 SRE 那条，便于回退）：
   ```json
   { "id": "prov_openrouter_free", "name": "OR-Free",
     "provider": "openai", "model": "stealth/space-bunny-alpha",
     "api_key": "any-non-empty", "baseUrl": "http://127.0.0.1:8790/v1",
     "ctx": 120000 }
   ```
   注意 `ctx` 建议**故意填小**（如 120k）——真正该由游戏侧主动裁剪；代理再兜一层。
   ⚠️ `api_key` 必须非空（很多客户端见到空 key 会直接不发请求），代理会忽略它、用自己读到的 OpenRouter key。
3. 先只切**一个**消费者（建议先切规划器）观察一轮，确认稳了再切同伴大脑 —— 不要把两个一起切
4. 备份 `providers.json`（现已有 `.bak-before-ctx-20260918` 的历史，另存一份当次备份）
5. 回滚 = 把 entry 删掉/改回 deepseek 那条

## 六、为什么"先不部署"是对的
- 免费模型上游**不稳定**（已实测到 provider_unavailable）；同伴死了要能退回付费线
- 207k 上下文的根因是 `ctx`，**换模型不自动解决**——必须靠代理瘦身 + 调小 `ctx` 双管
- 游戏内 AI 有**长任务**（当前正跑到 `primary-2`），中途换脑风险高，应等当前这轮跑完
