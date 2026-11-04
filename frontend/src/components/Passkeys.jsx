// More than one passkey on a profile, and the one-time code that adds one on another device
// (#95). Settings → Account lists the passkeys and offers both ways to add one; the sign-in screen
// — or the link in the code's QR, opened on the other device — redeems a code. The rules are the
// server's (api/passkeys-store.js, api/device-link.js and the passkeys block in api/server.js):
// what needs proof, the last way in, how long a code lives. This only words them.
import { useEffect, useRef, useState } from 'react'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t, tn } from '../lib/i18n.js'
import { dateLocale } from '../lib/i18n-core.js'
import { api, webauthnOK, createPasskey } from '../lib/api.js'
import { copyText } from '../lib/clipboard.js'
import { deviceLinkUrl, deviceLabel } from '../lib/device-link.js'
import { askAddDeviceData } from '../sheets.jsx'
import { passwordError, notReached, useAgainOnceReached, ProveOwner } from './PasswordAuth.jsx'
import QrCanvas from './QrCanvas.jsx'
import { Row, Button } from './ui.jsx'

const ui = () => useUI.getState()
const toast = m => ui().toast(m)
const post = (path, body) => api(path, { method: 'POST', body: JSON.stringify(body) })
const errStyle = { color: 'var(--red)', marginTop: 10 }
// A passkey prompt the person closed is their answer, not an error worth a line in red.
const dismissed = e => e?.name === 'NotAllowedError' || e?.name === 'AbortError'
// How long a code lives (api/device-link.js DEVICE_LINK_TTL_MS), for the sentence that says so.
const LINK_MINUTES = 10
// The server keeps a creation challenge five minutes; one older than four is asked for again
// rather than risked on a prompt that then fails.
const CHALLENGE_FRESH_MS = 4 * 60000

// The year only when it is not this one, so "Added … · Last used …" fits on one line.
const when = iso => {
  const d = new Date(iso)
  const year = d.getFullYear() !== new Date().getFullYear() ? { year: 'numeric' } : {}
  try { return d.toLocaleDateString(dateLocale(), { day: 'numeric', month: 'short', ...year }) }
  catch { return '' }
}
const label = (p, i) => p.name || t("PASSKEY_COUNT" /* 通行密钥 {0} */, i + 1)
// "Added 3 Sep 2026 · Last used 22 Sep 2026" — a passkey from before either was recorded has none.
const meta = p => [p.created && t("ADDED_COUNT" /* 添加于 {0} */, when(p.created)), p.lastUsed && t("LAST_USED_COUNT" /* 上次使用于 {0} */, when(p.lastUsed))].filter(Boolean).join(' · ')

// The server's refusal in the UI language. The proof codes are the password sheet's; the rest
// are this feature's own (api/openapi.yaml, tag passkeys).
export function passkeyError(e) {
  // The authenticator already holds one of this profile's passkeys (excludeCredentials).
  if (e?.name === 'InvalidStateError') return t("THIS_DEVICE_ALREADY_HAS_A_PASSKEY_FOR_THIS_PROFILE" /* 此设备已有该档案的通行密钥。 */)
  switch (e?.data?.code) {
    case 'last-way-in': return t("IT_IS_YOUR_ONLY_WAY_IN_SO_IT_CANNOT_BE_REMOVED_UNTIL" /* 这是你唯一的登录方式，在有其他方式之前不能移除。 */)
    case 'passkey-limit': return t("THIS_PROFILE_ALREADY_HAS_AS_MANY_PASSKEYS_AS_IT_CAN_HOLD" /* 此档案的通行密钥数量已达上限。 */)
    case 'credential-exists': return t("THIS_PASSKEY_ALREADY_BELONGS_TO_A_PROFILE" /* 此通行密钥已属于某个档案。 */)
    case 'link-invalid': return t("THAT_CODE_IS_WRONG_ALREADY_USED_OR_EXPIRED_MAKE_A_NEW_ONE" /* 代码错误、已被使用或已过期。请在你的另一台设备上生成新的代码。 */)
  }
  return passwordError(e)
}

// GET /api/account/passkeys: { passkeys, password, lastWayIn }, or null until it answers — and
// for as long as the answer is not a list, which is what a server from before #95 gives, so
// Settings on such a server simply has no passkey rows.
const listOf = r => (Array.isArray(r?.passkeys) ? r : null)
export function usePasskeys(on) {
  const [st, setSt] = useState(null)
  const [unreached, setUnreached] = useState(false)
  const load = () => api('/api/account/passkeys').then(r => { setSt(listOf(r)); setUnreached(false) }).catch(e => setUnreached(notReached(e)))
  useEffect(() => { if (on) load() }, [on])
  useAgainOnceReached(on && unreached, load)
  return { st, load, set: setSt }
}

/* ------------------------------------------------------------------- Settings -------------
   Settings → Account: the passkeys, and a code for another device. `changed` tells Settings to
   read the list again, and the password row with it — whether a password may be removed depends
   on how many passkeys there are. */
export function PasskeysRow({ state, changed }) {
  if (!state) return null
  const n = state.passkeys.length
  return <Row icon="fingerprint" iconTint="var(--acc)" title={t("PASSKEYS" /* 通行密钥 */)} accessory="chevron"
    subtitle={n === 0 ? t("NONE_YET_ADD_ONE_AND_SIGN_IN_WITHOUT_YOUR_PASSWORD" /* 还没有。添加一个，就能不用密码登录。 */) : tn("ONE_PASSKEY" /* 1 个通行密钥 */, "COUNT_PASSKEYS" /* {0} 个通行密钥 */, n)}
    onClick={() => ui().openSheet(close => <PasskeysSheet close={close} changed={changed} />)} />
}

export function DeviceLinkRow({ state }) {
  if (!state) return null
  return <Row icon="qr" iconTint="var(--blue)" title={t("ADD_ANOTHER_DEVICE" /* 添加其他设备 */)} accessory="chevron"
    subtitle={t("A_ONE_TIME_CODE_LETS_YOUR_PHONE_OR_ANOTHER_COMPUTER_SIGN_IN" /* 一次性代码可让你的手机或其他电脑用自己的通行密钥登录。 */)}
    onClick={() => ui().openSheet(close => <DeviceLinkSheet close={close} />)} />
}

export function PasskeysSheet({ close, changed }) {
  const { st, set } = usePasskeys(true)
  const done = r => { set(listOf(r) || st); changed?.() }
  if (!st) return <><h3>{t("PASSKEYS" /* 通行密钥 */)}</h3><div className="muted small">…</div></>
  const edit = (p, i) => ui().openSheet(c => <PasskeySheet passkey={p} title={label(p, i)} state={st} close={c} done={done} />)
  const add = () => ui().openSheet(c => <AddPasskeySheet state={st} close={c} done={done} />)
  return <>
    <h3>{t("PASSKEYS" /* 通行密钥 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("EACH_ONE_SIGNS_IN_TO_THIS_PROFILE_FROM_THE_DEVICE_OR_PASSWORD" /* 每个通行密钥都能从保存它的设备或密码管理器登录此档案。点按一个即可重命名或移除。 */)}
    </div>
    {st.passkeys.length > 0 && <div className="sect-b">
      {st.passkeys.map((p, i) => <Row key={p.id} icon="fingerprint" iconTint="var(--grey)" title={label(p, i)} subtitle={meta(p) || null}
        accessory="chevron" onClick={() => edit(p, i)} />)}
    </div>}
    {st.passkeys.length === 1 && st.lastWayIn && <div className="dim small" style={{ marginTop: 8 }}>
      {t("IT_IS_YOUR_ONLY_WAY_IN_SO_IT_CANNOT_BE_REMOVED_UNTIL" /* 这是你唯一的登录方式，在有其他方式之前不能移除。 */)}</div>}
    <div style={{ height: 14 }} />
    {webauthnOK() && <><Button variant="primary" icon="plus" onClick={add}>{t("ADD_A_PASSKEY" /* 添加通行密钥 */)}</Button><div style={{ height: 8 }} /></>}
    <Button onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}

// One passkey: its name, and removing it (RemovePasskeySheet).
function PasskeySheet({ passkey, title, state, close, done }) {
  const [name, setName] = useState(passkey.name || '')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const save = async ev => {
    ev.preventDefault()
    if (busy) return
    setBusy(true); setErr(null)
    try { done(await post('/api/account/passkeys/rename', { id: passkey.id, name })); close() }
    catch (e) { setErr(passkeyError(e)) }
    finally { setBusy(false) }
  }
  const remove = () => ui().openSheet(c => <RemovePasskeySheet passkey={passkey} title={title} state={state} close={c} done={r => { done(r); close() }} />)
  const info = meta(passkey)
  return <>
    <h3>{title}</h3>
    {info && <div className="muted small" style={{ marginBottom: 14 }}>{info}</div>}
    <form onSubmit={save} noValidate>
      <input className="input" placeholder={t("NAME_E_G_WORK_LAPTOP" /* 名称，例如：工作笔记本 */)} maxLength={40} value={name} onChange={e => setName(e.target.value)} />
      {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
      <div style={{ height: 12 }} />
      <Button type="submit" variant="primary" disabled={busy}>{t("SAVE" /* 保存 */)}</Button>
    </form>
    <div style={{ height: 8 }} />
    {state.lastWayIn
      ? <div className="dim small">{t("IT_IS_YOUR_ONLY_WAY_IN_SO_IT_CANNOT_BE_REMOVED_UNTIL" /* 这是你唯一的登录方式，在有其他方式之前不能移除。 */)}</div>
      : <button type="button" className="btn danger" disabled={busy} onClick={remove}>{t("REMOVE_PASSKEY" /* 移除通行密钥 */)}</button>}
  </>
}

/* Removing one asks for the proof adding one does (proveOwner in api/server.js): a copied
   session must not choose which of the owner's passkeys is left. The proof is the confirmation,
   so it is asked on the sheet that says what removing means; any passkey of the profile may give
   it, this one included. Removing does not end a session the passkey opened — sessions are not
   tied to one (api/server.js) — which the sheet says, with the way to do that. */
function RemovePasskeySheet({ passkey, title, state, close, done }) {
  const remove = async proof => {
    const r = await api('/api/account/passkeys?id=' + encodeURIComponent(passkey.id), { method: 'DELETE', body: JSON.stringify(proof) })
    close(); done(r)
    toast(t("PASSKEY_REMOVED" /* 已移除通行密钥 */))
  }
  return <>
    <h3>{t("REMOVE_THIS_PASSKEY" /* 移除这个通行密钥？ */)}</h3>
    <div className="small" style={{ fontWeight: 600, marginBottom: 6 }}>{title}</div>
    <div className="muted small" style={{ marginBottom: 6 }}>
      {t("IT_CAN_NO_LONGER_SIGN_IN_TO_THIS_PROFILE_A_DEVICE_ALREADY" /* 它将无法再登录此档案。已用它登录的设备会保持登录。如果设备丢失，请使用“在所有设备上退出登录”。 */)}
    </div>
    <div className="dim small" style={{ marginBottom: 14 }}>{t("FIRST_CONFIRM_THAT_IT_IS_YOU" /* 请先确认是你本人。 */)}</div>
    <ProveOwner passkey password={state.password} explain={passkeyError} danger submitText={t("REMOVE" /* 移除 */)} onProof={remove} />
    <div style={{ height: 8 }} />
    <Button type="button" variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </>
}

/* Adding one from Settings: the proof first, then the passkey prompt — two taps rather than one,
   because each prompt wants a tap of its own (Safari refuses a second prompt opened from the same
   one), and a password, where that is the proof, is typed before either. What it is for: a
   security key, a password manager, a phone through the browser's own QR prompt. Another device
   that can open openGym itself is easier with a code (DeviceLinkSheet). */
function AddPasskeySheet({ state, close, done }) {
  // Blank to start with: what gets added here is rarely this browser (a key, a phone, a manager).
  const [name, setName] = useState('')
  const [ready, setReady] = useState(null)   // { cid, options } once the proof went through
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const create = async () => {
    if (busy) return
    setBusy(true); setErr(null)
    try {
      const credential = await createPasskey(ready.options)
      done(await post('/api/account/passkeys/verify', { cid: ready.cid, credential, name }))
      close()
      toast(t("PASSKEY_ADDED" /* 已添加通行密钥 */))
    } catch (e) {
      if (dismissed(e)) return
      setErr(passkeyError(e))
      // The server spent the challenge on that answer: a retry starts from the proof again.
      if (e?.status) setReady(null)
    } finally { setBusy(false) }
  }
  return <>
    <h3>{t("ADD_A_PASSKEY" /* 添加通行密钥 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>{ready
      ? t("CONFIRMED_NOW_CREATE_THE_NEW_PASSKEY_YOUR_BROWSER_WILL_ASK_WHERE_TO" /* 已确认。现在创建新的通行密钥，浏览器会问你要把它存在哪里。 */)
      : t("FOR_THIS_DEVICE_A_SECURITY_KEY_A_PASSWORD_MANAGER_OR_YOUR_PHONE" /* 用于此设备、安全密钥、密码管理器，或通过浏览器自带的二维码使用你的手机。请先确认是你本人。 */)}</div>
    <input className="input" placeholder={t("NAME_E_G_WORK_LAPTOP" /* 名称，例如：工作笔记本 */)} maxLength={40} value={name} onChange={e => setName(e.target.value)} />
    <div style={{ height: 12 }} />
    {ready ? <Button variant="primary" icon="plus" disabled={busy} onClick={create}>{t("CREATE_PASSKEY" /* 创建通行密钥 */)}</Button>
      : <ProveOwner passkey={state.passkeys.length > 0} password={state.password} explain={passkeyError}
        onProof={async proof => setReady(await post('/api/account/passkeys/options', proof))} />}
    {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
  </>
}

/* A code for another device: after the same proof, the code itself, a QR code of the link that
   carries it, and a way to copy that link. The other device either scans it or types the code on
   its sign-in screen. When it expires the sheet says so and offers a new one. */
export function DeviceLinkSheet({ close }) {
  const { st } = usePasskeys(true)
  const [link, setLink] = useState(null)   // { code, expires }
  const [expired, setExpired] = useState(false)
  useEffect(() => {
    if (!link) return
    setExpired(false)
    const timer = setTimeout(() => setExpired(true), Math.max(0, link.expires - Date.now()))
    return () => clearTimeout(timer)
  }, [link])
  const url = link ? deviceLinkUrl(link.code) : ''
  const copy = async () => { if (await copyText(url)) toast(t("COPIED" /* 已复制 */)) }
  return <>
    <h3>{t("ADD_ANOTHER_DEVICE" /* 添加其他设备 */)}</h3>
    {!st ? <div className="muted small">…</div> : !link ? <>
      <div className="muted small" style={{ marginBottom: 14 }}>
        {t("YOU_GET_A_CODE_THAT_LETS_YOUR_PHONE_OR_ANOTHER_COMPUTER_CREATE" /* 你会得到一个代码，你的手机或其他电脑可以用它为此档案创建通行密钥。请先确认是你本人。 */)}
      </div>
      <ProveOwner passkey={st.passkeys.length > 0} password={st.password} explain={passkeyError}
        onProof={async proof => setLink(await post('/api/account/device-link', proof))} />
    </> : expired ? <>
      <div className="muted small" style={{ marginBottom: 14 }}>{t("THIS_CODE_HAS_EXPIRED" /* 此代码已过期。 */)}</div>
      <Button variant="primary" onClick={() => setLink(null)}>{t("MAKE_A_NEW_CODE" /* 生成新代码 */)}</Button>
    </> : <>
      <div className="muted small" style={{ marginBottom: 14 }}>
        {t("SCAN_THIS_WITH_THE_OTHER_DEVICE_OR_OPEN_OPENGYM_THERE_AND_ENTER" /* 用另一台设备扫描，或在那台设备上打开 openGym，在登录界面输入代码。仅可使用一次，{0} 分钟内有效。 */, LINK_MINUTES)}
      </div>
      <div className="ci-qr-plate" style={{ width: 'fit-content', margin: '0 auto 14px' }}><QrCanvas value={url} size={200} /></div>
      {/* Read out or typed character by character: left to right in every language. */}
      <div className="card" dir="ltr" style={{ textAlign: 'center', fontSize: 24, fontWeight: 700, letterSpacing: '.12em', padding: '14px 0' }}>{link.code}</div>
      <div style={{ height: 12 }} />
      <Button icon="copy" onClick={copy}>{t("COPY_LINK" /* 复制链接 */)}</Button>
    </>}
    <div style={{ height: 8 }} />
    <Button variant="ghost" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}

/* ------------------------------------------------------------------ the other device -------
   Redeeming a code: the device being added creates a passkey of its own, and that passkey signs it
   in. The code comes from the link's ?link= (the store holds it, see boot()) or is typed. A code
   from a link is checked as the sheet opens, so it can say whose profile this device is joining
   and the passkey prompt then opens straight from the tap. The passkey is named after this
   browser (deviceLabel), which the list in Settings can change. Signed in afterwards like a
   passkey sign-in on the sign-in screen: the same account coming back merges what this device
   kept for it (adoptProfile), and another account's copy is kept aside for that one (setUser).

   A link opens this sheet by itself, and anyone can send one: a code for their own profile would
   sign this browser in to it with a single tap and the passkey prompt, and whatever is logged
   here afterwards would be theirs to read (login CSRF). So unless the code is for the profile
   this browser is already signed in as — told apart by id, since names are not unique and the
   sender chooses theirs — the sheet says which profile this device ends up in and to go on only
   with a code from a device of one's own, and a guest's workouts go into that profile only when
   the guest says so, even into one that has nothing yet (adoptProfile's alwaysAsk). */
export function DeviceLinkRedeemSheet({ close }) {
  const user = useStore(s => s.user)
  const pending = useStore(s => s.linkCode)
  const [code, setCode] = useState(pending || '')
  const [info, setInfo] = useState(null)   // { code, cid, options, id, name, at } from checking the code
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const ref = useRef(null)
  const check = async c => {
    const r = await post('/api/device-link/options', { code: c })
    const i = { ...r, code: c, at: Date.now() }
    setInfo(i)
    return i
  }
  useEffect(() => {
    if (!webauthnOK()) return
    if (pending) check(pending).catch(e => setErr(passkeyError(e)))
    else setTimeout(() => ref.current?.focus(), 250)
  }, [])
  const submit = async ev => {
    ev.preventDefault()
    if (busy) return
    const c = code.trim()
    if (!c) { setErr(t("ENTER_THE_CODE_FROM_YOUR_OTHER_DEVICE" /* 输入你另一台设备上的代码。 */)); return }
    setBusy(true); setErr(null)
    let spent = false
    try {
      const i = info && info.code === c && Date.now() - info.at < CHALLENGE_FRESH_MS ? info : await check(c)
      const credential = await createPasskey(i.options)
      spent = true
      const r = await post('/api/device-link/verify', { code: c, cid: i.cid, credential, name: deviceLabel() })
      const st = useStore.getState()
      useStore.setState({ linkCode: null })
      const same = st.user?.id === r.user.id
      // Another profile: its question decides what becomes of this copy, and nothing syncs
      // before it is answered (adoptProfile).
      st.setUser(r.user, same ? undefined : { adopt: { alwaysAsk: true } })
      close()
      if (same) { toast(t("PASSKEY_ADDED" /* 已添加通行密钥 */)); return }
      // Signed in by now whatever happens next: a pull that fails is the sync banner's to say
      // (adoptProfile records it), not a reason to hide that this device got in.
      await st.adoptProfile(askAddDeviceData, { alwaysAsk: true }).catch(() => {})
      // Not "Welcome back": this may be the first time this person has seen that profile.
      toast(t("SIGNED_IN_AS_COUNT" /* 已登录为 {0} */, r.user.name))
    } catch (e) {
      if (!dismissed(e)) setErr(passkeyError(e))
      // Answered by the server, the challenge is gone; the next try asks for a new one.
      if (spent || e?.status) setInfo(null)
    } finally { setBusy(false) }
  }
  if (!webauthnOK()) return <>
    <h3>{t("ADD_THIS_DEVICE" /* 添加此设备 */)}</h3>
    <div className="muted small">{t("THIS_BROWSER_CANNOT_CREATE_PASSKEYS_SO_IT_CANNOT_BE_ADDED_WITH_A" /* 此浏览器无法创建通行密钥，因此不能通过代码添加。请在能创建通行密钥的浏览器中打开此链接。 */)}</div>
    <div style={{ height: 12 }} />
    <Button onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
  const joining = info && info.code === code.trim() ? info : null
  const elsewhere = joining && joining.id !== user?.id
  return <>
    <h3>{t("ADD_THIS_DEVICE" /* 添加此设备 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>{joining
      ? t("CREATE_A_PASSKEY_ON_THIS_DEVICE_FOR_THE_PROFILE_COUNT_IT_SIGNS" /* 在此设备上为档案“{0}”创建通行密钥。从现在起，你在这里用它登录。 */, joining.name)
      : t("ENTER_THE_CODE_YOUR_OTHER_DEVICE_SHOWS_UNDER_SETTINGS_ACCOUNT_ADD_ANOTHER" /* 输入你另一台设备在“设置 → 账号 → 添加其他设备”中显示的代码。之后此设备会有自己的通行密钥。 */)}</div>
    {elsewhere && <div className="card small" style={{ textAlign: 'start', marginBottom: 14 }}>
      {user && <div style={{ marginBottom: 8 }}>{user.name === joining.name
        ? t("THIS_CODE_IS_FOR_A_DIFFERENT_PROFILE_THAT_IS_ALSO_CALLED_COUNT" /* 这个代码属于另一个同样名为“{0}”的档案，而不是此浏览器当前登录的那个。将浏览器添加到那里，会让你的档案在这里退出登录。 */, joining.name)
        : t("THIS_BROWSER_IS_SIGNED_IN_AS_COUNT_ADDING_IT_TO_COUNT_SIGNS" /* 此浏览器已以“{0}”登录。将它添加到“{1}”会让“{0}”在这里退出登录。 */, user.name, joining.name)}</div>}
      <div>{t("ONLY_CONTINUE_IF_THIS_CODE_COMES_FROM_A_DEVICE_OF_YOUR_OWN" /* 只有当这个代码来自你自己的设备时才继续。之后此浏览器将登录到“{0}”，你在这里记录的内容都会进入该档案。 */, joining.name)}</div>
    </div>}
    <form onSubmit={submit} noValidate>
      <input ref={ref} className="input" name="device-code" autoComplete="one-time-code" placeholder={t("CODE_FROM_YOUR_OTHER_DEVICE" /* 来自你另一台设备的代码 */)} maxLength={20}
        value={code} onChange={e => setCode(e.target.value.toUpperCase())} autoCapitalize="characters" autoCorrect="off" spellCheck={false}
        dir="ltr" style={{ letterSpacing: '.14em', fontWeight: 600, textAlign: 'center' }} />
      {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
      <div style={{ height: 12 }} />
      <Button type="submit" variant="primary" disabled={busy}>{t("CREATE_PASSKEY" /* 创建通行密钥 */)}</Button>
    </form>
  </>
}
export const openDeviceLinkRedeem = () => ui().openSheet(close => <DeviceLinkRedeemSheet close={close} />)
