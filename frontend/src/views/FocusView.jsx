import { useState } from 'react'
import { useStore } from '../store/useStore.js'
import { exOr } from '../lib/exercises.js'
import { clampIncline, hasIncline, inclineFits, INCLINE_MAX, INCLINE_STEP } from '../lib/incline.js'
import { exerciseNameFor, t , translateValue } from '../lib/i18n.js'
import { fmtDate, fmtNum, fmtPlate } from '../lib/format.js'
import { EFFORT, effortOf, modeOf } from '../lib/history.js'
import { lastEntryFor, pinnedNoteFor, setsRepsOf } from '../lib/history.js'
import { effortColor, rirOf } from '../lib/effort.js'
import { progressionGuidance } from '../lib/progression-copy.js'
import {
  addCluster, addDrop, addSideCluster, addSideDrop, clustersOf, dropsOf,
  isFailureSet, isSideSet, isWarmupRow, nextBurstReps, toggleFailure, nextDropWeight, setClusterAt,
  setDropAt, setSideClusterAt, setSideDropAt, setSideField,
} from '../lib/workout-model.js'
import { weightIncrement, stepWeight } from '../lib/progression.js'
import { speedUnitOf, toSpeed, fromSpeed } from '../lib/speed.js'
import { effortPickerSheet, exerciseDetailSheet, exerciseHistorySheet, exerciseNoteSheet, menuSheet, barWeightSheet } from '../sheets.jsx'
import { baseWeightFor, inventoryFor, loadKindFor, rowLoad } from '../lib/plates.js'
import { ownedWeightsFor, stepOwned } from '../lib/dumbbells.js'
import Icon from '../components/Icon.jsx'
import { Button, Stepper } from '../components/ui.jsx'
import './FocusView.css'

const firstIncomplete = entry => {
  const index = entry.sets.findIndex(set => !set.done)
  return index < 0 ? Math.max(0, entry.sets.length - 1) : index
}

const clampSet = (entry, index) => Math.min(Math.max(index, 0), Math.max(0, entry.sets.length - 1))

const supersetSequence = (entries, unit) => {
  const rounds = Math.max(0, ...unit.map(index => entries[index]?.sets?.length || 0))
  return Array.from({ length: rounds }, (_, setIdx) =>
    unit.filter(entryIdx => entries[entryIdx]?.sets?.[setIdx]).map(entryIdx => ({ entryIdx, setIdx })),
  ).flat()
}

const toggleWarmup = row => {
  const next = { ...row }
  if (isWarmupRow(next)) {
    delete next.phase
    delete next.warmup
  } else {
    next.phase = 'warmup'
    // A warm-up is never taken to failure (isFailureSet ignores it anyway); dropping the mark
    // keeps it from coming back if the row is made a work set again.
    delete next.failure
  }
  return next
}

const addDropTo = (row, target) => {
  if (isSideSet(row)) return addSideDrop(row, target?.intensifier?.pct)
  const drops = dropsOf(row).length ? dropsOf(row) : row.drops || []
  const base = drops.at(-1)?.w ?? row.w ?? 0
  return addDrop(row, { w: nextDropWeight(base, target?.intensifier?.pct), r: row.r || 0 })
}

const addBurstTo = (row, restSec) => {
  if (isSideSet(row)) return addSideCluster(row, restSec)
  const clusters = clustersOf(row).length ? clustersOf(row) : row.clusters || []
  const reps = nextBurstReps(clusters.at(-1)?.r ?? row.r ?? 0)
  return { ...addCluster(row, { r: reps, restSec }), r: (row.r || 0) + reps }
}

function Prescription({ entry, setIdx, unit, fallbackRest, children }) {
  const target = entry.target || {}
  const reps = target.repsMin > 0 ? `${target.repsMin}–${target.reps}` : target.reps > 0 ? String(target.reps) : ''
  const load = target.weight > 0
    ? `@ ${fmtNum(target.weight)}${target.weightMax > target.weight ? `–${fmtNum(target.weightMax)}` : ''} ${unit}`
    : ''
  const rpe = target.rpeMin > 0
    ? `RPE ${fmtNum(target.rpeMin)}${target.rpeMax > target.rpeMin ? `–${fmtNum(target.rpeMax)}` : ''}`
    : ''
  const restSeconds = target.restSec > 0 ? target.restSec : fallbackRest
  const rest = restSeconds > 0 ? t("COUNT_REST" /* 休息 {0} */, t("DURATION_SECONDS_SHORT" /* {0} 秒 */, restSeconds)) : ''
  const badges = [reps && t("COUNT_REPS_A" /* {0} 次 */, reps), load, rpe, rest, target.tempo].filter(Boolean)

  return <div className="focus-prescription">
    <span className="focus-badge focus-progress">{t("SET_COUNT_OF_COUNT" /* 第 {0}/{1} 组 */, setIdx + 1, entry.sets.length)}</span>
    {badges.map(label => <span className="focus-badge" key={label}>{label}</span>)}
    {children}
  </div>
}

function PlanBadge({ entry, mode }) {
  const planned = entry.planned && mode !== 'cardio' ? entry.planned : null
  if (!planned) return null
  const today = entry.target || {}
  const todaySets = today.sets || planned.sets || 1
  const inPlan = mode === 'time'
    ? today.sec == null || today.sec === planned.sec
    : today.reps == null || (planned.repsMin > 0 ? today.reps >= planned.repsMin && today.reps <= planned.reps : today.reps === planned.reps)
  if (todaySets === (planned.sets || 1) && inPlan)
    return entry.carried ? <span className="focus-badge plan">{t("REPS_FROM_YOUR_LAST_SESSION" /* 次数沿用上次训练 */)}</span> : null
  return <span className="focus-badge plan">{t("PLAN_COUNT" /* 计划：{0} */, setsRepsOf({ ...planned, mode }))}</span>
}

function PlateBadge({ S, entry, set }) {
  if (modeOf({ ...(entry.target || {}), id: entry.id }) !== 'reps') return null
  const load = rowLoad(loadKindFor(S, { ...(entry.target || {}), id: entry.id }), set.w, baseWeightFor(S, entry.id), inventoryFor(S))
  if (!load) return null
  const stack = load.plates.map(fmtPlate).join(' + ')
  const text = load.barOnly ? t("BAR_ONLY" /* 空杠 */)
    : load.kind === 'pairs' ? t("COUNT_PER_SIDE" /* 每侧 {0} */, stack || '–') : t("LOAD_COUNT_A" /* 负重 {0} */, stack || '–')
  return <span className="focus-badge plate"><Icon name="plate" />{text}{load.missing > 0 && <> · <span className="short">{t("COUNT_SHORT" /* 差 {0} */, fmtPlate(load.missing) + ' ' + S.unit)}</span></>}</span>
}

export default function FocusView({
  entryIdx, unit, onToggle, onToggleSide, onField, onMutateSet, onStartTimed,
  onAddWarmup, onRemoveSetAt, onProgressionSettings, onSwap, onRemoveExercise,
  onNoProg, busy, onSelectEntry, onAdvanceUnit, onPairPrev, onPairNext, onUnpair, pointerEpoch,
}) {
  const S = useStore(state => state.S)
  const speedUnit = speedUnitOf(S)
  const entry = S.active.entries[entryIdx]
  const ex = exOr(entry.id)
  const last = lastEntryFor(S, entry.id)
  const pinnedNote = pinnedNoteFor(S, entry.id)
  const guidance = progressionGuidance(entry.plan)
  // Exercise operations use indexes, so their local-only epoch discards stale pointers instead
  // of letting a moved, removed, or newly inserted entry inherit one.
  const [pointerState, setPointerState] = useState(() => ({ epoch: pointerEpoch, pointers: new Map() }))
  const pointers = pointerState.epoch === pointerEpoch ? pointerState.pointers : new Map()
  const stored = pointers.get(entryIdx)
  const setIdx = clampSet(entry, Number.isInteger(stored) ? stored : firstIncomplete(entry))
  const set = entry.sets[setIdx]
  const firstOpenSet = firstIncomplete(entry)
  const locked = !set.done && setIdx > firstOpenSet
  const readOnly = set.done || locked
  const mode = modeOf({ ...(entry.target || {}), id: entry.id })
  const effort = effortOf(S)
  const effortField = EFFORT[effort]?.f
  const effortValue = effortField ? set[effortField] ?? null : null
  const effortTint = effortValue == null ? null : effortColor(rirOf({ [effortField]: effortValue }))
  const loadStep = weightIncrement({ ...(entry.target || {}), id: entry.id }, S.unit)
  // Bell to bell over the dumbbells you own, when the profile lists them (issue #376).
  const owned = mode === 'reps' ? ownedWeightsFor(S, { ...(entry.target || {}), id: entry.id }) : null
  const stepLoad = owned ? (v, _step, dir) => stepOwned(owned, v, dir) : stepWeight
  const selectSet = index => setPointerState(current => {
    const next = new Map(current.epoch === pointerEpoch ? current.pointers : [])
    next.set(entryIdx, clampSet(entry, index))
    return { epoch: pointerEpoch, pointers: next }
  })
  const sequence = unit.length > 1 ? supersetSequence(S.active.entries, unit) : []
  const sequenceIdx = sequence.findIndex(item => item.entryIdx === entryIdx && item.setIdx === setIdx)
  const clearPointer = index => setPointerState(current => {
    if (current.epoch !== pointerEpoch) return { epoch: pointerEpoch, pointers: new Map() }
    if (!current.pointers.has(index)) return current
    const next = new Map(current.pointers)
    next.delete(index)
    return { epoch: pointerEpoch, pointers: next }
  })
  const selectSequence = index => {
    const item = sequence[index]
    if (!item) return
    setPointerState(current => {
      const next = new Map(current.epoch === pointerEpoch ? current.pointers : [])
      next.set(item.entryIdx, item.setIdx)
      return { epoch: pointerEpoch, pointers: next }
    })
    onSelectEntry(item.entryIdx)
  }
  const drops = dropsOf(set).length ? dropsOf(set) : Array.isArray(set.drops) ? set.drops : []
  const bursts = clustersOf(set).length ? clustersOf(set) : Array.isArray(set.clusters) ? set.clusters : []

  const sideFields = side => {
    const sideSet = set.sides[side]
    const change = (field, value) => onMutateSet(setIdx, row => setSideField(row, side, field, value))
    const sideDrops = dropsOf(sideSet).length ? dropsOf(sideSet) : Array.isArray(sideSet.drops) ? sideSet.drops : []
    const sideBursts = clustersOf(sideSet).length ? clustersOf(sideSet) : Array.isArray(sideSet.clusters) ? sideSet.clusters : []
    return <section className="focus-side" data-focus-side={side}>
      <div className="focus-side-header">
        <strong>{side === 'L' ? t("LEFT" /* 左侧 */) : t("RIGHT" /* 右侧 */)}</strong>
        <button aria-label={side === 'L' ? t("COMPLETE_LEFT_SIDE" /* 完成左侧 */) : t("COMPLETE_RIGHT_SIDE" /* 完成右侧 */)}
          className={'focus-side-check' + (sideSet.done ? ' done' : '')}
          onClick={() => onToggleSide(setIdx, side,
            !sideSet.done && (set.sides.L.done || set.sides.R.done) ? onProgress : undefined)}><Icon name="check" /></button>
      </div>
      <Stepper label={t("LOAD_COUNT_B" /* 负重（{0}） */, S.unit)} ariaLabel="load" value={sideSet.w || 0} step={loadStep} onStep={stepLoad} disabled={readOnly || sideSet.done}
        onChange={value => change('w', value)} />
      <Stepper label={t("REPS" /* 次数 */)} ariaLabel="reps" value={sideSet.r || 0} step={1} decimal={false} disabled={readOnly || sideSet.done}
        onChange={value => change('r', value)} />
      <div className="focus-extras">
        {sideDrops.map((drop, index) => <div className="focus-extra" key={`drop-${index}`}>
          <span>{t("DROP_COUNT" /* 递减 {0} */, index + 1)}</span>
          <Stepper label={t("LOAD" /* 负重 */)} ariaLabel="load" value={drop.w || 0} step={loadStep} onStep={stepLoad} disabled={readOnly || sideSet.done}
            onChange={value => onMutateSet(setIdx, row => setSideDropAt(row, side, index, { w: value }))} />
          <Stepper label={t("REPS" /* 次数 */)} ariaLabel="reps" value={drop.r || 0} step={1} decimal={false} disabled={readOnly || sideSet.done}
            onChange={value => onMutateSet(setIdx, row => setSideDropAt(row, side, index, { r: value }))} />
        </div>)}
        {sideBursts.map((burst, index) => <div className="focus-extra" key={`burst-${index}`}>
          <span>{t("MINI_SET_COUNT" /* 小组 {0} */, index + 1)}</span>
          <Stepper label={t("REPS" /* 次数 */)} ariaLabel="reps" value={burst.r || 0} step={1} decimal={false} disabled={readOnly || sideSet.done}
            onChange={value => onMutateSet(setIdx, row => setSideClusterAt(row, side, index, value))} />
          <span className="dim small">{t("DURATION_SECONDS_SHORT" /* {0} 秒 */, burst.restSec)}</span>
        </div>)}
      </div>
    </section>
  }

  const onProgress = ({ unitDone }) => {
    const active = useStore.getState().S.active
    if (!active) return
    if (unitDone) {
      onAdvanceUnit()
      const nextEntryIdx = useStore.getState().S.active?.cur
      if (nextEntryIdx !== entryIdx) clearPointer(nextEntryIdx)
    }
    else if (unit.length === 1) selectSet(setIdx + 1)
    else clearPointer(active.cur)
  }

  const complete = () => {
    if (!isSideSet(set)) return onToggle(setIdx, onProgress)
    const sides = set.done ? ['L', 'R'] : ['L', 'R'].filter(side => !set.sides[side].done)
    sides.forEach((side, index) => onToggleSide(setIdx, side, index === sides.length - 1 ? onProgress : undefined))
  }

  const openEffort = () => effortPickerSheet(effort, effortValue, value => onField(setIdx, effortField, value))

  const openExerciseMenu = () => menuSheet({
    title: exerciseNameFor(exOr(entry.id)),
    items: [
      { icon: 'pencil', label: entry.note ? t("EDIT_NOTE" /* 编辑备注 */) : t("ADD_NOTE" /* 添加备注 */), onClick: () => exerciseNoteSheet(entryIdx) },
      { icon: 'info', label: t("DETAILS" /* 详情 */), onClick: () => exerciseDetailSheet(exOr(entry.id)) },
      { icon: 'history', label: t("HISTORY" /* 历史 */), onClick: () => exerciseHistorySheet(entry.id) },
      { icon: 'chartLine', label: t("PROGRESSION_SETTINGS" /* 进阶设置 */), onClick: onProgressionSettings },
      onNoProg && { icon: 'pause', label: t("DON_T_COUNT_FOR_PROGRESSION" /* 不计入进阶 */), sub: t("THIS_EXERCISE_THIS_SESSION_ONLY" /* 仅限此动作，仅限本次训练 */), on: entry.noProg === true, onClick: () => onNoProg(entry.noProg !== true) },
      mode === 'reps' && { icon: 'plate', label: t("PLATE_LOADING" /* 配重 */), onClick: () => barWeightSheet(entry.id, { ...(entry.target || {}), id: entry.id }) },
      onPairPrev && { icon: 'link', label: t("MAKE_SUPERSET_WITH_PREVIOUS" /* 与上一个组成超级组 */), onClick: onPairPrev },
      onPairNext && { icon: 'link', label: t("MAKE_SUPERSET_WITH_NEXT" /* 与下一个组成超级组 */), onClick: onPairNext },
      { icon: 'shuffle', label: t("SWAP_EXERCISE" /* 更换动作 */), onClick: onSwap, disabled: busy },
      { icon: 'trash', label: t("REMOVE_EXERCISE" /* 移除动作 */), onClick: onRemoveExercise, danger: true, disabled: busy },
    ],
  })

  const openSetMenu = () => menuSheet({
    title: t("SET_COUNT" /* 第 {0} 组 */, setIdx + 1),
    items: [
      { icon: 'flame', label: isWarmupRow(set) ? t("MARK_AS_WORK_SET" /* 标记为工作组 */) : t("MARK_AS_WARM_UP" /* 标记为热身组 */), onClick: () => onMutateSet(setIdx, toggleWarmup) },
      { icon: 'arrowDown', label: t("ADD_DROP_SET" /* 添加递减组 */), onClick: () => onMutateSet(setIdx, row => addDropTo(row, entry.target)) },
      { icon: 'bolt', label: t("ADD_REST_PAUSE_MINI_SET" /* 添加休息暂停小组 */), onClick: () => onMutateSet(setIdx, row => addBurstTo(row, entry.target?.intensifier?.type === 'restpause' ? entry.target.intensifier.restSec : (S.restPauseSec || 15))) },
      !isWarmupRow(set) && mode !== 'cardio' && { icon: 'gauge', label: t("TAKEN_TO_FAILURE" /* 做到力竭 */), sub: t("NOTHING_LEFT_IN_THE_TANK" /* 油箱见底了 */), on: isFailureSet(set), onClick: () => onMutateSet(setIdx, toggleFailure) },
      { icon: 'trash', label: t("DELETE_SET" /* 删除本组 */), danger: true, disabled: entry.sets.length <= 1, onClick: () => onRemoveSetAt(setIdx) },
    ],
  })

  return <div className="focus-view" data-testid="focus-view">
    <div className="focus-card">
      {unit.length > 1 && <div className="focus-superset-inline">
        <Icon name="reset" />
        <strong>{t("SUPERSET_A" /* 超级组： */)} {unit.map(index => exerciseNameFor(exOr(S.active.entries[index].id))).join(' + ')}</strong>
        <span>{t("ROUND_COUNT" /* 第 {0} 轮 */, setIdx + 1)} · {t("EXERCISE_COUNT_OF_COUNT" /* 第 {0}/{1} 个动作 */, unit.indexOf(entryIdx) + 1, unit.length)}</span>
        <Button size="xs" variant="ghost" icon="link" aria-label={t("UNPAIR" /* 取消组合 */)} onClick={onUnpair}>{t("UNPAIR" /* 取消组合 */)}</Button>
        <div className="focus-superset-nav">
          <button aria-label={t("PREVIOUS_SUPERSET_SET" /* 超级组上一组 */)} disabled={sequenceIdx <= 0} onClick={() => selectSequence(sequenceIdx - 1)}><Icon name="chevronLeft" /></button>
          <button aria-label={t("NEXT_SUPERSET_SET" /* 超级组下一组 */)} disabled={sequenceIdx < 0 || sequenceIdx >= sequence.length - 1} onClick={() => selectSequence(sequenceIdx + 1)}><Icon name="chevronRight" /></button>
        </div>
      </div>}
      <header className="focus-card-header">
        <h2>{exerciseNameFor(ex)}</h2>
        <button className="iconbtn" aria-label={t("DETAILS" /* 详情 */)} onClick={() => exerciseDetailSheet(ex)}><Icon name="info" /></button>
        {isWarmupRow(set) && <span className="focus-warmup" aria-label={t("WARM_UP" /* 热身 */)}>🔥</span>}
        {isFailureSet(set) && <span className="focus-failure" role="img" aria-label={t("TAKEN_TO_FAILURE" /* 做到力竭 */)}>{t("LABEL_F" /* 术语：F */)}</span>}
        <button className="iconbtn" aria-label={t("MORE" /* 更多 */)} onClick={openExerciseMenu}><Icon name="more" /></button>
      </header>

      <div className="focus-context">
        <div className="focus-tags">
          {mode === 'cardio' && <span className="tag acc">{t("CARDIO" /* 有氧 */)}</span>}
          {isSideSet(set) && <span className="tag acc">{t("PER_SIDE" /* 每侧 */)}</span>}
          {(ex.tg || ex.bp) && <span className="tag">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ex.tg || ex.bp)}</span>}
          {ex.eq && <span className="tag">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ex.eq)}</span>}
        </div>
        {entry.target?.note && <div className="focus-note">{entry.target.note}</div>}
        {pinnedNote && <div className="focus-note pinned"><Icon name="flag" />{t("FROM_COUNT" /* 来自 {0}： */, fmtDate(pinnedNote.d, true))} {pinnedNote.note}</div>}
        {entry.note && <div className="focus-note">{entry.note}</div>}
        {last && <div className="focus-last">{t("LAST_TIME" /* 上次 */)} · {fmtDate(last.d)}</div>}
        {guidance && <button className="focus-guidance" onClick={onProgressionSettings}><Icon name="lightbulb" />{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(guidance.policyLabel)}</button>}
      </div>
      <Prescription entry={entry} setIdx={setIdx} unit={S.unit} fallbackRest={S.restSec}>
        <PlanBadge entry={entry} mode={mode} />
        <PlateBadge S={S} entry={entry} set={set} />
        {entry.noProg === true && <span className="focus-badge warning"><Icon name="pause" />{t("NOT_COUNTED_FOR_PROGRESSION" /* 未计入进阶 */)}{onNoProg && <button type="button" className="focus-badge-action" onClick={() => onNoProg(false)}>{t("UNDO" /* 撤销 */)}</button>}</span>}
      </Prescription>
      {locked && <p className="focus-lock-note" role="status">{t("COMPLETE_SET_COUNT_TO_EDIT_THIS_ONE" /* 先完成第 {0} 组才能编辑本组。 */, firstOpenSet + 1)}</p>}

      <div data-testid="focus-set" className={(set.done ? 'complete ' : '') + (locked ? 'locked' : '')}>
        {isSideSet(set) ? <div className="focus-sides">{sideFields('L')}{sideFields('R')}</div> : <>
          {mode === 'cardio' ? <>
            <Stepper label={t("DURATION_MIN" /* 时长（分钟） */)} ariaLabel="duration" value={set.min || 0} step={1} decimal={false} disabled={readOnly}
              onChange={value => onField(setIdx, 'min', value)} />
            {/* Stored in km/h, shown and typed in the profile's speed unit, as on every other
                cardio input (lib/speed.js). */}
            <Stepper label={speedUnit === 'mph' ? t("SPEED_MPH" /* 速度（mph） */) : t("SPEED_KM_H" /* 速度（km/h） */)} ariaLabel="speed" value={toSpeed(set.speed || 0, speedUnit)} step={0.5} disabled={readOnly}
              onChange={value => onField(setIdx, 'speed', fromSpeed(value, speedUnit))} />
            {/* The treadmill's grade, where the exercise has one (lib/incline.js). */}
            {(inclineFits(ex) || entry.sets.some(hasIncline)) && <Stepper label={t("INCLINE" /* 坡度 (%) */)} ariaLabel="incline" value={set.incline || 0} step={INCLINE_STEP} max={INCLINE_MAX} disabled={readOnly}
              onChange={value => onField(setIdx, 'incline', clampIncline(value))} />}
          </> : <>
            <Stepper label={t("LOAD_COUNT_B" /* 负重（{0}） */, S.unit)} ariaLabel="load" value={set.w || 0} step={loadStep} onStep={stepLoad} disabled={readOnly}
              onChange={value => onField(setIdx, 'w', value)} />
          {mode === 'time' ? <div className="focus-timed">
            <strong>{t("COUNT_S_HOLD" /* 保持 {0} 秒 */, set.sec || entry.target?.sec || 45)}</strong>
            <Button icon="play" aria-label={t("START_SET" /* 开始这一组 */)} disabled={readOnly || busy}
              onClick={() => onStartTimed(setIdx, onProgress)}>{t("START_TIMER" /* 开始计时 */)}</Button>
          </div> : <Stepper label={t("REPS" /* 次数 */)} ariaLabel="reps" value={set.r || 0} step={1} decimal={false} disabled={readOnly}
            onChange={value => onField(setIdx, 'r', value)} />}</>}
        </>}
        <div className="focus-extras">
          {drops.map((drop, index) => <div className="focus-extra" key={`drop-${index}`}>
            <span>{t("DROP_COUNT" /* 递减 {0} */, index + 1)}</span>
            <Stepper label={t("LOAD" /* 负重 */)} ariaLabel="load" value={drop.w || 0} step={loadStep} onStep={stepLoad} disabled={readOnly}
              onChange={value => onMutateSet(setIdx, row => setDropAt(row, index, { w: value }))} />
            <Stepper label={t("REPS" /* 次数 */)} ariaLabel="reps" value={drop.r || 0} step={1} decimal={false} disabled={readOnly}
              onChange={value => onMutateSet(setIdx, row => setDropAt(row, index, { r: value }))} />
          </div>)}
          {bursts.map((burst, index) => <div className="focus-extra" key={`burst-${index}`}>
            <span>{t("MINI_SET_COUNT" /* 小组 {0} */, index + 1)}</span>
            <Stepper label={t("REPS" /* 次数 */)} ariaLabel="reps" value={burst.r || 0} step={1} decimal={false} disabled={readOnly}
              onChange={value => onMutateSet(setIdx, row => {
                const delta = (Number(value) || 0) - (clustersOf(row)[index]?.r ?? row.clusters?.[index]?.r ?? 0)
                return { ...setClusterAt(row, index, { r: value }), r: Math.max(0, (row.r || 0) + delta) }
              })} />
            <span className="dim small">{t("DURATION_SECONDS_SHORT" /* {0} 秒 */, burst.restSec)}</span>
          </div>)}
        </div>
        {mode === 'reps' && effortField && <button className={'effcell focus-effort' + (effortValue == null ? ' is-empty' : '')}
          style={effortTint ? { color: effortTint, borderColor: effortTint, background: `color-mix(in srgb, ${effortTint} 20%, var(--surface-2))` } : undefined}
          aria-label={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(EFFORT[effort].hd)} disabled={readOnly} onClick={openEffort}>{effortValue == null ? translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(EFFORT[effort].hd) : fmtNum(effortValue)}</button>}
      </div>
      <Button variant="primary" icon="check" aria-label={t("COMPLETE_SET" /* 完成本组 */)} onClick={complete}>{set.done ? t("COMPLETED" /* 已完成 */) : t("COMPLETE_SET" /* 完成本组 */)}</Button>
      <div className="focus-secondary">
        <button className="focus-skip" aria-label={t("SKIP_SET" /* 跳过本组 */)} disabled={setIdx >= entry.sets.length - 1} onClick={() => selectSet(setIdx + 1)}>
          <Icon name="play" />{t("SKIP" /* 跳过 */)}
        </button>
        <button className="iconbtn" aria-label={t("SET_MENU" /* 组菜单 */)} onClick={openSetMenu}><Icon name="more" /></button>
      </div>
    </div>

    <footer className="focus-pager">
      <button aria-label={t("PREVIOUS_SET" /* 上一组 */)} disabled={setIdx === 0} onClick={() => selectSet(setIdx - 1)}><Icon name="chevronLeft" /></button>
      <div className="focus-dots">
        {entry.sets.map((row, index) => <button key={index} aria-label={t("SET_COUNT" /* 第 {0} 组 */, index + 1)}
          className={(index === setIdx ? 'active ' : '') + (row.done ? 'done' : '')}
          onClick={() => selectSet(index)} />)}
      </div>
      <button aria-label={t("NEXT_SET" /* 下一组 */)} disabled={setIdx === entry.sets.length - 1} onClick={() => selectSet(setIdx + 1)}><Icon name="chevronRight" /></button>
    </footer>
  </div>
}
