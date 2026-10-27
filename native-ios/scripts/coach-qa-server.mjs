// Isolated, deterministic Coach fixture for simulator QA. Never contacts an AI provider.
// Run: node scripts/coach-qa-server.mjs. Pair the simulator to http://localhost:19384 (code QA).
import http from 'node:http';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync(path.join(root,'OpenGym/Resources/web-rules.js'),'utf8'),ctx);
const rules=(name,payload)=>JSON.parse(ctx.OpenGymRules[name](JSON.stringify(payload)));
let state={unit:'kg',routines:[{id:'qa-routine',name:'QA 原有训练',ex:[{id:'0289',sets:3,reps:10,weight:20}]}],week:{1:'qa-routine'},dayPlan:{},workouts:[{id:'qa-workout',routineId:'qa-routine',name:'QA 原有训练',d:'2026-10-26',start:1792980000000,end:1792981800000,entries:[{id:'0289',sets:[{w:20,r:10,done:true}]}]}],bodyweight:[],exWeights:{},customEx:[],futureField:{keep:true}};
let rev=1,status={job:null,pending:null,cap:{used:0,limit:0}},counter=0;
const audit=[];
function snapshot(){fs.mkdirSync(path.join(root,'artifacts/coach'),{recursive:true});fs.writeFileSync(path.join(root,'artifacts/coach/qa-result.json'),JSON.stringify({state,status,audit},null,2));}
function proposal(kind,id){
 if(kind==='create')return {id,kind,iteration:1,createdAt:Date.now(),bundle:{opengym_plan:1,name:'QA 三天力量计划',summary:'测试计划：结合哑铃与绳索，适合每周三次训练。',routines:[{id:'qa-new',name:'全身力量 A',why:'覆盖推、拉与下肢动作。',ex:[{id:'0289',sets:3,reps:10,weight:20,why:'保持稳定的动作节奏。'},{id:'1047',sets:3,reps:12,why:'补充背部训练。'}]}],week:{1:'qa-new',3:'qa-new',5:'qa-new'}}};
 if(kind==='debrief')return {id,kind,summary:'本次训练完成得不错，下次保持动作控制。',score:8,workout:{id:'qa-workout',name:'QA 原有训练',d:'2026-10-26'},highlights:['完成了计划训练。'],watch:['注意充分休息。'],nextTime:['逐步增加训练量。']};
 const r=state.routines[0],e=r.ex[0];return {id,kind:'review',summary:'建议逐步增加训练量，同时保持动作质量。',planHash:rules('coachInfo',{state}).planHash,changes:[{id:'qa-change',type:'sets',target:{routineId:r.id,exId:e.id},before:e.sets,after:e.sets+1,why:'当前完成稳定，适当增加一组。',routineName:r.name}],notes:['根据恢复情况调整。'],evidence:{sessions:1,from:'2026-10-26',to:'2026-10-27'}};
}
http.createServer(async(req,res)=>{
 let raw='';for await(const c of req)raw+=c;const b=raw?JSON.parse(raw):{};
 audit.push({method:req.method,path:req.url});let out={ok:true},code=200;
 switch(req.url){
 case '/api/health':out={ok:true};break;
 case '/api/pair/redeem':out={token:'coach-qa-token',user:{id:'coach-qa',name:'Coach QA（测试账号）'}};break;
 case '/api/me':out={user:{id:'coach-qa',name:'Coach QA（测试账号）'}};break;
 case '/api/config':out={coach:{enabled:true,provider:'fixture',community:true}};break;
 case '/api/data':if(req.method==='PUT'){if(b.baseRev!==rev){code=409;out={error:'conflict'}}else{state=b.state;rev++}}else out={state,rev};break;
 case '/api/coach/disclosure':out={providerLabel:'本机 QA 测试服务',categories:['plan','training','bodyweight','profile','prefs'],version:1};break;
 case '/api/coach/account':out={connected:true,mode:'instance',account:'本机测试数据',providerLabel:'Fixture'};break;
 case '/api/coach/status':out={...status,maxMessageLen:1000};break;
 case '/api/coach/plan':case '/api/coach/review':case '/api/coach/debrief':{
  if(status.job){code=409;out={error:'busy'};break;}
  const id='qa-'+(++counter),kind=req.url.endsWith('/plan')?'create':req.url.endsWith('/debrief')?'debrief':'review';
  status.job={id,kind,startedAt:Date.now(),state:'running'};out={job:status.job};code=202;
  setTimeout(()=>{status.pending=proposal(kind,id);status.job=null;status.last={id,kind,outcome:'proposed'};snapshot();},2200);break;
 }
 case '/api/coach/pending/resolve':status.pending=null;break;
 case '/api/coach/cohort':out={ok:false,sharing:!!state.coach?.share,people:1,minPeople:3};break;
 case '/api/coach/cohort/share':state.coach.share=b.share;rev++;break;
 default:code=404;out={error:'not found'};
 }
 snapshot();res.writeHead(code,{'Content-Type':'application/json'});res.end(JSON.stringify(out));
}).listen(19384,'127.0.0.1',()=>console.log('Isolated Coach QA server: http://localhost:19384 (pair code QA)'));
