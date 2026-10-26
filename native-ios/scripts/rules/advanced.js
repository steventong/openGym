import {buildCombinedEntries,deriveSessionName} from '../../../frontend/src/lib/session-merge.js';
import {buildCompletedWorkout,sessionEnd} from '../../../frontend/src/lib/finish-workout.js';
import {defaultConfig,modeOf,lastEntryFor,setLabel,workoutVolume,bestWeightForEntry,bestWeightFor,cleanupSg,pairAdjacent,unpairSuperset,supersetUnits,doneUnits,setUnitsTotal,setsDoneActive,copyRowAt,moveRoutineEntry,canBeWarmup} from '../../../frontend/src/lib/history.js';
import {registerCustom,beatsWeight} from '../../../frontend/src/lib/exercises.js';
import {normalizePyramid,flatFromPyramid,normalizePyramidRest,normalizePyramidWeight,pyramidRestFor} from '../../../frontend/src/lib/pyramid.js';
import * as M from '../../../frontend/src/lib/workout-model.js';
import {restSecFor,warmupRestSecFor,supersetFlowStep,nextUnfinishedUnit,restAfterSet,setProgressHighWater,restOnRecheck} from '../../../frontend/src/lib/supersetFlow.js';
import {entryDbLoad} from '../../../frontend/src/lib/dumbbells.js';
import {dropGrid} from '../../../frontend/src/lib/plates.js';
import {saveRotation,chooseFixedWeek,chooseRotation,startNewPass,stopPass,refillAfter,scheduleModeOf} from '../../../frontend/src/lib/rotation.js';
import {queueView,queueOf} from '../../../frontend/src/lib/queue.js';
const defaults=s=>{const state={unit:'kg',restSec:90,restPauseSec:15,bodyweight:[],workouts:[],routines:[],exWeights:{},week:{},dayPlan:{},customEx:[],...s};registerCustom(state.customEx);return state;};
const integer=(v,f,min,max)=>Math.max(min,Math.min(max,Math.round(Number(v))||f));
export function advancedConfig(input) {
  const {config:c}=JSON.parse(input),mode=modeOf(c), out={...defaultConfig(c.id,mode),...c,mode};
  out.sets=integer(c.sets,3,1,30); out.weight=Math.max(0,Number(c.weight)||0);
  if(c.restSec>0)out.restSec=integer(c.restSec,90,0,900);else delete out.restSec;
  if(mode==='cardio'){out.min=integer(c.min,20,1,1440);out.speed=Math.max(0,Number(c.speed)||0);}
  else { out.warmupSets=integer(c.warmupSets,0,0,5); if(!out.warmupSets)delete out.warmupSets; }
  if(mode==='time')out.sec=integer(c.sec,45,1,86400);
  if(mode!=='reps'){for(const k of ['pyramid','pyramidRest','pyramidWeight','intensifier'])delete out[k];}
  else {
    const stride=c.side?2:1;out.reps=Math.ceil(integer(c.reps,10,1,1000)/stride)*stride;
    const list=normalizePyramid(c.pyramid,stride);
    if(list.length){Object.assign(out,flatFromPyramid(list),{pyramid:list});out.pyramidRest=normalizePyramidRest(c.pyramidRest,list.length);out.pyramidWeight=normalizePyramidWeight(c.pyramidWeight,list.length);delete out.intensifier;delete out.lastToFailure;}
    else {
      for(const k of ['pyramid','pyramidRest','pyramidWeight'])delete out[k];
      if(c.intensifier?.type==='dropset')out.intensifier={type:'dropset',count:integer(c.intensifier.count,1,1,10),pct:integer(c.intensifier.pct,20,1,90)};
      else if(c.intensifier?.type==='restpause')out.intensifier={type:'restpause',totalReps:integer(c.intensifier.totalReps,8,1,1000),restSec:integer(c.intensifier.restSec,15,5,900)};
      else delete out.intensifier;
    }
  }
  if(mode==='cardio'){delete out.side;delete out.warmupSets;delete out.lastToFailure;}
  if(!out.side)delete out.side;if(!out.lastToFailure)delete out.lastToFailure;
  return JSON.stringify(out);
}
export function planGroup(input){const {rows,operation,index,direction}=JSON.parse(input);let next=rows;if(operation==='pair')next=pairAdjacent(rows,index,index+1);else if(operation==='unpair')next=unpairSuperset(rows,index);else if(operation==='move')next=moveRoutineEntry(rows,index,direction)||rows;cleanupSg(next);return JSON.stringify(next);}
export function beginAdvanced(input){
 const {state,ids,id,now,day}=JSON.parse(input),s=defaults(state),built=buildCombinedEntries(s,ids);
 if(!built.entries.length)throw Error('计划没有可训练的动作。');
 return JSON.stringify({id,d:day,start:now,name:deriveSessionName(built.routines.map(r=>r.name)),routineIds:built.routineIds,routineId:built.routineIds[0],entries:built.entries,bw:s.bodyweight.at(-1)?.w??null,cur:0});
}
export function finishAdvanced(input){
 const {state,active,now,today}=JSON.parse(input),s=defaults(state);
 if(s.workouts.some(w=>w.id===active.id))return JSON.stringify(s);
 const w=buildCompletedWorkout(active,{end:sessionEnd(active,now),prs:[]});
 if(!w.entries.length)throw Error('至少完成一组或一侧后再保存。');
 for(const entry of w.entries){const top=bestWeightForEntry(entry);const before=bestWeightFor(s,entry.id,entryDbLoad(entry));if(beatsWeight(entry.id,top,before))w.prs.push(entry.id);if(beatsWeight(entry.id,top,s.exWeights[entry.id]?.w||0))s.exWeights[entry.id]={w:top,d:w.d};}
 w.prs=[...new Set(w.prs)];w.vol=workoutVolume(w);s.workouts.push(w);s.workouts.sort((a,b)=>(a.d||'').localeCompare(b.d||'')||(a.start||0)-(b.start||0));refillAfter(s,w,today,now);delete s.active;return JSON.stringify(s);
}
export function rowInfo(input){const {row,target={}}=JSON.parse(input);return JSON.stringify({mode:M.modeForSet(row,target),side:M.isSideSet(row),warmup:M.isWarmupRow(row),type:M.setType(row),completed:M.hasCompletedWork(row),canWarmup:canBeWarmup(row)});}
export function sessionInfo(input){const {active}=JSON.parse(input);return JSON.stringify({done:active.entries.reduce((n,e)=>n+e.sets.reduce((v,s)=>v+doneUnits(s),0),0),total:setUnitsTotal(active.entries),completed:setsDoneActive(active),volume:workoutVolume(active)});}
export function editAdvancedRow(input){
 const {row,action,key,value,side,index,patch={},state={},target={},editing=false,now=Date.now()}=JSON.parse(input);let next=structuredClone(row);const grid=dropGrid(defaults(state),target);
 if(action==='field'){
   if(side) next=M.setSideField(next,side,key,value);
   else {if(value==null)delete next[key];else next[key]=value;}
   if(key==='rir'||key==='rpe'){const other=key==='rir'?'rpe':'rir';if(side){next=M.setSideField(next,side,other,null)}else delete next[other];}
 } else if(action==='toggle'){
   if(side)next=M.toggleSide(next,side);else next.done=!next.done;
   if(!editing){if(M.hasCompletedWork(next))next.at=now;else delete next.at;}
 } else if(action==='dropAdd') next=side||M.isSideSet(next)?M.addSideDrop(next,target.intensifier?.pct||20,grid):M.addDrop(next,{w:M.nextDropWeight(next.drops?.at(-1)?.w??next.w,target.intensifier?.pct||20,grid),r:next.r});
 else if(action==='dropEdit')next=side?M.setSideDropAt(next,side,index,patch):M.setDropAt(next,index,patch);
 else if(action==='dropRemove')next=M.isSideSet(next)?M.removeSideDropAt(next,index):M.removeDropAt(next,index);
 else if(action==='clusterAdd'){
   if(M.isSideSet(next))next=M.addSideCluster(next,target.intensifier?.restSec||15);
   else {const r=M.nextBurstReps(next.clusters?.at(-1)?.r??next.r);next={...M.addCluster(next,{r,restSec:target.intensifier?.restSec||15}),r:(next.r||0)+r};}
 } else if(action==='clusterEdit'){
   if(side)next=M.setSideClusterAt(next,side,index,value);
   else {const old=next.clusters?.[index]?.r||0;next={...M.setClusterAt(next,index,{r:value}),r:Math.max(0,(next.r||0)-old+value)};}
 } else if(action==='clusterRemove'){
   if(M.isSideSet(next))next=M.removeSideClusterAt(next,index);
   else {const r=next.clusters?.[index]?.r||0;next={...M.removeClusterAt(next,index),r:Math.max(0,(next.r||0)-r)};}
 } else if(action==='warmup'){next.phase=value?'warmup':'work';next.warmup=!!value;}
 else if(action==='failure')next=M.toggleFailure(next);
 return JSON.stringify(M.syncSideAggregate(next));
}
export function restForCompleted(input){
 const {active,entry,index,state,timerRunning=false}=JSON.parse(input),s=defaults(state),en=active.entries[entry],row=en.sets[index];
 const units=supersetUnits(active.entries),unit=units.find(u=>u.includes(entry))||[entry];
 const unitDone=unit.every(i=>active.entries[i].sets.every(r=>r.done)), next=unitDone?nextUnfinishedUnit(active.entries,units,entry):null;
 const last=unitDone&&!next, beforeWarm=next?.some(i=>active.entries[i].sets.some(r=>M.isWarmupRow(r)&&!r.done));
 const progress=setProgressHighWater(en,active.nativeHighWater?.[entry]||0);
 if(!progress.isNew&&!restOnRecheck({timerRunning,unitDone,lastUnit:last}))return JSON.stringify({preserveRest:true,highWater:progress.highWater});
 let rest=warmupRestSecFor(en,index,restSecFor(active.entries,unit,s.restSec,{idx:entry,sec:pyramidRestFor(en.target,en.sets,index)}));
 if(M.isSideSet(row)&&!row.done)return JSON.stringify({seconds:0,next:entry});
 const partner=row.side==='L'?en.sets[index+1]:row.side==='R'?en.sets[index-1]:null;
 if(partner?.side&&!partner.done&&M.modeForSet(row,en.target)==='time')return JSON.stringify({seconds:Math.min(10,rest),next:entry});
 const step=supersetFlowStep(active.entries,unit,entry);
 if(beforeWarm||last||(step&&!step.unitDone&&!step.roundDone))rest=0;
 return JSON.stringify({seconds:rest,next:progress.isNew?(step?.nextIdx??next?.[0]??entry):active.cur,highWater:progress.highWater});
}
export function rotationInfo(input){const {state,today}=JSON.parse(input);const s=defaults(state),q=queueOf(s);return JSON.stringify({mode:scheduleModeOf(s),view:queueView(s,today),external:!!q&&(!s.rotation||q.rotationId!==s.rotation.id)});}
export function rotationChange(input){
 const {state,action,ids=[],label='',today,now,active}=JSON.parse(input),s=defaults(state);if(active)s.active=active;
 if(action==='save'){
   const unique=[...new Set(ids)];if(unique.some(id=>!s.routines.some(r=>r.id===id)))throw Error('循环中的计划已被删除。');
   s.scheduleMode='rotation';if(unique.length)saveRotation(s,unique,label,today,now);else{stopPass(s,today);s.rotation={...(s.rotation||{}),sequence:[],label};}
 }else if(action==='week')chooseFixedWeek(s,today);
 else if(action==='resume')chooseRotation(s,today,now);
 else if(action==='restart')startNewPass(s,today,now);
 delete s.active;return JSON.stringify(s);
}

export function copyAdvancedSet(input){const {sets}=JSON.parse(input);return JSON.stringify(sets.length?copyRowAt(sets,sets.length-1):[{w:0,r:10,done:false}]);}

export function previousExercise(input) {
 const {state,id,rid,before=Infinity,exclude}=JSON.parse(input),s=defaults(state);
 registerCustom(s.customEx);
 s.workouts=s.workouts.filter(w=>w.id!==exclude && (!w.start || w.start<before)).sort((a,b)=>(a.d||'').localeCompare(b.d||'')||(a.start||0)-(b.start||0));
 const last=lastEntryFor(s,id,rid);
 return JSON.stringify(last?{date:last.d,label:last.sets.map(row=>setLabel(id,row,last.target,s.unit==='lb'?'mph':'km/h')).join(' · ')}:null);
}
