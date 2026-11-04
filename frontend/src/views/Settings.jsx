import { useEffect, useRef, useState, forwardRef, useSyncExternalStore } from 'react'
import { useNavigate, useParams, useLocation, Navigate } from 'react-router-dom'
import { useStore, DEF, hasData } from '../store/useStore.js'
import { healthStatus, loadHealth, enableHealth, disableHealth, openHealthConnect, onHealthChange } from '../lib/health-sync.js'
import { workoutControls } from '../lib/workout-controls.js'
import { speedUnitOf } from '../lib/speed.js'
import { formulaOf, FORMULA_NAMES } from '../lib/onerm.js'
import { copyText } from '../lib/clipboard.js'
import { useUI } from '../store/useUI.js'
import { ACCENTS, ACCENT_NAMES, todayISO, localTZ, weekStartOf, MONDAY, SUNDAY, fmtPlate } from '../lib/format.js'
import { inventoryFor, ownsPlates } from '../lib/plates.js'
import { dumbbellsOf } from '../lib/dumbbells.js'
import { effortOf } from '../lib/history.js'
import { figureOf } from '../lib/exercises.js'
import { unlock, chime, playOnSilentSupported, vibrateSupported, appleTouchDevice } from '../lib/sound.js'
import { REST_SOUND_IDS, restSoundOf } from '../lib/rest-sounds.js'
import { scheduleModeOf, chooseFixedWeek, chooseRotation } from '../lib/rotation.js'
import { queueOf } from '../lib/queue.js'
import { api, webauthnOK, passkeyRegister, passkeyError, IS_ANDROID } from '../lib/api.js'
import { pushSupported, enablePush, disablePush, sendTestPush, syncPushSubscription } from '../lib/push.js'
import { wakeLockSupported } from '../lib/wakelock.js'
import { t, tn, LANGS, INSTR_LANGS, EXERCISE_NAME_LANGS, baseLang, dateLocale , translateValue } from '../lib/i18n.js'
import { effectiveLang } from '../lib/default-lang.js'
import { DEMO, REPO } from '../lib/demo.js'
import { MOBILE, isAndroid, shareExport, shareExportBlob, syncReminder } from '../lib/mobile.js'
import { NUDGE_COPY, NUDGE_TONES, toneOf } from '../lib/nudge.js'
import { referencedFiles } from '../lib/media-refs.js'
import { mediaStore } from '../lib/media-store.js'
import { syncMedia, fetchToStore } from '../lib/media-sync.js'
import { getMediaStatus, subscribeMediaStatus, pendingRefCount } from '../lib/media-owed.js'
import { limitsFrom, fmtMB, MB } from '../lib/media-limits.js'
import { setRestAccent } from '../lib/rest-alert.js'
import { CUSTOM, accentKey, adjustedIn, applyAccent, cleanHex, inkOn, isGrey } from '../lib/accent.js'
import { checkForUpdate, downloadAndInstall, fetchChecksum, RELEASES_PAGE } from '../lib/update.js'
import { forgetCoach } from '../lib/coach-api.js'
import { REST_MAX, REST_PAUSE_MIN, REST_PAUSE_MAX, fmtRest, fmtDuration } from '../lib/duration.js'
import { starterPlanSheet, confirmSheet, importFromApp, importFromHevy, equipmentProfileSheet, plateInventorySheet, dumbbellInventorySheet, menuSheet } from '../sheets.jsx'
import Icon from '../components/Icon.jsx'
import { durationSheet } from '../components/DurationWheel.jsx'
import { showsConnection, showsLocalLine } from '../components/SyncBanner.jsx'
import BackupFolderRow, { useBackupFolder, autoBackupSubtitle } from '../components/BackupFolderRow.jsx'
import { ServerSyncSection, KeptChangesRows, leaveServer, connectServer, passkeySignIn } from '../components/ServerSync.jsx'
import { passwordOn, PasswordRow, openPasswordSignIn, openPasswordRegister } from '../components/PasswordAuth.jsx'
import { usePasskeys, PasskeysRow, DeviceLinkRow, openDeviceLinkRedeem } from '../components/Passkeys.jsx'
import { Section, Row, SelectRow, Switch, Segmented, Button, TextField, SearchField } from '../components/ui.jsx'
import { PAGES, ROOT_GROUPS, pageVisible, searchSettings, pageTrail } from './settings-pages.js'

/* Settings (v1.3.11). The root is one screen: an account card, eleven rows that each open a page
   (/settings/<page>), and a search over every row. Rare things live one level further down
   (Workout → Fine-tuning). The rows and their rules are the ones the single long page had; only
   where they sit changed. settings-pages.js says which page holds what, and is what the search
   reads. `page` is the open page (null for the root), `find` a row a search hit asked for, which
   is scrolled to and flashed. */

// What was typed into the search, kept while you step into a hit and back out again: tied to
// the history entry it was typed on, so Back (in the app, the browser's or Android's) brings the
// results back, while Settings opened afresh from anywhere (the gear, a tab) starts at the root.
let lastQuery = { q: '', key: null }

// The route: /settings and /settings/<page>. An unknown page, or one this device does not have
// (the Coach page off the phone app), goes back to the root.
export function SettingsRoute() {
  const { page } = useParams()
  const loc = useLocation()
  const ctx = { user: useStore(s => s.user), mobile: MOBILE }
  if (page && (!PAGES[page] || !pageVisible(PAGES[page].parent || page, ctx))) return <Navigate to="/settings" replace />
  if (page === 'coach') return <Navigate to="/coach/setup" replace />
  return <Settings key={page || 'root'} page={page || null} find={loc.state?.find || null} via={loc.state?.via || null} />
}

// "Mon" / "Sun" in the app's language, for the Plan & schedule row's preview.
const shortWeekday = day => {
  try { return new Intl.DateTimeFormat(dateLocale(), { weekday: 'short' }).format(new Date(2024, 0, day === 0 ? 7 : 1)) } catch { return day === 0 ? 'Sun' : 'Mon' }
}

// Running as an installed app (home-screen web app or the phone app): no install tip then.
const standalone = () => {
  try { return !!(window.matchMedia?.('(display-mode: standalone)').matches || window.navigator.standalone === true) } catch { return false }
}

export default function Settings({ page = null, find = null, via = null }) {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const user = useStore(s => s.user)
  const sync = useStore(s => s.sync)
  const coachLocal = useStore(s => s.coachLocal)
  // Name-and-password sign-in, where the instance offers it (#118).
  const config = useStore(s => s.config)
  const pwOn = passwordOn(config)
  // What the app is showing, which for a profile that never picked a language is worked out on
  // this device rather than stored (#303).
  const lang = effectiveLang(S, config)
  // This profile's passkeys and the code for another device (#95). A change to them is read back
  // here and by the password row, whose "Remove" depends on there being a passkey.
  const passkeys = usePasskeys(!!user && !MOBILE && !DEMO && (page === 'account'))
  const [credsV, setCredsV] = useState(0)
  const credsChanged = () => { passkeys.load(); setCredsV(v => v + 1) }
  const { update, importConflict, importBackup, setUnit, resetEverything: resetAll, setUser, pullState, pushState, resetDemo } = useStore()
  const toast = useUI(s => s.toast)
  const fileRef = useRef(null)
  const importRef = useRef(null)
  const body = useRef(null)
  const wakeOK = wakeLockSupported()

  // A planner's own queue (no rotationId, or one that doesn't match the saved rotation here) is
  // not this app's to switch off or overwrite. The Scheduling row goes read-only for it.
  const liveQ = queueOf(S)
  const externalQ = !!liveQ && (!S.rotation || liveQ.rotationId !== S.rotation.id)

  // Two honest choices on a unit switch (issue #22): convert the numbers, or keep them and only
  // change the label — the old behaviour, still right for someone who logged in lb all along
  // under a kg label. Closing the sheet leaves the unit as it was.
  const switchUnit = v => {
    if (v === S.unit) return
    menuSheet({
      title: t("CONVERT_TO_COUNT" /* 换算为 {0}？ */, v),
      subtitle: t("EVERY_STORED_WEIGHT_LOGGED_SETS_WORKING_WEIGHTS_ROUTINE_TARGETS_BODY_WEIGHT_BAR" /* 所有已保存的重量（记录的组、工作重量、计划目标、体重、杠铃杆重量）目前以 {0} 计。是换算数值，还是保留数值只更改单位标签？ */, S.unit),
      items: [
        { icon: 'calculator', label: t("CONVERT_THE_NUMBERS" /* 换算数值 */), onClick: () => setUnit(v) },
        { icon: 'pencil', label: t("KEEP_THE_NUMBERS_CHANGE_THE_LABEL" /* 保留数值，只改标签 */), onClick: () => setUnit(v, { convert: false }) },
      ],
    })
  }

  // Fixed Week or Rotation. A live queue always wins (scheduleModeOf, lib/rotation.js) — a queue
  // written by a planner switches the app to Rotation on its own — but choosing Rotation with
  // nothing built yet has no queue to derive from, so S.scheduleMode is what keeps it selected
  // (and the weekday grid hidden, on both Home and Plan) until the first routine is added.
  // Fixed Week behaves as on Plan (views/Plan.jsx setMode), with the same words: with no loop
  // running there is nothing to lose and it switches at once; a running loop asks first.
  const setScheduleMode = v => {
    if (v === scheduleModeOf(S)) return
    if (v === 'week') {
      // A planner's own queue is never this app's to drop — this control is text-only while one
      // is live (below), but the guard stays here too rather than trust the render alone.
      if (!liveQ) { update(s => { chooseFixedWeek(s) }); return }
      confirmSheet({
        title: t("BACK_TO_A_FIXED_WEEK" /* 回到固定周？ */),
        message: t("THE_LOOP_STOPS_YOUR_WEEKDAYS_STAY_AS_THEY_ARE_AND_THE_LOOP" /* 循环将停止。你的每周安排保持不变，循环会保存以后再用。 */),
        confirmText: t("USE_FIXED_WEEK" /* 使用固定周 */),
        onConfirm: () => update(s => { chooseFixedWeek(s) }),
      })
      return
    }
    // The same switch as Plan's "How you train" (lib/rotation.js). With nothing to start (no
    // saved sequence, or a malformed queue Plan has to sort out) the choice holds and you stay
    // here: the page then offers the way to Plan (below), so picking a value never leaves it.
    update(s => { chooseRotation(s) })
  }

  // --- update check state ---
  const [updateInfo, setUpdateInfo] = useState(null) // { hasUpdate, latestVersion, apkUrl, hashUrl } | null
  const [android, setAndroid] = useState(false)
  const [checking, setChecking] = useState(false)
  // Where auto-backup writes on this Android phone, for the Auto-backup row's own subtitle.
  const [backupDir] = useBackupFolder(MOBILE && android && !!S.autoBackup)

  useEffect(() => {
    // The in-app updater installs an .apk, so it only applies to the native Android build.
    // On iOS and the web this check is skipped and the update row never appears. isAndroid()
    // already answers false off the mobile build; the MOBILE check on top keeps the web bundle
    // from even asking (and from calling GitHub on every Settings visit). Only the pages
    // that show it ask: the root (for nothing but `android`) skips the release check.
    if (!MOBILE) return
    isAndroid().then(ok => { setAndroid(ok); if (ok && page === 'about') checkForUpdate().then(setUpdateInfo).catch(() => {}) })
  }, [page])

  // A search hit: scroll its row (or button) into view and flash it once. A row that shows only
  // once the page has heard back from the server (web push, the passkey list) is waited for a
  // moment; still missing, the hit's `via` row, if it names one, is flashed instead, with a word
  // on why.
  useEffect(() => {
    if (!find || !body.current) return
    const el = body.current
    const named = label => [...el.querySelectorAll('.lrow')].find(r => r.querySelector('.lrow-t')?.textContent === label)
      || [...el.querySelectorAll('.btn')].find(b => b.textContent.trim() === label)
    let tm = null
    const flash = row => {
      row.classList.add('sp-flash')
      if (typeof row.scrollIntoView === 'function') row.scrollIntoView({ block: 'center' })
      tm = setTimeout(() => row.classList.remove('sp-flash'), 1900)
    }
    const row = named(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(find))
    if (row) { flash(row); return () => clearTimeout(tm) }
    let done = false
    const mo = typeof MutationObserver === 'function' ? new MutationObserver(() => {
      const r = named(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(find))
      if (r && !done) { done = true; mo.disconnect(); clearTimeout(wait); flash(r) }
    }) : null
    mo?.observe(el, { childList: true, subtree: true })
    const wait = setTimeout(() => {
      if (done) return
      done = true; mo?.disconnect()
      const r = via && named(translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(via))
      if (r) { flash(r); toast(t("TURN_ON_PUSH_NOTIFICATIONS_FIRST" /* 请先打开推送通知。 */)) }
    }, 1500)
    return () => { done = true; mo?.disconnect(); clearTimeout(wait); clearTimeout(tm) }
  }, [find])

  // The same check, on demand: the automatic one is silent when it finds nothing or cannot
  // reach GitHub, and a person who taps "Check for updates" deserves an answer either way.
  const checkNow = async () => {
    if (checking) return
    setChecking(true)
    try {
      const info = await checkForUpdate()
      setUpdateInfo(info)
      if (!info.hasUpdate) toast(t("YOU_HAVE_THE_LATEST_VERSION" /* 已是最新版本。 */))
    } catch {
      toast(t("COULDN_T_CHECK_FOR_UPDATES_ARE_YOU_ONLINE" /* 无法检查更新。你在线吗？ */))
    }
    setChecking(false)
  }

  const onUpdateRowClick = () => {
    if (!updateInfo?.hasUpdate) return
    if (updateInfo.apkUrl) {
      // Start download & install
      const version = updateInfo.latestVersion
      confirmSheet({
        title: t("UPDATE_TO_COUNT" /* 更新到 {0}？ */, version),
        message: t("THE_LATEST_VERSION_WILL_BE_DOWNLOADED_AND_THE_INSTALLER_WILL_OPEN" /* 将下载最新版本并打开安装程序。 */),
        confirmText: t("DOWNLOAD_INSTALL" /* 下载并安装 */),
        onConfirm: async () => {
          // Open a progress sheet
          let closeProgress = null
          let setProgress = null
          useUI.getState().openSheet(close => {
            closeProgress = close
            return <DownloadProgress ref={fn => { setProgress = fn }} />
          }, { locked: true })
          try {
            // The release always publishes the checksum next to the APK. Without it the file is
            // not installed — a sideloaded binary is exactly the thing that should be verified.
            let expectedHash = null
            try { expectedHash = await fetchChecksum(updateInfo.hashUrl) } catch (e) { /* reported below */ }
            if (!/^[0-9a-f]{64}$/i.test(expectedHash || '')) throw new Error(t("CHECKSUM_NOT_AVAILABLE_SO_NOT_INSTALLING" /* 校验和不可用，所以不安装 */))
            await downloadAndInstall(updateInfo.apkUrl, expectedHash, (received, total) => {
              if (setProgress) setProgress(received, total)
            })
            if (closeProgress) closeProgress()
          } catch (e) {
            if (closeProgress) closeProgress()
            toast(t("UPDATE_FAILED_COUNT" /* 更新失败：{0} */, e.message))
          }
        },
      })
    } else {
      // Update available but no APK asset — open the releases page
      window.open(RELEASES_PAGE, '_blank', 'noopener')
    }
  }

  // Reads the store at the moment of the tap: the sheet that asks before a sign-out offers it too,
  // and the copy it exports is the one that has not reached the server.
  const doExport = async () => {
    const json = JSON.stringify(useStore.getState().S, null, 2)
    const name = 'opengym-backup-' + todayISO() + '.json'
    // WKWebView can't download blob URLs — the native build hands the file to the share sheet.
    if (MOBILE) {
      try { await shareExport(json, name); toast(t("BACKUP_EXPORTED" /* 备份已导出 */)) } catch (e) { /* share sheet dismissed */ }
      return
    }
    const blob = new Blob([json], { type: 'application/json' })
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); URL.revokeObjectURL(a.href)
    toast(t("BACKUP_EXPORTED" /* 备份已导出 */))
  }
  // "Export with photos & videos": the same JSON plus every file the state refers to, in a zip
  // (lib/backup-media.js). Signed in, a file this device never downloaded is fetched for it; one
  // nobody has is left out and counted. The sign-out sheet offers it while media are waiting.
  const doExportZip = async () => {
    const { exportBackupZip } = await import('../lib/backup-media.js')
    const st = useStore.getState()
    const signedIn = !!(st.user && st.config?.media)
    let out
    try { out = await exportBackupZip(st.S, { fetchOne: signedIn ? fetchToStore : null }) }
    catch { toast(t("SOMETHING_WENT_WRONG" /* 出了点问题 */)); return }
    const name = 'opengym-backup-' + todayISO() + '.zip'
    if (out.missing) toast(tn("COUNT_FILE_COULD_NOT_BE_INCLUDED" /* 有 {0} 个文件无法包含 */, "COUNT_FILES_COULD_NOT_BE_INCLUDED" /* 有 {0} 个文件无法包含 */, out.missing))
    if (MOBILE) {
      try { await shareExportBlob(out.blob, name); if (!out.missing) toast(t("BACKUP_EXPORTED" /* 备份已导出 */)) } catch (e) { /* share sheet dismissed */ }
      return
    }
    const a = document.createElement('a'); a.href = URL.createObjectURL(out.blob); a.download = name; a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 60000)
    if (!out.missing) toast(t("BACKUP_EXPORTED" /* 备份已导出 */))
  }
  // Import takes the JSON backup and the zip alike, told apart by their first bytes. A zip's
  // files go into the local store only once the import is confirmed, each checked against its
  // name first; the state's media refs and links pass the usual gates (lib/backup-media.js).
  const doImport = async ev => {
    const f = ev.target.files[0]; if (!f) return
    ev.target.value = ''
    let read
    try {
      const { readBackupFile } = await import('../lib/backup-media.js')
      read = await readBackupFile(f)
    } catch (e) {
      const { backupImportError } = await import('../lib/backup-media.js')
      toast(backupImportError(e)); return
    }
    const apply = async mergeWith => {
      if (read.files.length) {
        const { storeBackupMedia } = await import('../lib/backup-media.js')
        await storeBackupMedia(read.files, { limits: limitsFrom(useStore.getState().config) })
      }
      importBackup(read.state, { mergeWith })
      // The photos it brought are pending here and maybe gone from the server (a reset): sent now,
      // not after the ten-minute dedupe of the run before the reset.
      if (read.files.length) syncMedia({ force: true })
      toast(t("BACKUP_IMPORTED" /* 备份已导入 */))
    }
    // Signed in, the server is asked first: a workout logged since the backup was made, or on
    // another device meanwhile, would be deleted from the profile by the replace — said, with the
    // choice to merge those in instead (useStore importConflict / importBackup).
    const conflict = await importConflict(read.state)
    if (conflict) {
      const n = conflict.workouts
      menuSheet({
        title: t("IMPORT_BACKUP_A" /* 导入备份？ */),
        subtitle: t(n === 1
          ? "THE_SERVER_HAS_ONE_WORKOUT_THAT_IS_NOT_IN_THIS_BACKUP_LOGGED" /* 服务器上有 1 次训练不在此备份中，是备份之后或在其他设备上记录的。替换会删除它。 */
          : "THE_SERVER_HAS_COUNT_WORKOUTS_THAT_ARE_NOT_IN_THIS_BACKUP_LOGGED" /* 服务器上有 {0} 次训练不在此备份中，是备份之后或在其他设备上记录的。替换会删除它们。 */, n),
        items: [
          { icon: 'trash', label: t("REPLACE_ANYWAY" /* 仍然替换 */), danger: true, onClick: () => apply(null) },
          { icon: 'merge', label: t("MERGE_THEM_IN" /* 合并进来 */), onClick: () => apply(conflict) },
          { icon: 'xmark', label: t("CANCEL" /* 取消 */), onClick: () => {} },
        ],
      })
      return
    }
    confirmSheet({
      title: t("IMPORT_BACKUP_A" /* 导入备份？ */), message: t("THIS_REPLACES_ALL_CURRENT_DATA_WITH_THE_BACKUP_FILE" /* 这将用备份文件替换当前所有数据。 */), confirmText: t("IMPORT" /* 导入 */), danger: true,
      onConfirm: () => apply(null)
    })
  }
  // Whether any custom exercise has a photo or video: the rows about them only show then.
  const hasMedia = referencedFiles(S).length > 0
  const registerHere = () => useUI.getState().openSheet(close => <RegisterInline close={close} setUser={setUser} pushState={pushState} pullState={pullState} toast={toast} />)
  /* Disconnect (phone), Sign out, Sign out everywhere. None of them wipes this device while the
     server is missing a change: the confirm no longer promises a sync it never checked, and when
     something is owed, a second sheet says how much and offers to try again, to export a backup,
     or to go ahead anyway with the changes kept on this device (components/ServerSync.jsx).
     "Sign out everywhere" also ends every paired phone's token — the phones have no passkey to
     sign in with, so they have to be paired again, and the confirm says so. Failing, it touches
     nothing local: still signed in here, and the toast says so. */
  const kept = t("THE_CHANGES_YOUR_SERVER_HAS_NOT_SEEN_ARE_KEPT_ON_THIS_DEVICE" /* 服务器尚未收到的更改会保留在此设备上，并在它再次以此账号连接时重新加入。 */)
  // A workout running here is kept aside by the sign-out (useStore stashActive): the confirm says so.
  const running = () => S.active ? ' ' + t("YOU_HAVE_A_WORKOUT_RUNNING_IT_WAITS_ON_THIS_DEVICE_UNTIL_YOU" /* 你有一个正在进行的训练。它会留在这台设备上，等你回到这个账户。 */) : ''
  const leave = (kind, after) => leaveServer(kind, { exportBackup: doExport, exportBackupZip: doExportZip, done: r => { nav('/home'); if (r.stashed) toast(kept); else if (after) toast(after) } })
  const disconnect = () => confirmSheet({
    title: t("DISCONNECT_FROM_YOUR_SERVER" /* 要断开与服务器的连接吗？ */),
    message: t("THIS_PHONE_SWITCHES_BACK_TO_LOCAL_ONLY_AND_ITS_COPY_OF_YOUR" /* 这部手机将切换回仅本地模式，并删除其中的账号副本。会先检查你的服务器是否已有全部更改。如果没有，由你决定如何处理。 */) + running(),
    confirmText: t("DISCONNECT" /* 断开连接 */), danger: true,
    onConfirm: () => leave('disconnect', t("DISCONNECTED_BACK_TO_LOCAL_ONLY" /* 已断开连接。回到仅本地模式 */)),
  })
  const signOutHere = () => confirmSheet({
    title: t("SIGN_OUT" /* 退出登录？ */),
    message: t("YOUR_DATA_IS_REMOVED_FROM_THIS_BROWSER_YOUR_PROFILE_ON_THE_SERVER" /* 你的数据将从此浏览器中删除；服务器上的个人资料会保留它们。会先检查服务器是否已有全部更改。如果没有，由你决定如何处理。 */) + running(),
    confirmText: t("SIGN_OUT_A" /* 退出登录 */), danger: true,
    onConfirm: () => leave('signout'),
  })
  const signOutEverywhere = () => confirmSheet({
    title: t("SIGN_OUT_EVERYWHERE" /* 在所有设备上退出登录？ */),
    message: t("SIGNS_THIS_PROFILE_OUT_ON_EVERY_DEVICE_INCLUDING_THIS_ONE_PHONES_PAIRED" /* 在所有设备（包括此设备）上退出此个人资料。与它配对的手机会断开连接，需要重新配对。你的通行密钥仍然有效，随时可以用它们重新登录。 */) + running(),
    confirmText: t("SIGN_OUT_EVERYWHERE_A" /* 在所有设备上退出登录 */), danger: true,
    onConfirm: () => leave('everywhere', t("SIGNED_OUT_ON_ALL_DEVICES" /* 已在所有设备上退出登录 */)),
  })
  // Signed in, the empty state is pushed to the profile like any other change, so the wipe
  // reaches the server and every device that syncs with it — the dialog has to say so. The Coach
  // keeps its data outside S in two homes that can both be in use on one phone: a file per
  // profile on the server, and — when it runs with the phone's own key — a file on the device.
  // Each is cleared on its own; forgetCoach() alone would pick one by mode. A failed call must
  // not stop the reset.
  const resetEverything = () => confirmSheet({
    title: t("RESET_EVERYTHING" /* 重置所有内容？ */),
    message: user
      ? t("DELETES_YOUR_PLAN_WORKOUTS_BODY_WEIGHT_PHOTOS_AND_VIDEOS_FROM_YOUR_PROFILE" /* 从此服务器上的档案以及所有已登录设备中删除计划、训练、体重、照片和视频。无法撤销。 */)
      : t("DELETES_YOUR_PLAN_WORKOUTS_BODY_WEIGHT_PHOTOS_AND_VIDEOS_ON_THIS_DEVICE" /* 删除本设备上的计划、训练、体重、照片和视频。无法撤销。 */),
    confirmText: t("DELETE_EVERYTHING" /* 全部删除 */), danger: true,
    onConfirm: () => {
      if (user) api('/api/coach/forget', { method: 'POST', body: '{}' }).catch(() => {})
      if (coachLocal?.mode === 'byok') forgetCoach().catch(() => {})
      resetAll()
      nav('/home'); toast(t("ALL_DATA_RESET" /* 所有数据已重置 */))
      clearMediaAfterReset(!!user).catch(() => {})
    },
  })

  /* ---------------- what the pages and the search need to know about this device ---------------- */
  const canVibrate = vibrateSupported()
  const ctx = {
    user, mobile: MOBILE, android, demo: DEMO, wakeOK, hasMedia, pwOn, webauthn: webauthnOK(),
    sound: !!S.sound, playOnSilent: playOnSilentSupported(), canVibrate, vibrate: S.vibrate !== false,
    profiles: (S.equipProfiles || []).length > 0, nameLang: EXERCISE_NAME_LANGS.includes(baseLang(lang)),
    pushOK: !MOBILE && pushSupported(), reminderOn: !!S.reminder?.on, nudge: !!S.reminder?.nudge,
    autoBackup: !!S.autoBackup, synced: !!sync, installTip: !MOBILE && !standalone(), androidWeb: IS_ANDROID,
  }
  const mode = scheduleModeOf(S)
  const layout = ['list', 'compact', 'focus'].includes(S.workoutView) ? S.workoutView : 'cards'
  const layoutLabel = { cards: t("CARDS" /* 卡片 */), list: t("LIST" /* 列表 */), compact: t("COMPACT" /* 紧凑 */) }[layout]
  const activeProfile = (S.equipProfiles || []).find(p => p.id === S.activeEquipId)
  const themeLabel = { dark: t("DARK" /* 深色 */), light: t("LIGHT" /* 浅色 */), system: t("SYSTEM" /* 跟随系统 */) }[S.theme || 'dark'] || t("DARK" /* 深色 */)
  // The value a root row shows, so most questions are answered without opening the page.
  const preview = {
    workout: () => (S.restSec > 0 ? t("COUNT_REST" /* 休息 {0} */, fmtRest(S.restSec)) : t("NO_REST_TIMER" /* 不计时休息 */)) + ' · ' + layoutLabel,
    alerts: () => [S.sound ? t("SOUND" /* 提示音 */) : null, canVibrate && S.vibrate !== false ? t("VIBRATE" /* 振动 */) : null, S.timerFlash ? t("FLASH" /* 闪烁 */) : null].filter(Boolean).join(' · ') || t("SILENT" /* 静音 */),
    reminders: () => (S.reminder?.on ? (S.reminder.time || DEF.reminder?.time || '') : t("OFF" /* 关 */)),
    plan: () => (mode === 'rotation' ? t("ROTATION" /* 轮换 */) : t("FIXED_WEEK" /* 固定周 */)) + ' · ' + shortWeekday(weekStartOf(S) === SUNDAY ? 0 : 1),
    units: () => (S.unit || 'kg') + ' · ' + (LANGS[lang] || lang),
    equipment: () => (S.equipFilterOn && activeProfile ? activeProfile.name : t("EVERYTHING" /* 全部 */)),
    look: () => themeLabel + ' · ' + accentLabel(S),
    coach: () => (coachLocal?.mode === 'server' ? t("YOUR_SERVER" /* 你的服务器 */) : coachLocal?.mode === 'byok' ? t("YOUR_API_KEY" /* 你的 API 密钥 */) : t("OFF" /* 关 */)),
    data: () => '',
    about: () => 'v' + __APP_VERSION__,
  }

  const open = id => {
    if (id === 'coach') { nav('/coach/setup'); return }
    nav('/settings/' + id)
  }
  // Back the way you came when there is a way (the browser's back, Android's back, this button
  // all do the same); a page opened from a link with nothing behind it goes up to its parent.
  const back = () => {
    const up = PAGES[page]?.parent ? '/settings/' + PAGES[page].parent : '/settings'
    if ((window.history.state?.idx || 0) > 0) nav(-1)
    else nav(up, { replace: true })
  }

  /* ---------------- the pages ---------------- */
  const restRow = <Row icon="timer" iconTint="var(--orange)" title={t("REST_TIMER" /* 休息计时 */)} value={fmtRest(S.restSec)} accessory="chevron"
    onClick={() => durationSheet({
      title: t("REST_TIMER" /* 休息计时 */), value: S.restSec, max: REST_MAX, off: t("OFF" /* 关 */),
      footer: t("SCROLL_TO_ZERO_ZEROZERO_TO_TURN_THE_REST_TIMER_OFF" /* 滚动到 0:00 即可关闭休息计时。 */),
      onDone: v => update(s => { s.restSec = v }),
    })} />
  // Default for a rest-pause burst added live on a plain set. A planned exercise's own "Rest (s)"
  // (in its drop set / burst config) overrides it, the same way the main rest timer is the
  // fallback for an exercise without a rest of its own. On the wheel too, 5 s to 5 min: the
  // burst's rest is never 0 (lib/history.js keeps it at 5 s at least), so the wheel stops there.
  const restPauseRow = <Row icon="bolt" iconTint="var(--orange)" title={t("REST_PAUSE_REST" /* 休息暂停组内休息 */)} value={fmtDuration(S.restPauseSec || 15)} accessory="chevron"
    onClick={() => durationSheet({
      title: t("REST_PAUSE_REST" /* 休息暂停组内休息 */), value: S.restPauseSec || 15, min: REST_PAUSE_MIN, max: REST_PAUSE_MAX,
      footer: t("THE_SHORT_BREAK_BETWEEN_THE_BURSTS_OF_A_REST_PAUSE_SET" /* 休息暂停组中各小组之间的短暂休息。 */),
      onDone: v => update(s => { s.restPauseSec = v }),
    })} />

  const pages = {
    workout: () => <>
      <Section title={t("REST" /* 休息 */)} footer={t("EACH_EXERCISE_CAN_HAVE_ITS_OWN_REST_TOO_SET_IT_IN_THE" /* 每个动作也可以有自己的休息时间。在计划的动作设置里修改。 */)}>
        {restRow}
        {restPauseRow}
      </Section>
      <Section title={t("LOGGING" /* 记录 */)}>
        {/* Two names for the same judgement, so the column asks in the scale you already think in.
            The (i) sits before the control: you read it on the way to the choice, not after it. */}
        <Row icon="gauge" iconTint="var(--purple)" title={t("EFFORT_PER_SET" /* 每组强度 */)}>
          <button className="helpbtn" aria-label={t("WHAT_ARE_RIR_AND_RPE" /* RIR 和 RPE 是什么？ */)} onClick={effortHelpSheet}><Icon name="info" /></button>
          <Segmented className="seg-inline"
            options={[{ value: 'none', label: t("OFF" /* 关 */) }, { value: 'rir', label: t("RIR" /* 术语：RIR */) }, { value: 'rpe', label: t("RPE" /* 术语：RPE */) }]}
            value={effortOf(S)} onChange={v => update(s => { s.effort = v; delete s.showRir })} />
        </Row>
        {/* The line under each exercise that the rows are held against (#173). Tapping the line in
            a workout switches it too; this is where the choice can be found without knowing that. */}
        <SelectRow icon="history" iconTint="var(--blue)" title={t("SHOWN_UNDER_EACH_EXERCISE" /* 每个动作下方显示 */)}
          value={S.logRef === 'best' ? 'best' : 'last'} onChange={v => update(s => { s.logRef = v })}
          options={[
            { value: 'last', label: t("LAST_TIME" /* 上次 */), subtitle: t("WHAT_YOU_DID_THE_LAST_TIME_IN_THAT_ROUTINE" /* 上次在该训练计划完成的内容。 */) },
            { value: 'best', label: t("BEST_SET" /* 最佳组 */), subtitle: t("YOUR_HEAVIEST_SET_OF_THE_EXERCISE_FROM_ANY_WORKOUT" /* 该动作在所有训练中最重的一组。 */) },
          ]} />
        {/* One exercise at a time (cards with Prev/Next), the whole session stacked as a
            scrollable list, or that list stripped to just names and set rows (compact). Legacy or
            unknown values read as cards. The workout's ⋯ menu can override it for one session. */}
        <Row icon="layout" iconTint="var(--blue)" title={t("LAYOUT" /* 布局 */)}>
          <Segmented className="seg-inline"
            options={[{ value: 'cards', label: t("CARDS" /* 卡片 */) }, { value: 'list', label: t("LIST" /* 列表 */) }, { value: 'compact', label: t("COMPACT" /* 紧凑 */) }, { value: 'focus', label: t("FOCUS" /* 专注 */) }]}
            value={layout} onChange={v => update(s => { s.workoutView = v })} />
        </Row>
        {/* The saved side of the Layout menu's "Collapse completed exercises" (#241): on here, every
            session starts with it, and the menu still flips it for one session. Setting it here
            also drops a running session's own choice, so the switch does what it says right away. */}
        <Row icon="minimize" iconTint="var(--teal)" title={t("COLLAPSE_COMPLETED_EXERCISES" /* 折叠已完成的动作 */)}
          subtitle={t("IN_LIST_AND_COMPACT_A_FINISHED_EXERCISE_FOLDS_INTO_ONE_LINE" /* 在列表和紧凑视图中，完成的动作会折叠成一行。 */)}>
          <Switch aria-label={t("COLLAPSE_COMPLETED_EXERCISES" /* 折叠已完成的动作 */)} checked={!!S.collapseCompleted}
            onChange={v => update(s => { s.collapseCompleted = v; if (s.active) delete s.active.collapseCompleted })} />
        </Row>
      </Section>
      <Section title={t("BEFORE_AND_DURING" /* 开始前与训练中 */)}>
        {/* The quick weigh-in that opens on Start (sheets.jsx startFlow, issue #137); off skips
            straight to the session. Home and Stats still log weight by hand. */}
        <Row icon="scale" iconTint="var(--green)" title={t("WEIGH_IN_BEFORE_WORKOUTS" /* 训练前称重 */)}
          subtitle={t("ASKS_FOR_YOUR_BODY_WEIGHT_WHEN_A_WORKOUT_STARTS_OFF_STARTS_THE" /* 开始训练时询问体重。关闭后直接进入训练。 */)}>
          <Switch checked={S.weighIn !== false} onChange={v => update(s => { s.weighIn = v })} />
        </Row>
        {(wakeOK || !MOBILE) && (
          <Row icon="phoneScreen" iconTint="var(--yellow)" title={t("KEEP_SCREEN_AWAKE" /* 保持屏幕常亮 */)}
            subtitle={wakeOK ? t("THE_SCREEN_STAYS_ON_WHILE_A_WORKOUT_IS_RUNNING_SO_YOU_DON" /* 训练进行时屏幕保持常亮，组间无需再解锁手机。 */) : t("NOT_SUPPORTED_IN_THIS_BROWSER" /* 此浏览器不支持。 */)}>
            <Switch checked={wakeOK && S.keepAwake !== false} disabled={!wakeOK}
              onChange={v => update(s => { s.keepAwake = v })} />
          </Row>
        )}
        {/* 'full'/'mini' is also what the tap-toggle on the workout animation writes; 'off' hides
            workout media entirely (library, detail sheet and picker thumbs are unaffected).
            Legacy/unknown values read as 'full'. */}
        <Row icon="image" iconTint="var(--teal)" title={t("EXERCISE_ANIMATIONS" /* 动作动画 */)}>
          <Segmented className="seg-inline"
            options={[{ value: 'full', label: t("FULL" /* 完整 */) }, { value: 'mini', label: t("SMALL" /* 小 */) }, { value: 'off', label: t("HIDDEN" /* 隐藏 */) }]}
            value={S.gifSize === 'mini' || S.gifSize === 'off' ? S.gifSize : 'full'}
            onChange={v => update(s => { s.gifSize = v })} />
        </Row>
      </Section>
      <Section>
        <Row icon="wrench" iconTint="var(--grey)" title={t("FINE_TUNING" /* 细节调整 */)} subtitle={t("BUTTONS_TIMED_SETS" /* 按钮、计时组 */)} accessory="chevron" onClick={() => open('advanced')} />
      </Section>
    </>,

    advanced: () => {
      // S.wc overlays DEF.wc, so a profile from before these switches existed reads as the lean default.
      const wc = workoutControls(S)
      const setWc = (k, v) => update(s => { s.wc = { ...workoutControls(s), [k]: v } })
      return <>
        <Section title={t("SESSIONS_AND_TIMED_SETS" /* 训练与计时组 */)}>
          {/* Whose reps a planned session opens with (lib/session-start.js). The plan's by default:
              the routine is what you said you would do, and history and progression decide the
              weight. The other choice is the old behaviour, reps carried over from last time.
              Absent (an older profile) reads as the plan. */}
          <SelectRow icon="clipboard" iconTint="var(--green)" title={t("PLANNED_SESSIONS_START_FROM" /* 计划训练的起点 */)}
            value={S.startFrom === 'last' ? 'last' : 'plan'} onChange={v => update(s => { s.startFrom = v })}
            options={[
              { value: 'plan', label: t("YOUR_PLAN" /* 你的计划 */), subtitle: t("THE_ROUTINE_S_SETS_AND_REPS_YOUR_HISTORY_DECIDES_THE_WEIGHT" /* 按训练计划的组数和次数，重量由你的历史记录决定。 */) },
              { value: 'last', label: t("YOUR_LAST_SESSION" /* 你的上次训练 */), subtitle: t("THE_REPS_YOU_LOGGED_LAST_TIME_IN_THAT_ROUTINE_CARRIED_OVER" /* 沿用你上次在该训练计划记录的次数。 */) },
            ]} />
          <Row icon="stopwatch" iconTint="var(--orange)" title={t("KEEP_TIMING_AFTER_TARGET" /* 达到目标后继续计时 */)}
            subtitle={t("TIMED_SETS_CONTINUE_UP_TO_ONEFIVE_EXTRA_MINUTES_TAP_DONE_TO_LOG" /* 计时组最多继续 15 分钟。点击“完成”记录实际时长。 */)}>
            <Switch aria-label={t("KEEP_TIMING_AFTER_TARGET" /* 达到目标后继续计时 */)} checked={!!S.timedSetOvertime}
              onChange={v => update(s => { s.timedSetOvertime = v })} />
          </Row>
        </Section>
        {/* The lean workout screen keeps the sets and one "more" button per exercise; each switch
            brings one of the old always-visible button groups back for people who liked them. */}
        <Section title={t("BUTTONS_ON_THE_WORKOUT_SCREEN" /* 训练界面上的按钮 */)} footer={t("EVERYTHING_HIDDEN_HERE_STAYS_ONE_TAP_AWAY_THE_BUTTON_OF_AN_EXERCISE" /* 这里隐藏的一切都只需一次点按：动作的 ⋯ 按钮和组号。 */)}>
          <Row icon="plusCircle" iconTint="var(--green)" title={t("WEIGHT_AND_REPS_BUTTONS" /* 重量和次数的 +/− 按钮 */)} subtitle={t("OFF_TAP_THE_NUMBER_AND_TYPE_IT" /* 关闭：点按数字直接输入 */)}>
            <Switch checked={wc.steppers} onChange={v => setWc('steppers', v)} />
          </Row>
          <Row icon="bolt" iconTint="var(--orange)" title={t("DROP_AND_BURST_SHORTCUTS_ON_EVERY_SET" /* 每组显示递减/休息暂停快捷按钮 */)}>
            <Switch checked={wc.setShortcuts} onChange={v => setWc('setShortcuts', v)} />
          </Row>
          {/* Swipe actions (v1.3.11): not a button, but the same question of what a set row does. The
              one switch covers Plan's lists too; the stored key keeps its old name, swipeSets. */}
          <Row icon="swap" iconTint="var(--indigo)" title={t("SWIPE_ACTIONS" /* 滑动操作 */)} subtitle={t("SETS_ROUTINES_AND_THE_LOOP_LEFT_REMOVES_RIGHT_COPIES" /* 组、计划和循环：左滑移除，右滑复制 */)}>
            <Switch aria-label={t("SWIPE_ACTIONS" /* 滑动操作 */)} checked={wc.swipeSets} onChange={v => setWc('swipeSets', v)} />
          </Row>
          {/* The chip row at the top of a workout (#323): not a button row, but the same question of
              what the workout screen shows. On by default, it is about one line tall. */}
          <Row icon="more" iconTint="var(--mint)" title={t("EXERCISE_CHIPS_AT_THE_TOP" /* 顶部动作圆点 */)} subtitle={t("A_NUMBERED_DOT_PER_EXERCISE_FILLED_AS_YOU_GO_TAP_ONE_TO" /* 每个动作一个带编号的圆点，练着练着就填满了。点一下就能跳过去。 */)}>
            <Switch aria-label={t("EXERCISE_CHIPS_AT_THE_TOP" /* 顶部动作圆点 */)} checked={wc.exerciseChips} onChange={v => setWc('exerciseChips', v)} />
          </Row>
          <Row icon="link" iconTint="var(--blue)" title={t("SUPERSET_BUTTONS_IN_THE_EXERCISE_HEADER" /* 动作标题中的超级组按钮 */)}>
            <Switch checked={wc.pairButtons} onChange={v => setWc('pairButtons', v)} />
          </Row>
          <Row icon="swap" iconTint="var(--teal)" title={t("MOVE_SWAP_AND_REMOVE_BUTTONS_BELOW_THE_EXERCISE" /* 动作下方的移动、替换和删除按钮 */)}>
            <Switch checked={wc.exerciseButtons} onChange={v => setWc('exerciseButtons', v)} />
          </Row>
        </Section>
      </>
    },

    alerts: () => {
      const iPhone = appleTouchDevice()
      return <>
        <Section title={t("WHEN_A_REST_ENDS" /* 休息结束时 */)}>
          <Row icon="speaker" iconTint="var(--pink)" title={t("PLAY_A_SOUND" /* 播放提示音 */)}>
            {/* Turning the sound on is a tap: unlock the audio context now so a timer that ends
                before the next set check can already sound (iOS, #152). */}
            <Switch checked={!!S.sound} onChange={v => { if (v) unlock(true); update(s => { s.sound = v }) }} />
          </Row>
          {/* The chime that replaced the original three beeps (Discord: "too quiet under music")
              is not an improvement for everyone: louder is a cost with headphones or in a quiet
              room, and some want a sound that feels like theirs (#306). The chime by default; the
              sheet plays each one as you tap it (restSoundSheet). */}
          {S.sound && <Row icon="speaker" iconTint="var(--pink)" title={t("SOUND" /* 提示音 */)} value={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(REST_SOUND_LABEL[restSoundOf(S)])}
            accessory="chevron" onClick={restSoundSheet} />}
          {/* iOS only (WebKit's audio-session API, iOS 17+): with it off the ring/silent switch
              mutes the timer. On, the phone treats the timer like a music player (exclusive, and
              the music app is not told it may resume), so it is a choice, off by default. */}
          {S.sound && playOnSilentSupported() && (
            <Row icon="speaker" iconTint="var(--orange)" title={t("PLAY_EVEN_ON_SILENT" /* 静音时也播放 */)}
              subtitle={<>{t("MUSIC_PLAYING_ON_THIS_PHONE_STOPS_DURING_A_WORKOUT_AND_DOES_NOT" /* 锻炼期间，这部手机正在播放的音乐会停止，且不会自动恢复。 */)}<br />{t("IPHONE_ONLY" /* 仅限 iPhone */)}</>}>
              <Switch checked={!!S.soundOnSilent} onChange={v => update(s => { s.soundOnSilent = v })} />
            </Row>
          )}
        </Section>
        {/* The buzz at the end of a rest or a hold and on a set tick, on its own switch like the
            sound (Discord, asierlama). iOS has no navigator.vibrate: the row stays, greyed out,
            and says so, instead of an iPhone user looking for a setting that is not there. */}
        <Section footer={!canVibrate && iPhone ? t("IPHONE_DOESN_T_LET_OPENGYM_VIBRATE_A_SOUND_OR_A_FLASH_DOES" /* iPhone 不允许 openGym 振动。用提示音或闪烁屏幕就够了。 */) : null}>
          <Row icon="vibrate" iconTint="var(--indigo)" title={t("VIBRATE" /* 振动 */)} className={canVibrate ? '' : 'dis'}
            subtitle={canVibrate ? null : iPhone ? t("NOT_ON_IPHONE" /* iPhone 不支持 */) : t("NOT_SUPPORTED_IN_THIS_BROWSER" /* 此浏览器不支持。 */)}>
            <Switch checked={canVibrate && S.vibrate !== false} disabled={!canVibrate} onChange={v => update(s => { s.vibrate = v })} />
          </Row>
          {/* Android app only (#375), and only shown there, so it needs no "Android app only" hint: silent mode mutes the ordinary buzz and the notification's,
              so the end of a rest or a hold can buzz as an alarm instead. Opt-in, like the iOS row
              above: an alarm-class buzz is the most insistent thing an app can do on some phones. */}
          {MOBILE && android && canVibrate && S.vibrate !== false && (
            <Row icon="vibrate" iconTint="var(--indigo)" title={t("VIBRATE_ON_SILENT_TOO" /* 静音时也振动 */)}
              subtitle={t("THE_END_OF_A_REST_OR_A_HOLD_BUZZES_LIKE_AN_ALARM" /* 休息或保持结束时会像闹钟一样振动，即使在静音模式下。 */)}>
              <Switch checked={!!S.vibrateOnSilent} onChange={v => update(s => { s.vibrateOnSilent = v })} />
            </Row>
          )}
          <Row icon="sun" iconTint="var(--yellow)" title={t("FLASH_THE_SCREEN" /* 闪烁屏幕 */)}>
            <Switch checked={!!S.timerFlash} onChange={v => update(s => { s.timerFlash = v })} />
          </Row>
        </Section>
      </>
    },

    reminders: () => <NotificationsCard S={S} update={update} toast={toast} />,

    plan: () => <>
      <Section>
        {/* Fixed Week (S.week) or Rotation (the live queue, lib/queue.js + lib/rotation.js).
            Derived from the queue, never stored. */}
        <Row icon="repeat" iconTint="var(--orange)" title={t("HOW_YOU_TRAIN" /* 训练方式 */)}>
          {externalQ
            ? <span className="small dim">{t("ROTATION" /* 轮换 */)} · {t("EXTERNALLY_MANAGED" /* 由外部管理 */)}</span>
            : <Segmented className="seg-inline"
                options={[{ value: 'week', label: t("FIXED_WEEK" /* 固定周 */) }, { value: 'rotation', label: t("ROTATION" /* 轮换 */) }]}
                value={mode} onChange={setScheduleMode} />}
        </Row>
        {/* Rotation chosen with no loop running yet: the loop is built on Plan. */}
        {mode === 'rotation' && !liveQ && <Row icon="calendar" iconTint="var(--orange)" title={t("BUILD_YOUR_LOOP_IN_PLAN" /* 在计划中创建循环 */)}
          accessory="chevron" onClick={() => nav('/plan')} />}
        {/* Monday or Sunday: the Plan list, the Home strip, the calendar grid and every "this
            week" total follow it. Stored as a getDay() index (see lib/format.js). */}
        <Row icon="calendar" iconTint="var(--orange)" title={t("WEEK_STARTS_ON" /* 一周开始于 */)}>
          <Segmented className="seg-inline"
            options={[{ value: MONDAY, label: t("MONDAY" /* 星期一 */) }, { value: SUNDAY, label: t("SUNDAY" /* 星期日 */) }]}
            value={weekStartOf(S)} onChange={v => update(s => { s.weekStart = v })} />
        </Row>
      </Section>
      <Section>
        <Row icon="clipboard" iconTint="var(--green)" title={t("LOAD_STARTER_PLAN" /* 加载入门计划 */)} accessory="chevron" onClick={starterPlanSheet} />
      </Section>
    </>,

    units: () => <>
      <Section>
        <SelectRow
          icon="globe" iconTint="var(--blue)" title={t("LANGUAGE" /* 语言 */)}
          value={lang} onChange={v => update(s => { s.lang = v; s.langAuto = false })}
          options={Object.entries(LANGS).map(([k, name]) => ({
            value: k, label: name,
            subtitle: INSTR_LANGS.includes(k) ? null : t("EXERCISE_INSTRUCTIONS_AREN_T_TRANSLATED_INTO_THIS_LANGUAGE_YET_SO_THEY_STAY" /* 动作说明还没有翻译成这种语言，所以暂时显示英文。 */),
          }))}
        />
        {ctx.nameLang && <>
          <Row icon="globe" iconTint="var(--purple)" title={t("ENGLISH_EXERCISE_NAMES" /* 英文动作名称 */)}
            subtitle={t("SHOW_THE_ENGLISH_NAME_IN_PARENTHESES_NEXT_TO_THE_TRANSLATED_ONE" /* 在译文旁以括号显示英文名称。 */)}>
            <Switch checked={S.enParens?.[baseLang(lang)] ?? true}
              disabled={S.enOnly?.[baseLang(lang)] === true}
              onChange={v => update(s => { s.enParens = { ...(s.enParens || {}), [baseLang(lang)]: v } })} />
          </Row>
          <Row icon="globe" iconTint="var(--purple)" title={t("ENGLISH_NAMES_ONLY" /* 仅使用英文名称 */)}
            subtitle={t("REPLACE_THE_TRANSLATED_NAMES_WITH_THE_ORIGINAL_ENGLISH_ONES" /* 用原始英文名称替换译文。 */)}>
            <Switch checked={S.enOnly?.[baseLang(lang)] === true}
              onChange={v => update(s => { s.enOnly = { ...(s.enOnly || {}), [baseLang(lang)]: v } })} />
          </Row>
        </>}
      </Section>
      <Section footer={t("SWITCHING_THE_UNIT_OFFERS_TO_CONVERT_EVERY_STORED_WEIGHT" /* 切换单位时会提示换算所有已保存的重量。 */)}>
        <Row icon="scale" iconTint="var(--teal)" title={t("WEIGHT_UNIT" /* 重量单位 */)}>
          <Segmented className="seg-inline"
            options={[{ value: 'kg', label: 'kg' }, { value: 'lb', label: 'lb' }]}
            value={S.unit} onChange={v => switchUnit(v)} />
        </Row>
        {/* Display only: one decimal reads fine for plate-loadable numbers, two for anyone whose
            per-side figure lands on .25 or .75, or who loads microplates (issue #139). Nothing is
            stored or rounded differently; lib/format.js fmtNum just prints what is already there. */}
        <Row icon="ruler" iconTint="var(--teal)" title={t("WEIGHT_DECIMALS" /* 重量小数位 */)} subtitle={t("HOW_PRECISELY_WEIGHTS_ARE_SHOWN" /* 重量显示的精确程度。 */)}>
          <Segmented className="seg-inline"
            options={[{ value: 1, label: t("ZERO_FIVE" /* 术语：0.5 */) }, { value: 2, label: t("ZERO_TWOFIVE" /* 术语：0.25 */) }]}
            value={S.wdec === 2 ? 2 : 1} onChange={v => update(s => { s.wdec = v })} />
        </Row>
        {/* Cardio speed (Discord "miles per hour"). Unlike the weight unit this converts nothing:
            speeds stay stored in km/h and only what is shown and typed follows it (lib/speed.js).
            Until chosen it follows the weight unit, so a profile in pounds already reads mph. */}
        <Row icon="figureRun" iconTint="var(--teal)" title={t("SPEED_UNIT" /* 速度单位 */)}>
          <Segmented className="seg-inline"
            options={[{ value: 'kmh', label: 'km/h' }, { value: 'mph', label: 'mph' }]}
            value={speedUnitOf(S)} onChange={v => update(s => { s.speedUnit = v })} />
        </Row>
        {/* Which formula turns a set into an estimated 1RM (Discord, #155): the exercise page,
            the 1RM chart and records all follow it. Formula names are people, not words. */}
        <SelectRow icon="chart" iconTint="var(--teal)" title={t("ONE_REP_MAX_FORMULA" /* 1RM 公式 */)}
          value={formulaOf(S)} onChange={v => update(s => { s.oneRmFormula = v })}
          options={[
            { value: 'epley', label: 'Epley', subtitle: t("THE_COMMON_ONE_A_BIT_GENEROUS_AT_HIGHER_REPS" /* 最常用的一种。次数较多时略偏宽松。 */) },
            { value: 'brzycki', label: 'Brzycki', subtitle: t("MORE_CONSERVATIVE_ABOVE_FIVE_REPS" /* 超过五次后更保守。 */) },
            { value: 'lombardi', label: 'Lombardi', subtitle: t("GENEROUS_ESPECIALLY_AT_HIGH_REPS" /* 偏宽松，尤其是次数较多时。 */) },
            { value: 'oconner', label: FORMULA_NAMES.oconner, subtitle: t("THE_MOST_CONSERVATIVE_OF_THE_CLASSICS" /* 经典公式中最保守的。 */) },
            { value: 'mayhew', label: 'Mayhew' },
            { value: 'wathan', label: 'Wathan' },
            { value: 'lander', label: 'Lander' },
            { value: 'weighted', label: t("BLEND_OF_ALL" /* 全部综合 */), subtitle: t("AVERAGES_SEVEN_FORMULAS_AND_READS_YOUR_RIR_WHEN_YOU_LOG_IT" /* 取七种公式的平均值，并在你记录 RIR 时一并参考。 */) },
          ]} />
      </Section>
    </>,

    equipment: () => <EquipmentCard S={S} update={update} />,

    look: () => <>
      <Section footer={DEMO || MOBILE || !user ? undefined : t("SYNCED_WITH_YOUR_PROFILE" /* 与档案同步 */)}>
        <Row icon="moon" iconTint="var(--indigo)" title={t("THEME" /* 主题 */)}>
          <Segmented
            className="seg-inline"
            options={[
              { value: 'dark', icon: 'moon', label: t("DARK" /* 深色 */) },
              { value: 'light', icon: 'sun', label: t("LIGHT" /* 浅色 */) },
              { value: 'system', icon: 'gear', label: t("SYSTEM" /* 跟随系统 */) },
            ]}
            value={S.theme || 'dark'}
            onChange={v => update(s => { s.theme = v })}
          />
        </Row>
        <div className="lrow" style={{ flexWrap: 'wrap', rowGap: 12, paddingBottom: 14 }}>
          <span className="lrow-i" style={{ '--tint': 'var(--purple)' }}><Icon name="palette" /></span>
          <span className="lrow-m"><span className="lrow-t">{t("ACCENT_COLOR" /* 强调色 */)}</span></span>
          <span className="lrow-v">{accentLabel(S)}</span>
          <AccentSwatches S={S} update={update} />
        </div>
        {/* How the muscle map is drawn. The exercise drawings follow it until they are set below. */}
        <Row icon="figureStrength" iconTint="var(--teal)" title={t("BODY_DIAGRAM" /* 身体图示 */)}>
          <Segmented
            className="seg-inline"
            options={[{ value: 'male', label: t("MALE" /* 男性 */) }, { value: 'female', label: t("FEMALE" /* 女性 */) }]}
            value={S.body === 'female' ? 'female' : 'male'}
            onChange={v => update(s => { s.body = v })}
          />
        </Row>
        {/* Which figure the exercise animations show where both exist (about 940 exercises; the
            rest are drawn once). Only the picture changes: the exercise and its id stay the same,
            so nothing logged is touched, on this device or any other. */}
        <Row icon="figureStrength" iconTint="var(--teal)" title={t("EXERCISE_DRAWINGS" /* 动作图示 */)}
          subtitle={t("WHERE_AN_EXERCISE_IS_DRAWN_ON_BOTH_FIGURES_YOUR_WORKOUTS_STAY_EXACTLY" /* 动作在两种人体图上都有绘制时，显示哪一种。你的训练记录保持原样。 */)}>
          <Segmented
            className="seg-inline"
            options={[{ value: 'male', label: t("MALE" /* 男性 */) }, { value: 'female', label: t("FEMALE" /* 女性 */) }]}
            value={figureOf(S)}
            onChange={v => update(s => { s.exFigure = v })}
          />
        </Row>
      </Section>
      <Section title={t("ON_HOME" /* 首页上 */)}>
        {/* Membership QR codes on Home (views/CheckIn.jsx); off = no Home card, no route. */}
        <Row icon="qr" iconTint="var(--blue)" title={t("GYM_CHECK_IN" /* 健身房签到 */)}
          subtitle={t("SHOW_A_CARD_ON_HOME_WITH_YOUR_MEMBERSHIP_QR_CODES" /* 在首页显示一张包含会员二维码的卡片。 */)}>
          <Switch checked={S.checkIn !== false} onChange={v => update(s => { s.checkIn = v })} />
        </Row>
        {/* The Home summary is optional; hiding it leaves weight logging, history and Stats intact. */}
        <Row icon="scale" iconTint="var(--green)" title={t("BODY_WEIGHT" /* 体重 */)}
          subtitle={t("SHOW_THE_BODY_WEIGHT_CARD_ON_HOME" /* 在首页显示体重卡片。 */)}>
          <Switch checked={S.showWeightCard !== false} onChange={v => update(s => { s.showWeightCard = v })} />
        </Row>
        {/* The bar at the top that says the app is offline, kept local, or not synced (#369, #330).
            Here and not under Server & sync, which a phone kept local never shows. Switching it on
            also brings back the no-server line its × hid (#454). */}
        {!DEMO && <Row icon="cloud" iconTint="var(--blue)" title={t("SHOW_CONNECTION_STATUS" /* 显示连接状态 */)}
          subtitle={t("OFF_THE_BAR_AT_THE_TOP_IS_HIDDEN_A_DOT_ON_HOME" /* 关闭：隐藏顶部的提示栏。同步卡住时，“首页”上的小圆点仍会提醒你。 */)}>
          <Switch checked={S.connStatus !== false} onChange={v => update(s => { s.connStatus = v; if (v) s.connLocal = true })} />
        </Row>}
      </Section>
    </>,

    data: () => <>
      <Section title={t("BACK_UP" /* 备份 */)}>
        <Row icon="share" iconTint="var(--blue)" title={t("EXPORT_BACKUP_JSON" /* 导出备份（JSON） */)} subtitle={hasMedia ? t("WITHOUT_PHOTOS_AND_VIDEOS" /* 不含照片和视频 */) : undefined} accessory="chevron" onClick={doExport} />
        {hasMedia && <Row icon="share" iconTint="var(--blue)" title={t("EXPORT_WITH_PHOTOS_VIDEOS_ZIP" /* 连同照片和视频导出（.zip） */)} accessory="chevron" onClick={doExportZip} />}
        {/* 14 is AUTO_BACKUP_KEEP in lib/mobile.js, written out because the Settings tests mock
            that module wholesale; mobile.autobackup.test.js pins the two together. */}
        {MOBILE && <Row icon="folder" iconTint="var(--blue)" title={t("AUTO_BACKUP_ON_CHANGES" /* 变更时自动备份 */)}
          subtitle={autoBackupSubtitle(android && S.autoBackup ? backupDir : null, 14)}>
          <Switch checked={!!S.autoBackup} onChange={v => update(s => { s.autoBackup = v })} />
        </Row>}
        {/* Android only: the system folder picker (#161). iOS shows Documents in Files already. */}
        {MOBILE && android && S.autoBackup && <BackupFolderRow />}
      </Section>
      {MOBILE && android && <HealthConnectCard S={S} toast={toast} />}
      <Section title={t("BRING_DATA_IN" /* 导入数据 */)}>
        <Row icon="download" iconTint="var(--teal)" title={t("IMPORT_BACKUP" /* 导入备份 */)} accessory="chevron" onClick={() => fileRef.current.click()} />
        <Row icon="download" iconTint="var(--teal)" title={t("IMPORT_FROM_ANOTHER_APP" /* 从其他应用导入 */)}
          subtitle={t("FITNOTES_STRONG_HEVY_OR_BODY_WEIGHT_FROM_APPLE_HEALTH" /* FitNotes、Strong、Hevy，或来自 Apple 健康的体重 */)}
          accessory="chevron" onClick={() => importRef.current.click()} />
        <Row icon="key" iconTint="var(--teal)" title={t("IMPORT_FROM_HEVY" /* 从 Hevy 导入 */)}
          subtitle={t("PULL_YOUR_HISTORY_WITH_A_HEVY_PRO_API_KEY" /* 使用 Hevy Pro API 密钥拉取训练记录 */)}
          accessory="chevron" onClick={importFromHevy} />
      </Section>
      {hasMedia && <Section><MediaRow /></Section>}
      <Section>
        <Row icon="trash" iconTint="var(--red)" title={t("RESET_EVERYTHING_A" /* 重置所有内容 */)} danger onClick={resetEverything} />
      </Section>
      <input ref={fileRef} type="file" accept=".json,.zip,application/json,application/zip" style={{ display: 'none' }} onChange={doImport} />
      {/* Reset after reading so picking the same file twice still fires onChange. */}
      <input ref={importRef} type="file" accept=".csv,.xml,text/csv,text/xml" style={{ display: 'none' }}
        onChange={ev => { const f = ev.target.files[0]; if (f) importFromApp(f); ev.target.value = '' }} />
    </>,

    about: () => <>
      {/* Updates. On Android the row is always there: it checks on demand and installs when a
          release is newer (checksum verified, see onUpdateRowClick). On the web the app updates
          with its server, so the row points at the APK for the phone instead. iOS has no APK. */}
      <Section footer={MOBILE ? (android ? t("RELEASES_ARE_CHECKED_ON_GITHUB_THE_DOWNLOAD_IS_VERIFIED_AGAINST_ITS_CHECKSUM" /* 版本在 GitHub 上检查。安装程序打开前会校验下载文件的校验和。 */) : null) : t("THE_WEB_APP_UPDATES_TOGETHER_WITH_YOUR_SERVER_THE_ANDROID_APP_INSTALLS" /* 网页应用随服务器一起更新。Android 应用在这里自行安装更新。 */)}>
        <Row icon="info" iconTint="var(--grey)" title={t("VERSION" /* 版本 */)} value={'v' + __APP_VERSION__} />
        {MOBILE
          ? android && <Row icon="download" iconTint="var(--green)"
              title={updateInfo?.hasUpdate ? t("UPDATE_TO_OPENGYM_V_COUNT" /* 更新到 openGym v{0} */, updateInfo.latestVersion) : t("CHECK_FOR_UPDATES" /* 检查更新 */)}
              subtitle={checking ? t("CHECKING" /* 正在检查… */) : t("YOU_HAVE_V_COUNT" /* 当前 v{0} */, __APP_VERSION__)}
              accessory="chevron"
              onClick={() => (updateInfo?.hasUpdate ? onUpdateRowClick() : checkNow())} />
          : <Row icon="download" iconTint="var(--green)" title={t("GET_THE_ANDROID_APP" /* 获取 Android 应用 */)}
              subtitle={t("DOWNLOAD_THE_APK_FROM_OPENGYM_CH" /* 从 opengym.ch 下载 APK */)} accessory="chevron"
              onClick={() => window.open('https://opengym.ch/#download', '_blank', 'noopener')} />}
      </Section>
      {/* "Add to Home screen": not inside the phone app, and not once it is installed. */}
      {!MOBILE && !standalone() && <Section title={t("TIP" /* 提示 */)}>
        <Row icon="share" iconTint="var(--blue)"
          title={IS_ANDROID ? t("IN_CHROME_MENU_ADD_TO_HOME_SCREEN" /* 在 Chrome 中：⋮ 菜单 → 添加到主屏幕 */) : t("IN_SAFARI_SHARE_ADD_TO_HOME_SCREEN" /* 在 Safari 中：分享 → 添加到主屏幕 */)}
          subtitle={t("TO_INSTALL_OPENGYM_AS_A_FULL_SCREEN_APP" /* 即可将 openGym 安装为全屏应用。 */) + ' ' + (user ? t("YOUR_DATA_SYNCS_WITH_YOUR_PROFILE_SIGN_IN_ANYWHERE_AND_IT_S" /* 你的数据随档案同步。在任何地方登录，数据都在。 */) : t("GUEST_DATA_STAYS_ON_THIS_DEVICE_SO_EXPORT_A_BACKUP_NOW_AND" /* 访客数据只保存在本设备上，记得时不时导出备份！ */))} />
      </Section>}
      {/* The version, where the support template tells people to look for it. On the phone
          build there is no address bar and no about box, so without this there is no way to tell
          which build you are running, or whether an update actually installed. */}
      <div className="dim small sp-version">
        openGym v{__APP_VERSION__} · {t("FREE_OPEN_SOURCE_AGPL_VTHREE" /* 免费且开源（AGPL v3） */)}<br />
        <a href="https://github.com/DuarteSantos8/openGym" target="_blank" rel="noopener">{t("SOURCE_CODE" /* 源代码 */)}</a><br />
        {/* Attribution the media licence asks for word for word (agreement §8c), so it is not translated */} {t("EXERCISE_MEDIA_ALIAKSANDR_MAKATSERCHYK" /* 动作素材 © Aliaksandr Makatserchyk， */)} <a href="https://gymvisual.com/" target="_blank" rel="noopener">Gym visual</a>{t("GYMVISUAL_COM_MEDIA_LICENSED_FOR_USE_IN_OPENGYM_ONLY_SEE" /* ，gymvisual.com。素材仅授权在 openGym 中使用，详见 */)} <a href="https://github.com/DuarteSantos8/openGym/blob/main/NOTICE.md" target="_blank" rel="noopener">NOTICE.md</a>
      </div>
    </>,

    account: () => <>
      {/* The server: which one, which account, how that stands, "Sync now". A paired phone's
          Admin and Disconnect sit in the same block; a browser's account rows follow in their own. */}
      {user && !DEMO && <ServerSyncSection>
        {MOBILE && <>
          {user.admin && <Row icon="crown" iconTint="var(--indigo)" title={t("ADMIN_DASHBOARD" /* 管理后台 */)} accessory="chevron" onClick={() => nav('/admin')} />}
          <AccountIdRow id={user.id} />
          <Row icon="signOut" iconTint="var(--red)" title={t("DISCONNECT" /* 断开连接 */)} danger onClick={disconnect} />
        </>}
      </ServerSyncSection>}

      {/* account (demo and mobile builds have nothing to sign in to) */}
      {!(MOBILE && user) && <Section title={MOBILE ? t("YOUR_DATA" /* 你的数据 */) : DEMO ? t("DEMO" /* 演示 */) : t("ACCOUNT" /* 账号 */)}>
        {MOBILE ? <>
          <Row icon="lock" iconTint="var(--acc)" title={t("ALL_DATA_STAYS_ON_THIS_PHONE" /* 所有数据都保存在这部手机上 */)} subtitle={t("NO_ACCOUNT_NO_CLOUD_BACK_IT_UP_ANYTIME_IN_DATA_BACKUP" /* 无需账号，也没有云端。随时在“数据与备份”里备份。 */)} />
          <Row icon="cloud" iconTint="var(--indigo)" title={t("CONNECT_TO_MY_SERVER" /* 连接到我的服务器 */)} subtitle={t("SYNC_THIS_DEVICE_TO_YOUR_OWN_SELF_HOSTED_OPENGYM_INSTEAD" /* 改为将此设备与你自己的自托管 openGym 同步。 */)} accessory="chevron"
            onClick={connectServer} />
          <KeptChangesRows />
        </> : DEMO ? <>
          <Row icon="info" iconTint="var(--acc)" title={t("YOU_RE_IN_THE_DEMO" /* 你正在演示模式中 */)} subtitle={t("EXAMPLE_DATA_STORED_ONLY_IN_THIS_BROWSER_GO_WILD_AND_CHANGE_ANYTHING" /* 示例数据，只保存在此浏览器中。放开玩，想改什么就改什么。 */)} />
          <Row icon="reset" iconTint="var(--blue)" title={t("RESET_DEMO_DATA" /* 重置演示数据 */)} accessory="chevron"
            onClick={() => confirmSheet({ title: t("RESET_DEMO_DATA_A" /* 重置演示数据？ */), message: t("PUTS_THE_EXAMPLE_PLAN_WORKOUTS_AND_WEIGH_INS_BACK_THE_WAY_THEY" /* 将示例计划、训练和体重记录恢复到最初的样子。 */), confirmText: t("RESET" /* 重置 */), onConfirm: () => { resetDemo(); nav('/home'); toast(t("DEMO_DATA_RESET" /* 演示数据已重置 */)) } })} />
          <Row icon="rocket" iconTint="var(--indigo)" title={t("SELF_HOST_OPENGYM" /* 自托管 openGym */)} subtitle={t("PASSKEY_SIGN_IN_SYNC_ACROSS_YOUR_DEVICES_YOUR_OWN_DATA" /* 通行密钥登录、多设备同步、数据归你所有。 */)} accessory="chevron"
            onClick={() => window.open(REPO, '_blank', 'noopener')} />
        </> : user ? <>
          {user.admin && <Row icon="crown" iconTint="var(--indigo)" title={t("ADMIN_DASHBOARD" /* 管理后台 */)} accessory="chevron" onClick={() => nav('/admin')} />}
          <PasskeysRow state={passkeys.st} changed={credsChanged} />
          <DeviceLinkRow state={passkeys.st} />
          <Row icon="qr" iconTint="var(--blue)" title={t("PAIR_THE_MOBILE_APP" /* 配对手机应用 */)} subtitle={t("CONNECT_THE_OPENGYM_APP_ON_YOUR_PHONE_TO_THIS_ACCOUNT" /* 将手机上的 openGym 应用连接到此账户。 */)} accessory="chevron"
            onClick={() => useUI.getState().openSheet(close => <PairSheet close={close} />)} />
          {pwOn && <PasswordRow version={credsV} />}
          <Row icon="signOut" iconTint="var(--red)" title={t("SIGN_OUT_A" /* 退出登录 */)} danger onClick={signOutHere} />
          <Row icon="shield" iconTint="var(--red)" title={t("SIGN_OUT_EVERYWHERE_A" /* 在所有设备上退出登录 */)} subtitle={t("ENDS_THIS_PROFILE_S_SESSIONS_ON_ALL_YOUR_DEVICES" /* 结束此档案在你所有设备上的会话。 */)} danger onClick={signOutEverywhere} />
          <AccountIdRow id={user.id} />
        </> : webauthnOK() ? <>
          <Row icon="plusCircle" iconTint="var(--acc)" title={t("CREATE_PASSKEY_PROFILE" /* 创建通行密钥档案 */)} subtitle={t("KEEPS_YOUR_DATA_SAFE_AND_SEPARATE_PER_PERSON" /* 让你的数据安全，并按人分开保存。 */)} accessory="chevron" onClick={registerHere} />
          <Row icon="fingerprint" iconTint="var(--blue)" title={t("SIGN_IN_WITH_PASSKEY" /* 用通行密钥登录 */)} accessory="chevron" onClick={passkeySignIn} />
          {/* The Login screen offers both of these; a guest who skipped it had no way to either from here. */}
          {pwOn && <Row icon="plusCircle" iconTint="var(--orange)" title={t("CREATE_PROFILE_WITH_A_PASSWORD" /* 用密码创建个人资料 */)} accessory="chevron" onClick={openPasswordRegister} />}
          {pwOn && <Row icon="key" iconTint="var(--orange)" title={t("SIGN_IN_WITH_PASSWORD" /* 用密码登录 */)} accessory="chevron" onClick={() => openPasswordSignIn()} />}
          <Row icon="qr" iconTint="var(--blue)" title={t("USE_A_CODE_FROM_YOUR_OTHER_DEVICE" /* 使用另一台设备上的代码 */)} accessory="chevron" onClick={openDeviceLinkRedeem} />
          <KeptChangesRows />
        </> : pwOn ? <>
          {/* No passkeys in this browser (plain http on a LAN address, say): a password is the way in. */}
          <Row icon="plusCircle" iconTint="var(--acc)" title={t("CREATE_NEW_PROFILE" /* 创建新档案 */)} subtitle={t("KEEPS_YOUR_DATA_SAFE_AND_SEPARATE_PER_PERSON" /* 让你的数据安全，并按人分开保存。 */)} accessory="chevron" onClick={openPasswordRegister} />
          <Row icon="key" iconTint="var(--orange)" title={t("SIGN_IN_WITH_PASSWORD" /* 用密码登录 */)} accessory="chevron" onClick={() => openPasswordSignIn()} />
          <KeptChangesRows />
        </> : <>
          <Row icon="lock" iconTint="var(--grey)" title={t("PASSKEYS_NOT_SUPPORTED_IN_THIS_BROWSER" /* 此浏览器不支持通行密钥。 */)} />
          <KeptChangesRows />
        </>}
      </Section>}
      {/* The connection banner already says this to a guest; the line is for when it is switched
          off, or its × hid it (#454). */}
      {!user && !DEMO && !MOBILE && !(showsConnection(S) && showsLocalLine(S)) && <p className="sect-f" style={{ marginTop: -18, marginBottom: 22 }}>{t("GUEST_MODE_YOUR_DATA_LIVES_ONLY_IN_THIS_BROWSER" /* 访客模式：你的数据只保存在此浏览器中。 */)}</p>}
    </>,
  }

  /* ---------------- a page ---------------- */
  if (page && pages[page]) {
    const parent = PAGES[page].parent
    return <div className="narrow" ref={body}>
      <div className="sp-nav">
        {/* Named by what it says ("Settings", "Workout"), so a voice command for the visible
            word finds it; the chevron is hidden from assistive tech. */}
        <button className="sp-back" onClick={back}>
          <Icon name="chevronLeft" /><span>{parent ? translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(PAGES[parent].title) : t("SETTINGS" /* 设置 */)}</span>
        </button>
        <h1 className="sp-title">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(PAGES[page].title)}</h1>
      </div>
      {pages[page]()}
    </div>
  }

  /* ---------------- the root ---------------- */
  return <SettingsRoot ctx={ctx} preview={preview} open={open} user={user} sync={sync}
    home={() => nav('/home')} go={(hit) => {
      if (hit.page === 'coach') { nav('/coach/setup'); return }
      nav('/settings/' + hit.page, hit.isPage ? undefined : { state: hit.via ? { find: hit.title, via: hit.via } : { find: hit.title } })
    }} />
}

function SettingsRoot({ ctx, preview, open, user, sync, home, go }) {
  // The router's key for this history entry (what useLocation().key reads), taken once.
  const [key] = useState(() => window.history.state?.key || null)
  const [q, setQ] = useState(() => (key && lastQuery.key === key ? lastQuery.q : ''))
  const set = v => { lastQuery = { q: v, key }; setQ(v) }
  const hits = q.trim() ? searchSettings(q, ctx) : null
  // The account card: who this is, and the one line that matters about it.
  const acct = DEMO ? { title: t("DEMO" /* 演示 */), sub: t("EXAMPLE_DATA_ONLY_IN_THIS_BROWSER" /* 示例数据，仅保存在此浏览器中。 */) }
    : user ? {
      title: user.name || t("ACCOUNT" /* 账号 */),
      sub: sync && sync.status && sync.status !== 'ok' ? t("SYNC_NEEDS_A_LOOK" /* 同步需要查看一下 */) : MOBILE ? t("SYNCED_WITH_YOUR_SERVER" /* 已与你的服务器同步 */) : t("ACCOUNT_DEVICES_AND_SYNC" /* 账号、设备与同步 */),
    }
    : MOBILE ? { title: t("THIS_PHONE" /* 这部手机 */), sub: t("ALL_DATA_STAYS_ON_THIS_PHONE" /* 所有数据都保存在这部手机上 */) }
    : { title: t("GUEST" /* 访客 */), sub: t("YOUR_DATA_LIVES_ON_THIS_DEVICE_SIGN_IN_TO_SYNC" /* 你的数据保存在这台设备上。登录即可同步。 */) }
  const initial = user && !DEMO ? String(user.name || '?').trim().charAt(0).toUpperCase() : null
  return <div className="narrow">
    <div className="sp-nav">
      <button className="sp-back" onClick={home} aria-label={t("HOME" /* 首页 */)}><Icon name="chevronLeft" /><span>{t("HOME" /* 首页 */)}</span></button>
    </div>
    <h1 className="sp-root-title">{t("SETTINGS" /* 设置 */)}</h1>
    <div className="sp-search">
      <SearchField value={q} onChange={e => set(e.target.value)} onClear={() => set('')}
        placeholder={t("SEARCH" /* 搜索… */)} aria-label={t("SEARCH_SETTINGS" /* 搜索设置 */)} inputMode="search" enterKeyHint="search" autoComplete="off" />
    </div>
    {hits ? (hits.length ? <Section title={tn("COUNT_RESULT" /* {0} 个结果 */, "COUNT_RESULTS" /* {0} 个结果 */, hits.length)}>
      {hits.slice(0, 40).map(h => (
        <Row key={h.page + ':' + h.title} icon={h.icon} iconTint={h.tint} title={h.label} subtitle={h.trail} accessory="chevron" onClick={() => go(h)} />
      ))}
    </Section> : <div className="sp-empty">{t("NO_SETTING_MATCHES_COUNT" /* 没有与“{0}”匹配的设置。 */, q.trim())}</div>) : <>
      <Section>
        <button className="lrow tap sp-acct" onClick={() => open('account')}>
          <span className={'sp-avatar' + (initial ? ' on' : '')} aria-hidden="true">{initial || <Icon name="personCircle" />}</span>
          <span className="lrow-m"><span className="lrow-t">{acct.title}</span><span className="lrow-s">{acct.sub}</span></span>
          <Icon name="chevronRight" className="lrow-c" />
        </button>
      </Section>
      {ROOT_GROUPS.map(g => g.filter(id => pageVisible(id, ctx))).filter(g => g.length).map(g => (
        <Section key={g[0]}>
          {g.map(id => <Row key={id} icon={PAGES[id].icon} iconTint={PAGES[id].tint} title={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(PAGES[id].title)}
            value={preview[id]?.() || null} accessory="chevron" onClick={() => open(id)} className="sp-root-row" />)}
        </Section>
      ))}
      <div className="dim small sp-version">openGym v{__APP_VERSION__}</div>
    </>}
  </div>
}

// The whole point is that the two scales are one judgement counted from opposite ends, and a
// paragraph is a bad way to say that — the conversion table shows it in one look. Reading down
// a column is the answer to "what do I put here", so the numbers get their own aligned columns.
const EFFORT_ROWS = [
  ['0', '10', 'Nothing left, went to failure'],
  ['1', '9', 'One more rep in the tank'],
  ['2', '8', 'Two more reps'],
  ['3', '7', 'Three more reps'],
  ['4+', '≤6', 'Easy, warm-up territory'],
]
// RIR 2 / RPE 8: the row a working set usually lands on — the anchor the others are read
// against. Not where the stepper starts; + walks up from the bottom of the scale.
const EFFORT_TYPICAL = 2


// Download progress sheet — receives a ref callback that exposes a (received, total) setter.
// Uses forwardRef so the caller can push byte counts in without re-rendering the whole Settings tree.
const DownloadProgress = forwardRef(function DownloadProgress(_, ref) {
  const [pct, setPct] = useState(0)
  const [text, setText] = useState(t("STARTING_DOWNLOAD" /* 正在开始下载… */))
  // Expose a setter the caller can invoke directly
  if (ref) ref(function update(received, total) {
    if (total > 0) {
      const p = Math.min(100, Math.round((received / total) * 100))
      setPct(p)
      setText(t("COUNT" /* 术语：{0}% */, p))
    } else {
      setText(t("COUNT_MB" /* 术语：{0} MB */, (received / 1_000_000).toFixed(1)))
    }
  })
  return (
    <div style={{ textAlign: 'center', padding: '8px 0' }}>
      <h3>{t("DOWNLOADING_UPDATE" /* 正在下载更新… */)}</h3>
      <div style={{ margin: '16px 0', height: 6, borderRadius: 3, background: 'var(--fill-3)', overflow: 'hidden' }}>
        <div style={{ height: '100%', width: pct + '%', background: 'var(--acc)', borderRadius: 3, transition: 'width .2s' }} />
      </div>
      <div className="muted small">{text}</div>
    </div>
  )
})

// Settings → Sound (#306): every end-of-rest sound, each played as it is picked so you hear it
// before the next rest does. The sheet stays open for the next one; Done closes it. Stored as
// S.restSound, with S.classicChime kept for an app from before (lib/rest-sounds.js restSoundOf).
const REST_SOUND_LABEL = { chime: "CHIME_LOUDER" /* 铃声（更响） */, classic: "CLASSIC_BEEPS" /* 经典哔声 */, bell: "BELL" /* 铃声 */, beep: "BEEP_BEEP" /* 哔哔 */, whistle: "WHISTLE" /* 哨子 */, soft: "SOFT" /* 柔和 */ }
const REST_SOUND_HINT = {
  classic: "THE_QUIETER_THREE_BEEP_SOUND_FROM_BEFORE_ONE_THREE_NINE_INSTEAD_OF" /* 使用 1.3.9 版本之前更轻柔的三声提示音，而不是更响亮的铃声。 */,
  bell: "DING_DONG_REST_IS_OVER_CLASS_IS_IN" /* 叮咚。休息结束，回来上课。 */,
  beep: "YOUR_SPORTS_WATCH_CALLING_YOU_BACK" /* 你的运动手表在叫你回来。 */,
  whistle: "COACH_WANTS_YOU_BACK_ON_THE_BAR" /* 教练等你回到杠铃前。 */,
  soft: "GENTLE_FOR_HEADPHONES_OR_A_QUIET_ROOM" /* 轻柔，适合耳机或安静的房间。 */,
}
export function pickRestSound(id) {
  unlock(true)
  useStore.getState().update(s => { s.restSound = id; s.classicChime = id === 'classic' })
  chime(true, id)
}
export function RestSoundSheet({ close }) {
  const S = useStore(s => s.S)
  const cur = restSoundOf(S)
  return <>
    <h3>{t("SOUND" /* 提示音 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("TAP_ONE_TO_HEAR_IT" /* 点一下就能试听。 */)}</div>
    <Section>
      {REST_SOUND_IDS.map(id => <Row key={id} icon={id === cur ? 'speaker' : 'play'} iconTint="var(--pink)" title={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(REST_SOUND_LABEL[id])}
        subtitle={REST_SOUND_HINT[id] ? translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(REST_SOUND_HINT[id]) : null} accessory={id === cur ? 'check' : 'none'}
        onClick={() => pickRestSound(id)} />)}
    </Section>
    <div style={{ height: 14 }} />
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}
const restSoundSheet = () => useUI.getState().openSheet(close => <RestSoundSheet close={close} />)

function effortHelpSheet() {
  useUI.getState().openSheet(close => <>
    <h3>{t("EFFORT_PER_SET" /* 每组强度 */)}</h3>
    <div className="muted small" style={{ lineHeight: 1.5 }}>
      {t("HOW_HARD_A_SET_WAS_LOGGED_NEXT_TO_WEIGHT_AND_REPS_TWO" /* 记录这一组有多吃力，就写在重量和次数旁边。同一个判断的两种标度，只是从相反的一端开始数。 */)}
    </div>
    <div className="efftbl">
      <div className="r hd"><span className="n">{t("RIR" /* 术语：RIR */)}</span><span className="n">{t("RPE" /* 术语：RPE */)}</span><span className="f">{t("HOW_IT_FELT" /* 感受 */)}</span></div>
      {EFFORT_ROWS.map(([rir, rpe, feel], i) => (
        <div key={rir} className={'r' + (i === EFFORT_TYPICAL ? ' on' : '')}>
          <span className="n">{rir}</span><span className="n">{rpe}</span><span className="f">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(feel)}</span>
        </div>
      ))}
    </div>
    <div className="dim small" style={{ lineHeight: 1.5, display: 'grid', gap: 8 }}>
      <div>{t("RIR_COUNTS_THE_REPS_YOU_LEFT_IN_THE_TANK_RPE_READS_THE" /* RIR 数的是你还留了几次；RPE 把同样的吃力程度放到 10 分制里来读，所以 RPE ≈ 10 − RIR。选你习惯的那种就行。 */)}</div>
      <div>{t("THE_HIGHLIGHTED_ROW_IS_WHERE_MOST_WORKING_SETS_LAND_SETS_YOU_HAVE" /* 高亮那一行是大多数工作组落在的位置。已经记录的组保留原来的标度，而且别的地方不会读取这个值，所以进阶和估算 1RM 都不受影响。 */)}</div>
    </div>
    <div style={{ height: 8 }} />
  </>)
}

function NotificationsCard({ S, update, toast }) {
  if (MOBILE) return <MobileReminderCard S={S} update={update} toast={toast} />
  return <PushCard S={S} update={update} toast={toast} />
}

// Mobile build: the reminder is a native local notification scheduled on planned weekdays —
// no push server involved. The schedule itself is (re)synced by the store on every persist;
// this card only owns the OS permission prompt when the switch turns on.
function MobileReminderCard({ S, update, toast }) {
  const setReminder = patch => update(s => { s.reminder = { ...(s.reminder || DEF.reminder), ...patch, tz: localTZ() } })
  const toggle = async () => {
    const on = !S.reminder?.on
    if (on) {
      const ok = await syncReminder({ ...S, reminder: { ...(S.reminder || DEF.reminder), on: true } }, true)
      if (!ok) { toast(t("COULD_NOT_CHANGE_NOTIFICATION_SETTINGS" /* 无法更改通知设置 */)); return }
    }
    setReminder({ on })
  }
  return (
    <Section title={t("NOTIFICATIONS" /* 通知 */)}
      footer={S.reminder?.on ? t("REMINDS_YOU_AT_THIS_TIME_ON_DAYS_THAT_HAVE_A_ROUTINE_PLANNED" /* 在安排了训练计划的日子，此时间提醒你。 */) + nudgeNote(S) : null}>
      <Row icon="calendar" iconTint="var(--orange)" title={t("WORKOUT_DAY_REMINDER" /* 训练日提醒 */)}>
        <Switch checked={!!S.reminder?.on} onChange={toggle} />
      </Row>
      {S.reminder?.on && (
        <Row icon="clock" iconTint="var(--purple)" title={t("REMINDER_TIME" /* 提醒时间 */)}>
          <input type="time" className="timef" value={S.reminder?.time || DEF.reminder.time}
            onChange={e => setReminder({ time: e.target.value })} />
        </Row>
      )}
      {S.reminder?.on && <NudgeRows S={S} setReminder={setReminder} />}
    </Section>
  )
}

// The missed-workout nudge (lib/nudge.js): a switch and its tone, under the reminder they ride
// on — the server sends it with the same push (or the phone schedules it beside the reminder).
function NudgeRows({ S, setReminder }) {
  const r = S.reminder || {}
  return <>
    <Row icon="bell" iconTint="var(--red)" title={t("NUDGE_ME_WHEN_I_SKIP_A_PLANNED_WORKOUT" /* 跳过计划训练时提醒我 */)}>
      <Switch checked={!!r.nudge} onChange={() => setReminder({ nudge: !r.nudge })} />
    </Row>
    {r.nudge && (
      <SelectRow icon="chat" iconTint="var(--blue)" title={t("NUDGE_TONE" /* 提醒语气 */)}
        value={toneOf(r)} onChange={v => setReminder({ tone: v })}
        options={NUDGE_TONES.map(k => ({ value: k, label: toneLabel(k), subtitle: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(NUDGE_COPY[k].title) }))} />
    )}
  </>
}
const toneLabel = k => k === 'guilt' ? t("GUILT_TRIP" /* 情感攻势 */) : k === 'drill' ? t("DRILL_SERGEANT" /* 魔鬼教官 */) : t("FRIENDLY" /* 友好 */)
const nudgeNote = S => S.reminder?.nudge
  ? ' ' + t("ONE_NUDGE_IN_THE_EVENING_OF_A_PLANNED_DAY_WITH_NOTHING_LOGGED" /* 在计划训练日没有记录时，于晚上 20:00 到 21:30 之间提醒一次。连续错过 3 天后会保持安静，直到你下次训练。 */)
  : ''

function PushCard({ S, update, toast }) {
  const [on, setOn] = useState(false)
  const [busy, setBusy] = useState(false)
  const supported = pushSupported()

  // "On" means the server holds this browser's subscription, not merely that the browser has
  // one: a row the instance dropped (dead send, rebuilt db.json) left the switch on with nothing
  // ever arriving. syncPushSubscription re-registers on the way; if the server cannot be asked
  // (offline), the browser's side is the best answer available.
  useEffect(() => {
    if (!supported) return
    let gone = false
    syncPushSubscription()
      .then(ok => { if (!gone) setOn(ok) })
      .catch(() => navigator.serviceWorker.ready.then(reg => reg.pushManager.getSubscription()).then(sub => { if (!gone) setOn(!!sub) }).catch(() => {}))
    return () => { gone = true }
  }, [supported])

  const toggle = async v => {
    setBusy(true)
    try {
      if (!v) { await disablePush(); setOn(false); toast(t("NOTIFICATIONS_OFF" /* 通知已关闭 */)) }
      else { await enablePush(); setOn(true); toast(t("NOTIFICATIONS_ON" /* 通知已开启 */)) }
    } catch (e) { toast(e.message || t("COULD_NOT_CHANGE_NOTIFICATION_SETTINGS" /* 无法更改通知设置 */)) }
    setBusy(false)
  }
  const test = async () => {
    try { await sendTestPush(); toast(t("TEST_SENT_SHOULD_POP_UP_ANY_SECOND" /* 测试已发送！马上就到 */)) }
    catch (e) { toast(e.message || t("TEST_FAILED" /* 测试失败 */)) }
  }

  if (!supported) return (
    <Section title={t("NOTIFICATIONS" /* 通知 */)}>
      <Row icon="bellSlash" iconTint="var(--grey)" title={t("NOT_SUPPORTED_IN_THIS_BROWSER" /* 此浏览器不支持。 */)} />
    </Section>
  )

  return <>
    <Section
      title={t("NOTIFICATIONS" /* 通知 */)}
      footer={on && S.reminder?.on
        ? t("ONLY_SENT_ON_DAYS_YOU_HAVE_A_ROUTINE_PLANNED_AND_HAVEN_T" /* 仅在安排了训练且尚未记录的日子发送。 */) +
          (S.reminder?.tz ? ' ' + t("TIMEZONE_COUNT_AUTO_DETECTED_UPDATES_IF_YOU_TRAVEL" /* 时区：{0}（自动检测，旅行时自动更新）。 */, S.reminder.tz) : '') +
          nudgeNote(S)
        : null}
    >
      <Row icon="bell" iconTint="var(--red)" title={t("PUSH_NOTIFICATIONS" /* 推送通知 */)} subtitle={t("REST_TIMER_ALERTS_EVEN_IF_OPENGYM_IS_CLOSED" /* 休息计时提醒，即使 openGym 已关闭。 */)}>
        <Switch checked={on} disabled={busy} onChange={toggle} />
      </Row>
      {on && (
        <Row icon="calendar" iconTint="var(--orange)" title={t("WORKOUT_DAY_REMINDER" /* 训练日提醒 */)}>
          <Switch checked={!!S.reminder?.on} onChange={() => update(s => { s.reminder = { ...(s.reminder || DEF.reminder), on: !s.reminder?.on, tz: localTZ() } })} />
        </Row>
      )}
      {on && S.reminder?.on && (
        <Row icon="clock" iconTint="var(--purple)" title={t("REMINDER_TIME" /* 提醒时间 */)}>
          <input type="time" className="timef" value={S.reminder?.time || DEF.reminder.time}
            onChange={e => update(s => { s.reminder = { ...(s.reminder || DEF.reminder), time: e.target.value, tz: localTZ() } })} />
        </Row>
      )}
      {on && S.reminder?.on && (
        <NudgeRows S={S} setReminder={patch => update(s => { s.reminder = { ...(s.reminder || DEF.reminder), ...patch, tz: localTZ() } })} />
      )}
    </Section>
    {on && <div style={{ marginTop: -12, marginBottom: 22 }}><Button size="sm" icon="bell" onClick={test}>{t("SEND_TEST_NOTIFICATION" /* 发送测试通知 */)}</Button></div>}
  </>
}

// Equipment profiles ("Home", "Gym", ...) — each an id/name/eq-list; the active one filters
// the Library, exercise picker, and flags routine entries that need something outside it
// (see lib/equipment.js). Purely local/synced state — no server changes needed.
// What the chosen accent is called: a preset's colour name, or the user's own.
function accentLabel(S) {
  const k = accentKey(S)
  return k === CUSTOM ? t("YOUR_OWN_COLOR" /* 你自己的颜色 */) : translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ACCENT_NAMES[k] || "GREEN" /* 绿色 */)
}

/**
 * The presets, then one swatch for a colour of the user's own (lib/accent.js). With no colour
 * of their own yet it is a rainbow ring, and a tap opens the system colour picker straight away.
 * Once there is one it is filled with it: a tap picks it again (it is kept while a preset is
 * chosen), and a tap on it while it is the accent opens the picker to change it. The picker is
 * the native <input type="color"> laid over the swatch, so the tap that opens it is the user's
 * own, which iOS Safari and the Android WebView both want.
 */
// How long the colour picker has to rest before a colour is saved, when the browser sends no
// `change` at the end (it should, once the picker closes).
const OWN_COLOR_SETTLE_MS = 400

function AccentSwatches({ S, update }) {
  const key = accentKey(S)
  const own = cleanHex(S.accentCustom)
  const onCustom = key === CUSTOM
  const pickPreset = k => { update(s => { s.accent = k }); setRestAccent(k) }
  const pickOwn = hex => {
    const c = cleanHex(hex)
    if (!c || (onCustom && c === own)) return
    update(s => { s.accent = CUSTOM; s.accentCustom = c })
    setRestAccent(c)
  }
  // The picker sends a colour for every step of a drag (React's onChange is the `input` event).
  // Those only repaint the page; the colour is saved, synced and sent to the native countdown
  // once: on the picker's `change`, after it has rested a moment, or when Settings closes.
  const inputRef = useRef(null)
  const pending = useRef(null)
  const timer = useRef(0)
  const pickOwnRef = useRef(pickOwn)
  pickOwnRef.current = pickOwn
  const commit = () => {
    clearTimeout(timer.current)
    const c = pending.current
    pending.current = null
    if (c) pickOwnRef.current(c)
  }
  const preview = hex => {
    const c = cleanHex(hex)
    if (!c) return
    const de = document.documentElement
    applyAccent(de, c, de.dataset.theme)
    pending.current = c
    clearTimeout(timer.current)
    timer.current = setTimeout(commit, OWN_COLOR_SETTLE_MS)
  }
  const hasInput = !(own && !onCustom)
  useEffect(() => {
    const el = inputRef.current
    if (!el) return
    const onChange = () => { pending.current = cleanHex(el.value) || pending.current; commit() }
    el.addEventListener('change', onChange)
    return () => el.removeEventListener('change', onChange)
  }, [hasInput]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => commit, []) // eslint-disable-line react-hooks/exhaustive-deps
  // The input is not controlled (React would put the saved colour back after every drag step);
  // a colour changed elsewhere (sync, another tab) is put in by hand.
  useEffect(() => {
    if (!pending.current && inputRef.current) inputRef.current.value = own || '#30d158'
  }, [own])
  const ownLabel = t("YOUR_OWN_COLOR" /* 你自己的颜色 */)
  const grey = own && isGrey(own)
  const notes = own && onCustom ? [
    adjustedIn(own, 'dark') && (grey ? t("GREYS_SHOW_LIGHTER_IN_DARK_MODE_SO_BUTTONS_DON_T_LOOK_SWITCHED" /* 深色模式下灰色会调亮一些，免得按钮看起来像被停用了。 */) : t("A_TOUCH_LIGHTER_IN_DARK_MODE_SO_YOU_CAN_STILL_READ_IT" /* 深色模式下会稍微调亮一点，好让你看得清。 */)),
    adjustedIn(own, 'light') && (grey ? t("GREYS_SHOW_DARKER_IN_LIGHT_MODE_SO_BUTTONS_DON_T_LOOK_SWITCHED" /* 浅色模式下灰色会调暗一些，免得按钮看起来像被停用了。 */) : t("A_TOUCH_DARKER_IN_LIGHT_MODE_SO_YOU_CAN_STILL_READ_IT" /* 浅色模式下会稍微调暗一点，好让你看得清。 */)),
  ].filter(Boolean) : []
  return <>
    <div className="swatches" style={{ flexBasis: '100%', paddingInlineStart: 41 }}>
      {Object.entries(ACCENTS).map(([k, c]) => (
        <button key={k} className={'swatch' + (key === k ? ' on' : '')}
          style={{ background: c }} onClick={() => pickPreset(k)} aria-label={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ACCENT_NAMES[k] || k)} />
      ))}
      {!hasInput
        ? <button className="swatch swatch-own" style={{ background: own }} onClick={() => pickOwn(own)} aria-label={ownLabel} />
        : <span className={'swatch swatch-own' + (own ? ' on' : ' unset')} style={own ? { background: own, color: inkOn(own) } : undefined}>
          {own ? <Icon name="pencil" /> : <Icon name="plus" />}
          <input ref={inputRef} type="color" className="swatch-input" defaultValue={own || '#30d158'}
            onChange={e => preview(e.target.value)}
            aria-label={own ? t("CHANGE_YOUR_OWN_COLOR" /* 更改你自己的颜色 */) : t("PICK_YOUR_OWN_COLOR" /* 选择你自己的颜色 */)} />
        </span>}
    </div>
    {notes.map(n => <span key={n} className="lrow-s swatch-note" style={{ flexBasis: '100%', paddingInlineStart: 41 }}>{n}</span>)}
  </>
}

function EquipmentCard({ S, update }) {
  const profiles = S.equipProfiles || []
  const remove = p => confirmSheet({
    title: t("DELETE_PROFILE" /* 删除配置？ */), message: t("COUNT_AND_ITS_EQUIPMENT_LIST_WILL_BE_REMOVED" /* “{0}”及其器械清单将被删除。 */, p.name),
    confirmText: t("DELETE" /* 删除 */), danger: true,
    onConfirm: () => update(s => {
      s.equipProfiles = (s.equipProfiles || []).filter(x => x.id !== p.id)
      if (s.activeEquipId === p.id) s.activeEquipId = (s.equipProfiles[0] && s.equipProfiles[0].id) || null
    }),
  })
  // The plates you own, per unit (lib/plates.js) — what the set rows' plate lines load from.
  const plateSummary = ownsPlates(S)
    ? inventoryFor(S).map(p => fmtPlate(p.w) + '×' + p.n).join(' · ') || t("NONE" /* 无 */)
    : t("STANDARD_SET_TAP_TO_COUNT_THE_PAIRS_YOU_OWN" /* 标准配置。点按以清点你拥有的对数。 */)
  // The dumbbells you own, per unit (lib/dumbbells.js): what dumbbell lifts step and progress over.
  const bells = dumbbellsOf(S)
  const dumbbellSummary = bells.length
    ? bells.map(fmtPlate).join(' · ')
    : t("ANY_WEIGHT_TAP_TO_LIST_THE_ONES_YOU_OWN" /* 任意重量。点一下列出你有的哑铃。 */)
  return <Section title={t("EQUIPMENT" /* 器械 */)} footer={t("FILTERS_THE_EXERCISE_LIBRARY_AND_PICKER_AND_FLAGS_ROUTINE_EXERCISES_THAT_NEED" /* 筛选动作库和选择器，并标记训练计划中需要当前配置里没有的器械的动作。 */)}>
    <Row icon="plate" iconTint="var(--orange)" title={t("PLATES" /* 杠铃片 */)} subtitle={plateSummary} accessory="chevron" onClick={() => plateInventorySheet()} />
    <Row icon="dumbbell" iconTint="var(--teal)" title={t("DUMBBELLS" /* 哑铃 */)} subtitle={dumbbellSummary} accessory="chevron" onClick={() => dumbbellInventorySheet()} />
    {profiles.length > 0 && <Row icon="kettlebell" iconTint="var(--acc)" title={t("FILTER_BY_EQUIPMENT" /* 按器械筛选 */)}>
      <Switch checked={!!S.equipFilterOn} onChange={v => update(s => { s.equipFilterOn = v })} />
    </Row>}
    {profiles.length > 0 && <SelectRow icon="house" iconTint="var(--blue)" title={t("ACTIVE_PROFILE" /* 当前配置 */)}
      value={S.activeEquipId || ''} onChange={v => update(s => { s.activeEquipId = v })}
      options={profiles.map(p => ({ value: p.id, label: p.name }))} />}
    {profiles.map(p => (
      <Row key={p.id} icon="house" iconTint="var(--teal)" title={p.name}
        subtitle={t("COUNT_EQUIPMENT_TYPES" /* {0} 种器械 */, p.equipment.length)} accessory="chevron"
        onClick={() => equipmentProfileSheet(p)}>
        <button className="iconbtn" aria-label={t("DELETE" /* 删除 */)} onClick={ev => { ev.stopPropagation(); remove(p) }}><Icon name="trash" /></button>
      </Row>
    ))}
    <Row icon="plus" iconTint="var(--acc)" title={t("ADD_EQUIPMENT_PROFILE" /* 添加器械配置 */)} accessory="chevron" onClick={() => equipmentProfileSheet(null)} />
  </Section>
}

// The account's id, small and one tap to copy (#219). It is what an admin puts in ADMIN_UIDS,
// and the one thing that names an account beyond doubt when someone asks their admin for help:
// display names are free text and need not be unique. copyText also reaches the clipboard on a
// plain-http LAN address, where the Clipboard API is missing and password sign-in (#118) is the
// usual way in; where no copy works at all the id is still on screen to read out.
/* After "Reset everything": the photos and videos go too. Signed in, the empty state is pushed
   first and, once the server holds it, the server is asked to drop every file that state no
   longer refers to (POST /api/media/sweep) — asked before the push landed, it would still see the
   old state and keep everything, which is the safe side. Then this device keeps only the files a
   stash refers to: another account's changes kept here are not this reset's to delete. */
async function clearMediaAfterReset(signedIn) {
  const st = useStore.getState()
  if (signedIn && typeof st.pushState === 'function') {
    await st.pushState()
    const now = useStore.getState()
    if (now.sync?.status === 'ok' && now.config?.media) await api('/api/media/sweep', { method: 'POST', body: '{}' }).catch(() => {})
  }
  const keep = typeof st.stashedMediaHashes === 'function' ? await st.stashedMediaHashes() : new Set()
  await mediaStore.retainOnly(keep)
}

/* Settings → Data → "Photos & videos": how much of the server's space they take and what is still
   waiting to go up; a tap sends what is waiting now, offers again what the server refused, and
   lets a device that showed a file as missing ask for it again. On a device without a server that
   stores media, it says they are kept here only. */
function MediaRow() {
  const S = useStore(s => s.S)
  const user = useStore(s => s.user)
  const config = useStore(s => s.config)
  const status = useSyncExternalStore(subscribeMediaStatus, getMediaStatus)
  // Signed in, the files go to the server unless it has said it stores none. A config not known
  // yet — a phone started without a network; it is not kept between starts — is not that answer:
  // what is waiting is counted as waiting (and goes up once the server answers), not called
  // local-only as a guest's files are.
  const remote = !!user && (config == null || !!config.media)
  useEffect(() => { if (remote) syncMedia() }, [remote])
  const pending = remote ? pendingRefCount(S) : 0
  const u = status.usage
  const usage = remote && u && u.quotaBytes > 0
    ? t("COUNT_OF_COUNT_MB_USED_ON_YOUR_SERVER" /* 服务器已用 {0} / {1} MB */, fmtMB((u.bytes || 0) / MB), fmtMB(Math.round(u.quotaBytes / MB)))
    : null
  const sub = remote
    ? [usage, pending ? t("COUNT_WAITING_TO_UPLOAD" /* {0} 个等待上传 */, pending) : null].filter(Boolean).join(' · ') || undefined
    : t("KEPT_ON_THIS_DEVICE_ONLY_EXPORT_WITH_PHOTOS_VIDEOS_KEEPS_A_COPY" /* 仅保存在此设备上。“连同照片和视频导出”可以保留一份副本。 */)
  return <Row icon="image" iconTint="var(--teal)" title={t("PHOTOS_VIDEOS" /* 照片和视频 */)} subtitle={sub}
    onClick={remote ? () => syncMedia({ force: true, retryRejected: true }) : undefined} />
}

function AccountIdRow({ id }) {
  const toast = useUI(s => s.toast)
  if (!id) return null
  const copy = async () => { if (await copyText(id)) toast(t("ACCOUNT_ID_COPIED" /* 已复制账号 ID */)) }
  return <Row icon="personCircle" iconTint="var(--grey)" title={t("ACCOUNT_ID" /* 账号 ID */)} subtitle={<span className="acct-id">{id}</span>} onClick={copy} />
}

// Lets the mobile app's "connect to my server" mode (lib/remote.js) authenticate without a
// WebAuthn ceremony of its own — the code is minted here, from an already signed-in session,
// and redeemed by the app for a bearer token. See /api/pair/create in api/server.js.
function PairSheet({ close }) {
  const [code, setCode] = useState(null)
  const [err, setErr] = useState(null)
  useEffect(() => { api('/api/pair/create', { method: 'POST', body: '{}' }).then(r => setCode(r.code)).catch(e => setErr(e.message || t("COULD_NOT_GENERATE_A_CODE" /* 无法生成配对码 */))) }, [])
  return <>
    <h3>{t("PAIR_THE_MOBILE_APP" /* 配对手机应用 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("ON_THE_OPENGYM_APP_CHOOSE_CONNECT_TO_MY_SERVER_THEN_ENTER_THIS" /* 在 openGym 应用中选择“连接到我的服务器”，然后输入此地址和下面的配对码。5 分钟后失效。 */)}
    </div>
    {err ? <div className="dim small">{err}</div> : (
      <div className="card" style={{ textAlign: 'center', fontSize: 30, fontWeight: 700, letterSpacing: '.16em', padding: '18px 0' }}>
        {code || '········'}
      </div>
    )}
    <div style={{ height: 12 }} />
    <Button onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}

// The same registration as the sign-in screen's, reached from Settings instead. It asks for
// the invite code on the same terms: an invite-only instance rejects a registration without
// one, so a form that cannot collect it is a form that cannot succeed.
function RegisterInline({ close, setUser, pushState, pullState, toast }) {
  const nameRef = useRef(null)
  const [code, setCode] = useState('')
  const [inviteOnly, setInviteOnly] = useState(false)
  useEffect(() => { api('/api/config').then(c => setInviteOnly(!!c.invite_only)).catch(() => {}) }, [])
  const go = async () => {
    const n = (nameRef.current.value || '').trim()
    if (!n) { toast(t("ENTER_A_NAME" /* 请输入名字 */)); return }
    if (inviteOnly && !code.trim()) { toast(t("AN_INVITE_CODE_IS_REQUIRED" /* 需要邀请码 */)); return }
    try {
      const u = await passkeyRegister(n, code.trim()); setUser(u); close()
      if (hasData(useStore.getState().S)) { await pushState(); toast(t("PROFILE_CREATED_AND_YOUR_DATA_MOVED_INTO_IT" /* 档案已创建，你的数据已转入 */)) }
      else { await pullState(); toast(t("WELCOME_COUNT" /* 欢迎，{0} */, u.name)) }
    } catch (e) { if (e.name !== 'NotAllowedError' && e.name !== 'AbortError') toast(passkeyError(e, t("REGISTRATION_FAILED" /* 注册失败 */))) }
  }
  return <>
    <h3>{t("CREATE_YOUR_PROFILE" /* 创建你的档案 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>{t("PICK_A_NAME_THEN_CONFIRM_WITH_YOUR_DEVICE" /* 取个名字，然后用设备确认。 */)}</div>
    <TextField ref={nameRef} placeholder={t("YOUR_NAME" /* 你的名字 */)} maxLength={40} />
    {inviteOnly && <>
      <div style={{ height: 10 }} />
      <input className="input" placeholder={t("INVITE_CODE" /* 邀请码 */)} maxLength={40} value={code}
        onChange={e => setCode(e.target.value.toUpperCase())} style={{ letterSpacing: '.14em', fontWeight: 600, textAlign: 'center' }} />
      <div className="dim small" style={{ marginTop: 6 }}>{t("THIS_APP_IS_INVITE_ONLY_ENTER_THE_CODE_YOU_WERE_GIVEN" /* 此应用仅限邀请。请输入你收到的邀请码。 */)}</div>
    </>}
    <div style={{ height: 12 }} /><Button variant="primary" onClick={go}>{t("CREATE_PASSKEY" /* 创建通行密钥 */)}</Button>
  </>
}

// Android app: writing finished workouts and weigh-ins to Health Connect (#200), the phone's
// own store for health data, where other apps can read them. A fact about this phone, kept in
// its own file (lib/health-sync.js) and not in S, so it never switches on anywhere else. The card
// stays out of the way on a phone without Health Connect, and only points to installing it on
// Android 13 and lower, where it is an app of its own.
function HealthConnectCard({ S, toast }) {
  const [st, setSt] = useState(null)
  const [h, setH] = useState(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    let gone = false
    Promise.all([healthStatus(), loadHealth()]).then(([s, f]) => { if (!gone) { setSt(s); setH(f) } }).catch(() => {})
    const off = onHealthChange(f => { if (!gone) setH(f) })
    return () => { gone = true; off() }
  }, [])
  if (!st || !h || st.status === 'unsupported') return null

  if (st.status !== 'available') return (
    <Section title={t("HEALTH_CONNECT" /* 术语：Health Connect */)}>
      <Row icon="heart" iconTint="var(--red)" title={t("HEALTH_CONNECT" /* 术语：Health Connect */)}
        subtitle={st.status === 'update'
          ? t("UPDATE_HEALTH_CONNECT_TO_SHARE_WORKOUTS_AND_WEIGH_INS_WITH_OTHER_APPS" /* 更新 Health Connect，即可与其他应用共享训练和称重。 */)
          : t("INSTALL_HEALTH_CONNECT_TO_SHARE_WORKOUTS_AND_WEIGH_INS_WITH_OTHER_APPS" /* 安装 Health Connect，即可与其他应用共享训练和称重。 */)}
        accessory="chevron" onClick={() => openHealthConnect().catch(() => {})} />
    </Section>
  )

  const turnOn = async () => {
    setBusy(true)
    try {
      const r = await enableHealth(S)
      if (r.health) setH(r.health)
      else setH(await loadHealth())
      if (r.ok) toast(t("WRITING_TO_HEALTH_CONNECT" /* 正在写入 Health Connect */))
      else toast(r.reason === 'denied' ? t("HEALTH_CONNECT_PERMISSION_NOT_GRANTED" /* 未授予 Health Connect 权限 */) : t("COULD_NOT_WRITE_TO_HEALTH_CONNECT" /* 无法写入 Health Connect */))
    } catch { toast(t("COULD_NOT_WRITE_TO_HEALTH_CONNECT" /* 无法写入 Health Connect */)) }
    setBusy(false)
  }
  const turnOff = removeWritten => async () => {
    setBusy(true)
    try { setH(await disableHealth({ removeWritten })) }
    catch { toast(t("COULD_NOT_REMOVE_IT_FROM_HEALTH_CONNECT" /* 无法从 Health Connect 中移除 */)) }
    setBusy(false)
  }
  // Off can mean two things for what is already there, so it asks; closing the sheet keeps it on.
  const askOff = () => menuSheet({
    title: t("STOP_WRITING_TO_HEALTH_CONNECT" /* 停止写入 Health Connect？ */),
    subtitle: t("WHAT_OPENGYM_ALREADY_WROTE_CAN_STAY_IN_HEALTH_CONNECT_AS_YOUR_DATA" /* openGym 已写入的内容可以作为你的数据保留在 Health Connect 中，也可以从中移除。 */),
    items: [
      { icon: 'check', label: t("STOP_KEEP_WHAT_IT_WROTE" /* 停止，保留已写入的内容 */), onClick: turnOff(false) },
      { icon: 'trash', label: t("STOP_AND_REMOVE_WHAT_IT_WROTE" /* 停止并移除已写入的内容 */), danger: true, onClick: turnOff(true) },
    ],
  })

  return (
    <Section title={t("HEALTH_CONNECT" /* 术语：Health Connect */)}
      footer={h.on ? t("WORKOUTS_AND_WEIGH_INS_GO_TO_HEALTH_CONNECT_WHEN_YOU_FINISH_OR" /* 训练和称重在你完成或修改时写入 Health Connect。openGym 不会从中读取任何内容。 */) : null}>
      <Row icon="heart" iconTint="var(--red)" title={t("WRITE_TO_HEALTH_CONNECT" /* 写入 Health Connect */)}
        subtitle={t("FINISHED_WORKOUTS_AND_WEIGH_INS_FROM_THIS_PHONE_ONLY" /* 已完成的训练和称重，仅来自这部手机。 */)}>
        <Switch checked={!!h.on} disabled={busy} onChange={v => (v ? turnOn() : askOff())} />
      </Row>
      {h.on && h.error === 'permission' && <Row icon="warning" iconTint="var(--orange)"
        title={t("PERMISSION_WITHDRAWN_TAP_TO_ALLOW_AGAIN" /* 权限已撤销 — 轻触重新授予 */)} accessory="chevron" onClick={turnOn} />}
      {h.on && <Row icon="list" iconTint="var(--blue)" title={t("OPEN_HEALTH_CONNECT" /* 打开 Health Connect */)}
        accessory="chevron" onClick={() => openHealthConnect().catch(() => {})} />}
    </Section>
  )
}
