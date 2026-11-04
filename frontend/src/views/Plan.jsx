import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { DAYN, DAYS, weekOrder, weekStartOf, uid, exCount, routineCount, todayISO, fmtDate } from '../lib/format.js'
import { t , translateValue } from '../lib/i18n.js'
import {
  dayAssignSheet, starterPlanSheet, confirmSheet, menuSheet,
  planHasRoutines, exportPlanFile, printWholePlan, importPlanFile,
} from '../sheets.jsx'
import Icon from '../components/Icon.jsx'
import { Button, Row, Section, Segmented } from '../components/ui.jsx'
import SwipeRow from '../components/SwipeRow.jsx'
import { copyRoutine, deleteRoutine, restoreRoutine, routineSnapshot } from '../lib/routines.js'
import { workoutControls } from '../lib/workout-controls.js'
import { tappable } from '../lib/use-sheet-keyboard.js'
import { useListReorder, moved } from '../lib/use-list-reorder.js'
import { glyphOf, DEFAULT_GLYPH } from '../lib/glyphs.js'
import { DEMO } from '../lib/demo.js'
import { MOBILE } from '../lib/mobile.js'
import { coachAvailable } from '../lib/coach.js'
import { queueOf, queueView } from '../lib/queue.js'
import { deriveSessionName } from '../lib/session-merge.js'
import { markUndone, undoMarks } from '../lib/sync-merge.js'
import {
  scheduleModeOf, queueRecovery, rotationIds, saveRotation, startNewPass, startPass, stopPass,
  chooseRotation, chooseFixedWeek,
} from '../lib/rotation.js'

// Plan has two views (v1.3.11): Schedule (how you train, and when) and Routines (what you
// train). The last one you looked at comes back: a per-device convenience, never synced, so it
// lives in this browser's storage and not in S.
export const PLAN_VIEW_KEY = 'gym_plan_view'
const readView = () => {
  try { return localStorage.getItem(PLAN_VIEW_KEY) === 'routines' ? 'routines' : 'schedule' } catch { return 'schedule' }
}

/* Undo for Plan's two removals (v1.3.11). Both go through the store's normal update, so sync
   sees an ordinary edit (a routine put back clears its own removal stamp, lib/sync-merge.js). */

/** Deletes a routine with an Undo toast in place of a confirm: the toast puts it back exactly,
 *  list place, weekdays, reschedules and loop included (lib/routines.js routineSnapshot). */
export function deleteRoutineWithUndo(id) {
  const st = useStore.getState()
  const snap = routineSnapshot(st.S, id)
  if (!snap) return false
  const before = st.S
  st.update(s => { deleteRoutine(s, id) })
  // What the removal moved (weekdays, reschedules, the loop), for the Undo to mark as put back:
  // a change another device made to one of them before it saw the removal then still wins.
  snap.marks = undoMarks(before, useStore.getState().S)
  useUI.getState().toast(t("COUNT_GONE" /* “{0}”没了。 */, snap.routine.name), { action: t("UNDO" /* 撤销 */), onAction: () => undoDeleteRoutine(snap) })
  return true
}
export function undoDeleteRoutine(snap) {
  let ok = false
  useStore.getState().update(s => { ok = restoreRoutine(s, snap); if (ok && snap.marks) markUndone(s, snap.marks) })
  // False when a sync brought it back first (another device's Undo, or its later edit).
  if (!ok) useUI.getState().toast(t("IT_S_ALREADY_BACK" /* 它已经回来了。 */))
  return ok
}

/** Takes a routine out of the loop (the swipe and the edit-mode minus), with an Undo. The removal
 *  is the editor's own (`setSeq`), which may sweep the routine's future pins or roll a finished
 *  round over; so while the loop is still what the removal left, Undo puts the loop, the round and
 *  the swept pins back as they were. Once something else changed the loop, it just slots the
 *  routine back in at its old place, through the same save an edit uses. */
export function takeOutOfLoop(id, setSeq, seq, label) {
  const at = seq.indexOf(id)
  if (at < 0) return false
  const before = useStore.getState().S
  const snap = structuredClone({ rotation: before.rotation ?? null, queue: before.queue ?? null, dayPlan: before.dayPlan ?? {} })
  setSeq(seq.filter(x => x !== id))
  const after = useStore.getState().S
  const mark = loopMark(after)
  const marks = undoMarks(before, after)
  const name = before.routines.find(r => r.id === id)?.name ?? id
  useUI.getState().toast(t("COUNT_IS_OUT_OF_THE_LOOP" /* “{0}”已移出循环。 */, name), { action: t("UNDO" /* 撤销 */), onAction: () => undoTakeOut({ id, at, label, snap, mark, marks }) })
  return true
}
// What the loop looked like right after a removal: the saved loop, the pass and the mode switch.
const loopMark = S => JSON.stringify([S.rotation ?? null, S.queue ?? null, S.scheduleMode ?? null])
export function undoTakeOut({ id, at, label, snap, mark, marks }) {
  if (!useStore.getState().S.routines.some(r => r.id === id)) {
    useUI.getState().toast(t("TOO_LATE_THAT_ONE_S_GONE" /* 太晚了，那组已经没了 */))
    return false
  }
  useStore.getState().update(s => {
    if (loopMark(s) === mark) {
      s.rotation = snap.rotation
      s.queue = snap.queue
      const pins = Object.entries(snap.dayPlan).filter(([iso]) => s.dayPlan?.[iso] == null)
      if (pins.length) s.dayPlan = { ...(s.dayPlan || {}), ...Object.fromEntries(pins) }
      // Put back exactly: a reorder another device made before it saw the removal still wins.
      if (marks) markUndone(s, marks)
      return
    }
    // Only a loop that is still this app's and still running gets a pass written. After "Fixed
    // week", or with a coach's or planner's queue in charge, a new pass would quietly take over
    // again, so the routine just goes back into the saved loop for the next time it starts.
    const q = queueOf(s)
    const ours = scheduleModeOf(s) === 'rotation' && (!s.queue || (!!q && !!s.rotation && q.rotationId === s.rotation.id))
    if (!ours) {
      const seq = Array.isArray(s.rotation?.sequence) ? s.rotation.sequence : null
      if (seq && !seq.includes(id)) {
        const next = seq.slice()
        next.splice(Math.min(at, next.length), 0, id)
        s.rotation = { ...s.rotation, sequence: next }
      }
      return
    }
    const ids = q?.ids ?? rotationIds(s)
    if (ids.includes(id)) return
    const next = ids.slice()
    next.splice(Math.min(at, next.length), 0, id)
    saveRotation(s, next, s.queue?.label || s.rotation?.label || label)
  })
  return true
}

// The flash a row lands with when a swipe brought it (a duplicate, an undo): one per new value.
let flashSeq = 0

export default function Plan() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const update = useStore(s => s.update)
  const config = useStore(s => s.config)
  const coachMode = useStore(s => s.coachLocal?.mode)
  const user = useStore(s => s.user)
  const fileRef = useRef(null)
  const [view, setViewState] = useState(readView)
  const setView = v => {
    setViewState(v)
    try { localStorage.setItem(PLAN_VIEW_KEY, v) } catch { /* private mode: the view just isn't remembered */ }
  }

  /* The Coach's way in from Plan: its own button in the header (a banner over the week was too
     loud, the last entry of the share menu too hidden). Gated by the same predicate every other
     Coach surface uses, so an instance without the feature sees exactly the header it would have
     without it. */
  const showCoach = coachAvailable(config, user, { demo: DEMO, mobile: MOBILE, coachMode })

  // Share, print, import and starter plans: one menu behind the header button, so the
  // two views below are only about the plan itself.
  const openMenu = () => {
    const has = planHasRoutines(S)
    menuSheet({
      title: t("PLAN" /* 计划 */),
      subtitle: has ? null : t("ADD_AN_EXERCISE_TO_A_ROUTINE_FIRST_AN_EMPTY_PLAN_HAS_NOTHING" /* 请先给训练计划添加动作。空计划没什么可分享的。 */),
      items: [
        { icon: 'share', label: t("EXPORT_PLAN_FILE" /* 导出计划文件 */), sub: t("A_SMALL_FILE_A_FRIEND_CAN_IMPORT_INTO_THEIR_OWN_OPENGYM_ROUTINES" /* 一个小文件，朋友可以导入到自己的 openGym。只有训练计划，不含你的训练记录和体重。 */), disabled: !has, onClick: exportPlanFile },
        { icon: 'note', label: t("PRINT_SAVE_AS_PDF" /* 打印 / 保存为 PDF */), disabled: !has, onClick: printWholePlan },
        { icon: 'download', label: t("IMPORT_A_PLAN_FILE" /* 导入计划文件 */), onClick: () => fileRef.current?.click() },
        { icon: 'clipboard', label: t("LOAD_STARTER_PLAN" /* 加载入门计划 */), onClick: starterPlanSheet },
      ],
    })
  }
  const pickFile = ev => { const f = ev.target.files[0]; ev.target.value = ''; importPlanFile(f) }

  const mode = scheduleModeOf(S)

  return <div className="narrow plan">
    <div className="hdr">
      <div><h1>{t("PLAN" /* 计划 */)}</h1><div className="sub">{mode === 'rotation' ? t("YOUR_ROUTINES_IN_A_LOOP" /* 你的训练计划循环进行 */) : t("YOUR_WEEKLY_ROUTINE" /* 你的每周安排 */)}</div></div>
      <div className="hdr-actions">
        {showCoach && <Button size="sm" variant="tinted" icon="sparkles" onClick={() => nav('/coach')}>{t("COACH" /* 教练 */)}</Button>}
        <button className="iconbtn" onClick={openMenu} aria-label={t("PLAN_OPTIONS" /* 计划选项 */)} title={t("PLAN_OPTIONS" /* 计划选项 */)}><Icon name="share" /></button>
      </div>
    </div>
    <input ref={fileRef} type="file" accept="application/json,.json" onChange={pickFile} hidden />
    <Segmented className="plan-views" value={view} onChange={setView}
      options={[{ value: 'schedule', label: t("SCHEDULE" /* 训练安排 */) }, { value: 'routines', label: t("ROUTINES" /* 训练计划 */) }]} />
    {view === 'routines'
      ? <Routines S={S} update={update} nav={nav} />
      : <Schedule S={S} update={update} nav={nav} mode={mode} />}
  </div>
}

/* ================================ Schedule ================================ */

function Schedule({ S, update, nav, mode }) {
  const [editLoop, setEditLoop] = useState(false)
  /* The rotation editor. What it shows is the live pass when there is one, otherwise the saved
     sequence — S.rotation is only a definition, so the pass is the truth whenever it exists.
     Every edit writes straight through saveRotation: an edit IS the save (and, for a queue
     somebody else wrote, the adoption), so there is no half-edited state to lose. `since` and
     `startsOn` carry over, so progress already logged survives a reorder. */
  const liveQ = queueOf(S)
  const seq = liveQ?.ids ?? rotationIds(S)
  // A loop the app makes has no name of its own: Home shows it as 'Rotation' in the language on
  // screen. Stored as text, it stayed in the language it was made in (QA 2026-10-06).
  const seqLabel = liveQ?.label || S.rotation?.label || ''
  // Ownership, not presence: a planner's queue has no rotationId, or one that does not match the
  // saved rotation here — that's what makes it someone else's to write, not this app's.
  const managed = !!liveQ && !!S.rotation && liveQ.rotationId === S.rotation.id
  const external = !!liveQ && !managed
  const recovery = queueRecovery(S)
  const qv = liveQ ? queueView(S, todayISO()) : null

  // "How you train" is the same switch as Settings' (lib/rotation.js chooseRotation /
  // chooseFixedWeek), on the same keys. Leaving a running loop asks first: its progress goes,
  // the loop itself and the weekdays stay. With nothing running there is nothing to lose.
  const setMode = v => {
    if (v === mode) return
    if (v === 'rotation') { update(s => { chooseRotation(s) }); return }
    if (!liveQ) { update(s => { chooseFixedWeek(s) }); return }
    confirmSheet({
      title: t("BACK_TO_A_FIXED_WEEK" /* 回到固定周？ */),
      message: t("THE_LOOP_STOPS_YOUR_WEEKDAYS_STAY_AS_THEY_ARE_AND_THE_LOOP" /* 循环将停止。你的每周安排保持不变，循环会保存以后再用。 */),
      confirmText: t("USE_FIXED_WEEK" /* 使用固定周 */),
      onConfirm: () => update(s => { chooseFixedWeek(s) }),
    })
  }

  const setSeq = ids => update(s => {
    // Emptying the sequence stops the pass but stays on Rotation with an empty loop ('No rotation
    // yet'), so taking out the last routine to swap it for another never throws you onto the
    // weekday grid. Leaving the rotation is the 'How you train' switch's job.
    if (ids.length) saveRotation(s, ids, seqLabel)
    else {
      stopPass(s)
      if (s.rotation) s.rotation = { ...s.rotation, sequence: [] }
      s.scheduleMode = 'rotation'
    }
  })
  const loopReorder = useListReorder(seq.length, (from, to) => setSeq(moved(seq, from, to)))
  const takeOut = id => takeOutOfLoop(id, setSeq, seq, seqLabel)
  const swipe = workoutControls(S).swipeSets && !external
  const addToSeq = () => menuSheet({
    title: t("ADD_TO_THE_ROTATION" /* 添加到轮换 */),
    items: S.routines.filter(r => !seq.includes(r.id)).map(r => ({
      icon: glyphOf(r.emoji), label: r.name, onClick: () => setSeq([...seq, r.id]),
    })),
  })
  // The only path from a coach-written queue into a managed one: behind a confirmation that says
  // what happens — the coach gives up control: this app owns the queue and refills it itself, and a
  // later week written by the coach's app simply replaces it (the whole queue object, token and all).
  // The rotation takes a name of its own here rather than the planner's (e.g. "US W1") — that
  // name is this one pass's, and refillAfter would otherwise repeat it on every pass after it.
  // A loop of your own saved here is overwritten by the adoption, so the confirm says so.
  const ownSeq = S.rotation?.sequence || []
  const replacesOwn = ownSeq.length > 0 && (ownSeq.length !== seq.length || ownSeq.some((id, i) => id !== seq[i]))
  const adopt = () => confirmSheet({
    title: t("USE_THIS_ROTATION_A" /* 使用此轮换？ */),
    message: t("YOUR_COACH_GIVES_UP_CONTROL_OF_THIS_WEEK_OPENGYM_OWNS_THE_QUEUE" /* 你的教练放弃对本周的控制权：从现在起队列归 openGym 所有，它会在这些训练全部完成后自动重复它们。教练的应用推送的新一周会替换这个轮换。 */)
      + (replacesOwn ? ' ' + t("YOUR_OWN_LOOP_GETS_REPLACED" /* 你自己的循环会被替换。 */) : ''),
    confirmText: t("USE_THIS_ROTATION" /* 使用此轮换 */),
    onConfirm: () => update(s => saveRotation(s, seq, '')),
  })

  const ws = weekStartOf(S)
  const todayDow = new Date().getDay()
  const routineOf = id => S.routines.find(x => x.id === id)
  const dayRoutines = d => [].concat(S.week[d] || []).map(routineOf).filter(Boolean)
  // One weekday: what is on it at a glance, and a tap to change it (dayAssignSheet picks one
  // routine, several for a combined day, or a rest day).
  const dayRow = (d, rs = dayRoutines(d)) => {
    return <div key={d} className="item plan-day" data-day={d} aria-label={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYN[d])} {...tappable(() => dayAssignSheet(d))}>
      <span className={'plan-day-n' + (d === todayDow ? ' today' : '')} aria-hidden="true">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYS[d])}</span>
      <span className={'lrow-i' + (rs.length ? '' : ' rest')}><Icon name={rs.length ? glyphOf(rs[0].emoji) : 'moon'} /></span>
      <div className="grow">
        <div className="tt">{rs.length ? deriveSessionName(rs.map(r => r.name)) : t("REST_DAY" /* 休息日 */)}</div>
        <div className="ss">{rs.length === 1 ? exCount(rs[0].ex.length) : rs.length ? routineCount(rs.length) : t("TAP_TO_PLAN_SOMETHING" /* 点一下来安排训练 */)}</div>
      </div>
      <Icon name="chevronRight" className="chev" />
    </div>
  }
  // Beside a loop, a weekday shows only what it adds to it: a routine that is in the loop already
  // is the loop's session, the same rule Home follows (effectiveRoutineIds, history.js).
  const extraRoutines = d => dayRoutines(d).filter(r => !seq.includes(r.id))
  const plannedDays = weekOrder(ws).filter(d => extraRoutines(d).length)
  const doneCount = qv ? qv.items.filter(i => i.state === 'done').length : 0
  const stateWord = item => item.state === 'pinned' ? fmtDate(item.on, true)
    : { done: t("DONE" /* 完成 */), next: t("UP_NEXT" /* 下一个 */), later: t("LATER" /* 稍后 */) }[item.state]
  const editing = editLoop && !external

  return <>
    <Section className="plan-mode" footer={mode === 'rotation'
      ? t("ROUTINES_IN_A_LOOP_WHATEVER_IS_NEXT_STAYS_NEXT_UNTIL_YOU_TRAIN" /* 训练计划按循环进行。下一个会一直排在下一个，直到你完成它，不管哪天。 */)
      : t("THE_SAME_ROUTINES_ON_THE_SAME_WEEKDAYS_EVERY_WEEK" /* 每周同样的日子，同样的训练计划。 */)}>
      <Row icon="repeat" iconTint="var(--orange)" title={t("HOW_YOU_TRAIN" /* 训练方式 */)}>
        {/* A planner's own queue is not this app's to switch off: text, not a control. */}
        {external
          ? <span className="small dim plan-mode-locked">{t("ROTATION" /* 轮换 */)} · {t("EXTERNALLY_MANAGED" /* 由外部管理 */)}</span>
          : <Segmented className="seg-inline" value={mode} onChange={setMode}
              options={[{ value: 'week', label: t("FIXED_WEEK" /* 固定周 */) }, { value: 'rotation', label: t("ROTATION" /* 轮换 */) }]} />}
      </Row>
    </Section>

    {!S.routines.length && <div className="empty plan-empty">
      <div className="ico"><Icon name="clipboard" /></div>{t("NO_ROUTINES_YET" /* 还没有训练计划。 */)}<br />{t("MAKE_ONE_OR_GRAB_THE_STARTER_PLAN_TO_GET_GOING" /* 自己建一个，或者拿入门计划开始。 */)}
      <div style={{ marginTop: 12 }}><Button icon="clipboard" onClick={starterPlanSheet}>{t("LOAD_STARTER_PLAN" /* 加载入门计划 */)}</Button></div>
    </div>}

    {/* A queue payload that arrived unusable: a fix-up, shown whichever way you train. Giving it
        up also gives up S.scheduleMode='rotation', or the loop would sit there with no queue. */}
    {recovery && <div className="empty">
      {t("THIS_ROTATION_COULDN_T_BE_READ_ANOTHER_DEVICE_MAY_HAVE_WRITTEN_IT" /* 无法读取此轮换。可能是另一台设备写入的。 */)}
      <div style={{ marginTop: 10 }}>
        <Button size="sm" variant="tinted" aria-label={t("DISCARD_IT" /* 丢弃它 */)} onClick={() => update(s => { s.queue = null; s.scheduleMode = 'week' })}>{t("DISCARD_IT" /* 丢弃它 */)}</Button>
      </div>
    </div>}

    {mode === 'week' ? <>
      <h4 className="sec">{t("THIS_WEEK" /* 本周 */)}</h4>
      <div className="list plan-week">{weekOrder(ws).map(d => dayRow(d))}</div>
      <p className="sect-f">{t("WANT_TWO_ROUTINES_ON_ONE_DAY_TAP_THE_DAY_AND_PICK_BOTH" /* 一天想练两个训练计划？点一下那天，两个都选上。 */)}</p>
    </> : <div className="rotation">
      <div className="row between plan-sec-h">
        <h4 className="sec">{t("THE_LOOP" /* 循环 */)}{external && <span className="tag" style={{ marginInlineStart: 8 }}>{t("EXTERNALLY_MANAGED" /* 由外部管理 */)}</span>}</h4>
        {/* A coach's own queue is read-only here: the one way to change what it holds is to
            adopt it first ("Use this rotation" below), never a tap on one of its rows. */}
        {!external && <div className="row plan-sec-acts" style={{ gap: 6 }}>
          {seq.length > 0 && <button className="plan-textbtn" aria-pressed={editLoop} onClick={() => setEditLoop(e => !e)}>{editLoop ? t("DONE" /* 完成 */) : t("EDIT" /* 编辑 */)}</button>}
          <Button size="sm" variant="tinted" icon="plus" aria-label={t("ADD_ROUTINE_TO_THE_ROTATION" /* 将训练计划添加到轮换 */)}
            disabled={S.routines.every(r => seq.includes(r.id))} onClick={addToSeq}>{t("ADD" /* 添加 */)}</Button>
        </div>}
      </div>
      {seq.length ? <div className="list plan-loop" ref={loopReorder.listRef}>
        {seq.map((id, i) => {
          const r = routineOf(id)
          const item = qv?.items[i]
          // The loop's swipe is remove-only (v1.3.11): a routine is in the loop once, so there is
          // nothing to copy. The row the reorder measures is the swipe's outer element.
          const reorderProps = { 'data-reorder-row': '', style: loopReorder.rowStyle(i) }
          const row = <div {...(swipe ? {} : { key: id, ...reorderProps })} className={'item rotation-row' + (item?.state === 'done' ? ' is-done' : '')}>
            {editing && <button className="plan-minus" aria-label={t("REMOVE_COUNT_A" /* 移除 {0} */, r?.name ?? id)} title={t("REMOVE" /* 移除 */)}
              onClick={() => takeOut(id)}><Icon name="minus" /></button>}
            <span className={'plan-order' + (item?.state === 'next' ? ' next' : '')}>{item?.state === 'done' ? <Icon name="check" /> : i + 1}</span>
            <span className="lrow-i"><Icon name={glyphOf(r?.emoji)} /></span>
            <div className="grow" style={{ minWidth: 0 }}>
              <div className="tt">{r?.name ?? id}</div>
              <div className="ss">{item ? stateWord(item) : r ? exCount(r.ex.length) : ''}</div>
            </div>
            {editing && seq.length > 1 && <button className="plan-handle" aria-label={t("MOVE_COUNT" /* 移动 {0} */, r?.name ?? id)} title={t("DRAG_TO_REORDER" /* 拖动调整顺序 */)}
              {...loopReorder.handle(i)}><Icon name="chevronsUpDown" /></button>}
          </div>
          return swipe
            ? <SwipeRow key={id} {...reorderProps} className="swrow-item" deleteLabel={t("REMOVE" /* 移除 */)} deleteIcon="minus"
              onDelete={() => takeOut(id)}>{row}</SwipeRow>
            : row
        })}
      </div> : <div className="empty">{t("NO_ROTATION_YET_ADD_ROUTINES_IN_THE_ORDER_YOU_WANT_TO_TRAIN" /* 还没有轮换。按你想训练的顺序添加训练计划。第一个还没记录的训练计划会一直排在下一个。 */)}</div>}
      {seq.length > 0 && <p className="sect-f">
        {qv ? (qv.waiting ? t("NEXT_ROUND_STARTS_COUNT" /* 下一轮从 {0} 开始。 */, fmtDate(qv.startsOn, true)) : t("COUNT_OF_COUNT_DONE_THIS_ROUND" /* 本轮已完成 {0}/{1}。 */, doneCount, qv.items.length)) + ' ' : ''}
        {external ? '' : editing ? t("DRAG_TO_REORDER_TAP_THE_MINUS_TO_TAKE_ONE_OUT" /* 拖动可调整顺序。点减号可移除一个。 */) : t("TRAINED_OUT_OF_ORDER_JUST_PICK_ANOTHER_ROUTINE_ON_HOME" /* 没按顺序练？在首页选另一个训练计划就行。 */)}
      </p>}
      <div className="row" style={{ gap: 8, marginTop: 4, flexWrap: 'wrap' }}>
        {external && <Button size="sm" variant="tinted" aria-label={t("USE_THIS_ROTATION" /* 使用此轮换 */)} onClick={adopt}>{t("USE_THIS_ROTATION" /* 使用此轮换 */)}</Button>}
        {/* Throws the current round away and starts the saved loop again today; nothing logged
            before this moment counts for it (startNewPass, the strict pass). */}
        {!!liveQ && !external && <Button size="sm" icon="reset" aria-label={t("START_THE_LOOP_OVER" /* 重新开始循环 */)}
          onClick={() => update(s => startNewPass(s))}>{t("START_THE_LOOP_OVER" /* 重新开始循环 */)}</Button>}
        {/* Rotation chosen and a loop saved, but no round running (it was stopped elsewhere). */}
        {!liveQ && !recovery && seq.length > 0 && <Button size="sm" variant="tinted" icon="play" aria-label={t("START_THE_LOOP" /* 开始循环 */)}
          onClick={() => update(s => startPass(s))}>{t("START_THE_LOOP" /* 开始循环 */)}</Button>}
      </div>
      {/* The weekday routines ride along beside a loop (effectiveRoutineIds, history.js) and feed
          the same tally (weekTally, queue.js), so the days that still add one stay in sight; a
          day whose only routines are in the loop already adds nothing and is left out. */}
      {plannedDays.length > 0 && <>
        <h4 className="sec">{t("ALSO_ON_FIXED_DAYS" /* 固定日也有安排 */)}</h4>
        <div className="list plan-week">{plannedDays.map(d => dayRow(d, extraRoutines(d)))}</div>
        <p className="sect-f">{t("THESE_COUNT_ON_TOP_OF_THE_LOOP_TAP_A_DAY_TO_CHANGE" /* 这些在循环之外另算。点某一天可更改或清空。 */)}</p>
      </>}
    </div>}

    {/* Weekly muscle volume is analysis: it moved to Stats, next to Muscle balance. Stats only
        shows that card once there is a routine, so the link waits for one too. */}
    {S.routines.length > 0 && <Section className="plan-link">
      <Row icon="chart" iconTint="var(--indigo)" title={t("WEEKLY_MUSCLE_VOLUME" /* 每周肌群训练量 */)} subtitle={t("NOW_IN_STATS_NEXT_TO_MUSCLE_BALANCE" /* 现在在统计里，肌肉平衡旁边 */)}
        accessory="chevron" onClick={() => nav('/stats?focus=weekly-volume')} />
    </Section>}
  </>
}

/* ================================ Routines ================================ */

function Routines({ S, update, nav }) {
  const [edit, setEdit] = useState(false)
  const [flash, setFlash] = useState(null)
  const swipe = workoutControls(S).swipeSets
  const routines = S.routines
  // The order of this list is the order of `S.routines`, and every other screen reads the same
  // array (the Start screen, the day sheets, the routine pickers), so moving a routine here moves
  // it everywhere (#142). Reordering lives behind Edit, like on an iPhone.
  const reorder = useListReorder(routines.length, (from, to) => update(s => {
    if (to < 0 || to >= s.routines.length) return
    const [m] = s.routines.splice(from, 1)
    s.routines.splice(to, 0, m)
  }))

  const addRoutine = () => {
    const r = { id: uid(), name: t("NEW_ROUTINE" /* 新建训练计划 */), emoji: DEFAULT_GLYPH, ex: [] }
    update(s => { s.routines.push(r) })
    nav('/plan/r/' + r.id)
  }
  // The same delete as RoutineEdit's "Delete routine" button (lib/routines.js), with an Undo in
  // place of its confirm (v1.3.11): the swipe and the edit-mode minus both land here.
  const remove = r => deleteRoutineWithUndo(r.id)
  // The swipe's other side: a copy right below the original, named the way "Copy routine" names
  // one, and staying on this list rather than opening it.
  const duplicate = r => {
    const copy = copyRoutine(r, t("COPY" /* 副本 */))
    update(s => {
      const at = s.routines.findIndex(x => x.id === r.id)
      s.routines.splice(at < 0 ? s.routines.length : at + 1, 0, copy)
    })
    setFlash({ id: copy.id, n: ++flashSeq })
    // With its own Undo: the toast takes the place of any Undo still showing (one toast at a
    // time), so the newest swipe is at least the one you can take back.
    useUI.getState().toast(t("COPIED_AS_COUNT" /* 已复制为“{0}”。 */, copy.name), { action: t("UNDO" /* 撤销 */), onAction: () => {
      update(s => { if (s.routines.some(x => x.id === copy.id)) deleteRoutine(s, copy.id) })
    } })
  }
  // The weekdays a routine is on, short, in the order the week runs.
  const order = weekOrder(weekStartOf(S))
  const daysOf = id => order.filter(d => [].concat(S.week[d] || []).includes(id)).map(d => translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYS[d]))
  const sub = r => [exCount(r.ex.length), daysOf(r.id).join(', ')].filter(Boolean).join(' · ')

  return <>
    <div className="row between plan-sec-h plan-routines-bar">
      {routines.length > 0
        ? <button className="plan-textbtn" aria-pressed={edit} onClick={() => setEdit(e => !e)}>{edit ? t("DONE" /* 完成 */) : t("EDIT" /* 编辑 */)}</button>
        : <span />}
      <Button size="sm" variant="tinted" icon="plus" onClick={addRoutine}>{t("NEW_ROUTINE" /* 新建训练计划 */)}</Button>
    </div>
    {routines.length ? <>
      {edit
        ? <div className="list routine-list plan-routines is-editing" ref={reorder.listRef}>{routines.map((r, i) =>
          <div key={r.id} data-reorder-row className="item plan-routine" style={reorder.rowStyle(i)}>
            <button className="plan-minus" aria-label={t("DELETE_COUNT_A" /* 删除 {0} */, r.name)} title={t("DELETE_ROUTINE_A" /* 删除训练计划 */)} onClick={() => remove(r)}><Icon name="minus" /></button>
            <span className="lrow-i"><Icon name={glyphOf(r.emoji)} /></span>
            <div className="grow"><div className="tt">{r.name}</div><div className="ss">{sub(r)}</div></div>
            {routines.length > 1 && <button className="plan-handle" aria-label={t("MOVE_COUNT" /* 移动 {0} */, r.name)} title={t("DRAG_TO_REORDER" /* 拖动调整顺序 */)}
              {...reorder.handle(i)}><Icon name="chevronsUpDown" /></button>}
          </div>)}</div>
        : <div className="list routine-list plan-routines">{routines.map(r => {
          const row = <div key={r.id} className="item plan-routine" {...tappable(() => nav('/plan/r/' + r.id))}>
            <span className="lrow-i"><Icon name={glyphOf(r.emoji)} /></span>
            <div className="grow"><div className="tt">{r.name}</div><div className="ss">{sub(r)}</div></div>
            <Icon name="chevronRight" className="chev" /></div>
          // Swipe (v1.3.11, Settings → Swipe actions): toward the start deletes with an Undo,
          // toward the end duplicates. Edit's minus and the routine's own page stay the way in
          // for a keyboard and a screen reader.
          return swipe
            ? <SwipeRow key={r.id} className="swrow-item" copyLabel={t("DUPLICATE" /* 复制一份 */)}
              onDelete={() => remove(r)} onCopy={() => duplicate(r)}
              flash={flash?.id === r.id ? flash.n : 0}>{row}</SwipeRow>
            : row
        })}</div>}
      <p className="sect-f">{edit ? t("DRAG_TO_REORDER_TAP_THE_MINUS_TO_DELETE" /* 拖动可调整顺序。点减号可删除。 */) : t("TAP_A_ROUTINE_TO_EDIT_IT_REORDER_AND_DELETE_ARE_BEHIND_EDIT" /* 点训练计划即可编辑。调整顺序和删除在“编辑”里。 */)}</p>
    </> : <>
      <div className="empty"><div className="ico"><Icon name="clipboard" /></div>{t("NO_ROUTINES_YET" /* 还没有训练计划。 */)}<br />{t("MAKE_ONE_OR_GRAB_THE_STARTER_PLAN_TO_GET_GOING" /* 自己建一个，或者拿入门计划开始。 */)}</div>
      <Button icon="clipboard" onClick={starterPlanSheet}>{t("LOAD_STARTER_PLAN" /* 加载入门计划 */)}</Button>
    </>}
  </>
}
