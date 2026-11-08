// Disposable personal-feature fixture. Binds loopback; never reads user accounts or production data.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const output=path.join(root,'artifacts/personal');fs.mkdirSync(output,{recursive:true});
let state={unit:'kg',restSec:90,routines:[{id:'personal-r',name:'QA 上肢训练',ex:[{id:'0025',sets:3,reps:8,weight:60}]}],week:{1:['personal-r'],4:['personal-r']},dayPlan:{},customEx:[],favEx:[],bodyweight:[{d:'2026-10-20',w:75,t:1792400000000},{d:'2026-10-27',w:74.5,t:1793000000000}],exWeights:{'0025':{w:60,d:'2026-10-27'}},measurements:[{d:'2026-10-20',t:1792400000000,waist:80,chest:95,bodyFat:18,other:[]}],measurementEnabled:['waist','chest','bodyFat'],customMeasurements:[],workouts:[{id:'personal-w1',name:'QA 上肢训练',d:'2026-10-20',start:1792400000000,end:1792403600000,vol:800,entries:[{id:'0025',sets:[{w:50,r:8,done:true},{w:50,r:8,done:true}],target:{mode:'reps'}}],prs:['0025']},{id:'personal-w2',name:'QA 上肢训练',d:'2026-10-27',start:1793000000000,end:1793003600000,vol:960,entries:[{id:'0025',sets:[{w:60,r:8,done:true,rir:2},{w:60,r:8,done:true,rir:1}],target:{mode:'reps'}}],prs:['0025']}],futureField:{keep:true}};
let rev=1;const audit=[];
http.createServer(async(req,res)=>{
 try{
 let input='';for await(const chunk of req){input+=chunk;if(input.length>20_000_000)throw Error('too large');}const body=input?JSON.parse(input):{};
 let code=200,result={ok:true};
 if(req.url==='/api/health')result={ok:true};
 else if(req.url==='/api/pair/redeem'&&body.code==='QA')result={token:'personal-qa:fixture-only',user:{id:'personal-qa',name:'个人功能验收（虚构数据）'}};
 else if(req.url==='/api/me')result={user:{id:'personal-qa',name:'个人功能验收（虚构数据）'}};
 else if(req.url==='/api/data'){
  if(req.method==='PUT'){if(body.baseRev!==rev){code=409;result={error:'conflict'};}else{state=body.state;rev++;audit.push({at:Date.now(),rev,keys:Object.keys(state)});}}
  else result={state,rev};
 }else if(req.url==='/__qa')result={state,rev,audit};
 else{code=404;result={error:'not found'};}
 fs.writeFileSync(path.join(output,'qa-result.json'),JSON.stringify({state,rev,audit},null,2));
 res.writeHead(code,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
 }catch{res.writeHead(400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'invalid fixture request'}));}
}).listen(19386,'127.0.0.1',()=>console.log('Personal fixture: http://localhost:19386 — pair QA'));
