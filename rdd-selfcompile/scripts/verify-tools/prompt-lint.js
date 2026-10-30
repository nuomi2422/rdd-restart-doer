#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const fixture = process.env.PROMPT_LINT_FIXTURE;
const governed = fixture ? [
  { path: path.join(fixture, "machine-AGENTS.md"), kind: "machine", max: 80, required: "# DSH 用户全局指令" },
  { path: path.join(fixture, "workspace-AGENTS.md"), kind: "project", max: 100, required: "# RDD 项目入口" },
  { path: path.join(fixture, "pointers.md"), kind: "pointer", max: 150, required: "# RDD 按需指针目录" },
  { path: path.join(fixture, "goal.md"), kind: "goal", max: 150, required: "# 外层编码 AI Goal 提示词" }
] : [
  { path: "C:\\Users\\admin\\.dsh\\AGENTS.md", kind: "machine", max: 80, required: "# DSH 用户全局指令" },
  { path: "D:\\rdd\\workspace\\AGENTS.md", kind: "project", max: 100, required: "# RDD 项目入口" },
  { path: "D:\\rdd\\docs\\rdd-docs\\rdd架构\\指针目录.md", kind: "pointer", max: 150, required: "# RDD 按需指针目录" },
  { path: "D:\\rdd\\docs\\rdd-docs\\rdd架构\\外层编码AI-Goal提示词.md", kind: "goal", max: 150, required: "# 外层编码 AI Goal 提示词" }
];
const errors = []; const warnings = [];
function readFile(file) { try { return fs.readFileSync(file, "utf8"); } catch { errors.push(file + ": cannot read"); return ""; } }
for (const item of governed) { const text=readFile(item.path); if (!text) continue; const lines=text.split(/\r?\n/); const count=lines.at(-1)===""?lines.length-1:lines.length; if(count>item.max) errors.push(item.path+": line budget exceeded ("+count+"/"+item.max+")"); if(!text.includes(item.required)) errors.push(item.path+": missing required marker"); if(/(^|\n)###?\s+.*\bPROPOSED\b/m.test(text)) errors.push(item.path+": PROPOSED rule must stay in candidate file"); }
const pointerItem=governed.find(item=>item.kind==="pointer"); const pointer=pointerItem?readFile(pointerItem.path):"";
for(const match of pointer.matchAll(/`([DC]:\\[^`<>|]+\.(?:md|json|js|ps1))`/gi)){const target=match[1].trim(); if(/[<>]|YYYY-MM|<模块>/.test(target)) continue; if(!fs.existsSync(target)) errors.push(pointerItem.path+": missing pointer target "+target);}
const proposalsPath=fixture?path.join(fixture,"proposals.md"):"D:\\rdd\\docs\\rdd-docs\\rdd架构\\提示词候选规则.md"; const proposals=readFile(proposalsPath); if(/(^|\n)##?\s+[^\n]*\bACTIVE\b/m.test(proposals)) errors.push(proposalsPath+": ACTIVE rule found in proposal area");
const seen=new Map(); for(const item of governed){for(const line of readFile(item.path).split(/\r?\n/)){const match=line.match(/^#{1,4}\s+(.+)$/); if(!match) continue; const title=match[1].trim().toLowerCase(); if(title.length<8) continue; const previous=seen.get(title); if(previous&&previous!==item.path) warnings.push("duplicate heading "+title+" in "+previous+" and "+item.path); else seen.set(title,item.path);}}
for(const warning of warnings) console.log("WARN "+warning); for(const error of errors) console.log("ERROR "+error); console.log("prompt-lint: "+(errors.length?"FAIL":"PASS")+" ("+governed.length+" governed files, "+warnings.length+" warnings)"); process.exitCode=errors.length?1:0;
