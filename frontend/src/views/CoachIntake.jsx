// The questionnaire — the first thing the Coach asks, the moment somebody first opens it.
//
// One question per screen, big targets, as little copy as the question allows. Only goal and
// experience are required; everything after them makes the plan better without gating it,
// and someone who wants to just get training can skip through. The consent disclosure is the
// first screen of this flow rather than a separate card, because "what leaves the server" is
// the first thing to know, not a setting to find later.
//
// `?edit=1` reuses every screen as the profile editor: consent is skipped, answers are
// prefilled, and the last button saves instead of building.
import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t , translateValue } from '../lib/i18n.js'
import { DAYN } from '../lib/format.js'
import { EXDB } from '../lib/exercises.js'
import { emptyCoach, coachAvailable, hasConsent, CONSENT_VERSION, CATEGORY_TEXT, appendChat } from '../lib/coach.js'
import { requestPlan, disclosure, JOB_ERRORS } from '../lib/coach-api.js'
import { DEMO } from '../lib/demo.js'
import { MOBILE } from '../lib/mobile.js'
import { activeProfile } from '../lib/equipment.js'
import Icon from '../components/Icon.jsx'
import { Button, TextArea } from '../components/ui.jsx'
import '../coach.css'

// Each choice's text returns [title, detail] in the current language, through literal t() calls
// so check-source-strings sees every key, as CATEGORY_TEXT in lib/coach.js does. When the screen
// passed these to t() as variables the checker could not see them, and the eight details had no
// translation in any pack.
const GOALS = [
  ['strength', () => [t("GET_STRONGER" /* 变得更强 */), t("HEAVIER_LIFTS_LOWER_REPS" /* 更大的重量，更少的次数。 */)], 'barbell'],
  ['muscle', () => [t("BUILD_MUSCLE" /* 增肌 */), t("VOLUME_AND_PROGRESSION" /* 训练量与进阶。 */)], 'arm'],
  ['general', () => [t("GENERAL_FITNESS" /* 综合体能 */), t("BALANCED_SUSTAINABLE_TRAINING" /* 均衡、可持续的训练。 */)], 'heart'],
  ['fatloss', () => [t("LOSE_FAT" /* 减脂 */), t("KEEP_STRENGTH_WHILE_LEANING_OUT" /* 减脂的同时保持力量。 */)], 'flame'],
  ['endurance', () => [t("ENDURANCE" /* 耐力 */), t("HIGHER_REPS_LESS_REST_CARDIO" /* 次数更多、休息更少，外加有氧。 */)], 'figureRun']
]
const EXPERIENCE = [
  ['new', () => [t("NEW_TO_LIFTING" /* 力量训练新手 */), t("FIRST_MONTHS_IN_THE_GYM" /* 刚进健身房的头几个月。 */)], 'sparkles'],
  ['returning', () => [t("COMING_BACK_AFTER_A_BREAK" /* 休息后回归 */), t("YOU_KNOW_THE_MOVEMENTS_THE_NUMBERS_NEED_REBUILDING" /* 动作你都熟悉；重量需要重新练回来。 */)], 'reset'],
  ['regular', () => [t("TRAINING_REGULARLY" /* 规律训练中 */), t("CONSISTENT_FOR_A_WHILE_NOW" /* 已经坚持一段时间了。 */)], 'trophy']
]

// Equipment options come from the library's own taxonomy, most common first, so every choice
// on screen has exercises behind it.
const EQUIPMENT = (() => {
  const count = {}
  EXDB.forEach(e => { if (e.eq) count[e.eq] = (count[e.eq] || 0) + 1 })
  return Object.keys(count).sort((a, b) => count[b] - count[a]).slice(0, 14)
})()

const QUICK_MIN = [30, 45, 60, 90]
const toHHMM = min => String(Math.floor(min / 60)).padStart(2, '0') + ':' + String(min % 60).padStart(2, '0')
const fromHHMM = v => { const [h, m] = String(v || '').split(':').map(Number); return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : null }

export default function CoachIntake() {
  const nav = useNavigate()
  const [params] = useSearchParams()
  const editing = params.get('edit') === '1'
  const S = useStore(s => s.S)
  const user = useStore(s => s.user)
  const config = useStore(s => s.config)
  const coachMode = useStore(s => s.coachLocal?.mode)
  const update = useStore(s => s.update)
  const toast = useUI(s => s.toast)
  const [needConsent] = useState(() => !editing && !hasConsent(S))
  // An athlete who already answered the intake and only lacks the CURRENT consent (the wording
  // changed and CONSENT_VERSION moved) reads the new terms and goes back to the Coach. Without
  // this the redirect from the chat replayed all seven questions and ended in a new plan request.
  const [reconsentOnly] = useState(() => !editing && !hasConsent(S) && !!S.coach?.profile)
  const STEPS = reconsentOnly ? ['consent'] : [...(needConsent ? ['consent'] : []), 'goal', 'experience', 'days', 'length', 'equipment', 'limits', 'extras']
  const [step, setStep] = useState(0)
  const [busy, setBusy] = useState(false)
  const [p, setP] = useState(() => ({
    goal: null, experience: null, daysPerWeek: 3, preferredDays: [1, 3, 5],
    // A home gym already set up under Settings → Equipment is the best first guess here.
    sessionMin: 60, equipment: (activeProfile(S)?.equipment || []).filter(e => EQUIPMENT.includes(e)), limitations: '', likes: '', dislikes: '', notes: '',
    ...(S.coach?.profile || {})
  }))
  const set = patch => setP(v => ({ ...v, ...patch }))

  if (!coachAvailable(config, user, { demo: DEMO, mobile: MOBILE, coachMode })) { nav('/home', { replace: true }); return null }

  const key = STEPS[step]
  const last = step === STEPS.length - 1
  const canNext = key === 'goal' ? !!p.goal : key === 'experience' ? !!p.experience : key === 'length' ? p.sessionMin >= 10 : true
  const optional = ['equipment', 'limits', 'extras'].includes(key)

  const next = () => (last ? finish() : setStep(step + 1))
  const back = () => (step ? setStep(step - 1) : nav(editing ? '/coach' : '/plan'))

  const agree = () => {
    update(s => { s.coach = { ...(s.coach || emptyCoach()), consent: { agreedAt: new Date().toISOString(), version: CONSENT_VERSION } } })
    if (reconsentOnly) nav('/coach', { replace: true })
    else setStep(step + 1)
  }

  const finish = async () => {
    // `??`, not `||`: only a missing answer takes the default. Nought is an answer, and the clamp
    // turns it into one day like every other count below the floor.
    const profile = { ...p, daysPerWeek: Math.min(7, Math.max(1, p.daysPerWeek ?? 3)) }
    update(s => {
      const c = (s.coach = s.coach || emptyCoach())
      c.profile = profile
      // The conversation opens with the answers — rendered from the profile, so an edit later
      // is reflected rather than duplicated. One intake line whoever is writing it: a first-timer
      // whose plan request failed presses the button again, and must not open the thread with
      // the questionnaire twice.
      if (!(c.chat || []).some(m => m.kind === 'intake')) appendChat(s, { role: 'user', kind: 'intake' })
    })
    if (editing) { toast(t("SAVED" /* 已保存 */)); nav('/coach'); return }
    setBusy(true)
    try {
      await requestPlan(profile)
      nav('/coach', { replace: true })
    } catch (e) {
      // The server's refusal is English with its class beside it; the class picks the line.
      toast(JOB_ERRORS[e.data?.code] || e.message || t("COULD_NOT_ASK_THE_COACH" /* 无法请求教练 */)); setBusy(false)
    }
  }

  const toggleDay = d => set({
    preferredDays: p.preferredDays.includes(d) ? p.preferredDays.filter(x => x !== d) : [...p.preferredDays, d].sort()
  })
  const toggleEq = e => set({
    equipment: p.equipment.includes(e) ? p.equipment.filter(x => x !== e) : [...p.equipment, e]
  })

  const dots = STEPS.filter(s => s !== 'consent')
  const dotIndex = dots.indexOf(key)

  return <div className="narrow ob">
    <div className="ob-top">
      <button className="iconbtn" onClick={back} aria-label={t("BACK_A" /* 返回 */)}><Icon name="chevronLeft" /></button>
      {key !== 'consent' && <div className="ob-dots">
        {dots.map((s, i) => <span key={s} className={'ob-dot' + (i === dotIndex ? ' on' : i < dotIndex ? ' done' : '')} />)}
      </div>}
      {optional && !last ? <button className="ob-skip" onClick={next}>{t("SKIP" /* 跳过 */)}</button> : <span style={{ width: 36 }} />}
    </div>

    <div className="ob-body">
      {key === 'consent' && <Consent onAgree={agree} onDecline={() => nav('/plan')} />}

      {key === 'goal' && <>
        <div className="ob-eyebrow">{t("YOUR_GOAL" /* 你的目标 */)}</div>
        <h1 className="ob-h">{t("WHAT_ARE_YOU_TRAINING_FOR" /* 你的训练目标是什么？ */)}</h1>
        <p className="ob-p">{t("THE_COACH_BUILDS_THE_WHOLE_PLAN_AROUND_THIS" /* 教练会围绕这一点制定整个计划。 */)}</p>
        <div className="ob-choices">
          {GOALS.map(([v, text, icon]) => { const [title, sub] = text(); return <Choice key={v} on={p.goal === v} icon={icon} title={title} sub={sub} onClick={() => set({ goal: v })} /> })}
        </div>
      </>}

      {key === 'experience' && <>
        <div className="ob-eyebrow">{t("EXPERIENCE" /* 经验 */)}</div>
        <h1 className="ob-h">{t("WHERE_ARE_YOU_STARTING_FROM" /* 你目前处于什么阶段？ */)}</h1>
        <p className="ob-p">{t("SETS_THE_PACE_OF_PROGRESSION_AND_HOW_MUCH_THE_COACH_ASSUMES_YOU" /* 决定进阶的节奏，以及教练默认你已掌握多少。 */)}</p>
        <div className="ob-choices">
          {EXPERIENCE.map(([v, text, icon]) => { const [title, sub] = text(); return <Choice key={v} on={p.experience === v} icon={icon} title={title} sub={sub} onClick={() => set({ experience: v })} /> })}
        </div>
      </>}

      {key === 'days' && <>
        <div className="ob-eyebrow">{t("SCHEDULE" /* 训练安排 */)}</div>
        <h1 className="ob-h">{t("HOW_MANY_DAYS_A_WEEK" /* 每周练几天？ */)}</h1>
        <p className="ob-p">{t("PICK_WHAT_YOU_WILL_ACTUALLY_KEEP_NOT_THE_BEST_WEEK_YOU_CAN" /* 选择你真正能坚持的，而不是你能想象的最完美的一周。 */)}</p>
        <div className="ob-days">
          {[1, 2, 3, 4, 5, 6, 7].map(n => <button key={n} className={'ob-day' + (p.daysPerWeek === n ? ' on' : '')} onClick={() => set({ daysPerWeek: n })}>{n}</button>)}
        </div>
        <div className="ob-sub">{t("WHICH_DAYS_SUIT_YOU_OPTIONAL" /* 哪几天比较合适？（可选） */)}</div>
        <div className="ob-week">
          {[1, 2, 3, 4, 5, 6, 0].map(d => <button key={d} className={'ob-wd' + (p.preferredDays.includes(d) ? ' on' : '')} onClick={() => toggleDay(d)}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(DAYN[d]).slice(0, 2)}</button>)}
        </div>
      </>}

      {key === 'length' && <>
        <div className="ob-eyebrow">{t("SESSION_LENGTH" /* 训练时长 */)}</div>
        <h1 className="ob-h">{t("HOW_LONG_IS_A_SESSION" /* 一次训练多长时间？ */)}</h1>
        <p className="ob-p">{t("THE_COACH_FITS_THE_VOLUME_TO_THE_TIME_YOU_ACTUALLY_HAVE_INCLUDING" /* 教练会把训练量控制在你实际拥有的时间内，包括组间休息。 */)}</p>
        {/* A duration, not a clock time — so two wheels (hours, minutes in fives), never the
            native time input, which insists on AM/PM. */}
        <div className="ob-time" role="group" aria-label={t("HOW_LONG_IS_A_SESSION" /* 一次训练多长时间？ */)}>
          <select className="ob-wheel" value={Math.floor((p.sessionMin || 60) / 60)}
            onChange={e => set({ sessionMin: (+e.target.value) * 60 + ((p.sessionMin || 60) % 60) || 5 })}>
            {[0, 1, 2, 3].map(h => <option key={h} value={h}>{String(h).padStart(2, '0')}</option>)}
          </select>
          <span className="ob-time-sep">:</span>
          <select className="ob-wheel" value={(p.sessionMin || 60) % 60}
            onChange={e => set({ sessionMin: Math.floor((p.sessionMin || 60) / 60) * 60 + (+e.target.value) || 5 })}>
            {[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55].map(m => <option key={m} value={m}>{String(m).padStart(2, '0')}</option>)}
          </select>
          <span className="ob-time-l">{t("H_MM" /* 时:分 */)}</span>
        </div>
        <div className="ob-quick">
          {QUICK_MIN.map(m => <button key={m} className={'chip' + (p.sessionMin === m ? ' on' : '')} onClick={() => set({ sessionMin: m })}>{m} {t("MIN" /* 分钟 */)}</button>)}
        </div>
      </>}

      {key === 'equipment' && <>
        <div className="ob-eyebrow">{t("EQUIPMENT" /* 器械 */)}</div>
        <h1 className="ob-h">{t("WHAT_CAN_YOU_TRAIN_WITH" /* 你有哪些器材？ */)}</h1>
        <p className="ob-p">{t("PICK_EVERYTHING_YOU_HAVE_ACCESS_TO_LEAVE_IT_EMPTY_AND_THE_COACH" /* 选择你能用到的一切。若留空，教练将使用整个动作库。 */)}</p>
        <div className="ob-chips">
          {EQUIPMENT.map(e => <button key={e} className={'chip' + (p.equipment.includes(e) ? ' on' : '')} onClick={() => toggleEq(e)}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(e)}</button>)}
        </div>
      </>}

      {key === 'limits' && <>
        <div className="ob-eyebrow">{t("LIMITS" /* 限制 */)}</div>
        <h1 className="ob-h">{t("ANYTHING_TO_WORK_AROUND" /* 有什么需要避开的吗？ */)}</h1>
        <p className="ob-p">{t("INJURIES_JOINTS_THAT_COMPLAIN_MOVEMENTS_YOU_CANNOT_DO_OR_PRACTICAL_LIMITS_LIKE" /* 伤病、不舒服的关节、做不了的动作，或是现实限制，比如清晨六点在公寓里训练。 */)}</p>
        <div className="ob-field">
          <TextArea rows={4} maxLength={600} value={p.limitations} onChange={e => set({ limitations: e.target.value })}
            placeholder={t("E_G_DODGY_LEFT_SHOULDER_NO_BARBELL_OVERHEAD_PRESS" /* 例如“左肩不太好，不做杠铃过顶推举” */)} />
        </div>
        <div className="ob-note warn">{t("IF_SOMETHING_ACTUALLY_HURTS_SEE_A_PROFESSIONAL_THE_COACH_WILL_PROGRAM_CONSERVATIVELY" /* 如果确实疼痛，请去看专业人士。教练会保守地安排，但它无法诊断任何问题。 */)}</div>
      </>}

      {key === 'extras' && <>
        <div className="ob-eyebrow">{t("ALMOST_THERE" /* 快完成了 */)}</div>
        <h1 className="ob-h">{t("ANYTHING_ELSE" /* 还有别的吗？ */)}</h1>
        <p className="ob-p">{t("ALL_OPTIONAL_THE_MORE_THE_COACH_KNOWS_THE_LESS_IT_GUESSES" /* 全部可选。教练了解得越多，猜测就越少。 */)}</p>
        <div className="ob-sub" style={{ marginTop: 0 }}>{t("EXERCISES_YOU_LOVE" /* 你喜欢的动作 */)}</div>
        <div className="ob-field"><TextArea rows={2} maxLength={300} value={p.likes} onChange={e => set({ likes: e.target.value })} placeholder={t("E_G_DEADLIFTS_ANYTHING_WITH_A_KETTLEBELL" /* 例如「硬拉，任何壶铃动作」 */)} /></div>
        <div className="ob-sub" style={{ marginTop: 4 }}>{t("EXERCISES_YOU_WOULD_RATHER_NOT" /* 你不太想做的动作 */)}</div>
        <div className="ob-field"><TextArea rows={2} maxLength={300} value={p.dislikes} onChange={e => set({ dislikes: e.target.value })} placeholder={t("E_G_I_HATE_LUNGES" /* 例如「我讨厌箭步蹲」 */)} /></div>
        <div className="ob-sub" style={{ marginTop: 4 }}>{t("ANYTHING_YOU_WANT_THE_COACH_TO_KNOW" /* 还想让教练知道的事 */)}</div>
        <div className="ob-field"><TextArea rows={3} maxLength={600} value={p.notes} onChange={e => set({ notes: e.target.value })} placeholder={t("E_G_I_WANT_VISIBLE_ARMS_PROGRESS_BY_SPRING" /* 例如「希望到春天手臂有明显进步」 */)} /></div>
      </>}
    </div>

    {key !== 'consent' && <div className="ob-foot">
      <Button variant="primary" style={{ flex: 1 }} disabled={!canNext || busy} icon={last ? 'sparkles' : undefined} onClick={next}>
        {last ? (editing ? t("SAVE" /* 保存 */) : t("BUILD_MY_PLAN" /* 制定我的计划 */)) : t("CONTINUE" /* 继续 */)}
      </Button>
    </div>}
    {(key === 'goal' || key === 'experience') && !canNext && <div className="ob-hint">{t("PICK_ONE_TO_CONTINUE" /* 选择一项以继续。 */)}</div>}
  </div>
}

function Choice({ on, icon, title, sub, onClick }) {
  return <button className={'ob-choice' + (on ? ' on' : '')} onClick={onClick}>
    <Icon name={icon} />
    <span className="ob-choice-t">{title}{sub && <span className="ob-choice-s">{sub}</span>}</span>
    <Icon name="check" className="ob-k" />
  </button>
}

/* The disclosure: what leaves, where to, who pays. Rendered from the same category list the
   payload is built from, so the promise on screen cannot drift from what actually goes. */
function Consent({ onAgree, onDecline }) {
  const config = useStore(s => s.config)
  const [info, setInfo] = useState(null)
  useEffect(() => { disclosure().then(setInfo).catch(() => {}) }, [])
  const who = info?.payer === 'you'
    ? t("SENT_STRAIGHT_TO_COUNT_WITH_YOUR_OWN_API_KEY_YOU_PAY_FOR" /* 使用你自己的 API 密钥直接发送到 {0}。每个请求的费用都由你承担。 */, info.host || info.providerLabel)
    : t("SENT_TO_COUNT_RUNNING_ON_THIS_SERVER_UNDER_THE_INSTANCE_OWNER_S" /* 发送到在此服务器上以实例所有者账户运行的 {0}。 */, info?.providerLabel || config?.coach?.providerLabel || t("THE_CONFIGURED_AI_PROVIDER" /* 已配置的 AI 提供方 */))
  return <>
    <div className="ob-eyebrow">{t("BEFORE_WE_START" /* 开始之前 */)}</div>
    <h1 className="ob-h">{t("MEET_THE_COACH" /* 认识教练 */)}</h1>
    <p className="ob-p">{t("IT_DESIGNS_YOUR_PLAN_FROM_A_FEW_ANSWERS_AND_ADJUSTS_IT_FROM" /* 它根据几个回答设计你的计划，并根据你的实际记录进行调整。未经你同意它不会更改任何内容，每项更改都可以撤销。 */)}</p>
    <div className="ob-sub" style={{ marginTop: 0 }}>{t("WHAT_IT_READS" /* 它会读取什么 */)}</div>
    <div className="ob-consent">
      {(info?.categories || Object.keys(CATEGORY_TEXT)).map(k => {
        const [title, sub] = CATEGORY_TEXT[k]?.() || [k, '']
        return <div key={k} className="ob-consent-row"><Icon name="check" /><div><b>{title}</b><span>{sub}</span></div></div>
      })}
    </div>
    <div className="ob-fine">
      <div>{who}</div>
      <div>{t("YOUR_NAME_YOUR_SIGN_IN_DETAILS_AND_EVERYTHING_ELSE_ABOUT_YOUR_ACCOUNT" /* 你的姓名、登录信息以及账号的其他一切都留在本地，绝不会包含他人的数据。 */)}</div>
      <div style={{ color: 'var(--yellow)' }}>{t("THE_COACH_IS_NOT_A_DOCTOR_OR_A_PHYSIOTHERAPIST_IF_SOMETHING_HURTS" /* 教练不是医生或物理治疗师。如果哪里疼，请咨询专业人士。 */)}</div>
    </div>
    <div className="ob-foot" style={{ flexDirection: 'column' }}>
      <Button variant="primary" onClick={onAgree}>{t("I_UNDERSTAND_LET_S_GO" /* 明白了，开始吧 */)}</Button>
      <Button onClick={onDecline}>{t("NOT_NOW" /* 暂不 */)}</Button>
    </div>
  </>
}
