/** 架构导航的路径与依赖适配。
 * 2026-11-06：复用注册表与已有MCP SDK，避免第二套根路径和历史经验库。
 * 用法：由 server/cli 导入；不连接游戏、不读密钥。
 * SDK缺失直接报错，不在线自动安装。
 */
import path from 'node:path';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const registry = require(path.resolve(here, '../../../../harness/rdd-harness/bin/lib/registry.js')).load();
export const knowledgeRoot = registry.roots.knowledge;
export const graphFile = path.join(knowledgeRoot, '架构意图/035-架构导航图谱.json');
export async function sdk(module) {
  const pkg = registry.resolve('tools/mcp-memory/node_modules/@modelcontextprotocol/server-memory/package.json');
  const resolve = createRequire(fs.realpathSync(pkg));
  return import(pathToFileURL(resolve.resolve('@modelcontextprotocol/sdk/' + module)).href);
}
