// Native personal features use the same catalogue, units and analytics as the web client.
import { registerCustom, EXIDX, betterWeight, isAssisted } from '../../../frontend/src/lib/exercises.js';
import { convertStateUnit } from '../../../frontend/src/lib/units.js';
import { inventoryFor, loadKindFor, baseWeightFor, rowLoad } from '../../../frontend/src/lib/plates.js';
import { eqAvailable, exAvailable, ALL_EQUIPMENT } from '../../../frontend/src/lib/equipment.js';
import { buildPlanBundle, parsePlan, mergePlan } from '../../../frontend/src/lib/plan-share.js';
import { buildStarterPlan } from '../../../frontend/src/lib/starter.js';
import { normalizeMeasurementsState, MEASUREMENT_FIELDS } from '../../../frontend/src/lib/measurements.js';
import { bestWeightForEntry, metricEntriesForExercise, metricModeForEntry, completedRepsOf, streakWeeks, workoutVolume, cleanupSg } from '../../../frontend/src/lib/history.js';
import { e1rmSeries, best1RM, estimate1RM, formulaOf } from '../../../frontend/src/lib/onerm.js';
import { currentDbLoad, workoutAs } from '../../../frontend/src/lib/dumbbells.js';
import { maxRepsSeries } from '../../../frontend/src/lib/pyramid.js';
import { perSetSessions, perSetLines } from '../../../frontend/src/lib/per-set.js';
import { avgRir, toScale, displayScale } from '../../../frontend/src/lib/effort.js';
import { loadOfWorkouts, loadOfWeeklyPlan, MUSCLES, MUSCLE_NAME, exerciseMuscleSnapshot, normalizeMuscleGroups } from '../../../frontend/src/lib/muscles.js';
import { fatigueOf, strengthOf } from '../../../frontend/src/lib/recovery.js';
import { computeBalance } from '../../../frontend/src/lib/structuralBalance.js';
import { TEMPLATES, TEMPLATE_LIST, DEFAULT_TEMPLATE_ID } from '../../../frontend/src/lib/structuralBalanceTemplates.js';
import { speedUnitOf, toSpeed } from '../../../frontend/src/lib/speed.js';
import { rebuildPrHistory } from '../../../frontend/src/lib/workout-date.js';
import { workoutText } from '../../../frontend/src/lib/workout-text.js';
const prepare = state => {
  const s = {unit:'kg', workouts:[], routines:[], customEx:[], bodyweight:[], exWeights:{}, week:{}, dayPlan:{}, ...state};
  registerCustom(s.customEx); s.workouts.sort((a,b)=>(a.start||0)-(b.start||0)); return s;
};
export function personalInfo(input) {
  const p=JSON.parse(input), s=prepare(p.state);
  if(p.action==='customMetadata')return JSON.stringify({groups:normalizeMuscleGroups(p.exercise)});
  if(p.action==='equipment')return JSON.stringify({equipment:ALL_EQUIPMENT,available:Object.values(EXIDX).filter(e=>p.equipment ? eqAvailable(p.equipment,e) : exAvailable(s,e)).map(e=>e.id)});
  if(p.action==='plates'){const kind=loadKindFor(s,p.config);return JSON.stringify({kind,base:baseWeightFor(s,p.config.id),...rowLoad(kind,p.weight,baseWeightFor(s,p.config.id),inventoryFor(s))});}
  if(p.action==='measurements')return JSON.stringify({fields:MEASUREMENT_FIELDS,state:normalizeMeasurementsState(s)});
  if(p.action==='exportPlan')return JSON.stringify(buildPlanBundle(s,p.name));
  if(p.action==='parsePlan')return JSON.stringify(parsePlan(p.raw,s.unit));
  if(p.action==='starter'){const plan=buildStarterPlan(p.id,p.equipment);if(!plan)throw Error('未知模板');return JSON.stringify(plan);}
  if(p.action==='oneRM')return JSON.stringify({value:estimate1RM(p.weight,p.reps,formulaOf(s)),formula:formulaOf(s)});
  if(p.action==='workoutText')return JSON.stringify({text:workoutText(p.workout,{unit:s.unit,speedUnit:speedUnitOf(s),nameOf:entry=>p.names?.[entry.id]||EXIDX[entry.id]?.n||entry.n||entry.id})});
  if(p.action==='balance'){const template=TEMPLATES[p.template]||TEMPLATES[DEFAULT_TEMPLATE_ID];return JSON.stringify({templates:TEMPLATE_LIST.map(t=>({id:t.id,name:t.label})),template,result:computeBalance(s,template)});}
  if(p.action==='muscles'){
    const opts={unit:s.unit,bodyweightKg:s.bodyweight.at(-1)?.w*(s.unit==='lb'?0.45359237:1)};
    const selected=s.workouts.filter(w=>!p.days||w.start>=p.now-p.days*86400000);
    return JSON.stringify({muscles:MUSCLES.map(id=>({id,name:MUSCLE_NAME[id]})),load:loadOfWorkouts(selected),plan:loadOfWeeklyPlan(s),fatigue:fatigueOf(s.workouts,p.now,opts),strength:strengthOf(s.workouts,p.now,opts),streak:streakWeeks(s)});
  }
  if(p.action==='progress'){
    const id=p.id,meaning=currentDbLoad(s,id), ws=s.workouts.map(w=>workoutAs(w,id,meaning));
    const data=ws.map(w=>{const entries=metricEntriesForExercise(w,id);const reps=entries.filter(x=>x.mode==='reps');const chosen=reps.length?reps:entries;const mode=reps.length?'reps':chosen.at(-1)?.mode;return {w,mode,rows:chosen.filter(x=>x.mode===mode).flatMap(x=>x.rows),entries:chosen};});
    const mode=data.filter(x=>x.rows.length).at(-1)?.mode||'reps';
    const repsOnly=mode==='reps'&&!ws.some(w=>(w.entries||[]).some(e=>e.id===id&&bestWeightForEntry(e)>0));
    const points=data.filter(x=>x.mode===mode&&x.rows.length).map(x=>{
      const weighted=x.entries.map(e=>bestWeightForEntry(e.entry)).filter(v=>v>0);
      const y=mode==='reps'&&!repsOnly?weighted.reduce((best,v)=>best>0?betterWeight(id,best,v):v,0):Math.max(0,...x.rows.map(r=>mode==='cardio'?toSpeed(r.speed||0,speedUnitOf(s)):mode==='time'?(r.sec||0):completedRepsOf(r)));
      return {t:x.w.start,d:x.w.d,y,effort:avgRir(x.rows)};
    }).filter(p=>p.y>0);
    const eachMetric=repsOnly||isAssisted(id)?'reps':'e1rm';
    return JSON.stringify({mode,unit:mode==='cardio'?speedUnitOf(s):mode==='time'?'秒':repsOnly?'次':s.unit,points,e1rm:e1rmSeries(s,id),best:best1RM(s,id),max:maxRepsSeries(ws,id),effort:points.filter(p=>p.effort!=null).map(p=>({...p,y:toScale(displayScale(s),p.effort)})),effortUnit:displayScale(s).toUpperCase(),perSet:perSetLines(perSetSessions(ws,id,{metric:eachMetric,formula:formulaOf(s)})),perSetUnit:eachMetric==='reps'?'次':s.unit});
  }
  throw Error('未知功能');
}
export function personalChange(input){
  const p=JSON.parse(input),s=prepare(p.state);
  if(p.action==='unit'){
    const out=p.convert?convertStateUnit(s,p.unit):{...s,unit:p.unit};
    if(p.convert)out.bodyweight=(out.bodyweight||[]).map(row=>{
      const prior=s.bodyweight.find(x=>x.d===row.d),mark=prior?.healthKit;
      return mark&&prior.w===mark.value&&prior.t===mark.time?{...row,healthKit:{...row.healthKit,value:row.w}}:row;
    });
    return JSON.stringify(out);
  }
  if(p.action==='importPlan'){mergePlan(s,p.bundle,{schedule:p.schedule});return JSON.stringify(s);}
  if(p.action==='deleteCustom'){
    const ex=s.customEx.find(x=>x.id===p.id);if(!ex)return JSON.stringify(s);
    const snapshot=exerciseMuscleSnapshot(ex);
    for(const w of s.workouts)for(const e of w.entries||[])if(e.id===p.id){e.n=ex.n;if(!e.muscleSnapshot||!Object.keys(e.muscleSnapshot).length)e.muscleSnapshot=snapshot;}
    s.customEx=s.customEx.filter(x=>x.id!==p.id);s.routines.forEach(r=>{r.ex=(r.ex||[]).filter(e=>e.id!==p.id);cleanupSg(r.ex);});delete s.exWeights[p.id];s.favEx=(s.favEx||[]).filter(id=>id!==p.id);return JSON.stringify(s);
  }
  if(p.action==='deleteWorkout'){
    const removed=s.workouts.find(w=>(w.id||`${w.d}|${w.start}`)===p.id);if(!removed)return JSON.stringify(s);
    s.workouts=s.workouts.filter(w=>w!==removed);const touched=[...new Set((removed.entries||[]).map(e=>e.id))];
    // An empty changed record lets the web rule rebuild only affected record badges.
    s.workouts=rebuildPrHistory(s.workouts,touched,{entries:[]});
    for(const id of touched){const before=(removed.entries||[]).filter(e=>e.id===id).map(bestWeightForEntry).filter(w=>w>0).reduce((a,b)=>a>0?betterWeight(id,a,b):b,0);if(s.exWeights[id]?.w!==before)continue;
      const remaining=s.workouts.flatMap(w=>(w.entries||[]).filter(e=>e.id===id).map(e=>({w:bestWeightForEntry(e),d:w.d}))).filter(x=>x.w>0);
      const best=remaining.reduce((a,b)=>!a||betterWeight(id,a.w,b.w)===b.w?b:a,null);if(best)s.exWeights[id]=best;else delete s.exWeights[id];
    }return JSON.stringify(s);
  }
  throw Error('未知操作');
}

import { bestSetFor } from '../../../frontend/src/lib/exercise-history.js';
import { lastEntryFor, modeOf, setLabel } from '../../../frontend/src/lib/history.js';
import { repeatSessionEntries } from '../../../frontend/src/lib/session-repeat.js';
import { POLICIES_FOR, policyFor, MAX_TRIPLE_SETS } from '../../../frontend/src/lib/progression.js';
export function personalReference(input) {
 const p=JSON.parse(input),s=prepare(p.state);s.workouts=s.workouts.filter(w=>w.id!==p.exclude&&(!w.start||w.start<p.before));
 const best=s.logRef==='best', mode=modeOf(p.entry.target||{id:p.entry.id});
 const found=best?bestSetFor(s,p.entry.id,mode,p.entry.target?.dbLoad):lastEntryFor(s,p.entry.id,p.entry.rid);
 return JSON.stringify(found?{kind:best?'最佳':'上次',date:found.d,label:(best?[found.set]:found.sets).map(r=>setLabel(p.entry.id,r,found.target,speedUnitOf(s))).join(' · ')}:null);
}
export function personalRepeat(input) {
 const p=JSON.parse(input),s=prepare(p.state),{entries,skipped}=repeatSessionEntries(s,p.workout);
 if(!entries.length)throw Error('没有可重复的动作；原动作可能已删除。');
 return JSON.stringify({active:{id:p.id,d:p.day,start:p.now,name:p.workout.name||'自由训练',routineIds:[],entries,bw:s.bodyweight.at(-1)?.w??null,cur:0},skipped});
}
export function validatePersonalConfig(input) {
 const {config:c}=JSON.parse(input),mode=modeOf(c),allowed=POLICIES_FOR[mode]||['off'];
 if(c.prog&&!allowed.includes(c.prog))throw Error('进阶规则与记录方式不兼容。');
 const policy=policyFor(c,null,mode);
 if((policy!=='off'||c.backoff)&&c.inc!=null&&!(Number(c.inc)>0))throw Error('进阶步进必须大于零。');
 if(['double','triple'].includes(policy)&&(!(c.repsMin>0)||c.repsMin>c.reps))throw Error('次数下限必须大于零，且不超过上限。');
 if(policy==='triple'&&(!(c.setsMax>=c.sets)||c.setsMax>MAX_TRIPLE_SETS))throw Error(`组数上限需介于起始组数与 ${MAX_TRIPLE_SETS} 之间。`);
 if(c.deloadFactor!=null&&(!(c.deloadFactor>=0.5)||c.deloadFactor>0.95))throw Error('减量系数应为 0.5–0.95。');
 return JSON.stringify(c);
}
