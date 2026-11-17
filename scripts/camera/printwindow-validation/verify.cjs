'use strict';
const fs=require('fs'),path=require('path'),{spawn}=require('child_process');
const root=path.resolve(process.argv[2]),rows=JSON.parse(fs.readFileSync(path.join(root,'summary.json'),'utf8'));
const ff='D:/rdd/tools/ffmpeg/bin/ffmpeg.exe',probe='D:/rdd/tools/ffmpeg/bin/ffprobe.exe';
async function exec(exe,args,log){return new Promise((resolve,reject)=>{const err=fs.openSync(log,'wx');const p=spawn(exe,args,{stdio:['ignore','pipe',err],windowsHide:true});let text='';p.stdout.on('data',b=>text+=b);p.on('error',reject);p.on('close',code=>{fs.closeSync(err);resolve({code,text})})});}
async function pixels(file,w,h,log){return new Promise((resolve,reject)=>{
 const err=fs.openSync(log,'wx'),p=spawn(ff,['-hide_banner','-v','error','-i',file,'-an','-f','rawvideo','-pix_fmt','rgb24','pipe:1'],{stdio:['ignore','pipe',err],windowsHide:true});
 const size=w*h*3;let tail=Buffer.alloc(0),frames=0,magentaFrames=0,nonTargetFrames=0,counts=[];
 p.stdout.on('data',b=>{
  let joined=tail.length?Buffer.concat([tail,b]):b,offset=0;
  while(joined.length-offset>=size){const frame=joined.subarray(offset,offset+size);offset+=size;
   let magenta=0;for(let i=0;i<frame.length;i+=3)if(frame[i]>180&&frame[i+1]<70&&frame[i+2]>180)magenta++;
   if(magenta>500)magentaFrames++;
   const i=(340*w+600)*3;if(!(frame[i]<40&&frame[i+1]>70&&frame[i+1]<125&&frame[i+2]>85&&frame[i+2]<145))nonTargetFrames++;
   let count=0;for(let bit=0;bit<16;bit++){const j=(260*w+24+36*bit)*3;if(frame[j]+frame[j+1]+frame[j+2]>500)count|=(1<<bit);}
   counts.push(count);frames++;
  }tail=Buffer.from(joined.subarray(offset));
 });p.on('error',reject);p.on('close',code=>{fs.closeSync(err);let backwards=0;for(let i=1;i<counts.length;i++)if(counts[i]<counts[i-1])backwards++;
 resolve({code,frames,trailingBytes:tail.length,magentaFrames,nonTargetFrames,firstCounter:counts[0],lastCounter:counts.at(-1),distinctCounters:new Set(counts).size,backwards,counts});});
});}
(async()=>{
 const output=[];
 for(const row of rows){for(const part of row.parts){
  const file=path.join(row.run,part.name),pr=await exec(probe,['-v','error','-count_frames','-show_entries','stream=codec_name,width,height,r_frame_rate,nb_read_frames:format=duration','-of','json',file],path.join(row.dir,'probe.log'));
  const info=JSON.parse(pr.text),video=info.streams[0];
  const decoded=await pixels(file,video.width,video.height,path.join(row.dir,'decode.log'));
  const counts=decoded.counts;delete decoded.counts;
  fs.writeFileSync(path.join(row.dir,'decoded-counters.json'),JSON.stringify(counts));
  output.push({name:row.name,recorderCode:row.code,ffprobeCode:pr.code,probe:info,decoded,accounting:row.accounting,segments:fs.readFileSync(path.join(row.run,'segments.csv'),'utf8').trim()});
 }}
 fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify(output,null,2));
 console.log(JSON.stringify(output,null,2));
 if(output.some(x=>x.decoded.code!==0||x.decoded.trailingBytes!==0||x.decoded.magentaFrames!==0||x.decoded.nonTargetFrames!==0||x.decoded.backwards!==0||x.decoded.frames!==x.accounting.frames||x.decoded.distinctCounters<2))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});
