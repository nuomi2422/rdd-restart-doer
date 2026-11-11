#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const fixture=process.env.PROMPT_LINT_FIXTURE;
const files=fixture?[
 {path:path.join(fixture,"machine-AGENTS.md"),optional:true,max:80,required:"# DSH 用户全局指令"},
 {path:path.join(fixture,"workspace-AGENTS.md"),max:100,required:"# RDD 项目入口"},
 {path:path.join(fixture,"pointers.md"),max:150,required:"# RDD 按需指针目录"},
 {path:path.join(fixture,"goal.md"),max:150,required:"# 外层编码 AI Goal 提示词"}
]:[
 {path:"C:/Users/admin/.dsh/AGENTS.md",optional:true,max:80,required:"# DSH 用户全局指令"},
 {path:"D:/rdd/workspace/AGENTS.md",max:100,required:"# RDD 项目入口"},
 {path:"D:/rdd/docs/rdd-docs/rdd架构/指针目录.md",max:150,required:"# RDD 按需指针目录"},
 {path:"D:/rdd/docs/rdd-docs/rdd架构/外层编码AI-Goal提示词.md",max:150,required:"# 外层编码 AI Goal 提示词"}
];
const errors=[];
const read=(p,optional=false)=>{try{return fs.readFileSync(p,"utf8")}catch(e){if(optional&&e.code==="ENOENT"){console.log("SKIP "+p+": optional user-global instructions absent");return "";}errors.push(p+": cannot read");return ""}};
// 2026-11-11: the owner removed global instructions; absence is valid, read errors are not.
for(const f of files){const t=read(f.path,f.optional);if(!t)continue;const n=t.split("\n").length-(t.endsWith("\n")?1:0);if(n>f.max)errors.push(f.path+": line budget exceeded ("+n+"/"+f.max+")");if(!t.includes(f.required))errors.push(f.path+": missing required marker");if(t.split("\n").some(x=>x.includes("PROPOSED")&&x.trim().startsWith("#")))errors.push(f.path+": PROPOSED rule must stay in candidate file");}
const pointer=read(files[2].path);
for(const line of pointer.split("\n")){const a=line.indexOf("`D:/");if(a<0)continue;const b=line.indexOf("`",a+1);if(b<0)continue;const target=line.slice(a+1,b);if(target.includes("<")||target.includes("YYYY-MM"))continue;if(!fs.existsSync(target))errors.push(files[2].path+": missing pointer target "+target);}
const proposal=fixture?path.join(fixture,"proposals.md"):"D:/rdd/docs/rdd-docs/rdd架构/提示词候选规则.md";if(read(proposal).split("\n").some(x=>x.includes("ACTIVE")))errors.push(proposal+": ACTIVE rule found in proposal area");
for(const e of errors)console.log("ERROR "+e);
console.log("prompt-lint: "+(errors.length?"FAIL":"PASS")+" ("+files.length+" governed files)");
process.exitCode=errors.length?1:0;
