import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { EXIDX, matchExercise, betterWeight, isAssisted } from '../lib/exercises.js'
import { lastBW, streakWeeks, setLabel, modeOf, effortOf, entriesForExercise, metricEntriesForExercise, metricModeForEntry, bestWeightForEntry, completedRepsOf, workoutDay, workoutAt } from '../lib/history.js'
import { fmtNum, fmtDate, fmtVol, todayISO, isoOf, weekKey, weekStartOf, exerciseNameText } from '../lib/format.js'
import { speedUnitOf, speedLabel, toSpeed } from '../lib/speed.js'
import { t, exerciseNameFor, exerciseNameClass, getLang , translateValue } from '../lib/i18n.js'
import { bwSheet, goalSheet, calendarSheet, dayOverrideSheet, workoutDetailSheet, exerciseHistorySheet, WorkoutRow, bwDeltaColor, weighInsSheet } from '../sheets.jsx'
import LineChart from '../components/LineChart.jsx'
import Heatmap from '../components/Heatmap.jsx'
import Icon from '../components/Icon.jsx'
import BodyMap, { BodyMapLegend } from '../components/BodyMap.jsx'
import { loadOfWeeklyPlan, loadOfWorkouts, muscleBalanceWindow, rankOf, MUSCLES, MUSCLE_NAME, musclesOf } from '../lib/muscles.js'
import { fatigueOf, strengthOf, STRENGTH_FLOOR, LB_TO_KG } from '../lib/recovery.js'
import { strengthExerciseRowsForMuscle } from '../lib/strength-exercises.js'
import { fatigueStateOf } from '../lib/recovery-view.js'
import { e1rmSeries, best1RM, formulaOf } from '../lib/onerm.js'
import { currentDbLoad, workoutAs } from '../lib/dumbbells.js'
import { maxRepsSeries } from '../lib/pyramid.js'
import { perSetSessions, perSetLines, dropOffSet } from '../lib/per-set.js'
import {
  hasEffort, hasEstimableEffort, displayScale, scaleName, toScale, avgRir, effortSummary, effortWeeks,
  effortHistogram, isHardSet, HARD_RIR, MIN_RATED
} from '../lib/effort.js'
import { anchorsByWorkout, resolveSetRir } from '../lib/recovery.js'
import { Button, Segmented, SelectRow } from '../components/ui.jsx'
import { tappable } from '../lib/use-sheet-keyboard.js'
import { isWarmupRow } from '../lib/workout-model.js'

// Set 1 to 5 on the per-set chart — system colours, so each line keeps its hue in dark mode.
const SET_COLORS = ['var(--blue)', 'var(--green)', 'var(--orange)', 'var(--purple)', 'var(--pink)']

// The date range buttons under Body weight, and since issue #511 under Exercise progress too.
// In days, 0 = everything; a function because the labels follow the current language.
const rangeOptions = () => [{ value: 30, label: '1M' }, { value: 90, label: '3M' }, { value: 365, label: '1Y' }, { value: 0, label: t("ALL" /* 全部 */) }]
// Where a range starts, in ms. Worked out once per pick rather than from each render's clock, so
// the memoised chart arrays below keep their identity (LineChart drops its hover on a new one).
const rangeStart = days => (days ? Date.now() - days * 86400000 : 0)

// Which muscles the training in a window actually hit — and, the point of the card,
// which ones it keeps missing. Shading is relative within the window (lib/muscles.js).
function latestMuscleTraining(workouts) {
  const latest = {}
  for (const workout of workouts || []) {
    const timestamp = workoutAt(workout)
    if (!Number.isFinite(timestamp)) continue
    for (const entry of workout.entries || []) {
      if (!(entry.sets || []).some(set => set?.done === true && !isWarmupRow(set))) continue
      const exercise = EXIDX[entry.id] || entry.exercise || entry
      for (const slug of Object.keys(musclesOf(exercise))) {
        if (latest[slug] == null || timestamp > latest[slug]) latest[slug] = timestamp
      }
    }
  }
  return latest
}

export const FATIGUE_LEVELS = [
  { at: 0, level: 0 },
  { at: 0.15, level: 1 },
  { at: 0.25, level: 2 },
  { at: 0.4, level: 3 },
  { at: 0.55, level: 4, exclusive: true },
]

export const STRENGTH_LEVELS = [
  { at: STRENGTH_FLOOR, level: 0 },
  { at: 0.625, level: 1 },
  { at: 0.75, level: 2 },
  { at: 0.875, level: 3 },
  { at: 1, level: 4 },
]

function useNow() {
  const [, setTick] = useState(0)
  useEffect(() => {
    const iv = setInterval(() => setTick(tick => tick + 1), 60000)
    return () => clearInterval(iv)
  }, [])
  return Date.now()
}

/**
 * Return the whole weeks since a completed muscle-training timestamp.
 *
 * @param {number} now Current render-time timestamp in milliseconds.
 * @param {number} lastTrained Timestamp of the latest completed training event.
 * @returns {number} Non-negative whole weeks, including zero for ages under seven days.
 */
export function weeksSinceTraining(now, lastTrained) {
  return Math.max(0, Math.floor((now - lastTrained) / 86400000 / 7))
}

function FatigueLegend() {
  return <div className="hm-legend hm-fatigue" aria-label={t("FATIGUE" /* 疲劳 */)}>
    <span>{t("FATIGUED" /* 已疲劳 */)}</span><div className="hm-c l4" />
    <span>{t("RECOVERING" /* 恢复中 */)}</span><div className="hm-c l2" />
    <span>{t("READY" /* 准备好 */)}</span><div className="hm-c l0" />
  </div>
}

function StrengthLegend() {
  return <div className="hm-legend hm-strength" aria-label={t("STRENGTH" /* 力量 */)}>
    <span>1 <span className="dim">{t("FULL_A" /* 完全 */)}</span></span><div className="hm-c l4" /><div className="hm-c l3" /><div className="hm-c l2" />
    <div className="hm-c l1" /><div className="hm-c l0" /><span>{fmtNum(STRENGTH_FLOOR)} <span className="dim">{t("FLOOR" /* 下限 */)}</span></span>
  </div>
}

function fatigueLabel(value) {
  const state = fatigueStateOf(value)
  return t(state === 'ready' ? "READY" /* 准备好 */ : state === 'recovering' ? "RECOVERING" /* 恢复中 */ : "FATIGUED" /* 已疲劳 */)
}

// The user's own last registered bodyweight, in kg: the body-mass part of a bodyweight
// exercise's load for fatigue and for estimated effort, so both read the same set the same way.
function profileBodyweightKg(S) {
  const entries = S.bodyweight || []
  if (!entries.length) return null
  const last = entries.slice().sort((a, b) => String(a.d).localeCompare(String(b.d))).at(-1)
  if (!last || !(last.w > 0)) return null
  return S.unit === 'lb' ? last.w * LB_TO_KG : last.w
}

function MuscleBalance({ S }) {
  const [view, setView] = useState('balance')
  const [win, setWin] = useState(7)
  const [weekOffset, setWeekOffset] = useState(0)
  const [hard, setHard] = useState(false)
  const [sel, setSel] = useState(null)
  const [weeklyExpanded, setWeeklyExpanded] = useState(false)
  const now = useNow()
  const lang = getLang()
  const workouts = S.workouts
  const bodyweightKg = useMemo(() => profileBodyweightKg(S), [S.bodyweight, S.unit])
  const fatigue = useMemo(() => fatigueOf(workouts, now, { bodyweightKg, unit: S.unit }), [workouts, now, bodyweightKg, S.unit])
  const strength = useMemo(() => strengthOf(workouts, now, { bodyweightKg, unit: S.unit }), [workouts, now, bodyweightKg, S.unit])
  const muscleExercises = useMemo(() => (sel ? strengthExerciseRowsForMuscle(S, now, sel) : []), [S, now, sel, lang])
  const lastTrained = useMemo(() => latestMuscleTraining(workouts), [workouts])
  const strengthHint = slug => {
    if (lastTrained[slug] == null) return t("NOT_TRAINED" /* 未训练 */)
    const weeks = weeksSinceTraining(now, lastTrained[slug])
    return t("WEEKS_SINCE_TRAINING_COUNT" /* 上次训练：{0}周前 */, weeks)
  }
  const toggleSel = m => setSel(s => (s === m ? null : m))
  const ws = weekStartOf(S)
  const currentWeek = weekKey(todayISO(), ws)
  const selectedWeekDate = new Date(currentWeek + 'T12:00:00')
  selectedWeekDate.setDate(selectedWeekDate.getDate() + weekOffset * 7)
  const selectedWeek = isoOf(selectedWeekDate)
  const weekly = win === 7
  const inWin = weekly
    ? S.workouts.filter(workout => workoutDay(workout) && weekKey(workoutDay(workout), ws) === selectedWeek)
    : muscleBalanceWindow(S.workouts, win, now, todayISO(), ws)
  // Counting only the sets taken near failure turns the map from "where did the volume go"
  // into "where did the stimulus go" — a muscle can lead on sets and still never be trained
  // hard. Offered only when the window holds ratings at all, since with none the hard map
  // would just be empty and read as "you trained nothing".
  const rated = inWin.some(w => w.entries.some(e => e.sets.some(s => s.done && isHardSet(s))))
  const on = !weekly && hard && rated
  const load = loadOfWorkouts(inWin, on ? isHardSet : null)
  const planned = weekly && weekOffset === 0 ? loadOfWeeklyPlan(S) : {}
  const comparisonMuscles = MUSCLES
    .filter(muscle => (planned[muscle] || 0) > 0 || (load[muscle] || 0) > 0)
    .sort((a, b) => (load[b] || 0) - (load[a] || 0) || (planned[b] || 0) - (planned[a] || 0) || MUSCLES.indexOf(a) - MUSCLES.indexOf(b))
  const volWin = S.workouts.filter(w => workoutAt(w) > now - 90 * 86400000)
  const vol90 = loadOfWorkouts(volWin, null)
  const { worked, missed } = rankOf(load)
  const { worked: strengthOrder } = rankOf(strength)
  const detrained = strengthOrder.filter(slug => strength[slug] < 1)
  const top = worked.slice(0, 4)
  const completedMuscles = weekly && weeklyExpanded ? worked : top
  const max = worked.length ? load[worked[0]] : 0
  const sets = m => fmtNum(Math.round((load[m] || 0) * 10) / 10)
  const visibleComparisonMuscles = sel ? [sel] : weeklyExpanded ? comparisonMuscles : comparisonMuscles.slice(0, 4)
  const comparisonRows = visibleComparisonMuscles.map(muscle => {
    const completed = Math.round((load[muscle] || 0) * 10) / 10
    const target = Math.round((planned[muscle] || 0) * 10) / 10
    const percentage = target > 0 ? Math.round(completed / target * 100) : null
    const fill = target > 0 ? Math.round(Math.min(completed / target, 1) * 100) : completed > 0 ? 100 : 0
    const completedSets = t("COUNT_SETS" /* {0} 组 */, fmtNum(completed))
    const plannedSets = t("COUNT_SETS" /* {0} 组 */, fmtNum(target))
    return <div className="mrow" data-muscle-volume={muscle} key={muscle}>
      <span className="nm">{sel === muscle ? <b>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[muscle])}</b> : translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[muscle])}</span>
      <span className="bar"><i style={{ width: fill + '%' }} /></span>
      <span className="v" style={{ textAlign: 'end' }}
        aria-label={`${t("COMPLETED" /* 已完成 */)} ${completedSets} · ${t("PLANNED" /* 已计划 */)} ${plannedSets}`}>
        {fmtNum(completed)}/{fmtNum(target)}{percentage == null ? '' : ` · ${percentage}%`}
      </span>
    </div>
  })
  const completionSummary = <>
    {missed.length > 0 && <>
      <h4 className="sec" style={{ marginTop: 12 }}>{on ? t("NO_HARD_SETS_IN_THIS_PERIOD" /* 此期间没有硬组 */) : t("NOT_TRAINED_IN_THIS_PERIOD" /* 此期间未训练 */)}</h4>
      <div className="mchips">{missed.map(m => <span key={m} className="mchip miss">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[m])}</span>)}</div>
    </>}
    {!missed.length && worked.length > 0 &&
      <div className="muted small" style={{ marginTop: 10 }}>{on
        ? t("EVERY_MUSCLE_GROUP_GOT_AT_LEAST_ONE_HARD_SET_IN_THIS_PERIOD" /* 此期间每个肌群都至少练了一个硬组。 */)
        : t("EVERY_MUSCLE_GROUP_GOT_SOME_WORK_IN_THIS_PERIOD" /* 此期间每个肌群都得到了训练。 */)}</div>}
  </>
  const weeklyToggle = rowCount => weekly && !sel && rowCount > 4 && <>
    <div style={{ height: 8 }} />
    <Button className="weekly-volume-toggle" trailingIcon="chevronDown" aria-expanded={weeklyExpanded}
      onClick={() => setWeeklyExpanded(expanded => !expanded)}>
      {t(weeklyExpanded ? "SHOW_LESS" /* 显示更少 */ : "SHOW_MORE" /* 显示更多 */)}
    </Button>
  </>
  const completedRows = <>
    {sel && <div className="mrow" data-muscle-volume={sel} style={{ borderTop: 'var(--hair) solid var(--sep)', marginTop: 4, paddingTop: 10 }}>
      <span className="nm"><b>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[sel])}</b></span>
      <span className="v">{sets(sel) ? t("COUNT_SETS" /* {0} 组 */, sets(sel)) : on ? t("NO_HARD_SETS" /* 没有硬组 */) : t("NOT_TRAINED" /* 未训练 */)}</span>
    </div>}
    {!sel && completedMuscles.map(m => <div key={m} className="mrow" data-muscle-volume={m}>
      <span className="nm">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[m])}</span>
      <span className="bar"><i style={{ width: Math.round(load[m] / max * 100) + '%', background: on ? 'var(--yellow)' : undefined }} /></span>
      <span className="v">{t("COUNT_SETS" /* {0} 组 */, sets(m))}</span>
    </div>)}
    {weeklyToggle(worked.length)}
    {completionSummary}
  </>

  return <div className="card">
    <Segmented className="seg-range" value={view} onChange={setView}
      options={[{ value: 'balance', label: t("MUSCLE_BALANCE" /* 肌肉平衡 */) }, { value: 'fatigue', label: t("FATIGUE" /* 疲劳 */) }, { value: 'strength', label: t("STRENGTH" /* 力量 */) }]} />
    {view === 'balance' ? <>
      <div className="row between" style={{ marginBottom: 8 }}>
        <h2 style={{ margin: 0 }}>{t("MUSCLE_BALANCE" /* 肌肉平衡 */)} <span className="dim" style={{ textTransform: 'none', letterSpacing: 0 }}>· {on ? t("BY_HARD_SETS" /* 按硬组 */) : t("BY_SETS_WORKED" /* 按训练组数 */)}</span></h2>
        {!weekly && rated && <Button size="sm" icon="gauge" style={on ? { color: 'var(--yellow)' } : undefined}
          onClick={() => { setHard(h => !h); setSel(null) }}>{on ? t("HARD" /* 硬组 */) : t("ALL" /* 全部 */)}</Button>}
      </div>
      <Segmented className="seg-range" value={win} onChange={v => { setWin(v); setSel(null); setWeeklyExpanded(false) }}
        options={[{ value: 7, label: t("WEEK" /* 本周 */) }, { value: 30, label: '30d' }, { value: 90, label: '90d' }, { value: 0, label: t("ALL" /* 全部 */) }]} />
      {weekly ? <div data-weekly-volume-comparison data-week={selectedWeek}>
        <div className="row between" style={{ margin: '10px 0 6px' }}>
          <button className="iconbtn sm" aria-label={t("PREVIOUS_WEEK" /* 上一周 */)} onClick={() => { setWeekOffset(offset => offset - 1); setSel(null); setWeeklyExpanded(false) }}><Icon name="chevronLeft" /></button>
          <span className="small" style={{ fontWeight: 600 }}>{t("WEEK_OF_COUNT" /* {0} 起的一周 */, fmtDate(selectedWeek))}</span>
          <button className="iconbtn sm" aria-label={t("NEXT_WEEK" /* 下一周 */)} disabled={weekOffset === 0}
            onClick={() => { setWeekOffset(offset => Math.min(0, offset + 1)); setSel(null); setWeeklyExpanded(false) }}><Icon name="chevronRight" /></button>
        </div>
        <BodyMap className="tappable" load={load} body={S.body} selected={sel} onMuscle={toggleSel} />
        <BodyMapLegend />
        {weekOffset === 0
          ? comparisonRows.length ? <>{comparisonRows}{weeklyToggle(comparisonMuscles.length)}{completionSummary}</> : <div className="muted small">{t("NO_WORKOUTS_IN_THIS_PERIOD_YET" /* 此期间还没有训练。 */)}</div>
          : inWin.length ? completedRows : <div className="muted small">{t("NO_WORKOUTS_IN_THIS_PERIOD_YET" /* 此期间还没有训练。 */)}</div>}
      </div> : inWin.length ? <>
        <BodyMap className="tappable" load={load} body={S.body} selected={sel}
          onMuscle={toggleSel} />
        <BodyMapLegend />
        {completedRows}
      </> : <div className="muted small">{t("NO_WORKOUTS_IN_THIS_PERIOD_YET" /* 此期间还没有训练。 */)}</div>}
    </> : view === 'fatigue' ? <>
      <h2>{t("FATIGUE" /* 疲劳 */)}</h2>
      <BodyMap className="tappable hm-fatigue" load={fatigue} thresholds={FATIGUE_LEVELS} body={S.body} selected={sel} onMuscle={toggleSel} />
      <FatigueLegend />
      <div className="muted small" style={{ marginTop: 10 }}>{t("FATIGUE_SHOWS_HOW_RECENTLY_EACH_MUSCLE_WAS_TRAINED_HIGH_MEANS_REST" /* 疲劳度显示每个肌群最近一次训练距今多久。数值越高，越需要休息。 */)}</div>
      {sel && <div className="mrow" style={{ borderTop: 'var(--hair) solid var(--sep)', marginTop: 4, paddingTop: 10 }}>
        <span className="nm"><b>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[sel])}</b></span>
        <span className="v">{fatigueLabel(fatigue[sel])}</span>
      </div>}
    </> : <>
      <h2>{t("STRENGTH" /* 力量 */)}</h2>
      <BodyMap className="tappable hm-strength" load={strength} thresholds={STRENGTH_LEVELS} body={S.body} selected={sel} onMuscle={toggleSel} />
      <StrengthLegend />
      <div className="muted small" style={{ marginTop: 10 }}>{t("STRENGTH_SHOWS_RETAINED_MUSCLE_STRENGTH_TRAIN_AGAIN_TO_RESET_IT" /* 力量显示肌肉力量保留了多少。再次训练即可重置。 */)}</div>
      {sel && <>
        <h4 className="sec" style={{ marginTop: 14 }}>{t("EXERCISES" /* 动作库 */)} · {translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[sel])}</h4>
        {/* A row quotes the exercise's estimated 1RM, so a tap opens the exercise history
            sheet — the curve behind that number plus the last sessions set by set. */}
        {muscleExercises.length ? muscleExercises.map(row => (
          <div key={row.id} className="mrow" style={{ minHeight: 48, alignItems: 'stretch', cursor: 'pointer' }} {...tappable(() => exerciseHistorySheet(row.id))}>
            <span className="nm" style={{ whiteSpace: 'normal', lineHeight: 1.35, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
              <span style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                <span className={EXIDX[row.id] ? exerciseNameClass(EXIDX[row.id]) : undefined}>{row.name}</span>
                {row.primary === sel
                  ? <span className="dim" style={{ fontSize: 11, marginInlineStart: 6 }}>{t("PRIMARY" /* 主要 */)}</span>
                  : <span className="dim" style={{ fontSize: 11, marginInlineStart: 6 }}>{t("SECONDARY" /* 次要 */)}</span>}
              </span>
              <span className="small dim" style={{ display: 'block', fontWeight: 400 }}>{t("EST_ONE_REP_MAX" /* 估算 1RM */)}: {fmtNum(row.est)} {S.unit} · {fmtDate(row.estDate, true)}</span>
            </span>
            {/* Filled by width, like the bars around it, rather than a 'to right' gradient: a block
                starts at the inline start, so in right-to-left it fills from the right. */}
            <span className="bar" style={{ alignSelf: 'center' }}><i style={{ width: Math.round(row.decay * 100) + '%' }} /></span>
            <span className="v" style={{ alignSelf: 'center' }}>{fmtNum(row.current)} {S.unit}<span className="dim"> · {Math.round(row.decay * 100)}%</span></span>
          </div>
        )) : <div className="muted small">{t("NO_EXERCISES_WITH_AN_ESTIMATED_ONE_REP_MAX_YET" /* 暂无估算1RM的动作。 */)}</div>}
      </>}
      {!sel && <div className="muted small" style={{ marginTop: 10 }}>{t("TAP_A_MUSCLE_TO_SEE_ITS_EXERCISES" /* 点击肌肉查看其动作。 */)}</div>}
      {/* Detrained muscles: the bar is retained strength, the value says how long ago the
          muscle was last trained. Sets in the last 90 days ride along only when there are
          any — a muscle is on this list precisely because it has not been trained lately, so
          that number alone read as "0 sets" all the way down and told nobody anything. */}
      {detrained.map(slug => {
        const sets90 = Math.round((vol90[slug] || 0) * 10) / 10
        return <div key={slug} className="mrow">
          <span className="nm">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[slug])}</span>
          <span className="bar"><i style={{ width: Math.round(strength[slug] * 100) + '%' }} /></span>
          <span className="v" style={{ textAlign: 'end' }}>
            {sets90 ? t("COUNT_SETS" /* {0} 组 */, fmtNum(sets90)) : strengthHint(slug)}
            {sets90 ? <span className="dim small" style={{ display: 'block', fontWeight: 400 }}>{strengthHint(slug)}</span> : null}
          </span>
        </div>
      })}
    </>}
  </div>
}


// How hard the training was — the half of the picture a volume chart cannot show. Everything
// is computed in RIR (lib/effort.js) and converted to whichever scale this profile reads.
// Every number carries how much of the training it speaks for: rating is optional and off by
// default, so a partly rated history is the normal case, and an average without its
// denominator would quietly speak for sets that were never rated.
function EffortCard({ S }) {
  const [win, setWin] = useState(90)
  const kind = displayScale(S)
  const hd = scaleName(kind)
  const logged = effortSummary(S, win)
  // Thin or missing ratings fall back to estimates (same precedence fatigue scoring
  // uses), so imported histories get an effort card too. Well-rated windows keep
  // their logged numbers untouched - estimates never dilute a real average.
  const blend = logged.rated < MIN_RATED
  // Same options as the fatigue map (unit + profile bodyweight), so a bodyweight set is
  // estimated against the same body-mass-inclusive anchor in both places.
  const opts = useMemo(() => ({ unit: S.unit, bodyweightKg: profileBodyweightKg(S) }), [S.unit, S.bodyweight])
  const anchors = useMemo(
    () => (blend ? anchorsByWorkout(S.workouts, opts) : new Map()),
    [blend, S.workouts, opts],
  )
  const resolve = (s, w, e) => resolveSetRir(s, s, e, w, anchors.get(w), opts)
  const sum = blend ? effortSummary(S, win, resolve) : logged
  const weeks = blend ? effortWeeks(S, win, resolve) : effortWeeks(S, win)
  const hist = blend ? effortHistogram(S, win, resolve) : effortHistogram(S, win)
  const estimated = blend && sum.est > 0
  const maxBin = Math.max(1, ...hist.map(b => b.n))
  // The week's set count rides along in the tooltip, because the pair is the reading:
  // volume up with effort up is fatigue piling up, volume up with effort flat is adaptation.
  const pts = weeks.map(w => ({ t: w.t, y: toScale(kind, w.rir), note: t("COUNT_SETS" /* {0} 组 */, w.sets) }))
  // Bins run hardest-first in both scales: RIR 0 and RPE 10 are the same set.
  const binLabel = b => kind === 'rpe' ? (b.tail ? '≤ 6' : String(10 - b.rir)) : (b.tail ? b.rir + '+' : String(b.rir))

  return <div className="card">
    <h2>{t("EFFORT" /* 用力程度 */)} <span className="dim" style={{ textTransform: 'none', letterSpacing: 0 }}>· {t("HOW_CLOSE_TO_FAILURE" /* 距离力竭的程度 */)}{estimated ? ' · ' + t("ESTIMATED" /* 估算 */) : ''}</span></h2>
    <Segmented className="seg-range" value={win} onChange={setWin}
      options={[{ value: 30, label: '30d' }, { value: 90, label: '90d' }, { value: 365, label: '1Y' }, { value: 0, label: t("ALL" /* 全部 */) }]} />
    {sum.rated === 0 && sum.est === 0 ? <div className="muted small">{t("NO_RATED_SETS_IN_THIS_PERIOD" /* 此期间没有已评分的组。 */)}</div> : <>
      <div className="row between" style={{ alignItems: 'flex-end', gap: 12 }}>
        <div>
          <div className="stat-v">{sum.avg == null ? '–' : fmtNum(toScale(kind, sum.avg)) + ' ' + hd}</div>
          <div className="small dim">{t("AVERAGE_EFFORT" /* 平均强度 */)}</div>
        </div>
        <div style={{ textAlign: 'end' }}>
          <div className="stat-v" style={{ color: 'var(--yellow)' }}>{sum.hardPct == null ? '–' : Math.round(sum.hardPct * 100) + '%'}</div>
          <div className="small dim">{t("AT_COUNT_COUNT_OR_HARDER" /* {0} {1} 或更硬 */, hd, fmtNum(toScale(kind, HARD_RIR)))}</div>
        </div>
      </div>
      <div className="small dim" style={{ marginTop: 8 }}>{estimated
        ? t("COUNT_RATED_COUNT_ESTIMATED_OF_COUNT_SETS" /* {0} 组已评分 · {1} 组为估算，共 {2} 组 */, sum.rated, sum.est, sum.done)
        : t("COUNT_OF_COUNT_FINISHED_SETS_RATED" /* {1} 个已完成组中有 {0} 个已评分 */, sum.rated, sum.done)}</div>
      {effortOf(S) === 'none' && <div className="small" style={{ color: 'var(--yellow)', marginTop: 4 }}>
        {t("EFFORT_PER_SET_IS_OFF_TURN_IT_ON_IN_SETTINGS_WORKOUT_TO" /* 每组强度已关闭。在 设置 → 训练 中打开即可继续评分。 */)}
      </div>}
      {pts.length > 1 && <>
        <h4 className="sec" style={{ marginTop: 12 }}>{t("WEEK_BY_WEEK" /* 逐周变化 */)}</h4>
        <div className="chart"><LineChart points={pts} h={140} unit={hd} color="var(--yellow)" invert={kind === 'rir'} /></div>
      </>}
      <h4 className="sec" style={{ marginTop: 12 }}>{t("WHERE_THE_SETS_LAND" /* 组都落在哪里 */)}</h4>
      {hist.map(b => <div key={b.rir} className="mrow">
        <span className="nm">{hd} {binLabel(b)}</span>
        <span className="bar"><i style={{ width: Math.round(b.n / maxBin * 100) + '%', background: b.rir <= HARD_RIR ? 'var(--yellow)' : 'var(--label-3)' }} /></span>
        <span className="v">{b.n ? b.n + ' · ' + Math.round(b.pct * 100) + '%' : '–'}</span>
      </div>)}
      <div className="small dim" style={{ marginTop: 8 }}>
        {t("MOST_WORKING_SETS_BELONG_CLOSE_TO_FAILURE_NOT_AT_IT_HALF_AT" /* 大多数工作组应该接近力竭，而不是真的力竭。一半在最底、一半在最顶，平均下来照样看着很健康。 */)}
      </div>
    </>}
  </div>
}

// Stats = the analytics hub: all charts, progress and history live here.
// The muscle volume your plan programs in a week: every weekday routine once, plus each session
// of a running rotation (lib/muscles.js loadOfWeeklyPlan). It used to sit on Plan; it is analysis,
// so it lives here now, next to Muscle balance, and Plan links to it (/stats?focus=weekly-volume).
const PLAN_VOLUME_ROWS = 5
export function WeeklyPlanVolume({ S }) {
  const [all, setAll] = useState(false)
  const load = loadOfWeeklyPlan(S)
  const muscles = rankOf(load).worked
  const shown = all ? muscles : muscles.slice(0, PLAN_VOLUME_ROWS)
  const max = muscles.length ? load[muscles[0]] : 0
  return <div className="card" id="weekly-volume" data-weekly-muscle-volume>
    <h2 style={{ marginBottom: 2 }}>{t("WEEKLY_MUSCLE_VOLUME" /* 每周肌群训练量 */)}</h2>
    <div className="muted small" style={{ marginBottom: 10 }}>{t("PLANNED_SETS_PER_WEEK_FROM_YOUR_PLAN" /* 按你的计划，每周计划的组数。 */)}</div>
    {muscles.length ? shown.map(muscle => <div className="mrow" key={muscle}>
      <span className="nm">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[muscle])}</span>
      <span className="bar"><i style={{ width: Math.round(load[muscle] / max * 100) + '%' }} /></span>
      <span className="v">{t("COUNT_SETS" /* {0} 组 */, fmtNum(Math.round(load[muscle] * 10) / 10))}</span>
    </div>) : <div className="muted small">{t("NO_MUSCLE_VOLUME_PLANNED" /* 尚未安排肌群训练。 */)}</div>}
    {muscles.length > PLAN_VOLUME_ROWS && <>
      <div style={{ height: 8 }} />
      <Button className="weekly-plan-toggle" trailingIcon={all ? 'chevronUp' : 'chevronDown'} aria-expanded={all}
        onClick={() => setAll(v => !v)}>{t(all ? "SHOW_LESS" /* 显示更少 */ : "SHOW_MORE" /* 显示更多 */)}</Button>
    </>}
  </div>
}

export default function Stats() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const [range, setRange] = useState(90)
  // Plan's "Weekly muscle volume" row lands here (/stats?focus=weekly-volume). The router is a
  // HashRouter, so the query sits in the hash; the scroll waits a frame for the page's own
  // scroll-to-top on navigation to have happened first.
  useEffect(() => {
    if (!/[?&]focus=weekly-volume\b/.test(window.location.hash || '')) return
    const frame = window.requestAnimationFrame(() => document.getElementById('weekly-volume')?.scrollIntoView?.({ block: 'start', behavior: 'smooth' }))
    return () => window.cancelAnimationFrame(frame)
  }, [])
  const [exId, setExId] = useState(null)
  const [exMetric, setExMetric] = useState('top')
  // Exercise progress over a date range (issue #511), All by default. Only the chart follows it:
  // "Best:" and the recent sessions under it stay all-time.
  const [exRange, setExRange] = useState(0)
  const exFrom = useMemo(() => rangeStart(exRange), [exRange])
  const inExRange = p => p.t >= exFrom
  const now = Date.now()
  const kind = displayScale(S)
  const hd = scaleName(kind)

  const bwPts = S.bodyweight.filter(b => range === 0 || (b.t || new Date(b.d).getTime()) > now - range * 86400000)
    .map(b => ({ t: b.t || new Date(b.d).getTime(), y: b.w, d: b.d }))
  const bw30 = S.bodyweight.filter(b => (b.t || new Date(b.d).getTime()) > now - 30 * 86400000)
  const bwDelta30 = bw30.length > 1 ? bw30[bw30.length - 1].w - bw30[0].w : null
  const workouts = S.workouts
  const monthW = workouts.filter(w => workoutDay(w)?.slice(0, 7) === todayISO().slice(0, 7)).length

  // Dumbbell weights are read in each exercise's current meaning (lib/dumbbells.js), so the
  // chart and its best compare like with like across a switch between per bell and total.
  const meantIn = {}
  const metricDataOf = (workout, id) => {
    const entries = metricEntriesForExercise(workoutAs(workout, id, meantIn[id] ??= currentDbLoad(S, id)), id)
    const mode = entries.at(-1)?.mode || null
    const sameMode = entries.filter(item => item.mode === mode)
    const best = mode === 'reps' ? sameMode.reduce((value, item) => {
      const candidate = bestWeightForEntry(item.entry)
      if (!(candidate > 0)) return value
      return value > 0 ? betterWeight(id, value, candidate) : candidate
    }, 0) : 0
    return { mode, entries: sameMode, rows: sameMode.flatMap(item => item.rows), best }
  }
  const entryOf = id => workouts.flatMap(w => w.entries).find(e => e.id === id)
  const listOf = value => Array.isArray(value) ? value : value == null || value === '' ? [] : [value]
  const firstAvailable = (...values) => {
    for (const value of values) {
      const list = listOf(value)
      if (list.length) return list
    }
    return []
  }
  const nameOf = id => {
    if (EXIDX[id]) return exerciseNameFor(EXIDX[id])
    const entry = entryOf(id)
    return entry?.muscleSnapshot?.n || entry?.n || id
  }
  const matcherOf = id => {
    if (EXIDX[id]) return EXIDX[id]
    const entry = entryOf(id)
    const snapshot = entry?.muscleSnapshot || {}
    const primaries = firstAvailable(snapshot.primaries, entry?.primaries)
    const secondaries = firstAvailable(
      snapshot.sm, snapshot.secondaries, snapshot.muscleGroups,
      entry?.sm, entry?.secondaries, entry?.muscleGroups,
    )
    return {
      n: snapshot.n || entry?.n || id,
      bp: snapshot.bp || entry?.bp || '',
      tg: primaries[0] || snapshot.tg || entry?.tg || '',
      sm: secondaries,
      eq: snapshot.eq || entry?.eq || '',
      desc: snapshot.desc || entry?.desc || '',
    }
  }
  // Cardio is charted and ranked in the profile's speed unit; the sets keep km/h (lib/speed.js).
  const speedUnit = speedUnitOf(S)
  const currentOf = id => {
    for (let i = workouts.length - 1; i >= 0; i--) {
      const data = metricDataOf(workouts[i], id)
      if (!data.mode) continue
      const mode = data.mode
      const rows = data.rows
      const mx = mode === 'reps'
        ? data.best
        : Math.max(0, ...rows.map(s => mode === 'cardio' ? toSpeed(s.speed || 0, speedUnit) : mode === 'time' ? (s.sec || 0) : (s.w || 0)))
      if (mx > 0) return { mx, unit: mode === 'cardio' ? speedLabel(speedUnit) : mode === 'time' ? 's' : S.unit }
      // Unloaded reps work still has a current figure — its rep count. Without this the whole
      // picker label went blank and the exercise sorted to the bottom as if it had no history.
      if (mode === 'reps') {
        const reps = Math.max(0, ...rows.map(completedRepsOf))
        if (reps > 0) return { mx: reps, unit: t("REPS_A" /* 次 */) }
      }
    }
    return { mx: 0, unit: S.unit }
  }
  const exHist = [...new Set(workouts.flatMap(w => w.entries.map(e => e.id)))].filter(id => EXIDX[id] || nameOf(id) !== id)
  const exCurrent = Object.fromEntries(exHist.map(id => [id, currentOf(id)]))
  exHist.sort((a, b) => exCurrent[b].mx - exCurrent[a].mx || nameOf(a).localeCompare(nameOf(b)))
  const curEx = exId && exHist.includes(exId) ? exId : exHist[0] || null
  // A completed reps work row is authoritative for strength metrics, even when the parent
  // target also contains timed/cardio work. Entries without reps rows use their selected mode.
  const curMode = curEx ? (() => {
    for (let i = workouts.length - 1; i >= 0; i--) {
      const data = metricDataOf(workouts[i], curEx)
      if (data.mode) return data.mode
      const entries = entriesForExercise(workouts[i], curEx)
      for (let j = entries.length - 1; j >= 0; j--) {
        const mode = metricModeForEntry(entries[j])
        if (mode) return mode
      }
    }
    return modeOf({ id: curEx })
  })() : 'reps'
  const curCardio = curMode === 'cardio'
  const curTimed = curMode === 'time'
  // A pull-up or a push-up carries no weight, so its "best weight" is 0 — and dropping every
  // zero point left the card reading "No data yet" for exercises with a full history behind
  // them (issue #5). When nothing in an exercise's history was ever loaded, the progress IS
  // the rep count, so plot that. Add a weighted set later and it switches back to weight on
  // its own, which is also the honest reading: that is when load became the thing improving.
  const repsOnly = curEx && curMode === 'reps' && !workouts.some(w =>
    entriesForExercise(w, curEx).some(en => bestWeightForEntry(en) > 0))
  const metric = s => curCardio ? toSpeed(s.speed || 0, speedUnit) : curTimed ? (s.sec || 0) : (s.w || 0)
  const exUnit = curCardio ? speedLabel(speedUnit) : curTimed ? 's' : repsOnly ? t("REPS_A" /* 次 */) : S.unit
  let exPts = [], exList = [], exBest = 0
  if (curEx) {
    workouts.forEach(w => {
      const data = metricDataOf(w, curEx)
      if (data.mode === curMode) {
        const doneSets = data.rows
        const representative = data.entries.at(-1)?.entry
        const mx = curMode === 'reps'
          ? (repsOnly ? Math.max(0, ...doneSets.map(completedRepsOf)) : data.best)
          : Math.max(0, ...doneSets.map(metric))
        if (mx > 0) {
          exPts.push({ t: w.start, y: mx, d: w.d, sets: doneSets, target: representative?.target })
          // Weighted work on an assistance machine reads the other way: the smallest load is the
          // best (issue #232). Reps, duration and speed are always "more is better".
          const better = curMode === 'reps' && !repsOnly ? betterWeight(curEx, exBest || mx, mx) : Math.max(exBest, mx)
          exBest = exBest > 0 ? better : mx
        }
      }
    })
    exList = exPts.slice(-5).reverse()
  }
  // Estimated 1RM (issue #18) — only reps-mode training produces one, so cardio and timed
  // work simply have no points and the toggle stays hidden.
  // Both memoised on the same inputs, and it has to start at e1rmSeries: LineChart clears its
  // hover whenever `points` changes identity, so a chart array rebuilt on every render made the
  // tooltip vanish under your finger the moment anything else on this screen re-rendered.
  // Memoising only the .map() would not have helped — its dependency was itself rebuilt each time.
  const e1Pts = useMemo(
    () => (curEx && curMode === 'reps' ? e1rmSeries(S, curEx) : []),
    [S, curEx, curMode],
  )
  const e1ChartPts = useMemo(() => e1Pts.filter(p => p.t >= exFrom).map(p => ({ t: p.t, y: p.y, d: p.d })), [e1Pts, exFrom])
  const e1Best = curEx && curMode === 'reps' ? best1RM(S, curEx) : null
  const showE1 = e1Pts.length > 0
  // Effort on this exercise, per session. It rides on the top-set curve as well as having a
  // curve of its own, because the two only mean something together: the same weight moved
  // with more left in the tank is progress a weight-only chart draws as a flat line.
  const exRir = exPts.map(p => avgRir(p.sets))
  const showEff = exRir.filter(v => v != null).length >= 3
  const effPts = exPts.map((p, i) => (exRir[i] == null ? null : { t: p.t, y: toScale(kind, exRir[i]), d: p.d })).filter(p => p && inExRange(p))
  // Pyramid sets' Max sets: the most reps in one, per workout — the point of a Max set is seeing
  // that number climb, which the top-set weight line does not show.
  const maxPts = useMemo(
    () => (curEx && curMode === 'reps' ? maxRepsSeries(workouts, curEx).map(p => ({ t: p.t, y: p.y, d: p.d, note: p.w > 0 ? fmtNum(p.w) + ' ' + S.unit : undefined })) : []),
    [workouts, curEx, curMode, S.unit],
  )
  const showMax = maxPts.length > 0
  const maxBest = showMax ? Math.max(...maxPts.map(p => p.y)) : 0
  const maxChartPts = useMemo(() => maxPts.filter(p => p.t >= exFrom), [maxPts, exFrom])
  // Per set (issue #145): one line per set number, to see which set you drop off on — often not
  // the last. Offered once two sessions are logged and one of them has two sets or more.
  // Memoised like e1Pts: LineChart drops its hover whenever `points` changes identity.
  // Loaded work is drawn as each set's estimated 1RM, so straight sets at one weight still part
  // where reps were lost. Reps instead for unloaded work, an assistance machine (where a 1RM
  // reads backwards), or a history of sets all past the estimate's rep cap.
  const oneRmFormula = formulaOf(S)
  const perSet = useMemo(() => {
    if (!curEx || curMode !== 'reps') return null
    const usable = list => list.length >= 2 && list.some(s => s.sets.length >= 2)
    let metric = repsOnly || isAssisted(curEx) ? 'reps' : 'e1rm'
    let sessions = perSetSessions(workouts, curEx, { metric, formula: oneRmFormula })
    if (metric === 'e1rm' && !usable(sessions)) sessions = perSetSessions(workouts, curEx, { metric: metric = 'reps' })
    if (!usable(sessions)) return null
    const { lines, hidden } = perSetLines(sessions)
    const shown = new Set(lines.map(l => l.n))
    return {
      series: lines.map(l => ({ n: l.n, points: l.points, color: SET_COLORS[l.n - 1] })),
      anchors: sessions.map(s => ({
        t: s.t, d: s.d, y: Math.max(...s.sets.map(x => x.y)),
        note: s.sets.filter(x => shown.has(x.n)).map(x => x.n + ': ' + (repsOnly ? x.r : fmtNum(x.w) + '×' + x.r)).join(' · '),
      })),
      ns: lines.map(l => l.n),
      hidden,
      metric,
      drop: dropOffSet(sessions),
    }
  }, [workouts, curEx, curMode, repsOnly, oneRmFormula])
  // The same sessions cut to the range; a set number with nothing left in it drops out of the legend.
  const perSetChart = useMemo(() => {
    if (!perSet) return null
    const series = perSet.series.map(s => ({ ...s, points: s.points.filter(p => p.t >= exFrom) })).filter(s => s.points.length)
    return { anchors: perSet.anchors.filter(p => p.t >= exFrom), series, ns: series.map(s => s.n) }
  }, [perSet, exFrom])
  const onSets = !!perSet && exMetric === 'sets'
  const onE1 = showE1 && exMetric === 'e1rm'
  const onEff = showEff && exMetric === 'effort'
  const onMax = showMax && exMetric === 'max'
  const topPts = exPts.map((p, i) => ({
    t: p.t, y: p.y, d: p.d,
    // 0 RIR (nothing left) is a full dot, 4+ a faint one; unrated sessions keep the plain line.
    m: exRir[i] == null ? null : 1 - Math.min(4, Math.max(0, exRir[i])) / 4,
    note: exRir[i] == null ? undefined : hd + ' ' + fmtNum(toScale(kind, exRir[i]))
  })).filter(inExRange)
  const chartPts = onSets ? perSetChart.anchors : onMax ? maxChartPts : onEff ? effPts : onE1 ? e1ChartPts : topPts
  // A line needs two workouts. A range that holds fewer says so, instead of a lone dot or an empty box.
  const rangeTooShort = exRange !== 0 && chartPts.length < 2
  const exOpts = [{ value: 'top', label: t("TOP_SET" /* 最佳组 */) }]
  if (perSet) exOpts.push({ value: 'sets', label: t("PER_SET" /* 每组 */) })
  if (showE1) exOpts.push({ value: 'e1rm', label: t("EST_ONE_REP_MAX" /* 估算 1RM */) })
  if (showEff) exOpts.push({ value: 'effort', label: t("EFFORT" /* 用力程度 */) })
  if (showMax) exOpts.push({ value: 'max', label: t("MAX_REPS" /* 力竭次数 */) })

  return <>
    <div className="hdr"><div><h1>{t("STATS" /* 统计 */)}</h1><div className="sub">{t("PROGRESS_HISTORY" /* 进度与历史 */)}</div></div>
      <button className="iconbtn" onClick={() => nav('/history')} aria-label={t("HISTORY" /* 历史 */)}><Icon name="history" /></button></div>

    <div className="tiles">
      <div className="tile"><div className="l"><Icon name="dumbbell" />{t("WORKOUTS" /* 训练次数 */)}</div><div className="v">{workouts.length}</div></div>
      <div className="tile"><div className="l"><Icon name="calendar" />{t("THIS_MONTH" /* 本月 */)}</div><div className="v">{monthW}</div></div>
      <div className="tile"><div className="l"><Icon name="flame" />{t("WEEK_STREAK" /* 连续周数 */)}</div><div className="v">{streakWeeks(S)}</div></div>
      <div className="tile"><div className="l"><Icon name="scale" />{t("WEIGHT_THREEZEROD" /* 体重 30 天 */)}</div><div className="v" style={{ fontSize: 22, color: bwDelta30 === null ? 'inherit' : bwDeltaColor(bwDelta30, (lastBW(S) || {}).w || 0) }}>{bwDelta30 === null ? '–' : (bwDelta30 > 0 ? '+' : '') + fmtNum(bwDelta30) + ' ' + S.unit}</div></div>

    </div>

    <div className="card">
      <h2>{t("ACTIVITY_LAST_ONETWO_MONTHS" /* 活动（近 12 个月） */)}</h2>
      <Heatmap
        S={S}
        metric={S.heatmapMetric === 'vol' ? 'vol' : 'time'}
        onMetricChange={metric => useStore.getState().update(s => { s.heatmapMetric = metric })}
        onDay={iso => { const ws = workouts.filter(w => workoutDay(w) === iso); if (ws.length === 1) workoutDetailSheet(ws[0]); else if (ws.length) calendarSheet(iso); else dayOverrideSheet(iso) }}
      />
    </div>

    {(workouts.length > 0 || Object.keys(loadOfWeeklyPlan(S)).length > 0) && <MuscleBalance S={S} />}
    {S.routines.length > 0 && <WeeklyPlanVolume S={S} />}
    {workouts.length > 0 && <div className="card row between" style={{ alignItems: 'center', gap: 12 }}>
      <div style={{ minWidth: 0 }}><h2 style={{ margin: 0 }}>{t("STRUCTURAL_BALANCE" /* 结构平衡 */)}</h2>
        <div className="muted small" style={{ marginTop: 4 }}>{t("SEE_WHICH_LIFT_IS_HOLDING_BACK_THE_REST" /* 看看哪个动作拖了其他动作的后腿。 */)}</div></div>
      <Button size="sm" variant="tinted" trailingIcon="chevronRight" style={{ flexShrink: 0 }} onClick={() => nav('/structural-balance')}>{t("OPEN" /* 打开 */)}</Button>
    </div>}
    {workouts.length > 0 && <div className="card row between" style={{ alignItems: 'center', gap: 12 }}>
      <div style={{ minWidth: 0 }}><h2 style={{ margin: 0 }}>{t("PROGRESS_PHOTOS" /* 进度照片 */)}</h2>
        <div className="muted small" style={{ marginTop: 4 }}>{t("EVERY_PHOTO_YOU_KEPT_WITH_A_WORKOUT_LINED_UP_BY_DATE_PLUS" /* 你随训练保存的每张照片，按日期排好。还有前后对比滑块。 */)}</div></div>
      <Button size="sm" variant="tinted" trailingIcon="chevronRight" style={{ flexShrink: 0 }} onClick={() => nav('/progress-photos')}>{t("OPEN" /* 打开 */)}</Button>
    </div>}
    <div className="card row between" style={{ alignItems: 'center', gap: 12 }}>
      <div style={{ minWidth: 0 }}><h2 style={{ margin: 0 }}>{t("BODY_MEASUREMENTS" /* 身体围度 */)}</h2>
        <div className="muted small" style={{ marginTop: 4 }}>{(S.measurements || []).length
          ? t("LAST_CHECK_IN_COUNT" /* 上次记录 {0} */, fmtDate(S.measurements[S.measurements.length - 1].d, true))
          : t("WAIST_ARMS_BODY_FAT_AND_ANYTHING_ELSE_YOU_MEASURE_EACH_WITH_ITS" /* 腰围、手臂、体脂，以及你测量的其他部位，每项都有自己的曲线。 */)}</div></div>
      <Button size="sm" variant="tinted" trailingIcon="chevronRight" style={{ flexShrink: 0 }} onClick={() => nav('/measurements')}>{t("OPEN" /* 打开 */)}</Button>
    </div>
    {(hasEffort(S) || hasEstimableEffort(S)) && <EffortCard S={S} />}

    <div className="cols">
      <div className="card">
        <div className="row between bw-head" style={{ marginBottom: 8 }}>
          <h2 style={{ margin: 0 }}>{t("BODY_WEIGHT" /* 体重 */)}</h2>
          <div className="row" style={{ gap: 8 }}>
            <Button size="sm" icon="target" style={S.targetW ? { color: 'var(--yellow)' } : undefined} onClick={goalSheet}>{S.targetW ? fmtNum(S.targetW) : t("GOAL" /* 目标 */)}</Button>
            <Button size="sm" icon="plus" onClick={() => bwSheet()}>{t("LOG" /* 记录 */)}</Button>
          </div>
        </div>
        <Segmented className="seg-range" value={range} onChange={setRange}
          options={rangeOptions()} />
        <div className="chart"><LineChart points={bwPts} h={160} unit={S.unit} goal={S.targetW} /></div>
        {/* every weigh-in, week by week with its average (Discord 'Weight') */}
        {S.bodyweight.length > 0 && <div className="row" style={{ justifyContent: 'flex-end', marginTop: 4 }}>
          <Button size="sm" variant="ghost" trailingIcon="chevronRight" onClick={weighInsSheet}>{t("ALL_WEIGH_INS" /* 全部称重记录 */)}</Button>
        </div>}
      </div>

      <div className="card">
        <h2>{t("EXERCISE_PROGRESS" /* 动作进步 */)}</h2>
        {exHist.length ? <>
          <div className="sect-b" style={{ marginBottom: 10 }}>
            <SelectRow title={t("EXERCISE" /* 动作 */)} sheetTitle={t("EXERCISE_PROGRESS" /* 动作进步 */)} value={curEx} onChange={setExId} stackedValue
              options={exHist.map(id => ({ value: id, label: (EXIDX[id] ? exerciseNameText(EXIDX[id]) : nameOf(id)) + (exCurrent[id].mx ? ' · ' + fmtNum(exCurrent[id].mx) + ' ' + exCurrent[id].unit : '') }))}
              search={{
                placeholder: t("SEARCH" /* 搜索… */),
                label: t("SEARCH" /* 搜索… */),
                emptyLabel: t("NO_MATCH" /* 没有匹配 */),
                match: (option, query) => matchExercise(matcherOf(option.value), query),
              }} />
          </div>
          {exOpts.length > 1 && <Segmented className="seg-range" value={onMax ? 'max' : onEff ? 'effort' : onE1 ? 'e1rm' : onSets ? 'sets' : 'top'} onChange={setExMetric} options={exOpts} />}
          <Segmented className="seg-range" value={exRange} onChange={setExRange} options={rangeOptions()} />
          <div className="chart">
            {rangeTooShort
              ? <div className="empty small">{t("FEWER_THAN_TWO_WORKOUTS_IN_THIS_PERIOD_PICK_A_LONGER_ONE" /* 此期间的训练少于两次，请选择更长的期间。 */)}</div>
              : onSets
              ? <LineChart points={perSetChart.anchors} series={perSetChart.series} h={150} unit={perSet.metric === 'reps' ? t("REPS_A" /* 次 */) : S.unit} />
              : onMax
              ? <LineChart points={maxChartPts} h={150} unit={t("REPS_A" /* 次 */)} color="var(--blue)" />
              : onEff
              ? <LineChart points={effPts} h={150} unit={hd} color="var(--yellow)" invert={kind === 'rir'} />
              : <LineChart points={chartPts} h={150} unit={exUnit} color="var(--blue)" />}
          </div>
          {onSets && !rangeTooShort && <div className="row small" style={{ gap: 12, flexWrap: 'wrap', marginTop: 6 }}>
            {perSetChart.ns.map(n => <span key={n} className="row" style={{ gap: 5, alignItems: 'center' }}>
              <span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: 4, background: SET_COLORS[n - 1] }} />{t("SET_COUNT" /* 第 {0} 组 */, n)}
            </span>)}
          </div>}
          <div style={{ marginTop: 8 }}>{exList.map((p, i) => <div key={i} className="row between small" style={{ padding: '6px 0', borderBottom: 'var(--hair) solid var(--sep)' }}>
            <span className="muted">{fmtDate(p.d, true)}</span><span>{p.sets.map(s => setLabel(curEx, s, p.target, speedUnit)).join('  ')}</span></div>)}</div>
          <div className="small dim" style={{ marginTop: 8 }}>
            {onSets ? (perSet.metric === 'reps' ? t("REPS_IN_EACH_WORKING_SET_ONE_LINE_PER_SET_NUMBER" /* 每个工作组的次数，每个组号一条线 */) : t("ESTIMATED_ONE_REP_MAX_OF_EACH_WORKING_SET_ONE_LINE_PER_SET" /* 每个工作组的估算 1RM，每个组号一条线 */)) : onMax ? <>{t("MOST_REPS_IN_A_MAX_SET_PER_WORKOUT" /* 每次训练中力竭组的最多次数 */)} · {t("BEST" /* 最佳： */)}{' '}<b className="accent">{maxBest} {t("REPS_A" /* 次 */)}</b></> : onEff ? t("AVERAGE_EFFORT_PER_WORKOUT" /* 每次训练的平均强度 */) : onE1 ? t("ESTIMATED_ONE_REP_MAX_PER_WORKOUT" /* 每次训练的估算 1RM */) : curCardio ? t("TOP_SPEED_PER_WORKOUT" /* 每次训练最高速度 */) : curTimed ? t("LONGEST_HOLD_PER_WORKOUT" /* 每次训练的最长保持时间 */) : repsOnly ? t("MOST_REPS_IN_A_SET_PER_WORKOUT" /* 每次训练单组最多次数 */) : t("BEST_SET_WEIGHT_PER_WORKOUT" /* 每次训练最佳组重量 */)}
            {onEff || onMax || onSets ? '' : <> · {t("BEST" /* 最佳： */)}{' '}<b className="accent">{fmtNum(onE1 ? e1Best.est : exBest)} {onE1 ? S.unit : exUnit}</b></>}
          </div>
          {onSets && (perSet.drop || perSet.hidden > 0) && <div className="small dim" style={{ marginTop: 4 }}>
            {perSet.drop && t("WHERE_YOU_MOST_OFTEN_DROP_OFF_SET_COUNT_COUNT_OF_COUNT_WORKOUTS" /* 最常掉的组：第 {0} 组（{2} 次训练中 {1} 次） */, perSet.drop.n, perSet.drop.count, perSet.drop.of)}
            {perSet.drop && perSet.hidden > 0 ? ' · ' : ''}
            {perSet.hidden > 0 && t("ONLY_THE_FIRST_COUNT_SETS_ARE_DRAWN" /* 只绘制前 {0} 组。 */, perSet.ns.length)}
          </div>}
          {onE1 && <div className="small dim" style={{ marginTop: 4 }}>
            {t("BEST_ESTIMATE_FROM_COUNT_ON_COUNT_AN_ESTIMATE_NOT_A_TESTED_MAX" /* 基于 {1} 的 {0} 得出的最佳预估。这是推算值，不是实测极限。 */, fmtNum(e1Best.w) + ' ' + S.unit + ' × ' + e1Best.r, fmtDate(e1Best.d, true))}
          </div>}
          {!onEff && !onE1 && !onMax && !onSets && showEff && <div className="small dim" style={{ marginTop: 4 }}>
            {t("A_FULLER_DOT_MEANS_LESS_LEFT_IN_THE_TANK_THE_SAME_WEIGHT" /* 点越实，说明油箱里剩得越少。同样的重量配上更低的 {0}，是光看曲线看不出来的进步。 */, hd)}
          </div>}
        </> : <div className="muted small">{t("FINISH_YOUR_FIRST_WORKOUT_AND_YOUR_PROGRESS_CURVES_WILL_SHOW_UP_HERE" /* 完成第一次训练，你的进度曲线就会出现在这里。 */)}</div>}
      </div>
    </div>

    {workouts.length > 0 && <>
      <div className="row between" style={{ marginBottom: 10 }}>
        <h4 className="sec" style={{ margin: 0 }}>{t("RECENT_WORKOUTS" /* 最近训练 */)}</h4>
        <Button size="sm" variant="ghost" trailingIcon="chevronRight" onClick={() => nav('/history')}>{t("ALL" /* 全部 */)} {workouts.length}</Button>
      </div>
      <div className="list">{[...workouts].reverse().slice(0, 6).map(w => <WorkoutRow key={w.id} w={w} onClick={() => workoutDetailSheet(w)} />)}</div>
    </>}
  </>
}
