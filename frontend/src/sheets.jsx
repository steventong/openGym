import { useDeferredValue, useEffect, useMemo, useRef, useState } from 'react'
import { useStore } from './store/useStore.js'
import { useUI } from './store/useUI.js'
import { EXDB, EXIDX, BODYPARTS, isCardio, isBodyweightEq, allExercises, equipmentOf, byCategory, smOf, searchExercises, similarExercises, exOr, isAssisted, betterWeight, beatsWeight, isCustomEx } from './lib/exercises.js'
import { activeProfile, exAvailable, ALL_EQUIPMENT, newProfile, profileEquipment, ACC_V } from './lib/equipment.js'
import { fmtDate, fmtDateRange, fmtNum, fmtPlate, exerciseNameText, fmtVol, fmtDur, durPart, todayISO, isoOf, uid, exCount, routineCount, setsWorkCount, DAYN, DAYS, weekOrder, weekStartOf, weekDayOffset, MONTHS_LONG, ACCENTS } from './lib/format.js'
import { lastEntryFor, bestWeightFor, bestWeightForEntry, buildSets, effectiveRoutineIds, workoutDay, workoutVolume, setsDone, setsDoneActive, setUnitsTotal, lastBW, sessionSections, setLabel, defaultConfig, cleanupSg, modeOf, effortOf, EFFORT, capEffort, stepEffort, isBw, isPerSide, sideReps, workSetsDone, applyIntensifierPlan, MAX_PLANNED_WARMUPS, NOTE_MAX, SESSION_NOTE_MAX } from './lib/history.js'
import { usesBar, defaultBarWeight, hasBarOverride, isNoBar } from './lib/bar.js'
import { PLATE_SIZES, pairsOf, ownsPlates, withPlatePairs, withStandardPlates, withLoadKind, loadKindFor, baseWeightFor, dropGrid } from './lib/plates.js'
import { toScale, rirOf, EFFORT_PRESETS, effortColor } from './lib/effort.js'
import { beep, vibrate } from './lib/sound.js'
import { t, tn, dateLocale, instrFor, instrTranslated, descFor, exerciseNameFor, exerciseNameClass, getLang, useLang , translateValue } from './lib/i18n.js'
import { nav, closeThenNav, navToWorkout } from './lib/nav.js'
import { buildStarterPlan, starterPlanDays, starterPlanOptions } from './lib/starter.js'
import Media, { Thumb } from './components/Media.jsx'
import CustomMediaField from './components/CustomMediaField.jsx'
import WorkoutMediaSection, { workoutMediaCount } from './components/WorkoutMedia.jsx'
import { mediaOf, normalizeMediaRef, cleanUrl, workoutMediaOf } from './lib/media-refs.js'
import { syncMedia } from './lib/media-sync.js'
import LineChart from './components/LineChart.jsx'
import Stepper from './components/Stepper.jsx'
import { durationSheet } from './components/DurationWheel.jsx'
import { SG_NAME_MAX } from './lib/superset-meta.js'
import { REST_MAX, fmtRest } from './lib/duration.js'
import Icon from './components/Icon.jsx'
import { Button, Slider, Switch, Segmented, SelectRow, Row, TextField, NumberField, MultiSelectRow } from './components/ui.jsx'
import { glyphOf, GLYPH_GROUPS, DEFAULT_GLYPH } from './lib/glyphs.js'
import BodyMap from './components/BodyMap.jsx'
import MuscleExplorer from './components/MuscleExplorer.jsx'
import ExerciseViewToggle from './components/ExerciseViewToggle.jsx'
import { sameMuscleFirst, swapMuscleOf } from './lib/similar-exercises.js'
import { exerciseMuscleSnapshot, loadOfWorkouts, MUSCLES, MUSCLE_NAME, muscleWeightsOf, normalizeMuscleGroups, hasExplicitMuscleMetadata, inMuscleOrder } from './lib/muscles.js'
import { parseImport, mergeImport } from './lib/import-csv.js'
import { importHevyData, HevyApiError, HEVY_DEV_SETTINGS, mergeHevyRoutines } from './lib/import-hevy.js'
import { buildPlanBundle, parsePlan, mergePlan, printPlan, planPrintHTML } from './lib/plan-share.js'
import { estimate1RM, best1RM, is1RMRecord, REP_CAP, formulaOf, FORMULA_NAMES } from './lib/onerm.js'
import { exerciseHistory } from './lib/exercise-history.js'
import { isBellEx, dbLoadOf, dbLoadFor, withDbLoad, withMeaning, historyAs, entryDbLoad, currentDbLoad, isOneArm, ownedWeightsFor, dumbbellsOf, ownsDumbbells, withDumbbells, presetWeights, cleanWeights } from './lib/dumbbells.js'
import { policyFor, defaultIncrement, POLICIES_FOR, POLICY_NAME, POLICY_DESC, MAX_BW_SETS, MAX_TRIPLE_SETS, weightIncrement } from './lib/progression.js'
import { normalizeRepRange } from './lib/rep-range.js'
import { isBackoff, backoffWeights } from './lib/backoff.js'
import { isPyramid, normalizePyramid, normalizePyramidRest, normalizePyramidWeight, pyramidFromFlat, flatFromPyramid, pyramidLabel, PYRAMID_MAX, MAX_PYRAMID_SETS, PYRAMID_PRESETS } from './lib/pyramid.js'
import { MOBILE, shareExport, shareExportBlob, printHtml } from './lib/mobile.js'
import { speedUnitOf, toSpeed, fromSpeed } from './lib/speed.js'
import { buildCompletedWorkout, sessionEnd } from './lib/finish-workout.js'
import { refillAfter } from './lib/rotation.js'
import { isWarmupRow, hasCompletedWork } from './lib/workout-model.js'
import { saveSessionAsRoutine } from './lib/session-routines.js'
import { repeatSessionEntries } from './lib/session-repeat.js'
import { swapActiveExercise } from './lib/active-exercise-swap.js'
import { useSheetKeyboard, useRevealActiveChip, tappable } from './lib/use-sheet-keyboard.js'
import { useAutoMore } from './lib/use-auto-more.js'
import { isFav, toggleFav, sortFavouritesFirst, sortYoursFirst } from './lib/favourites.js'
import { buildSessionEntries, buildPlannedEntry, builtOutOfProgression } from './lib/session-start.js'
import { finishCompare, finishCardio } from './lib/finish-compare.js'
import { workoutFit, fitFileName } from './lib/fit-export.js'
import { joinSessionNoProg } from './lib/session-noprog.js'
import { buildCombinedEntries, deriveSessionName } from './lib/session-merge.js'
import { workoutsOn, backfillStart, backfillEnd, completeBackfill, historyAsOf, sessionHistory } from './lib/backfill.js'
import { moveWorkout, sameWorkout, startTimeOf, durationMinOf, setWorkoutDuration, rebuildPrHistory, MAX_DURATION_MIN, endsInFuture } from './lib/workout-date.js'
import { editCompletedSession, editLeftEmpty, editedRecord, editChangesNothing } from './lib/session-edit.js'
import { stampWorkout } from './lib/sync-merge.js'
import { weeklyWeights } from './lib/bodyweight.js'
import { workoutText } from './lib/workout-text.js'
import { workoutCardModel, layoutWorkoutCard, drawWorkoutCard, viewAspect, CARD_FONT } from './lib/workout-card.js'
import { copyText } from './lib/clipboard.js'
import { queueRemaining, pinState } from './lib/queue.js'
import { DAY_NOTE_TAGS, DAY_NOTE_LABEL, DAY_NOTE_ICON, dayNoteOf, dayNoteLine, canNoteDay, withDayNote } from './lib/day-notes.js'

const S = () => useStore.getState().S
const update = (...a) => useStore.getState().update(...a)
const ui = () => useUI.getState()
const toast = m => ui().toast(m)
const snd = () => S().sound

/* ============================ custom confirm dialog ============================ */
function ConfirmDialog({ title, message, confirmText, cancelText, danger, onConfirm, onCancel, close }) {
  return <div style={{ textAlign: 'center', padding: '4px 0' }}>
    {title && <h3 style={{ marginBottom: 8 }}>{title}</h3>}
    <div className="muted" style={{ marginBottom: 18, lineHeight: 1.5 }}>{message}</div>
    <button className={'btn ' + (danger ? 'danger' : 'primary')} onClick={() => { close(); onConfirm && onConfirm() }}>{confirmText || t("CONFIRM" /* 确认 */)}</button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={() => { close(); onCancel && onCancel() }}>{cancelText || t("CANCEL" /* 取消 */)}</Button>
  </div>
}
// "1 workouts and 1 weigh-ins" read wrong: a count of one takes the singular, per noun. Four
// whole sentences rather than two spliced counts, so every language keeps its own word order.
export function addDeviceDataMessage(workouts, weighIns) {
  const one = n => Number(n) === 1
  return one(workouts)
    ? one(weighIns)
      ? t("COUNT_WORKOUT_AND_COUNT_WEIGH_IN_WERE_LOGGED_ON_THIS_DEVICE_WHILE" /* 此设备在未登录时记录了 {0} 次训练和 {1} 次体重。把它们加入你的个人资料，或保持个人资料与服务器上的完全一致。 */, workouts, weighIns)
      : t("COUNT_WORKOUT_AND_COUNT_WEIGH_INS_WERE_LOGGED_ON_THIS_DEVICE_WHILE" /* 此设备在未登录时记录了 {0} 次训练和 {1} 次体重。把它们加入你的个人资料，或保持个人资料与服务器上的完全一致。 */, workouts, weighIns)
    : one(weighIns)
      ? t("COUNT_WORKOUTS_AND_COUNT_WEIGH_IN_WERE_LOGGED_ON_THIS_DEVICE_WHILE" /* 此设备在未登录时记录了 {0} 次训练和 {1} 次体重。把它们加入你的个人资料，或保持个人资料与服务器上的完全一致。 */, workouts, weighIns)
      : t("COUNT_WORKOUTS_AND_COUNT_WEIGH_INS_WERE_LOGGED_ON_THIS_DEVICE_WHILE" /* 此设备在未登录时记录了 {0} 次训练和 {1} 次体重。把它们加入你的个人资料，或保持个人资料与服务器上的完全一致。 */, workouts, weighIns)
}
// Sign-in found workouts on this device that the profile does not have (logged while signed
// out). The profile is the truth — settings and plan come from the server either way — the
// question is only whether these entries are added to it or dropped. Resolves true to add.
// Routines and the rest of a plan made here while signed out: asked about as well (they come along
// with "Add them"), in their own words when there is nothing else.
export function addDeviceSetupMessage(routines) {
  const n = Number(routines) || 0
  return n === 0
    ? t("YOUR_PLAN_NOTES_OR_GYM_CARDS_ON_THIS_DEVICE_WERE_SET_UP" /* 此设备在未登录时设置了计划、备注或健身房卡。把它们加入你的个人资料，或保持个人资料与服务器上的完全一致。 */)
    : n === 1
      ? t("COUNT_ROUTINE_WAS_MADE_ON_THIS_DEVICE_WHILE_SIGNED_OUT_ADD_IT" /* 此设备在未登录时创建了 {0} 个训练计划。把它加入你的个人资料，或保持个人资料与服务器上的完全一致。 */, n)
      : t("COUNT_ROUTINES_WERE_MADE_ON_THIS_DEVICE_WHILE_SIGNED_OUT_ADD_THEM" /* 此设备在未登录时创建了 {0} 个训练计划。把它们加入你的个人资料，或保持个人资料与服务器上的完全一致。 */, n)
}
export function askAddDeviceData(extras) {
  const logged = extras.workouts || extras.bodyweight || extras.customEx
  return new Promise(resolve => confirmSheet({
    title: logged ? t("ADD_THIS_DEVICE_S_WORKOUTS_TO_YOUR_PROFILE" /* 把此设备上的训练加入你的个人资料？ */) : t("ADD_THIS_DEVICE_S_PLAN_TO_YOUR_PROFILE" /* 把此设备上的计划加入你的个人资料？ */),
    message: logged ? addDeviceDataMessage(extras.workouts, extras.bodyweight) : addDeviceSetupMessage(extras.routines),
    confirmText: t("ADD_THEM" /* 加入 */), cancelText: t("KEEP_PROFILE_AS_IS" /* 保持不变 */),
    onConfirm: () => resolve(true), onCancel: () => resolve(false), locked: true
  }))
}
/* ============================ menu sheet ============================ */
// A list of actions, one per row, closing on tap. This is where the workout screen parks
// everything that is not a set you are about to log: the point of a single "more" button is
// that the ten things you do once a session stop competing with the two you do every set.
// items: [{ icon, label, sub, onClick, danger, disabled, on }] — `on` draws a check for toggles.
// sections: [{ title, items }] instead of `items` splits a longer menu into groups, each with an
// optional small header; a group whose items are all falsy is left out, header and all.
// `accent` tints a row's icon, for the one entry a menu leads with.
// A title is shown as written: most are sentences ("Convert to lb?", "Set 2"), which a default
// title-casing turned into "Convert To Lb?". An exercise name passes exerciseNameClass as
// titleClass, which title-cases the lower-case packs and leaves a cased one alone.
function MenuSheet({ title, titleClass = '', subtitle, items, sections, close }) {
  const groups = (sections || [{ items }])
    .map(g => ({ title: g.title, items: (g.items || []).filter(Boolean) }))
    .filter(g => g.items.length)
  return <>
    {title && <h3 className={titleClass || undefined} style={{ marginBottom: subtitle ? 2 : 10 }}>{title}</h3>}
    {subtitle && <div className="muted small" style={{ marginBottom: 10 }}>{subtitle}</div>}
    {groups.map((g, gi) => <div key={gi} className={'menu-group' + (sections ? ' grouped' : '')}>
      {g.title && <div className="menu-sec">{g.title}</div>}
      <div className="list menu-list">
        {g.items.map((it, i) => <div key={i}
          className={'item menu-item' + (it.danger ? ' danger' : '') + (it.disabled ? ' disabled' : '') + (it.accent ? ' accent' : '')}
          aria-disabled={it.disabled || undefined}
          {...tappable(it.disabled ? null : () => { close(); it.onClick && it.onClick() })}>
          {it.icon && <span className="lrow-i"><Icon name={it.icon} /></span>}
          <div className="grow"><div className="tt">{it.label}</div>{it.sub && <div className="ss">{it.sub}</div>}</div>
          {it.on != null && <span className={'menu-on' + (it.on ? ' is-on' : '')}><Icon name="check" /></span>}
          {it.chevron && <Icon name="chevronRight" className="menu-chev" />}
        </div>)}
      </div>
    </div>)}
  </>
}
export function menuSheet(opts) {
  ui().openSheet(close => <MenuSheet {...opts} close={close} />)
}

// Themed replacement for window.confirm — callback-based (no blocking).
export function confirmSheet(opts) {
  ui().openSheet(close => <ConfirmDialog {...opts} close={close} />, { kind: 'center', ...(opts.locked ? { locked: true } : {}) })
}

/* ============================ starter plan ============================ */
// Plan names and blurbs live here, not in lib/starter.js: check-source-strings.mjs only finds
// string literals written inside a t() call, so copy parked in the catalog and passed in as a
// variable is invisible to it — it would quietly stay English in every language.
const PLAN_COPY = {
  ppl: () => ({ name: t("PUSH_PULL_LEGS" /* 推 / 拉 / 腿 */), about: t("PUSH_PULL_AND_LEGS_EACH_GET_THEIR_OWN_DAY" /* 推、拉、腿各占一天。 */) }),
  'upper-lower': () => ({ name: t("UPPER_LOWER" /* 上肢 / 下肢 */), about: t("UPPER_BODY_TWICE_LOWER_BODY_TWICE" /* 上肢两次，下肢两次。 */) }),
  'full-body': () => ({ name: t("FULL_BODY" /* 全身 */), about: t("THREE_SESSIONS_THE_WHOLE_BODY_EACH_TIME" /* 三次训练，每次练全身。 */) }),
  '5x5': () => ({ name: t("FIVE_FIVE" /* 术语：5×5 */), about: t("FIVE_SETS_OF_FIVE_ON_THE_MAIN_BARBELL_LIFTS" /* 主要杠铃动作五组五次。 */) })
}

// Adds the plan's routines (reusing one you already have under the same name) and puts them on
// its weekdays. Existing routines are never touched
// and only the weekdays the plan asks for are reassigned; an id with no plan behind it changes
// nothing at all. planId is deliberately required — a default invites `onClick={loadStarterPlan}`,
// which hands the click event in as the plan and silently loads nothing.
export function loadStarterPlan(planId, profile) {
  const plan = buildStarterPlan(planId, profile ? profileEquipment(profile) : undefined)
  if (!plan) return false
  update(st => {
    // Loading the same plan again reuses the routines it added last time (same name, same
    // exercises) for the weekdays instead of a second Upper A, Lower A, ... under the same names.
    // A plan fitted to different equipment has other exercises, so it is added alongside.
    const idOf = {}
    const sameLift = (a, b) => a.ex.length === b.ex.length && a.ex.every((e, i) => e.id === b.ex[i].id)
    plan.routines.forEach(r => {
      const have = st.routines.find(x => x.name === r.name && sameLift(x, r))
      if (have) idOf[r.id] = have.id
      else { st.routines.push(r); idOf[r.id] = r.id }
    })
    plan.schedule.forEach(({ day, routineId }) => { st.week[day] = [idOf[routineId]] })
  })
  if (plan.fit) toast(t("COUNT_LOADED_FITTED_TO_COUNT_COUNT_SWAPPED_COUNT_DROPPED" /* 已加载{0}，并按“{1}”调整：替换 {2} 项，移除 {3} 项 */, PLAN_COPY[planId]().name, profile.name, plan.fit.swapped, plan.fit.dropped))
  else toast(t("COUNT_LOADED" /* 已加载{0} */, PLAN_COPY[planId]().name))
  return true
}

// Intl joins the days the way each language does it — "and" vs "und", "、" in Chinese.
const dayList = days => new Intl.ListFormat(dateLocale()).format(days.map(d => translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYN[d])))

function StarterPlanChooser({ close }) {
  const week = useStore(s => s.S.week)
  const routines = useStore(s => s.S.routines)
  const profiles = useStore(s => s.S.equipProfiles) || []
  // Fitting starts on for the profile you already filter by; '' leaves the plan as written.
  const [fitId, setFitId] = useState(() => activeProfile(useStore.getState().S)?.id || '')
  const fit = profiles.find(p => p.id === fitId) || null
  const choose = (id, name) => {
    const days = starterPlanDays(id)
    close()
    // A confirmation is only worth showing when one of those days is actually occupied — by a
    // routine that still exists, not by a stale id the Plan already shows as "Rest".
    const taken = day => [].concat(week[day] || []).some(id => routines.some(r => r.id === id))
    if (!days.some(taken)) { loadStarterPlan(id, fit); return }
    confirmSheet({
      title: t("LOAD_COUNT" /* 加载{0}？ */, name),
      message: t("THE_NEW_PLAN_GOES_ON_COUNT_YOUR_EXISTING_ROUTINES_STAY_ONLY_THOSE" /* 新计划会排在{0}。你现有的训练计划都会保留，每周计划里只有这几天会变。 */, dayList(days)),
      confirmText: t("LOAD_PLAN" /* 加载计划 */),
      onConfirm: () => loadStarterPlan(id, fit)
    })
  }
  return <>
    <h3>{t("CHOOSE_STARTER_PLAN" /* 选择入门计划 */)}</h3>
    {profiles.length > 0
      ? <div className="chips" style={{ margin: '0 0 10px' }}>
          <div className="small dim" style={{ width: '100%' }}>{t("FIT_TO_MY_EQUIPMENT" /* 按我的器械调整 */)}</div>
          <button className={'chip nocap' + (!fit ? ' on' : '')} onClick={() => setFitId('')}>{t("AS_WRITTEN" /* 保持原样 */)}</button>
          {profiles.map(p => <button key={p.id} className={'chip nocap' + (fit?.id === p.id ? ' on' : '')} onClick={() => setFitId(p.id)}>{p.name}</button>)}
        </div>
      : <div className="small dim" style={{ margin: '0 0 10px' }}>{t("ADD_AN_EQUIPMENT_PROFILE_IN_SETTINGS_TO_FIT_A_PLAN_TO_WHAT" /* 在设置中添加器械配置，即可让计划适配你拥有的器械。 */)}</div>}
    <div className="list">
      {starterPlanOptions().map(({ id, days }) => {
        const { name, about } = PLAN_COPY[id]()
        return <div key={id} className="item" {...tappable(() => choose(id, name))}>
          <span className="lrow-i" style={{ background: 'var(--surface-3)' }}><Icon name="clipboard" /></span>
          <div className="grow"><div className="tt">{name}</div><div className="ss">{t("COUNT_DAYS_PER_WEEK" /* 每周 {0} 天 */, days)} · {about}</div></div>
          <Icon name="chevronRight" className="chev" />
        </div>
      })}
    </div>
  </>
}

export const starterPlanSheet = () => ui().openSheet(close => <StarterPlanChooser close={close} />)

/* ============================ weight picker (shared: body weight + goal) ============================ */
// Fixed range, not a moving window — a window that resizes itself mid-drag (the previous
// attempt) makes the thumb's position unpredictable: every time it grows, everything already
// placed on it shifts toward one side. A static range never has that problem, at the cost of
// coarser precision per pixel — the +/- buttons, and typing straight into the read-out, cover
// exact values.
// The ceiling follows the profile's unit: 300 covers a body weight or a working weight in
// kg, but as pounds it cut off at 136 kg — below plenty of people's body weight, and well
// below an everyday squat.
const W_LO = 1
const wHi = unit => (unit === 'lb' ? 660 : 300)
// A typed body weight may sit past the slider (a 320 kg lifter is real), but not past any
// person: 9999 saved, drew the chart from -0 to 10,000 and set a goal 9,922 kg away.
const bwMax = unit => (unit === 'lb' ? 1500 : 700)
const bwTooHeavy = (n, unit) => {
  if (n <= bwMax(unit)) return false
  toast(t("THAT_LOOKS_TOO_HEAVY_KEEP_IT_AT_COUNT_OR_LESS" /* 这好像太重了。最多 {0}。 */, fmtNum(bwMax(unit)) + ' ' + unit))
  return true
}
function WeightInput({ value, setValue, unit }) {
  const W_HI = wHi(unit)
  const clamp = x => Math.max(W_LO, Math.min(W_HI, Math.round((x || 0) * 10) / 10))
  const sv = Math.max(W_LO, Math.min(W_HI, value))
  const onSlide = v => setValue(clamp(v))
  const onType = v => setValue(v)

  return <>
    <div className="bwstep">
      <button className="bw-pm" onClick={() => onSlide(value - 0.1)} aria-label={t("DECREASE_BY_COUNT" /* 减少 {0} */, fmtNum(0.1))}><Icon name="minus" /></button>
      <label className="bw-read">
        <NumberField fit value={value} onChange={onType} aria-label={t("WEIGHT_COUNT" /* 重量（{0}） */, unit)} enterKeyHint="done"
          onKeyDown={e => { if (e.key === 'Enter') e.currentTarget.blur() }} />
        <span className="u"> {unit}</span>
      </label>
      <button className="bw-pm" onClick={() => onSlide(value + 0.1)} aria-label={t("INCREASE_BY_COUNT" /* 增加 {0} */, fmtNum(0.1))}><Icon name="plus" /></button>
    </div>
    <div className="chips" style={{ justifyContent: 'center', margin: '8px 0' }}>
      <button className="chip" onClick={() => onSlide(value - 1)}>−1</button>
      <button className="chip" onClick={() => onSlide(value - 0.5)}>−0.5</button>
      <button className="chip" onClick={() => onSlide(value + 0.5)}>+0.5</button>
      <button className="chip" onClick={() => onSlide(value + 1)}>+1</button>
    </div>
    <Slider value={sv} min={W_LO} max={W_HI} step={0.5} onChange={onSlide} />
  </>
}

/* ============================ body weight ============================ */
function BwSheet({ required, onDone, close }) {
  const st = useStore(s => s.S)
  const unit = st.unit
  const bw = lastBW(st)
  const [v, setV] = useState(bw ? bw.w : 70)
  const save = () => {
    const n = Math.round((v || 0) * 10) / 10
    if (!n || n <= 0) { toast(t("ENTER_A_VALID_WEIGHT" /* 请输入有效的重量 */)); return }
    if (bwTooHeavy(n, unit)) return
    update(s => {
      const iso = todayISO()
      const ex = s.bodyweight.find(b => b.d === iso)
      if (ex) { ex.w = n; ex.t = Date.now() } else s.bodyweight.push({ d: iso, w: n, t: Date.now() })
      s.bodyweight.sort((a, b) => (a.d < b.d ? -1 : 1))
    })
    close()
    if (onDone) onDone(n); else toast(t("WEIGHT_SAVED" /* 体重已保存 */))
  }
  const recent = [...st.bodyweight].reverse().slice(0, 3)
  return <>
    {/* This sheet opens `locked` — swipe/backdrop/Escape/Android-back all no-op on it (see
        Modals.jsx) so an accidental tap on "Start" can't be walked back by reflex the way
        every other sheet in the app can. The two buttons below already cover leaving it
        deliberately; this is the same close a normal sheet gets everywhere else, just
        opted back in explicitly instead of by omission. Plain close() — no onDone, no
        nav — so it's a true no-op: the screen underneath is exactly where you left it. */}
    {required
      ? <div className="row between" style={{ marginBottom: 14 }}>
          <h3 style={{ marginBottom: 0 }}>{t("QUICK_CHECK_IN" /* 快速称重 */)}</h3>
          <button className="iconbtn" aria-label={t("CANCEL" /* 取消 */)} onClick={() => close()}><Icon name="xmark" /></button>
        </div>
      : <h3>{t("LOG_BODY_WEIGHT" /* 记录体重 */)}</h3>}
    <div className="muted small">{required ? t("SLIDE_OR_TAP_TO_SET_YOUR_WEIGHT_WE_ASK_BEFORE_EVERY_WORKOUT" /* 滑动或点按记录体重。每次训练前称重，方便持续跟踪体重变化。 */) : t("TODAY" /* 今天 */) + ', ' + fmtDate(todayISO(), true)}</div>
    <WeightInput value={v} setValue={setV} unit={unit} />
    <div style={{ height: 14 }} />
    <Button variant="primary" onClick={save}>{required ? t("SAVE_START_WORKOUT" /* 保存并开始训练 */) : t("SAVE" /* 保存 */)}</Button>
    {required && <>
      <div style={{ height: 8 }} /><Button variant="ghost" className="dim" onClick={() => { close(); onDone && onDone(null) }}>{t("START_WITHOUT_WEIGHING_IN" /* 不称重直接开始 */)}</Button>
      <div style={{ height: 2 }} /><Button variant="ghost" className="dim" icon="swap" onClick={() => closeThenNav(close, '/workout')}>{t("CHOOSE_A_DIFFERENT_WORKOUT" /* 选择其他训练 */)}</Button>
    </>}
    {!required && recent.length > 0 && <>
      <h4 className="sec">{t("RECENT_WEIGH_INS" /* 最近称重 */)}</h4>
      <div className="list" style={{ gap: 0 }}>
        {recent.map(b => <WeighInRow key={b.d} b={b} unit={unit} />)}
      </div>
      {st.bodyweight.length > recent.length && <div className="row" style={{ justifyContent: 'flex-end', marginTop: 6 }}>
        <Button size="sm" variant="ghost" trailingIcon="chevronRight" onClick={weighInsSheet}>{t("ALL_WEIGH_INS" /* 全部称重记录 */)}</Button>
      </div>}
    </>}
  </>
}
export function bwSheet(opts = {}) {
  const h = ui().openSheet(close => <BwSheet {...opts} close={close} />, { locked: !!opts.required })
  return h
}

// One weigh-in with its delete button, in the log sheet's recent three and in the full list.
// The full list asks first (`confirm`): it is months of history scrolled through on a phone, and a
// stray tap on one of its trash buttons took a past weigh-in with nothing to bring it back. The log
// sheet's three are the ones just typed, where taking back a typo in one tap is the point.
function WeighInRow({ b, unit, confirm = false }) {
  const delEntry = () => update(s => { s.bodyweight = s.bodyweight.filter(x => x.d !== b.d) })
  const ask = () => confirmSheet({
    title: t("DELETE_WEIGH_IN" /* 删除称重记录？ */), message: `${fmtDate(b.d, true)} · ${fmtNum(b.w)} ${unit}`,
    confirmText: t("DELETE" /* 删除 */), danger: true, onConfirm: delEntry,
  })
  return <div className="row between" style={{ padding: '9px 2px', borderBottom: '1px solid var(--sep)' }}>
    <span className="small muted">{fmtDate(b.d, true)}</span>
    <span className="row" style={{ gap: 12 }}><b>{fmtNum(b.w)} {unit}</b>
      <button className="iconbtn" style={{ width: 32, height: 30, borderRadius: 8, fontSize: 15, color: 'var(--red)' }} onClick={confirm ? ask : delEntry} aria-label={t("DELETE_WEIGH_IN_A" /* 删除称重记录 */)}><Icon name="trash" /></button></span>
  </div>
}

/* ============================ weigh-ins ============================ */
// Every weigh-in, week by week (Discord 'Weight'): each week under its mean and how far that
// moved from the week before, the numbers behind the curve on the card. The chart plots the
// weekly means, since the swing from one morning to the next is what makes a single weigh-in
// hard to read. The weeks start on the profile's first day of the week.
function WeighIns() {
  const st = useStore(s => s.S)
  const ws = weekStartOf(st)
  const weeks = useMemo(() => weeklyWeights(st.bodyweight, ws), [st.bodyweight, ws])
  const points = useMemo(() => [...weeks].reverse()
    .map(w => ({ t: new Date(w.key + 'T12:00:00').getTime(), y: Math.round(w.avg * 100) / 100, d: w.key })), [weeks])
  const n = weeks.reduce((sum, w) => sum + w.n, 0)
  if (!n) return <>
    <h3>{t("WEIGH_INS" /* 称重记录 */)}</h3>
    <div className="empty"><div className="ico"><Icon name="scale" /></div>{t("NO_WEIGH_INS_YET_LOG_YOUR_WEIGHT_TO_START_THE_CURVE" /* 还没有称重记录。记一下体重，曲线就开始了。 */)}</div>
  </>
  return <>
    <h3 style={{ marginBottom: 2 }}>{t("WEIGH_INS" /* 称重记录 */)}</h3>
    <div className="muted small" style={{ marginBottom: 10 }}>{tn("COUNT_WEIGH_IN" /* {0} 次称重 */, "COUNT_WEIGH_INS" /* {0} 次称重 */, n)}</div>
    <div className="chart"><LineChart points={points} h={140} unit={st.unit} goal={st.targetW} /></div>
    <div className="small dim" style={{ marginTop: 6 }}>{t("WEEKLY_AVERAGE" /* 每周平均 */)}</div>
    {weeks.map(w => {
      // Only a change the display can show: at one decimal, 0.02 kg is "0", and an arrow over a
      // zero says something moved when, as far as the screen goes, nothing did.
      const moved = w.delta != null && fmtNum(Math.abs(w.delta)) !== fmtNum(0)
      return <div key={w.key} data-week={w.key}>
        <div className="row between" style={{ margin: '16px 2px 4px', gap: 8 }}>
          <span className="small" style={{ fontWeight: 600 }}>{t("WEEK_OF_COUNT" /* {0} 起的一周 */, fmtDate(w.key))}</span>
          <span className="small row" style={{ gap: 8 }}>
            {moved && <span className="row" style={{ gap: 2, fontWeight: 500, color: bwDeltaColor(w.delta, w.avg) }}>
              <Icon name={w.delta > 0 ? 'arrowUp' : 'arrowDown'} style={{ fontSize: 12 }} />{fmtNum(Math.abs(w.delta))}
            </span>}
            <span className="muted" style={{ whiteSpace: 'nowrap' }}>{t("AVERAGE_COUNT" /* 平均 {0} */, fmtNum(w.avg) + ' ' + st.unit)}</span>
          </span>
        </div>
        <div className="list" style={{ gap: 0 }}>{w.entries.map(b => <WeighInRow key={b.d} b={b} unit={st.unit} confirm />)}</div>
      </div>
    })}
  </>
}
export const weighInsSheet = () => ui().openSheet(close => <WeighIns close={close} />)

/* ============================ import from another app ============================ */
// "12 sets bring an RPE with them": the file rated its sets. The column is off by default, so
// with it off the line says where to switch it on.
const effortLine = (effort, n, scale) => effort === 'none'
  ? tn("COUNT_SET_BRINGS_AN_COUNT_WITH_IT_SWITCH_ON_EFFORT_PER_SET" /* {0} 组自带 {1}。在设置中打开“每组强度”就能看到。 */, "COUNT_SETS_BRING_AN_COUNT_WITH_THEM_SWITCH_ON_EFFORT_PER_SET" /* {0} 组自带 {1}。在设置中打开“每组强度”就能看到。 */, n, scale)
  : tn("COUNT_SET_BRINGS_AN_COUNT_WITH_IT" /* {0} 组自带 {1}。 */, "COUNT_SETS_BRING_AN_COUNT_WITH_THEM" /* {0} 组自带 {1}。 */, n, scale)
// Shows what a parsed export would actually do before anything is written. An import is
// the one action where "just try it" is expensive — it's someone's entire training
// history — so the numbers, the unit conversion and the exercises we couldn't recognise
// are all on screen before the confirm button.
function ImportSummary({ parsed, close }) {
  const st = useStore(s => s.S)
  const isBW = parsed.kind === 'bodyweight'
  const have = isBW
    ? parsed.bodyweight.filter(b => st.bodyweight.some(x => x.d === b.d)).length
    : parsed.workouts.filter(w => st.workouts.some(x => x.d === w.d)).length
  const fresh = (isBW ? parsed.bodyweight.length : parsed.workouts.length) - have

  const doImport = () => {
    let res
    update(s => { res = mergeImport(s, parsed) })
    close()
    toast(isBW
      ? tn("COUNT_WEIGH_IN_IMPORTED" /* 已导入 {0} 条称重记录 */, "COUNT_WEIGH_INS_IMPORTED" /* 已导入 {0} 条称重记录 */, res.added)
      : tn("COUNT_WORKOUT_IMPORTED" /* 已导入 {0} 次训练 */, "COUNT_WORKOUTS_IMPORTED" /* 已导入 {0} 次训练 */, res.added))
  }

  return <>
    <h3>{parsed.source ? t("IMPORT_FROM_COUNT" /* 从 {0} 导入 */, parsed.source) : t("IMPORT_HISTORY" /* 导入历史记录 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>
      {fmtDateRange(parsed.from, parsed.to, true)}
    </div>

    <div className="tiles" style={{ textAlign: 'start' }}>
      {isBW ? <>
        <div className="tile"><div className="l">{t("WEIGH_INS" /* 称重记录 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{parsed.bodyweight.length}</div></div>
        <div className="tile"><div className="l">{t("NEW" /* 新建 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{fresh}</div></div>
      </> : <>
        <div className="tile"><div className="l">{t("WORKOUTS" /* 训练次数 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{parsed.workouts.length}</div></div>
        <div className="tile"><div className="l">{t("SETS" /* 组数 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{parsed.sets}</div></div>
        <div className="tile"><div className="l">{t("EXERCISES_MATCHED" /* 已匹配动作 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{parsed.matched}</div></div>
        <div className="tile"><div className="l">{t("ADDED_AS_YOUR_OWN" /* 添加为自定义 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{parsed.created}</div></div>
      </>}
    </div>

    {parsed.mixedUnits ? <div className="small" style={{ color: 'var(--yellow)', marginBottom: 10 }}>
      {t("THE_FILE_MIXES_KG_AND_LB_SO_EACH_SET_IS_CONVERTED_TO" /* 文件中混用了 kg 和 lb，所以每组都会换算成 {0}。 */, st.unit)}
    </div> : parsed.converted ? <div className="small" style={{ color: 'var(--yellow)', marginBottom: 10 }}>
      {t("THE_FILE_IS_IN_COUNT_AND_YOUR_PROFILE_IS_IN_COUNT_SO" /* 文件使用 {0}，你的档案使用 {1}，所以重量会被换算。 */, parsed.fileUnit, st.unit)}
    </div> : null}
    {!isBW && !parsed.fileUnit && !parsed.mixedUnits && <div className="small dim" style={{ marginBottom: 10 }}>
      {t("THE_FILE_DOESN_T_SAY_WHICH_UNIT_IT_USES_SO_NUMBERS_ARE" /* 文件没有标明单位，所以数字按原样导入。 */)}
    </div>}
    {have > 0 && <div className="small dim" style={{ marginBottom: 10 }}>
      {t("COUNT_DAYS_ALREADY_HAVE_DATA_HERE_AND_WILL_BE_LEFT_ALONE" /* 有 {0} 天已存在数据，将保持不变。 */, have)}
    </div>}
    {/* The file rated its sets. Say so: the column is off by default, so the ratings would
        otherwise arrive invisibly and look like they had been dropped. */}
    {!isBW && (parsed.rirSets + parsed.rpeSets) > 0 && <div className="small dim" style={{ marginBottom: 10 }}>
      {effortLine(effortOf(st), parsed.rirSets || parsed.rpeSets, parsed.rirSets ? 'RIR' : 'RPE')}
    </div>}
    {/* Rows the parser could not use (no date or name, nothing measured, impossible numbers)
        are left out; say how many, so a short history does not look like a lost one. */}
    {!isBW && parsed.skipped > 0 && <div className="small dim" style={{ marginBottom: 10 }}>
      {tn("COUNT_ROW_SKIPPED_COULDN_T_READ_IT" /* 已跳过 {0} 行（无法读取） */, "COUNT_ROWS_SKIPPED_COULDN_T_READ_THEM" /* 已跳过 {0} 行（无法读取） */, parsed.skipped)}
    </div>}
    {!isBW && parsed.unmatchedNames.length > 0 && <>
      <h4 className="sec">{t("NOT_IN_THE_LIBRARY_SO_THEY_RE_ADDED_AS_YOUR_OWN_EXERCISES" /* 不在动作库中，所以已添加为你的自定义动作 */)}</h4>
      <div className="mchips" style={{ marginBottom: 12 }}>
        {parsed.unmatchedNames.slice(0, 12).map(n => <span key={n} className="mchip capitalize">{n}</span>)}
        {parsed.unmatchedNames.length > 12 && <span className="mchip">+{parsed.unmatchedNames.length - 12}</span>}
      </div>
    </>}

    <Button variant="primary" onClick={doImport} disabled={!fresh}>
      {fresh ? t("IMPORT" /* 导入 */) : t("NOTHING_NEW_TO_IMPORT" /* 没有新内容可导入 */)}
    </Button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </>
}

/** Read a CSV/XML export, then show what it would do. */
export function importFromApp(file, onDone) {
  const rd = new FileReader()
  rd.onload = () => {
    let parsed
    try { parsed = parseImport(String(rd.result), { unit: S().unit, customEx: S().customEx }) }
    catch (e) { toast(t("COULD_NOT_READ_THAT_FILE" /* 无法读取该文件 */)); return }
    if (parsed.error === 'empty') { toast(t("THAT_FILE_IS_EMPTY" /* 该文件是空的 */)); return }
    if (parsed.error) { toast(t("WE_DON_T_RECOGNISE_THAT_FILE_S_COLUMNS_CHECK_THE_DOCS_FOR" /* 我们认不出这个文件的列。支持的应用请查看文档。 */)); return }
    if (parsed.kind === 'bodyweight' ? !parsed.bodyweight.length : !parsed.workouts.length) {
      toast(t("NOTHING_TO_IMPORT_FROM_THAT_FILE" /* 该文件中没有可导入的内容 */)); return
    }
    ui().openSheet(close => <ImportSummary parsed={parsed} close={close} />)
    onDone && onDone()
  }
  rd.onerror = () => toast(t("COULD_NOT_READ_THAT_FILE" /* 无法读取该文件 */))
  rd.readAsText(file)
}

/* ============================ import from Hevy API ============================ */
// The key lives in React state for this sheet only — dismissed with the sheet, never
// written to the store / localStorage / the server. After a successful fetch the user
// picks workouts and/or weigh-ins before anything is merged.

export function importFromHevy() {
  ui().openSheet(close => <HevyImportSheet close={close} />)
}

function hevyProgressLabel(p) {
  if (!p) return t("FETCHING_FROM_HEVY" /* 正在从 Hevy 获取… */)
  if (p.stage === 'templates') return t("FETCHING_EXERCISES_COUNT_COUNT" /* 正在获取动作… ({0}/{1}) */, p.page, p.pageCount)
  if (p.stage === 'workouts') return t("FETCHING_WORKOUTS_COUNT_COUNT" /* 正在获取训练… ({0}/{1}) */, p.page, p.pageCount)
  if (p.stage === 'routines') return t("FETCHING_ROUTINES_COUNT_COUNT" /* 正在获取计划… ({0}/{1}) */, p.page, p.pageCount)
  if (p.stage === 'body') return t("FETCHING_WEIGH_INS_COUNT_COUNT" /* 正在获取体重… ({0}/{1}) */, p.page, p.pageCount)
  if (p.stage === 'parse') return t("MATCHING_EXERCISES" /* 正在匹配动作… */)
  return t("FETCHING_FROM_HEVY" /* 正在从 Hevy 获取… */)
}

function HevyImportSheet({ close }) {
  const st = useStore(s => s.S)
  const [apiKey, setApiKey] = useState('')
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState(null)
  const [payload, setPayload] = useState(null) // { workouts, routines, bodyweight }
  const [wantWorkouts, setWantWorkouts] = useState(true)
  const [wantRoutines, setWantRoutines] = useState(true)
  const [wantBody, setWantBody] = useState(true)
  const keyRef = useRef(null)

  // Drop the key from memory when the sheet goes away (unmount or successful import).
  useEffect(() => () => { setApiKey('') }, [])

  const wipeKey = () => { setApiKey(''); if (keyRef.current) keyRef.current.value = '' }

  const fetchAccount = async () => {
    const key = apiKey.trim()
    if (!key) { toast(t("PASTE_YOUR_HEVY_API_KEY_FIRST" /* 请先粘贴 Hevy API 密钥 */)); return }
    setBusy(true)
    setProgress({ stage: 'templates', page: 1, pageCount: 1 })
    setPayload(null)
    try {
      const data = await importHevyData(key, { unit: st.unit, customEx: st.customEx, onProgress: setProgress })
      wipeKey()
      const empty = !data.workouts.workouts.length && !data.routines.routines.length && !data.bodyweight.bodyweight.length
      if (empty) {
        toast(t("NOTHING_TO_IMPORT_FROM_HEVY" /* Hevy 没有可导入的内容 */))
        return
      }
      setWantWorkouts(!!data.workouts.workouts.length)
      setWantRoutines(!!data.routines.routines.length)
      setWantBody(!!data.bodyweight.bodyweight.length)
      setPayload(data)
    } catch (e) {
      if (e instanceof HevyApiError && e.message === 'auth') toast(t("THAT_HEVY_API_KEY_WAS_REFUSED" /* 该 Hevy API 密钥被拒绝 */))
      else if (e instanceof HevyApiError && e.message === 'rate-limit') toast(t("HEVY_IS_RATE_LIMITING_REQUESTS_WAIT_A_MINUTE_AND_TRY_AGAIN" /* Hevy 正在限制请求频率。请等一分钟后重试 */))
      else if (e instanceof HevyApiError && e.message === 'empty') toast(t("PASTE_YOUR_HEVY_API_KEY_FIRST" /* 请先粘贴 Hevy API 密钥 */))
      else toast(t("COULDN_T_REACH_HEVY_CHECK_THE_KEY_AND_TRY_AGAIN" /* 无法连接 Hevy。请检查密钥后重试 */))
    } finally {
      setBusy(false)
      setProgress(null)
    }
  }

  const doImport = () => {
    if (!payload) return
    const parts = []
    let addedW = 0, addedR = 0, addedB = 0
    update(s => {
      if (wantWorkouts && payload.workouts.workouts.length) {
        const res = mergeImport(s, payload.workouts)
        addedW = res.added
        parts.push(tn("COUNT_WORKOUT_IMPORTED" /* 已导入 {0} 次训练 */, "COUNT_WORKOUTS_IMPORTED" /* 已导入 {0} 次训练 */, res.added))
      }
      if (wantRoutines && payload.routines.routines.length) {
        const res = mergeHevyRoutines(s, payload.routines)
        addedR = res.added
        parts.push(tn("COUNT_ROUTINE_IMPORTED" /* 已导入 {0} 个训练计划 */, "COUNT_ROUTINES_IMPORTED" /* 已导入 {0} 个训练计划 */, res.added))
      }
      if (wantBody && payload.bodyweight.bodyweight.length) {
        const res = mergeImport(s, payload.bodyweight)
        addedB = res.added
        parts.push(tn("COUNT_WEIGH_IN_IMPORTED" /* 已导入 {0} 条称重记录 */, "COUNT_WEIGH_INS_IMPORTED" /* 已导入 {0} 条称重记录 */, res.added))
      }
    })
    close()
    if (!addedW && !addedR && !addedB) toast(t("NOTHING_NEW_TO_IMPORT" /* 没有新内容可导入 */))
    else toast(parts.join(' · '))
  }

  if (!payload) {
    return <>
      <h3>{t("IMPORT_FROM_HEVY" /* 从 Hevy 导入 */)}</h3>
      <div className="muted small" style={{ marginBottom: 14, lineHeight: 1.5 }}>
        {t("PULL_YOUR_HISTORY_WITH_A_HEVY_PRO_API_KEY_THE_KEY_IS" /* 使用 Hevy Pro API 密钥拉取训练记录。密钥仅用于本次导入，不会保存。 */)}
      </div>
      <label className="small dim" style={{ display: 'block', marginBottom: 6 }}>{t("HEVY_API_KEY" /* Hevy API 密钥 */)}</label>
      <TextField
        ref={keyRef}
        type="password"
        autoComplete="off"
        spellCheck={false}
        placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        value={apiKey}
        disabled={busy}
        onChange={e => setApiKey(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter' && !busy) fetchAccount() }}
      />
      <div className="small" style={{ margin: '10px 0 16px', lineHeight: 1.45 }}>
        <a href={HEVY_DEV_SETTINGS} target="_blank" rel="noopener noreferrer">{t("GET_YOUR_API_KEY" /* 获取 API 密钥 */)}</a>
        <span className="dim"> · {t("HEVY_SETTINGS_DEVELOPER" /* Hevy → 设置 → Developer */)}</span>
      </div>
      {busy && <div className="small dim" style={{ marginBottom: 12 }}>{hevyProgressLabel(progress)}</div>}
      <Button variant="primary" onClick={fetchAccount} disabled={busy || !apiKey.trim()}>
        {busy ? t("FETCHING_FROM_HEVY" /* 正在从 Hevy 获取… */) : t("FETCH_FROM_HEVY" /* 从 Hevy 获取 */)}
      </Button>
      <div style={{ height: 8 }} />
      <Button variant="ghost" className="dim" onClick={close} disabled={busy}>{t("CANCEL" /* 取消 */)}</Button>
    </>
  }

  const w = payload.workouts
  const r = payload.routines
  const b = payload.bodyweight
  const haveW = w.workouts.filter(x => st.workouts.some(y => y.d === x.d)).length
  const freshW = w.workouts.length - haveW
  const haveB = b.bodyweight.filter(x => st.bodyweight.some(y => y.d === x.d)).length
  const freshB = b.bodyweight.length - haveB
  // Routines are always added as new copies (same as plan import).
  const freshR = r.routines.length
  const canImport = (wantWorkouts && freshW > 0) || (wantRoutines && freshR > 0) || (wantBody && freshB > 0)
  const unmatched = [...new Set([
    ...(wantWorkouts ? w.unmatchedNames : []),
    ...(wantRoutines ? r.unmatchedNames : []),
  ])].sort()

  return <>
    <h3>{t("IMPORT_FROM_HEVY" /* 从 Hevy 导入 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>
      {w.from && (w.from === w.to ? fmtDate(w.from, true) : fmtDate(w.from, true) + ' – ' + fmtDate(w.to, true))}
      {!w.from && b.from && (b.from === b.to ? fmtDate(b.from, true) : fmtDate(b.from, true) + ' – ' + fmtDate(b.to, true))}
    </div>

    <div className="tiles" style={{ textAlign: 'start' }}>
      <div className="tile"><div className="l">{t("WORKOUTS" /* 训练次数 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{w.workouts.length}</div></div>
      <div className="tile"><div className="l">{t("ROUTINES" /* 训练计划 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{r.routines.length}</div></div>
      <div className="tile"><div className="l">{t("EXERCISES_MATCHED" /* 已匹配动作 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{w.matched + r.matched}</div></div>
      <div className="tile"><div className="l">{t("ADDED_AS_YOUR_OWN" /* 添加为自定义 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{w.created + r.created}</div></div>
    </div>

    {w.workouts.length > 0 && <div className="row between" style={{ padding: '10px 2px', borderTop: '1px solid var(--sep)', gap: 12 }}>
      <div>
        <div className="tt" style={{ fontSize: 15 }}>{t("IMPORT_WORKOUTS" /* 导入训练 */)}</div>
        <div className="small dim">{t("COUNT_NEW_COUNT_DAYS_ALREADY_HERE" /* {0} 条新记录 · {1} 天已有数据 */, freshW, haveW)}</div>
      </div>
      <Switch checked={wantWorkouts} onChange={setWantWorkouts} />
    </div>}
    {r.routines.length > 0 && <div className="row between" style={{ padding: '10px 2px', borderTop: '1px solid var(--sep)', gap: 12 }}>
      <div>
        <div className="tt" style={{ fontSize: 15 }}>{t("IMPORT_ROUTINES" /* 导入训练计划 */)}</div>
        <div className="small dim">{t("COUNT_ROUTINES_COUNT_EXERCISES_ADDED_AS_NEW_PLANS" /* {0} 个计划 · {1} 个动作，作为新计划添加 */, freshR, r.exerciseCount)}</div>
      </div>
      <Switch checked={wantRoutines} onChange={setWantRoutines} />
    </div>}
    {b.bodyweight.length > 0 && <div className="row between" style={{ padding: '10px 2px', borderTop: '1px solid var(--sep)', borderBottom: '1px solid var(--sep)', gap: 12, marginBottom: 8 }}>
      <div>
        <div className="tt" style={{ fontSize: 15 }}>{t("IMPORT_WEIGH_INS" /* 导入体重 */)}</div>
        <div className="small dim">{t("COUNT_NEW_COUNT_DAYS_ALREADY_HERE" /* {0} 条新记录 · {1} 天已有数据 */, freshB, haveB)}</div>
      </div>
      <Switch checked={wantBody} onChange={setWantBody} />
    </div>}
    {!b.bodyweight.length && <div style={{ borderBottom: '1px solid var(--sep)', marginBottom: 8 }} />}

    {(w.converted || r.converted) && <div className="small" style={{ color: 'var(--yellow)', marginBottom: 10 }}>
      {t("HEVY_STORES_WEIGHTS_IN_KG_SO_THEY_LL_BE_CONVERTED_TO_COUNT" /* Hevy 以公斤存储重量，所以会换算为 {0}。 */, st.unit)}
    </div>}
    {wantWorkouts && (w.rirSets + w.rpeSets) > 0 && <div className="small dim" style={{ marginBottom: 10 }}>
      {effortLine(effortOf(st), w.rirSets || w.rpeSets, w.rirSets ? 'RIR' : 'RPE')}
    </div>}
    {unmatched.length > 0 && <>
      <h4 className="sec">{t("NOT_IN_THE_LIBRARY_SO_THEY_RE_ADDED_AS_YOUR_OWN_EXERCISES" /* 不在动作库中，所以已添加为你的自定义动作 */)}</h4>
      <div className="mchips" style={{ marginBottom: 12 }}>
        {unmatched.slice(0, 12).map(n => <span key={n} className="mchip capitalize">{n}</span>)}
        {unmatched.length > 12 && <span className="mchip">+{unmatched.length - 12}</span>}
      </div>
    </>}

    <Button variant="primary" onClick={doImport} disabled={!canImport}>
      {canImport ? t("IMPORT" /* 导入 */) : t("NOTHING_NEW_TO_IMPORT" /* 没有新内容可导入 */)}
    </Button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={() => { setPayload(null); wipeKey() }}>{t("BACK_A" /* 返回 */)}</Button>
  </>
}

/* ============================ target weight ============================ */
export function bwDeltaColor(delta, currentW) {
  if (!delta) return 'var(--label-2)'
  if (!S().targetW) return 'var(--label)'
  const up = S().targetW > currentW
  return (delta > 0) === up ? 'var(--acc)' : 'var(--red)'
}
function GoalSheet({ close }) {
  const st = S()
  const bw = lastBW(st)
  const [v, setV] = useState(st.targetW || (bw ? bw.w : 70))
  return <>
    <h3>{t("TARGET_WEIGHT" /* 目标体重 */)}</h3>
    <div className="muted small">{t("YOUR_GOAL_IS_DRAWN_AS_A_LINE_THROUGH_THE_WEIGHT_CHARTS_AND" /* 目标会以一条线显示在体重图表中，增减会根据是否朝目标靠近来着色。 */)}</div>
    <WeightInput value={v} setValue={setV} unit={st.unit} />
    <div style={{ height: 14 }} />
    <Button variant="primary" onClick={() => {
      const n = Math.round((v || 0) * 10) / 10
      if (!n || n <= 0) { toast(t("ENTER_A_VALID_WEIGHT" /* 请输入有效的重量 */)); return }
      if (bwTooHeavy(n, st.unit)) return
      update(s => { s.targetW = n }); close()
      const b = lastBW(S()); toast(t("GOAL_SET_COUNT" /* 目标已设置：{0} */, fmtNum(n) + ' ' + st.unit) + (b ? ' (' + t("COUNT_TO_GO" /* 还差 {0} */, fmtNum(Math.abs(n - b.w))) + ')' : ''))
    }}>{t("SAVE_GOAL" /* 保存目标 */)}</Button>
    {st.targetW && <><div style={{ height: 8 }} /><Button variant="danger" onClick={() => { update(s => { s.targetW = null }); close(); toast(t("GOAL_REMOVED" /* 目标已移除 */)) }}>{t("REMOVE_GOAL" /* 移除目标 */)}</Button></>}
  </>
}
export const goalSheet = () => ui().openSheet(close => <GoalSheet close={close} />)

/* ============================ plate loading ============================ */
// One editor for every place an exercise's loading shows up (exercise detail, exercise config,
// mid-workout sheet). Three things, all per exercise and display-only (lib/plates.js):
//   • how the weight is loaded — per side of a bar, one stack, or not plate-loaded at all
//     (S.loadKind; absent = derived from the equipment, so most exercises never store it);
//   • the base weight before any plate goes on — the bar (S.barWeights, profile unit, lib/bar.js;
//     stepping down to 0 clears the override and falls back to the bar type's default), or a
//     sled's / machine's own weight for anything else;
//   • "No bar" for a bar exercise: an explicit 0 (issue #138 — a counterbalanced Smith machine),
//     so the whole total is plates. Distinct from the stepper's 0, which means "default".
// `cfg` is the routine/session config the caller has (its `bodyweight` flag turns a dumbbell
// exercise into "added weight", i.e. a single stack) — the default kind is derived from the
// same thing the workout screen derives it from, so what the editor shows as chosen is what
// the rows do. Without one, the equipment alone decides.
function BarWeightEditor({ ex, cfg, extra }) {
  const st = useStore(s => s.S)
  const bar = usesBar(ex)
  const ctx = { ...(cfg || {}), id: ex.id }
  const kind = loadKindFor(st, ctx)
  const explicit = hasBarOverride(st, ex.id)
  const noBar = bar && isNoBar(st, ex.id)
  const def = defaultBarWeight(ex.eq, st.unit)
  const base = baseWeightFor(st, ex)
  // The kinds a pick would only be restating. With a `cfg` there is one: the same default the
  // rows derive. Without one the equipment decides — and for body-weight equipment that answer
  // ('single', the load being whatever you hang on) is not the one a routine logging the total
  // derives ('none', bodyweight: false), so the segment sits lit on a kind the rows do not use
  // and the pick that would fix it is the only way to say so: both readings are consulted, and
  // it is stored unless it is the default under either. Everything else keeps the plain rule —
  // a dumbbell's cfg-less 'none' is what a dumbbell row derives, and storing it would freeze
  // 'none' onto the exercise everywhere, override the 'single' an added-weight entry derives,
  // and leave no pick that takes the key off again.
  const defaults = cfg ? [loadKindFor(null, ctx)]
    : isBodyweightEq(ex.id) ? [true, false].map(b => loadKindFor(null, { id: ex.id, bodyweight: b }))
    : [loadKindFor(null, ctx)]
  // Picking what the equipment already implies puts the exercise back on it (a stamped null,
  // lib/plates.js), so a later change of the equipment's own default still reaches it.
  const setKind = k => update(s => {
    s.loadKind = withLoadKind(s.loadKind, ex.id, defaults.every(d => d === k) ? null : k)
  })
  const setBar = v => update(s => {
    s.barWeights = s.barWeights || {}
    const n = Math.max(0, Math.round((v || 0) * 100) / 100)
    if (n > 0) s.barWeights[ex.id] = n; else delete s.barWeights[ex.id]
  })
  // "No bar" is a stored 0, which is a different thing from no entry at all: a counterbalanced
  // Smith carriage weighs nothing in your hands, so the plate math and the drop-set steps must
  // start from what you logged (issue #138). Clearing it goes back to the bar type's default.
  const setNoBar = on => update(s => {
    s.barWeights = s.barWeights || {}
    if (on) s.barWeights[ex.id] = 0; else delete s.barWeights[ex.id]
  })
  return <>
    <Segmented className="seg-inline" value={kind} onChange={setKind}
      options={[{ value: 'pairs', label: t("PER_SIDE" /* 每侧 */) }, { value: 'single', label: t("SINGLE_STACK" /* 单堆 */) }, { value: 'none', label: t("OFF" /* 关 */) }]} />
    <div className="small dim" style={{ margin: '8px 0 12px' }}>
      {kind === 'pairs' ? t("PLATES_SPLIT_OVER_BOTH_SIDES_OF_A_BAR" /* 杠铃片分装在杆的两侧。 */)
        : kind === 'single' ? t("ONE_STACK_A_BELT_A_LANDMINE_A_PLATE_LOADED_MACHINE_A_SLED" /* 单堆：腰带、地雷杆、挂片式器械、雪橇。 */)
          : t("NO_PLATE_LINE_UNDER_THE_SETS" /* 组数下方不显示杠铃片提示行。 */)}
    </div>
    {kind !== 'none' && <>
      {bar && <div className="list menu-list" style={{ marginBottom: 6 }}>
        <Row icon="barbell" title={t("NO_BAR" /* 无杠铃杆 */)} subtitle={t("THE_WEIGHT_YOU_LOG_IS_ALL_PLATES" /* 你记录的重量全部是杠铃片。 */)}>
          <Switch checked={noBar} onChange={setNoBar} />
        </Row>
      </div>}
      {!noBar && <div className="row cfgrow" style={{ marginBottom: 6 }}>
        <Stepper label={bar ? t("BAR_COUNT" /* 杆 ({0}) */, st.unit) : t("BASE_WEIGHT_COUNT" /* 基础重量 ({0}) */, st.unit)} value={base} step={2.5} onChange={setBar} />
      </div>}
      <div className="small dim" style={{ marginBottom: 18 }}>
        {noBar ? t("PLATES_ARE_COUNTED_FROM_ZERO_TURN_THIS_OFF_FOR_THE_DEFAULT_COUNT" /* 杠铃片从 0 开始计算。关闭则使用默认值（{0}）。 */, fmtNum(def) + ' ' + st.unit)
          : bar ? (explicit ? t("SET_TO_ZERO_TO_GO_BACK_TO_THE_DEFAULT_COUNT" /* 设为 0 即恢复默认值（{0}）。 */, fmtNum(def) + ' ' + st.unit) : t("DEFAULT_FOR_THIS_BAR_TYPE" /* 此类杠铃杆的默认值。 */))
            : t("THE_MACHINE_OR_SLED_ITSELF_BEFORE_ANY_PLATE_GOES_ON_ZERO_IF" /* 机器或雪橇本身的重量，装上任何杠铃片之前。如果全是杠铃片，就填 0。 */)}
        {extra ? ' ' + extra : ''}
      </div>
    </>}
  </>
}

// What a dumbbell or kettlebell weight means (issue #474, lib/dumbbells.js): as entered (the
// default, how every set before this was counted), one bell, or both together. `value` is the
// meaning in force and `onChange` stores a pick; the caller decides where (the routine's slot or
// the exercise's own default). The line under it says what the pick does to the numbers.
function DbLoadPicker({ ex, cfg, value, onChange }) {
  const one = isOneArm({ ...(cfg || {}), id: ex.id })
  return <>
    <Segmented className="seg-inline" value={value} onChange={onChange}
      options={[{ value: 'as', label: t("AS_ENTERED" /* 按输入 */) }, { value: 'each', label: t("EACH" /* 每只 */) }, { value: 'total', label: t("BOTH" /* 合计 */) }]} />
    <div className="small dim" style={{ margin: '8px 0 18px' }}>
      {value === 'each' ? (one ? t("THE_WEIGHT_OF_THE_ONE_YOU_HOLD_ONE_ARM_SO_IT_COUNTS" /* 你手里那一只的重量。单臂，所以只算一次。 */) : t("THE_WEIGHT_OF_ONE_SO_TWOZERO_MEANS_TWOZERO_IN_EACH_HAND_VOLUME" /* 一只的重量，20 就是每只手 20。容量会算两只。 */))
        : value === 'total' ? t("BOTH_TOGETHER_SO_FOURZERO_MEANS_TWO_TWOZEROS" /* 两只加起来，40 就是两只 20。 */)
          : t("COUNTED_AS_YOU_TYPE_IT_THE_WAY_IT_ALWAYS_WAS" /* 按你输入的算，一直都是这样。 */)}
    </div>
  </>
}

// Mid-workout sheet behind the ⋯ menu's "Plate loading" — same values, same editor.
function BarWeightSheet({ exId, cfg, close }) {
  const ex = exOr(exId)
  return <>
    <h3>{t("PLATE_LOADING" /* 配重 */)}</h3>
    <div className={`muted small ${exerciseNameClass(ex)}`} style={{ marginBottom: 12 }}>{exerciseNameFor(ex)}</div>
    <BarWeightEditor ex={ex} cfg={cfg} extra={t("APPLIES_TO_THIS_EXERCISE_EVERYWHERE_NOT_JUST_THIS_PLAN" /* 对这个动作处处生效，不只在此计划中。 */)} />
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}
export const barWeightSheet = (exId, cfg) => ui().openSheet(close => <BarWeightSheet exId={exId} cfg={cfg} close={close} />)

// The plates you own, as pairs per size, for the profile's unit (Settings → Equipment → Plates).
// The first edit copies the standard set into S.plates[unit] and changes one count in it, so the
// list you see is always the list the set rows load from. "Back to the standard set" empties the
// unit's list again. Both are stamped (lib/plates.js), so the last change wins a sync.
function PlateInventorySheet({ close }) {
  const st = useStore(s => s.S)
  const unit = st.unit === 'lb' ? 'lb' : 'kg'
  const own = ownsPlates(st)
  const setPairs = (w, n) => update(s => { s.plates = withPlatePairs(s, w, n) })
  const reset = () => update(s => { s.plates = withStandardPlates(s) })
  return <>
    <h3>{t("PLATES" /* 杠铃片 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("PAIRS_OF_EACH_SIZE_YOU_OWN_EVERY_SET_ROW_LOADS_FROM_THIS" /* 你拥有的每种重量的对数。每一行组数都从这份清单里取用，所以只有一对 45 的家庭健身房永远不会被要求用两片。 */)}
    </div>
    {PLATE_SIZES[unit].map(w => (
      <div className="row cfgrow" key={w} style={{ marginBottom: 6 }}>
        <Stepper label={fmtPlate(w) + ' ' + unit} value={pairsOf(st, w)} step={1} decimal={false} unit={t("PAIRS" /* 对 */)} onChange={n => setPairs(w, n)} />
      </div>
    ))}
    <div className="small dim" style={{ margin: '4px 0 14px' }}>
      {own ? t("YOUR_OWN_LIST_FOR_COUNT" /* 你自己的 {0} 清单。 */, unit) : t("THE_STANDARD_SET_PLENTY_OF_EACH_CHANGE_ANY_COUNT_TO_MAKE_IT" /* 标准配置，每种都很充足。改改数量，让它变成你自己的。 */)}
    </div>
    {own && <Button onClick={reset} style={{ marginBottom: 8 }}>{t("BACK_TO_THE_STANDARD_SET" /* 恢复为标准配置 */)}</Button>}
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}
export const plateInventorySheet = () => ui().openSheet(close => <PlateInventorySheet close={close} />)

// The dumbbells you own, for the profile's unit (Settings → Equipment → Dumbbells, issue #376):
// a list of single bells, kept per unit like the plates (lib/dumbbells.js). With one, progression,
// deloads, warm-ups, drops and the stepper of every dumbbell lift land on these; an empty list
// puts them back on the increment. Tapping a weight takes it off, the field adds one, and the
// quick fill writes the usual rack for the unit to edit from. Every change is stamped.
function DumbbellInventorySheet({ close }) {
  const st = useStore(s => s.S)
  const unit = st.unit === 'lb' ? 'lb' : 'kg'
  const list = dumbbellsOf(st)
  const [draft, setDraft] = useState(null)
  const save = ws => update(s => { s.dumbbells = withDumbbells(s, ws) })
  const preset = presetWeights(unit)
  const add = () => {
    const w = cleanWeights([draft])[0]
    if (!w) { toast(t("ENTER_A_VALID_WEIGHT" /* 请输入有效的重量 */)); return }
    save([...list, w])
    setDraft(null)
  }
  return <>
    <h3>{t("DUMBBELLS" /* 哑铃 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("THE_WEIGHTS_YOU_OWN_ONE_BELL_EACH_PROGRESSION_DELOADS_WARM_UPS_AND" /* 你拥有的重量，每个一只。哑铃动作的加重、减载、热身以及 + 和 − 按钮都只会落在这些重量上。 */)}
    </div>
    {list.length > 0
      ? <div className="chips" style={{ flexWrap: 'wrap', overflow: 'visible', touchAction: 'auto', marginBottom: 12 }}>
        {list.map(w => <button key={w} className="chip on nocap" aria-label={t("REMOVE_COUNT_A" /* 移除 {0} */, fmtPlate(w) + ' ' + unit)}
          onClick={() => save(list.filter(x => x !== w))}>{fmtPlate(w)} <Icon name="xmark" /></button>)}
      </div>
      : <div className="small dim" style={{ marginBottom: 12 }}>{t("NO_LIST_YET_SO_DUMBBELL_LIFTS_STEP_BY_THEIR_INCREMENT_AS_USUAL" /* 还没有列表，所以哑铃动作照常按增量递增。 */)}</div>}
    <div className="row" style={{ gap: 8, marginBottom: 12 }}>
      <NumberField className="input" decimal value={draft ?? ''} onChange={v => setDraft(v)}
        aria-label={t("WEIGHT_COUNT" /* 重量（{0}） */, unit)} placeholder={t("WEIGHT_COUNT" /* 重量（{0}） */, unit)} onKeyDown={e => { if (e.key === 'Enter') add() }} />
      <Button icon="plus" onClick={add} style={{ flex: '0 0 auto', width: 'auto' }}>{t("ADD" /* 添加 */)}</Button>
    </div>
    <Button onClick={() => save(preset)} style={{ marginBottom: 8 }}>
      {t("FILL_IN_COUNT_TO_COUNT_COUNT_EVERY_COUNT" /* 填入 {0} 到 {1} {2}，每隔 {3} */, fmtPlate(preset[0]), fmtPlate(preset.at(-1)), unit, fmtPlate(preset[1] - preset[0]))}
    </Button>
    {list.length > 0 && <Button variant="danger" onClick={() => save([])} style={{ marginBottom: 8 }}>{t("CLEAR_THE_LIST" /* 清空列表 */)}</Button>}
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}
export const dumbbellInventorySheet = () => ui().openSheet(close => <DumbbellInventorySheet close={close} />)

/* ============================ exercise detail ============================ */
// Estimated 1RM for one exercise (issue #18): what the log already implies, plus a calculator
// for a set you have not done — so the number is reachable before there is any history.
function OneRM({ ex }) {
  const st = useStore(s => s.S)
  const best = best1RM(st, ex.id)
  const [w, setW] = useState(best ? best.w : (st.exWeights[ex.id] || {}).w || 20)
  const [r, setR] = useState(best ? best.r : 5)
  const est = estimate1RM(w, r, formulaOf(st))
  return <>
    <h4 className="sec">{t("ESTIMATED_ONE_REP_MAX" /* 估算 1RM */)}</h4>
    {best && <div className="small" style={{ marginBottom: 8 }}>
      {t("FROM_YOUR_LOG" /* 来自你的记录： */)} <b className="accent">{fmtNum(best.est)} {st.unit}</b>
      <span className="dim"> · {t("COUNT_COUNT_ON_COUNT" /* 术语：{2}：{0} × {1} */, fmtNum(best.w) + ' ' + st.unit, best.r, fmtDate(best.d, true))}</span>
    </div>}
    <div className="row cfgrow" style={{ marginBottom: 10 }}>
      <Stepper label={t("WEIGHT_COUNT" /* 重量（{0}） */, st.unit)} value={w} step={2.5} onChange={setW} />
      <Stepper label={t("REPS" /* 次数 */)} value={r} step={1} decimal={false} onChange={setR} />
    </div>
    <div className="row between" style={{ marginBottom: 4 }}>
      <span className="muted small">{t("ESTIMATE" /* 预估 */)}</span>
      <b className="accent" style={{ fontSize: 20 }}>{est === null ? '–' : fmtNum(est) + ' ' + st.unit}</b>
    </div>
    <div className="small dim">{est === null
      ? t("ENTER_A_WEIGHT_AND_ONE_COUNT_REPS_BEYOND_THAT_IT_S_BASICALLY" /* 请输入重量和 1–{0} 次。再多就基本是瞎猜了。 */, REP_CAP)
      : formulaOf(st) === 'weighted'
        ? t("A_BLEND_OF_SEVEN_FORMULAS_CALCULATED_FROM_ONE_SET_NOT_A_TESTED" /* 七种公式的综合：由单组计算得出，并非实测最大值。 */)
        : t("COUNT_FORMULA_CALCULATED_FROM_ONE_SET_NOT_A_TESTED_MAX" /* {0} 公式：由单组计算得出，并非实测最大值。 */, FORMULA_NAMES[formulaOf(st)])}</div>
  </>
}

// A muscle the catalogue credits with nothing (a bench press's biceps, #359) is not one it trains,
// so it is not shown as a tag either; "By muscle" already leaves the exercise out.
const trainedBy = ex => { const weights = muscleWeightsOf(ex); return slug => weights[slug] !== 0 }
// The detail page's tags: body part, main muscles, equipment, then up to three helpers. A word
// says once what it says: the body part "Chest" and the main muscle "Chest" of a bench press
// were two tags (QA 10-06), and a helper never repeats a main muscle.
export function detailTags(ex) {
  const seen = new Set()
  const out = []
  const add = (label, extra) => {
    const k = String(label || '').trim().toLocaleLowerCase()
    if (!k || seen.has(k)) return false
    seen.add(k)
    out.push({ key: out.length, label, ...extra })
    return true
  }
  add(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ex.bp), { acc: true })
  if (ex.bp === 'cardio') add(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME['cardiovascular system']), { icon: 'figureStrength' })
  else for (const s of (ex.primaries?.length ? ex.primaries : (ex.tg ? [ex.tg] : [])).filter(trainedBy(ex))) add(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[s] || s), { icon: 'figureStrength' })
  add(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ex.eq), { icon: 'kettlebell' })
  let helpers = 0
  for (const s of (ex.secondaries?.length ? ex.secondaries : smOf(ex)).filter(trainedBy(ex))) {
    if (helpers >= 3) break
    if (add(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[s] || s))) helpers++
  }
  return out
}

function ExerciseDetail({ ex, close }) {
  useLang() // the description and steps arrive in their own chunk the first time a sheet asks
  const st = useStore(s => s.S)
  const last = lastEntryFor(st, ex.id)
  const best = bestWeightFor(st, ex.id, currentDbLoad(st, ex.id))
  const fav = isFav(st, ex.id)
  const flipFav = () => {
    let on = false
    update(s => { on = toggleFav(s, ex.id) })
    toast(on ? t("ADDED_TO_FAVOURITES" /* 已加入收藏 */) : t("REMOVED_FROM_FAVOURITES" /* 已取消收藏 */))
  }
  return <>
    <div className="row between" style={{ gap: 8, alignItems: 'flex-start' }}>
      <h3 className={'exdetail-name ' + exerciseNameClass(ex)}>{exerciseNameFor(ex)}</h3>
      <button className={'iconbtn fav-btn' + (fav ? ' on' : '')} aria-pressed={fav}
        aria-label={fav ? t("REMOVE_FROM_FAVOURITES" /* 取消收藏 */) : t("ADD_TO_FAVOURITES" /* 加入收藏 */)} onClick={flipFav}>
        <Icon name={fav ? 'starFill' : 'star'} />
      </button>
    </div>
    <Media ex={ex} />
    <div className="row" style={{ gap: 6, flexWrap: 'wrap', margin: '10px 0' }}>
      {detailTags(ex).map(tg => <span key={tg.key} className={'tag' + (tg.acc ? ' acc' : '')}>{tg.icon && <Icon name={tg.icon} />}{tg.label}</span>)}
    </div>
    {descFor(ex) && <div className="exnote">{descFor(ex)}</div>}
    {best > 0 && <div className="small row" style={{ marginBottom: 6, gap: 5 }}><Icon name="trophy" style={{ fontSize: 14, color: 'var(--yellow)' }} />{t("BEST" /* 最佳： */)} <b className="accent" style={{ whiteSpace: 'nowrap' }}>{fmtNum(best)} {st.unit}</b>{last ? ` · ${t("LAST" /* 上次 */)} ${fmtDate(last.d)}: ${last.sets.map(s => setLabel(ex.id, s, last.target, speedUnitOf(st))).join(', ')}` : ''}</div>}
    <Button variant="primary" icon="plus" style={{ margin: '10px 0 4px' }} onClick={() => addToRoutineSheet(ex)}>{t("ADD_TO_MY_PLAN" /* 加入我的计划 */)}</Button>
    {last && <Button icon="history" style={{ marginTop: 4 }} onClick={() => exerciseHistorySheet(ex.id)}>{t("HISTORY" /* 历史 */)}</Button>}
    {isCustomEx(ex) && <div className="row" style={{ gap: 8, marginTop: 8 }}>
      <Button icon="pencil" style={{ flex: 1 }} onClick={() => { close(); customExSheet(ex) }}>{t("EDIT" /* 编辑 */)}</Button>
      <Button variant="danger" icon="trash" style={{ flex: 1 }} onClick={() => deleteCustomEx(ex, close)}>{t("DELETE" /* 删除 */)}</Button>
    </div>}
    {modeOf({ id: ex.id }) === 'reps' && <>
      <h4 className="sec">{t("PLATE_LOADING" /* 配重 */)}</h4>
      <BarWeightEditor ex={ex} extra={t("YOU_STILL_LOG_THE_TOTAL_WEIGHT_THIS_ONLY_FEEDS_THE_PLATE_LINE" /* 你记录的仍是总重量。这只用于每组下方的杠铃片提示行。 */)} />
    </>}
    {/* The exercise's own default meaning of its weight (S.dbLoad), stamped like the loading
        above. A routine can still pick its own on the exercise's settings. */}
    {isBellEx(ex) && <>
      <h4 className="sec">{t("WEIGHT_MEANS" /* 重量表示 */)}</h4>
      <DbLoadPicker ex={ex} value={dbLoadFor(st, ex.id)}
        onChange={v => update(s => { s.dbLoad = withDbLoad(s.dbLoad, ex.id, v) })} />
    </>}
    {/* No one-rep max on an assistance machine: the load is the help you were given, so the
        calculator would answer "your 1RM is 23 kg" about a number that gets smaller as you get
        stronger (issue #232). Cardio has none for the same kind of reason. */}
    {!isCardio(ex) && !isAssisted(ex) && <OneRM ex={ex} />}
    {instrFor(ex).length > 0 &&<><h4 className="sec">{t("HOW_TO" /* 动作要领 */)}{getLang() !== 'en' && !instrTranslated(ex) && <span className="dim" style={{ textTransform: 'none', letterSpacing: 0 }}> · {t("INSTRUCTIONS_IN_ENGLISH" /* 说明为英文 */)}</span>}</h4><ol className="steps-list">{instrFor(ex).map((s, i) => <li key={i}>{s}</li>)}</ol></>}
    {/* The catalogue is community-edited (catalogue/README.md): a wrong muscle, a clumsy step or a
        missing translation is one tap from an issue that already names the exercise. */}
    {!isCustomEx(ex) && !ex.missing && <a className="small dim exfix-link" target="_blank" rel="noopener"
      href={'https://github.com/DuarteSantos8/openGym/issues/new?template=exercise.yml&exercise=' + encodeURIComponent(ex.id + ', ' + ex.n)}>
      <Icon name="pencil" /> {t("SUGGEST_A_FIX_FOR_THIS_EXERCISE" /* 为此动作提出修改建议 */)}</a>}
  </>
}
export const exerciseDetailSheet = ex => ui().openSheet(close => <ExerciseDetail ex={ex} close={close} />)

/* ============================ exercise history ============================ */
// What you did on this exercise before, reachable mid-workout (issue #43): the curve first,
// then the last sessions set by set, so the question "what did I do last month" is answered
// without leaving the workout for Stats. Derived once per log change — the sheet re-renders on
// every store tick while a session runs, and LineChart drops its hover whenever `points`
// changes identity, so a series rebuilt per render would lose the tooltip under your finger.
function ExerciseHistory({ exId }) {
  const st = useStore(s => s.S)
  const ex = exOr(exId)
  const h = useMemo(() => exerciseHistory(st, exId), [st.workouts, exId])
  const [curve, setCurve] = useState('top')
  const onE1 = curve === 'e1rm' && h.e1rmPoints.length > 0
  const unit = h.metric === 'weight' ? st.unit : h.metric === 'reps' ? t("REPS_A" /* 次 */) : h.metric === 'sec' ? 's' : t("MIN" /* 分钟 */)
  const e1Best = useMemo(() => Math.max(0, ...h.e1rmPoints.map(p => p.y)), [h])
  if (!h.total) return <>
    <h3 className={exerciseNameClass(ex)}>{exerciseNameFor(ex)}</h3>
    <div className="empty"><div className="ico"><Icon name="history" /></div>{t("NO_SESSIONS_LOGGED_YET" /* 尚未记录任何训练 */)}</div>
  </>
  const tail = s => [
    s.volume > 0 && t("VOLUME" /* 训练量 */) + ' ' + fmtVol(s.volume, st.unit),
    s.e1rm != null && t("EST_ONE_REP_MAX" /* 估算 1RM */) + ' ' + fmtNum(s.e1rm) + ' ' + st.unit,
  ].filter(Boolean).join(' · ')
  return <>
    <h3 className={exerciseNameClass(ex)} style={{ marginBottom: 2 }}>{exerciseNameFor(ex)}</h3>
    <div className="muted small" style={{ marginBottom: 10 }}>{t("EXERCISE_HISTORY" /* 动作历史 */)} · {tn("COUNT_SESSION" /* {0} 次训练 */, "COUNT_SESSIONS" /* {0} 次训练 */, h.total)}</div>
    {/* Only reps work with a load produces an estimate, so the toggle is absent for the rest. */}
    {h.e1rmPoints.length > 0 && h.metric === 'weight' && <Segmented className="seg-range" value={curve} onChange={setCurve}
      options={[{ value: 'top', label: t("TOP_SET" /* 最佳组 */) }, { value: 'e1rm', label: t("EST_ONE_REP_MAX" /* 估算 1RM */) }]} />}
    <div className="chart" style={{ marginTop: 8 }}>
      <LineChart points={onE1 ? h.e1rmPoints : h.points} h={140} unit={onE1 ? st.unit : unit} color="var(--blue)" />
    </div>
    <div className="small row" style={{ margin: '6px 0 4px', gap: 5 }}>
      <Icon name="trophy" style={{ fontSize: 14, color: 'var(--yellow)' }} />
      {t("BEST" /* 最佳： */)} <b className="accent">{fmtNum(onE1 ? e1Best : h.best)} {onE1 ? st.unit : unit}</b>
    </div>
    <h4 className="sec">{h.sessions.length < h.total ? t("LAST_COUNT_SESSIONS" /* 最近 {0} 次训练 */, h.sessions.length) : t("SESSIONS" /* 训练次数 */)}</h4>
    <div className="list">
      {h.sessions.map(s => <div key={s.id} className="item" style={{ alignItems: 'flex-start' }}>
        <div className="grow">
          <div className="tt">{fmtDate(s.d, true)} {s.pr && <span className="pr"><Icon name="trophy" />PR</span>}</div>
          <div className="ss">{s.sets.map(x => setLabel(exId, x, s.target, speedUnitOf(st))).join('  ·  ')}</div>
          {tail(s) && <div className="small dim" style={{ marginTop: 3 }}>{tail(s)}</div>}
        </div>
        {s.value != null && s.value > 0 && <b className="accent nocap" style={{ whiteSpace: 'nowrap' }}>{fmtNum(s.value)} {unit}</b>}
      </div>)}
    </div>
  </>
}
export const exerciseHistorySheet = exId => ui().openSheet(close => <ExerciseHistory exId={exId} close={close} />)

/* ============================ add to routine ============================ */
function AddToRoutine({ ex, close }) {
  const st = useStore(s => s.S)
  const pick = rid => {
    close()
    const isNew = rid === '_new'
    exConfigSheet(ex, null, cfg => {
      update(s => {
        let r = isNew ? { id: uid(), name: t("NEW_ROUTINE" /* 新建训练计划 */), emoji: DEFAULT_GLYPH, ex: [] } : s.routines.find(x => x.id === rid)
        if (isNew) s.routines.push(r)
        if (r) r.ex.push({ id: ex.id, ...cfg })
      })
      const r = isNew ? S().routines[S().routines.length - 1] : st.routines.find(x => x.id === rid)
      toast(t("COUNT_ADDED_TO_COUNT" /* “{0}”已加入 {1} */, exerciseNameText(ex), r ? r.name : t("ROUTINE_A" /* 训练计划 */)))
      if (isNew && r) nav('/plan/r/' + r.id)
    }, null, isNew ? null : st.routines.find(x => x.id === rid))
  }
  return <>
    <h3 className={exerciseNameClass(ex)}>{t("ADD_COUNT" /* 添加“{0}” */, exerciseNameFor(ex))}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("PICK_A_ROUTINE_SETS_REPS_AND_WEIGHT_COME_NEXT" /* 选一个训练计划。组数、次数和重量接下来再设。 */)}</div>
    <div className="list">
      {st.routines.map(r => <div key={r.id} className="item" {...tappable(() => pick(r.id))}>
        <span className="lrow-i"><Icon name={glyphOf(r.emoji)} /></span>
        <div className="grow"><div className="tt">{r.name}</div><div className="ss">{exCount(r.ex.length)}</div></div>
        {r.ex.some(e => e.id === ex.id) && <span className="tag">{t("ALREADY_IN" /* 已包含 */)}</span>}<Icon name="plus" className="chev" />
      </div>)}
      <div className="item" {...tappable(() => pick('_new'))}><span className="lrow-i" style={{ background: 'var(--surface-3)' }}><Icon name="plusCircle" /></span>
        <div className="grow"><div className="tt">{t("NEW_ROUTINE" /* 新建训练计划 */)}</div><div className="ss">{t("CREATE_ONE_AND_START_WITH_THIS_EXERCISE" /* 新建一个并从这个动作开始 */)}</div></div><Icon name="plus" className="chev" /></div>
    </div>
  </>
}
export const addToRoutineSheet = ex => ui().openSheet(close => <AddToRoutine ex={ex} close={close} />)

/* ============================ custom exercises (issue #11) ============================ */
// Name + body part is all it takes — the exercise then behaves like any built-in one
// (planning, logging, PRs, stats). A photo, GIF or video of your own, and a link to a video or
// guide, are optional (components/CustomMediaField.jsx): the state keeps a small reference to the
// file, never the file itself, and the link is cleaned on save and again whenever it is opened.
function CustomExForm({ existing, prefill, onDone, close }) {
  const nameRef = useRef(null)
  const onNameFocus = useSheetKeyboard(nameRef)
  const [n, setN] = useState(existing ? existing.n : (prefill || ''))
  const [bp, setBp] = useState(existing ? existing.bp : '')
  const [eq, setEq] = useState(existing ? (existing.eq || '') : '')
  const storedEq = existing && typeof existing.eq === 'string' && existing.eq && !ALL_EQUIPMENT.includes(existing.eq) ? existing.eq : null
  const [desc, setDesc] = useState(existing ? (existing.desc || '') : '')
  const [media, setMedia] = useState(() => mediaOf(existing))
  // Whether this form changed the media at all. An edit that did not touch it writes back what the
  // exercise had, byte for byte: a ref from a newer version of the app (a codec or type this one
  // does not know) reads as nothing here, and re-normalizing it on a rename would delete it on
  // every device.
  const [mediaTouched, setMediaTouched] = useState(false)
  const [url, setUrl] = useState(existing && typeof existing.url === 'string' ? existing.url : '')
  const onMedia = patch => {
    if ('media' in patch) { setMedia(patch.media); setMediaTouched(true) }
    if ('url' in patch) setUrl(patch.url)
  }
  const [primaries, setPrimaries] = useState(() => {
    if (existing && Array.isArray(existing.primaries) && existing.primaries.length) return [...existing.primaries]
    if (existing?.bp === 'cardio') return ['cardiovascular system']
    const norm = hasExplicitMuscleMetadata(existing || {}) ? normalizeMuscleGroups(existing || {}) : []
    return norm.length ? [norm[0]] : []
  })
  const [secondaries, setSecondaries] = useState(() => {
    if (existing && Array.isArray(existing.primaries) && existing.primaries.length) return [...(existing.secondaries || [])]
    const norm = hasExplicitMuscleMetadata(existing || {}) ? normalizeMuscleGroups(existing || {}) : []
    return norm.slice(1)
  })
  // Every primary chip this sheet saw a tap on, in that order. `primaries` alone cannot say what the
  // user reached for first: an existing exercise seeds it in the map's order, because that is how the
  // muscles are stored. The taps are the only record of the user's own order, and they decide the
  // target when the one the exercise had is un-ticked.
  const [primaryTaps, setPrimaryTaps] = useState([])
  const togglePrimary = value => {
    setPrimaryTaps(current => [...current, value])
    setPrimaries(current => current.includes(value) ? current.filter(m => m !== value) : [...current, value])
  }
  const toggleSecondary = value => setSecondaries(current => current.includes(value) ? current.filter(m => m !== value) : [...current, value])
  const save = () => {
    const name = n.trim()
    if (!name) { toast(t("GIVE_IT_A_NAME" /* 请输入名称 */)); return }
    if (!bp) { toast(t("PICK_A_BODY_PART" /* 请选择身体部位 */)); return }
    if (!eq) { toast(t("PICK_EQUIPMENT" /* 选择器械 */)); return }
    // An exercise kept under its own name is not a duplicate, even when the catalogue has one
    // spelled the same (an imported "trap bar deadlift"): only a new or changed name is checked.
    const renamed = !existing || name.toLowerCase() !== String(existing.n || '').trim().toLowerCase()
    const dup = renamed && allExercises(S()).find(e => e.n.toLowerCase() === name.toLowerCase() && e.id !== (existing || {}).id)
    if (dup) { toast(t("COUNT_ALREADY_EXISTS" /* 「{0}」已存在 */, dup.n)); return }
    const d = desc.trim().slice(0, 1000)
    // An empty field removes the link; anything else has to be a web address.
    const link = url.trim() ? cleanUrl(url) : null
    if (url.trim() && !link) { toast(t("THAT_LINK_IS_NOT_A_WEB_ADDRESS" /* 这不是一个网址 */)); return }
    const keepMedia = !!existing && !mediaTouched
    const ref = keepMedia ? null : normalizeMediaRef(media)
    // Stored in the map's order, not the order the chips were tapped in — the tags on the exercise
    // used to shuffle with every edit.
    const prim = bp === 'cardio' ? ['cardiovascular system'] : inMuscleOrder(primaries)
    const sm = inMuscleOrder(secondaries.filter(m => !prim.includes(m)))
    const groups = [...prim, ...sm]
    // The one-word target (the library row, the picker, the Muscles view) is not the sorted list's
    // head — a hip thrust with Traps as an extra primary is not a Traps exercise. It is the primary
    // tapped first, and an edit keeps the exercise's target as long as that muscle is still a primary.
    // Once that muscle is gone the next answer is the first one tapped here that survived — a tap that
    // only turned a chip off says nothing and is skipped with it. The sorted list is the last resort,
    // for the user who drops the target and adds nothing in its place.
    const tg = (existing && prim.includes(existing.tg)) ? existing.tg : (primaryTaps.find(m => prim.includes(m)) || prim[0] || '')
    let id = existing && existing.id
    const extra = c => {
      if (!keepMedia) { if (ref) c.media = ref; else delete c.media }
      if (link) c.url = link; else delete c.url
    }
    if (existing) update(s => { const c = (s.customEx || []).find(x => x.id === id); if (c) {
      c.n = name; c.bp = bp; c.desc = d; c.tg = tg; c.sm = sm; c.muscleGroups = groups; c.primaries = prim; c.secondaries = sm; c.eq = eq
      extra(c)
    } })
    else {
      id = 'c' + uid()
      update(s => { const c = { id, n: name, bp, desc: d, tg, sm, muscleGroups: groups, primaries: prim, secondaries: sm, eq, custom: true }; extra(c); (s.customEx = s.customEx || []).push(c) })
    }
    // The file goes to the server now rather than after the state's own debounce: another device
    // that sees the reference first shows a tile until it arrives.
    if (ref) syncMedia({ force: true })
    close()
    toast(existing ? t("SAVED" /* 已保存 */) : t("COUNT_CREATED" /* 「{0}」已创建 */, name))
    onDone && onDone(EXIDX[id])
  }
  return <>
    <h3>{existing ? t("EDIT_CUSTOM_EXERCISE" /* 编辑自定义动作 */) : t("CREATE_YOUR_OWN_EXERCISE" /* 创建自己的动作 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("NAME_IT_AND_PICK_A_BODY_PART_IT_WORKS_JUST_LIKE_ANY" /* 起个名字，选个身体部位。用起来和其他动作一模一样。 */)}</div>
    <input ref={nameRef} className="input" placeholder={t("EXERCISE_NAME" /* 动作名称 */)} maxLength={80} value={n} onFocus={onNameFocus} onChange={e => setN(e.target.value)} />
    <div className="chips" style={{ margin: '12px 0' }}>
      {BODYPARTS.map(b => <button key={b} className={'chip' + (bp === b ? ' on' : '')} onClick={() => setBp(b)}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(b)}</button>)}
    </div>
    <div className="chips" style={{ margin: '12px 0' }}>
      {ALL_EQUIPMENT.map(k => (<button key={k} className={'chip' + (eq === k ? ' on' : '')} onClick={() => setEq(k)}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(k)}</button>))}
      {/* An imported exercise can carry equipment the list does not have (`custom` from a CSV or
          Hevy import). It stays a chip of its own, picked, so Save does not stop on "Pick equipment". */}
      {storedEq && <button key={storedEq} className={'chip' + (eq === storedEq ? ' on' : '')} onClick={() => setEq(storedEq)}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(storedEq)}</button>}
    </div>
    {bp && <>
      {bp !== 'cardio' && <MultiSelectRow title={t("PRIMARY_MUSCLE_GROUPS" /* 主要肌群 */)} sheetTitle={t("PRIMARY_MUSCLE_GROUPS" /* 主要肌群 */)}
        values={primaries}
        options={MUSCLES.map(m => ({ value: m, label: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[m]) }))}
        onToggle={togglePrimary} noneLabel={t("NO_EXPLICIT_MUSCLE_GROUP" /* 无明确肌群 */)} doneLabel={t("DONE" /* 完成 */)} />
      }
      <MultiSelectRow title={t("ADDITIONAL_MUSCLE_GROUPS" /* 其他肌群 */)} sheetTitle={t("ADDITIONAL_MUSCLE_GROUPS" /* 其他肌群 */)}
        values={secondaries}
        options={MUSCLES.filter(m => !primaries.includes(m)).map(m => ({ value: m, label: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[m]) }))}
        onToggle={toggleSecondary} noneLabel={t("NO_EXPLICIT_MUSCLE_GROUP" /* 无明确肌群 */)} doneLabel={t("DONE" /* 完成 */)} />
    </>}
    {bp === 'cardio' && <div className="small dim row" style={{ marginBottom: 10, gap: 5 }}><Icon name="figureRun" style={{ fontSize: 13 }} />{t("CARDIO_EXERCISES_LOG_TIME_SPEED_INSTEAD_OF_WEIGHT_REPS" /* 有氧动作记录时间 + 速度，而不是重量 × 次数。 */)}</div>}
    <textarea className="input" rows={4} maxLength={1000} placeholder={t("DESCRIPTION_OPTIONAL_SETUP_CUES_ANYTHING_YOU_WANT_TO_REMEMBER" /* 描述（可选）：设置、要点，任何你想记住的内容 */)}
      value={desc} onChange={e => setDesc(e.target.value)} />
    <CustomMediaField media={media} url={url} onChange={onMedia} />
    <div style={{ height: 14 }} />
    <Button variant="primary" onClick={save}>{existing ? t("SAVE" /* 保存 */) : t("CREATE_EXERCISE" /* 创建动作 */)}</Button>
    {existing && <><div style={{ height: 8 }} /><Button variant="danger" icon="trash" onClick={() => { close(); deleteCustomEx(existing) }}>{t("DELETE_EXERCISE" /* 删除动作 */)}</Button></>}
  </>
}
export const customExSheet = (existing, onDone, prefill) => ui().openSheet(close => <CustomExForm existing={existing} prefill={prefill} onDone={onDone} close={close} />)

export function deleteCustomEx(ex, afterDelete) {
  if (S().active?.entries.some(e => e.id === ex.id)) { toast(t("FINISH_YOUR_CURRENT_WORKOUT_FIRST" /* 请先完成当前训练 */)); return }
  confirmSheet({
    title: t("DELETE_COUNT" /* 删除「{0}」？ */, ex.n),
    message: t("IT_WILL_BE_REMOVED_FROM_YOUR_ROUTINES_ALREADY_LOGGED_WORKOUTS_KEEP_THEIR" /* 将从你的计划中移除。已记录的训练会保留其组数。 */),
    confirmText: t("DELETE" /* 删除 */), danger: true,
    onConfirm: () => {
      update(s => {
        // Keep display and muscle metadata in history before the custom catalogue row disappears.
        const snapshot = exerciseMuscleSnapshot(ex)
        s.workouts.forEach(w => w.entries.forEach(e => {
          if (e.id !== ex.id) return
          e.n = ex.n
          if (!e.muscleSnapshot || !Object.keys(e.muscleSnapshot).length) e.muscleSnapshot = snapshot
        }))
        s.customEx = (s.customEx || []).filter(x => x.id !== ex.id)
        s.routines.forEach(r => { r.ex = r.ex.filter(e => e.id !== ex.id); cleanupSg(r.ex) })
        delete s.exWeights[ex.id]
        s.favEx = (s.favEx || []).filter(id => id !== ex.id)
      })
      toast(t("EXERCISE_DELETED" /* 动作已删除 */))
      afterDelete && afterDelete()
    }
  })
}

/* ============================ exercise picker ============================ */
// Exercises already used in your routines or past workouts (for the "Chosen" filter + a marker).
function usageMap(st) {
  const u = {}
  st.routines.forEach(r => r.ex.forEach(e => { u[e.id] = (u[e.id] || 0) + 1 }))
  st.workouts.forEach(w => w.entries.forEach(e => { u[e.id] = (u[e.id] || 0) + 1 }))
  return u
}
// The swap pickers' own scope (#473): exercises sharing the swapped exercise's target muscle.
const SAME = '≈'
function ExercisePicker({ onPick, title, close, like }) {
  const st = useStore(s => s.S)
  const usage = usageMap(st)
  const [q, setQ] = useState('')
  // What a swap is away from: the picker opens on what trains the same muscle, if anything you
  // can use does, and "All" is one tap back to everything.
  const likeEx = like ? (EXIDX[like] || allExercises(st).find(e => e.id === like) || null) : null
  // A muscle nothing else trains gets no chip at all rather than one that lists nothing.
  const likeTg = swapMuscleOf(likeEx) && sameMuscleFirst(allExercises(st), likeEx).length ? swapMuscleOf(likeEx) : ''
  const [bp, setBp] = useState(() => {
    if (!likeTg) return ''
    const prof = activeProfile(st)
    return sameMuscleFirst(allExercises(st), likeEx).some(e => !prof || exAvailable(st, e)) ? SAME : ''
  })                                        // '' = all, '★' = chosen, '☆' = favourites, '≈' = same muscle, else a body part
  const [eq, setEq] = useState('')          // '' = any equipment
  const [cat, setCat] = useState('')        // '' = any type
  const [showAll, setShowAll] = useState(false)
  const [shown, setShown] = useState(50)
  const [byMuscle, setByMuscle] = useState(false)
  const searchRef = useRef(null)
  const bpStrip = useRef(null), eqStrip = useRef(null), catStrip = useRef(null)
  const onSearchFocus = useSheetKeyboard(searchRef)
  const moreRef = useAutoMore(() => setShown(s => s + 50))
  const all = allExercises(st)
  const profile = activeProfile(st)
  const inScope = e => bp === '★' ? usage[e.id] : bp === '☆' ? isFav(st, e.id) : (!bp || e.bp === bp)
  let inPart = searchExercises(bp === SAME ? sameMuscleFirst(all, likeEx) : all.filter(inScope), q)
  if (bp === '★') inPart = [...inPart].sort((a, b) => (usage[b.id] - usage[a.id]) || exerciseNameFor(a).localeCompare(exerciseNameFor(b)))
  // The Library's Type row (issue #521), with its fallback: a type the search or muscle group
  // narrowed away is ignored for this view, not forgotten.
  const { opts: catOpts, on: catOn, list: base } = byCategory(inPart, cat)
  const eqFiltered = (profile && !showAll) ? base.filter(e => exAvailable(st, e)) : base
  const eqOpts = equipmentOf(eqFiltered)
  // Drop the equipment filter if the search narrowed it away, so you never hit a dead end.
  const eqOn = eqOpts.includes(eq) ? eq : ''
  // Favourites float to the top of whatever the filters left (issue #6), the rest keeps its order.
  // On the same-muscle list the equipment order wins: what is on the same kit comes first,
  // favourites leading within each half.
  // While searching, what you have logged or planned follows right after them.
  const narrowedList = eqOn ? eqFiltered.filter(e => e.eq === eqOn) : eqFiltered
  const ranked = q.trim() ? sortYoursFirst(narrowedList, st, usage) : sortFavouritesFirst(narrowedList, st)
  const f = bp === SAME ? sameMuscleFirst(ranked, likeEx) : ranked
  const chosenCount = Object.keys(usage).length
  const favCount = (st.favEx || []).length
  const special = bp === '★' || bp === '☆'
  // The Library's live result count (GitLab !31), for the same reason: how many are left.
  const narrowed = !!(q.trim() || bp || eqOn || catOn)
  useRevealActiveChip(bpStrip, bp)
  useRevealActiveChip(eqStrip, eqOn)
  useRevealActiveChip(catStrip, catOn)
  // Close but not exact (a typo too many, most of the words, a similar name), listed under the
  // results once you have scrolled to their end, so a search almost never ends on nothing.
  // Worked out a beat behind the typing (useDeferredValue): the list itself never waits for it.
  const qLate = useDeferredValue(q)
  const similar = q.trim() && qLate === q && !special && f.length <= shown
    ? similarExercises((profile && !showAll ? all.filter(e => exAvailable(st, e)) : all).filter(e => bp === SAME || !bp || e.bp === bp), q, f, f.length ? 12 : 30)
    : []
  const pickRow = e => <div key={e.id} className="item" {...tappable(() => onPick(e))}>
        <Thumb ex={e} /><div className="grow"><div className={`tt ${exerciseNameClass(e)}`}>{isFav(st, e.id) && <Icon name="starFill" className="fav-star" />}{exerciseNameFor(e)}</div><div className="ss capitalize">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[e.tg] || e.tg || e.bp)} · {translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(e.eq)}</div></div>
        {/* Accent tag = already in a routine/log ("Chosen"); the yellow star by the name = favourite. */}
        {usage[e.id] && <span className="tag acc"><Icon name="starFill" /></span>}
        {/* A "+" glyph reads as "add this now" — it used to just open the same detail sheet as
            tapping the row, so it added nothing until you'd scrolled past the sets/reps config
            and found the real button. Now it does what it looks like: adds with the default
            config right away. Tapping the row itself still opens the detail/config sheet, for
            when you want to set sets/reps before adding. */}
        <button className="iconbtn chev" aria-label={t("ADD_COUNT" /* 添加“{0}” */, exerciseNameFor(e))} style={{ padding: 8, margin: -8 }}
          onClick={ev => { ev.stopPropagation(); onPick(e, true) }}><Icon name="plus" /></button>
      </div>
  if (byMuscle) return <>
    <div className="row between" style={{ marginBottom: 10 }}><h3>{title || t("ADD_EXERCISE" /* 添加动作 */)}</h3>
      <Button size="sm" variant="ghost" onClick={() => setByMuscle(false)}>{t("ALL" /* 全部 */)}</Button>
    </div>
    <MuscleExplorer onPick={onPick} />
  </>

  return <>
    <div className="row between" style={{ marginBottom: 10 }}><h3>{title || t("ADD_EXERCISE" /* 添加动作 */)}</h3>
      <Button size="sm" variant="tinted" icon="figureStrength" onClick={() => setByMuscle(true)}>{t("BY_MUSCLE" /* 按肌肉 */)}</Button>
    </div>
    {/* .picker-search is what index.css keys the keyboard-aware sheet layout on: the sheet
        lifts above the keys and the search stays put while the list scrolls under it. */}
    <div className="picker-search"><div className="search-row"><div className={'search' + (narrowed ? ' has-count' : '') + (q ? ' has-clear' : '')}><svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" /></svg>
      <input ref={searchRef} className="input" placeholder={t("SEARCH_COUNT_EXERCISES" /* 搜索 {0} 个动作… */, all.length)} value={q} onFocus={onSearchFocus} onChange={e => { setQ(e.target.value); setShown(50) }} />
      {narrowed && <span className="search-count" role="status" aria-label={exCount(f.length)}>{fmtNum(f.length)}</span>}
      {q && <button className="clear" onClick={() => { setQ(''); setShown(50) }} aria-label={t("CLEAR" /* 清除 */)}><Icon name="xmark" /></button>}</div>
      <ExerciseViewToggle /></div></div>
    {profile && <div className="small dim row" style={{ margin: '8px 0 2px', gap: 6, alignItems: 'center' }}>
      <Icon name="kettlebell" style={{ fontSize: 13 }} />
      {showAll ? t("SHOWING_ALL_EQUIPMENT" /* 正在显示全部器械 */) : t("SHOWING_WHAT_YOU_HAVE_IN_COUNT" /* 正在显示你在“{0}”拥有的器械 */, profile.name)}
      <button className="chip nocap" style={{ marginInlineStart: 'auto', padding: '3px 10px', fontSize: 12 }} onClick={() => setShowAll(v => !v)}>
        {showAll ? t("FILTER_BY_COUNT" /* 按“{0}”筛选 */, profile.name) : t("SHOW_ALL_EQUIPMENT" /* 显示全部器械 */)}
      </button>
    </div>}
    {/* Changing muscle group keeps the equipment filter: if it still has exercises under the new
        group the filter stays applied, and if not the eqOn fallback above drops it for this view
        without forgetting the choice (issue #71). The favourites/chosen chips still clear it —
        those are cross-body-part views where a stale equipment filter would be confusing. */}
    <div className="chips" ref={bpStrip} style={{ margin: eqOpts.length > 1 || catOpts.length > 1 ? '10px 0 6px' : '10px 0' }}>
      {likeTg && <button className={'chip nocap' + (bp === SAME ? ' on' : '')} onClick={() => { setBp(SAME); setShown(50) }}><Icon name="figureStrength" style={{ fontSize: 12, display: 'inline-block', marginInlineEnd: 4, verticalAlign: '-1px' }} />{t("SAME_MUSCLE_COUNT" /* 同一肌群：{0} */, translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[likeTg] || likeTg))}</button>}
      {favCount > 0 && <button className={'chip' + (bp === '☆' ? ' on' : '')} onClick={() => { setBp('☆'); setEq(''); setShown(50) }}><Icon name="starFill" className="fav-star" />{t("FAVOURITES" /* 收藏 */)} ({favCount})</button>}
      {chosenCount > 0 && <button className={'chip' + (bp === '★' ? ' on' : '')} onClick={() => { setBp('★'); setEq(''); setShown(50) }}><Icon name="starFill" style={{ fontSize: 12, display: 'inline-block', marginInlineEnd: 4, verticalAlign: '-1px' }} />{t("CHOSEN" /* 常用 */)} ({chosenCount})</button>}
      <button className={'chip nocap' + (!bp ? ' on' : '')} onClick={() => { setBp(''); setShown(50) }}>{t("ALL" /* 全部 */)}</button>
      {BODYPARTS.map(b => <button key={b} className={'chip' + (bp === b ? ' on' : '')} onClick={() => { setBp(b); setShown(50) }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(b)}</button>)}
    </div>
    {catOpts.length > 1 && <div className="chips" ref={catStrip} style={{ marginBottom: eqOpts.length > 1 ? 6 : 10 }}>
      <button className={'chip nocap' + (!catOn ? ' on' : '')} onClick={() => { setCat(''); setShown(50) }}>{t("ANY_TYPE" /* 所有类型 */)}</button>
      {catOpts.map(x => <button key={x} className={'chip' + (catOn === x ? ' on' : '')} onClick={() => { setCat(x); setShown(50) }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(x)}</button>)}
    </div>}
    {eqOpts.length > 1 && <div className="chips" ref={eqStrip} style={{ marginBottom: 10 }}>
      <button className={'chip nocap' + (!eqOn ? ' on' : '')} onClick={() => { setEq(''); setShown(50) }}>{t("ANY_EQUIPMENT" /* 所有器械 */)}</button>
      {eqOpts.map(x => <button key={x} className={'chip' + (eqOn === x ? ' on' : '')} onClick={() => { setEq(x); setShown(50) }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(x)}</button>)}
    </div>}
    <div className={'list' + (st.exerciseView === 'cards' ? ' ex-grid' : '')}>
      {!special && <div className="item ex-new" {...tappable(() => customExSheet(null, ex => onPick(ex), q.trim()))}>
        <div className="thumb thumb-x"><Icon name="plusCircle" /></div>
        <div className="grow"><div className="tt">{t("CREATE_YOUR_OWN_EXERCISE" /* 创建自己的动作 */)}</div><div className="ss">{t("NAME_BODY_PART_AND_A_PHOTO_OR_VIDEO_IF_YOU_LIKE" /* 名称 + 身体部位，可附照片或视频 */)}</div></div><Icon name="plus" className="chev" />
      </div>}
      {f.slice(0, shown).map(pickRow)}
      {f.length === 0 && bp === '★' && <div className="empty">{t("NOTHING_PICKED_YET_ADD_SOME_EXERCISES_AND_THEY_LL_SHOW_UP_HERE" /* 还没选任何动作。添加一些动作，它们就会出现在这里。 */)}</div>}
      {f.length === 0 && bp === '☆' && <div className="empty">{t("NO_FAVOURITES_YET_TAP_THE_STAR_ON_AN_EXERCISE_TO_ADD_ONE" /* 还没有收藏。点动作旁的星标就能加进来。 */)}</div>}
      {similar.length > 0 && <h4 className="sec similar-label">{f.length ? t("SIMILAR_EXERCISES" /* 相似动作 */) : t("NO_EXACT_MATCH_THESE_COME_CLOSE" /* 没有完全匹配，这些比较接近： */)}</h4>}
      {similar.map(pickRow)}
    </div>
    {f.length > shown && <><div style={{ height: 8 }} /><Button ref={moreRef} onClick={() => setShown(s => s + 50)}>{t("SHOW_MORE" /* 显示更多 */)}</Button></>}
  </>
}
// `title` names what the pick is for when it is not an add — the routine editor's Replace (#110).
// `like` is the exercise a swap or a replace is away from: the picker then opens on the ones that
// train the same muscle, same equipment first (#473).
export const exercisePicker = (onPick, { title, like } = {}) => ui().openSheet(close => <ExercisePicker onPick={onPick} title={title} like={like} close={close} />)

/** Start a safe swap for one exact active-workout occurrence. */
export function swapActiveWorkoutExercise(index) {
  const active = S().active
  if (!active?.entries?.[index]) return

  // The "+" on a picker row commits with the default config, exactly as it does in the add
  // flows; tapping the row still opens the config sheet first.
  // Worded for the session, not the routine: a swap changes today's workout only.
  const picker = exercisePicker((ex, quick) => quick ? swapTo(ex, defaultConfig(ex.id)) : exConfigSheet(ex, null, cfg => swapTo(ex, cfg), null, null, null, null, t("USE_IN_THIS_WORKOUT" /* 用于本次训练 */)), { title: t("SWAP_EXERCISE" /* 更换动作 */), like: active.entries[index].id })
  function swapTo(ex, cfg) {
    // The picker is a chooser here, not a stack you keep adding from: one swap, then back to
    // the workout. (The add flow deliberately leaves it open.)
    picker.close()
    const full = { ...cfg, id: ex.id }
    const st = S()
    const current = st.active?.entries?.[index]
    if (!current) return
    // A swap is an in-place substitution — routine identity is unchanged, so the replacement
    // keeps the slot's own `rid` and reads its prescription from that routine (not a
    // session-wide one). A slot with no `rid` is freestyle.
    const slotRoutine = current.rid ? st.routines.find(r => r.id === current.rid) : null
    const freestyle = !slotRoutine
    // Same rows the add flow builds: last time's loads and, in a planned session, the
    // prescription — swapping barbell for dumbbell bench must not start you at an empty bar.
    // Built from what came before the session's day when it is logged into the past (sessionHistory).
    const step = modeOf(full) === 'reps' ? weightIncrement(full, st.unit) : defaultIncrement(ex.id, st.unit)
    const past = sessionHistory(st)
    // A freestyle swap logs dumbbell weights the way the exercise means them now, and starts
    // from last time read in that meaning (lib/dumbbells.js), as a planned one does.
    const built = freestyle
      ? { target: withMeaning(st, cfg, ex.id), plan: null, sets: applyIntensifierPlan(buildSets(historyAs(past, ex.id, dbLoadFor(st, full)), full, { step: (modeOf(full) === 'reps' && ownedWeightsFor(st, full)) || step, preferLast: true }), full, dropGrid(st, full)) }
      : buildPlannedEntry(past, full, slotRoutine, { noProg: builtOutOfProgression(current, slotRoutine) })
    const replacement = {
      id: ex.id,
      ...built,
      ...(current.rid ? { rid: current.rid } : {}),
      // A slot kept out of progression stays out once swapped. Replaced in place the entry keeps
      // it anyway; inserted beside logged sets, the replacement would otherwise count as a
      // regular session of the new exercise. Only a deload or rehab slot is built without a
      // prescription (above): one kept out by hand keeps the marker and its Undo on the card,
      // and an Undo must leave numbers that are right to count.
      ...(current.noProg === true ? { noProg: true } : {}),
    }

    const apply = options => {
      // A timed callback closes over entry/set indexes. Invalidate it, and the current rest,
      // before the selected occurrence can be replaced or a new entry shifts those indexes.
      ui().stopWork()
      ui().stopRest()
      update(state => { swapActiveExercise(state.active, index, replacement, options) }, true)
    }
    const logged = (current.sets || []).some(set => set.done === true)
    if (!logged) { apply(); return }

    if (current.sg) {
      ui().openSheet(close => <>
        <h3>{t("SWAP_EXERCISE_A" /* 要更换动作吗？ */)}</h3>
        <div className="muted small" style={{ marginBottom: 12 }}>
          {t("LOGGED_SETS_STAY_WITH_THE_ORIGINAL_EXERCISE_CHOOSE_WHERE_THE_REPLACEMENT_BELONGS" /* 已记录的组数会保留在原动作上。请选择替换动作的位置。 */)}
        </div>
        <Button variant="primary" onClick={() => { close(); apply({ loggedConfirmed: true, groupDisposition: 'keep' }) }}>
          {t("KEEP_REPLACEMENT_IN_THIS_GROUP" /* 将替换动作保留在此组 */)}
        </Button>
        <div style={{ height: 8 }} />
        <Button variant="ghost" onClick={() => { close(); apply({ loggedConfirmed: true, groupDisposition: 'detach' }) }}>
          {t("INSERT_AFTER_THIS_GROUP" /* 插入到此组之后 */)}
        </Button>
      </>)
      return
    }

    confirmSheet({
      title: t("SWAP_EXERCISE_A" /* 要更换动作吗？ */),
      message: t("LOGGED_SETS_STAY_WITH_THE_ORIGINAL_EXERCISE_THE_REPLACEMENT_WILL_BE_INSERTED" /* 已记录的组数会保留在原动作上。替换动作将插入其后。 */),
      confirmText: t("CONTINUE" /* 继续 */),
      onConfirm: () => apply({ loggedConfirmed: true })
    })
  }
}

/* ============================ equipment profiles ============================ */
// Create or edit one profile ("Home", "Gym", ...): a name plus a checklist of what you have.
function EquipmentProfileSheet({ profile, close }) {
  const update = useStore(s => s.update)
  const nameRef = useRef(null)
  const [checked, setChecked] = useState(new Set(profile ? profileEquipment(profile) : []))
  const toggle = k => setChecked(s => { const n = new Set(s); n.has(k) ? n.delete(k) : n.add(k); return n })
  const save = () => {
    const name = (nameRef.current.value || '').trim()
    if (!name) { return }
    update(s => {
      s.equipProfiles = s.equipProfiles || []
      const equipment = [...checked]
      if (profile) {
        const p = s.equipProfiles.find(x => x.id === profile.id)
        if (p) { p.name = name; p.equipment = equipment; p.accV = ACC_V }
      } else {
        const p = newProfile(name); p.equipment = equipment
        s.equipProfiles.push(p)
        if (!s.activeEquipId) s.activeEquipId = p.id
      }
    })
    close()
  }
  return <>
    <h3>{profile ? t("EDIT_PROFILE" /* 编辑配置 */) : t("NEW_EQUIPMENT_PROFILE" /* 新建器械配置 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("NAME_IT_AFTER_WHERE_YOU_TRAIN_LIKE_HOME_OR_GYM_THEN_TICK" /* 用你训练的地点命名（比如“家里”或“健身房”），然后勾选你在那里有的器械。 */)}
    </div>
    <TextField ref={nameRef} defaultValue={profile?.name || ''} placeholder={t("PROFILE_NAME" /* 配置名称 */)} maxLength={40} />
    <div style={{ height: 12 }} />
    <div className="chips">
      {ALL_EQUIPMENT.map(k => (
        <button key={k} className={'chip' + (checked.has(k) ? ' on' : '')} onClick={() => toggle(k)}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(k)}</button>
      ))}
    </div>
    <div className="dim small" style={{ marginTop: 10 }}>
      {t("BODY_WEIGHT_EXERCISES_ARE_ALWAYS_AVAILABLE_UNLESS_THEY_NEED_A_PULL_UP" /* 自重动作始终可用，除非需要引体向上杆或卧推凳。 */)}
    </div>
    <div style={{ height: 14 }} /><Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const equipmentProfileSheet = profile => ui().openSheet(close => <EquipmentProfileSheet profile={profile} close={close} />)

/* ============================ exercise config ============================ */
// Progression settings for one exercise (issue #17). Shown inside the config sheet because
// "how does this lift go up" belongs next to sets and reps, not in a separate screen. Left
// on "follow the routine" it inherits, so most people never touch it.
const progressionStepOf = (c, mode, ex, unit) =>
  c.inc >= 0 ? c.inc : (mode === 'time' ? 5 : defaultIncrement(ex.id, unit))
// Back-off sets step down by the same Step, so a plan using them needs one even with no rule.
const progressionStepIsValid = (step, policy, backoff = false) =>
  (policy === 'off' && !backoff) || (Number.isFinite(step) && step > 0)
// Back-off sets (lib/backoff.js) are offered where there is a load to step down: rep work on a
// loaded exercise, not a pyramid (it owns each set), not a rest-pause (one work set), not an
// assistance machine (less load is harder there).
const backoffOffered = (c, mode, ex, bw) => mode === 'reps' && !bw && !isAssisted({ ...c, id: ex.id })
  && !(Array.isArray(c.pyramid) && c.pyramid.length) && c.intensifier?.type !== 'restpause'

// Double and triple progression both climb a rep range (`repsMin`..`reps`), so the sheet keeps it
// normalised for either.
const climbsRange = policy => policy === 'double' || policy === 'triple'
// Triple progression's set ceiling while it is being edited: never below the starting sets.
const setsMaxOf = c => Math.max(Math.max(1, Math.round(c.sets) || 1), Math.min(MAX_TRIPLE_SETS, Math.round(c.setsMax) || 0))

function ProgressionFields({ ex, mode, c, setC, routine, unit, perSide, bw }) {
  // Triple progression adds sets and then load. Bodyweight work with nothing added already climbs
  // reps and then sets on its own (the rep ceiling below), and has no load to finish the cycle
  // with, so it is not offered there.
  const options = (POLICIES_FOR[mode] || ['off']).filter(p => p !== 'triple' || !bw || c.weight > 0 || c.prog === 'triple')
  if (options.length < 2) return null
  const inherited = policyFor({ id: ex.id }, routine, mode)
  const active = policyFor({ ...c, id: ex.id }, routine, mode)
  const inc = progressionStepOf(c, mode, ex, unit)
  const canBackoff = backoffOffered(c, mode, ex, bw)
  const backoff = canBackoff && c.backoff === true
  const invalid = !progressionStepIsValid(inc, active, backoff)
  // "26 → 24 → 22 kg": what the sets will open at, from the weight and step typed above.
  const preview = backoff && c.weight > 0 && inc > 0
    ? backoffWeights(c.weight, Math.max(1, Math.round(c.sets) || 1), inc).map(fmtNum).join(' → ') + ' ' + unit
    : ''
  const stride = mode === 'reps' && perSide ? 2 : 1
  const range = climbsRange(active) ? normalizeRepRange(c.reps, c.repsMin, stride) : null
  const epleyEligible = mode === 'reps' && !isBw({ ...c, id: ex.id }) && (active === 'linear' || climbsRange(active))
  // What is typed is shown as typed, 0 for an emptied field included: shown as the default 90
  // instead, the field could not be emptied to type a new percentage.
  const deloadPercent = Math.round((c.deloadFactor != null && Number.isFinite(Number(c.deloadFactor)) ? Number(c.deloadFactor) : 0.9) * 100)
  const setRule = v => setC(x => {
    const next = { ...x, prog: v || undefined }
    // Greyskull's final set is taken to failure by design, so choosing it here switches "Last set
    // to failure" on too, unless it was already decided. Only the sheet's draft: nothing is
    // written until Save, and a plan saved before stays what it was.
    if (v === 'greyskull' && next.lastToFailure == null) next.lastToFailure = true
    const picked = policyFor({ ...next, id: ex.id }, routine, mode)
    // Triple progression opens with room for two more sets, the usual 3 to 5.
    if (picked === 'triple' && !(next.setsMax > 0)) next.setsMax = Math.min(MAX_TRIPLE_SETS, Math.max(1, Math.round(next.sets) || 1) + 2)
    return climbsRange(picked)
      ? { ...next, ...normalizeRepRange(next.reps, next.repsMin, stride) }
      : next
  })
  return <>
    <h4 className="sec">{t("PROGRESSION" /* 进阶方式 */)}</h4>
    <div className="sect-b" style={{ marginBottom: 8 }}>
      <SelectRow title={t("RULE" /* 规则 */)} sheetTitle={t("PROGRESSION" /* 进阶方式 */)} value={c.prog || ''} onChange={setRule}
        options={[{ value: '', label: t("FOLLOW_THE_ROUTINE_COUNT" /* 跟随该计划（{0}） */, translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(POLICY_NAME[inherited])) },
          ...options.map(p => ({ value: p, label: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(POLICY_NAME[p]) }))]} />
    </div>
    <div className="small dim" style={{ marginBottom: active === 'off' ? 18 : 10 }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(POLICY_DESC[active])}</div>
    {/* Double progression on a weighted exercise fills this row with four steppers; `cfgrow-4`
        lets it wrap into two pairs on phones, where four abreast left the inputs a few px wide. */}
    {(active !== 'off' || backoff) && <div className={'row cfgrow' + ((active === 'double' && epleyEligible) || active === 'triple' ? ' cfgrow-4' : '')} style={{ marginBottom: 18 }}>
      <Stepper label={mode === 'time' ? t("STEP_SECONDS" /* 加量（秒） */) : t("STEP_COUNT" /* 加量（{0}） */, unit)} value={inc}
        step={mode === 'time' ? 5 : 1.25} decimal={mode !== 'time'} invalid={invalid} className={invalid ? 'invalid' : ''}
        onChange={v => setC(x => ({ ...x, inc: v }))} />
      {climbsRange(active) && <>
        {/* The draft stays as typed: normalising on every keystroke turned "12" into 92 (the
            "1" was pulled above the lower bound first). Save and the engine normalise anyway. */}
        <Stepper label={t("REPS_FROM" /* 次数下限 */)} value={c.repsMin ?? range.repsMin} step={stride} decimal={false}
          onChange={v => setC(x => ({ ...x, repsMin: v }))} />
        <Stepper label={t("REPS_UP_TO" /* 次数上限 */)} value={c.reps ?? range.reps} step={stride} decimal={false}
          onChange={v => setC(x => ({ ...x, reps: v }))} />
      </>}
      {/* Where triple progression stops adding sets; the Sets above are where it starts. */}
      {active === 'triple' && <Stepper label={t("SETS_UP_TO" /* 组数上限 */)} value={c.setsMax ?? setsMaxOf(c)} step={1} decimal={false}
        onChange={v => setC(x => ({ ...x, setsMax: v }))} />}
      {epleyEligible && <Stepper label={t("DELOAD_ONE_REP_MAX" /* 减量 1RM (%) */)} value={deloadPercent} step={5} min={50} max={95} decimal={false}
        onChange={v => setC(x => ({ ...x, deloadFactor: Number(v) / 100 }))} />}
    </div>}
    {invalid && <div className="small" role="alert" style={{ color: 'var(--red)', marginTop: -10, marginBottom: 18 }}>
      {t("ENTER_A_POSITIVE_STEP_TO_USE_THIS_PROGRESSION_RULE" /* 请输入一个正数步长以使用此进阶规则。 */)}
    </div>}
    {/* Off by default and only written when on, so every plan saved before it stays the shape
        it was. The step is the one above: the gear's own increment, set once per exercise. */}
    {canBackoff && <>
      <div className="sect-b" style={{ marginBottom: 8 }}>
        <Row icon="steps" iconTint="var(--acc)" title={t("BACK_OFF_SETS" /* 减重组（Back-off） */)}
          subtitle={t("EACH_SET_ONE_STEP_LIGHTER_THAN_THE_ONE_BEFORE_THE_WEIGHT_ABOVE" /* 每组比上一组轻一个步长。上面的重量是第一组。 */)}>
          <Switch checked={backoff} onChange={v => setC(x => ({ ...x, backoff: v || undefined }))} />
        </Row>
      </div>
      <div className="small dim" style={{ marginBottom: 18 }}>
        {backoff
          ? (preview ? t("SETS_OPEN_AT_COUNT_THE_FIRST_SET_GOES_UP_WHEN_EVERY_SET" /* 各组从 {0} 开始。每组都达到目标次数时，第一组加重，其余各组随之调整。 */, preview) : t("THE_FIRST_SET_GOES_UP_WHEN_EVERY_SET_REACHES_ITS_REPS_AND" /* 每组都达到目标次数时，第一组加重，其余各组随之调整。 */))
          : t("ALL_SETS_AT_THE_SAME_WEIGHT" /* 所有组使用相同重量。 */)}
      </div>
    </>}
  </>
}

// The drop-set and rest-pause fields take what is typed and are held to their minimums once left
// (Stepper `min`). A sheet saved from a field still being typed in is held to them here: an
// emptied weight drop would otherwise plan drops at the same weight.
const intensifierToSave = x => (x.type === 'dropset'
  ? { ...x, count: Math.max(1, Math.round(x.count) || 0), pct: Math.max(5, Number(x.pct) || 0) }
  : x.type === 'restpause'
    ? { ...x, totalReps: Math.max(1, Math.round(x.totalReps) || 0), restSec: Math.max(5, Number(x.restSec) || 0) }
    : x)

function ExConfig({ ex, existing, onSave, onDelete, onReplace, close, routine, initial, saveLabel }) {
  const st = useStore(s => s.S)
  const cardio = isCardio(ex.id)
  const speedUnit = speedUnitOf(st)
  const seed = existing || initial || defaultConfig(ex.id)
  const [c, setC] = useState(() => {
    const cfg = { ...seed }
    // A session's target carries the meaning of its dumbbell weight as a stamp (lib/dumbbells.js);
    // one that only repeats the exercise's own default is not the slot's choice, so it is not kept.
    if (cfg.dbLoad != null && dbLoadOf(cfg.dbLoad) === dbLoadFor(st, ex.id)) delete cfg.dbLoad
    return climbsRange(policyFor({ ...cfg, id: ex.id }, routine, modeOf({ ...cfg, id: ex.id })))
      ? { ...cfg, ...normalizeRepRange(cfg.reps, cfg.repsMin, isPerSide(cfg) ? 2 : 1) }
      : cfg
  })
  // Cardio keeps its own duration+speed form; the reps/time choice (issue #16) is offered for
  // everything else, which is where the gap was — planks, hangs, wall sits, loaded carries.
  const mode = cardio ? 'cardio' : modeOf({ ...c, id: ex.id })
  // Both default from the dataset and are then whatever the config says — see isBw.
  const bw = !cardio && isBw({ ...c, id: ex.id })
  const perSide = isPerSide(c)
  // Pyramid sets: one rep target per set, in place of the flat Sets × Reps (CONTEXT.md).
  const pyramid = mode === 'reps' && isPyramid({ ...c, mode })
  const setPyramidAt = (i, v) => setC(x => ({ ...x, pyramid: x.pyramid.map((p, j) => (j === i ? v : p)) }))
  const progressionPolicy =policyFor({ ...c, id: ex.id }, routine, mode)
  const progressionStepInvalid = !progressionStepIsValid(progressionStepOf(c, mode, ex, st.unit), progressionPolicy, c.backoff === true && backoffOffered(c, mode, ex, bw))
  const activePolicy = policyFor({ ...c, id: ex.id }, routine, mode)
  // Both climb a range: the flat Reps stepper gives way to "Reps from" / "Reps up to".
  const ranged = mode === 'reps' && climbsRange(activePolicy)
  const triple = mode === 'reps' && activePolicy === 'triple'
  // Keep whatever the other mode already had (sets, weight) and fill only what is missing.
  const setMode = m => setC(x => {
    const next = { ...defaultConfig(ex.id, m), ...x, mode: m }
    return m === 'reps' && climbsRange(policyFor({ ...next, id: ex.id }, routine, 'reps'))
      ? { ...next, ...normalizeRepRange(next.reps, next.repsMin, isPerSide(next) ? 2 : 1) }
      : next
  })
  const save = () => {
    if (progressionStepInvalid) return
    close()
    const sets = Math.max(1, Math.round(c.sets) || (cardio ? 1 : 3))
    // Only carry progression settings that differ from the inherited default, so a plan file
    // stays readable and "follow the routine" keeps meaning exactly that.
    const prog = {}
    if (c.prog) prog.prog = c.prog
    if (c.inc > 0) prog.inc = c.inc
    // Epley deloading is configurable per occurrence, but the default stays omitted so older
    // plans retain their compact shape and keep the existing 90% behaviour.
    if (mode === 'reps' && !bw && (activePolicy === 'linear' || climbsRange(activePolicy))) {
      const deloadFactor = Math.max(0.5, Math.min(0.95, Number(c.deloadFactor) || 0.9))
      if (deloadFactor !== 0.9) prog.deloadFactor = deloadFactor
    }
    // Written only when it differs from what the dataset already says, so a barbell config
    // stays exactly the shape it was before these flags existed.
    // `bodyweight` is true of a hold as much as of a set of reps. `side` used to be dropped on
    // switching to Time too — a timed hold has no rep count to split — but "per side" does not
    // have to mean splitting: for a hold it means doing the whole thing once per side, so the
    // flag now survives the switch and buildWorkSets doubles the planned sets instead.
    const flags = {}
    if (bw !== isBodyweightEq(ex.id)) flags.bodyweight = bw
    // Free text, e.g. a pyramid's per-set loading ("bar only, +1 plate/side each set") — the
    // sets/reps/weight fields are one flat target and have no room for that on their own.
    // Mode-independent, so it is spread in below rather than folded into `flags`.
    const note = (c.note || '').trim().slice(0, 500)
    const withNote = note ? { note } : {}
    // Only written when there are any, so a plan that never asked for warm-ups keeps the exact
    // shape it had — and reads back as 0 either way (buildSets).
    const warmupSets = Math.max(0, Math.min(MAX_PLANNED_WARMUPS, Math.round(c.warmupSets) || 0))
    const withWarmups = warmupSets ? { warmupSets } : {}
    // Per-exercise rest (issue #10): written only when a positive value was set, so 0 keeps
    // inheriting the global rest timer and a config that never touched it stays the shape it
    // was. Mode-independent — a heavy triple, a plank and a cardio interval all rest.
    const restSec = Math.max(0, Math.round(c.restSec) || 0)
    const withRest = restSec ? { restSec } : {}
    // What a dumbbell weight means in this slot (lib/dumbbells.js): written only when the slot
    // picked its own, so every other config stays the shape it was.
    const dbLoad = isBellEx(ex) && !bw ? dbLoadOf(c.dbLoad) : null
    const withMeant = dbLoad ? { dbLoad } : {}
    // "Last set to failure": written only when on, so a plan that never asked keeps its shape.
    const withFailure = c.lastToFailure === true ? { lastToFailure: true } : {}
    if (cardio) onSave({ sets, min: Math.max(1, Math.round(c.min) || 20), speed: Math.max(0, c.speed || 8), ...withNote, ...withRest })
    else if (mode === 'time') onSave({ sets, mode: 'time', sec: Math.max(1, Math.round(c.sec) || 45), weight: Math.max(0, c.weight || 0), ...flags, ...(perSide ? { side: true } : {}), ...prog, ...withNote, ...withWarmups, ...withRest, ...withMeant, ...withFailure })
    else {
      // A unilateral target is stored even: the split has to divide, and a typed 15 would
      // otherwise plan seven reps on one side and eight on the other, every session.
      const typed = Math.max(1, Math.round(c.reps) || 10)
      const stride = perSide ? 2 : 1
      let reps = perSide ? Math.ceil(typed / stride) * stride : typed
      let range = null
      if (ranged) {
        range = normalizeRepRange(reps, c.repsMin, stride)
        reps = range.reps
      }
      const out = { sets, mode: 'reps', reps, weight: Math.max(0, c.weight || 0), ...flags, ...(perSide ? { side: true } : {}), ...prog, ...withNote, ...withWarmups, ...withRest, ...withMeant }
      // The list is the prescription; sets and reps follow it, so everything that reads the
      // flat target (a config sheet reopened with the toggle off, older builds) still makes sense.
      const list = pyramid ? normalizePyramid(c.pyramid, stride) : []
      if (list.length) Object.assign(out, flatFromPyramid(list), { pyramid: list })
      const pyramidRest = list.length ? normalizePyramidRest(c.pyramidRest, list.length) : []
      if (pyramidRest.length) out.pyramidRest = pyramidRest
      const pyramidWeight = list.length && !bw ? normalizePyramidWeight(c.pyramidWeight, list.length) : []
      if (pyramidWeight.length) out.pyramidWeight = pyramidWeight
      if (ranged) out.repsMin = range.repsMin
      // Triple progression's set ceiling, written only when it is above the starting sets: at the
      // same number it would add nothing, and the plan keeps the shape it had.
      if (triple && !list.length && setsMaxOf(c) > sets) out.setsMax = setsMaxOf(c)
      // A ceiling below the working reps would tell you to add a set on day one.
      if (bw && !(out.weight > 0) && c.repsMax > 0) out.repsMax = Math.max(reps, Math.round(c.repsMax))
      // Every set in this exercise becomes a drop-set/rest-pause (buildSets stamps the rows) —
      // decided here, in the plan, not re-decided live each time you train it.
      if (!list.length && c.intensifier && c.intensifier.type) out.intensifier = intensifierToSave(c.intensifier)
      // Back-off sets: written only when on, and only where the sheet offered them.
      if (c.backoff === true && backoffOffered(out, 'reps', ex, bw) && isBackoff({ ...out, backoff: true })) out.backoff = true
      // A pyramid has its own Max set for this, so the flag is not offered (or kept) there.
      if (!list.length) Object.assign(out, withFailure)
      onSave(out)
    }
  }
  return <>
    <h3 className={exerciseNameClass(ex)}>{exerciseNameFor(ex)}</h3>
    <Media ex={ex} />
    {/* The same tags the exercise detail sheet shows, secondaries included: choosing what goes
        into a plan is exactly when "what else does this hit" matters, and until now that was
        only visible from the Exercises tab, after the fact. Custom exercises and the newer
        metadata name muscles by the map's ids ("forearm", "gluteal"), which only MUSCLE_NAME
        turns into a translatable label. */}
    <div className="row" style={{ gap: 6, flexWrap: 'wrap', margin: '10px 0 14px' }}>
      {cardio && <span className="tag acc"><Icon name="figureRun" />{t("CARDIO" /* 有氧 */)}</span>}
      <span className="tag">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[ex.tg] || ex.tg || ex.bp)}</span><span className="tag">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ex.eq)}</span>
      {!cardio && (ex.secondaries?.length ? ex.secondaries : smOf(ex)).filter(trainedBy(ex)).slice(0, 3)
        .map((s, i) => <span key={i} className="tag dim">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MUSCLE_NAME[s] || s)}</span>)}
    </div>
    {descFor(ex) && <div className="exnote">{descFor(ex)}</div>}
    {!cardio && <div style={{ marginBottom: 14 }}>
      <Segmented className="seg-range" value={mode} onChange={setMode}
        options={[{ value: 'reps', label: t("REPS" /* 次数 */) }, { value: 'time', label: t("TIME" /* 时间 */) }]} />
    </div>}
    <div className="row cfgrow" style={{ marginBottom: mode === 'time' ? 8 : 18 }}>
      {cardio ? <>
        <Stepper label={t("INTERVALS" /* 间歇数 */)} value={c.sets} step={1} decimal={false} onChange={v => setC(x => ({ ...x, sets: v }))} />
        <Stepper label={t("MINUTES" /* 分钟 */)} value={c.min} step={1} decimal={false} onChange={v => setC(x => ({ ...x, min: v }))} />
        {/* Typed and stepped in the profile's unit, kept in km/h (lib/speed.js). */}
        <Stepper label={speedUnit === 'mph' ? t("SPEED_MPH" /* 速度（mph） */) : t("SPEED_KM_H" /* 速度（km/h） */)} value={toSpeed(c.speed, speedUnit)} step={0.5}
          onChange={v => setC(x => ({ ...x, speed: fromSpeed(v, speedUnit) }))} />
      </> : mode === 'time' ? <>
        <Stepper label={t("SETS" /* 组数 */)} value={c.sets} step={1} decimal={false} onChange={v => setC(x => ({ ...x, sets: v }))} />
        <Stepper label={t("SECONDS" /* 秒数 */)} value={c.sec} step={5} decimal={false} onChange={v => setC(x => ({ ...x, sec: v }))} />
        {/* A bodyweight hold's load is the "Added" row below — showing both put two fields on
            one value. */}
        {!bw && <Stepper label={t("WEIGHT_COUNT" /* 重量（{0}） */, st.unit)} value={c.weight} step={2.5} onChange={v => setC(x => ({ ...x, weight: v }))} />}
      </> : <>
        {/* Rest-pause always trains as exactly two rows — a warm-up at this rep count, then one
            rest-pause work set — so "Sets" has nothing left to mean and only invites a mismatch. */}
        {c.intensifier?.type !== 'restpause' && !pyramid &&
          <Stepper label={triple ? t("SETS_FROM" /* 组数下限 */) : t("SETS" /* 组数 */)} value={c.sets} step={1} decimal={false} onChange={v => setC(x => ({ ...x, sets: v }))} />}
        {!ranged && !pyramid && <Stepper label={t("REPS" /* 次数 */)} value={c.reps} step={perSide ? 2 : 1} decimal={false} onChange={v => setC(x => ({ ...x, reps: v }))} />}
        {/* On bodyweight work the weight stepper is the click #32 is about, so it is not here
            until there is a belt to describe — see the added-weight row below. */}
        {!bw && !pyramid && <Stepper label={t("WEIGHT_COUNT" /* 重量（{0}） */, st.unit)} value={c.weight} step={2.5} onChange={v => setC(x => ({ ...x, weight: v }))} />}
      </>}
    </div>
    {/* Pyramid sets: a row per set, each with its own reps or Max, rest and weight. A set left
        at 0 weight starts from that same set last time (buildSets). */}
    {pyramid && <div style={{ marginTop: -10, marginBottom: 18 }}>
      {/* Presets replace the list (and its rests and weights) in one tap; the sheet is not saved
          until Save. */}
      <div className="chips" style={{ marginBottom: 10 }}>
        {PYRAMID_PRESETS.map((preset, k) => <button key={k} type="button" className="chip"
          onClick={() => setC(x => ({ ...x, pyramid: [...preset], pyramidRest: undefined, pyramidWeight: undefined }))}>{pyramidLabel(preset)}</button>)}
      </div>
      {c.pyramid.map((p, i) => <div key={i} style={{ marginBottom: 10 }}>
        <div className="row cfgrow" style={{ marginBottom: 4 }}>
          {p === PYRAMID_MAX
            ? <div className="small"><strong>{t("SET_COUNT" /* 第 {0} 组 */, i + 1)}</strong> · {t("MAX_AS_MANY_REPS_AS_YOU_CAN" /* 力竭：能做多少做多少 */)}</div>
            : <Stepper label={t("SET_COUNT" /* 第 {0} 组 */, i + 1)} value={p} step={perSide ? 2 : 1} min={1} decimal={false} onChange={v => setPyramidAt(i, v)} />}
          <Stepper label={t("REST_S" /* 休息（秒） */)} value={(c.pyramidRest || [])[i] || 0} step={15} decimal={false}
            onChange={v => setC(x => {
              const rest = Array.from({ length: x.pyramid.length }, (_, j) => (x.pyramidRest || [])[j] || 0)
              rest[i] = v
              return { ...x, pyramidRest: rest }
            })} />
        </div>
        {/* Bodyweight work has its one "Added" load below instead. */}
        {!bw && <div className="row cfgrow" style={{ marginBottom: 4 }}>
          <Stepper label={t("WEIGHT_COUNT" /* 重量（{0}） */, st.unit)} value={(c.pyramidWeight || [])[i] || 0} step={2.5}
            onChange={v => setC(x => {
              const weight = Array.from({ length: x.pyramid.length }, (_, j) => (x.pyramidWeight || [])[j] || 0)
              weight[i] = v
              return { ...x, pyramidWeight: weight }
            })} />
        </div>}
        <div className="row" style={{ justifyContent: 'flex-end', gap: 8 }}>
          <Button size="sm" variant={p === PYRAMID_MAX ? 'primary' : 'plain'} aria-pressed={p === PYRAMID_MAX}
            onClick={() => setPyramidAt(i, p === PYRAMID_MAX ? (c.reps || 10) : PYRAMID_MAX)}>{t("MAX" /* 力竭次数 */)}</Button>
          {c.pyramid.length > 1 && <Button size="sm" icon="trash" aria-label={t("REMOVE_SET" /* 减一组 */)} title={t("REMOVE_SET" /* 减一组 */)}
            onClick={() => setC(x => ({ ...x, pyramid: x.pyramid.filter((_, j) => j !== i), pyramidRest: x.pyramidRest?.filter((_, j) => j !== i), pyramidWeight: x.pyramidWeight?.filter((_, j) => j !== i) }))} />}
        </div>
      </div>)}
      <Button size="sm" icon="plus" disabled={c.pyramid.length >= MAX_PYRAMID_SETS}
        onClick={() => setC(x => ({
          ...x,
          pyramid: [...x.pyramid, x.pyramid[x.pyramid.length - 1]],
          // The new set copies the last one's rest too, like its target.
          pyramidRest: x.pyramidRest?.length ? [...x.pyramid.map((_, j) => x.pyramidRest[j] || 0), x.pyramidRest[x.pyramid.length - 1] || 0] : x.pyramidRest,
          pyramidWeight: x.pyramidWeight?.length ? [...x.pyramid.map((_, j) => x.pyramidWeight[j] || 0), x.pyramidWeight[x.pyramid.length - 1] || 0] : x.pyramidWeight,
        }))}>{t("ADD_SET" /* 添加一组 */)}</Button>
      <div className="small dim" style={{ marginTop: 8 }}>{t("A_SET_LEFT_AT_ZERO_REST_USES_THE_EXERCISE_S_REST" /* 休息为 0 的组使用该动作的休息时间。 */)}</div>
      {!bw && <div className="small dim" style={{ marginTop: 4 }}>{t("A_SET_LEFT_AT_ZERO_WEIGHT_STARTS_FROM_THAT_SET_S_WEIGHT" /* 重量为 0 的组从上次同一组的重量开始。 */)}</div>}
    </div>}
    {c.intensifier?.type === 'restpause' && <div className="small dim" style={{ marginTop: -10, marginBottom: 18 }}>
      {t("REST_PAUSE_ALWAYS_TRAINS_AS_ONE_WARM_UP_SET_AT_THIS_REP" /* 休息暂停组 始终按这个次数练一个热身组，再加一个 rest-pause 工作组。这里不使用“组数”。 */)}
    </div>}
    {/* Planned warm-ups: the session used to start at the work weight and you added every
        warm-up by hand, every time. Rest-pause is excluded because it builds its own warm-up
        row, and cardio because an interval plan has no load to ramp. */}
    {!cardio && c.intensifier?.type !== 'restpause' && <>
      <div className="row cfgrow" style={{ marginBottom: 6 }}>
        <Stepper label={t("WARM_UP_SETS" /* 热身组 */)} value={c.warmupSets || 0} step={1} decimal={false}
          onChange={v => setC(x => ({ ...x, warmupSets: Math.max(0, Math.min(MAX_PLANNED_WARMUPS, Math.round(v) || 0)) }))} />
      </div>
      <div className="small dim" style={{ marginBottom: 18 }}>
        {(c.warmupSets || 0) > 0
          ? t("ADDED_BEFORE_YOUR_WORK_SETS_AND_LEFT_OUT_OF_VOLUME_RECORDS_AND" /* 加在工作组之前，不计入容量、纪录和进阶。每一组都把与正式重量的差距缩小一半，杠铃动作不会低于空杠，训练中仍可随时调整任意一组。 */)
          : t("RAMP_UP_SETS_ADDED_BEFORE_THE_WORK_SETS_SO_YOU_DO_NOT" /* 在工作组之前加入的爬升组，这样就不用每次手动添加。 */)}
      </div>
    </>}
    {mode === 'time' && !bw && <div className="small dim" style={{ marginBottom: 18 }}>
      {t("A_TIMER_RUNS_WHILE_YOU_HOLD_THE_SET_LEAVE_THE_WEIGHT_AT" /* 保持这一组时会有计时器运行。徒手静力动作把重量留在 0。 */)}
    </div>}
    {/* Per-exercise rest (issue #10). Its own full-width row, like the other steppers with an
        explanation under them, and outside every mode branch because a heavy triple, a plank
        and a cardio interval all rest — they just do not all want the same break. */}
    {/* On the same wheel as the default rest timer (v1.3.11): 0:00 is "no rest of its own", so
        the default applies, and the row says which default that is. */}
    <div className="sect-b cfg-rest" style={{ marginBottom: 6 }}>
      <Row icon="timer" iconTint="var(--orange)" title={t("REST_FOR_THIS_EXERCISE" /* 本动作的休息 */)} accessory="chevron"
        value={c.restSec > 0 ? fmtRest(c.restSec) : t("DEFAULT_COUNT" /* 默认（{0}） */, fmtRest(st.restSec))}
        onClick={() => durationSheet({
          title: t("REST_FOR_THIS_EXERCISE" /* 本动作的休息 */), value: c.restSec > 0 ? c.restSec : 0, max: REST_MAX,
          off: t("DEFAULT_COUNT" /* 默认（{0}） */, fmtRest(st.restSec)),
          footer: t("REST_AFTER_EACH_SET_OF_THIS_EXERCISE_ZERO_ZEROZERO_MEANS_YOUR_DEFAULT" /* 这个动作每组之后的休息时间。设为 0:00 就用默认休息。 */),
          onDone: v => setC(x => ({ ...x, restSec: v })),
        })} />
    </div>
    <div className="small dim" style={{ marginBottom: 18 }}>
      {t("REST_AFTER_EACH_SET_OF_THIS_EXERCISE_ZERO_ZEROZERO_MEANS_YOUR_DEFAULT" /* 这个动作每组之后的休息时间。设为 0:00 就用默认休息。 */)}
    </div>
    {/* ---------- bodyweight + per side (issues #31/#32/#33) ---------- */}
    {!cardio && <div className="sect-b" style={{ marginBottom: 8 }}>
      <Row icon="figureStrength" iconTint="var(--acc)" title={t("BODYWEIGHT" /* 自重动作 */)}
        subtitle={bw ? (mode === 'time' ? t("NO_WEIGHT_TO_ENTER_JUST_TIME_THE_HOLD" /* 无需填写重量。只需为保持计时。 */) : t("NO_WEIGHT_TO_ENTER_JUST_LOG_THE_REPS" /* 无需输入重量。只记次数就好。 */)) : t("ASK_FOR_A_WEIGHT_ON_EVERY_SET" /* 每组都询问重量。 */)}>
        <Switch checked={bw} onChange={v => setC(x => ({ ...x, bodyweight: v, weight: v ? 0 : x.weight }))} />
      </Row>
      {mode !== 'cardio' && <Row icon="sides" iconTint="var(--blue)" title={t("PER_SIDE" /* 每侧 */)}
        subtitle={mode === 'time'
          ? (perSide
            ? tn("COUNT_SET_BECOMES_COUNT_ONE_ON_EACH_SIDE_COUNT_S_HELD_EVERY" /* {0} 组变为 {1} 组：每侧各一组，每次保持 {2} 秒。 */, "COUNT_SETS_BECOME_COUNT_ONE_ON_EACH_SIDE_COUNT_S_HELD_EVERY" /* {0} 组变为 {1} 组：每侧各一组，每次保持 {2} 秒。 */, c.sets || 0, (c.sets || 0) * 2, c.sec || 0)
            : t("FOR_SIDE_PLANKS_SINGLE_ARM_HOLDS_AND_THE_LIKE_TRAINS_EACH_SIDE" /* 适用于侧平板支撑、单臂悬挂之类的动作。每侧单独训练。 */))
          : (perSide ? t("YOU_STILL_LOG_THE_TOTAL_COUNT_IS_COUNT_PER_SIDE" /* 你记录的仍然是总数：{0} 表示每侧 {1} 次。 */, c.reps || 0, fmtNum(sideReps(c.reps))) : t("FOR_LUNGES_SINGLE_ARM_ROWS_AND_THE_LIKE" /* 用于弓步蹲、单臂划船之类的动作。 */))}>
        {/* Reps: turning it on rounds the target up to an even number, since half of an odd total
            is a rep one side does not get. Time: nothing to round — a hold's whole duration
            happens twice, so only the flag changes (buildWorkSets doubles the planned sets). */}
        <Switch checked={perSide} onChange={v => setC(x => {
          if (mode === 'time') return { ...x, side: v || undefined }
          const next = { ...x, side: v || undefined, reps: v ? Math.ceil((x.reps || 0) / 2) * 2 : x.reps }
          return climbsRange(policyFor({ ...next, id: ex.id }, routine, 'reps'))
            ? { ...next, ...normalizeRepRange(next.reps, next.repsMin, v ? 2 : 1) }
            : next
        })} />
      </Row>}
      {/* Off keeps the list as `pyramidDraft`, so a stray tap does not lose it before Save
          (save writes neither field unless the toggle is on). */}
      {/* The last work set of every session is marked as taken to failure, like Greyskull's
          final AMRAP set (workout-model isFailureSet, history.js applyFailurePlan). A pyramid
          already has its Max set for that. */}
      {!pyramid && <Row icon="gauge" iconTint="var(--purple)" title={t("LAST_SET_TO_FAILURE" /* 最后一组做到力竭 */)}
        subtitle={c.lastToFailure ? t("THE_LAST_SET_GOES_UNTIL_NOTHING_IS_LEFT_AND_COUNTS_AS_ALL" /* 最后一组做到一点不剩，除非你自己打分，否则按全力计算。 */) : t("PLAN_THE_FINAL_SET_AS_AN_ALL_OUT_ONE" /* 把最后一组安排成全力组。 */)}>
        <Switch checked={c.lastToFailure === true} onChange={v => setC(x => ({ ...x, lastToFailure: v || undefined }))} />
      </Row>}
      {mode === 'reps' && <Row icon="steps" iconTint="var(--acc)" title={t("PYRAMID_SETS" /* 金字塔组 */)}
        subtitle={t("A_DIFFERENT_REP_TARGET_FOR_EACH_SET_E_G_ONETWO_EIGHT_SIX" /* 每组设定不同的目标次数，例如 12 · 8 · 6 · 力竭 · 12。 */)}>
        <Switch checked={pyramid} onChange={v => setC(x => (v
          ? { ...x, pyramid: x.pyramidDraft || pyramidFromFlat(x), intensifier: undefined }
          : { ...x, ...flatFromPyramid(x.pyramid), pyramidDraft: x.pyramid, pyramid: undefined }))} />
      </Row>}
    </div>}
    {/* A stepper is too wide to sit in a list row next to a label — it squeezes the text to
        one word per line — so added weight gets the same full-width treatment as sets and
        reps, with its explanation underneath. */}
    {bw && <>
      <div className="row cfgrow" style={{ marginBottom: 8 }}>
        <Stepper label={t("ADDED_COUNT_A" /* 负重（{0}） */, st.unit)} value={c.weight || 0} step={2.5}
          onChange={v => setC(x => ({ ...x, weight: v }))} />
      </div>
      <div className="small dim" style={{ marginBottom: 18 }}>
        {t("FOR_DIPS_OR_PULL_UPS_WITH_A_BELT_PROGRESSION_THEN_FOLLOWS_THE" /* 用于系负重腰带做双杠臂屈伸或引体向上。此时进阶方式跟随重量。 */)}
      </div>
    </>}
    {/* The rep ceiling only means something when there is no load to add instead. */}
    {mode === 'reps' && bw && !(c.weight > 0) && <div className="row cfgrow" style={{ marginBottom: 18 }}>
      <Stepper label={t("TOP_OF_THE_RANGE" /* 次数上限 */)} value={c.repsMax || 0} step={1} decimal={false}
        onChange={v => setC(x => ({ ...x, repsMax: v }))} />
    </div>}
    {mode === 'reps' && bw && !(c.weight > 0) && <div className="small dim" style={{ marginTop: -10, marginBottom: 18 }}>
      {c.repsMax > 0
        ? t("REPS_CLIMB_TO_COUNT_THEN_A_SET_IS_ADDED_AND_THE_REPS" /* 次数升到 {0} 后加一组，次数重新开始。到 {1} 组时会改为提示你加重量。 */, c.repsMax, MAX_BW_SETS)
        : t("REPS_CLIMB_BY_ONE_WHENEVER_EVERY_SET_WAS_CLEAN_SET_A_CEILING" /* 每组都做干净，次数就加一。设置上限后，达到上限会加一组，而不是一直加次数。 */)}
    </div>}
    {/* A pyramid already shapes every set; a drop-set or rest-pause would reshape them again. */}
    {mode === 'reps' && !pyramid && <>
      <h4 className="sec">{t("DROP_SET_REST_PAUSE" /* 递减组 / 休息暂停组 */)}</h4>
      <div className="sect-b" style={{ marginBottom: 8 }}>
        <SelectRow title={t("INTENSIFIER" /* 强化技巧 */)} sheetTitle={t("INTENSIFIER" /* 强化技巧 */)} value={c.intensifier?.type || ''}
          onChange={v => setC(x => ({
            ...x,
            intensifier: !v ? undefined : v === 'dropset'
              ? { type: 'dropset', count: x.intensifier?.count || 1, pct: x.intensifier?.pct || 20 }
              // The activation set's own reps are whatever "Reps" above already says — a
              // rest-pause plan only adds two new numbers: the total extra reps wanted past
              // it, and the rest between the bursts that total gets split into.
              : { type: 'restpause', totalReps: x.intensifier?.totalReps || x.reps || 8, restSec: x.intensifier?.restSec || st.restPauseSec || 15 },
          }))}
          options={[
            { value: '', label: t("NONE" /* 无 */) },
            { value: 'dropset', label: t("DROP_SET" /* 递减组 */) },
            { value: 'restpause', label: t("REST_PAUSE" /* 休息暂停组 */) },
          ]} />
      </div>
      {c.intensifier?.type === 'dropset' && <div className="row cfgrow" style={{ marginBottom: 8 }}>
        <Stepper label={t("DROPS" /* 递减次数 */)} value={c.intensifier.count} step={1} min={1} decimal={false}
          onChange={v => setC(x => ({ ...x, intensifier: { ...x.intensifier, count: v } }))} />
        <Stepper label={t("WEIGHT_DROP" /* 减重幅度（%） */)} value={c.intensifier.pct} step={5} min={5} decimal={false}
          onChange={v => setC(x => ({ ...x, intensifier: { ...x.intensifier, pct: v } }))} />
      </div>}
      {c.intensifier?.type === 'restpause' && <div className="row cfgrow" style={{ marginBottom: 8 }}>
        <Stepper label={t("REST_PAUSE_REPS" /* 休息暂停组总次数 */)} value={c.intensifier.totalReps} step={1} min={1} decimal={false}
          onChange={v => setC(x => ({ ...x, intensifier: { ...x.intensifier, totalReps: v } }))} />
        <Stepper label={t("REST_S" /* 休息（秒） */)} value={c.intensifier.restSec} step={5} min={5} decimal={false}
          onChange={v => setC(x => ({ ...x, intensifier: { ...x.intensifier, restSec: v } }))} />
      </div>}
      {c.intensifier?.type && <div className="small dim" style={{ marginTop: -2, marginBottom: 18 }}>
        {c.intensifier.type === 'dropset'
          ? t("EVERY_SET_BECOMES_A_DROP_SET_AFTER_THE_MAIN_SET_COUNT_DROP" /* 每组都变成递减组：主组之后，无休息完成 {0} 次递减，每次约减轻 {1}%。 */, c.intensifier.count, c.intensifier.pct)
          : t("EVERY_SET_BECOMES_REST_PAUSE_COUNT_REPS_TO_START_THEN_COUNT_MORE" /* 每组都变成休息暂停组：先做 {0} 次，再分成几个短爆发共 {1} 次，每次前休息 {2} 秒，每次数量大约减半。 */, c.reps || 0, c.intensifier.totalReps, c.intensifier.restSec)}
      </div>}
    </>}
    {/* What a dumbbell weight means, for this routine's slot (cfg.dbLoad). Picking what the
        exercise already means drops the key, so the slot follows the exercise's default again. */}
    {isBellEx(ex) && !bw && mode !== 'cardio' && <>
      <h4 className="sec">{t("WEIGHT_MEANS" /* 重量表示 */)}</h4>
      <DbLoadPicker ex={ex} cfg={c} value={dbLoadFor(st, { ...c, id: ex.id })}
        onChange={v => setC(x => ({ ...x, dbLoad: v === dbLoadFor(st, ex.id) ? undefined : v }))} />
    </>}
    {/* How the weight is plate-loaded and what the bar weighs — per exercise, not per plan, so
        it sits apart from the config fields above and writes straight to S.barWeights/S.loadKind. */}
    {mode === 'reps' && <>
      <h4 className="sec">{t("PLATE_LOADING" /* 配重 */)}</h4>
      <BarWeightEditor ex={ex} cfg={c} extra={t("APPLIES_TO_THIS_EXERCISE_EVERYWHERE_NOT_JUST_THIS_PLAN" /* 对这个动作处处生效，不只在此计划中。 */)} />
    </>}
    {pyramid
      ? <div className="small dim" style={{ marginBottom: 18 }}>{t("WEIGHT_IS_UP_TO_YOU_PYRAMID_SETS_ARE_NOT_PROGRESSED_AUTOMATICALLY" /* 重量由你决定：金字塔组不会自动递增。 */)}</div>
      : <ProgressionFields ex={ex} mode={mode} c={c} setC={setC} routine={routine} unit={st.unit} perSide={perSide} bw={bw} />}
    <textarea className="input" rows={3} maxLength={500} style={{ marginBottom: 18 }}
      placeholder={t("NOTE_OPTIONAL_LOADING_CUES_BAR_ONLY_THEN_ONE_PLATE_SIDE_EACH_SET" /* 备注（可选）：加重提示，比如“空杠开始，之后每组每侧 +1 片”，任何值得记住的事 */)}
      value={c.note || ''} onChange={e => setC(x => ({ ...x, note: e.target.value }))} />
    {/* What saving does, when it is neither of the two usual things: the routine editor's
        Replace (#110) seeds this sheet with the slot it replaces, and saving puts the exercise
        into that slot. */}
    <Button variant="primary" disabled={progressionStepInvalid} onClick={save}>{saveLabel || (existing ? t("SAVE" /* 保存 */) : t("ADD_TO_ROUTINE" /* 加入训练计划 */))}</Button>
    {isCustomEx(ex) && <><div style={{ height: 8 }} /><Button icon="pencil" onClick={() => { close(); customExSheet(ex) }}>{t("EDIT_OR_DELETE_THIS_EXERCISE" /* 编辑或删除此动作 */)}</Button></>}
    {/* The routine editor's counterpart to a workout's Swap (#110): another exercise in this
        slot, with the slot's sets, reps, weight, rule and note kept (lib/routines.js). What was
        changed on this sheet and not saved is left behind, as closing it would. */}
    {onReplace && <><div style={{ height: 8 }} /><Button icon="swap" onClick={() => { close(); onReplace() }}>{t("REPLACE_EXERCISE" /* 替换动作 */)}</Button></>}
    {onDelete && <><div style={{ height: 8 }} /><Button variant="danger" onClick={() => { close(); onDelete() }}>{t("REMOVE_FROM_ROUTINE" /* 从计划中移除 */)}</Button></>}
  </>
}
export const exConfigSheet = (ex, existing, onSave, onDelete, routine, initial, onReplace, saveLabel) => ui().openSheet(close => <ExConfig ex={ex} existing={existing} initial={initial} onSave={onSave} onDelete={onDelete} onReplace={onReplace} routine={routine} saveLabel={saveLabel} close={close} />)

/* ============================ glyph picker ============================ */
// Grouped by what the glyph means for a training day, so picking one is a scan
// of four short rows rather than a hunt through twenty loose icons.
export const glyphPicker = (current, onPick) => {
  const cur = glyphOf(current)
  return ui().openSheet(close => <>
    <h3>{t("PICK_AN_ICON" /* 选择图标 */)}</h3>
    {GLYPH_GROUPS.map(g => (
      <div key={g.key} style={{ marginBottom: 14 }}>
        <div className="sect-t" style={{ padding: '0 2px 7px' }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(g.key)}</div>
        <div className="glyph-grid">
          {g.items.map(n => (
            <button key={n} className={'glyph-cell' + (n === cur ? ' on' : '')}
              onClick={() => { close(); onPick(n) }} aria-label={n}>
              <Icon name={n} />
            </button>
          ))}
        </div>
      </div>
    ))}
    <div style={{ height: 4 }} />
  </>)
}

/* ============================ effort quick picker (RIR / RPE) ============================ */
// Rating a set used to mean walking a +/- stepper up the scale — eleven taps to log "5 reps
// left". This is the one-tap replacement: a colour-coded button per preset, plus a free field
// for the value between two presets. Presets are stored in RIR internally; a profile that logs
// RPE sees the same buttons labelled on its own scale (toScale), coloured identically — the
// colour is the effort, not the number, so 0 RIR and 10 RPE are both the "went to failure" end.
function EffortPicker({ kind, value, onPick, close }) {
  // Local mirror so the ticked preset and the exact field track typing live.
  const [v, setV] = useState(value ?? null)
  // The exact field used to write through on every change, and onPick concludes the set (issue
  // #64): it ticks the set, beeps and starts the rest. Since stepEffort(kind, null, 1) returns
  // the band's minimum, one tap of + — or typing the `1` of `10` — was a committed rating, fired
  // under the sheet you were still typing into, and on the last set of the last exercise it
  // stacked workoutCompleteSheet on top of the picker. So typing moves the mirror only, and the
  // rating is written once, when the sheet goes away: Done, the backdrop, a swipe or Escape all
  // unmount this. A preset row still commits on the spot, which is what makes it one tap.
  const typed = useRef(value ?? null)
  const done = useRef(false)
  const set = nv => { typed.current = nv; setV(nv) }
  useEffect(() => () => {
    if (done.current) return
    if (typed.current !== (value ?? null)) onPick(typed.current)
  }, [])
  // `v` is in the profile's own scale (whatever sits on the set: s.rir or s.rpe). Compare in
  // RIR so the tick lands on the right preset on either scale, and so a typed RPE colours the
  // same as the RIR it equals.
  const curRir = rirOf(kind === 'rpe' ? { rpe: v } : { rir: v })
  const curColor = effortColor(curRir)
  const commit = nv => { done.current = true; close(); onPick(nv) }
  const pick = rir => commit(toScale(kind, rir))
  const hd = EFFORT[kind].hd
  // Same list the ⋯ menus use: a tinted square with the value where the icon goes, the sentence
  // as the row title, a tick on the current one. The exact field is the app's own stepper,
  // tinted like the logged cell in the set row, so the sheet and the row read as one thing.
  return <>
    <h3 style={{ marginBottom: 2 }}>{t("HOW_HARD_WAS_THAT_SET" /* 这组有多吃力？ */)}</h3>
    <div className="muted small" style={{ marginBottom: 10 }}>{t("TAP_HOW_MANY_REPS_YOU_HAD_LEFT_OR_TYPE_AN_EXACT_COUNT" /* 点选你还能再做几次，或直接输入准确的 {0}。 */, hd)}</div>
    <div className="list menu-list effpick">
      {EFFORT_PRESETS.map(p => {
        const label = fmtNum(toScale(kind, p.rir)) + (p.tail ? '+' : '')
        const on = curRir != null && curRir === p.rir
        return <div key={p.rir} className={'item menu-item' + (on ? ' on' : '')} style={{ '--bc': p.color }}
          {...tappable(() => pick(p.rir))}>
          <span className="lrow-i effpick-n">{label}</span>
          <div className="grow"><div className="tt">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(p.feel)}</div></div>
          <span className={'menu-on' + (on ? ' is-on' : '')}><Icon name="check" /></span>
        </div>
      })}
      <div className="item menu-item effpick-free">
        <div className="grow"><div className="tt">{t("EXACT_COUNT" /* 准确的 {0} */, hd)}</div></div>
        <div className="stp effcell-stp"
          style={curColor ? { color: curColor, background: `color-mix(in srgb, ${curColor} 20%, var(--surface-2))` } : undefined}>
          <button aria-label={t("DECREASE" /* 减少 */)} onClick={() => set(stepEffort(kind, v, -1))}><Icon name="minus" /></button>
          <span className="val"><NumberField decimal nullable value={v ?? ''} placeholder="–"
            onChange={nv => set(capEffort(kind, nv))} /></span>
          <button aria-label={t("INCREASE" /* 增加 */)} onClick={() => set(stepEffort(kind, v, 1))}><Icon name="plus" /></button>
        </div>
      </div>
    </div>
    {v != null && <>
      <div style={{ height: 10 }} />
      {/* Only after the exact field has moved the value off what is stored: the preset rows
          close themselves, so this row exists for the one path that does not. */}
      {v !== (value ?? null) && <Button icon="check" onClick={() => commit(v)}>{t("DONE" /* 完成 */)}</Button>}
      <Button variant="ghost" className="dim" icon="xmark" onClick={() => commit(null)}>{t("CLEAR_RATING" /* 清除评分 */)}</Button>
    </>}
    <div style={{ height: 4 }} />
  </>
}
// kind is 'rir' | 'rpe'; value is the set's current rating on that scale (or null); onPick
// receives the new value on that same scale (null to clear). The caller stores it exactly as
// weight/reps are stored — a null drops the key rather than writing a zero.
export const effortPickerSheet = (kind, value, onPick) =>
  ui().openSheet(close => <EffortPicker kind={kind} value={value} onPick={onPick} close={close} />)

/* ============================ share / print / import a plan ============================ */
export const planToolsSheet = () => ui().openSheet(close => <PlanTools close={close} />)

// The three things the Plan menu and this sheet both do with a plan, so the two can never drift.
export const planHasRoutines = st => (st.routines || []).some(r => r.ex && r.ex.length)
export async function exportPlanFile() {
  const st = S(), user = useStore.getState().user
  const bundle = buildPlanBundle(st, user?.name ? t("COUNT_S_PLAN" /* {0} 的计划 */, user.name) : '')
  const json = JSON.stringify(bundle, null, 2)
  const name = 'opengym-plan-' + todayISO() + '.json'
  if (MOBILE) { try { await shareExport(json, name) } catch (e) { /* dismissed */ } return }
  const blob = new Blob([json], { type: 'application/json' })
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); URL.revokeObjectURL(a.href)
  toast(t("PLAN_FILE_SAVED_SEND_IT_TO_A_FRIEND" /* 计划文件已保存。发给朋友吧！ */))
}
// Web: the browser's print dialog (→ Save as PDF). Mobile: the OS print flow via the native
// Print plugin — Android WebView has no window.print(). Same printable HTML both ways.
export function printWholePlan() {
  const st = S(), owner = useStore.getState().user?.name || ''
  if (MOBILE) printHtml(planPrintHTML(st, owner), t("WEEKLY_TRAINING_PLAN" /* 每周训练计划 */)).catch(() => { /* dismissed */ })
  else printPlan(st, owner)
}
// A picked plan file → the import sheet, or a toast saying why not.
export function importPlanFile(f, onRead) {
  if (!f) return
  const rd = new FileReader()
  rd.onload = () => {
    try { const bundle = parsePlan(rd.result, S().unit || 'kg'); onRead?.(); planImportSheet(bundle) }
    // parsePlan's own refusal is written for people; anything else is not shown raw.
    catch (e) { toast(e?.code === 'not-plan' ? t("IMPORT_FAILED_COUNT" /* 导入失败：{0} */, e.message) : t("COULDN_T_READ_THAT_FILE" /* 无法读取这个文件。 */)) }
  }
  rd.readAsText(f)
}

function PlanTools({ close }) {
  const st = useStore(s => s.S)
  const fileRef = useRef(null)
  const hasRoutines = planHasRoutines(st)

  const exportFile = async () => { await exportPlanFile(); close() }
  const pickFile = ev => {
    const f = ev.target.files[0]; ev.target.value = ''
    importPlanFile(f, close)
  }

  return <>
    <h3>{t("SHARE_YOUR_PLAN" /* 分享你的计划 */)}</h3>
    <div className="muted small" style={{ marginBottom: 16 }}>{t("SEND_YOUR_ROUTINES_TO_A_FRIEND_OR_PUT_YOUR_WEEK_ON_PAPER" /* 把你的训练计划发给朋友，或把这一周打印到纸上。 */)}</div>
    <Button variant="primary" icon="share" onClick={exportFile} disabled={!hasRoutines}>{t("EXPORT_PLAN_FILE" /* 导出计划文件 */)}</Button>
    <div className="dim small" style={{ margin: '7px 2px 0', lineHeight: 1.4 }}>{t("A_SMALL_FILE_A_FRIEND_CAN_IMPORT_INTO_THEIR_OWN_OPENGYM_ROUTINES" /* 一个小文件，朋友可以导入到自己的 openGym。只有训练计划，不含你的训练记录和体重。 */)}</div>
    <div style={{ height: 12 }} />
    <Button variant="tinted" icon="note" onClick={() => { close(); printWholePlan() }} disabled={!hasRoutines}>{t("PRINT_SAVE_AS_PDF" /* 打印 / 保存为 PDF */)}</Button>
    <div className="dim small" style={{ margin: '7px 2px 0', lineHeight: 1.4 }}>{t("A_CLEAN_PRINTOUT_ONE_PAGE_PER_PLAN_NO_EXERCISE_EVER_GETS_SPLIT" /* 干净的打印版，每个计划一页。动作绝不会被拆到两页。 */)}</div>
    {!hasRoutines && <div className="dim small" style={{ margin: '12px 2px 0' }}>{t("ADD_AN_EXERCISE_TO_A_ROUTINE_FIRST_AN_EMPTY_PLAN_HAS_NOTHING" /* 请先给训练计划添加动作。空计划没什么可分享的。 */)}</div>}
    <h4 className="sec">{t("GOT_A_PLAN_FROM_A_FRIEND" /* 收到朋友的计划了吗？ */)}</h4>
    <Button variant="ghost" icon="download" onClick={() => fileRef.current?.click()}>{t("IMPORT_A_PLAN_FILE" /* 导入计划文件 */)}</Button>
    <input ref={fileRef} type="file" accept="application/json,.json" onChange={pickFile} hidden />
  </>
}

export const planImportSheet = bundle => ui().openSheet(close => <PlanImport bundle={bundle} close={close} />)

function PlanImport({ bundle, close }) {
  const [schedule, setSchedule] = useState(false)
  const apply = () => {
    update(s => mergePlan(s, bundle, { schedule }))
    close()
    toast(tn("ADDED_COUNT_ROUTINE_TO_YOUR_PLAN" /* 已向你的计划添加 {0} 个训练计划 */, "ADDED_COUNT_ROUTINES_TO_YOUR_PLAN" /* 已向你的计划添加 {0} 个训练计划 */, bundle.routineCount))
    nav('/plan')
  }
  return <>
    <h3>{bundle.name ? t("IMPORT_COUNT" /* 导入“{0}” */, bundle.name) : t("IMPORT_THIS_PLAN" /* 导入此计划 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {routineCount(bundle.routineCount)}
      {' · ' + exCount(bundle.exerciseCount)}
      {bundle.scheduledDays > 0
        ? ' · ' + tn("SCHEDULED_ON_COUNT_DAY" /* 已安排在 {0} 天 */, "SCHEDULED_ON_COUNT_DAYS" /* 已安排在 {0} 天 */, bundle.scheduledDays)
        : ''}
    </div>
    <div className="dim small" style={{ marginBottom: 14, lineHeight: 1.4 }}>{t("THESE_ARE_ADDED_AS_NEW_ROUTINES_NOTHING_YOU_ALREADY_HAVE_IS_TOUCHED" /* 它们会作为新的训练计划添加。你已有的内容一点都不会动。 */)}</div>
    {bundle.dropped > 0 && <div className="small" style={{ color: 'var(--yellow)', marginBottom: 14, lineHeight: 1.4 }}>
      {t(bundle.dropped === 1
        ? "COUNT_EXERCISE_IN_THE_FILE_ISN_T_IN_YOUR_LIBRARY_AND_WAS" /* 文件中有 {0} 个动作不在你的动作库中，已略过。 */
        : "COUNT_EXERCISES_IN_THE_FILE_AREN_T_IN_YOUR_LIBRARY_AND_WERE" /* 文件中有 {0} 个动作不在你的动作库中，已略过。 */, bundle.dropped)}
    </div>}
    {bundle.scheduledDays > 0 && <div className="row between" style={{ padding: '10px 2px', borderTop: '1px solid var(--sep)', borderBottom: '1px solid var(--sep)', marginBottom: 16, gap: 12 }}>
      <div><div className="tt" style={{ fontSize: 15 }}>{t("USE_THIS_WEEKLY_SCHEDULE" /* 使用此每周日程 */)}</div><div className="small dim">{t("REPLACES_YOUR_CURRENT_MON_SUN_ASSIGNMENTS" /* 替换你当前的周一至周日安排。 */)}</div></div>
      <Switch checked={schedule} onChange={setSchedule} />
    </div>}
    <Button variant="primary" onClick={apply}>{t("ADD_TO_MY_PLAN" /* 加入我的计划 */)}</Button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </>
}

/* ============================ day override / assign ============================ */
function DayOverride({ iso, close }) {
  const st = useStore(s => s.S)
  const hasOvr = st.dayPlan[iso] !== undefined
  // A fulfilled pin (a coach session pinned here and since done) reads as no override, as it does
  // everywhere else — the row to clear the leftover entry stays.
  const changed = hasOvr && pinState(st, st.dayPlan[iso]) !== 'done'
  // The plan the day would have without its override — the weekday's routines, and in a coach
  // week the queue's session for the day in front of them, same as the Home row shows.
  const { [iso]: _ovr, ...noOvr } = st.dayPlan
  const weeklyNames = effectiveRoutineIds({ ...st, dayPlan: noOvr }, iso).map(id => st.routines.find(r => r.id === id)?.name).filter(Boolean)
  // A weekday can hold several routines; the per-date override stays single-pick, so picking
  // one here collapses a combined day to it (docs/dev/COMBINE_ROUTINES.md §8). The check marks
  // show everything currently planned for the day.
  const effIds = effectiveRoutineIds(st, iso)
  // A planned day in the past with nothing logged was missed — or trained and never logged,
  // like a run you forgot to start the app for (#284). Logging it opens "Log a past workout" on
  // that date with the day's routines picked, where the time and the duration can still change.
  const missed = iso < todayISO() && effIds.length > 0 && !workoutsOn(st, iso).length
  const logIt = () => { close(); logPastWorkoutSheet({ iso, routineIds: effIds }) }
  // A note on a day off (#261, lib/day-notes.js): offered on today and past days with nothing
  // logged, kept in view on any day that already has one. Quiet on purpose: a row, not a button.
  const note = dayNoteOf(st, iso)
  const canNote = !!note || (canNoteDay(iso) && !workoutsOn(st, iso).length)
  // The coach week's sessions still to do come first, in slot order: picking one here pins it
  // to this day — the same per-date override, read back by queueNext (lib/queue.js). A session
  // already pinned to another day says so in place of its exercise count. Done sessions and
  // your own routines follow in the plain list.
  const remaining = queueRemaining(st)
  // Your own rotation's pass (its rotationId matches the saved rotation) is your loop, not a coach's week.
  const ownLoop = !!st.queue && !!st.rotation && st.queue.rotationId === st.rotation.id
  const coach = remaining.map(id => st.routines.find(r => r.id === id)).filter(Boolean)
  // Active pins straight from the plan (earliest day per session, today or later) — not the
  // row's 'pinned' items, which leave out the session pinned to today itself.
  const pinnedOn = Object.entries(st.dayPlan).filter(([d, id]) => d >= todayISO() && remaining.includes(id)).sort()
    .reduce((m, [d, id]) => (m[id] ? m : { ...m, [id]: d }), {})
  const set = v => {
    update(s => { if (!v) delete s.dayPlan[iso]; else s.dayPlan[iso] = v })
    close()
    toast(v === '' ? t("BACK_TO_WEEKLY_PLAN" /* 恢复每周计划 */) : v === 'rest' ? t("COUNT_SET_TO_REST" /* {0} 已设为休息 */, fmtDate(iso)) : t("COUNT_PLANNED_FOR_COUNT" /* {0} 已安排在 {1} */, (st.routines.find(r => r.id === v) || {}).name, fmtDate(iso)))
  }
  const row = r => <div key={r.id} className="item" {...tappable(() => set(r.id))}>
    <span className="lrow-i"><Icon name={glyphOf(r.emoji)} /></span>
    <div className="grow"><div className="tt">{r.name}</div><div className="ss">{pinnedOn[r.id] && pinnedOn[r.id] !== iso ? fmtDate(pinnedOn[r.id], true) : exCount(r.ex.length)}</div></div>
    {effIds.includes(r.id) && <Icon name="check" className="accent" />}</div>
  return <>
    <h3>{fmtDate(iso, true)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("WEEKLY_PLAN" /* 每周计划： */)} {weeklyNames.length ? deriveSessionName(weeklyNames) : t("REST" /* 休息 */)}{changed && <span style={{ color: 'var(--orange)' }}> · {t("CHANGED_FOR_THIS_DAY" /* 此日已更改 */)}</span>}<br />{t("SICK_MISSED_A_DAY_OR_WANT_A_DIFFERENT_SESSION_PICK_WHAT_TO" /* 生病、错过一天或想换个训练？选择改练什么。 */)}</div>
    {missed && <div style={{ marginBottom: 14 }}><Button variant="primary" icon="checkCircle" onClick={logIt}>{t("LOG_THIS_WORKOUT" /* 补记这次训练 */)}</Button></div>}
    {canNote && <div className="day-note" style={{ marginBottom: 14 }}>
      <div className="item day-note-row" {...tappable(() => dayNoteSheet(iso))}>
        <span className="lrow-i" style={{ background: 'var(--surface-3)' }}><Icon name={note?.tag ? DAY_NOTE_ICON[note.tag] : 'note'} /></span>
        <div className="grow">{note
          ? <><div className="tt">{note.tag ? translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAY_NOTE_LABEL[note.tag]) : t("DAY_NOTE" /* 当日备注 */)}</div>{note.text && <div className="ss" style={{ whiteSpace: 'pre-wrap' }}>{note.text}</div>}</>
          : <div className="tt">{t("ADD_A_NOTE_FOR_THIS_DAY" /* 为这一天添加备注 */)}</div>}</div>
        <Icon name={note ? 'pencil' : 'plus'} className="chev" />
      </div>
    </div>}
    {coach.length > 0 && <>
      <h4 className="sec" style={{ marginTop: 0 }}>{ownLoop ? t("YOUR_LOOP" /* 你的循环 */) : t("COACH_WEEK" /* 教练周 */)}</h4>
      <div className="list" style={{ marginBottom: 8 }}>{coach.map(row)}</div>
    </>}
    <div className="list">
      {st.routines.filter(r => !remaining.includes(r.id)).map(row)}
      <div className="item" {...tappable(() => set('rest'))}><span className="lrow-i" style={{ background: 'var(--surface-3)' }}><Icon name="moon" /></span><div className="grow"><div className="tt">{t("REST_SKIP_THIS_DAY" /* 休息 / 跳过这天 */)}</div></div>{effIds.length === 0 && <Icon name="check" className="accent" />}</div>
      {hasOvr && <div className="item" {...tappable(() => set(''))}><span className="lrow-i" style={{ background: 'var(--surface-3)' }}><Icon name="reset" /></span><div className="grow"><div className="tt">{t("BACK_TO_WEEKLY_PLAN" /* 恢复每周计划 */)}</div></div></div>}
    </div>
  </>
}
export const dayOverrideSheet = iso => ui().openSheet(close => <DayOverride iso={iso} close={close} />)

// Why a day went without training (#261): one quick pick, a line of text, or both. Saving an
// empty note takes it away (a stamped clear, lib/day-notes.js withDayNote), and so does Remove.
function DayNote({ iso, close }) {
  const noteRef = useRef(null)
  const onNoteFocus = useSheetKeyboard(noteRef)
  const st = useStore(s => s.S)
  const had = dayNoteOf(st, iso)
  const [tag, setTag] = useState(had?.tag || null)
  const [text, setText] = useState(had?.text || '')
  const write = v => {
    update(s => { s.dayNotes = withDayNote(s.dayNotes, iso, v) })
    close()
  }
  const save = () => {
    const clean = text.trim().slice(0, NOTE_MAX)
    if (!tag && !clean && !had) { close(); return }
    write({ tag, text: clean })
    toast(tag || clean ? t("NOTED_SEE_YOU_NEXT_SESSION" /* 记下了，下次训练见！ */) : t("NOTE_REMOVED" /* 备注已删除 */))
  }
  const remove = () => { write(null); toast(t("NOTE_REMOVED" /* 备注已删除 */)) }
  return <>
    <h3>{fmtDate(iso, true)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("LIFE_HAPPENS_LEAVE_YOURSELF_A_NOTE_AND_THE_MISSED_DAY_NUDGE_LETS" /* 生活总有意外。给自己留个备注，错过训练的提醒就会放过这一天。 */)}</div>
    <div className="chips" style={{ margin: '0 0 12px' }}>
      {DAY_NOTE_TAGS.map(k => <button key={k} className={'chip nocap' + (tag === k ? ' on' : '')} aria-pressed={tag === k}
        onClick={() => setTag(tag === k ? null : k)}><Icon name={DAY_NOTE_ICON[k]} /> {translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAY_NOTE_LABEL[k])}</button>)}
    </div>
    <textarea ref={noteRef} className="input" rows={3} maxLength={NOTE_MAX} value={text}
      placeholder={t("ANYTHING_ELSE_OPTIONAL" /* 还有别的吗？（可选） */)}
      onFocus={onNoteFocus} onChange={e => setText(e.target.value)} />
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
    {had && <><div style={{ height: 10 }} /><Button variant="ghost" icon="trash" onClick={remove}>{t("REMOVE_NOTE" /* 删除备注 */)}</Button></>}
  </>
}
export const dayNoteSheet = iso => ui().openSheet(close => <DayNote iso={iso} close={close} />)

// Plan → Schedule → a weekday. One sheet for the whole day: tap routines to put them on it or
// take them off (two or more make a combined day, docs/dev/COMBINE_ROUTINES.md), in the order
// tapped, which is the order the session runs them; "Rest day" clears it. The sheet stays open
// for a second pick, so "Done" closes it. The weekday never stores [] (the key goes instead).
function DayAssign({ day, close }) {
  const st = useStore(s => s.S)
  const cur = [].concat(st.week[day] || [])
  const toggle = id => update(s => {
    const ids = [].concat(s.week[day] || [])
    const next = ids.includes(id) ? ids.filter(x => x !== id) : [...ids, id]
    if (next.length) s.week[day] = next; else delete s.week[day]
  })
  const rest = () => { update(s => { delete s.week[day] }); close() }
  return <>
    <h3 style={{ marginBottom: 2 }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYN[day])}</h3>
    <div className="muted small" style={{ marginBottom: 10 }}>{t("PICK_ONE_ROUTINE_OR_MORE_TO_TRAIN_THEM_TOGETHER" /* 选一个训练计划，或选多个一起练。 */)}</div>
    <div className="list menu-list">
      <div className="item menu-item" {...tappable(rest)}><span className="lrow-i" style={{ background: 'var(--surface-3)' }}><Icon name="moon" /></span><div className="grow"><div className="tt">{t("REST_DAY" /* 休息日 */)}</div></div><span className={'menu-on' + (!cur.length ? ' is-on' : '')}><Icon name="check" /></span></div>
      {st.routines.map(r => {
        const on = cur.includes(r.id)
        return <div key={r.id} className="item menu-item" aria-pressed={on} {...tappable(() => toggle(r.id))}>
          <span className="lrow-i"><Icon name={glyphOf(r.emoji)} /></span>
          <div className="grow"><div className="tt">{r.name}</div><div className="ss">{exCount(r.ex.length)}</div></div>
          <span className={'menu-on' + (on ? ' is-on' : '')}><Icon name="check" /></span>
        </div>
      })}
    </div>
    <div style={{ height: 12 }} />
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}
export const dayAssignSheet = day => ui().openSheet(close => <DayAssign day={day} close={close} />)

/* ============================ workout detail ============================ */
// Correcting when a saved session happened: typed in from another app, or logged on the wrong
// day. Only its place in history moves — the sets, the volume and the notes are the record, and
// the session keeps the length it had. The PR badges of the exercises it trained are worked out
// again, because "this was a record" is a claim about the sessions before it.
function WorkoutDateEdit({ w, onDone, close }) {
  const [date, setDate] = useState(w.d)
  const [time, setTime] = useState(startTimeOf(w))
  const today = todayISO()
  const save = () => {
    if (!date || date > today) { toast(t("PICK_A_DAY_UP_TO_TODAY" /* 请选择今天或之前的日期 */)); return }
    // Nothing to do, and nothing to push: a no-op save and a workout deleted from another
    // sheet both just close.
    if (date === w.d && time === startTimeOf(w)) { close(); return }
    if (!(S().workouts || []).some(x => sameWorkout(x, w))) { close(); return }
    // It keeps its length, so the end it would have is what has to be in the past.
    if (endsInFuture(date, time, durationMinOf(w))) { toast(t("THAT_S_STILL_IN_THE_FUTURE_TRY_AN_EARLIER_START" /* 这还在未来。试试更早的开始时间。 */)); return }
    update(s => {
      const next = moveWorkout(s.workouts, w, date, time)
      if (next) s.workouts = next
    })
    close()
    onDone && onDone()
    toast(t("WORKOUT_MOVED" /* 训练已移动 */))
  }
  return <>
    <h3>{t("CHANGE_DATE_TIME" /* 修改日期和时间 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("THE_SESSION_KEEPS_ITS_LENGTH_PERSONAL_RECORDS_ARE_WORKED_OUT_AGAIN_FROM" /* 训练时长保持不变。个人记录会按新的顺序重新计算。 */)}</div>
    <Row icon="calendar" title={t("DATE" /* 日期 */)}>
      <input type="date" className="timef" value={date} max={today} onChange={e => setDate(e.target.value)} /></Row>
    <Row icon="clock" title={t("START_TIME" /* 开始时间 */)}>
      <input type="time" className="timef" value={time} onChange={e => setTime(e.target.value)} /></Row>
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const workoutDateSheet = (w, onDone) => ui().openSheet(close => <WorkoutDateEdit w={w} onDone={onDone} close={close} />)

// Correcting how long a saved session ran — mostly the workout nobody ended until they got home
// (Discord). The start stays, the end follows it; the sets, the order of history and the badges
// do not depend on the length and are left alone.
function WorkoutDurationEdit({ w, onDone, close }) {
  const [dur, setDur] = useState(durationMinOf(w))
  // A cleared field reads as 0, and saving that made the session one minute long without a word
  // (QA 1.3.9): it is refused with the reason under the field, and the saved length stays.
  const durInvalid = !(dur >= 1)
  const durTooLong = dur > MAX_DURATION_MIN
  const save = () => {
    if (durInvalid) { toast(t("ENTER_HOW_LONG_IT_TOOK_AT_LEAST_ONE_MINUTE" /* 请输入用时（至少 1 分钟）。 */)); return }
    if (durTooLong) { toast(t("THAT_S_MORE_THAN_A_DAY_KEEP_IT_TO_TWOFOUR_HOURS_OR" /* 超过一天了。最多 24 小时。 */)); return }
    let changed = false
    update(s => {
      const next = setWorkoutDuration(s.workouts, w, dur)   // at least a minute, however the field was left
      if (next) { s.workouts = next; changed = true }
    })
    close()
    if (!changed) return
    onDone && onDone()
    toast(t("DURATION_CHANGED" /* 时长已修改 */))
  }
  return <>
    <h3>{t("CHANGE_DURATION" /* 修改时长 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("FORGOT_TO_FINISH_ON_TIME_SET_HOW_LONG_THE_SESSION_REALLY_TOOK" /* 忘了及时结束？设置本次训练的实际时长。开始时间和组数保持不变。 */)}</div>
    {/* min 0, not 1: the stepper would put a cleared field back to 1 as it lost focus to Save. */}
    {/* No max either: one would cut a typo down to a day on blur and save that without a word. */}
    <Stepper label={t("DURATION" /* 时长 */)} unit={t("MIN" /* 分钟 */)} value={dur} step={5} min={0} decimal={false} invalid={durInvalid || durTooLong} onChange={v => setDur(Math.round(v))} />
    {durInvalid && <div className="small" style={{ color: 'var(--red)', marginTop: 6 }}>{t("ENTER_HOW_LONG_IT_TOOK_AT_LEAST_ONE_MINUTE" /* 请输入用时（至少 1 分钟）。 */)}</div>}
    {durTooLong && <div className="small" style={{ color: 'var(--red)', marginTop: 6 }}>{t("THAT_S_MORE_THAN_A_DAY_KEEP_IT_TO_TWOFOUR_HOURS_OR" /* 超过一天了。最多 24 小时。 */)}</div>}
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const workoutDurationSheet = (w, onDone) => ui().openSheet(close => <WorkoutDurationEdit w={w} onDone={onDone} close={close} />)

function WorkoutDetail({ w, close }) {
  const noteRef = useRef(null)
  const onNoteFocus = useSheetKeyboard(noteRef)
  const st = useStore(s => s.S)
  const update = useStore(s => s.update)
  // The session note is editable here rather than only at the finish sheet: what you want to
  // record about a session is often clearer once you have looked at what you actually did.
  const [note, setNote] = useState(w.note || '')
  // A note written here is an edit of the saved workout, stamped for the sync to keep it over an
  // older copy of the same workout (stampWorkout) — and only when it changed, since a stamp
  // outranks what another device wrote since.
  const saveNote = () => update(s => {
    const rec = s.workouts.find(x => sameWorkout(x, w))
    if (!rec) return
    const text = note.trim().slice(0, SESSION_NOTE_MAX)
    if (text === (rec.note || '')) return
    if (text) rec.note = text; else delete rec.note
    stampWorkout(rec)
  })
  // onBlur alone loses the note: Escape, the Android back gesture and swipe-to-dismiss all
  // close the sheet without ever moving focus out of the textarea. Flush on unmount too. The
  // ref is what makes that work — a cleanup closes over the note from its own render, which
  // is the empty string this started with.
  const latest = useRef(note)
  latest.current = note
  const initial = useRef(w.note || '')
  useEffect(() => () => {
    const text = latest.current.trim().slice(0, SESSION_NOTE_MAX)
    if (text === initial.current) return
    update(s => {
      const rec = s.workouts.find(x => sameWorkout(x, w))
      if (!rec || text === (rec.note || '')) return   // deleted from this very sheet, or already saved
      if (text) rec.note = text; else delete rec.note
      stampWorkout(rec)
    })
  }, [])
  const nameOf = e => (EXIDX[e.id] ? exerciseNameFor(EXIDX[e.id]) : (e.n || e.id))
  // Tapping an exercise opens its history (Discord 'Improvement ideas'): from one session to the
  // curve it sits on, which is the question a past workout raises most often.
  const entryRow = (e, i) => {
    const ex = EXIDX[e.id]
    return <div key={i} className="row wd-ex" style={{ alignItems: 'flex-start' }} {...tappable(() => exerciseHistorySheet(e.id))}>
      {ex && <Thumb ex={ex} />}
      <div className="grow"><div className={`tt ${exerciseNameClass(ex)}`} style={{ fontWeight: 600 }}>{nameOf(e)} {w.prs && w.prs.includes(e.id) && <span className="pr"><Icon name="trophy" />PR</span>}</div>
        <div className="ss">{e.sets.filter(hasCompletedWork).map(s => setLabel(e.id, s, e.target, speedUnitOf(st))).join('  ·  ') || t("NO_SETS" /* 无组数 */)}</div>
        {e.note && <div className="small dim" style={{ marginTop: 3, whiteSpace: 'pre-wrap' }}>
          {e.notePin && <Icon name="pin" style={{ fontSize: 12, marginInlineEnd: 4, verticalAlign: '-1px', color: 'var(--yellow)' }} />}{e.note}
        </div>}</div>
      <Icon name="chevronRight" className="chev" style={{ alignSelf: 'center' }} />
    </div>
  }
  // Exercises done as a superset stay together under a "Superset" label and one bar, the way the
  // routine editor shows them (Discord: "supersets aren't shown at all"). Adjacent entries with
  // the same tag, as in the workout itself; a workout finished before the tag was kept has none.
  const entryRows = units => units.map(unit => {
    if (unit.length < 2) return entryRow(w.entries[unit[0]], unit[0])
    return <div key={'ss' + unit[0]} className="wd-ss">
      <div className="ss-label"><Icon name="link" />{t("SUPERSET" /* 超级组 */)}</div>
      {unit.map(i => entryRow(w.entries[i], i))}
    </div>
  })
  // Copied with the note as it stands in the box, which may not be saved yet.
  const copyAsText = async () => {
    const rec = { ...(st.workouts.find(x => sameWorkout(x, w)) || w), note: note.trim() }
    toast(await copyText(workoutText(rec, { unit: st.unit, nameOf, speedUnit: speedUnitOf(st) })) ? t("COPIED" /* 已复制 */) : t("COULD_NOT_COPY" /* 无法复制 */))
  }
  // A Garmin .fit activity (#447) of the saved record, for Garmin Connect's Import Data.
  const exportFit = () => {
    const rec = st.workouts.find(x => sameWorkout(x, w)) || w
    let bytes
    try { bytes = workoutFit(rec, { unit: st.unit, version: __APP_VERSION__ }) }
    catch (e) { toast(t("COULD_NOT_CREATE_THE_FILE" /* 无法创建文件 */)); return }
    saveFitFile(new Blob([bytes], { type: 'application/vnd.ant.fit' }), fitFileName(rec))
  }
  const shareAsImage = () => {
    const rec = st.workouts.find(x => sameWorkout(x, w)) || w
    ui().openSheet(c2 => <ShareWorkoutImage w={rec} nameOf={nameOf} close={c2} />)
  }
  // A combined session's entries carry a `rid`; group them into per-routine sections in merge
  // order, with each section's supersets paired inside it (sessionSections, which "Copy as text"
  // reads the workout through too). A legacy single-routine workout (one routineIds, or no rid
  // anywhere) renders flat.
  const groups = sessionSections(w.entries)
  const grouped = groups.length > 1 || (groups[0] && groups[0].rid && (w.routineIds || []).length > 1)
  return <>
    <h3>{w.name}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{[fmtDate(w.d, true), ...durPart(w.end - w.start), fmtVol(w.vol, st.unit), ...(w.bw ? [fmtNum(w.bw) + ' ' + st.unit] : [])].join(' · ')}</div>
    {grouped ? groups.map(g => {
      const r = g.rid ? st.routines.find(x => x.id === g.rid) : null
      const items = g.items.map(i => w.entries[i])
      const setN = items.reduce((n, e) => n + e.sets.filter(s => s.done && !isWarmupRow(s)).length, 0)
      const vol = workoutVolume({ entries: items })
      return <div key={g.rid || '__none'}>
        <div className="row between" style={{ margin: '2px 0 8px', paddingBottom: 6, borderBottom: '1px solid var(--sep)' }}>
          <div className="row" style={{ gap: 7, fontWeight: 600 }}>
            {r && <Icon name={glyphOf(r.emoji)} />}{r ? r.name : t("FREESTYLE" /* 自由训练 */)}
          </div>
          <div className="small dim">{t("COUNT_SETS" /* {0} 组 */, setN)} · {fmtVol(vol, st.unit)}</div>
        </div>
        {entryRows(g.units)}
      </div>
    }) : entryRows(groups[0]?.units || [])}
    {/* Progress photos and form-check videos: added and removed right here, on the saved record. */}
    <WorkoutMediaSection w={w} />
    <div className="small muted" style={{ margin: '4px 0 6px' }}>{t("SESSION_NOTE" /* 训练备注 */)}</div>
    <textarea ref={noteRef} className="input" rows={Math.min(16, Math.max(2, note.split('\n').length))} maxLength={SESSION_NOTE_MAX} value={note}
      placeholder={t("HOW_THE_SESSION_WENT_AS_A_WHOLE" /* 这次训练整体感觉如何。 */)}
      onFocus={onNoteFocus} onChange={e => setNote(e.target.value)} onBlur={saveNote} />
    <div style={{ height: 14 }} />
    {st.active && <p className="small muted">{t("FINISH_YOUR_CURRENT_WORKOUT_FIRST" /* 请先完成当前训练 */)}</p>}
    {/* The editor starts from the record as it is, so a note typed here goes in first — the same
        flush the date row does, and the unmount hook then has nothing left to write over it. */}
    <Button icon="pencil" disabled={!!st.active} onClick={() => {
      saveNote()
      initial.current = latest.current.trim().slice(0, SESSION_NOTE_MAX)
      try { update(state => { editCompletedSession(state, w) }); closeThenNav(close, '/workout') }
      catch (error) { toast(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(error.message)) }
    }}>{t("EDIT_WORKOUT" /* 编辑训练 */)}</Button>
    <div style={{ height: 8 }} />
    {/* The same exercises again, today, as a new session (#58): the rows read what was logged
        in this workout. The record itself stays as it is. */}
    <Button icon="reset" disabled={!!st.active} style={{ marginBottom: 8 }} onClick={() => {
      saveNote()
      initial.current = latest.current.trim().slice(0, SESSION_NOTE_MAX)
      repeatWorkout(w, close)
    }}>{t("REPEAT_TODAY" /* 今天再练一次 */)}</Button>
    {/* The note lives in a textarea that only writes on blur, and moving the workout re-keys a
        legacy record — so flush it first and stop the unmount hook writing it a second time. */}
    <Button icon="calendar" style={{ marginBottom: 8 }} onClick={() => {
      saveNote()
      initial.current = latest.current.trim().slice(0, SESSION_NOTE_MAX)
      workoutDateSheet(w, close)
    }}>{t("CHANGE_DATE_TIME" /* 修改日期和时间 */)}</Button>
    <Button icon="stopwatch" style={{ marginBottom: 8 }} onClick={() => {
      saveNote()
      initial.current = latest.current.trim().slice(0, SESSION_NOTE_MAX)
      workoutDurationSheet(w, close)
    }}>{t("CHANGE_DURATION" /* 修改时长 */)}</Button>
    <Button icon="plus" onClick={() => confirmSheet({
      title: t("SAVE_AS_ROUTINE" /* 要保存为训练计划吗？ */),
      message: t("CREATE_AN_INDEPENDENT_ROUTINE_FROM_THESE_EXERCISE_TARGETS_YOUR_WORKOUT_HISTORY_IS" /* 根据这些训练目标创建独立训练计划。你的训练记录会保留。 */),
      confirmText: t("SAVE" /* 保存 */),
      onConfirm: () => {
        let id
        try { update(s => { id = saveSessionAsRoutine(s, w, w.name) }) }
        catch (e) { toast(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(e.message)); return }
        close()
        nav('/plan/r/' + id)
      }
    })}>{t("SAVE_AS_ROUTINE_A" /* 保存为训练计划 */)}</Button>
    <div style={{ height: 8 }} />
    <Button icon="copy" onClick={copyAsText}>{t("COPY_AS_TEXT" /* 复制为文本 */)}</Button>
    <div style={{ height: 8 }} />
    <Button icon="share" onClick={shareAsImage}>{t("SHARE_AS_IMAGE" /* 分享为图片 */)}</Button>
    <div style={{ height: 8 }} />
    <Button icon="download" onClick={exportFit}>{t("EXPORT_AS_FIT_FILE" /* 导出为 .fit 文件 */)}</Button>
    <div style={{ height: 10 }} />
    {/* Matched the way the edits above are, not by id: a workout from before ids has none, and
        filtering on `x.id !== undefined` took every other one of them with it. */}
    <Button variant="danger" onClick={() => confirmSheet({ title: t("DELETE_WORKOUT" /* 删除训练？ */), message: t("THIS_REMOVES_IT_FROM_YOUR_HISTORY_FOR_GOOD" /* 它将从历史中永久删除。 */) + mediaGoesToo(S().workouts.find(x => sameWorkout(x, w))), confirmText: t("DELETE" /* 删除 */), danger: true, onConfirm: () => { update(s => { s.workouts = s.workouts.filter(x => !sameWorkout(x, w)) }); close(); toast(t("WORKOUT_DELETED" /* 训练已删除 */)) } })}>{t("DELETE_WORKOUT_A" /* 删除训练 */)}</Button>
  </>
}
// "Share as image" (#453): the card lib/workout-card.js lays out, painted in the theme and accent
// the app is showing right now, previewed before it goes anywhere. The muscle map is the finish
// summary's, for this one session; whether the card carries it is remembered with the profile.
function ShareWorkoutImage({ w, nameOf, close }) {
  const st = useStore(s => s.S)
  const update = useStore(s => s.update)
  const withMap = st.shareMap !== false
  const model = useMemo(() => workoutCardModel(w, { unit: st.unit, nameOf }), [w, st.unit])
  // The last picture stays up while the next one is drawn, so the toggle never blanks the sheet.
  const [img, setImg] = useState(null)
  const [busy, setBusy] = useState(false)
  const shown = useRef(null)
  useEffect(() => {
    let alive = true
    workoutCardImage(model, { map: withMap, body: st.body })
      .then(blob => {
        if (!alive) return
        if (!blob) { setImg(prev => ({ ...prev, failed: true })); return }
        if (shown.current) URL.revokeObjectURL(shown.current)
        shown.current = URL.createObjectURL(blob)
        setImg({ blob, url: shown.current })
      })
      .catch(() => { if (alive) setImg(prev => ({ ...prev, failed: true })) })
    return () => { alive = false }
  }, [model, withMap, st.body])
  useEffect(() => () => { if (shown.current) URL.revokeObjectURL(shown.current) }, [])
  const name = 'opengym-workout-' + (workoutDay(w) || todayISO()) + '.png'
  const share = async () => {
    setBusy(true)
    await shareImage(img.blob, name, w.name || 'openGym')
    setBusy(false)
    close()
  }
  return <>
    <h3>{t("SHARE_WORKOUT" /* 分享训练 */)}</h3>
    <div className="share-card">
      {img?.url
        ? <img src={img.url} alt={t("PREVIEW_OF_THE_IMAGE_TO_SHARE" /* 待分享图片的预览 */)} />
        : img?.failed ? <div className="share-card-ph small muted">{t("COULD_NOT_CREATE_THE_IMAGE" /* 无法生成图片 */)}</div>
          : <div className="share-card-ph" aria-hidden="true" />}
    </div>
    {model.levels && <div className="sect-b" style={{ marginBottom: 12 }}>
      <Row icon="figureStrength" iconTint="var(--acc)" title={t("MUSCLE_MAP" /* 肌肉图 */)} subtitle={t("SHOW_WHICH_MUSCLES_THIS_WORKOUT_TRAINED" /* 显示本次训练锻炼了哪些肌肉。 */)}>
        <Switch checked={withMap} aria-label={t("MUSCLE_MAP" /* 肌肉图 */)} onChange={v => update(s => { s.shareMap = v })} />
      </Row>
    </div>}
    <Button variant="primary" icon="share" disabled={!img?.blob || busy} onClick={share}>{t("SHARE" /* 分享 */)}</Button>
  </>
}
async function workoutCardImage(model, { map, body }) {
  const root = getComputedStyle(document.documentElement)
  const css = (name, fallback) => root.getPropertyValue(name).trim() || fallback
  const colors = { bg: css('--bg', '#000'), surface: css('--surface', '#1c1c1e'), tile: css('--surface-2', '#2c2c2e'), label: css('--label', '#fff'), label2: css('--label-2', '#999'), acc: css('--acc', '#30d158') }
  // The body geometry is ~90 KB and lazy everywhere else too (components/BodyMap.jsx).
  const geometry = map && model.levels ? (await import('./lib/body-paths.js')).default : null
  const shape = geometry && (geometry[body] || geometry.male)
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  const measure = (text, weight, size) => { ctx.font = `${weight} ${size}px ${CARD_FONT}`; return ctx.measureText(text).width }
  const layout = layoutWorkoutCard(model, { measure, rtl: document.documentElement.dir === 'rtl', map: shape ? { aspect: viewAspect(shape.front) } : null })
  canvas.width = layout.width
  canvas.height = layout.height
  drawWorkoutCard(ctx, layout, colors, shape ? { body: shape, levels: model.levels } : null)
  return new Promise(resolve => canvas.toBlob(resolve, 'image/png'))
}
// The .fit file goes out the way a backup does: the share sheet in the phone app (Files, Drive,
// Garmin Connect itself), a download in the browser.
async function saveFitFile(blob, name) {
  if (MOBILE) { try { await shareExportBlob(blob, name) } catch (e) { /* share sheet dismissed */ } return }
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); URL.revokeObjectURL(a.href)
  toast(t("SAVED_GARMIN_CONNECT_CAN_TAKE_IT_FROM_HERE" /* 已保存。接下来交给 Garmin Connect 吧。 */))
}
// The phone app goes through the OS share sheet the way a backup does; a browser that can share
// files (most phones) opens its own; anything else saves the picture as a download.
async function shareImage(blob, name, title) {
  if (MOBILE) { try { await shareExportBlob(blob, name) } catch (e) { /* share sheet dismissed */ } return }
  const file = typeof File === 'function' ? new File([blob], name, { type: 'image/png' }) : null
  if (file && navigator.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file], title }) } catch (e) { /* dismissed */ }
    return
  }
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); URL.revokeObjectURL(a.href)
  toast(t("IMAGE_SAVED" /* 图片已保存 */))
}
// The sentence a workout's Delete adds when its photos and videos go with it — every file the
// record lists, shown or not. Empty when it has none.
function mediaGoesToo(rec) {
  const n = workoutMediaOf(rec, Infinity).length
  return n ? ' ' + tn("ITS_PHOTO_OR_VIDEO_IS_DELETED_WITH_IT" /* 其中的照片或视频也会一并删除。 */, "ITS_COUNT_PHOTOS_OR_VIDEOS_ARE_DELETED_WITH_IT" /* 其中的 {0} 个照片或视频也会一并删除。 */, n) : ''
}
export const workoutDetailSheet = w => ui().openSheet(close => <WorkoutDetail w={w} close={close} />)

/* ============================ calendar ============================ */
function Calendar({ start, close }) {
  const st = useStore(s => s.S)
  const [cur, setCur] = useState(() => { const d = start ? new Date(start) : new Date(); d.setDate(1); return d })
  const y = cur.getFullYear(), mo = cur.getMonth()
  const byDay = {}
  st.workouts.forEach(w => {
    const day = workoutDay(w)
    if (day) (byDay[day] = byDay[day] || []).push(w)
  })
  // Which column the 1st sits in, and therefore how many blanks come before it.
  const ws = weekStartOf(st)
  const startOffset = weekDayOffset(new Date(y, mo, 1).getDay(), ws)
  const daysIn = new Date(y, mo + 1, 0).getDate()
  const monthWs = st.workouts.filter(w => workoutDay(w)?.startsWith(y + '-' + String(mo + 1).padStart(2, '0')))
  const monthVol = monthWs.reduce((a, w) => a + (w.vol || 0), 0)
  const monthMs = monthWs.reduce((a, w) => a + Math.max(0, (w.end || w.start) - w.start), 0)
  const cells = []
  for (let i = 0; i < startOffset; i++) cells.push(<div key={'e' + i} />)
  for (let d = 1; d <= daysIn; d++) {
    const iso = y + '-' + String(mo + 1).padStart(2, '0') + '-' + String(d).padStart(2, '0')
    // A fulfilled pin (a coach session pinned here and since done) reads as no override, as it does everywhere else.
    const ws = byDay[iso], planned = effectiveRoutineIds(st, iso).length > 0, ovr = st.dayPlan[iso] !== undefined && pinState(st, st.dayPlan[iso]) !== 'done'
    // A day off with a note on it (#261) shows the note's dot instead of the plan's, and its
    // note as the tooltip; tapping it opens the day sheet, where the note is.
    const note = !ws && dayNoteOf(st, iso)
    const dotCls = ws ? 'done' : note ? 'noted' : ovr && planned ? 'ovr' : planned ? 'plan' : ''
    cells.push(<button key={d} className={'cal-d' + (ws ? ' has' : '') + (note ? ' noted' : '') + (iso === todayISO() ? ' today' : '')}
      title={note ? dayNoteLine(note, t) : undefined} onClick={() => {
      if (!ws) { close(); dayOverrideSheet(iso); return }
      if (ws.length === 1) { close(); workoutDetailSheet(ws[0]); return }
      close(); ui().openSheet(c2 => <><h3>{fmtDate(iso, true)}</h3><div className="list">{ws.map(w => <WorkoutRow key={w.id} w={w} onClick={() => { c2(); workoutDetailSheet(w) }} />)}</div></>)
    }}><span>{d}</span><i className={dotCls} /></button>)
  }
  return <>
    <div className="row between" style={{ marginBottom: 2 }}>
      <button className="iconbtn" onClick={() => setCur(new Date(y, mo - 1, 1))} aria-label={t("PREVIOUS_MONTH" /* 上个月 */)}><Icon name="chevronLeft" /></button>
      <h3 style={{ margin: 0 }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(MONTHS_LONG[mo])} {y}</h3>
      <button className="iconbtn" onClick={() => setCur(new Date(y, mo + 1, 1))} aria-label={t("NEXT_MONTH" /* 下个月 */)}><Icon name="chevronRight" /></button>
    </div>
    <div className="small muted" style={{ textAlign: 'center' }}>{monthWs.length ? `${tn("COUNT_WORKOUT" /* {0} 次训练 */, "COUNT_WORKOUTS" /* {0} 次训练 */, monthWs.length)} · ${fmtDur(monthMs)} · ${fmtVol(monthVol, st.unit)}` : t("NO_WORKOUTS_THIS_MONTH" /* 本月没有训练 */)}</div>
    <div className="cal-grid">{weekOrder(ws).map(d => <div key={d} className="cal-h">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYS[d])}</div>)}{cells}</div>
    <div className="cal-legend">
      <span><i style={{ background: 'var(--acc)' }} />{t("TRAINED" /* 已训练 */)}</span>
      <span><i style={{ background: 'var(--label-3)' }} />{t("PLANNED" /* 已计划 */)}</span>
      <span><i style={{ background: 'var(--orange)' }} />{t("RESCHEDULED_A" /* 已改期 */)}</span>
      {Object.keys(st.dayNotes || {}).some(k => k.startsWith(y + '-' + String(mo + 1).padStart(2, '0')) && dayNoteOf(st, k)) &&
        <span><i style={{ background: 'var(--indigo)' }} />{t("DAY_NOTE" /* 当日备注 */)}</span>}
    </div>
    <div className="small dim" style={{ textAlign: 'center', marginTop: 10 }}>{t("TAP_A_TRAINED_DAY_FOR_DETAILS_TAP_ANY_OTHER_DAY_TO_PLAN" /* 点按已训练的日期查看详情 · 点按其他日期安排训练 */)}</div>
  </>
}
export const calendarSheet = start => ui().openSheet(close => <Calendar start={start} close={close} />)

/* shared small workout row (used in lists) */
export function WorkoutRow({ w, onClick }) {
  const st = useStore(s => s.S)
  const glyph = glyphOf((st.routines.find(r => r.id === w.routineId) || {}).emoji)
  const mediaN = workoutMediaCount(w)
  return <div className="item" {...tappable(onClick)}>
    <span className="lrow-i" style={{ width: 34, height: 34, borderRadius: 8, fontSize: 19 }}><Icon name={glyph} /></span>
    <div className="grow"><div className="tt">{w.name}</div>
      <div className="ss">{[fmtDate(w.d, true), ...durPart(w.end - w.start), tn("COUNT_SET" /* {0} 组 */, "COUNT_SETS" /* {0} 组 */, setsDone(w)), fmtVol(w.vol, st.unit)].join(' · ')}</div></div>
    {mediaN > 0 && <span className="wrow-media" title={tn("COUNT_PHOTO_OR_VIDEO" /* {0} 个照片或视频 */, "COUNT_PHOTOS_OR_VIDEOS" /* {0} 个照片或视频 */, mediaN)} aria-label={tn("COUNT_PHOTO_OR_VIDEO" /* {0} 个照片或视频 */, "COUNT_PHOTOS_OR_VIDEOS" /* {0} 个照片或视频 */, mediaN)}><Icon name="image" />{mediaN}</span>}
    {w.prs && w.prs.length > 0 && <span className="pr"><Icon name="trophy" />{w.prs.length} PR</span>}
    <Icon name="chevronRight" className="chev" />
  </div>
}

/* a day off with a note (#261), as History lists it between the workouts */
export function DayNoteRow({ iso, note }) {
  return <div className="item day-note-row" {...tappable(() => dayNoteSheet(iso))}>
    <span className="lrow-i" style={{ width: 34, height: 34, borderRadius: 8, fontSize: 19, background: 'var(--surface-3)' }}><Icon name={note.tag ? DAY_NOTE_ICON[note.tag] : 'note'} /></span>
    <div className="grow"><div className="tt">{note.tag ? translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAY_NOTE_LABEL[note.tag]) : t("DAY_NOTE" /* 当日备注 */)}</div>
      <div className="ss">{[fmtDate(iso, true), note.text].filter(Boolean).join(' · ')}</div></div>
    <Icon name="chevronRight" className="chev" />
  </div>
}

/* ============================ workout lifecycle ============================ */
// `routineIds` accepts `string | string[] | null` — `[r.id]` for one routine,
// `effectiveRoutineIds(...)` for today's planned session, `[]` / null for explicit freestyle.
export function startFlow(routineIds) {
  // The weigh-in is a setting (Settings → During a workout, issue #137): off goes straight
  // into the session with no body weight on it, same as "Start without weighing in".
  if (S().weighIn === false) { beginWorkout(routineIds, null); return }
  bwSheet({ required: true, onDone: bw => beginWorkout(routineIds, bw) })
}
export function beginWorkout(routineIds, bw) {
  const st = S()
  const { entries, routineIds: rids, routines } = buildCombinedEntries(st, routineIds)
  update(s => {
    s.active = {
      id: uid(), d: todayISO(), start: Date.now(),
      // A session tracks its routines as a list; per-entry `rid` carries which one each
      // exercise came from. No top-level `excludeFromProgression` — per-entry `noProg` does it.
      routineIds: rids,
      name: routines.length ? deriveSessionName(routines.map(r => r.name)) : t("FREESTYLE" /* 自由训练 */),
      bw: bw || null, cur: 0, entries,
      // Snapshot the layout at start so the header ⋮ can change it for this session only —
      // changing the saved default (Settings → Workout view) mid-session leaves it alone.
      workoutView: st.workoutView || 'cards',
    }
  })
  useUI.getState().stopRest()
  navToWorkout()
}

// "Repeat today" (#58): a saved workout's exercises as a new freestyle session dated today, each
// seeded from what that workout logged (lib/session-repeat.js). The weigh-in asks first, the
// way starting any workout does.
export function repeatWorkout(w, close) {
  const st = S()
  if (st.active) { toast(t("FINISH_YOUR_CURRENT_WORKOUT_FIRST" /* 请先完成当前训练 */)); return }
  const { entries, skipped } = repeatSessionEntries(st, w)
  if (!entries.length) { toast(t("NOTHING_TO_REPEAT_ITS_EXERCISES_NO_LONGER_EXIST" /* 没有可重复的内容。其中的动作已不存在。 */)); return }
  const go = bw => {
    if (S().active) { toast(t("FINISH_YOUR_CURRENT_WORKOUT_FIRST" /* 请先完成当前训练 */)); return }
    update(s => {
      s.active = {
        id: uid(), d: todayISO(), start: Date.now(), routineIds: [],
        name: w.name || t("FREESTYLE" /* 自由训练 */), bw: bw || null, cur: 0, entries,
        workoutView: s.workoutView || 'cards',
      }
    })
    useUI.getState().stopRest()
    if (close) closeThenNav(close, '/workout'); else navToWorkout()
    if (skipped) toast(tn("COUNT_EXERCISE_NO_LONGER_EXISTS_AND_WAS_LEFT_OUT" /* 有 {0} 个动作已不存在，已略过。 */, "COUNT_EXERCISES_NO_LONGER_EXIST_AND_WERE_LEFT_OUT" /* 有 {0} 个动作已不存在，已略过。 */, skipped))
  }
  if (st.weighIn === false) { go(null); return }
  if (close) close()
  bwSheet({ required: true, onDone: go })
}

/* ============================ log a past workout ============================ */
// The same screen as a live session, pointed at another day. `backfill` on the active
// session is what tells the workout screen to drop the clock and the rest timers, and tells
// the finish path to file the workout where its date belongs instead of at the end.
// `initial` is a missed day of the plan (#284): its date, and the routines planned for it. A
// combined day is offered as the one session it plans, next to each routine on its own.
const PLANNED_DAY = '__planned-day'
function LogPastWorkout({ initial, close }) {
  const st = useStore(s => s.S)
  const yesterday = new Date(); yesterday.setDate(yesterday.getDate() - 1)
  const planned = [].concat(initial?.routineIds || []).map(id => st.routines.find(r => r.id === id)).filter(Boolean)
  const [date, setDate] = useState(initial?.iso || isoOf(yesterday))
  const [time, setTime] = useState('18:00')
  const [dur, setDur] = useState(60)
  const [routineId, setRoutineId] = useState(planned.length > 1 ? PLANNED_DAY : planned[0]?.id || '')
  const today = todayISO()
  const options = [
    { value: '', label: t("FREESTYLE" /* 自由训练 */) },
    ...(planned.length > 1 ? [{ value: PLANNED_DAY, label: deriveSessionName(planned.map(r => r.name)) }] : []),
    ...st.routines.map(r => ({ value: r.id, label: r.name })),
  ]

  const go = replaceId => {
    close()
    const routineIds = routineId === PLANNED_DAY ? planned.map(r => r.id) : routineId ? [routineId] : []
    beginBackfill({ iso: date, time, durationMin: Math.max(1, dur), routineIds, replaceId })
  }
  const submit = () => {
    if (!date || date > today) { toast(t("PICK_A_DAY_UP_TO_TODAY" /* 请选择今天或之前的日期 */)); return }
    if (!(dur >= 1)) { toast(t("ENTER_HOW_LONG_IT_TOOK_AT_LEAST_ONE_MINUTE" /* 请输入用时（至少 1 分钟）。 */)); return }
    if (dur > MAX_DURATION_MIN) { toast(t("THAT_S_MORE_THAN_A_DAY_KEEP_IT_TO_TWOFOUR_HOURS_OR" /* 超过一天了。最多 24 小时。 */)); return }
    if (endsInFuture(date, time, dur)) { toast(t("THAT_S_STILL_IN_THE_FUTURE_TRY_AN_EARLIER_START" /* 这还在未来。试试更早的开始时间。 */)); return }
    const existing = workoutsOn(st, date)
    if (!existing.length) { go(null); return }
    ui().openSheet(c => <SameDayChoice iso={date} existing={existing} close={c}
      onReplace={id => { c(); go(id) }} onAdd={() => { c(); go(null) }} />, { kind: 'center' })
  }

  return <>
    <h3>{t("LOG_A_PAST_WORKOUT" /* 补记过去的训练 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("LOGGED_ON_THE_USUAL_WORKOUT_SCREEN_WITHOUT_TIMERS" /* 在平时的训练界面记录，只是没有计时器。 */)}</div>
    <Row icon="calendar" title={t("DATE" /* 日期 */)}>
      <input type="date" className="timef" value={date} max={today} onChange={e => setDate(e.target.value)} /></Row>
    <Row icon="clock" title={t("START_TIME" /* 开始时间 */)}>
      <input type="time" className="timef" value={time} onChange={e => setTime(e.target.value)} /></Row>
    <Stepper label={t("DURATION" /* 时长 */)} unit={t("MIN" /* 分钟 */)} value={dur} step={5} min={0} decimal={false} invalid={!(dur >= 1) || dur > MAX_DURATION_MIN} onChange={v => setDur(Math.round(v))} />
    {!(dur >= 1) && <div className="small" style={{ color: 'var(--red)', marginTop: 6 }}>{t("ENTER_HOW_LONG_IT_TOOK_AT_LEAST_ONE_MINUTE" /* 请输入用时（至少 1 分钟）。 */)}</div>}
    {dur > MAX_DURATION_MIN && <div className="small" style={{ color: 'var(--red)', marginTop: 6 }}>{t("THAT_S_MORE_THAN_A_DAY_KEEP_IT_TO_TWOFOUR_HOURS_OR" /* 超过一天了。最多 24 小时。 */)}</div>}
    <div style={{ height: 8 }} />
    <SelectRow icon="dumbbell" title={t("ROUTINE" /* 训练计划 */)} value={routineId} options={options} onChange={setRoutineId} />
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={submit}>{t("CONTINUE" /* 继续 */)}</Button>
  </>
}
// Three ways out when the day already has a workout. Replacing with several on that day means
// picking which one; the rest of the day is left alone. A workout with photos or videos says
// they come along.
function SameDayChoice({ iso, existing, onReplace, onAdd, close }) {
  return <div style={{ textAlign: 'center', padding: '4px 0' }}>
    <h3 style={{ marginBottom: 8 }}>{fmtDate(iso, true)}</h3>
    <div className="muted" style={{ marginBottom: 18, lineHeight: 1.5 }}>{t("THERE_IS_ALREADY_A_WORKOUT_ON_THAT_DAY" /* 那天已经有一次训练了。 */)}</div>
    {existing.map(w => {
      // Replacing re-logs the sets; the photos and videos move to the new record (completeBackfill).
      const n = workoutMediaOf(w, Infinity).length
      return <div key={w.id} style={{ marginBottom: 8 }}>
        <button className="btn danger" onClick={() => onReplace(w.id)}>{existing.length > 1 ? t("REPLACE" /* 替换 */) + ' · ' + w.name : t("REPLACE" /* 替换 */)}</button>
        {n > 0 && <div className="small dim samed-media" style={{ marginTop: 4 }}>{tn("ITS_PHOTO_OR_VIDEO_MOVES_TO_THE_NEW_WORKOUT" /* 其中的照片或视频会移到新的训练中。 */, "ITS_COUNT_PHOTOS_OR_VIDEOS_MOVE_TO_THE_NEW_WORKOUT" /* 其中的 {0} 个照片或视频会移到新的训练中。 */, n)}</div>}
      </div>
    })}
    <button className="btn primary" onClick={onAdd}>{t("ADD_AS_SECOND_WORKOUT" /* 添加为第二次训练 */)}</button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </div>
}
// History's button hands this its click event; only a day from the plan counts as `initial`.
export function logPastWorkoutSheet(initial) {
  if (S().active) { toast(t("FINISH_YOUR_CURRENT_WORKOUT_FIRST" /* 请先完成当前训练 */)); return }
  const from = typeof initial?.iso === 'string' ? initial : null
  ui().openSheet(close => <LogPastWorkout initial={from} close={close} />)
}
// A backfilled session is built the way a live one is (buildCombinedEntries → buildPlannedEntry),
// so its entries carry the same stamps: the routine list, per-entry rid and the plan, no
// top-level routineId. One routine from the picker, or every routine of a missed combined day.
// Only from the history before that day (historyAsOf): a session logged later must not hand its
// progression back to the day it skipped.
function beginBackfill({ iso, time, durationMin, routineIds, replaceId }) {
  const st = S()
  const start = backfillStart(iso, time)
  const past = historyAsOf(st, { d: iso, start, replaceId })
  const { entries, routineIds: rids, routines } = buildCombinedEntries(past, routineIds || [])
  update(s => {
    s.active = {
      id: uid(), d: iso, start,
      routineIds: rids,
      name: routines.length ? deriveSessionName(routines.map(r => r.name)) : t("FREESTYLE" /* 自由训练 */),
      bw: null, cur: 0, entries,
      backfill: { durationMin, replaceId: replaceId || null },
      // Same layout snapshot as a live session (see beginWorkout).
      workoutView: st.workoutView || 'cards',
    }
  })
  useUI.getState().stopRest()
  navToWorkout()
}

/* ============================ add a routine mid-session ============================ */
// The workout header ⋮ → Add routine. Single-pick: a routine already in the session, or one
// with no exercises, is shown disabled and tagged. Picking one appends its entries (each
// stamped with its `rid`), extends `s.active.routineIds`, and re-derives the session name.
// `s.active.cur` is left where it is — the appended block is reached by scrolling / Next.
function AddRoutineToSession({ close }) {
  const st = useStore(s => s.S)
  const active = st.active
  if (!active) return null
  const inSession = new Set([].concat(active.routineIds || []))
  const add = r => {
    const entries = buildSessionEntries(sessionHistory(st), r).map(e => ({ ...e, rid: r.id }))
    update(s => {
      if (!s.active) return
      // A session kept out of progression as a whole (the header ⋮) keeps the routine's
      // exercises out too, the same as an exercise added on its own.
      s.active.entries.push(...entries.map(e => joinSessionNoProg(s.active, e)))
      s.active.routineIds = [...[].concat(s.active.routineIds || []), r.id]
      if (!s.active.customName) {
        s.active.name = deriveSessionName(s.active.routineIds.map(id => s.routines.find(x => x.id === id)?.name).filter(Boolean))
      }
    })
    close()
    toast(t("COUNT_ADDED_COUNT" /* 已添加 {0}（{1}） */, r.name, exCount(r.ex.length)))
  }
  return <>
    <h3>{t("ADD_ROUTINE" /* 添加训练计划 */)}</h3>
    <div className="list">
      {st.routines.map(r => {
        const already = inSession.has(r.id)
        const empty = !(r.ex || []).length
        const disabled = already || empty
        return <div key={r.id} className={'item' + (disabled ? ' disabled' : '')} aria-disabled={disabled || undefined}
          {...tappable(disabled ? null : () => add(r))}>
          <span className="lrow-i"><Icon name={glyphOf(r.emoji)} /></span>
          <div className="grow"><div className="tt">{r.name}</div><div className="ss">{exCount(r.ex.length)}</div></div>
          {already ? <span className="tag">{t("ALREADY_ADDED" /* 已添加 */)}</span> : empty ? <span className="tag">{t("NO_EXERCISES" /* 没有动作 */)}</span> : <Icon name="chevronRight" className="chev" />}
        </div>
      })}
    </div>
  </>
}
export function addRoutineToSessionSheet() {
  if (!S().active) return
  ui().openSheet(close => <AddRoutineToSession close={close} />)
}

/* ============================ exercise notes ============================
   Two notes, one sheet, because from the user's side it is one question — "what do I want to
   remember about this exercise?" — with two different lifetimes:

     · today's note belongs to this session and is stored on the workout entry. It is history:
       what happened, how it felt. The PIN is the user saying "this one is for next time", which
       only they can know at the moment of writing — see pinnedNoteFor.
     · the standing note belongs to the exercise itself and lives in S.exNotes. Seat height, pin
       position, a form cue. True every session, so it is shown every session and never expires.

   A routine's own `note` (a plan's instruction for this exercise) is edited in the config sheet
   and is deliberately not here: it belongs to the plan, not to the day or to the movement. */
function ExerciseNote({ entryIdx, close }) {
  const noteRef = useRef(null)
  const onNoteFocus = useSheetKeyboard(noteRef)
  const st = useStore(s => s.S)
  const update = useStore(s => s.update)
  const A = st.active
  const editing = !!A?.editingWorkoutId
  const entry = A ? A.entries[entryIdx] : null
  const ex = entry ? exOr(entry.id) : null
  const [note, setNote] = useState(entry?.note || '')
  const [pin, setPin] = useState(!!entry?.notePin)
  const [standing, setStanding] = useState(entry ? (st.exNotes?.[entry.id] || '') : '')
  useEffect(() => { if (!entry) close() }, [!entry])
  if (!entry) return null

  const save = () => {
    const today = note.trim().slice(0, NOTE_MAX)
    const always = standing.trim().slice(0, NOTE_MAX)
    update(s => {
      const e = s.active?.entries?.[entryIdx]
      if (e) {
        if (today) { e.note = today; if (pin) e.notePin = true; else delete e.notePin }
        else { delete e.note; delete e.notePin }
      }
      if (!editing) {
        s.exNotes = s.exNotes || {}
        if (always) s.exNotes[entry.id] = always
        else delete s.exNotes[entry.id]
      }
    })
    close()
  }

  return <>
    <h3 className={exerciseNameClass(ex)}>{exerciseNameFor(ex)}</h3>
    <div className="small muted" style={{ marginBottom: 6 }}>{t("THIS_SESSION" /* 本次训练 */)}</div>
    <textarea ref={noteRef} className="input" rows={3} maxLength={NOTE_MAX} value={note}
      placeholder={t("HOW_IT_WENT_WHAT_TO_CHANGE_SAVED_WITH_TODAY_S_WORKOUT" /* 感觉如何，下次要改什么。随今天的训练一起保存。 */)}
      onFocus={onNoteFocus} onChange={e => setNote(e.target.value)} />
    <div style={{ height: 10 }} />
    <div className="sect-b">
      <Row icon="pin" iconTint="var(--yellow)" title={t("SHOW_THIS_NEXT_TIME" /* 下次显示 */)}
        subtitle={t("BRINGS_IT_UP_AGAIN_THE_NEXT_TIME_YOU_TRAIN_THIS_EXERCISE" /* 下次练这个动作时会再次出现。 */)}>
        <Switch checked={pin} onChange={setPin} disabled={!note.trim()} />
      </Row>
    </div>
    {!editing && <>
      <div style={{ height: 18 }} />
      <div className="small muted" style={{ marginBottom: 6 }}>{t("ALWAYS_FOR_THIS_EXERCISE" /* 这个动作始终显示 */)}</div>
      <textarea className="input" rows={2} maxLength={NOTE_MAX} value={standing}
        placeholder={t("SEAT_HEIGHT_PIN_POSITION_A_FORM_CUE_SHOWN_EVERY_SESSION" /* 座椅高度、插销位置、动作要点。每次训练都会显示。 */)}
        onChange={e => setStanding(e.target.value)} />
    </>}
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const exerciseNoteSheet = entryIdx => ui().openSheet(close => <ExerciseNote entryIdx={entryIdx} close={close} />)

function SetNote({ entryIdx, setIdx, close }) {
  const noteRef = useRef(null)
  const onNoteFocus = useSheetKeyboard(noteRef)
  const row = useStore(s => s.S.active?.entries?.[entryIdx]?.sets?.[setIdx])
  const update = useStore(s => s.update)
  const [note, setNote] = useState(row?.note || '')

  useEffect(() => { if (!row) close() }, [!row])
  if (!row) return null

  const save = () => {
    const text = note.trim().slice(0, NOTE_MAX)
    update(s => {
      const set = s.active?.entries?.[entryIdx]?.sets?.[setIdx]
      if (!set) return
      if (text) set.note = text
      else delete set.note
    }, true)
    close()
  }

  return <>
    <h3>{t("SET_NOTE" /* 组备注 */)}</h3>
    <textarea ref={noteRef} className="input" rows={4} maxLength={NOTE_MAX} value={note}
      placeholder={t("ANYTHING_SPECIFIC_TO_REMEMBER_ABOUT_THIS_SET" /* 记录这组需要特别注意的事项。 */)}
      onFocus={onNoteFocus} onChange={event => setNote(event.target.value)} />
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}

export const setNoteSheet = (entryIdx, setIdx) =>
  ui().openSheet(close => <SetNote entryIdx={entryIdx} setIdx={setIdx} close={close} />)

/* The session note: how the whole workout went, as opposed to how one exercise went. It lives
   on the active session, so buildCompletedWorkout carries it onto the finished workout and it
   shows up again in history — where it stays editable. Written here rather than only after the
   fact because "notes you can write during a workout" is the point; a note you can only add
   once the session is filed is a different, smaller feature. */
function SessionNote({ close }) {
  const noteRef = useRef(null)
  const onNoteFocus = useSheetKeyboard(noteRef)
  const st = useStore(s => s.S)
  const update = useStore(s => s.update)
  const A = st.active
  const [note, setNote] = useState(A?.note || '')
  useEffect(() => { if (!A) close() }, [!A])
  if (!A) return null

  const save = () => {
    const text = note.trim().slice(0, SESSION_NOTE_MAX)
    update(s => { if (!s.active) return; if (text) s.active.note = text; else delete s.active.note })
    close()
  }

  return <>
    <h3>{t("SESSION_NOTE" /* 训练备注 */)}</h3>
    <textarea ref={noteRef} className="input" rows={4} maxLength={SESSION_NOTE_MAX} value={note}
      placeholder={t("HOW_THE_SESSION_WENT_AS_A_WHOLE" /* 这次训练整体感觉如何。 */)}
      onFocus={onNoteFocus} onChange={e => setNote(e.target.value)} />
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const sessionNoteSheet = () => ui().openSheet(close => <SessionNote close={close} />)

function RenameWorkout({ close }) {
  const inputRef = useRef(null)
  const onFocus = useSheetKeyboard(inputRef)
  const st = useStore(s => s.S)
  const update = useStore(s => s.update)
  const A = st.active
  const [name, setName] = useState(A?.name || '')
  useEffect(() => { if (!A) close() }, [!A])
  if (!A) return null

  const trimmed = name.trim().slice(0, 60)
  const canSave = trimmed.length > 0

  const save = () => {
    if (!canSave) return
    update(s => {
      if (!s.active) return
      s.active.name = trimmed
      s.active.customName = true
    })
    close()
  }

  return <>
    <h3>{t("RENAME_WORKOUT" /* 重命名训练 */)}</h3>
    <input ref={inputRef} className="input" type="text" autoFocus maxLength={60} value={name}
      placeholder={t("WORKOUT_TITLE" /* 训练标题 */)}
      onFocus={onFocus} onChange={e => setName(e.target.value)}
      onKeyDown={e => { if (e.key === 'Enter' && canSave) save() }} />
    <div style={{ height: 18 }} />
    <Button variant="primary" disabled={!canSave} onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const renameWorkoutSheet = () => ui().openSheet(close => <RenameWorkout close={close} />)

// A superset's own name and rest between rounds (#292), from the routine editor.
function SupersetSettings({ meta, onSave, close }) {
  const inputRef = useRef(null)
  const onFocus = useSheetKeyboard(inputRef)
  const [name, setName] = useState(meta.name || '')
  const [rest, setRest] = useState(meta.rest || 0)
  const save = () => { onSave({ name: name.trim().slice(0, SG_NAME_MAX), rest }); close() }
  return <>
    <h3>{t("SUPERSET" /* 超级组 */)}</h3>
    <input ref={inputRef} className="input" type="text" maxLength={SG_NAME_MAX} value={name}
      placeholder={t("NAME_E_G_ARM_FINISHER" /* 名称，例如手臂收尾 */)} onFocus={onFocus} onChange={e => setName(e.target.value)}
      onKeyDown={e => { if (e.key === 'Enter') save() }} />
    <div style={{ height: 12 }} />
    <div className="list">
      <Row icon="timer" iconTint="var(--orange)" title={t("REST_AFTER_EACH_ROUND" /* 每轮后的休息 */)}
        value={rest > 0 ? fmtRest(rest) : t("LONGEST_EXERCISE_REST" /* 最长的动作休息 */)} accessory="chevron"
        onClick={() => durationSheet({ title: t("REST_AFTER_EACH_ROUND" /* 每轮后的休息 */), value: rest, max: REST_MAX, off: t("LONGEST_EXERCISE_REST" /* 最长的动作休息 */),
          footer: t("WITHOUT_ONE_THE_SUPERSET_RESTS_AS_LONG_AS_ITS_LONGEST_EXERCISE_REST" /* 不设置的话，超级组的休息时间等于其中最长的动作休息。 */), onDone: setRest })} />
    </div>
    <div style={{ height: 18 }} />
    <Button variant="primary" onClick={save}>{t("SAVE" /* 保存 */)}</Button>
  </>
}
export const supersetSheet = (meta, onSave) => ui().openSheet(close => <SupersetSettings meta={meta} onSave={onSave} close={close} />)

/* Drop-set drops and rest-pause bursts are edited inline on the set row itself (Workout.jsx) —
   no sheet, no timer. A planned exercise (see the "Intensifier" config below) arrives with them
   already computed via applyIntensifierPlan; an unplanned straight set can still grow one live
   by tapping "+ Drop"/"+ Burst", which appends with the same suggested-next-value math. */

// Shown when the last exercise's last set is checked — finish, or keep going.
function WorkoutComplete({ close }) {
  return <div style={{ textAlign: 'center', padding: '8px 0' }}>
    <div style={{ fontSize: 44, display: 'flex', justifyContent: 'center', color: 'var(--acc)' }}><Icon name="checkCircle" /></div>
    <h3 style={{ margin: '8px 0' }}>{t("THAT_S_THE_WHOLE_WORKOUT" /* 训练全部完成！ */)}</h3>
    <div className="muted small" style={{ marginBottom: 16 }}>{t("ALL_EXERCISES_DONE_NICE_WORK_FINISH_UP_OR_ADD_ANOTHER_ONE_IF" /* 所有动作都完成了，干得漂亮！可以结束训练，如果还有余力就再加一个。 */)}</div>
    <Button variant="primary" icon="flag" onClick={() => { close(); finishWorkout() }}>{t("FINISH_WORKOUT" /* 结束训练 */)}</Button>
    <div style={{ height: 8 }} />
    <Button onClick={() => { close(); useUI.getState().toast(t("KEEP_GOING_TAP_ADD_EXERCISE_BELOW" /* 继续加油：点按下方“+ 添加动作” */)) }}>{t("CONTINUE_WORKOUT" /* 继续训练 */)}</Button>
  </div>
}
export const workoutCompleteSheet = () => ui().openSheet(close => <WorkoutComplete close={close} />, { kind: 'center' })

export function saveWorkoutEdits(onExit = () => nav('/history')) {
  // A save decision left open after the editor already closed (a second prompt from a route
  // exit that raced the first save) has nothing to save or delete: it only finishes leaving.
  if (!S().active?.editingWorkoutId) { onExit(); return }
  // An edit that unticked or removed every set would save a workout with nothing in it, which
  // the history would still list and count as a training day. Deleting it is what that edit
  // means; Keep editing goes back to the sets.
  if (editLeftEmpty(S().active)) {
    confirmSheet({
      title: t("DELETE_WORKOUT" /* 删除训练？ */),
      message: t("NO_SETS_ARE_LEFT_IN_THIS_WORKOUT_SO_THERE_IS_NOTHING_TO" /* 这次训练已经没有任何一组了，没有可保存的内容。要从历史中删除它吗？ */) + mediaGoesToo(editedRecord(S())),
      confirmText: t("DELETE_WORKOUT_A" /* 删除训练 */), cancelText: t("KEEP_EDITING" /* 继续编辑 */), danger: true,
      onConfirm: () => {
        useStore.getState().deleteHistoryEdit()
        useUI.getState().stopRest()
        useUI.getState().stopWork()
        useStore.getState().autoBackupNow()
        toast(t("WORKOUT_DELETED" /* 训练已删除 */))
        onExit()
      },
    })
    return
  }
  try {
    useStore.getState().saveHistoryEdit()
    useUI.getState().stopRest()
    useUI.getState().stopWork()
    useStore.getState().autoBackupNow()
    toast(t("WORKOUT_UPDATED" /* 训练已更新 */))
    onExit()
  } catch (error) { toast(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(error.message)) }
}

// The one save prompt that may be open: { id, onExit }. Closing the editor and a route exit
// can both ask in the same moment (the X, then the route change its tap set off); a second
// prompt stacked under the first came back after Save changes and asked all over again
// (QA 10-06). The second ask now joins the open prompt and only says where to go after it.
let savePrompt = null
const promptOpen = () => !!savePrompt && useUI.getState().sheets.some(x => x.id === savePrompt.id)

export function exitWorkoutEdit(onExit = () => nav('/history')) {
  if (!S().active?.editingWorkoutId) { onExit(); return }
  if (promptOpen()) { savePrompt.onExit = onExit; return }
  const prompt = { id: null, onExit }
  const done = () => prompt.onExit()
  const leave = () => {
    // A stale prompt's Don't save must not throw away whatever is in S.active by now.
    if (!S().active?.editingWorkoutId) { done(); return }
    useStore.getState().discardHistoryEdit()
    useUI.getState().stopRest()
    useUI.getState().stopWork()
    done()
  }
  // Nothing to save: closing just closes, as it does for a workout only looked at.
  if (editChangesNothing(S())) { leave(); return }
  prompt.id = ui().openSheet(close => <>
    <h3>{t("SAVE_WORKOUT_CHANGES" /* 保存训练更改？ */)}</h3>
    <p className="muted">{t("SAVE_YOUR_EDITS_TO_THIS_WORKOUT_OR_KEEP_THE_ORIGINAL_RECORD" /* 保存对此训练的编辑，或保留原始记录。 */)}</p>
    <Button variant="primary" onClick={() => { close(); saveWorkoutEdits(done) }}>{t("SAVE_CHANGES" /* 保存更改 */)}</Button>
    <div style={{ height: 8 }} />
    <Button onClick={() => { close(); leave() }}>{t("DON_T_SAVE" /* 不保存 */)}</Button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={close}>{t("KEEP_EDITING" /* 继续编辑 */)}</Button>
  </>, { kind: 'center' })?.id
  savePrompt = prompt
}

// "60 kg × 5, 5, 4", or "60×5 · 62.5×5" when the weight changed between sets; a bodyweight lift
// without load is just its reps. A set taken to failure keeps its "F", as it does in the history.
export function setsLine(sets, unit) {
  const ws = new Set(sets.map(s => s.w))
  const reps = s => s.r + (s.f ? ' ' + t("LABEL_F" /* 术语：F */) : '')
  if (ws.size === 1) {
    const w0 = sets[0].w
    return (w0 > 0 ? fmtNum(w0) + ' ' + unit + ' × ' : '') + sets.map(reps).join(', ')
  }
  return sets.map(s => (s.w > 0 ? fmtNum(s.w) + '×' : '') + reps(s)).join(' · ')
}
const TREND = { 1: ['arrowUp', 'var(--green)'], 0: ['minus', 'var(--text-2)'], [-1]: ['arrowDown', 'var(--orange)'] }
function LastAndNext({ st, w }) {
  const rows = finishCompare(st, w)
  if (!rows.length) return null
  const nextWord = { up: t("STEP_UP" /* 加一档 */), hold: t("SAME_AGAIN" /* 原样再来 */), down: t("LIGHTER" /* 减轻一点 */), deload: t("DELOAD" /* 减载 */) }
  return <div style={{ textAlign: 'start', marginBottom: 14 }}>
    <h4 className="sec">{t("LAST_TIME_AND_NEXT_TIME" /* 上次与下次 */)}</h4>
    <div className="list">{rows.map(row => {
      const ex = EXIDX[row.id]
      const tr = row.trend == null ? null : TREND[row.trend]
      return <div key={row.id} className="item" style={{ display: 'block' }}>
        <div className="row between" style={{ gap: 8 }}>
          <span className={'tt ' + exerciseNameClass(ex)} style={{ fontWeight: 600 }}>{ex ? exerciseNameFor(ex) : row.id}</span>
          {tr ? <span style={{ color: tr[1], display: 'inline-flex' }} aria-label={row.trend > 0 ? t("UP_ON_LAST_TIME" /* 比上次多 */) : row.trend < 0 ? t("DOWN_ON_LAST_TIME" /* 比上次少 */) : t("SAME_AS_LAST_TIME" /* 和上次一样 */)}><Icon name={tr[0]} /></span>
            : <span className="tag nocap">{t("FIRST_TIME" /* 第一次 */)}</span>}
        </div>
        <div className="small">{t("TODAY" /* 今天 */)}: {setsLine(row.today, st.unit)}</div>
        {row.last && <div className="small dim">{t("LAST_TIME" /* 上次 */)}: {setsLine(row.last, st.unit)}</div>}
        {row.next && <div className="small accent">{t("NEXT_TIME" /* 下次 */)}: {row.next.w != null ? fmtNum(row.next.w) + ' ' + st.unit : ''}{row.next.w != null && row.next.r != null ? ' × ' : ''}{row.next.r != null ? row.next.r : ''} · {nextWord[row.next.kind]}</div>}
      </div>
    })}</div>
  </div>
}

// The cardio of the session, which "Last time and next time" leaves out: minutes, speed and the
// treadmill's incline as they were logged.
function CardioDone({ st, w }) {
  const rows = finishCardio(w)
  if (!rows.length) return null
  return <div style={{ textAlign: 'start', marginBottom: 14 }}>
    <h4 className="sec">{t("CARDIO" /* 有氧 */)}</h4>
    <div className="list">{rows.map((row, i) => {
      const ex = EXIDX[row.id]
      return <div key={i} className="item" style={{ display: 'block' }}>
        <span className={'tt ' + exerciseNameClass(ex)} style={{ fontWeight: 600 }}>{ex ? exerciseNameFor(ex) : row.id}</span>
        <div className="small">{row.sets.map(x => setLabel(row.id, x, row.target, speedUnitOf(st))).join('  ·  ')}</div>
      </div>
    })}</div>
  </div>
}

function FinishSummary({ w, prs, e1prs = [], close }) {
  const st = useStore(s => s.S)
  return <div style={{ textAlign: 'center', padding: '8px 0' }}>
    <div style={{ fontSize: 44, display: 'flex', justifyContent: 'center', color: 'var(--acc)' }}><Icon name="trophy" /></div>
    <h3 style={{ margin: '8px 0' }}>{t("WORKOUT_COMPLETE" /* 训练完成！ */)}</h3>
    <div className="tiles" style={{ textAlign: 'start' }}>
      <div className="tile"><div className="l">{t("DURATION" /* 时长 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{fmtDur(w.end - w.start)}</div></div>
      <div className="tile"><div className="l">{t("VOLUME" /* 训练量 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{fmtVol(w.vol, st.unit)}</div></div>
      <div className="tile"><div className="l">{t("SETS" /* 组数 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{setsWorkCount(setsDone(w), workSetsDone(w))}</div></div>
      <div className="tile"><div className="l">{t("PRS" /* 纪录 */)}</div><div className="v" style={{ fontSize: 20 }}>{prs.length || '–'}</div></div>
    </div>
    {(prs.length > 0 || e1prs.length > 0) && <div style={{ textAlign: 'start', marginBottom: 12 }}>
      {prs.map(id => <div key={id} className="small accent row" style={{ gap: 5 }}><Icon name="trophy" style={{ fontSize: 13 }} />{t("NEW_PR" /* 新纪录： */)} <span className={exerciseNameClass(EXIDX[id])}>{EXIDX[id] ? exerciseNameFor(EXIDX[id]) : id}</span></div>)}
      {e1prs.map(p => <div key={p.id} className="small accent row" style={{ gap: 5 }}><Icon name="chartLine" style={{ fontSize: 13 }} />{t("BEST_ESTIMATED_ONE_REP_MAX" /* 最佳估算 1RM： */)} <span className={exerciseNameClass(EXIDX[p.id])}>{EXIDX[p.id] ? exerciseNameFor(EXIDX[p.id]) : p.id}</span> · {fmtNum(p.est)} {st.unit}</div>)}
    </div>}
    <h4 className="sec" style={{ textAlign: 'start' }}>{t("WHAT_YOU_JUST_TRAINED" /* 你刚刚练了什么 */)}</h4>
    <BodyMap load={loadOfWorkouts([w])} body={st.body} />
    <div style={{ height: 14 }} />
    <LastAndNext st={st} w={w} />
    <CardioDone st={st} w={w} />
    {/* The moment for a progress photo or the clip of a set: the workout is already saved, so
        what is added here goes straight onto its record. */}
    <div style={{ textAlign: 'start' }}><WorkoutMediaSection w={w} hint /></div>
    <Button variant="primary" onClick={() => closeThenNav(close, '/home')}>{t("NICE" /* 太棒了！ */)}</Button>
  </div>
}
export function finishWorkout() {
  if (S().active?.editingWorkoutId) { saveWorkoutEdits(); return }
  const A = S().active
  if (!A) return
  const done = setsDoneActive(A)
  const total = setUnitsTotal(A.entries)
  if (!done) { confirmSheet({ title: t("NOTHING_LOGGED_YET" /* 还没有记录 */), message: t("YOU_HAVEN_T_CHECKED_OFF_ANY_SETS_FINISH_THE_WORKOUT_ANYWAY" /* 你还没有勾选任何组。仍要结束训练吗？ */), confirmText: t("FINISH_ANYWAY" /* 仍然结束 */), onConfirm: doFinishWorkout }); return }
  if (done < total) { confirmSheet({ title: t("FINISH_EARLY" /* 提前结束？ */), message: tn("COUNT_SET_STILL_UNCHECKED_FINISH_THE_WORKOUT_NOW" /* 还有 {0} 组未勾选。现在结束训练吗？ */, "COUNT_SETS_STILL_UNCHECKED_FINISH_THE_WORKOUT_NOW" /* 还有 {0} 组未勾选。现在结束训练吗？ */, total - done), confirmText: t("FINISH_WORKOUT" /* 结束训练 */), onConfirm: doFinishWorkout }); return }
  doFinishWorkout()
}
// The workout screen's Finish pill (v1.3.11): one sheet with both ways out, Finish and save or
// Discard. It says what finishWorkout's confirm would have said about sets still unchecked, so
// the save needs no second question. `onDiscard` is the screen's own discard, with its confirm.
// The editor of a saved workout still saves at once.
export function finishWorkoutSheet({ onDiscard } = {}) {
  if (S().active?.editingWorkoutId) { saveWorkoutEdits(); return }
  const A = S().active
  if (!A) return
  const done = setsDoneActive(A)
  const total = setUnitsTotal(A.entries)
  menuSheet({
    title: !done ? t("NOTHING_LOGGED_YET" /* 还没有记录 */) : done < total ? t("FINISH_EARLY" /* 提前结束？ */) : t("FINISH_WORKOUT_A" /* 结束训练？ */),
    subtitle: !done ? t("YOU_HAVEN_T_CHECKED_OFF_ANY_SETS_FINISH_THE_WORKOUT_ANYWAY" /* 你还没有勾选任何组。仍要结束训练吗？ */)
      : done < total ? tn("COUNT_SET_STILL_UNCHECKED_FINISH_THE_WORKOUT_NOW" /* 还有 {0} 组未勾选。现在结束训练吗？ */, "COUNT_SETS_STILL_UNCHECKED_FINISH_THE_WORKOUT_NOW" /* 还有 {0} 组未勾选。现在结束训练吗？ */, total - done) : null,
    sections: [
      { items: [{ icon: 'flag', accent: true, label: t("FINISH_AND_SAVE" /* 结束并保存 */), onClick: doFinishWorkout }] },
      { items: [onDiscard && { icon: 'trash', danger: true, label: t("DISCARD_WORKOUT_A" /* 放弃训练 */), onClick: onDiscard }] },
    ],
  })
}
function doFinishWorkout() {
  const st = S()
  const A = st.active
  if (!A) return
  const past = !!A.backfill
  const prs = []
  const e1prs = []
  // A workout logged into the past is held against the history before it, the way an edit of a
  // saved one is (rebuildPrHistory, below): it gains a badge it leads with, and a later session
  // it outdoes loses its own. It used to report none at all while the editor's Save awarded them
  // (QA 1.3.9). The confirmed weights are left alone either way.
  if (!past) A.entries.forEach(e => {
    const loads = e.sets.filter(s => s.done && !isWarmupRow(s)).map(s => s.w).filter(w => w > 0)
    const mx = loads.length ? loads.reduce((a, b) => betterWeight(e.id, a, b)) : 0
    // Held against history read the way this session logged a dumbbell weight (lib/dumbbells.js).
    if (beatsWeight(e.id, mx, bestWeightFor(st, e.id, entryDbLoad(e)))) prs.push(e.id)
    // A heavier estimate without a heavier top set is its own kind of progress —
    // same weight for more reps. Reported separately so it can't be read as a load PR.
    const rec = is1RMRecord(st, e.id, e)
    if (rec && !prs.includes(e.id)) e1prs.push({ id: e.id, ...rec })
  })
  const w = buildCompletedWorkout(A, {
    end: past ? backfillEnd(A) : sessionEnd(A),
    prs,
    snapshotFor: e => isCustomEx(EXIDX[e.id]) ? exerciseMuscleSnapshot(EXIDX[e.id]) : null,
  })
  w.vol = workoutVolume(w)
  let shown = w
  update(s => {
    if (past) {
      // Its start and end are in the past; the stamp says when it was logged, which is what a
      // merge after a reset elsewhere asks of it (lib/sync-merge.js sinceReset).
      stampWorkout(w)
      const replaced = A.backfill.replaceId ? s.workouts.find(x => x.id === A.backfill.replaceId) : null
      const touched = [...new Set([...(replaced?.entries || []), ...w.entries].map(e => e?.id).filter(id => id != null))]
      s.workouts = rebuildPrHistory(completeBackfill(s.workouts, A, w), touched, w)
      shown = s.workouts.find(x => x === w || (w.id != null && x.id === w.id)) || w
      prs.push(...[...(shown.prs || [])])
    } else {
      w.entries.forEach(e => {
        const mx = bestWeightForEntry(e)
        if (mx > 0 && beatsWeight(e.id, mx, (s.exWeights[e.id] || {}).w || 0)) s.exWeights[e.id] = { w: mx, d: w.d }
      })
      s.workouts.push(w)
    }
    s.active = null
    // A rotation pass this app manages starts its next pass the moment the last session lands
    // (lib/rotation.js). A planner's queue is left alone: it completes and waits for its writer.
    refillAfter(s, w)
  })
  useStore.getState().autoBackupNow()
  useUI.getState().stopRest()
  // A hold still counting (a plank left unchecked, then Finish early) goes with the workout, as
  // on Discard: its bar is app-wide and would chime over the summary, and its callback writes
  // into s.active, which is gone. What it held is not logged, like any set left unchecked.
  useUI.getState().stopWork()
  beep(snd(), 880, 0.15); beep(snd(), 1100, 0.15, 0.18); beep(snd(), 1320, 0.3, 0.36)
  ui().openSheet(close => <FinishSummary w={shown} prs={prs} e1prs={e1prs} close={close} />, { kind: 'center', locked: true })
}
