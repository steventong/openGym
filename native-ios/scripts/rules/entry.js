// Build-time, read-only imports of openGym's existing pure rules. No WebView or DOM.
import { effectiveRoutineIds, bestWeightForEntry, workoutVolume } from '../../../frontend/src/lib/history.js';
import { registerCustom, beatsWeight } from '../../../frontend/src/lib/exercises.js';
import { rebuildPrHistory } from '../../../frontend/src/lib/workout-date.js';
export function schedule(input) {
  const {state,dates,today}=JSON.parse(input);
  return JSON.stringify(dates.map(date=>effectiveRoutineIds({routines:[],workouts:[],week:{},dayPlan:{},...state},date,today)));
}
export function repairHistory(input) {
  const {state,changedID,touched,recomputeEntries,previous}=JSON.parse(input);
  registerCustom(state.customEx || []);
  const list=state.workouts.sort((a,b)=>(a.d||'').localeCompare(b.d||'') || (a.start||0)-(b.start||0));
  const changed=list.find(w=>w.id===changedID);
  if(!changed) throw new Error('workout missing');
  if(recomputeEntries) {
    changed.entries=changed.entries.map(e=>({...e,topW:bestWeightForEntry(e)||null}));
    changed.vol=workoutVolume(changed);
  }
  state.workouts=rebuildPrHistory(list,touched,changed);
  if(recomputeEntries) {
    const bestIn=(w,id)=>(w?.entries||[]).filter(e=>e.id===id).reduce((best,e)=>{const top=bestWeightForEntry(e);return beatsWeight(id,top,best)?top:best},0);
    for(const id of touched) {
      const kept=state.exWeights?.[id],before=bestIn(previous,id);
      if(!kept || !(kept.w>0) || kept.w!==before || !beatsWeight(id,before,bestIn(changed,id))) continue;
      let best=null;
      for(const w of state.workouts) {const top=bestIn(w,id); if(beatsWeight(id,top,best?.w||0)) best={w:top,d:w.d};}
      if(best)state.exWeights[id]=best;else delete state.exWeights[id];
    }
  }
  return JSON.stringify(state);
}
export * from './advanced.js';
