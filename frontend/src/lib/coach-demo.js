// The Coach, in the demo build.
//
// The GitHub Pages demo has no backend at all, so there is nothing to run a CLI and nothing
// to poll. Rather than hide the feature there — it is the most interesting thing the app
// does — the demo answers the same calls locally with a canned proposal.
//
// It is built from the demo profile's actual routines rather than hard-coded, so every id
// resolves, the before/after values are real, and applying it exercises exactly the same
// code path as a live instance: validate, snapshot, apply, log, revert. What is faked is the
// provider, not the feature.
//
// Nothing here ships in a self-hosted bundle: every entry point is behind DEMO, which Vite
// replaces at build time.

import { EXIDX, EXDB } from './exercises.js'
import { modeOf, workoutVolume, workoutAt } from './history.js'
import { isWarmupRow } from './workout-model.js'
import { best1RM } from './onerm.js'
import { fmtNum } from './format.js'
import { planHash } from './coach.js'
import { t } from './i18n.js'

const DELAY = 2200      // long enough to see "the Coach is thinking…", short enough to forgive

let pending = null
let job = null
let timer = null
let lastError = null    // the last job that ended without a proposal, in the server's shape

const iso = d => d.toISOString().slice(0, 10)

/** The routine the canned review aims at: the first with two exercises, one to swap and one to cut a set from. */
const reviewable = S => (S.routines || []).find(r => (r.ex || []).length >= 2)

/** A change-set that reads like a real one, aimed at whatever the demo profile actually has. */
function buildReview(S) {
  const routine = reviewable(S)
  if (!routine) return null
  const reps = (routine.ex || []).filter(e => modeOf(e) === 'reps')
  const first = reps[0] || routine.ex[0]
  // Anything but `first`: the two changes below swap `first` away and re-set `second`, so the
  // same entry in both aborts the whole change-set on apply (`missing target`). `reps[1]` was
  // not enough — a routine whose only rep-mode exercise sits at index 1 landed on it twice.
  const second = reps.find(e => e !== first) || routine.ex.find(e => e !== first)
  const other = (S.routines || []).find(r => r.id !== routine.id)

  // Something plausible that is *not* in this routine, from the same body part as the first
  // exercise — a swap the reader can believe rather than a random pick out of 1,324.
  const bp = EXIDX[first.id]?.bp
  const swapTo = EXDB.find(e => e.bp === bp && e.eq === 'dumbbell' && !(routine.ex || []).some(x => x.id === e.id))
    || EXDB.find(e => e.bp === bp && !(routine.ex || []).some(x => x.id === e.id))

  const sessions = (S.workouts || []).slice(-9)
  const changes = []
  if (swapTo) changes.push({
    id: 'd1', type: 'swap-exercise', target: { routineId: routine.id, exId: first.id },
    before: EXIDX[first.id]?.n || first.id, after: { id: swapTo.id, name: swapTo.n },
    why: t("EVERY_TOP_SET_ON_THIS_ONE_CAME_IN_AT_RPE_NINE_FIVE" /* 这个动作的主要组连续三次训练都在 RPE 9.5 或以上，而重量没有变化。把动作换掉四周，通常比死磕同一个动作更快突破平台期。 */)
  })
  if (second) changes.push({
    id: 'd2', type: 'sets', target: { routineId: routine.id, exId: second.id },
    before: second.sets ?? 3, after: Math.max(1, (second.sets ?? 3) - 1),
    why: t("SESSIONS_HAVE_BEEN_RUNNING_ABOUT_FIFTEEN_MINUTES_OVER_THIS_IS_THE_ACCESSORY" /* 训练时间大约超出了十五分钟。这个辅助动作少做一组损失最小。 */)
  })
  if (other) changes.push({
    id: 'd3', type: 'week', target: { weekday: 6 }, before: null, after: other.id,
    why: t("YOU_HAVE_MOVED_THIS_SESSION_TO_SATURDAY_THREE_WEEKS_RUNNING_BETTER_THE" /* 你已经连续三周把这次训练挪到周六了。与其每次都手动改，不如直接写进计划。 */)
  })

  return {
    id: 'demo-review', kind: 'review', createdAt: Date.now(), expiresAt: Date.now() + 864e5,
    planHash: planHash(S), iteration: 1,
    summary: t("THREE_THINGS_WORTH_CHANGING_AND_ONE_WORTH_KNOWING_ABOUT_EVERYTHING_ELSE_IS" /* 有三处值得调整，还有一件值得知道。其他一切都很好：深蹲和拉的动作都在按计划进步。 */),
    evidence: { from: sessions[0]?.d || iso(new Date(Date.now() - 28 * 864e5)), to: sessions.at(-1)?.d || iso(new Date()), sessions: sessions.length || 9 },
    changes,
    notes: [t("BODY_WEIGHT_HAS_BEEN_FLAT_FOR_FOUR_WEEKS_WHILE_THE_GOAL_IS" /* 目标是增重，但体重已经四周没动了。这是厨房的问题，不是训练的问题。拖后腿的不是计划。 */)]
  }
}

/** A small, honest starter plan for the demo's creation flow. */
function buildPlan(S, intake) {
  const pick = (bp, eq) => EXDB.find(e => e.bp === bp && (!eq || e.eq === eq)) || EXDB.find(e => e.bp === bp)
  const days = intake?.preferredDays?.length ? intake.preferredDays.slice(0, 3) : [1, 3, 5]
  const eq = (intake?.equipment || [])[0] || null
  const mk = (id, name, sets, reps, why) => ({ id, sets, reps, mode: 'reps', why })
  const routines = [
    {
      id: 'dr1', name: t("FULL_BODY_A_A" /* 全身 A */), emoji: '💪', prog: 'linear',
      why: t("THE_TWO_BIG_LOWER_BODY_AND_PRESSING_PATTERNS_FIRST_WHILE_YOU_ARE" /* 趁体力充沛时，先做下肢和推这两个大模式。 */),
      ex: [
        mk(pick('upper legs', eq)?.id, null, 3, 8, t("THE_MAIN_LOWER_BODY_DRIVER_WHERE_MOST_OF_THE_STRENGTH_COMES_FROM" /* 下肢的主力动作，大部分力量都来自这里。 */)),
        mk(pick('chest', eq)?.id, null, 3, 10, t("HORIZONTAL_PRESSING_THE_OTHER_HALF_OF_THE_SESSION" /* 水平推，训练的另一半。 */)),
        mk(pick('back', eq)?.id, null, 3, 10, t("A_PULL_FOR_EVERY_PRESS_SO_THE_SHOULDERS_STAY_BALANCED" /* 每个推的动作都配一个拉的动作，让肩部保持平衡。 */))
      ].filter(e => e.id)
    },
    {
      id: 'dr2', name: t("FULL_BODY_B" /* 全身 B */), emoji: '🏋️', prog: 'linear',
      why: t("THE_SAME_PATTERNS_DIFFERENT_VARIATIONS_ENOUGH_OVERLAP_TO_PROGRESS_ENOUGH_DIFFERENCE_TO" /* 相同的模式，不同的变式：重叠得够多才能进步，差异够大才能保持新鲜。 */),
      ex: [
        mk(pick('upper legs', eq)?.id, null, 3, 10, t("SAME_PATTERN_HIGHER_REPS_THAN_DAY_A" /* 相同的动作模式，次数比 A 日更多。 */)),
        mk(pick('shoulders', eq)?.id, null, 3, 10, t("VERTICAL_PRESSING" /* 垂直推。 */)),
        mk(pick('upper arms', eq)?.id, null, 3, 12, t("DIRECT_ARM_WORK_SINCE_YOU_ASKED_FOR_IT" /* 直接的手臂训练，因为你要求了。 */))
      ].filter(e => e.id)
    }
  ]
  const week = {}
  days.forEach((d, i) => { week[d] = routines[i % routines.length].id })
  return {
    id: 'demo-plan', kind: 'create', createdAt: Date.now(), expiresAt: Date.now() + 864e5, iteration: 1,
    planHash: planHash(S),
    summary: t("A_TWO_DAY_ROTATION_ACROSS_THREE_SESSIONS_A_WEEK_BUILT_AROUND_THE" /* 根据你列出的器械，安排为每周三次训练、两天轮换。先做复合动作，每个推配一个拉，并让两天之间有足够的重叠，确保任何部位都不会两周得不到训练。 */),
    bundle: {
      opengym_plan: 1, name: t("COACH_PLAN" /* 教练计划 */),
      summary: t("A_TWO_DAY_ROTATION_ACROSS_THREE_SESSIONS_A_WEEK_BUILT_AROUND_THE" /* 根据你列出的器械，安排为每周三次训练、两天轮换。先做复合动作，每个推配一个拉，并让两天之间有足够的重叠，确保任何部位都不会两周得不到训练。 */),
      basedOn: (S.workouts || []).length ? t("BASED_ON_THE_TRAINING_ALREADY_IN_THIS_DEMO_PROFILE" /* 基于此演示档案中已有的训练。 */) : t("NO_TRAINING_HISTORY_YET_SO_STARTING_CONSERVATIVELY" /* 还没有训练记录，所以先保守开始。 */),
      week, routines, customEx: []
    }
  }
}

/** One session, read back with its own numbers — no plan changes, just what a coach would say after. */
function buildDebrief(S, workoutId) {
  const all = (S.workouts || []).filter(w => w && w.d)
  const w = all.find(x => x.id === workoutId) || all[all.length - 1]
  if (!w) return null
  // workoutVolume() reads `w.entries` and `e.sets` without a guard; every other line here
  // tolerates both being absent. A workout carrying a date and nothing else therefore threw
  // inside the timer below, where at the time nothing caught it — the job stayed 'running'
  // for ever and every later request answered 409.
  const entries = (w.entries || []).map(en => ({ ...en, sets: en.sets || [] }))
  const done = entries.reduce((n, en) => n + en.sets.filter(s => s.done && !isWarmupRow(s)).length, 0)
  const planned = entries.reduce((n, en) => n + en.sets.filter(s => !isWarmupRow(s)).length, 0)
  const vol = Math.round(Number.isFinite(w.vol) ? w.vol : workoutVolume({ ...w, entries }))
  const prs = (w.prs || []).length
  const minutes = w.end && w.start ? Math.round((w.end - w.start) / 60000) : null
  const complete = planned > 0 && done >= planned
  const score = complete ? (prs ? 9 : 8) : 7
  const highlights = [
    complete ? t("EVERY_PLANNED_SET_DONE_COUNT_OF_COUNT" /* 计划的组全部完成：{0}/{1}。 */, done, planned) : t("COUNT_OF_COUNT_PLANNED_SETS_DONE" /* 计划的 {1} 组已完成 {0} 组。 */, done, planned),
    t("COUNT_COUNT_MOVED_IN_TOTAL" /* 总共举起 {0} {1}。 */, fmtNum(vol), S.unit)
  ]
  if (prs) highlights.push(t("COUNT_NEW_PERSONAL_RECORDS" /* {0} 项新个人纪录。 */, prs))
  const watch = minutes && minutes > 80 ? [t("COUNT_MINUTES_IS_LONG_REST_PERIODS_MAY_BE_CREEPING_UP" /* {0} 分钟有点长了。组间休息可能在悄悄变长。 */, minutes)] : [t("TOP_SETS_LOGGED_WITHOUT_AN_EFFORT_RATING_ADD_RIR_SO_THE_NEXT" /* 主要组没有记录费力程度；加上 RIR，下次审查才知道有多吃力。 */)]
  const nextTime = [complete ? t("ADD_THE_NEXT_LOAD_STEP_ON_THE_MAIN_LIFT" /* 主项动作加到下一个重量档。 */) : t("REPEAT_THE_SAME_LOADS_AND_GET_EVERY_SET" /* 重复同样的重量，完成每一组。 */), t("KEEP_THE_SESSION_UNDER_AN_HOUR_AND_A_QUARTER" /* 把训练控制在一小时一刻钟以内。 */)]
  return {
    id: 'demo-debrief', kind: 'debrief', createdAt: Date.now(), expiresAt: Date.now() + 864e5,
    planHash: planHash(S), iteration: 1,
    workout: { id: w.id, d: w.d, name: w.name || null, minutes, vol, sets: done, prs },
    summary: complete
      ? t("A_CLEAN_SESSION_EVERYTHING_ON_THE_SHEET_GOT_DONE_AND_THE_LOADS" /* 一次干净的训练：计划上的都完成了，重量也守住了。从内部看，进步就是这个样子：平淡无奇，一再重复。 */)
      : t("MOST_OF_THE_WORK_GOT_DONE_ONE_OR_TWO_SETS_FELL_SHORT" /* 大部分都完成了。有一两组没达标，偶尔一次没关系。如果下次同样的组还没做到，那才是信号。 */),
    score, highlights, watch, nextTime
  }
}

/** What "the room" would say on a busy instance — five people, plausible medians, your real bests. */
export function demoCohort(S) {
  const since = Date.now() - 56 * 864e5
  const you = Math.round((S.workouts || []).filter(w => workoutAt(w) > since).length / 8 * 10) / 10
  const ids = [...new Set((S.routines || []).flatMap(r => (r.ex || []).map(e => e.id)))].slice(0, 5)
  const exercises = ids.map(id => {
    const b = best1RM(S, id)
    const mine = b ? Math.round(b.est * 10) / 10 : null
    return { id, name: EXIDX[id]?.n || id, people: 4, median: mine ? Math.round(mine * 0.92) : 60, you: mine }
  })
  return { ok: true, enabled: true, sharing: true, people: 5, minPeople: 3, unit: S.unit, sessionsPerWeek: { median: 3, you }, exercises, rankPct: 62 }
}

/* ---------------- the API surface the demo stands in for ---------------- */

export const demoStatus = () => ({ job, pending, cap: { used: 0, limit: 0 }, lastError })

function start(kind, make) {
  if (job) throw Object.assign(new Error(t("THE_COACH_IS_ALREADY_THINKING_ABOUT_YOUR_TRAINING" /* 教练已经在思考你的训练了。 */)), { status: 409 })
  job = { id: 'demo-' + kind, kind, state: 'running', startedAt: Date.now() }
  lastError = null
  clearTimeout(timer)
  // A builder that throws still has to end the job: left uncaught, one throw kept `job` at
  // 'running' for ever and every later request answered 409 until the page was reloaded. The
  // failure is recorded the way the server and the phone record theirs, so the chat's
  // job-ended effect writes the same error line it would for them. `nostate` because the only
  // thing a builder can trip over is the shape of the profile's own data.
  timer = setTimeout(() => {
    try { pending = make() }
    catch (e) { lastError = { errorClass: 'nostate', detail: String(e && e.message || e) } }
    finally { job = null }
  }, DELAY)
  return { job }
}
export const demoReview = S => {
  // Refused before the job starts, the way demoDebrief refuses with no workout: without a
  // two-exercise routine buildReview has nothing to aim at, and a job that runs the whole wait
  // and ends with neither a proposal nor an error reads as the Coach ignoring you.
  if (!reviewable(S)) throw Object.assign(new Error(t("THERE_S_NO_ROUTINE_TO_REVIEW_YET_BUILD_ONE_WITH_AT_LEAST" /* 还没有可点评的训练计划。先创建一个至少包含两个动作的计划。 */)), { status: 409, code: 'noroutine' })
  return start('review', () => buildReview(S))
}
export const demoPlan = (S, intake) => start('create', () => buildPlan(S, intake))
// A refine re-reads the saved answers, as the server's payload does when a refine carries no
// intake of its own (`opts.intake || coach.profile`). Built from nothing, every revised plan
// went back to Mon/Wed/Fri whatever days were chosen at intake.
export const demoRefine = S => start('create', () => {
  const p = buildPlan(S, S.coach?.profile || null)
  return { ...p, iteration: (pending?.iteration || 1) + 1, summary: t("REVISED_AS_YOU_ASKED_EVERYTHING_YOU_DID_NOT_QUESTION_IS_EXACTLY_AS" /* 已按你的要求修改。你没有提出疑问的部分完全保持原样。 */) + ' ' + p.summary }
})
export const demoDebrief = (S, workoutId) => {
  if (!(S.workouts || []).some(w => w && w.d)) throw Object.assign(new Error(t("THERE_S_NO_WORKOUT_TO_LOOK_AT_YET_LOG_ONE_FIRST" /* 还没有可查看的训练。先记录一次吧。 */)), { status: 409, code: 'noworkout' })
  return start('debrief', () => buildDebrief(S, workoutId))
}
export const demoResolve = () => { pending = null; return { ok: true } }
export const demoDisclosure = () => ({
  provider: 'demo', providerLabel: t("THE_CONFIGURED_AI_PROVIDER" /* 已配置的 AI 提供方 */),
  categories: ['plan', 'training', 'bodyweight', 'profile', 'prefs'], version: 1
})
