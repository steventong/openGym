import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t } from '../lib/i18n.js'
import { effortOf } from '../lib/history.js'
import { workoutControls } from '../lib/workout-controls.js'
import { unlock, vibrateSupported, appleTouchDevice } from '../lib/sound.js'
import { wakeLockSupported } from '../lib/wakelock.js'
import { MOBILE } from '../lib/mobile.js'
import { closeThenNav } from '../lib/nav.js'
import { REST_MAX, fmtRest } from '../lib/duration.js'
import { durationSheet } from './DurationWheel.jsx'
import { Section, Row, Switch, Segmented, Button } from './ui.jsx'

// The settings people touch at the gym, without leaving the workout (v1.3.11, opened from the
// workout's ⋯ → Workout settings). Every row writes the same S.* field as Settings → Workout and
// Settings → Timer alerts, so a change here sticks for the next session too; nothing in it is
// for this session only. The one exception to "same as Settings" is Layout: the running session
// may carry its own layout from the ⋯ menu (S.active.workoutView), and choosing one here clears
// that, or the saved choice would not show until the next workout.
export function WorkoutSettings({ close }) {
  const S = useStore(s => s.S)
  const update = useStore(s => s.update)
  const canVibrate = vibrateSupported()
  const iPhone = appleTouchDevice()
  const wakeOK = wakeLockSupported()
  const layout = ['list', 'compact'].includes(S.active?.workoutView || S.workoutView) ? (S.active?.workoutView || S.workoutView) : 'cards'
  const gif = S.gifSize === 'mini' || S.gifSize === 'off' ? S.gifSize : 'full'
  const allSettings = () => closeThenNav(close, '/settings/workout')
  return <div className="ws-sheet">
    <div className="row between" style={{ marginBottom: 2 }}>
      <h3 style={{ margin: 0 }}>{t("WORKOUT_SETTINGS" /* 训练设置 */)}</h3>
      <Button size="sm" variant="ghost" onClick={close}>{t("DONE" /* 完成 */)}</Button>
    </div>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("CHANGES_STICK_FOR_YOUR_NEXT_WORKOUTS_TOO" /* 更改也会用于你之后的训练。 */)}</div>
    <Section>
      <Row icon="timer" iconTint="var(--orange)" title={t("REST_TIMER" /* 休息计时 */)} value={fmtRest(S.restSec)} accessory="chevron"
        onClick={() => durationSheet({
          title: t("REST_TIMER" /* 休息计时 */), value: S.restSec, max: REST_MAX, off: t("OFF" /* 关 */),
          footer: t("SCROLL_TO_ZERO_ZEROZERO_TO_TURN_THE_REST_TIMER_OFF" /* 滚动到 0:00 即可关闭休息计时。 */),
          onDone: v => update(s => { s.restSec = v }),
        })} />
      <Row icon="speaker" iconTint="var(--pink)" title={t("PLAY_A_SOUND" /* 播放提示音 */)}>
        {/* A tap: unlock the audio now so a rest ending before the next tick can sound (iOS, #152). */}
        <Switch checked={!!S.sound} onChange={v => { if (v) unlock(true); update(s => { s.sound = v }) }} />
      </Row>
      <Row icon="vibrate" iconTint="var(--indigo)" title={t("VIBRATE" /* 振动 */)} className={canVibrate ? '' : 'dis'}
        subtitle={canVibrate ? null : iPhone ? t("NOT_ON_IPHONE" /* iPhone 不支持 */) : t("NOT_SUPPORTED_IN_THIS_BROWSER" /* 此浏览器不支持。 */)}>
        <Switch checked={canVibrate && S.vibrate !== false} disabled={!canVibrate} onChange={v => update(s => { s.vibrate = v })} />
      </Row>
      <Row icon="sun" iconTint="var(--yellow)" title={t("FLASH_THE_SCREEN" /* 闪烁屏幕 */)}>
        <Switch checked={!!S.timerFlash} onChange={v => update(s => { s.timerFlash = v })} />
      </Row>
      {(wakeOK || !MOBILE) && <Row icon="phoneScreen" iconTint="var(--yellow)" title={t("KEEP_SCREEN_AWAKE" /* 保持屏幕常亮 */)}
        subtitle={wakeOK ? t("THE_SCREEN_STAYS_ON_WHILE_A_WORKOUT_IS_RUNNING_SO_YOU_DON" /* 训练进行时屏幕保持常亮，组间无需再解锁手机。 */) : t("NOT_SUPPORTED_IN_THIS_BROWSER" /* 此浏览器不支持。 */)}>
        <Switch checked={wakeOK && S.keepAwake !== false} disabled={!wakeOK} onChange={v => update(s => { s.keepAwake = v })} />
      </Row>}
    </Section>
    <Section>
      <Row icon="layout" iconTint="var(--blue)" title={t("LAYOUT" /* 布局 */)}>
        <Segmented className="seg-inline"
          options={[{ value: 'cards', label: t("CARDS" /* 卡片 */) }, { value: 'list', label: t("LIST" /* 列表 */) }, { value: 'compact', label: t("COMPACT" /* 紧凑 */) }]}
          value={layout} onChange={v => update(s => { s.workoutView = v; if (s.active) delete s.active.workoutView })} />
      </Row>
      <Row icon="gauge" iconTint="var(--purple)" title={t("EFFORT_PER_SET" /* 每组强度 */)}>
        <Segmented className="seg-inline"
          options={[{ value: 'none', label: t("OFF" /* 关 */) }, { value: 'rir', label: t("RIR" /* 术语：RIR */) }, { value: 'rpe', label: t("RPE" /* 术语：RPE */) }]}
          value={effortOf(S)} onChange={v => update(s => { s.effort = v; delete s.showRir })} />
      </Row>
      <Row icon="swap" iconTint="var(--indigo)" title={t("SWIPE_ACTIONS" /* 滑动操作 */)} subtitle={t("SETS_ROUTINES_AND_THE_LOOP_LEFT_REMOVES_RIGHT_COPIES" /* 组、计划和循环：左滑移除，右滑复制 */)}>
        <Switch aria-label={t("SWIPE_ACTIONS" /* 滑动操作 */)} checked={workoutControls(S).swipeSets}
          onChange={v => update(s => { s.wc = { ...workoutControls(s), swipeSets: v } })} />
      </Row>
      <Row icon="image" iconTint="var(--teal)" title={t("EXERCISE_ANIMATIONS" /* 动作动画 */)}>
        <Segmented className="seg-inline"
          options={[{ value: 'full', label: t("FULL" /* 完整 */) }, { value: 'mini', label: t("SMALL" /* 小 */) }, { value: 'off', label: t("HIDDEN" /* 隐藏 */) }]}
          value={gif} onChange={v => update(s => { s.gifSize = v })} />
      </Row>
    </Section>
    <Section>
      <Row icon="gear" iconTint="var(--grey)" title={t("ALL_SETTINGS" /* 所有设置 */)} accessory="chevron" onClick={allSettings} />
    </Section>
  </div>
}

/** Opens the in-workout settings sheet. */
export function workoutSettingsSheet() {
  return useUI.getState().openSheet(close => <WorkoutSettings close={close} />)
}
