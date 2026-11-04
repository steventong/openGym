// Talking to the Coach endpoints, and knowing when to stop.
//
// Jobs are minutes-scale, so the client polls. The one rule worth stating: polling only runs
// while a Coach surface is on screen or a job is known to be in flight. An app that pings the
// server every thirty seconds forever because a feature exists is an app that costs battery
// for a feature nobody is using.

import { useEffect, useState, useCallback, useRef } from 'react'
import { api } from './api.js'
import { DEMO } from './demo.js'
import { MOBILE } from './mobile.js'
import { t, getLang } from './i18n.js'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'

const POLL_MS = 3000        // a job is running: often enough to feel live
const IDLE_MS = 60000       // a Coach screen is open but nothing is running

// The demo build has no backend, so it answers these locally with a canned proposal built
// from its own seeded profile (lib/coach-demo.js). Everything downstream — validation,
// staleness, apply, revert, the log — runs unchanged; only the provider is faked. The module
// is imported dynamically so none of it lands in a self-hosted bundle.
let demoMod = null
const demo = async () => (demoMod = demoMod || await import('./coach-demo.js'))
const S = () => useStore.getState().S
// Each request says which language the app is in: a profile that never picked one has no stored
// `lang` worth trusting — it is worked out per device (#303, lib/default-lang.js) — and the
// Coach should answer in what the person is reading.

// The mobile build's third answer: a phone that brought its own API key runs the Coach itself
// (lib/coach-local.js — the same core the server runs, imported lazily so the catalogue and the
// validator only ever load on a phone that chose this). A paired phone takes the api() branch
// like the web app does; nothing on the web or demo builds reaches this.
let localMod = null
const LOCAL = () => MOBILE && useStore.getState().coachLocal?.mode === 'byok'
const local = async () => {
  if (!localMod) {
    localMod = await import('./coach-local.js')
    // There is no admin card on a phone: the user is the operator, so failures go to them.
    localMod.setNotifier(ev => {
      const toast = useUI.getState().toast
      if (ev.kind === 'failed') toast(jobErrorText(ev.errorClass, ev.detail))
      else if (ev.kind === 'nochange') toast(t("NOTHING_TO_CHANGE_RIGHT_NOW_COUNT" /* 目前无需更改：{0} */, String(ev.reading || '').slice(0, 140)))
    })
  }
  return localMod
}

// The job this app last started and has not written a reply for yet. A run that fails before
// the first status poll — a provider refusing the connection answers in milliseconds — is never
// seen running, so "running, then gone" cannot be the only way the chat learns a run ended: it
// also compares the server's last outcome with the id the start request returned. Kept here,
// at module level, because the plan the intake asks for is started on another screen.
let awaited = null
const track = r => {
  if (r?.job?.id) awaited = r.job.id
  return r
}
export const awaitedJob = () => awaited
export const settleAwaited = id => { if (!id || awaited === id) awaited = null }

export const coachStatus = async () => DEMO ? (await demo()).demoStatus() : LOCAL() ? (await local()).localStatus() : api('/api/coach/status')
const _requestReview = async note => DEMO ? (await demo()).demoReview(S()) : LOCAL() ? (await local()).localReview(S(), note) : api('/api/coach/review', { method: 'POST', body: JSON.stringify({ note: note || '', lang: getLang() }) })
export const requestReview = (...a) => _requestReview(...a).then(track)
const _requestPlan = async intake => DEMO ? (await demo()).demoPlan(S(), intake) : LOCAL() ? (await local()).localPlan(S(), intake) : api('/api/coach/plan', { method: 'POST', body: JSON.stringify({ intake, lang: getLang() }) })
export const requestPlan = (...a) => _requestPlan(...a).then(track)
const _refinePlan = async text => DEMO ? (await demo()).demoRefine(S()) : LOCAL() ? (await local()).localRefine(S(), text) : api('/api/coach/plan', { method: 'POST', body: JSON.stringify({ refine: text, lang: getLang() }) })
export const refinePlan = (...a) => _refinePlan(...a).then(track)
const _requestDebrief = async workoutId => DEMO ? (await demo()).demoDebrief(S(), workoutId) : LOCAL() ? (await local()).localDebrief(S(), workoutId) : api('/api/coach/debrief', { method: 'POST', body: JSON.stringify({ workoutId: workoutId || null, lang: getLang() }) })
export const requestDebrief = (...a) => _requestDebrief(...a).then(track)
// The room: anonymous medians across the profiles on this instance that opted in. Only a
// server has a room; a phone with its own key and the demo both answer locally.
export const cohortStats = async () => DEMO ? (await demo()).demoCohort(S()) : LOCAL() ? { ok: false, enabled: false } : api('/api/coach/cohort')
export const setCohortShare = async share => (DEMO || LOCAL()) ? { ok: true, sharing: !!share } : api('/api/coach/cohort/share', { method: 'POST', body: JSON.stringify({ share: !!share }) })
export const resolvePending = async body => DEMO ? (await demo()).demoResolve() : LOCAL() ? (await local()).localResolve(body) : api('/api/coach/pending/resolve', { method: 'POST', body: JSON.stringify(body) })
export const forgetCoach = async () => DEMO ? (await demo()).demoResolve() : LOCAL() ? (await local()).localForget() : api('/api/coach/forget', { method: 'POST', body: '{}' })
export const disclosure = async () => DEMO ? (await demo()).demoDisclosure() : LOCAL() ? (await local()).localDisclosure() : api('/api/coach/disclosure')

/* Whose provider account this profile is about to spend. Its own call because the constraint is
   that the Coach screen states it too, not just the admin card — and because in instance mode a
   second profile is refused outright, which is something the user has to be able to read before
   they ask for anything rather than after a job is turned down. */
export const coachAccount = async () =>
  DEMO ? { mode: 'instance', provider: 'demo', providerLabel: 'Demo', account: null, connected: true, reason: null, message: null }
    : LOCAL() ? { mode: 'device', provider: useStore.getState().coachLocal.provider, providerLabel: null, account: null, connected: true, reason: null, message: null }
      : api('/api/coach/account')

/* Admin-only. The token is write-only from the client's side: it goes up once and is never
   read back, so there is deliberately no "show me the current credential" call to pair with it. */
export const connectCredential = body => api('/api/admin/coach/connect', { method: 'POST', body: JSON.stringify(body) })
export const disconnectCredential = () => api('/api/admin/coach/disconnect', { method: 'POST', body: '{}' })

/**
 * Live job/proposal state.
 *
 * `active` lets a caller (the Home card) subscribe only while it is mounted and visible;
 * everything else keeps the poll off. Errors are swallowed on purpose — a Coach status call
 * failing while you are mid-workout is not something to interrupt anyone about.
 */
export function useCoachStatus(active = true) {
  const [state, setState] = useState({ job: null, pending: null, cap: null, loading: true })
  const timer = useRef(null)
  const loop = useRef(null)   // the running poll loop's `tick`, so a manual refresh can re-pace it
  const seq = useRef(0)       // which status request is the newest one

  const refresh = useCallback(async () => {
    const mine = ++seq.current
    try {
      const s = await coachStatus()
      // An answer that arrives after a newer request was sent is older than what that request
      // will bring: the idle poll in flight when a run is started must not land after the
      // refresh that follows the start, putting back the run count and last outcome from before.
      if (mine !== seq.current) return s
      setState({ ...s, loading: false })
      // A refresh that finds a job in flight — the one the caller just started — must not leave
      // the loop asleep on its idle cadence: without this the card shows up to a minute after
      // the job ended, sitting on "thinking…" the whole time.
      if (s?.job && loop.current) { clearTimeout(timer.current); timer.current = setTimeout(loop.current, POLL_MS) }
      return s
    } catch {
      if (mine === seq.current) setState(s => ({ ...s, loading: false }))
      return null
    }
  }, [])

  useEffect(() => {
    if (!active) return
    let stopped = false
    const tick = async () => {
      const s = await refresh()
      if (stopped) return
      clearTimeout(timer.current)
      timer.current = setTimeout(tick, s?.job ? POLL_MS : IDLE_MS)
    }
    loop.current = tick
    tick()
    return () => { stopped = true; loop.current = null; clearTimeout(timer.current) }
  }, [active, refresh])

  return { ...state, refresh }
}

// Server failure classes, in the app's voice. The provider's own words go to the admin card;
// what a lifter needs is what it means for them and whether trying again will help.
//
// Each line is a getter, so it is translated when it is read, not when this module loads: the
// module loads once, in English, before any locale pack has arrived, and a language picked later
// would otherwise never reach these lines. The lookup is still JOB_ERRORS[cls].
export const JOB_ERRORS = {
  get off() { return t("THE_COACH_ISN_T_SET_UP_ON_THIS_INSTANCE" /* 此实例上尚未设置教练。 */) },
  get busy() { return t("THE_COACH_IS_ALREADY_THINKING_ABOUT_YOUR_TRAINING" /* 教练已经在思考你的训练了。 */) },
  get cap() { return t("THE_COACH_IS_TAKING_A_REST_DAY_TRY_AGAIN_TOMORROW" /* 教练今天放休息日。明天再试吧。 */) },
  get consent() { return t("THE_COACH_NEEDS_YOUR_GO_AHEAD_FIRST" /* 教练需要先获得你的同意。 */) },
  get timeout() { return t("THE_COACH_TOOK_TOO_LONG_AND_GAVE_UP" /* 教练耗时太久，已放弃。 */) },
  get auth() { return t("THE_COACH_COULDN_T_SIGN_IN_TO_ITS_PROVIDER_THE_INSTANCE_OWNER" /* 教练无法登录其提供商。需要实例所有者检查配置。 */) },
  get missing() { return t("THE_COACH_ISN_T_INSTALLED_PROPERLY_ON_THIS_INSTANCE" /* 此实例上的教练安装不正确。 */) },
  get provider() { return t("THE_COACH_COULDN_T_RUN_THE_INSTANCE_OWNER_NEEDS_TO_CHECK_ITS" /* 教练无法运行。需要实例所有者检查配置。 */) },
  get unusable() { return t("THE_COACH_ANSWERED_WITH_SOMETHING_THE_APP_COULDN_T_USE" /* 应用无法使用教练给出的回答。 */) },
  get restart() { return t("THE_SERVER_RESTARTED_WHILE_THE_COACH_WAS_THINKING" /* 教练思考时服务器重启了。 */) },
  get nostate() { return t("THE_COACH_COULDN_T_READ_YOUR_TRAINING_DATA" /* 教练无法读取你的训练数据。 */) },
  get noworkout() { return t("THERE_S_NO_WORKOUT_TO_LOOK_AT_YET_LOG_ONE_FIRST" /* 还没有可查看的训练。先记录一次吧。 */) },
  // The refusal at enqueue when the process cannot drop privileges (api/coach/jobs.js). The same
  // words as api/coach/routes.js USER_ERROR.unprivileged; what to fix goes to the admin card.
  get unprivileged() { return t("THE_COACH_IS_SWITCHED_OFF_ON_THIS_INSTANCE_FOR_SAFETY_REASONS" /* 出于安全原因，此实例已关闭教练。 */) },
  get internal() { return t("SOMETHING_WENT_WRONG_ON_THE_SERVER" /* 服务器出了点问题。 */) }
}

// The same failures on a phone that brought its own key: there is no instance owner to
// check anything, the person reading this is the operator, and the provider's own words
// are the only thing that lets them fix it (a spent quota, a wrong model, a rejected key).
export const BYOK_ERRORS = {
  get auth() { return t("YOUR_AI_PROVIDER_REJECTED_THE_KEY_ON_THIS_PHONE_CHECK_IT_UNDER" /* 你的 AI 提供商拒绝了此手机上的密钥。请在“设置 → AI 教练”中检查。 */) },
  get missing() { return t("THE_COACH_ISN_T_SET_UP_ON_THIS_PHONE_CHECK_SETTINGS_AI" /* 此手机上尚未设置教练。请查看“设置 → AI 教练”。 */) },
  get provider() { return t("YOUR_AI_PROVIDER_COULDN_T_ANSWER" /* 你的 AI 提供商未能给出回答。 */) },
  get unusable() { return t("THE_COACH_ANSWERED_WITH_SOMETHING_THE_APP_COULDN_T_USE" /* 应用无法使用教练给出的回答。 */) },
  get internal() { return t("SOMETHING_WENT_WRONG_ON_THIS_PHONE" /* 此手机上出了点问题。 */) }
}

/** The line the person sees for a failed job — with the reason attached where they can act on it. */
export function jobErrorText(cls, detail) {
  const own = LOCAL()
  const base = (own && BYOK_ERRORS[cls]) || JOB_ERRORS[cls] || (own ? BYOK_ERRORS.internal : JOB_ERRORS.internal)
  const why = own && detail ? String(detail).trim().slice(0, 300) : ''
  return why ? `${base}\n${why}` : base
}
