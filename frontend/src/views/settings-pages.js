import { englishText } from '../lib/i18n-core.js'
// Settings (v1.3.11): which page each row lives on, and the index the search field reads.
//
// The root holds eleven rows in four groups plus the account card; each opens a page at
// /settings/<page>. Rare things hang one level further down (Workout → Fine-tuning). Titles here
// are shared JSON keys the pages render with t(), so a search hit can find its row on the page
// by the same text and flash it (views/Settings.jsx). settings-pages.test.jsx renders every page
// and checks that each entry below really is a row there.
import { t } from '../lib/i18n.js'
import { ACCENT_NAMES } from '../lib/format.js'

export const PAGES = {
  workout: { title: "WORKOUT" /* 训练 */, icon: 'play', tint: 'var(--green)' },
  alerts: { title: "TIMER_ALERTS" /* 计时提醒 */, icon: 'speaker', tint: 'var(--pink)' },
  reminders: { title: "REMINDERS" /* 提醒 */, icon: 'bell', tint: 'var(--red)' },
  plan: { title: "PLAN_SCHEDULE" /* 计划与安排 */, icon: 'calendar', tint: 'var(--orange)' },
  units: { title: "UNITS_LANGUAGE" /* 单位与语言 */, icon: 'ruler', tint: 'var(--teal)' },
  equipment: { title: "EQUIPMENT" /* 器械 */, icon: 'kettlebell', tint: 'var(--indigo)' },
  look: { title: "LOOK_HOME" /* 外观与首页 */, icon: 'palette', tint: 'var(--purple)' },
  coach: { title: "AI_COACH" /* AI 教练 */, icon: 'sparkles', tint: 'var(--green)' },
  data: { title: "DATA_BACKUP" /* 数据与备份 */, icon: 'folder', tint: 'var(--blue)' },
  about: { title: "ABOUT_UPDATES" /* 关于与更新 */, icon: 'info', tint: 'var(--grey)' },
  account: { title: "ACCOUNT" /* 账号 */, icon: 'personCircle', tint: 'var(--grey)' },
  advanced: { title: "FINE_TUNING" /* 细节调整 */, icon: 'wrench', tint: 'var(--grey)', parent: 'workout' },
}
export const PAGE_IDS = Object.keys(PAGES)

// The root, top to bottom. Whether a row shows is pageVisible's call.
export const ROOT_GROUPS = [['workout', 'alerts', 'reminders'], ['plan', 'units', 'equipment'], ['look', 'coach'], ['data', 'about']]

/**
 * Whether a page exists for this device and profile. Reminders need a push server (signed in) or
 * the phone's own notifications; the Coach page is the phone's Coach setup (the web app's Coach
 * runs on the server, set up by its admin).
 */
export function pageVisible(page, ctx) {
  if (page === 'reminders') return !!(ctx.user || ctx.mobile)
  if (page === 'coach') return !!ctx.mobile
  return page in PAGES
}

// One entry per row. `kw` is extra words people search for (English; the translated title and
// page name are searched too). `opts` are the English labels of a segmented or picker row's
// choices, searched in both languages, so "Dunkel" finds Theme; `tkw` is a word in the app's own
// language for a row whose title does not say it ("Wochenstart"). `when` repeats the row's own visibility rule, so a search never
// offers a row the page would not show. The one rule a search cannot know in advance is whether
// this browser's push subscription is on (the server is asked when the page opens): those rows
// name `via`, the row the hit flashes instead when they turn out not to be there.
const signedInWeb = c => !!c.user && !c.mobile && !c.demo
// The reminder rows: the phone's own notifications, or web push where the browser has it.
const remind = c => !!c.mobile || !!c.pushOK
const PUSH = "PUSH_NOTIFICATIONS" /* 推送通知 */
export const SEARCH = [
  // Workout
  { page: 'workout', title: "REST_TIMER" /* 休息计时 */, icon: 'timer', tint: 'var(--orange)', kw: 'rest pause break seconds minutes timer countdown' },
  { page: 'workout', title: "REST_PAUSE_REST" /* 休息暂停组内休息 */, icon: 'bolt', tint: 'var(--orange)', kw: 'burst cluster rest pause' },
  { page: 'workout', title: "EFFORT_PER_SET" /* 每组强度 */, icon: 'gauge', tint: 'var(--purple)', kw: 'rir rpe effort reps in reserve difficulty', opts: ["RIR" /* 术语：RIR */, "RPE" /* 术语：RPE */] },
  { page: 'workout', title: "SHOWN_UNDER_EACH_EXERCISE" /* 每个动作下方显示 */, icon: 'history', tint: 'var(--blue)', kw: 'last time best set reference previous', opts: ["LAST_TIME" /* 上次 */, "BEST_SET" /* 最佳组 */] },
  { page: 'workout', title: "LAYOUT" /* 布局 */, icon: 'layout', tint: 'var(--blue)', kw: 'workout view cards list compact', opts: ["CARDS" /* 卡片 */, "LIST" /* 列表 */, "COMPACT" /* 紧凑 */] },
  { page: 'workout', title: "COLLAPSE_COMPLETED_EXERCISES" /* 折叠已完成的动作 */, icon: 'minimize', tint: 'var(--teal)', kw: 'collapse fold minimize hide done finished completed exercises list compact remaining left to do' },
  { page: 'workout', title: "WEIGH_IN_BEFORE_WORKOUTS" /* 训练前称重 */, icon: 'scale', tint: 'var(--green)', kw: 'body weight weigh scale start' },
  { page: 'workout', title: "KEEP_SCREEN_AWAKE" /* 保持屏幕常亮 */, icon: 'phoneScreen', tint: 'var(--yellow)', kw: 'wake lock screen sleep display on', when: c => c.wakeOK || !c.mobile },
  { page: 'workout', title: "EXERCISE_ANIMATIONS" /* 动作动画 */, icon: 'image', tint: 'var(--teal)', kw: 'gif animation video media pictures images', opts: ["FULL" /* 完整 */, "SMALL" /* 小 */, "HIDDEN" /* 隐藏 */] },
  { page: 'workout', title: "FINE_TUNING" /* 细节调整 */, icon: 'wrench', tint: 'var(--grey)', kw: 'advanced more options' },
  // Fine-tuning
  { page: 'advanced', title: "PLANNED_SESSIONS_START_FROM" /* 计划训练的起点 */, icon: 'clipboard', tint: 'var(--green)', kw: 'start from plan last session reps carry over', opts: ["YOUR_PLAN" /* 你的计划 */, "YOUR_LAST_SESSION" /* 你的上次训练 */] },
  { page: 'advanced', title: "KEEP_TIMING_AFTER_TARGET" /* 达到目标后继续计时 */, icon: 'stopwatch', tint: 'var(--orange)', kw: 'timed set overtime hold duration' },
  { page: 'advanced', title: "WEIGHT_AND_REPS_BUTTONS" /* 重量和次数的 +/− 按钮 */, icon: 'plusCircle', tint: 'var(--green)', kw: 'steppers plus minus buttons workout controls' },
  { page: 'advanced', title: "DROP_AND_BURST_SHORTCUTS_ON_EVERY_SET" /* 每组显示递减/休息暂停快捷按钮 */, icon: 'bolt', tint: 'var(--orange)', kw: 'drop set burst shortcuts workout controls' },
  { page: 'advanced', title: "SWIPE_ACTIONS" /* 滑动操作 */, icon: 'swap', tint: 'var(--indigo)', kw: 'swipe gesture slide delete remove copy duplicate set routine loop plan workout controls', tkw: () => t("SWIPE_GESTURE" /* 滑动 手势 */) },
  { page: 'advanced', title: "EXERCISE_CHIPS_AT_THE_TOP" /* 顶部动作圆点 */, icon: 'more', tint: 'var(--mint)', kw: 'chips dots overview progress jump navigate exercise list workout controls' },
  { page: 'advanced', title: "SUPERSET_BUTTONS_IN_THE_EXERCISE_HEADER" /* 动作标题中的超级组按钮 */, icon: 'link', tint: 'var(--blue)', kw: 'superset pair workout controls' },
  { page: 'advanced', title: "MOVE_SWAP_AND_REMOVE_BUTTONS_BELOW_THE_EXERCISE" /* 动作下方的移动、替换和删除按钮 */, icon: 'swap', tint: 'var(--teal)', kw: 'move swap remove replace workout controls' },
  // Timer alerts
  { page: 'alerts', title: "PLAY_A_SOUND" /* 播放提示音 */, icon: 'speaker', tint: 'var(--pink)', kw: 'sound sounds audio beep chime volume' },
  { page: 'alerts', title: "SOUND" /* 提示音 */, icon: 'bell', tint: 'var(--pink)', kw: 'classic timer sound beep chime tone bell whistle soft ringtone custom rest end', opts: ["CHIME_LOUDER" /* 铃声（更响） */, "CLASSIC_BEEPS" /* 经典哔声 */, "BELL" /* 铃声 */, "BEEP_BEEP" /* 哔哔 */, "WHISTLE" /* 哨子 */, "SOFT" /* 柔和 */], when: c => c.sound },
  { page: 'alerts', title: "PLAY_EVEN_ON_SILENT" /* 静音时也播放 */, icon: 'speaker', tint: 'var(--orange)', kw: 'silent mute ring switch iphone music', when: c => c.sound && c.playOnSilent },
  { page: 'alerts', title: "VIBRATE" /* 振动 */, icon: 'vibrate', tint: 'var(--indigo)', kw: 'vibrate vibration haptic haptics buzz' },
  { page: 'alerts', title: "VIBRATE_ON_SILENT_TOO" /* 静音时也振动 */, icon: 'vibrate', tint: 'var(--indigo)', kw: 'alarm silent vibrate android', when: c => c.mobile && c.android && c.canVibrate && c.vibrate },
  { page: 'alerts', title: "FLASH_THE_SCREEN" /* 闪烁屏幕 */, icon: 'sun', tint: 'var(--yellow)', kw: 'flash light blink screen' },
  // Reminders
  { page: 'reminders', title: PUSH, icon: 'bell', tint: 'var(--red)', kw: 'push notification alerts', when: c => !c.mobile && !!c.user && c.pushOK },
  { page: 'reminders', title: "WORKOUT_DAY_REMINDER" /* 训练日提醒 */, icon: 'calendar', tint: 'var(--orange)', kw: 'reminder notification remind', when: remind, via: PUSH },
  { page: 'reminders', title: "REMINDER_TIME" /* 提醒时间 */, icon: 'clock', tint: 'var(--purple)', kw: 'reminder time clock hour when', when: c => remind(c) && c.reminderOn, via: PUSH },
  { page: 'reminders', title: "NUDGE_ME_WHEN_I_SKIP_A_PLANNED_WORKOUT" /* 跳过计划训练时提醒我 */, icon: 'bell', tint: 'var(--red)', kw: 'nudge skip missed motivation', when: c => remind(c) && c.reminderOn, via: PUSH },
  { page: 'reminders', title: "NUDGE_TONE" /* 提醒语气 */, icon: 'chat', tint: 'var(--blue)', kw: 'nudge tone friendly guilt drill sergeant', opts: ["FRIENDLY" /* 友好 */, "GUILT_TRIP" /* 情感攻势 */, "DRILL_SERGEANT" /* 魔鬼教官 */], when: c => remind(c) && c.reminderOn && c.nudge, via: PUSH },
  { page: 'reminders', title: "SEND_TEST_NOTIFICATION" /* 发送测试通知 */, icon: 'bell', tint: 'var(--red)', kw: 'test push notification try', when: c => !c.mobile && c.pushOK, via: PUSH },
  // Plan & schedule
  { page: 'plan', title: "HOW_YOU_TRAIN" /* 训练方式 */, icon: 'repeat', tint: 'var(--orange)', kw: 'scheduling schedule rotation fixed week split loop round cycle', opts: ["FIXED_WEEK" /* 固定周 */, "ROTATION" /* 轮换 */] },
  { page: 'plan', title: "WEEK_STARTS_ON" /* 一周开始于 */, icon: 'calendar', tint: 'var(--orange)', kw: 'monday sunday first day week', opts: ["MONDAY" /* 星期一 */, "SUNDAY" /* 星期日 */], tkw: () => t("WEEK_START" /* 每周开始 */) },
  { page: 'plan', title: "LOAD_STARTER_PLAN" /* 加载入门计划 */, icon: 'clipboard', tint: 'var(--green)', kw: 'starter template beginner program routine' },
  // Units & language
  { page: 'units', title: "LANGUAGE" /* 语言 */, icon: 'globe', tint: 'var(--blue)', kw: 'language translation idioma sprache langue lingua' },
  { page: 'units', title: "ENGLISH_EXERCISE_NAMES" /* 英文动作名称 */, icon: 'globe', tint: 'var(--purple)', kw: 'exercise names english translation', when: c => c.nameLang },
  { page: 'units', title: "ENGLISH_NAMES_ONLY" /* 仅使用英文名称 */, icon: 'globe', tint: 'var(--purple)', kw: 'exercise names english translation', when: c => c.nameLang },
  { page: 'units', title: "WEIGHT_UNIT" /* 重量单位 */, icon: 'scale', tint: 'var(--teal)', kw: 'kg lb lbs pounds kilos kilograms unit' },
  { page: 'units', title: "WEIGHT_DECIMALS" /* 重量小数位 */, icon: 'ruler', tint: 'var(--teal)', kw: 'decimals precision microplates rounding' },
  { page: 'units', title: "SPEED_UNIT" /* 速度单位 */, icon: 'figureRun', tint: 'var(--teal)', kw: 'speed mph kmh km/h miles cardio' },
  { page: 'units', title: "ONE_REP_MAX_FORMULA" /* 1RM 公式 */, icon: 'chart', tint: 'var(--teal)', kw: '1rm one rep max epley brzycki lombardi formula estimate' },
  // Equipment
  { page: 'equipment', title: "PLATES" /* 杠铃片 */, icon: 'plate', tint: 'var(--orange)', kw: 'plates bar plate math barbell' },
  { page: 'equipment', title: "DUMBBELLS" /* 哑铃 */, icon: 'dumbbell', tint: 'var(--teal)', kw: 'dumbbells dumbbell rack inventory adjustable weights own home gym' },
  { page: 'equipment', title: "FILTER_BY_EQUIPMENT" /* 按器械筛选 */, icon: 'kettlebell', tint: 'var(--green)', kw: 'equipment filter home gym', when: c => c.profiles },
  { page: 'equipment', title: "ACTIVE_PROFILE" /* 当前配置 */, icon: 'house', tint: 'var(--blue)', kw: 'equipment profile home gym', when: c => c.profiles },
  { page: 'equipment', title: "ADD_EQUIPMENT_PROFILE" /* 添加器械配置 */, icon: 'plusCircle', tint: 'var(--green)', kw: 'equipment profile home gym hotel' },
  // Look & Home
  { page: 'look', title: "THEME" /* 主题 */, icon: 'moon', tint: 'var(--indigo)', kw: 'dark mode light mode theme appearance night', opts: ["DARK" /* 深色 */, "LIGHT" /* 浅色 */, "SYSTEM" /* 跟随系统 */] },
  { page: 'look', title: "ACCENT_COLOR" /* 强调色 */, icon: 'palette', tint: 'var(--purple)', kw: 'color colour accent tint custom own picker hex rgb', opts: [...Object.values(ACCENT_NAMES), "YOUR_OWN_COLOR" /* 你自己的颜色 */], tkw: () => t("CUSTOM_COLOR_PICKER" /* 自定义颜色 自己的颜色 取色器 调色板 */) },
  { page: 'look', title: "BODY_DIAGRAM" /* 身体图示 */, icon: 'figureStrength', tint: 'var(--teal)', kw: 'muscle map body male female', opts: ["MALE" /* 男性 */, "FEMALE" /* 女性 */] },
  { page: 'look', title: "EXERCISE_DRAWINGS" /* 动作图示 */, icon: 'figureStrength', tint: 'var(--teal)', kw: 'figure male female woman man picture', opts: ["MALE" /* 男性 */, "FEMALE" /* 女性 */] },
  { page: 'look', title: "GYM_CHECK_IN" /* 健身房签到 */, icon: 'qr', tint: 'var(--blue)', kw: 'qr code membership card check in barcode' },
  { page: 'look', title: "BODY_WEIGHT" /* 体重 */, icon: 'scale', tint: 'var(--green)', kw: 'weight card home' },
  { page: 'look', title: "SHOW_CONNECTION_STATUS" /* 显示连接状态 */, icon: 'cloud', tint: 'var(--blue)', kw: 'sync offline banner bar connection', when: c => !c.demo },
  // Data & backup
  { page: 'data', title: "EXPORT_BACKUP_JSON" /* 导出备份（JSON） */, icon: 'share', tint: 'var(--blue)', kw: 'export backup json download save' },
  { page: 'data', title: "EXPORT_WITH_PHOTOS_VIDEOS_ZIP" /* 连同照片和视频导出（.zip） */, icon: 'share', tint: 'var(--blue)', kw: 'zip media export backup', when: c => c.hasMedia },
  { page: 'data', title: "AUTO_BACKUP_ON_CHANGES" /* 变更时自动备份 */, icon: 'folder', tint: 'var(--blue)', kw: 'auto backup automatic', when: c => c.mobile },
  { page: 'data', title: "BACKUP_FOLDER" /* 备份文件夹 */, icon: 'folder', tint: 'var(--blue)', kw: 'auto backup folder location directory', when: c => c.mobile && c.android && c.autoBackup },
  { page: 'data', title: "IMPORT_BACKUP" /* 导入备份 */, icon: 'download', tint: 'var(--teal)', kw: 'import restore backup json zip' },
  { page: 'data', title: "IMPORT_FROM_ANOTHER_APP" /* 从其他应用导入 */, icon: 'download', tint: 'var(--teal)', kw: 'strong hevy fitnotes apple health csv import' },
  { page: 'data', title: "IMPORT_FROM_HEVY" /* 从 Hevy 导入 */, icon: 'key', tint: 'var(--teal)', kw: 'hevy api import' },
  { page: 'data', title: "PHOTOS_VIDEOS" /* 照片和视频 */, icon: 'image', tint: 'var(--teal)', kw: 'media storage photos videos upload', when: c => c.hasMedia },
  { page: 'data', title: "RESET_EVERYTHING_A" /* 重置所有内容 */, icon: 'trash', tint: 'var(--red)', kw: 'delete wipe reset erase' },
  // About & updates
  { page: 'about', title: "CHECK_FOR_UPDATES" /* 检查更新 */, icon: 'download', tint: 'var(--green)', kw: 'update apk android version', when: c => c.mobile && c.android },
  { page: 'about', title: "GET_THE_ANDROID_APP" /* 获取 Android 应用 */, icon: 'download', tint: 'var(--green)', kw: 'apk android download app', when: c => !c.mobile },
  { page: 'about', title: "VERSION" /* 版本 */, icon: 'info', tint: 'var(--grey)', kw: 'version about licence license source code open source' },
  { page: 'about', title: "IN_CHROME_MENU_ADD_TO_HOME_SCREEN" /* 在 Chrome 中：⋮ 菜单 → 添加到主屏幕 */, icon: 'share', tint: 'var(--blue)', kw: 'install app home screen tip pwa', when: c => c.installTip && c.androidWeb },
  { page: 'about', title: "IN_SAFARI_SHARE_ADD_TO_HOME_SCREEN" /* 在 Safari 中：分享 → 添加到主屏幕 */, icon: 'share', tint: 'var(--blue)', kw: 'install app home screen tip pwa', when: c => c.installTip && !c.androidWeb },
  // Account
  { page: 'account', title: "SYNC_NOW" /* 立即同步 */, icon: 'reset', tint: 'var(--acc)', kw: 'server sync upload refresh status connection', when: c => !!c.user && !c.demo && c.synced },
  { page: 'account', title: "PASSKEYS" /* 通行密钥 */, icon: 'fingerprint', tint: 'var(--acc)', kw: 'passkey security login', when: signedInWeb },
  { page: 'account', title: "ADD_ANOTHER_DEVICE" /* 添加其他设备 */, icon: 'qr', tint: 'var(--blue)', kw: 'device link code phone computer', when: signedInWeb },
  { page: 'account', title: "PAIR_THE_MOBILE_APP" /* 配对手机应用 */, icon: 'qr', tint: 'var(--blue)', kw: 'pair phone app android iphone', when: signedInWeb },
  { page: 'account', title: "PASSWORD" /* 密码 */, icon: 'key', tint: 'var(--orange)', kw: 'password login', when: c => signedInWeb(c) && c.pwOn },
  { page: 'account', title: "SIGN_OUT_A" /* 退出登录 */, icon: 'signOut', tint: 'var(--red)', kw: 'log out logout sign out', when: signedInWeb },
  { page: 'account', title: "SIGN_OUT_EVERYWHERE_A" /* 在所有设备上退出登录 */, icon: 'shield', tint: 'var(--red)', kw: 'log out all devices sessions', when: signedInWeb },
  { page: 'account', title: "ACCOUNT_ID" /* 账号 ID */, icon: 'personCircle', tint: 'var(--grey)', kw: 'id uid admin account', when: c => !!c.user && !c.demo },
  { page: 'account', title: "ADMIN_DASHBOARD" /* 管理后台 */, icon: 'crown', tint: 'var(--indigo)', kw: 'admin users dashboard', when: c => !!c.user?.admin && !c.demo },
  { page: 'account', title: "DISCONNECT" /* 断开连接 */, icon: 'signOut', tint: 'var(--red)', kw: 'disconnect server local', when: c => c.mobile && !!c.user },
  { page: 'account', title: "CONNECT_TO_MY_SERVER" /* 连接到我的服务器 */, icon: 'cloud', tint: 'var(--indigo)', kw: 'server sync self-hosted connect', when: c => c.mobile && !c.user },
  { page: 'account', title: "SIGN_IN_WITH_PASSKEY" /* 用通行密钥登录 */, icon: 'fingerprint', tint: 'var(--blue)', kw: 'login sign in log in passkey', when: c => !c.mobile && !c.demo && !c.user && c.webauthn },
  { page: 'account', title: "SIGN_IN_WITH_PASSWORD" /* 用密码登录 */, icon: 'key', tint: 'var(--orange)', kw: 'login sign in log in password', when: c => !c.mobile && !c.demo && !c.user && c.pwOn },
  { page: 'account', title: "CREATE_PASSKEY_PROFILE" /* 创建通行密钥档案 */, icon: 'plusCircle', tint: 'var(--acc)', kw: 'register account sign up create profile', when: c => !c.mobile && !c.demo && !c.user && c.webauthn },
  { page: 'account', title: "RESET_DEMO_DATA" /* 重置演示数据 */, icon: 'reset', tint: 'var(--blue)', kw: 'demo reset example', when: c => c.demo },
]

// Lower case, accents and other marks dropped, so "théme", "Thème" and "theme" meet.
export const fold = s => String(s || '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()

const WORD_CHAR = /[\p{L}\p{N}]/u
const atWordStart = (hay, w) => {
  for (let i = hay.indexOf(w); i !== -1; i = hay.indexOf(w, i + 1)) if (i === 0 || !WORD_CHAR.test(hay[i - 1])) return true
  return false
}

/** The trail a hit names under its title: "Workout" or "Workout › Fine-tuning". */
export function pageTrail(page, tr = t) {
  const p = PAGES[page]
  if (!p) return ''
  return p.parent ? tr(PAGES[p.parent].title) + ' › ' + tr(p.title) : tr(p.title)
}

/**
 * Settings rows matching a query, best first: every word of the query has to appear in the
 * row's title, its page, or its extra words (in English and in the app's language). A title
 * that starts with the query ranks first, then a title containing it, then the rest. Pages
 * themselves are hits too ("units" finds Units & language).
 */
export function searchSettings(query, ctx, tr = t) {
  const words = fold(query).trim().split(/\s+/).filter(Boolean)
  if (!words.length) return []
  const q = words.join(' ')
  const hits = []
  const consider = (entry, isPage) => {
    const title = tr(entry.title)
    const opts = entry.opts || []
    // What the screen says, in the app's language: anywhere in a word, since German and others
    // build long compounds ("Wochenstart", "Pausentimer").
    const own = fold([title, ...opts.map(o => tr(o)), entry.tkw ? entry.tkw() : '', isPage ? '' : pageTrail(entry.page, tr)].join(' '))
    // The English words behind it: only from the start of a word, so a "ton" typed in German
    // does not find "buttons".
    const en = fold([englishText(entry.title), entry.kw || '', ...opts.map(englishText), isPage ? '' : englishText(PAGES[entry.page]?.title)].join(' '))
    if (!words.every(w => own.includes(w) || atWordStart(en, w))) return
    const ft = fold(title)
    const rank = ft.startsWith(q) ? 0 : ft.includes(q) ? 1 : isPage ? 2 : 3
    hits.push({ ...entry, label: title, trail: isPage ? tr("SETTINGS" /* 设置 */) : pageTrail(entry.page, tr), isPage, rank })
  }
  for (const id of PAGE_IDS) {
    const top = PAGES[id].parent ? PAGES[id].parent : id
    if (!pageVisible(top, ctx) || id === 'advanced') continue
    consider({ page: id, title: PAGES[id].title, icon: PAGES[id].icon, tint: PAGES[id].tint }, true)
  }
  for (const e of SEARCH) {
    if (!pageVisible(PAGES[e.page].parent || e.page, ctx)) continue
    if (e.when && !e.when(ctx)) continue
    consider(e, false)
  }
  return hits.sort((a, b) => a.rank - b.rank)
}
