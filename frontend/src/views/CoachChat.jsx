// The conversation with the Coach.
//
// Everything the Coach does happens here: your answers as the opening message, a typing
// bubble while a job runs (with how long it usually takes), the plan or the suggestions as a
// card you page through, a composer to say what to change, and one button that imports the
// result. History stays in the thread — come back any time, ask for a review, refine again.
//
// The thread is `S.coach.chat` (small, synced) plus whatever is live right now from the
// status poll: a running job or a pending proposal. Nothing about the proposal is copied into
// the chat until a decision is made about it, so two devices can never disagree on what is
// pending. Once decided, the chat line carries a `ref` into `S.coach.log`, where the whole
// proposal — every change, accepted or not, the notes, the evidence — is kept, so saying yes
// or no never makes it disappear. Turning the Coach off is the admin's decision, not a control
// on this screen.
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { closeThenNav } from '../lib/nav.js'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t, tn , translateValue } from '../lib/i18n.js'
import { fmtDate, fmtNum, DAYS, weekOrder, weekStartOf } from '../lib/format.js'
import { exLine } from '../lib/history.js'
import { speedUnitOf } from '../lib/speed.js'
import { DEMO } from '../lib/demo.js'
import { MOBILE } from '../lib/mobile.js'
import {
  coachAvailable, hasConsent, emptyCoach, appendChat, recordTiming, estimateMs, profileLines,
  markStale, applicable, applyChangeSet, applyCreatedPlan, recordDismissal, recordDebrief, logEntry,
  changeTitle, changeValues, exName, canRevert, revertLast
} from '../lib/coach.js'
import { insightsFor, sessionInsights } from '../lib/coach-insights.js'
import { useCoachStatus, requestReview, requestDebrief, requestPlan, refinePlan, resolvePending, cohortStats, setCohortShare, jobErrorText, awaitedJob, settleAwaited, JOB_ERRORS } from '../lib/coach-api.js'
import { confirmSheet } from '../sheets.jsx'
import Icon from '../components/Icon.jsx'
import { glyphOf } from '../lib/glyphs.js'
import LineChart from '../components/LineChart.jsx'
import { Button, Check, Switch, Section, Row, SelectRow } from '../components/ui.jsx'
import '../coach.css'

export default function CoachChat() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const user = useStore(s => s.user)
  const config = useStore(s => s.config)
  const coachLocal = useStore(s => s.coachLocal)
  const update = useStore(s => s.update)
  const storeReady = useStore(s => s.ready)
  const toast = useUI(s => s.toast)
  const openSheet = useUI(s => s.openSheet)
  const { job, pending, cap, loading, lastError, last, refresh, maxMessageLen } = useCoachStatus(true)
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const endRef = useRef(null)
  const prevJob = useRef(null)
  const coachMode = coachLocal?.mode

  const ok = coachAvailable(config, user, { demo: DEMO, mobile: MOBILE, coachMode })
  const ready = ok && hasConsent(S) && !!S.coach?.profile
  // Not before the store has loaded: a cold start straight on #/coach would otherwise read an
  // empty state, decide there is no consent, and bounce a consenting user into the intake.
  useEffect(() => {
    if (!storeReady) return
    if (!ok) nav('/home', { replace: true })
    else if (!ready) nav('/coach/intake', { replace: true })
  }, [storeReady, ok, ready])

  // A job that ends is either a proposal, "nothing to change", or a failure. The server tells
  // the client none of that directly — the job simply stops appearing — so the transition is
  // read here, once, and written into the thread as the Coach's reply. Two ways to see it end:
  // the job was seen running and is now gone, or the run this app started (its id came back
  // from the start request) is already the server's last outcome — a provider that refuses the
  // connection fails the run before the first status poll, and it is never seen running at all.
  useEffect(() => {
    if (loading) return
    const was = prevJob.current
    prevJob.current = job
    if (job) return
    const mine = awaitedJob()
    const endedUnseen = !was && !!mine && last?.id === mine
    if (!was && !endedUnseen) return
    settleAwaited(was ? was.id : mine)
    const ms = was?.startedAt ? Date.now() - was.startedAt : 0
    update(s => {
      // A run that ended unseen has no duration worth learning from.
      if (was) recordTiming(s, ms)
      if (!pending) {
        const cls = lastError?.errorClass || (last?.outcome === 'failed' ? (last.errorClass || 'internal') : null)
        appendChat(s, cls
          ? { role: 'coach', kind: 'error', text: jobErrorText(cls, lastError?.detail) }
          : { role: 'coach', kind: 'nochange', text: last?.reading
            ? last.reading
            : t("I_LOOKED_THROUGH_EVERYTHING_AND_THERE_IS_NOTHING_I_WOULD_CHANGE_RIGHT" /* 我全部看了一遍，目前没有想改的地方。继续保持，再练几次后再来问我。 */) })
      }
    })
  }, [job, pending, loading, last?.id])

  useEffect(() => { if (typeof endRef.current?.scrollIntoView === 'function') endRef.current.scrollIntoView({ block: 'end' }) }, [S.coach?.chat?.length, !!job, !!pending])

  if (!ready) return null
  const coach = S.coach || emptyCoach()
  const community = !!config?.coach?.community && !DEMO && !(MOBILE && coachMode === 'byok')

  const send = async () => {
    const msg = text.trim()
    if (!msg || busy) return
    setBusy(true)
    try {
      // A message about a proposed plan refines it. With no plan at all — the first attempt
      // failed, or nothing was ever built — the message asks for one; a review would only
      // answer that there is no workout to look at, which is how people got stuck.
      if (pending?.kind === 'create' || !(S.routines || []).length) await refinePlan(msg)
      else await requestReview(msg)
      update(s => appendChat(s, { role: 'user', kind: 'text', text: msg }))
      setText('')
      refresh()
    } catch (e) {
      // A server that refuses the job says so in English, with its class beside it: the class
      // picks the translated line. One with no line here ('shared') keeps the server's words.
      toast(JOB_ERRORS[e.data?.code] || e.message || t("COULD_NOT_ASK_THE_COACH" /* 无法请求教练 */))
    }
    setBusy(false)
  }

  const ask = async (fn, line) => {
    setBusy(true)
    try {
      await fn()
      update(s => appendChat(s, { role: 'user', kind: 'text', text: line }))
      refresh()
    } catch (e) { toast(JOB_ERRORS[e.data?.code] || e.message || t("COULD_NOT_ASK_THE_COACH" /* 无法请求教练 */)) }
    setBusy(false)
  }
  const askReview = () => ask(() => requestReview(''), t("HAVE_A_LOOK_AT_MY_TRAINING_AND_TELL_ME_WHAT_YOU_WOULD" /* 看看我的训练，告诉我你会改什么。 */))
  const lastWorkout = (S.workouts || []).filter(w => w && w.d).at(-1) || null
  const askDebrief = () => ask(() => requestDebrief(lastWorkout?.id || null), lastWorkout?.name
    ? t("HOW_DID_MY_COUNT_SESSION_GO" /* 我的 {0} 训练怎么样？ */, lastWorkout.name)
    : t("HOW_DID_MY_LAST_WORKOUT_GO" /* 我上次训练怎么样？ */))
  const askNewPlan = () => ask(() => requestPlan(coach.profile), t("BUILD_ME_A_FRESH_PLAN_FROM_MY_ANSWERS" /* 根据我的回答给我制定一个新计划。 */))
  const askImprove = r => ask(
    () => requestReview(t("FOCUS_ONLY_ON_MY_ROUTINE_COUNT_IMPROVE_IT_EXERCISE_CHOICE_ORDER_SETS" /* 只关注我的计划“{0}”。改进它：动作选择、顺序、组数与次数、次数范围、进阶方式。其他计划不要动。 */, r.name)),
    t("IMPROVE_MY_ROUTINE_COUNT" /* 改进我的计划“{0}”。 */, r.name))

  const pickRoutine = () => openSheet(close => <div className="chat-menu">
    <h3>{t("IMPROVE_WHICH_ROUTINE" /* 改进哪个计划？ */)}</h3>
    <div className="sect-b">
      {(S.routines || []).map(r => <Row key={r.id} icon={glyphOf(r.emoji)} iconTint="var(--acc)" title={r.name} subtitle={tn("COUNT_EXERCISE" /* {0} 个动作 */, "COUNT_EXERCISES" /* {0} 个动作 */, (r.ex || []).length)} accessory="chevron" onClick={() => { close(); askImprove(r) }} />)}
      {!(S.routines || []).length && <div className="chat-empty">{t("YOU_DON_T_HAVE_ANY_ROUTINES_YET_ASK_THE_COACH_FOR_A" /* 你还没有训练计划。先向教练要一份吧。 */)}</div>}
    </div>
    <div style={{ height: 10 }} />
  </div>)

  const showHistory = () => openSheet(close => <HistorySheet S={S} close={close} openSheet={openSheet} />)
  const showCohort = () => openSheet(() => <CohortSheet S={S} update={update} toast={toast} />)

  const idle = !job && !pending
  const menu = () => openSheet(close => <div className="chat-menu">
    <h3>{t("COACH" /* 教练 */)}</h3>
    <div className="sect-b">
      {idle && <Row icon="sparkles" iconTint="var(--acc)" title={t("ASK_FOR_A_REVIEW" /* 请求复盘 */)} subtitle={t("WHAT_WOULD_THE_COACH_CHANGE_AFTER_YOUR_LAST_SESSIONS" /* 教练在你最近几次训练后会改什么？ */)} accessory="chevron" onClick={() => { close(); askReview() }} />}
      {idle && !!lastWorkout && <Row icon="checkCircle" iconTint="var(--green)" title={t("REVIEW_MY_LAST_WORKOUT" /* 复盘上次训练 */)} subtitle={t("WHAT_WENT_WELL_WHAT_TO_WATCH_WHAT_TO_DO_NEXT_TIME" /* 哪些做得好、需要注意什么、下次怎么做 */)} accessory="chevron" onClick={() => { close(); askDebrief() }} />}
      {idle && !!(S.routines || []).length && <Row icon="wrench" iconTint="var(--orange)" title={t("IMPROVE_A_ROUTINE" /* 改进一个计划 */)} subtitle={t("PICK_ONE_THE_COACH_WORKS_ON_JUST_THAT" /* 选一个，教练只处理它 */)} accessory="chevron" onClick={() => { close(); pickRoutine() }} />}
      {community && <Row icon="person" iconTint="var(--teal)" title={t("COMPARE_WITH_OTHERS_HERE" /* 与这里的其他人比较 */)} subtitle={t("ANONYMOUS_MEDIANS_FROM_THIS_INSTANCE" /* 来自本实例的匿名中位数 */)} accessory="chevron" onClick={() => { close(); showCohort() }} />}
      <Row icon="history" iconTint="var(--blue)" title={t("EVERYTHING_THE_COACH_PROPOSED" /* 教练提出的所有建议 */)} subtitle={t("PLANS_SUGGESTIONS_AND_DEBRIEFS_KEPT" /* 计划、建议和复盘，全部保留 */)} accessory="chevron" onClick={() => { close(); showHistory() }} />
      {idle && <Row icon="clipboard" iconTint="var(--indigo)" title={t("START_A_NEW_PLAN" /* 开始新计划 */)} subtitle={t("A_FRESH_PLAN_FROM_YOUR_ANSWERS_YOUR_WORKOUTS_STAY" /* 根据你的回答生成新计划；训练记录保留 */)} accessory="chevron" onClick={() => { close(); askNewPlan() }} />}
      <Row icon="pencil" iconTint="var(--indigo)" title={t("EDIT_MY_ANSWERS" /* 编辑我的回答 */)} subtitle={t("GOAL_DAYS_EQUIPMENT_LIMITS" /* 目标、天数、器材、限制 */)} accessory="chevron" onClick={() => closeThenNav(close, '/coach/intake?edit=1')} />
      <Row icon="clock" iconTint="var(--purple)" title={t("AUTOMATIC_REVIEWS" /* 自动复盘 */)} subtitle={cadenceLabel(coach)} accessory="chevron" onClick={() => { close(); cadenceSheet(openSheet, update) }} />
      {canRevert(S) && <Row icon="reset" iconTint="var(--blue)" title={t("UNDO_THE_LAST_COACH_CHANGES_A" /* 撤销教练上次的更改 */)} accessory="chevron" onClick={() => { close(); doRevert() }} />}
    </div>
    <div style={{ height: 10 }} />
  </div>)

  const doRevert = () => confirmSheet({
    title: t("UNDO_THE_LAST_COACH_CHANGES" /* 要撤销教练上次的更改吗？ */),
    message: t("YOUR_PLAN_GOES_BACK_TO_HOW_IT_WAS_BEFORE_YOU_ACCEPTED_THEM" /* 你的计划会恢复到你接受这些更改之前的状态。此后记录的训练不受影响。 */),
    confirmText: t("UNDO" /* 撤销 */),
    onConfirm: () => {
      let ok = false
      update(s => { ok = revertLast(s); if (ok) appendChat(s, { role: 'coach', kind: 'reverted', text: t("DONE_YOUR_PLAN_IS_BACK_TO_HOW_IT_WAS_BEFORE_MY_LAST" /* 搞定！你的计划已恢复到我上次更改之前的样子。 */) }) })
      toast(ok ? t("PLAN_RESTORED" /* 计划已恢复 */) : t("NOTHING_TO_UNDO" /* 没有可撤销的内容 */))
    }
  })

  const status = job ? t("THINKING" /* 思考中… */) : pending ? t("HAS_A_SUGGESTION_FOR_YOU" /* 有一个建议给你 */) : t("HERE_WHEN_YOU_NEED_IT" /* 随时待命 */)
  const placeholder = pending?.kind === 'create'
    ? t("WHAT_SHOULD_CHANGE" /* 需要改什么？ */)
    : job ? t("COACH_IS_THINKING" /* 教练思考中… */) : t("MESSAGE_THE_COACH" /* 给教练留言… */)

  return <div className="narrow chat">
    <div className="chat-hdr">
      <button className="iconbtn" onClick={() => nav('/plan')} aria-label={t("BACK_A" /* 返回 */)}><Icon name="chevronLeft" /></button>
      <div className="chat-av"><Icon name="sparkles" /></div>
      <div className="grow">
        <h1>{t("COACH" /* 教练 */)}</h1>
        <div className={'chat-st' + (job ? ' live' : '')}>{status}</div>
      </div>
      <button className="iconbtn" onClick={menu} aria-label={t("MORE" /* 更多 */)}><Icon name="more" /></button>
    </div>

    <div className="msgs">
      <Bubble role="coach">{t("HI_I_M_YOUR_COACH_I_BUILD_YOUR_PLAN_FROM_YOUR_ANSWERS" /* 你好，我是你的教练。我根据你的回答制定计划，再根据你实际记录的内容调整。你不点头，什么都不会变。 */)}</Bubble>

      {(coach.chat || []).map(m => <Message key={m.id} m={m} S={S} profile={coach.profile} openSheet={openSheet} />)}

      {job && <Typing S={S} kind={job.kind} coachLocal={coachLocal} config={config} />}

      {pending && !job && (pending.kind === 'create'
        ? <PlanCard p={pending} S={S} update={update} toast={toast} nav={nav} refresh={refresh} />
        : pending.kind === 'debrief'
          ? <DebriefCard p={pending} S={S} update={update} toast={toast} refresh={refresh} />
          : <ReviewCard p={pending} S={S} update={update} toast={toast} refresh={refresh} />)}

      <div ref={endRef} />
    </div>

    <div className="composer">
      {idle && !busy && <div className="chips-row">
        <button className="qchip" onClick={askReview}><Icon name="sparkles" />{t("REVIEW_MY_TRAINING" /* 评估我的训练 */)}</button>
        {!!lastWorkout && <button className="qchip" onClick={askDebrief}><Icon name="checkCircle" />{t("LAST_WORKOUT" /* 上次训练 */)}</button>}
        {!!(S.routines || []).length && <button className="qchip" onClick={pickRoutine}><Icon name="wrench" />{t("IMPROVE_A_ROUTINE" /* 改进一个计划 */)}</button>}
        {community && <button className="qchip" onClick={showCohort}><Icon name="person" />{t("COMPARE" /* 比较 */)}</button>}
      </div>}
      <div className="composer-in">
        <textarea rows={1} value={text} maxLength={maxMessageLen || 1000} placeholder={placeholder} disabled={!!job}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }} />
        <button className="send" onClick={send} disabled={!text.trim() || busy || !!job} aria-label={t("SEND" /* 发送 */)}><Icon name="arrowUp" /></button>
      </div>
      {cap?.limit > 0 && <div className="composer-cap">{t("COUNT_OF_COUNT_COACH_RUNS_USED_TODAY" /* 今日已使用 {1} 次教练调用中的 {0} 次 */, cap.used, cap.limit)}</div>}
    </div>
  </div>
}

/* ---------------------------------- bubbles ---------------------------------- */

function Bubble({ role, kind, at, children }) {
  const cls = kind === 'error' ? ' err' : ''
  return <div className={'msg ' + role}>
    <div className={'bub' + cls}>{children}</div>
    {at && <div className="msg-t">{stamp(at)}</div>}
  </div>
}

function Message({ m, S, profile, openSheet }) {
  if (m.kind === 'intake') {
    const lines = profileLines(profile)
    return <Bubble role="user" at={m.at}>
      {t("HERE_IS_WHAT_I_AM_WORKING_WITH" /* 这是我的情况： */)}
      <ul>{lines.map((l, i) => <li key={i}>{l}</li>)}</ul>
    </Bubble>
  }
  if (m.kind === 'applied' || m.kind === 'dismissed' || m.kind === 'debrief') {
    const entry = m.ref ? logEntry(S, m.ref) : null
    return <div className="msg coach" style={entry ? { maxWidth: '100%', width: '100%' } : undefined}>
      {!!m.text && <div className="bub">{m.text}</div>}
      {entry && <Recap entry={entry} S={S} openSheet={openSheet} />}
      {m.at && <div className="msg-t">{stamp(m.at)}</div>}
    </div>
  }
  if (m.kind === 'reverted' || m.kind === 'nochange' || m.kind === 'error' || m.kind === 'text') {
    return <Bubble role={m.role} kind={m.kind} at={m.at}>{m.text}</Bubble>
  }
  return null
}

const stamp = at => {
  const d = new Date(at)
  const today = new Date()
  const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  return d.toDateString() === today.toDateString() ? time : fmtDate(d.toISOString().slice(0, 10)) + ' · ' + time
}

function Typing({ S, kind, coachLocal, config }) {
  const ms = estimateMs(S)
  // "Local" on either side: the phone's own OpenAI-compatible endpoint, or the server's —
  // /api/config names the provider, and a model on the owner's box is nothing like a cloud API.
  const local = (coachLocal?.mode === 'byok' && coachLocal?.provider === 'compatible') || config?.coach?.provider === 'compatible'
  let eta
  if (ms) {
    const min = Math.round(ms / 60000)
    eta = min < 1 ? t("USUALLY_UNDER_A_MINUTE" /* 通常不到一分钟。 */) : t("USUALLY_ABOUT_COUNT_MIN" /* 通常约 {0} 分钟。 */, min)
  } else {
    // Until a job has been measured, "a minute or two" is a cloud number — say nothing for a
    // local model rather than something wrong; the next line already warns it takes longer.
    eta = local ? '' : t("THIS_USUALLY_TAKES_A_MINUTE_OR_TWO" /* 通常需要一两分钟。 */)
  }
  const doing = kind === 'create' ? t("BUILDING_YOUR_PLAN" /* 正在制定你的计划… */) : kind === 'debrief' ? t("LOOKING_AT_THAT_SESSION" /* 正在查看该次训练… */) : t("READING_YOUR_TRAINING" /* 正在查看你的训练… */)
  return <div className="msg coach">
    <div className="bub typing"><i /><i /><i /></div>
    <div className="typing-eta">
      {doing} {eta}
      {local ? ' ' + t("A_LOCAL_MODEL_CAN_TAKE_LONGER" /* 本地模型可能需要更长时间。 */) : ''}
      {' ' + t("FEEL_FREE_TO_LEAVE_IT_KEEPS_GOING" /* 你可以离开，它会继续运行。 */)}
    </div>
  </div>
}

/* ---------------------------------- the plan ---------------------------------- */

function PlanCard({ p, S, update, toast, nav, refresh }) {
  const b = p.bundle
  const [tab, setTab] = useState(0)
  const [schedule, setSchedule] = useState(true)
  const r = b.routines[Math.min(tab, b.routines.length - 1)]
  const weekDays = useMemo(() => new Set(Object.keys(b.week || {}).map(Number)), [b])

  const accept = () => {
    try {
      let n = 0
      update(s => {
        const res = applyCreatedPlan(s, p, { schedule })
        n = res?.routines?.length || b.routines.length
        appendChat(s, { role: 'coach', kind: 'applied', ref: res.logId, text: schedule
          ? t("IMPORTED_COUNT_ROUTINES_ARE_IN_YOUR_PLAN_AND_YOUR_WEEK_IS_SET" /* 已导入！{0} 个训练计划已加入你的计划，本周也安排好了。下次训练见。 */, n)
          : t("IMPORTED_COUNT_ROUTINES_ARE_IN_YOUR_PLAN_YOUR_WEEK_IS_UNCHANGED_SCHEDULE" /* 已导入！{0} 个训练计划已加入你的计划。本周安排不变，你想什么时候排都行。 */, n) })
      })
      resolvePending({ accepted: ['plan'] }).catch(() => {})
      toast(t("YOUR_PLAN_IS_LIVE" /* 你的计划已生效 */))
      refresh()
    } catch (e) { toast(e.message || t("THAT_PROPOSAL_CAN_T_BE_READ" /* 无法读取该提议。 */)) }
  }
  const discard = () => confirmSheet({
    title: t("DISCARD_THIS_PLAN" /* 要放弃这个计划吗？ */), message: t("NOTHING_IS_SAVED_AND_YOU_CAN_ASK_AGAIN_ANYTIME" /* 不会保存任何内容，你随时可以再次请求。 */),
    confirmText: t("DISCARD" /* 放弃 */), danger: true,
    onConfirm: () => {
      update(s => { const ref = recordDismissal(s, p); appendChat(s, { role: 'coach', kind: 'dismissed', ref, text: t("DISCARDED_TELL_ME_WHAT_WAS_OFF_AND_I_WILL_BUILD_A_DIFFERENT" /* 已放弃。告诉我哪里不合适，我会重新制定一个。 */) }) })
      resolvePending({ dismissed: true }).catch(() => {})
      refresh()
    }
  })

  return <div className="msg coach" style={{ maxWidth: '100%', width: '100%' }}>
    <div className="pcard">
      <div className="pcard-hd">
        <div className="pcard-eyebrow">{p.iteration > 1 ? t("REVISION_COUNT" /* 第 {0} 版 */, p.iteration) : t("YOUR_PLAN" /* 你的计划 */)}</div>
        <h2 className="pcard-h">{b.name || t("COACH_PLAN" /* 教练计划 */)}</h2>
        {!!b.summary && <p className="pcard-sum">{b.summary}</p>}
        {!!b.basedOn && <p className="pcard-sum" style={{ fontSize: 13 }}>{b.basedOn}</p>}
      </div>

      <WeekStrip days={weekDays} ws={weekStartOf(S)} />

      {b.routines.length > 1 && <div className="pcard-tabs">
        {b.routines.map((x, i) => <button key={x.id || i} className={'pcard-tab' + (i === tab ? ' on' : '')} onClick={() => setTab(i)}><Icon name={glyphOf(x.emoji)} />{x.name}</button>)}
      </div>}

      {r && <RoutineBlock r={r} unit={S.unit} speedUnit={speedUnitOf(S)} />}

      <div className="pcard-row">
        <span className="lrow-m"><span className="lrow-t">{t("USE_THIS_WEEKLY_SCHEDULE" /* 使用此每周日程 */)}</span><span className="lrow-s">{t("REPLACES_YOUR_CURRENT_WEEK_DAYS_THIS_PLAN_LEAVES_EMPTY_BECOME_REST_DAYS" /* 将替换你当前的一周安排。此计划留空的日子将成为休息日。 */)}</span></span>
        <Switch checked={schedule} onChange={setSchedule} />
      </div>
      <div className="pcard-note">{t("THE_COACH_IS_NOT_A_DOCTOR_OR_A_PHYSIOTHERAPIST_IF_SOMETHING_HURTS" /* 教练不是医生或物理治疗师。如果哪里疼，请咨询专业人士。 */)}</div>
      <div className="pcard-ft">
        <Button variant="primary" icon="download" onClick={accept}>{t("IMPORT_THIS_PLAN" /* 导入此计划 */)}</Button>
        <Button onClick={discard}>{t("DISCARD" /* 放弃 */)}</Button>
      </div>
    </div>
    <div className="msg-t">{t("NOT_QUITE_RIGHT_SAY_WHAT_TO_CHANGE_BELOW_AND_I_WILL_REVISE" /* 不太合适？在下方说说要改什么，我会重新修改整个计划。 */)}</div>
  </div>
}

// In the order the week is set to start on (Settings), like the Plan's own week.
const WeekStrip = ({ days, ws }) => <div className="pcard-week">
  {weekOrder(ws).map(d => <div key={d} className={'pcard-wd' + (days.has(d) ? ' on' : '')}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYS[d])}</div>)}
</div>

const RoutineBlock = ({ r, unit, speedUnit }) => <div className="pcard-rt">
  <div className="pcard-rt-h"><b><Icon name={glyphOf(r.emoji)} />{r.name}</b><span>{tn("COUNT_EXERCISE" /* {0} 个动作 */, "COUNT_EXERCISES" /* {0} 个动作 */, r.ex.length)}</span></div>
  {!!r.why && <div className="pcard-why">{r.why}</div>}
  {r.ex.map((e, i) => <div key={i} className="pcard-ex">
    <div className="pcard-ex-r"><span className="pcard-ex-n">{exName(e.id)}</span><span className="pcard-ex-l">{exLine(e, unit, speedUnit)}</span></div>
    {!!e.why && <div className="pcard-ex-w">{e.why}</div>}
  </div>)}
</div>

/* ---------------------------------- a review ---------------------------------- */

function ReviewCard({ p, S, update, toast, refresh }) {
  const marked = useMemo(() => markStale(p, S), [p, S])
  const usable = applicable(marked)
  const [accepted, setAccepted] = useState(() => new Set(usable.map(c => c.id)))
  const toggle = id => setAccepted(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  const apply = () => {
    const ids = [...accepted].filter(id => usable.some(c => c.id === id))
    if (!ids.length) { discard(); return }
    try {
      update(s => {
        const res = applyChangeSet(s, marked, ids)
        appendChat(s, { role: 'coach', kind: 'applied', ref: res.logId, text: tn("APPLIED_COUNT_CHANGE_TO_YOUR_PLAN" /* 已对你的计划应用 {0} 项更改。 */, "APPLIED_COUNT_CHANGES_TO_YOUR_PLAN" /* 已对你的计划应用 {0} 项更改。 */, ids.length) })
      })
      resolvePending({ accepted: ids, rejected: marked.changes.filter(c => !ids.includes(c.id)).map(c => c.id) }).catch(() => {})
      toast(tn("COUNT_CHANGE_APPLIED" /* 已应用 {0} 项更改 */, "COUNT_CHANGES_APPLIED" /* 已应用 {0} 项更改 */, ids.length))
      refresh()
    } catch (e) { toast(e.message || t("COULD_NOT_APPLY_THOSE_CHANGES" /* 无法应用这些更改 */)) }
  }
  const discard = () => confirmSheet({
    title: t("DISMISS_THESE_SUGGESTIONS" /* 要忽略这些建议吗？ */), message: t("NOTHING_CHANGES_AND_THE_COACH_WILL_REMEMBER_YOU_TURNED_THESE_DOWN" /* 不会有任何改动，教练会记住你拒绝了这些建议。 */),
    confirmText: t("DISMISS" /* 忽略 */), danger: true,
    onConfirm: () => {
      update(s => { const ref = recordDismissal(s, marked); appendChat(s, { role: 'coach', kind: 'dismissed', ref, text: t("GOT_IT_I_WON_T_SUGGEST_THESE_AGAIN_WITHOUT_NEW_EVIDENCE" /* 明白了。没有新的依据，我不会再建议这些。 */) }) })
      resolvePending({ dismissed: true }).catch(() => {})
      refresh()
    }
  })

  return <div className="msg coach" style={{ maxWidth: '100%', width: '100%' }}>
    <div className="pcard">
      <div className="pcard-hd">
        <div className="pcard-eyebrow">{t("SUGGESTIONS" /* 建议 */)}</div>
        <h2 className="pcard-h">{tn("COUNT_SUGGESTION" /* {0} 条建议 */, "COUNT_SUGGESTIONS" /* {0} 条建议 */, marked.changes.length)}</h2>
        {!!marked.summary && <p className="pcard-sum">{marked.summary}</p>}
        {!!marked.evidence?.sessions && <p className="pcard-sum" style={{ fontSize: 13 }}>
          {t("BASED_ON_YOUR_LAST_COUNT_SESSIONS" /* 基于你最近 {0} 次训练 */, marked.evidence.sessions)}{marked.evidence.from ? ` · ${fmtDate(marked.evidence.from)} – ${fmtDate(marked.evidence.to)}` : ''}
        </p>}
        {marked.planMoved && <p className="pcard-sum" style={{ fontSize: 13, color: 'var(--yellow)' }}>
          {t("YOUR_PLAN_CHANGED_SINCE_THE_COACH_LOOKED_AT_IT_SUGGESTIONS_THAT_NO" /* 自教练查看以来，你的计划有变动。不再匹配的建议已置灰。重新请求复盘即可再次看到。 */)}
        </p>}
      </div>

      <Insights S={S} window={marked.evidence} />

      {marked.changes.map(c => {
        const stale = c.status === 'stale'
        return <ChangeRow key={c.id} c={c} S={S} stale={stale}>
          {!stale && <Check checked={accepted.has(c.id)} onChange={() => toggle(c.id)} />}
        </ChangeRow>
      })}

      <Notes notes={marked.notes} />

      <div className="pcard-note">{t("THE_COACH_IS_NOT_A_DOCTOR_OR_A_PHYSIOTHERAPIST_IF_SOMETHING_HURTS" /* 教练不是医生或物理治疗师。如果哪里疼，请咨询专业人士。 */)}</div>
      <div className="pcard-ft">
        <Button variant="primary" icon="check" onClick={apply}>
          {accepted.size ? tn("APPLY_COUNT_CHANGE" /* 应用 {0} 项更改 */, "APPLY_COUNT_CHANGES" /* 应用 {0} 项更改 */, accepted.size) : t("APPLY_NOTHING" /* 不应用任何更改 */)}
        </Button>
        <Button onClick={discard}>{t("DISMISS_ALL" /* 全部忽略 */)}</Button>
      </div>
    </div>
  </div>
}

function ChangeRow({ c, S, stale, badge, children }) {
  const vals = changeValues(c, S)
  return <div className={'pcard-chg' + (stale ? ' stale' : '') + (c.status === 'rejected' ? ' declined' : '')}>
    <div className="grow">
      <div className="pcard-chg-t">{changeTitle(c, S)}{c.routineName ? <span className="dim" style={{ fontWeight: 400 }}> · {c.routineName}</span> : null}</div>
      {vals && <div className="pcard-chg-v"><span className="tag">{vals.before}</span><Icon name="chevronRight" style={{ fontSize: 12, color: 'var(--label-3)' }} /><span className="tag acc">{vals.after}</span></div>}
      <div className="pcard-chg-w">{c.why}</div>
      {stale && <div className="pcard-chg-stale">{t("DOESN_T_MATCH_YOUR_PLAN_ANY_MORE_SO_IT_CAN_T_BE" /* 已与你的计划不符，所以无法应用。 */)}</div>}
    </div>
    {badge}
    {children}
  </div>
}

const Notes = ({ notes }) => !!notes?.length && <div className="pcard-notes">
  {notes.map((n, i) => <div key={i}><Icon name="lightbulb" />{n}</div>)}
</div>

/* ---------------------------------- insights ---------------------------------- */

const BP_LABEL = { back: 'Back muscles', cardio: 'Cardio', chest: 'Chest', 'lower arms': 'Forearms', 'lower legs': 'Calves', neck: 'Neck', shoulders: 'Shoulders', 'upper arms': 'Arms', 'upper legs': 'Legs', waist: 'Core', other: 'Other' }
const bpLabel = bp => translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(BP_LABEL[bp] || bp)

/**
 * The numbers the Coach read, drawn: how much and how often, where the body weight went,
 * which lifts moved, which body parts got the work. Computed on the device for the window the
 * proposal names, so the picture under a suggestion is the evidence behind it, not decoration.
 */
function Insights({ S, window: win, compact }) {
  const ins = useMemo(() => insightsFor(S, win || {}), [S, win?.from, win?.to])
  if (!ins.sessions && !ins.bodyweight.points.length) return null
  const maxBp = ins.bodyParts[0]?.sets || 1
  const bw = ins.bodyweight
  return <div className="ins">
    <div className="ins-tiles">
      <Tile v={ins.sessions} l={t("SESSIONS" /* 训练次数 */)} />
      <Tile v={ins.minutes != null ? ins.minutes : '–'} l={t("MIN_SESSION" /* 分钟 / 次 */)} />
      <Tile v={ins.volume ? kfmt(ins.volume) : '–'} l={t("VOLUME_COUNT" /* 训练量（{0}） */, S.unit)} />
      <Tile v={ins.sets} l={t("SETS" /* 组数 */)} />
    </div>

    {bw.points.length > 1 && <div className="ins-block">
      <div className="ins-h">
        <span>{t("BODY_WEIGHT" /* 体重 */)}</span>
        <span className={'ins-delta' + (bw.delta > 0 ? ' up' : bw.delta < 0 ? ' down' : '')}>
          {bw.delta > 0 ? '+' : ''}{fmtNum(bw.delta)} {S.unit}{bw.goal != null ? ` · ${t("GOAL_A" /* 目标 */)} ${fmtNum(bw.goal)}` : ''}
        </span>
      </div>
      <div className="chart"><LineChart points={bw.points} h={compact ? 96 : 120} unit={S.unit} goal={bw.goal} axes={!compact} /></div>
    </div>}

    {!!ins.strength.length && <div className="ins-block">
      <div className="ins-h"><span>{t("ESTIMATED_ONE_REP_MAX" /* 估算 1RM */)}</span><span className="dim">{t("FIRST_LAST_SESSION" /* 首次 → 末次训练 */)}</span></div>
      {ins.strength.map(x => <div key={x.id} className="ins-row">
        <span className="ins-row-n">{x.name}</span>
        <span className="ins-row-v"><span className="tag">{fmtNum(x.first)}</span><Icon name="chevronRight" /><span className="tag acc">{fmtNum(x.last)}</span></span>
        <span className={'ins-delta' + (x.delta > 0 ? ' up' : x.delta < 0 ? ' down' : '')}>{x.delta > 0 ? '▲' : x.delta < 0 ? '▼' : '•'} {Math.abs(x.pct)}%</span>
      </div>)}
    </div>}

    {!!ins.bodyParts.length && !compact && <div className="ins-block">
      <div className="ins-h"><span>{t("WORK_SETS_BY_BODY_PART" /* 各部位工作组 */)}</span></div>
      {ins.bodyParts.slice(0, 6).map(b => <div key={b.bp} className="ins-bar">
        <span className="ins-bar-l">{bpLabel(b.bp)}</span>
        <span className="ins-bar-t"><i style={{ width: Math.max(4, Math.round(b.sets / maxBp * 100)) + '%' }} /></span>
        <span className="ins-bar-v">{b.sets}</span>
      </div>)}
    </div>}
  </div>
}
const Tile = ({ v, l }) => <div className="ins-tile"><div className="ins-tile-v">{v}</div><div className="ins-tile-l">{l}</div></div>
const kfmt = n => (n >= 10000 ? Math.round(n / 1000) + 'k' : fmtNum(n))

/* ---------------------------------- a debrief ---------------------------------- */

function DebriefBody({ p, S }) {
  const w = p.workout || {}
  const live = useMemo(() => sessionInsights(S, (S.workouts || []).find(x => x.id === w.id) || null), [S, w.id])
  const score = Number.isFinite(p.score) ? Math.max(1, Math.min(10, p.score)) : null
  return <>
    {score != null && <div className="deb-score">
      <div className="deb-ring" style={{ '--pct': score / 10 }}><span>{score}</span><small>/10</small></div>
      <div className="deb-score-t"><b>{scoreWord(score)}</b><span>{w.name || t("WORKOUT" /* 训练 */)}{w.d ? ' · ' + fmtDate(w.d) : ''}</span></div>
    </div>}
    {live && <div className="ins">
      <div className="ins-tiles">
        <Tile v={live.now.sets} l={t("SETS" /* 组数 */)} />
        <Tile v={live.now.minutes != null ? live.now.minutes : '–'} l={t("MINUTES" /* 分钟 */)} />
        <Tile v={live.now.volume ? kfmt(live.now.volume) : '–'} l={t("VOLUME_COUNT" /* 训练量（{0}） */, S.unit)} />
        <Tile v={live.now.prs || '–'} l={t("PRS" /* 纪录 */)} />
      </div>
      {live.then && <div className="ins-cmp">
        {t("VS_LAST_COUNT_ON_COUNT" /* 对比上次 {0}（{1}）： */, w.name || t("SESSION" /* 训练 */), fmtDate(live.prevDate))}{' '}
        <Delta v={live.now.volume - live.then.volume} unit={S.unit} label={t("VOLUME_A" /* 训练量 */)} />
        {live.now.minutes != null && live.then.minutes != null && <Delta v={live.now.minutes - live.then.minutes} unit="min" label={t("TIME_A" /* 时间 */)} />}
      </div>}
      {!!live.lifts.length && <div className="ins-block">
        <div className="ins-h"><span>{t("BEST_SET_ESTIMATED_ONE_REP_MAX" /* 最佳组，估算 1RM */)}</span></div>
        {live.lifts.slice(0, 6).map(x => <div key={x.id} className="ins-row">
          <span className="ins-row-n">{x.name} <span className="dim">{fmtNum(x.w)}×{x.r}</span></span>
          <span className="ins-row-v"><span className="tag acc">{fmtNum(x.est)}</span></span>
          {x.prev != null && <span className={'ins-delta' + (x.est > x.prev ? ' up' : x.est < x.prev ? ' down' : '')}>{x.est > x.prev ? '▲' : x.est < x.prev ? '▼' : '•'} {fmtNum(Math.abs(x.est - x.prev))}</span>}
        </div>)}
      </div>}
    </div>}
    <DebriefList icon="checkCircle" tint="var(--green)" title={t("WHAT_WENT_WELL" /* 做得好的地方 */)} items={p.highlights} />
    <DebriefList icon="warning" tint="var(--yellow)" title={t("WORTH_WATCHING" /* 值得注意 */)} items={p.watch} />
    <DebriefList icon="arrowUp" tint="var(--acc)" title={t("NEXT_TIME" /* 下次 */)} items={p.nextTime} />
  </>
}
const Delta = ({ v, unit, label }) => <span className={'ins-delta' + (v > 0 ? ' up' : v < 0 ? ' down' : '')}>{v > 0 ? '+' : ''}{fmtNum(v)} {unit} {label}</span>
const DebriefList = ({ icon, tint, title, items }) => !!items?.length && <div className="deb-list">
  <div className="deb-list-h" style={{ color: tint }}><Icon name={icon} />{title}</div>
  {items.map((x, i) => <div key={i} className="deb-item">{x}</div>)}
</div>
const scoreWord = s => s >= 9 ? t("EXCELLENT_SESSION" /* 出色的训练 */) : s >= 7 ? t("GOOD_SESSION" /* 不错的训练 */) : s >= 5 ? t("SOLID_SESSION" /* 扎实的训练 */) : t("TOUGH_SESSION" /* 艰难的训练 */)

function DebriefCard({ p, S, update, toast, refresh }) {
  const done = () => {
    update(s => { const ref = recordDebrief(s, p); appendChat(s, { role: 'coach', kind: 'debrief', ref, text: '' }) })
    resolvePending({ accepted: ['debrief'] }).catch(() => {})
    toast(t("KEPT_IN_YOUR_COACH_HISTORY" /* 已保存到教练记录 */))
    refresh()
  }
  return <div className="msg coach" style={{ maxWidth: '100%', width: '100%' }}>
    <div className="pcard">
      <div className="pcard-hd">
        <div className="pcard-eyebrow">{t("WORKOUT_DEBRIEF" /* 训练复盘 */)}</div>
        <h2 className="pcard-h">{p.workout?.name || t("YOUR_LAST_WORKOUT" /* 你上次的训练 */)}</h2>
        {!!p.summary && <p className="pcard-sum">{p.summary}</p>}
      </div>
      <DebriefBody p={p} S={S} />
      <div className="pcard-ft">
        <Button variant="primary" icon="check" onClick={done}>{t("GOT_IT" /* 知道了 */)}</Button>
      </div>
    </div>
    <div className="msg-t">{t("WANT_CHANGES_TO_THE_PLAN_FROM_THIS_ASK_FOR_A_REVIEW_BELOW" /* 想据此调整计划？在下方请求一次审查。 */)}</div>
  </div>
}

/* ---------------------------------- what was decided ---------------------------------- */

/** A decided proposal, folded: one line of what it was and what you did, and a way back in. */
function Recap({ entry, S, openSheet }) {
  const open = () => openSheet(() => <ProposalDetail entry={entry} S={S} />)
  const decisions = entry.decisions || []
  const acc = decisions.filter(d => d.status === 'accepted').length
  const rej = decisions.length - acc
  const kind = entry.kind
  const eyebrow = kind === 'create' ? t("PLAN" /* 计划 */) : kind === 'debrief' ? t("WORKOUT_DEBRIEF" /* 训练复盘 */) : t("SUGGESTIONS" /* 建议 */)
  const state = kind === 'debrief' ? null
    : entry.dismissed ? { cls: 'no', text: t("DECLINED_A" /* 已拒绝 */) }
      : kind === 'create' ? { cls: 'yes', text: t("IMPORTED" /* 已导入 */) }
        : rej ? { cls: 'mix', text: t("COUNT_ACCEPTED_COUNT_DECLINED" /* {0} 项采纳 · {1} 项拒绝 */, acc, rej) } : { cls: 'yes', text: t("COUNT_ACCEPTED" /* {0} 项采纳 */, acc) }
  const title = kind === 'create' ? (entry.bundle?.name || t("COACH_PLAN" /* 教练计划 */))
    : kind === 'debrief' ? (entry.workout?.name || t("WORKOUT" /* 训练 */)) + (entry.score != null ? ` · ${entry.score}/10` : '')
      : tn("COUNT_SUGGESTION" /* {0} 条建议 */, "COUNT_SUGGESTIONS" /* {0} 条建议 */, decisions.length)
  return <button className="recap" onClick={open}>
    <div className="recap-top">
      <span className="pcard-eyebrow">{eyebrow}</span>
      {state && <span className={'recap-state ' + state.cls}>{state.text}</span>}
    </div>
    <div className="recap-t">{title}</div>
    {!!entry.summary && <div className="recap-s">{entry.summary}</div>}
    {kind === 'review' && !!decisions.length && <div className="recap-chips">
      {decisions.slice(0, 4).map(d => <span key={d.id} className={'recap-chip ' + (d.status === 'accepted' ? 'yes' : 'no')}><Icon name={d.status === 'accepted' ? 'check' : 'xmark'} />{changeTitle(d, S)}</span>)}
      {decisions.length > 4 && <span className="recap-chip">+{decisions.length - 4}</span>}
    </div>}
    <div className="recap-more">{t("SHOW_EVERYTHING" /* 查看全部 */)}<Icon name="chevronRight" /></div>
  </button>
}

/** The whole proposal, as it was, read-only. */
function ProposalDetail({ entry, S }) {
  const [tab, setTab] = useState(0)
  const kind = entry.kind
  const b = entry.bundle
  const r = b?.routines?.[Math.min(tab, (b?.routines?.length || 1) - 1)]
  const weekDays = useMemo(() => new Set(Object.keys(b?.week || {}).map(Number)), [b])
  return <div className="pdetail">
    <div className="pcard-hd" style={{ paddingInline: 0 }}>
      <div className="pcard-eyebrow">{kind === 'create' ? t("PLAN" /* 计划 */) : kind === 'debrief' ? t("WORKOUT_DEBRIEF" /* 训练复盘 */) : t("SUGGESTIONS" /* 建议 */)} · {fmtDate(new Date(entry.at).toISOString().slice(0, 10))}</div>
      <h2 className="pcard-h">{kind === 'create' ? (b?.name || t("COACH_PLAN" /* 教练计划 */)) : kind === 'debrief' ? (entry.workout?.name || t("WORKOUT" /* 训练 */)) : tn("COUNT_SUGGESTION" /* {0} 条建议 */, "COUNT_SUGGESTIONS" /* {0} 条建议 */, entry.decisions?.length || 0)}</h2>
      {!!entry.summary && <p className="pcard-sum">{entry.summary}</p>}
      {entry.dismissed && <p className="pcard-sum" style={{ color: 'var(--red)' }}>{t("YOU_DECLINED_THIS" /* 你拒绝了这项。 */)}</p>}
      {!!entry.evidence?.sessions && <p className="pcard-sum" style={{ fontSize: 13 }}>
        {t("BASED_ON_YOUR_LAST_COUNT_SESSIONS" /* 基于你最近 {0} 次训练 */, entry.evidence.sessions)}{entry.evidence.from ? ` · ${fmtDate(entry.evidence.from)} – ${fmtDate(entry.evidence.to)}` : ''}
      </p>}
    </div>

    {kind === 'review' && <>
      <Insights S={S} window={entry.evidence} />
      {(entry.decisions || []).map(d => <ChangeRow key={d.id} c={d} S={S} stale={d.status === 'stale'}
        badge={<span className={'recap-state ' + (d.status === 'accepted' ? 'yes' : 'no')}>{d.status === 'accepted' ? t("ACCEPTED" /* 已采纳 */) : d.status === 'stale' ? t("EXPIRED" /* 已过期 */) : t("DECLINED_A" /* 已拒绝 */)}</span>} />)}
      <Notes notes={entry.notes} />
    </>}

    {kind === 'create' && b && <>
      <WeekStrip days={weekDays} ws={weekStartOf(S)} />
      {b.routines.length > 1 && <div className="pcard-tabs" style={{ paddingInline: 0 }}>
        {b.routines.map((x, i) => <button key={x.id || i} className={'pcard-tab' + (i === tab ? ' on' : '')} onClick={() => setTab(i)}><Icon name={glyphOf(x.emoji)} />{x.name}</button>)}
      </div>}
      {r && <RoutineBlock r={r} unit={S.unit} speedUnit={speedUnitOf(S)} />}
      <p className="pcard-sum" style={{ fontSize: 13 }}>{entry.scheduled ? t("YOUR_WEEK_WAS_SET_TO_THIS_SCHEDULE" /* 你的一周已按此安排设置。 */) : t("IMPORTED_WITHOUT_CHANGING_YOUR_WEEK" /* 已导入，未更改你的一周安排。 */)}</p>
    </>}
    {kind === 'create' && !b && <p className="pcard-sum">{t("THIS_PLAN_WAS_IMPORTED_BEFORE_THE_APP_KEPT_PROPOSALS_ONLY_ITS_SUMMARY" /* 此计划在应用开始保存建议之前导入，只剩下摘要。 */)}</p>}

    {kind === 'debrief' && <DebriefBody p={entry} S={S} />}
    {kind === 'revert' && <p className="pcard-sum">{t("REVERTED_THE_LAST_COACH_CHANGES" /* 已撤销教练上次的更改。 */)}</p>}
    <div style={{ height: 10 }} />
  </div>
}

/** Every proposal ever made, newest first. Nothing the Coach said is gone after a decision. */
function HistorySheet({ S, close, openSheet }) {
  const log = [...(S.coach?.log || [])].reverse()
  const icon = { create: ['clipboard', 'var(--indigo)'], review: ['sparkles', 'var(--acc)'], debrief: ['checkCircle', 'var(--green)'], revert: ['reset', 'var(--blue)'] }
  return <div className="chat-menu">
    <h3>{t("EVERYTHING_THE_COACH_PROPOSED" /* 教练提出的所有建议 */)}</h3>
    {!log.length && <div className="chat-empty">{t("NOTHING_YET_EVERY_PLAN_SUGGESTION_AND_DEBRIEF_WILL_BE_KEPT_HERE_WHETHER" /* 还没有内容。每个计划、建议和复盘都会保存在这里，无论你说了好还是不。 */)}</div>}
    <div className="sect-b">
      {log.map(e => {
        const [ic, tint] = icon[e.kind] || ['sparkles', 'var(--acc)']
        const n = (e.decisions || []).length
        const acc = (e.decisions || []).filter(d => d.status === 'accepted').length
        const title = e.kind === 'create' ? (e.bundle?.name || t("COACH_PLAN" /* 教练计划 */)) + (e.iteration > 1 ? ` · ${t("REVISION_COUNT" /* 第 {0} 版 */, e.iteration)}` : '')
          : e.kind === 'debrief' ? t("DEBRIEF_COUNT" /* 复盘：{0} */, e.workout?.name || t("WORKOUT" /* 训练 */)) + (e.score != null ? ` · ${e.score}/10` : '')
            : e.kind === 'revert' ? t("REVERTED_THE_LAST_COACH_CHANGES" /* 已撤销教练上次的更改。 */)
              : tn("COUNT_SUGGESTION" /* {0} 条建议 */, "COUNT_SUGGESTIONS" /* {0} 条建议 */, n)
        const sub = fmtDate(new Date(e.at).toISOString().slice(0, 10)) + ' · ' + (e.kind === 'debrief' ? String(e.summary || '').slice(0, 60)
          : e.dismissed ? t("DECLINED_A" /* 已拒绝 */) : e.kind === 'create' ? t("IMPORTED" /* 已导入 */) : e.kind === 'revert' ? '' : t("COUNT_ACCEPTED_COUNT_DECLINED" /* {0} 项采纳 · {1} 项拒绝 */, acc, n - acc))
        return <Row key={e.id} icon={ic} iconTint={tint} title={title} subtitle={sub} accessory="chevron"
          onClick={() => { close(); openSheet(() => <ProposalDetail entry={e} S={S} />) }} />
      })}
    </div>
    <div style={{ height: 10 }} />
  </div>
}

/* ---------------------------------- the others here ---------------------------------- */

/**
 * How you sit against everyone else on this instance — medians only, at least three people
 * sharing, nothing that identifies anyone. The admin turns it on for the instance; each person
 * turns it on for themselves; a person who does not share sees nothing either.
 */
function CohortSheet({ S, update, toast }) {
  const [d, setD] = useState(null)
  const [busy, setBusy] = useState(false)
  const load = () => cohortStats().then(setD).catch(e => { toast(e.message || t("COULD_NOT_LOAD" /* 无法加载 */)); setD({ ok: false }) })
  useEffect(() => { load() }, [])
  const share = async v => {
    setBusy(true)
    try { await setCohortShare(v); update(s => { (s.coach = s.coach || emptyCoach()).share = v }); await load() }
    catch (e) { toast(e.message || t("COULD_NOT_SAVE" /* 无法保存 */)) }
    setBusy(false)
  }
  const sharing = !!d?.sharing
  return <div className="chat-menu">
    <h3>{t("COMPARE_WITH_OTHERS_HERE" /* 与这里的其他人比较 */)}</h3>
    <Section footer={t("ONLY_MEDIANS_ACROSS_EVERYONE_WHO_SHARES_NEVER_A_NAME_A_BODY_WEIGHT" /* 只统计共享者之间的中位数，绝不包含姓名、体重或单次训练。关闭后你会立即从数据中移除。 */)}>
      <Row icon="person" iconTint="var(--teal)" title={t("INCLUDE_ME" /* 把我算进去 */)} subtitle={sharing ? t("YOUR_LIFTS_COUNT_TOWARDS_THE_MEDIANS" /* 你的成绩会计入中位数 */) : t("OFF_YOU_SEE_NOTHING_AND_SHARE_NOTHING" /* 已关闭。你看不到也不共享任何内容 */)}>
        <Switch checked={sharing} disabled={busy || !d} onChange={share} />
      </Row>
    </Section>
    {!d && <div className="chat-empty">{t("LOADING" /* 加载中… */)}</div>}
    {d && sharing && !d.ok && <div className="chat-empty">{d.people != null
      ? t("NOT_ENOUGH_PEOPLE_ARE_SHARING_YET_COUNT_OF_COUNT_NEEDED_ROPE_IN" /* 共享的人还不够（需要 {1} 人，目前 {0} 人）。快拉上你的健身伙伴！ */, d.people, d.minPeople)
      : t("NOT_AVAILABLE_RIGHT_NOW" /* 暂时不可用。 */)}</div>}
    {d && sharing && d.ok && <div className="ins" style={{ padding: 0 }}>
      <div className="ins-tiles">
        <Tile v={d.people} l={t("PEOPLE" /* 人数 */)} />
        <Tile v={fmtNum(d.sessionsPerWeek.you)} l={t("YOUR_SESSIONS_WK" /* 你的每周训练 */)} />
        <Tile v={fmtNum(d.sessionsPerWeek.median)} l={t("MEDIAN_WK" /* 每周中位数 */)} />
        <Tile v={d.rankPct != null ? d.rankPct + '%' : '–'} l={t("YOUR_STRENGTH_RANK" /* 你的力量排名 */)} />
      </div>
      {!!d.exercises.length && <div className="ins-block">
        <div className="ins-h"><span>{t("ESTIMATED_ONE_REP_MAX_YOU_VS_MEDIAN" /* 估算 1RM：你的成绩与中位数 */)}</span><span className="dim">{S.unit}</span></div>
        {d.exercises.map(x => {
          const max = Math.max(x.median, x.you || 0) || 1
          return <div key={x.id} className="cmp">
            <div className="cmp-h"><span>{x.name}</span><span className="dim">{x.people} {t("PEOPLE_A" /* 人 */)}</span></div>
            <div className="cmp-bar you"><i style={{ width: Math.round((x.you || 0) / max * 100) + '%' }} /><span>{t("YOU" /* 你 */)} · {x.you != null ? fmtNum(x.you) : '–'}</span></div>
            <div className="cmp-bar"><i style={{ width: Math.round(x.median / max * 100) + '%' }} /><span>{t("MEDIAN" /* 中位数 */)} · {fmtNum(x.median)}</span></div>
          </div>
        })}
      </div>}
      {!d.exercises.length && <div className="chat-empty">{t("NO_EXERCISE_IS_TRAINED_BY_THREE_OR_MORE_PEOPLE_YET" /* 还没有任何动作被三人或以上练过。 */)}</div>}
    </div>}
    <div style={{ height: 10 }} />
  </div>
}

/* ---------------------------------- cadence ---------------------------------- */

const cadenceLabel = coach => {
  const c = coach.cadence && coach.cadence !== 'off' ? coach.cadence : null
  if (!c) return t("OFF" /* 关 */)
  if (c.weekly) return t("WEEKLY" /* 每周 */)
  return t("AFTER_EVERY_FEW_WORKOUTS" /* 每隔几次训练 */)
}

function cadenceSheet(openSheet, update) {
  openSheet(close => <CadenceSheet close={close} update={update} />)
}
function CadenceSheet({ update }) {
  const coach = useStore(s => s.S.coach) || emptyCoach()
  const cadence = coach.cadence && coach.cadence !== 'off' ? coach.cadence : null
  const mode = !cadence ? 'off' : cadence.weekly ? 'weekly' : 'every'
  const setMode = m => update(s => {
    const c = (s.coach = s.coach || emptyCoach())
    c.cadence = m === 'off' ? 'off' : m === 'weekly' ? { weekly: { day: 0, time: '18:00' } } : { everyWorkouts: 4 }
  })
  const patch = fn => update(s => { const c = (s.coach = s.coach || emptyCoach()); fn(c) })
  return <>
    <h3>{t("AUTOMATIC_REVIEWS" /* 自动复盘 */)}</h3>
    <Section footer={mode === 'off' ? t("OFF_THE_COACH_ONLY_LOOKS_WHEN_YOU_ASK" /* 已关闭。教练只在你开口时才看。 */) : t("YOU_ARE_ONLY_NOTIFIED_WHEN_THE_COACH_ACTUALLY_HAS_SOMETHING_TO_SUGGEST" /* 只有当教练确实有建议时才会通知你。 */)}>
      <SelectRow icon="clock" iconTint="var(--purple)" title={t("WHEN" /* 时间 */)} value={mode} onChange={setMode}
        options={[
          { value: 'off', label: t("OFF" /* 关 */) },
          { value: 'weekly', label: t("WEEKLY" /* 每周 */), subtitle: t("ON_A_DAY_AND_TIME_YOU_CHOOSE" /* 在你选定的日期和时间 */) },
          { value: 'every', label: t("AFTER_EVERY_FEW_WORKOUTS" /* 每隔几次训练 */), subtitle: t("AS_SOON_AS_YOU_HAVE_LOGGED_ENOUGH" /* 一旦记录足够就进行 */) }
        ]} />
      {mode === 'weekly' && <>
        <SelectRow icon="calendar" iconTint="var(--orange)" title={t("DAY" /* 星期 */)} value={cadence.weekly.day}
          onChange={v => patch(c => { c.cadence = { weekly: { ...c.cadence.weekly, day: v } } })}
          options={['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'].map((d, i) => ({ value: i, label: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(d) }))} />
        <Row icon="clock" iconTint="var(--purple)" title={t("TIME" /* 时间 */)}>
          <input type="time" className="timef" value={cadence.weekly.time || '18:00'}
            onChange={e => patch(c => { c.cadence = { weekly: { ...c.cadence.weekly, time: e.target.value } } })} />
        </Row>
      </>}
      {mode === 'every' && <SelectRow icon="dumbbell" iconTint="var(--teal)" title={t("AFTER_HOW_MANY_WORKOUTS" /* 每隔多少次训练 */)}
        value={cadence.everyWorkouts || 4}
        onChange={v => patch(c => { c.cadence = { everyWorkouts: v } })}
        options={[3, 4, 5, 6, 8, 10].map(n => ({ value: n, label: tn("COUNT_WORKOUT" /* {0} 次训练 */, "COUNT_WORKOUTS" /* {0} 次训练 */, n) }))} />}
    </Section>
  </>
}
