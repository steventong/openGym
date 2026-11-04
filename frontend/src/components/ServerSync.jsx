// The connection to the server, as the screens show it and act on it: the persistent indicator
// (SyncBanner.jsx), the "Server & sync" block in Settings, and the question a sign-out or a
// disconnect asks when the server has not got everything yet. The store decides the state
// (useStore.js, `sync` — see statusOf there); this file only words it and offers what to do.
import { useEffect, useState } from 'react'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t, tn } from '../lib/i18n.js'
import { fmtAgo, changeCount } from '../lib/format.js'
import { passkeyLogin, passkeyError, webauthnOK } from '../lib/api.js'
import { MOBILE, shareExport } from '../lib/mobile.js'
import { syncMedia } from '../lib/media-sync.js'
import { DEMO } from '../lib/demo.js'
import { askAddDeviceData, menuSheet } from '../sheets.jsx'
import { ConnectSheet, CfAccessSheet } from '../views/MobileOnboarding.jsx'
import { passwordOn, openPasswordSignIn } from './PasswordAuth.jsx'
import { Section, Row, Button } from './ui.jsx'

const ui = () => useUI.getState()
const toast = m => ui().toast(m)
// Whether this browser has a way to sign in at all: a passkey, or a password on an instance that
// offers one (#118) — which is also what a browser without passkey support has left.
const pwOn = () => passwordOn(useStore.getState?.()?.config)
const canSignIn = () => webauthnOK() || pwOn()

// "gym.example.com" out of the base URL the store keeps (a subpath stays: it is part of which
// server this is). Anything unparseable is shown as it is.
export const hostOf = base => {
  try { const u = new URL(base); return u.host + u.pathname.replace(/\/$/, '') } catch { return base || '' }
}

// Whether the device says it has a network at all. fetch fails the same way for a phone with no
// network and for a server that is down, or behind a proxy whose error page carries no CORS
// header (the phone app is another origin): only this tells "offline" from "your server".
export const isOnline = () => typeof navigator === 'undefined' || navigator.onLine !== false
// The same, for a screen that has to change its words when the network comes or goes.
export function useOnline() {
  const [online, setOnline] = useState(isOnline)
  useEffect(() => {
    const on = () => setOnline(isOnline())
    window.addEventListener('online', on)
    window.addEventListener('offline', on)
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', on) }
  }, [])
  return online
}

/* One state of `sync`, in words:
     tone    'ok' | 'wait' | 'off' | 'bad' | 'quiet' — the colour, from fine to deliberate local use
     line    the short status line: Settings, and the toast after "Sync now"
     banner  the sentence the persistent indicator shows, or null when there is nothing to say
     action  what the indicator offers: 'retry' | 'pair' | 'signin' | 'connect' | null
   `mobile` is the build (a phone pairs, a browser signs in); `online` whether the device has a
   network, which decides whether "offline" is the device or the server. Every state that is not
   'ok' says the changes are kept on this device — that is the one thing the person needs to hear
   first. */
export function connectionView(sync, { mobile = MOBILE, online = isOnline() } = {}) {
  if (!sync) return null
  const err = sync.lastError || {}
  // A device that says it has no network is offline whatever the last request found: said the
  // moment it goes, not at the next sync attempt, which may be a poll away. Only the states that
  // claim a working connection give way; a refusal or an error keeps its own words.
  const status = !online && (sync.status === 'ok' || sync.status === 'pending') ? 'offline' : sync.status
  switch (status) {
    case 'ok':
      return { tone: 'ok', icon: 'cloud', line: t("ALL_SYNCED" /* 已全部同步 */), banner: null, action: null }
    case 'pending':   // the sentence already says "tap to retry": no second word for it
      return { tone: 'wait', icon: 'reset', line: t("WAITING_TO_SYNC" /* 等待同步 */), banner: t("NOT_SYNCED_YET_TAP_TO_RETRY" /* 尚未同步。点按重试。 */), action: 'retry', label: null }
    // A sign-in's question about this device's workouts is still open (useStore adoptProfile):
    // nothing syncs until it is answered, and "retry" — Sync now — asks it again.
    case 'held':
      return { tone: 'wait', icon: 'reset', line: t("WAITING_FOR_YOUR_ANSWER_ABOUT_THIS_DEVICE_S_WORKOUTS" /* 正在等待你对本设备训练的答复 */), banner: t("NOTHING_SYNCS_UNTIL_YOU_SAY_WHETHER_THIS_DEVICE_S_WORKOUTS_GO_INTO" /* 在你决定是否把本设备的训练加入个人资料之前，什么都不会同步。点按以答复。 */), action: 'retry', label: null }
    case 'offline':
      if (online) return {
        tone: 'off', icon: 'cloudSlash', action: 'retry',
        line: err.code === 'timeout' ? t("THE_SERVER_DID_NOT_ANSWER_IN_TIME" /* 服务器没有及时响应。 */) : t("THE_SERVER_CANNOT_BE_REACHED" /* 无法连接服务器 */),
        banner: sync.pending ? t("YOUR_SERVER_CAN_T_BE_REACHED_YOUR_CHANGES_ARE_SAVED_ON_THIS" /* 无法连接你的服务器。你的更改已保存在此设备上，服务器恢复响应后会自动同步。 */) : t("YOUR_SERVER_CAN_T_BE_REACHED_SHOWING_THE_LAST_COPY_SYNCED_WITH" /* 无法连接你的服务器。正在显示最后一次与它同步的副本。 */),
      }
      return {
        tone: 'off', icon: 'cloudSlash', action: 'retry',
        line: err.code === 'timeout' ? t("THE_SERVER_DID_NOT_ANSWER_IN_TIME" /* 服务器没有及时响应。 */) : t("OFFLINE_THE_SERVER_CAN_T_BE_REACHED" /* 离线。无法连接服务器 */),
        banner: sync.pending ? t("OFFLINE_YOUR_CHANGES_ARE_SAVED_ON_THIS_DEVICE_AND_SYNC_WHEN_YOU" /* 离线。你的更改已保存在此设备上，恢复联网后会自动同步。 */) : t("OFFLINE_SHOWING_THE_LAST_COPY_SYNCED_WITH_THE_SERVER" /* 离线。正在显示最后一次与服务器同步的副本。 */),
      }
    case 'error':
      return err.code === 'bad-response'
        ? { tone: 'bad', icon: 'warning', action: 'retry', line: t("NOT_AN_OPENGYM_ANSWER_HTTP_COUNT" /* 不是 openGym 的响应（HTTP {0}） */, err.status), banner: t("YOUR_SERVER_S_ADDRESS_ANSWERED_WITH_SOMETHING_OTHER_THAN_OPENGYM_HTTP_COUNT" /* 你的服务器地址返回了不属于 openGym 的内容（HTTP {0}）。你的更改保留在这里。 */, err.status) }
        : { tone: 'bad', icon: 'warning', action: 'retry', line: t("SERVER_ERROR_HTTP_COUNT" /* 服务器错误（HTTP {0}） */, err.status), banner: t("YOUR_SERVER_ANSWERED_WITH_AN_ERROR_HTTP_COUNT_YOUR_CHANGES_ARE_KEPT" /* 你的服务器返回了错误（HTTP {0}）。你的更改保留在这里。 */, err.status) }
    case 'auth':
      if (!mobile) return { tone: 'bad', icon: 'lock', action: 'signin', line: t("THE_SERVER_REFUSES_THIS_BROWSER" /* 服务器拒绝了此浏览器 */), banner: t("YOUR_SERVER_NO_LONGER_ACCEPTS_THIS_BROWSER_YOUR_CHANGES_ARE_KEPT_HERE" /* 你的服务器不再接受此浏览器。你的更改保留在这里。 */) }
      // A phone an earlier version unpaired kept no address and no token: nothing refuses it,
      // there is simply nothing to ask.
      return err.code === 'not-paired'
        ? { tone: 'bad', icon: 'lock', action: 'pair', line: t("THIS_PHONE_IS_NOT_CONNECTED_TO_A_SERVER" /* 这部手机没有连接到任何服务器。 */), banner: t("THIS_PHONE_IS_NO_LONGER_PAIRED_WITH_YOUR_SERVER_YOUR_CHANGES_ARE" /* 这部手机已不再与你的服务器配对。你的更改保留在这里。 */) }
        : { tone: 'bad', icon: 'lock', action: 'pair', line: t("THE_SERVER_REFUSES_THIS_PHONE" /* 服务器拒绝了这部手机 */), banner: t("YOUR_SERVER_NO_LONGER_ACCEPTS_THIS_PHONE_YOUR_CHANGES_ARE_KEPT_HERE" /* 你的服务器不再接受这部手机。你的更改保留在这里。 */) }
    // 'local': no server at all. On a phone that is a choice that needs no reminder (#454, #369):
    // Settings still says it and offers Connect, the bar stays away. A guest in a browser is on a
    // server it could sign in to, so it still hears that its data stays in this browser.
    default:
      return mobile
        ? { tone: 'quiet', icon: 'lock', action: 'connect', line: t("ON_THIS_PHONE_ONLY_NOT_CONNECTED_TO_A_SERVER" /* 仅在这部手机上，未连接服务器 */), banner: null }
        : { tone: 'quiet', icon: 'lock', action: canSignIn() ? 'signin' : null, line: t("GUEST_MODE_YOUR_DATA_LIVES_ONLY_IN_THIS_BROWSER" /* 访客模式：你的数据只保存在此浏览器中。 */), banner: t("GUEST_MODE_YOUR_DATA_LIVES_ONLY_IN_THIS_BROWSER" /* 访客模式：你的数据只保存在此浏览器中。 */) }
  }
}

// The word on the indicator's button: the view's own `label` when it has one (null for none),
// else the action's.
export const actionLabel = view => (view.label !== undefined ? view.label : ({ retry: t("TRY_AGAIN" /* 重试 */), pair: t("PAIR_AGAIN" /* 重新配对 */), signin: t("SIGN_IN" /* 登录 */), connect: t("CONNECT" /* 连接 */) })[view.action] || null)

// "Sync now": whatever is waiting goes, the server's copy is checked, and the answer is said.
export async function syncNowWithToast() {
  const sync = await useStore.getState().syncNow()
  const view = connectionView(sync)
  if (view) toast(view.line)
  return sync
}

// A phone whose server refuses it, or that an earlier version unpaired: the connect sheet, with
// the address it had where it still has one. The same account merges what the phone kept.
export function pairAgain() {
  const server = useStore.getState().sync?.server || ''
  ui().openSheet(close => <ConnectSheet close={close} initialUrl={server} again />)
}
export function connectServer() {
  ui().openSheet(close => <ConnectSheet close={close} />)
}

// A browser whose session ended, or a guest: the passkey sign-in, and the same account merges
// what this browser kept (adoptProfile). On an instance with passwords the sign-in sheet comes
// first, with the passkey one tap away on it: which of the two this account has is not
// something this browser can know.
export function signInAgain() {
  if (pwOn()) { openPasswordSignIn(webauthnOK() ? passkeySignIn : undefined); return }
  return passkeySignIn()
}
export async function passkeySignIn() {
  const st = useStore.getState()
  try {
    const u = await passkeyLogin()
    st.setUser(u, { adopt: true })
    await st.adoptProfile(askAddDeviceData)
    toast(t("WELCOME_BACK_COUNT" /* 欢迎回来，{0} */, u.name))
  } catch (e) { if (e.name !== 'NotAllowedError' && e.name !== 'AbortError') toast(passkeyError(e, t("SIGN_IN_FAILED" /* 登录失败 */))) }
}

/* ---------------------------------------------------------- leaving the server ---------------
   Disconnect (phone), Sign out and Sign out everywhere (browser) never wipe changes the server
   has not received (useStore.js). When some are owed, the store refuses and says how many; this
   asks what to do: try again, export a backup, or go ahead anyway — which keeps the changes on
   the device until it reaches this server as this account again. `done(result)` runs once the
   device has actually left. */
const LEAVE = {
  disconnect: { run: (st, o) => st.disconnectServer(o), anyway: () => t("DISCONNECT_ANYWAY" /* 仍然断开连接 */), failed: () => t("COULDN_T_DISCONNECT_YOU_RE_STILL_CONNECTED" /* 无法断开连接。你仍处于连接状态。 */) },
  signout: { run: (st, o) => st.signOut(o), anyway: () => t("SIGN_OUT_ANYWAY" /* 仍然退出登录 */), failed: () => t("COULDN_T_SIGN_OUT_YOU_RE_STILL_SIGNED_IN" /* 无法退出登录。你仍处于登录状态。 */) },
  everywhere: { run: (st, o) => st.signOutAll(o), anyway: () => t("SIGN_OUT_ANYWAY" /* 仍然退出登录 */), failed: () => t("COULDN_T_SIGN_OUT_EVERYWHERE_YOU_RE_STILL_SIGNED_IN" /* 无法在所有设备上退出登录。你仍处于登录状态。 */) },
}
async function attempt(kind, opts) {
  try { return await LEAVE[kind].run(useStore.getState(), opts) }
  catch (e) {   // only a local failure lands here (signOut swallows a failed logout request); each says which action it was
    toast(LEAVE[kind].failed())
    return null
  }
}
export async function leaveServer(kind, { exportBackup, exportBackupZip, done }) {
  const r = await attempt(kind)
  if (!r) return
  if (r.owed && !r.stashed) {
    ui().openSheet(close => <OwedSheet kind={kind} count={r.count} media={r.media || 0} exportBackup={exportBackup} exportBackupZip={exportBackupZip} done={done} close={close} />, { kind: 'center', locked: true })
    return
  }
  done(r)
}

// `media`: photos or videos of custom exercises the server has not confirmed (useStore
// unsyncedChanges). They are owed like any change, so the sheet names them; while there are any,
// its export writes the backup with them (the plain JSON would leave exactly those out).
export function OwedSheet({ kind, count: count0, media: media0 = 0, exportBackup, exportBackupZip, done, close }) {
  const sync = useStore(s => s.sync)
  const [count, setCount] = useState(count0)
  const [media, setMedia] = useState(media0)
  const [busy, setBusy] = useState(false)
  const [tried, setTried] = useState(false)
  const view = connectionView(sync)
  // Refused because it is paired or signed in to a server that no longer takes it: trying
  // again cannot work, and pairing or signing in again brings the changes to the server.
  const refused = sync?.status === 'auth'
  const finish = r => { close(); done(r) }
  const retry = async () => {
    setBusy(true)
    await useStore.getState().syncNow()
    // Past the refusals too, as the Settings row does: a proxy's limit or the server's caps may
    // have been fixed since, and a file refused for good would otherwise hold this sheet open on
    // every try.
    await syncMedia({ force: true, retryRejected: true })
    const r = await attempt(kind)
    setBusy(false)
    if (!r) return
    if (!r.owed || r.stashed) return finish(r)
    setCount(r.count); setMedia(r.media || 0); setTried(true)
  }
  const anyway = async () => {
    setBusy(true)
    const r = await attempt(kind, { force: true })
    setBusy(false)
    if (!r) return
    if (r.owed && !r.stashed) { toast(t("COULDN_T_KEEP_A_COPY_OF_THE_CHANGES_ON_THIS_DEVICE_NOTHING" /* 无法在此设备上保留更改的副本。没有删除任何内容。 */)); return }
    finish(r)
  }
  return <div style={{ textAlign: 'center', padding: '4px 0' }}>
    <h3 style={{ marginBottom: 8 }}>{t("NOT_EVERYTHING_IS_ON_YOUR_SERVER_YET" /* 你的服务器还没有全部内容 */)}</h3>
    {(count !== 0 || !media) && <div style={{ marginBottom: 6, fontWeight: 600 }}>
      {count > 0 ? t("NOT_ON_YOUR_SERVER_YET_COUNT" /* 尚未到达服务器：{0} */, changeCount(count)) : t("SOME_CHANGES_ON_THIS_DEVICE_HAVE_NOT_REACHED_YOUR_SERVER" /* 此设备上的部分更改尚未到达你的服务器。 */)}
    </div>}
    {media > 0 && <div style={{ marginBottom: 6, fontWeight: 600 }}>{tn("COUNT_PHOTO_OR_VIDEO_HAS_NOT_REACHED_YOUR_SERVER_YET" /* 有 {0} 个照片或视频尚未到达你的服务器。 */, "COUNT_PHOTOS_OR_VIDEOS_HAVE_NOT_REACHED_YOUR_SERVER_YET" /* 有 {0} 个照片或视频尚未到达你的服务器。 */, media)}</div>}
    {(tried || refused) && view && <div className="small" style={{ color: 'var(--red)', marginBottom: 6 }}>{view.line}</div>}
    {/* It names the button below it: Try again, or Pair again / Sign in where the server refuses. */}
    <div className="muted small" style={{ marginBottom: 18, lineHeight: 1.5 }}>
      {refused
        ? (MOBILE
          ? t("PAIR_AGAIN_OR_EXPORT_A_BACKUP_FIRST_GOING_AHEAD_ANYWAY_KEEPS_A" /* 请重新配对，或先导出备份。如果仍然继续，这些更改的副本会保留在此设备上，直到它再次以此账号连接到此服务器。届时会重新加入。 */)
          : t("SIGN_IN_AGAIN_OR_EXPORT_A_BACKUP_FIRST_GOING_AHEAD_ANYWAY_KEEPS" /* 请重新登录，或先导出备份。如果仍然继续，这些更改的副本会保留在此设备上，直到它再次以此账号连接到此服务器。届时会重新加入。 */))
        : t("TRY_AGAIN_OR_EXPORT_A_BACKUP_FIRST_GOING_AHEAD_ANYWAY_KEEPS_A" /* 请重试，或先导出备份。如果仍然继续，这些更改的副本会保留在此设备上，直到它再次以此账号连接到此服务器。届时会重新加入。 */)}
    </div>
    {refused && MOBILE && <><button className="btn primary" disabled={busy} onClick={() => { close(); pairAgain() }}>{t("PAIR_AGAIN" /* 重新配对 */)}</button><div style={{ height: 8 }} /></>}
    {refused && !MOBILE && canSignIn() && <><button className="btn primary" disabled={busy} onClick={() => { close(); signInAgain() }}>{pwOn() ? t("SIGN_IN" /* 登录 */) : t("SIGN_IN_WITH_PASSKEY" /* 用通行密钥登录 */)}</button><div style={{ height: 8 }} /></>}
    {!refused && <><button className="btn primary" disabled={busy} onClick={retry}>{busy ? t("SYNCING" /* 正在同步… */) : t("TRY_AGAIN" /* 重试 */)}</button><div style={{ height: 8 }} /></>}
    {media > 0 && exportBackupZip
      ? <Button icon="share" disabled={busy} onClick={exportBackupZip}>{t("EXPORT_WITH_PHOTOS_VIDEOS_ZIP" /* 连同照片和视频导出（.zip） */)}</Button>
      : <Button icon="share" disabled={busy} onClick={exportBackup}>{t("EXPORT_BACKUP_JSON" /* 导出备份（JSON） */)}</Button>}
    <div style={{ height: 8 }} />
    <button className="btn danger" disabled={busy} onClick={anyway}>{LEAVE[kind].anyway()}</button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" disabled={busy} onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </div>
}

/* ---------------------------------------------------------------- Settings ------------------- */
const TINT = { ok: 'var(--green)', wait: 'var(--orange)', off: 'var(--grey)', bad: 'var(--red)', quiet: 'var(--grey)' }

// Settings → "Server & sync", for a device signed in or paired: which server, which account, how
// things stand, since when, what is still waiting, and "Sync now". `children` are the account's
// own rows (the phone's Admin and Disconnect), which belong in the same block.
export function ServerSyncSection({ children }) {
  const user = useStore(s => s.user)
  const sync = useStore(s => s.sync)
  useStore(s => s.S)   // the count of waiting changes follows every edit
  useStore(s => s.config)   // whether "Sign in" may offer a password
  const unsynced = useStore(s => s.unsyncedChanges)
  const online = useOnline()
  const [busy, setBusy] = useState(false)
  // "Last synced: 3 minutes ago" goes stale on an open screen; a re-render now and then keeps it true.
  const [, tick] = useState(0)
  useEffect(() => { const iv = setInterval(() => tick(n => n + 1), 30000); return () => clearInterval(iv) }, [])
  if (!user || !sync) return null
  const view = connectionView(sync, { online })
  // While everything is fine, a change still in its short debounce is not news; once anything
  // is wrong, how much is waiting is exactly what the person needs.
  const owed = sync.status !== 'ok' && typeof unsynced === 'function' ? unsynced() : { owed: false }
  const sub = [
    sync.lastSynced ? t("LAST_SYNCED_COUNT" /* 上次同步：{0} */, fmtAgo(sync.lastSynced)) : t("NOT_SYNCED_WITH_THIS_SERVER_YET" /* 尚未与此服务器同步 */),
    owed.owed && (owed.count > 0 ? t("NOT_ON_YOUR_SERVER_YET_COUNT" /* 尚未到达服务器：{0} */, changeCount(owed.count)) : owed.count == null ? t("SOME_CHANGES_ON_THIS_DEVICE_HAVE_NOT_REACHED_YOUR_SERVER" /* 此设备上的部分更改尚未到达你的服务器。 */) : null),
  ].filter(Boolean).join(' · ')
  const now = async () => {
    if (busy) return
    setBusy(true)
    try { await syncNowWithToast() } finally { setBusy(false) }
  }
  return <Section title={t("SERVER_SYNC" /* 服务器与同步 */)}>
    {/* No address: a phone an earlier version unpaired. The status row below already says it is
        not connected; this row only says which server, and there is none to name. */}
    <Row icon="globe" iconTint="var(--blue)" title={sync.server ? hostOf(sync.server) : t("SERVER_ADDRESS_UNKNOWN" /* 服务器地址未知 */)}
      subtitle={t("SIGNED_IN_AS_COUNT" /* 已登录为 {0} */, user.name)} />
    <Row icon={view.icon} iconTint={TINT[view.tone]} title={view.line} subtitle={sub} className="sync-status" />
    <Row icon="reset" iconTint="var(--acc)" title={busy ? t("SYNCING" /* 正在同步… */) : t("SYNC_NOW" /* 立即同步 */)} onClick={now} />
    {MOBILE && <Row icon="key" iconTint="var(--orange)" title={t("CLOUDFLARE_ACCESS" /* 术语：Cloudflare Access */)} accessory="chevron"
      onClick={() => ui().openSheet(close => <CfAccessSheet close={close} server={sync.server || ''} />)} />}
    {sync.status === 'auth' && (MOBILE
      ? <Row icon="qr" iconTint="var(--indigo)" title={t("PAIR_AGAIN" /* 重新配对 */)} subtitle={t("YOUR_CHANGES_ARE_KEPT_HERE_AND_MERGED_INTO_YOUR_ACCOUNT_ONCE_IT" /* 你的更改保留在这里，重新配对后会合并到你的账号。 */)} accessory="chevron" onClick={pairAgain} />
      : canSignIn() && <Row icon={pwOn() ? 'person' : 'fingerprint'} iconTint="var(--blue)" title={pwOn() ? t("SIGN_IN" /* 登录 */) : t("SIGN_IN_WITH_PASSKEY" /* 用通行密钥登录 */)} subtitle={t("YOUR_CHANGES_ARE_KEPT_HERE_AND_MERGED_INTO_YOUR_ACCOUNT_ONCE_YOU" /* 你的更改保留在这里，重新登录后会合并到你的账号。 */)} accessory="chevron" onClick={signInAgain} />)}
    {/* another account's, kept when this one signed in over a copy that still owed them */}
    <KeptChangesRows />
    {children}
  </Section>
}

// The changes a forced sign-out or disconnect kept on this device, waiting for their server and
// account — so a device that went ahead anyway still says what it holds and for whom.
export function KeptChangesRows() {
  const kept = useStore(s => s.keptChanges)
  const rev = useStore(s => s.keptRev)
  const user = useStore(s => s.user)
  const [rows, setRows] = useState([])
  // Asked again when the account changes and whenever the kept changes do — the ones handed
  // back on a sign-in go some moments after it.
  useEffect(() => {
    let gone = false
    if (typeof kept === 'function') kept().then(r => { if (!gone) setRows(r || []) }).catch(() => {})
    return () => { gone = true }
  }, [kept, user?.id, rev])
  if (DEMO) return null
  // A copy kept for an account that may never come back here (its server lost it, or it was
  // deleted) is saved as a backup file, to import into another profile with "Merge them in".
  const save = async k => {
    const state = await useStore.getState().keptState(k.server, k.uid)
    if (!state) return
    const json = JSON.stringify(state, null, 2)
    const name = 'opengym-kept-' + String(k.name || k.uid).replace(/[^\w-]+/g, '_') + '-' + new Date().toISOString().slice(0, 10) + '.json'
    if (MOBILE) { try { await shareExport(json, name); useUI.getState().toast(t("BACKUP_EXPORTED" /* 备份已导出 */)) } catch { /* share sheet dismissed */ } return }
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([json], { type: 'application/json' })); a.download = name; a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 60000)
    useUI.getState().toast(t("BACKUP_EXPORTED" /* 备份已导出 */))
  }
  return rows.map(k => <Row key={(k.server || '') + '|' + k.uid} icon="history" iconTint="var(--orange)"
    title={t("CHANGES_KEPT_FOR_COUNT" /* 为 {0} 保留的更改 */, k.name || k.uid)}
    subtitle={(k.server ? hostOf(k.server) + ' · ' : '') + t("ADDED_BACK_WHEN_THIS_DEVICE_CONNECTS_AS_THAT_ACCOUNT_AGAIN" /* 此设备再次以该账号连接时会重新加入。 */)}
    accessory="chevron"
    onClick={() => menuSheet({ title: t("CHANGES_KEPT_FOR_COUNT" /* 为 {0} 保留的更改 */, k.name || k.uid), items: [{ icon: 'download', label: t("SAVE_AS_A_BACKUP_FILE" /* 保存为备份文件 */), onClick: () => save(k) }] })} />)
}
