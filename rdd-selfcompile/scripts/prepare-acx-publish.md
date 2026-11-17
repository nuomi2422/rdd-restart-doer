# 174 AC 发布参数离线准备

此工具仅包装已验的 FE1BDD 源表示，不发布、不读凭据、不启动 Java/游戏，不写 AC 运行库。仅支持准确源码 SHA256 `FE1BDD749F53EA928607C41F0C391200479948EE8718084D8EC19E27C6B08407`。

仅缩短 planner_notes 的重复说明；其余完整 JSON AST 强等，包括 57 个顶层步骤、65 个深层步骤、全部安全守卫、description、safety_notes 与 limits。完整 AST 因 planner_notes 改变而不相等，原源文件和完整说明不得覆盖。

## 生成（Node.js 18+）

从 workspace 仓根执行，下列占位符必须替换。UUID 无默认值；先核当前同伴身份，不能照抄历史现场 UUID。输出目录必须不存在，建议放仓外临时目录，生成的 payload/proof 不应提交。

生成命令：

    node rdd-selfcompile/scripts/prepare-acx-publish.cjs --source <准确FE1B源.ac> --companion <当前UUID> --out-dir <新的仓外目录> --note-file <可选UTF8备注.txt>

不需要备注时省略 --note-file；不嵌入原现场备注或大段正文到命令行。工具读取源并核准确 SHA、元数据外 AST、完整参数 JSON 转义和接收端 JSON roundtrip，最后独占创建输出目录。

输出 publish.json 和 proof.json。证明含源、传输 ac_json、整个 payload、native arguments 的 SHA256，UTF-16 字符/UTF-8 字节数及余量。备注不同会改变最终长度与指纹；每次按实际文件校验，不复用旧数字。

## 真实传输约束

McpServer.handleToolInvoke 复制参数后删除 companion，再用 JsonElement.toString 生成 ExecuteToolPayload.argumentsJson。字符上限是 16384 Java UTF-16 单元，UTF-8 编码上限为 3 倍；HTTP RPC 总体字节数不是该字段长度。工具同时核 native 参数字符和字节上限，拒绝超限，不修改 codec。

已交历史备注 21 字符时 native 参数为 16229 字符/17415 UTF-8 字节，余 155 字符；这是原样本，不是所有备注的保证。仅 JSON 去排版而保全部原 AST 仍超限。本脚本的 metadata 摘要是明确差异，不假称全 AST 相同。

## 唯一驾驶核验后才可发布

    node rdd-selfcompile/scripts/numen-mcp.js call acx_publish "@<绝对输出目录>/publish.json"

不要使用 mcp-call.js 包装器发送此长参数：它会先读 @file 再把全文重新塞进子进程 argv，可能触 Windows 命令行上限。直接 numen-mcp.js 原入口读取文件；PowerShell 中 @路径必须引号包住。生成器本身永不执行此命令。

离线通过不证明 native 编解码、发布成功、Loader/Runner 或世界效果；必须核唯一驾驶实际回执。保留原 pretty 源、旧超长失败票及 source↔transport 映射；不热写活库，不扩 codec，不新分块协议或重建 MC 包。
