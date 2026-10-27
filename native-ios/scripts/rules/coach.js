import * as C from '../../../frontend/src/lib/coach.js';
import { insightsFor, sessionInsights } from '../../../frontend/src/lib/coach-insights.js';
import { registerCustom } from '../../../frontend/src/lib/exercises.js';
import { exLine } from '../../../frontend/src/lib/history.js';
import { _setLangState } from '../../../frontend/src/lib/i18n-core.js';
import zh from '../../../frontend/src/locales/zh.js';
const init = s => { _setLangState('zh',zh,null,null); registerCustom(s.customEx || []); return {routines:[],workouts:[],week:{},dayPlan:{},customEx:[],exWeights:{},unit:'kg',...s}; };
const rows = (p,s) => (p.changes || p.decisions || []).map(c=>({...c,title:C.changeTitle(c,s),values:C.changeValues(c,s)}));
export function coachInfo(input) {
 const {state,proposal,history=false,categories=[]}=JSON.parse(input),s=init(state),c=s.coach||C.emptyCoach();
 const p=proposal && (proposal.kind==='review'&&!history?C.markStale(proposal,s):proposal);
 if(p){p.changes=rows(p,s);if(p.bundle)p.bundle={...p.bundle,routines:(p.bundle.routines||[]).map(r=>({...r,ex:r.ex.map(e=>({...e,line:exLine(e,s.unit,s.unit==='lb'?'mph':'km/h')}))}))};}
 return JSON.stringify({consent:C.hasConsent(s),profileLines:C.profileLines(c.profile),canRevert:C.canRevert(s),planHash:C.planHash(s),proposal:p||null,estimateMs:C.estimateMs(s),categories:categories.map(k=>({id:k,title:C.CATEGORY_TEXT[k]?.()[0]||k,detail:C.CATEGORY_TEXT[k]?.()[1]||''})),insights:p?(p.kind==='debrief'?sessionInsights(s,s.workouts.find(w=>w.id===p.workout?.id)):insightsFor(s,p.evidence||{})):null});
}
export function coachMutation(input) {
 const a=JSON.parse(input),s=init(a.state),c=s.coach=s.coach||C.emptyCoach(),op=a.operationId;
 if(op&&(c.nativeOperations||[]).includes(op))return JSON.stringify(s);
 const already=a.proposal&&(c.log||[]).some(x=>x.proposalId===a.proposal.id&&x.kind!=='revert');
 if(a.action==='consent') c.consent={agreedAt:new Date().toISOString(),version:C.CONSENT_VERSION};
 else if(a.action==='profile') { c.profile=a.profile; if(!(c.chat||[]).some(m=>m.kind==='intake')) C.appendChat(s,{role:'user',kind:'intake'}); }
 else if(a.action==='cadence')c.cadence=a.cadence;
 else if(a.action==='chat') { if(!(c.chat||[]).some(m=>m.id===a.message.id))C.appendChat(s,a.message); }
 else if(a.action==='outcome') {
  const id='job-'+a.last.id;
  if(!(c.chat||[]).some(m=>m.id===id)) C.appendChat(s,{id,role:'coach',kind:a.last.outcome==='failed'?'error':'nochange',text:a.text});
 }
 else if(a.action==='revert') {
  if(a.planHash!==C.planHash(s))throw Error('计划已在其他设备更改，请刷新后重新确认撤销。');
  if(!C.revertLast(s))throw Error('没有可以撤销的教练修改。');
  C.appendChat(s,{role:'coach',kind:'reverted',text:'已撤销上次教练修改；训练记录保留。'});
 }
 else if(a.action==='resolve'&&!already) {
  const p=a.proposal; if(!p?.id)throw Error('建议已失效，请刷新。');
  if(p.expiresAt&&p.expiresAt<Date.now())throw Error('这份建议已过期，请重新请求。');
  let ref,kind,text;
  if(a.dismissed){ref=C.recordDismissal(s,p);kind='dismissed';text='已拒绝这份建议。可以告诉教练需要怎样调整。';}
  else if(p.kind==='create') {
   if(a.planHash!==C.planHash(s))throw Error('计划已在其他设备更改，请刷新后重新确认导入。');
   ref=C.applyCreatedPlan(s,p,{schedule:!!a.schedule}).logId;kind='applied';text=a.schedule?'计划已导入，每周安排已更新。':'计划已导入，原来的每周安排保留。';
  }else if(p.kind==='debrief'){ref=C.recordDebrief(s,p);kind='debrief';text='训练复盘已保存。';}
  else{
   const marked=C.markStale(p,s),ids=a.accepted||[];
   if(!ids.length||ids.some(id=>!marked.changes.some(c=>c.id===id&&c.status!=='stale')))throw Error('选中的建议已与当前计划不符，请刷新后重新选择。');
   ref=C.applyChangeSet(s,marked,ids).logId;kind='applied';text=`已应用 ${ids.length} 项修改。`;
  }
  C.appendChat(s,{role:'coach',kind,ref,text});
 }
 if(op)c.nativeOperations=[...(c.nativeOperations||[]),op].slice(-30);
 return JSON.stringify(s);
}
