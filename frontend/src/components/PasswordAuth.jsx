// Name-and-password sign-in next to passkeys (#118), on an instance that offers it
// (GET /api/config → `password_login`). Everything a password needs on screen lives here:
// signing in, redeeming the one-time code an admin hands out, creating a profile with a
// password, and the Settings row that sets, changes or removes one — and the "confirm it is you"
// step (ProveOwner) that Settings asks for before a way in is added or removed, where the
// password is one of the two answers — and the optional sign-in e-mail a profile may type there
// instead of its name (EmailRow). Passkeys stay the default wherever this appears; the rules
// themselves are the server's (api/password.js and the password block in api/server.js), this
// only words them.
import { useEffect, useRef, useState } from 'react'
import { useStore, hasData } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t } from '../lib/i18n.js'
import { dateLocale } from '../lib/i18n-core.js'
import { api, webauthnOK, passkeyAssertion, passwordLogin, passwordRegister, passwordResetRedeem } from '../lib/api.js'
import { askAddDeviceData } from '../sheets.jsx'
import { Row, Button } from './ui.jsx'

// The server's floor (api/password.js MIN_LENGTH), checked here first so the common mistake is
// answered without a round trip. The server still decides.
export const MIN_PASSWORD = 10
export const passwordOn = config => !!config?.password_login
// An address the way the server stores and compares it (nameKey in api/password.js): NFKC,
// trimmed, lower-cased.
export const foldEmail = s => String(s || '').normalize('NFKC').trim().toLowerCase()
// The server's own check (normalizeEmail and EMAIL_RE in api/password.js), so what passes here is
// what the server takes; a test holds the two together. The server still decides.
const EMAIL_RE = /^[^\s@<>()[\]\\,;:"]{1,64}@(?=.{1,253}$)[^\s@<>()[\]\\,;:"._-][^\s@<>()[\]\\,;:"]*\.[^\s@<>()[\]\\,;:".]{2,}$/u
export const looksLikeEmail = s => {
  const e = foldEmail(s)
  return !!e && [...e].length <= 254 && EMAIL_RE.test(e) && !e.includes('..')
}

const ui = () => useUI.getState()
const toast = m => ui().toast(m)
const length = s => [...String(s || '')].length
const errStyle = { color: 'var(--red)', marginTop: 10 }

// "in 5 minutes" in the UI language, for how long a pause (429, Retry-After) still lasts.
function fmtIn(sec) {
  const [n, unit] = sec < 60 ? [Math.max(1, Math.round(sec)), 'second'] : sec < 3600 ? [Math.ceil(sec / 60), 'minute'] : [Math.ceil(sec / 3600), 'hour']
  try { return new Intl.RelativeTimeFormat(dateLocale(), { numeric: 'always' }).format(n, unit) }
  catch { return n + ' ' + unit }
}

// The server's answer in the UI language. Every password route sends a stable `code` beside its
// English message (api/openapi.yaml, Error.code); an answer without one is shown as it came.
export function passwordError(e) {
  const code = e?.data?.code
  if (e?.status === 429 || code === 'locked') return t("TOO_MANY_ATTEMPTS_TRY_AGAIN_COUNT" /* 尝试次数过多。请{0}再试。 */, fmtIn(e?.data?.retryAfter || 60))
  switch (code) {
    case 'bad-credentials': return t("WRONG_NAME_E_MAIL_OR_PASSWORD" /* 名字、邮箱或密码错误。 */)
    case 'too-short': return t("USE_AT_LEAST_COUNT_CHARACTERS" /* 至少使用 {0} 个字符。 */, MIN_PASSWORD)
    case 'too-long': return t("THAT_PASSWORD_IS_TOO_LONG" /* 这个密码太长了。 */)
    case 'too-common': return t("THAT_PASSWORD_IS_TOO_EASY_TO_GUESS_TRY_A_LONGER_ONE_OR" /* 这个密码太容易被猜到了。试试更长的密码，或者几个随机的词连在一起。 */)
    case 'name-taken': return t("ANOTHER_PROFILE_ALREADY_SIGNS_IN_WITH_THIS_NAME" /* 已有另一个档案用这个名字登录。 */)
    case 'email-invalid': return t("THAT_IS_NOT_AN_E_MAIL_ADDRESS" /* 这不是邮箱地址。 */)
    case 'email-taken': return t("ANOTHER_PROFILE_ALREADY_USES_THIS_E_MAIL_ADDRESS" /* 已有另一个档案在使用这个邮箱地址。 */)
    case 'invite': return t("THAT_INVITE_CODE_IS_NOT_VALID" /* 这个邀请码无效。 */)
    case 'current-required': case 'current-wrong': return t("YOUR_CURRENT_PASSWORD_IS_NOT_RIGHT" /* 你当前的密码不对。 */)
    case 'passkey': case 'passkey-required': return t("YOUR_PASSKEY_COULD_NOT_BE_CONFIRMED" /* 无法确认你的通行密钥。 */)
    case 'last-way-in': return t("THIS_PASSWORD_IS_THE_ONLY_WAY_INTO_YOUR_PROFILE_SO_IT_CANNOT" /* 这个密码是进入你档案的唯一方式，因此不能移除。 */)
    case 'reset-invalid': return t("THAT_RESET_CODE_IS_WRONG_OR_HAS_EXPIRED_ASK_YOUR_ADMIN_FOR" /* 这个重置码错误或已过期。请向管理员要一个新的。 */)
    case 'disabled': return t("THIS_ACCOUNT_HAS_BEEN_DISABLED" /* 此账户已被停用。 */)
    case 'busy': return t("THE_SERVER_IS_BUSY_TRY_AGAIN_IN_A_MOMENT" /* 服务器繁忙。请稍后再试。 */)
  }
  return e?.message || t("SIGN_IN_FAILED" /* 登录失败 */)
}
// A passkey prompt the person closed is their answer, not an error worth a line in red.
const dismissed = e => e?.name === 'NotAllowedError' || e?.name === 'AbortError'

// Signed in: the same steps as a passkey sign-in (Login.jsx) — and the same account coming back
// merges what this device kept for it (adoptProfile).
async function signedIn(u, close) {
  const st = useStore.getState()
  st.setUser(u, { adopt: true })
  close()
  await st.adoptProfile(askAddDeviceData)
  toast(t("WELCOME_BACK_COUNT" /* 欢迎回来，{0} */, u.name))
}

const field = { autoCapitalize: 'none', autoCorrect: 'off', spellCheck: false }
const codeStyle = { letterSpacing: '.14em', fontWeight: 600, textAlign: 'center' }

/* Sign in with name (or the profile's sign-in e-mail) and password, or — one tap away — redeem a reset code from the admin, which
   sets a new password and signs in. `onPasskey`, when given, offers the passkey instead. The
   inputs carry the autocomplete names password managers look for, inside a real form. */
export function PasswordSignInSheet({ close, onPasskey }) {
  const [mode, setMode] = useState('signin')   // 'signin' | 'reset'
  const [name, setName] = useState('')
  const [pw, setPw] = useState('')
  const [code, setCode] = useState('')
  const [next, setNext] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const nameRef = useRef(null)
  useEffect(() => { setTimeout(() => nameRef.current?.focus(), 250) }, [])
  const reset = mode === 'reset'
  const submit = async ev => {
    ev.preventDefault()
    if (busy) return
    const n = name.trim()
    const bad = !n ? t("ENTER_YOUR_NAME_OR_E_MAIL" /* 请输入你的名字或邮箱。 */)
      : !reset && !pw ? t("ENTER_YOUR_PASSWORD" /* 请输入你的密码。 */)
      : reset && !code.trim() ? t("ENTER_THE_RESET_CODE" /* 请输入重置码。 */)
      : reset && length(next) < MIN_PASSWORD ? t("USE_AT_LEAST_COUNT_CHARACTERS" /* 至少使用 {0} 个字符。 */, MIN_PASSWORD)
      // A typo here is only found at the next sign-in, and fixing it takes another code.
      : reset && next !== again ? t("THE_TWO_PASSWORDS_ARE_NOT_THE_SAME" /* 两次输入的密码不一致。 */)
      : null
    if (bad) { setErr(bad); return }
    setBusy(true); setErr(null)
    try { await signedIn(reset ? await passwordResetRedeem(n, code.trim(), next) : await passwordLogin(n, pw), close) }
    catch (e) { setErr(passwordError(e)) }
    finally { setBusy(false) }
  }
  return <>
    <h3>{reset ? t("RESET_YOUR_PASSWORD" /* 重置你的密码 */) : t("SIGN_IN_WITH_PASSWORD" /* 用密码登录 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>{reset
      ? t("ENTER_THE_CODE_YOUR_ADMIN_GAVE_YOU_AND_CHOOSE_A_NEW_PASSWORD" /* 输入管理员给你的代码，并设置新密码。你在其他所有地方都会被退出登录。 */)
      : t("USE_YOUR_PROFILE_NAME_OR_THE_E_MAIL_YOU_ADDED_TO_IT" /* 使用你的档案名字（或你为它添加的邮箱）和你的密码。 */)}</div>
    <form onSubmit={submit} noValidate>
      {/* One field for both: the server looks an entry with an "@" up as an e-mail first. Not
          type="email", which would refuse a plain name. */}
      <input ref={nameRef} className="input" name="username" autoComplete="username" placeholder={t("NAME_OR_E_MAIL" /* 名字或邮箱 */)} maxLength={254}
        value={name} onChange={e => setName(e.target.value)} {...field} />
      <div style={{ height: 10 }} />
      {reset ? <>
        <input className="input" name="reset-code" autoComplete="one-time-code" placeholder={t("RESET_CODE" /* 重置码 */)} maxLength={20}
          value={code} onChange={e => setCode(e.target.value.toUpperCase())} {...field} style={codeStyle} />
        <div style={{ height: 10 }} />
        <input className="input" type="password" name="new-password" autoComplete="new-password" placeholder={t("NEW_PASSWORD" /* 新密码 */)}
          value={next} onChange={e => setNext(e.target.value)} />
        <div style={{ height: 10 }} />
        <input className="input" type="password" name="new-password-again" autoComplete="new-password" placeholder={t("REPEAT_THE_PASSWORD" /* 再次输入密码 */)}
          value={again} onChange={e => setAgain(e.target.value)} />
        <div className="dim small" style={{ marginTop: 6 }}>{t("AT_LEAST_COUNT_CHARACTERS_A_FEW_UNRELATED_WORDS_MAKE_A_GOOD_ONE" /* 至少 {0} 个字符。几个互不相关的词就是一个好密码。 */, MIN_PASSWORD)}</div>
      </> : <input className="input" type="password" name="password" autoComplete="current-password" placeholder={t("PASSWORD" /* 密码 */)}
        value={pw} onChange={e => setPw(e.target.value)} />}
      {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
      <div style={{ height: 12 }} />
      <Button type="submit" variant="primary" disabled={busy}>{reset ? t("SET_PASSWORD_SIGN_IN" /* 设置密码并登录 */) : t("SIGN_IN" /* 登录 */)}</Button>
    </form>
    <div style={{ height: 8 }} />
    <Button type="button" variant="ghost" className="dim" onClick={() => { setErr(null); setMode(reset ? 'signin' : 'reset') }}>
      {reset ? t("SIGN_IN_WITH_PASSWORD" /* 用密码登录 */) : t("HAVE_A_RESET_CODE_FROM_YOUR_ADMIN" /* 有管理员给的重置码？ */)}</Button>
    {onPasskey && !reset && webauthnOK() && <>
      <div style={{ height: 8 }} />
      <Button type="button" icon="fingerprint" onClick={() => { close(); onPasskey() }}>{t("SIGN_IN_WITH_PASSKEY" /* 用通行密钥登录 */)}</Button>
    </>}
  </>
}
export const openPasswordSignIn = onPasskey => ui().openSheet(close => <PasswordSignInSheet close={close} onPasskey={onPasskey} />)

/* The password half of creating a profile. Name and invite code are the caller's state, so
   switching between passkey and password on the sign-up sheet keeps what was typed. */
export function PasswordRegisterForm({ close, inviteOnly, name, setName, code, setCode }) {
  const [email, setEmail] = useState('')
  const [pw, setPw] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const submit = async ev => {
    ev.preventDefault()
    if (busy) return
    const n = name.trim()
    const mail = email.trim()
    const bad = !n ? t("ENTER_A_NAME" /* 请输入名字 */)
      : mail && !looksLikeEmail(mail) ? t("THAT_IS_NOT_AN_E_MAIL_ADDRESS" /* 这不是邮箱地址。 */)
      : inviteOnly && !code.trim() ? t("AN_INVITE_CODE_IS_REQUIRED" /* 需要邀请码 */)
      : length(pw) < MIN_PASSWORD ? t("USE_AT_LEAST_COUNT_CHARACTERS" /* 至少使用 {0} 个字符。 */, MIN_PASSWORD)
      : pw !== again ? t("THE_TWO_PASSWORDS_ARE_NOT_THE_SAME" /* 两次输入的密码不一致。 */)
      : null
    if (bad) { setErr(bad); return }
    setBusy(true); setErr(null)
    try {
      const u = await passwordRegister(n, pw, code.trim(), mail)
      const st = useStore.getState()
      st.setUser(u); close()
      if (hasData(useStore.getState().S)) { await st.pushState(); toast(t("PROFILE_CREATED_AND_THIS_DEVICE_S_DATA_MOVED_INTO_IT" /* 档案已创建，本设备的数据已转入 */)) }
      else { await st.pullState(); toast(t("WELCOME_COUNT" /* 欢迎，{0} */, u.name)) }
    } catch (e) { setErr(passwordError(e)) }
    finally { setBusy(false) }
  }
  return <form onSubmit={submit} noValidate>
    <input className="input" name="username" autoComplete="username" placeholder={t("YOUR_NAME" /* 你的名字 */)} maxLength={40}
      value={name} onChange={e => setName(e.target.value)} {...field} />
    <div style={{ height: 10 }} />
    <input className="input" type="email" name="email" autoComplete="email" inputMode="email" placeholder={t("E_MAIL_OPTIONAL" /* 邮箱（可选） */)} maxLength={254}
      value={email} onChange={e => setEmail(e.target.value)} {...field} />
    <div className="dim small" style={{ marginTop: 6 }}>{t("LETS_YOU_SIGN_IN_WITH_IT_INSTEAD_OF_YOUR_NAME_NOTHING_IS" /* 可以用它代替名字登录。不会向它发送任何邮件。 */)}</div>
    {inviteOnly && <>
      <div style={{ height: 10 }} />
      <input className="input" placeholder={t("INVITE_CODE" /* 邀请码 */)} maxLength={40} value={code}
        onChange={e => setCode(e.target.value.toUpperCase())} style={codeStyle} />
      <div className="dim small" style={{ marginTop: 6 }}>{t("THIS_APP_IS_INVITE_ONLY_ENTER_THE_CODE_YOU_WERE_GIVEN" /* 此应用仅限邀请。请输入你收到的邀请码。 */)}</div>
    </>}
    <div style={{ height: 10 }} />
    <input className="input" type="password" name="new-password" autoComplete="new-password" placeholder={t("PASSWORD" /* 密码 */)}
      value={pw} onChange={e => setPw(e.target.value)} />
    <div style={{ height: 10 }} />
    <input className="input" type="password" name="new-password-again" autoComplete="new-password" placeholder={t("REPEAT_THE_PASSWORD" /* 再次输入密码 */)}
      value={again} onChange={e => setAgain(e.target.value)} />
    <div className="dim small" style={{ marginTop: 6 }}>{t("AT_LEAST_COUNT_CHARACTERS_A_FEW_UNRELATED_WORDS_MAKE_A_GOOD_ONE" /* 至少 {0} 个字符。几个互不相关的词就是一个好密码。 */, MIN_PASSWORD)}</div>
    {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
    <div style={{ height: 12 }} />
    <Button type="submit" variant="primary" disabled={busy}>{t("CREATE_PROFILE" /* 创建档案 */)}</Button>
  </form>
}

// The same form on its own sheet — Settings, in a browser that cannot make a passkey.
function PasswordRegisterSheet({ close }) {
  const config = useStore(s => s.config)
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  return <>
    <h3>{t("CREATE_YOUR_PROFILE" /* 创建你的档案 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>{t("PICK_A_NAME_AND_A_PASSWORD_YOU_SIGN_IN_WITH_BOTH" /* 选择一个名字和一个密码。你用两者一起登录。 */)}</div>
    <PasswordRegisterForm close={close} inviteOnly={!!config?.invite_only} name={name} setName={setName} code={code} setCode={setCode} />
  </>
}
export const openPasswordRegister = () => ui().openSheet(close => <PasswordRegisterSheet close={close} />)

/* "Confirm it is you" — what the server asks before anything that adds or takes away a way in
   (proveOwner in api/server.js): a passkey this profile already has, or its current password
   where that counts. `passkey`: the profile has one. `password`: its password counts as proof —
   set, and the instance takes passwords (GET /api/account/passkeys → `password`). Hands the body
   the server takes to `onProof` — for a removal, the removal itself — and shows the refusal,
   worded by `explain`, when that throws. For a removal this step is the confirmation too, so
   `danger` colours it and `submitText` names the action on the password's button.

   A proof is made on the tap, for the one request it goes with, and never kept. A passkey prompt
   still open when the sheet closes is called off, and whatever a prompt answers after that is
   dropped: someone who backed out of removing a passkey must not have it removed by a prompt
   they no longer see. */
export function ProveOwner({ passkey, password, onProof, explain = passwordError, danger = false, submitText }) {
  const name = useStore(s => s.user?.name) || ''
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const live = useRef(true)
  const prompt = useRef(null)   // the AbortController of a passkey prompt still open
  useEffect(() => {
    // Set here, not only initially: StrictMode unmounts and mounts again, and the first cleanup
    // must not leave the sheet thinking it is gone.
    live.current = true
    return () => { live.current = false; prompt.current?.abort() }
  }, [])
  const run = async proof => {
    if (busy) return
    setBusy(true); setErr(null)
    const ctl = new AbortController()
    prompt.current = ctl
    try {
      const body = await proof(ctl.signal)
      if (!live.current) return
      await onProof(body)
    } catch (e) { if (live.current && !dismissed(e)) setErr(explain(e)) }
    finally {
      if (prompt.current === ctl) prompt.current = null
      if (live.current) setBusy(false)
    }
  }
  const withPasskey = !!passkey && webauthnOK()
  const withPassword = ev => {
    ev.preventDefault()
    if (!pw) { setErr(t("ENTER_YOUR_PASSWORD" /* 请输入你的密码。 */)); return }
    run(async () => ({ current: pw }))
  }
  // A removal's buttons are red whichever proof carries it: each of them removes.
  const main = danger ? 'danger' : 'primary'
  return <>
    {withPasskey && <Button variant={main} icon="fingerprint" disabled={busy} onClick={() => run(signal => passkeyAssertion({ signal }))}>{t("CONFIRM_WITH_A_PASSKEY" /* 用通行密钥确认 */)}</Button>}
    {password && <form onSubmit={withPassword} noValidate>
      {withPasskey && <div className="dim small" style={{ margin: '14px 0 8px', textAlign: 'center' }}>{t("OR_WITH_YOUR_PASSWORD" /* 或使用你的密码 */)}</div>}
      {/* Tells a password manager which account the password belongs to. */}
      <input type="text" name="username" autoComplete="username" value={name} readOnly hidden />
      <input className="input" type="password" name="current-password" autoComplete="current-password" placeholder={t("CURRENT_PASSWORD" /* 当前密码 */)}
        value={pw} onChange={e => setPw(e.target.value)} />
      <div style={{ height: 10 }} />
      <Button type="submit" variant={withPasskey && !danger ? 'plain' : main} disabled={busy}>{submitText || t("CONTINUE" /* 继续 */)}</Button>
    </form>}
    {/* A profile with no passkey whose password no longer counts — the instance switched
        passwords off — has nothing left to answer with (docs/SELF_HOSTING.md). */}
    {!withPasskey && !password && <div className="dim small">{passkey
      ? t("THIS_BROWSER_CANNOT_CONFIRM_WITH_YOUR_PASSKEY_DO_THIS_ON_A_DEVICE" /* 此浏览器无法用你的通行密钥确认。请在保存了通行密钥的设备上操作。 */)
      : t("THIS_PROFILE_HAS_NO_PASSKEY_AND_THIS_SERVER_DOES_NOT_TAKE_PASSWORDS" /* 此档案没有通行密钥，而此服务器不接受密码，所以这里无法确认是你本人。请联系管理员。 */)}</div>}
    {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
  </>
}

/* Settings' account rows read the server as the screen opens. One that found the server down
   has nothing to show, and stayed missing until Settings was left and opened again, while the
   block above it already said "All synced". It asks again whenever the store hears from the
   server — a push or pull that landed, a check that found both sides in step — until it gets
   an answer. A refusal (a server from before the route, a 403) is an answer: asking again
   would only get the same one. */
export const notReached = e => e?.status == null || e.status >= 500
export function useAgainOnceReached(unreached, load) {
  const reachedAt = useStore(s => s.sync?.lastSynced)
  useEffect(() => { if (unreached) load() }, [reachedAt])
}

/* ------------------------------------------------------------------- Settings -------------
   Settings → Account → Password, for a signed-in browser. A first password needs a passkey
   ceremony right now (a session on its own could be a copied cookie); a change needs the
   current password, or the passkey when it was forgotten. Saving signs every other device out,
   which the sheet says before anyone taps. */
// `version` changes when the profile's passkeys do (Settings, components/Passkeys.jsx): whether the
// password may be removed depends on them, so the row asks again.
export function PasswordRow({ version = 0 }) {
  const [st, setSt] = useState(null)   // GET /api/account/password
  const [unreached, setUnreached] = useState(false)
  const load = () => api('/api/account/password').then(r => { setSt(r); setUnreached(false) }).catch(e => setUnreached(notReached(e)))
  useEffect(() => { load() }, [version])
  useAgainOnceReached(unreached, load)
  if (!st) return null
  // Nothing here could set a first password without a passkey ceremony.
  if (!st.set && (!webauthnOK() || !st.passkeys)) return null
  const blocked = !st.set && st.nameTaken
  const subtitle = blocked ? t("ANOTHER_PROFILE_ALREADY_SIGNS_IN_WITH_THIS_NAME" /* 已有另一个档案用这个名字登录。 */)
    : st.set ? t("SET_SIGN_IN_AS_COUNT" /* 已设置 · 以“{0}”登录 */, st.name)
    : t("NOT_SET_HANDY_FOR_SIGNING_IN_WHERE_PASSKEYS_DON_T_WORK" /* 未设置。在通行密钥用不了的地方登录时很方便。 */)
  return <>
    <Row icon="key" iconTint="var(--orange)" title={t("PASSWORD" /* 密码 */)} subtitle={subtitle} accessory={blocked ? 'none' : 'chevron'}
      onClick={blocked ? undefined : () => ui().openSheet(close => <PasswordSheet status={st} close={close} done={load} />)} />
    {/* The server only signs in by an address that belongs to a profile with a password, so
        without one the row is left out; one already saved stays reachable to change or remove. */}
    {(st.set || st.email) && <EmailRow status={st} done={load} />}
  </>
}

export function PasswordSheet({ status, close, done }) {
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const save = async withPasskey => {
    if (busy) return
    const bad = !withPasskey && !current ? t("ENTER_YOUR_PASSWORD" /* 请输入你的密码。 */)
      : length(next) < MIN_PASSWORD ? t("USE_AT_LEAST_COUNT_CHARACTERS" /* 至少使用 {0} 个字符。 */, MIN_PASSWORD)
      : next !== again ? t("THE_TWO_PASSWORDS_ARE_NOT_THE_SAME" /* 两次输入的密码不一致。 */)
      : null
    if (bad) { setErr(bad); return }
    setBusy(true); setErr(null)
    try {
      const proof = withPasskey ? await passkeyAssertion() : { current }
      await api('/api/account/password', { method: 'POST', body: JSON.stringify({ next, ...proof }) })
      close(); done()
      toast(t("PASSWORD_SAVED_YOU_RE_NOW_SIGNED_OUT_EVERYWHERE_ELSE" /* 密码已保存。你已在其他所有地方退出登录。 */))
    } catch (e) { if (!dismissed(e)) setErr(passwordError(e)) }
    finally { setBusy(false) }
  }
  const remove = () => ui().openSheet(c => <RemovePasswordSheet status={status} close={c} done={() => { close(); done() }} />)
  return <>
    <h3>{status.set ? t("CHANGE_PASSWORD" /* 更改密码 */) : t("SET_A_PASSWORD" /* 设置密码 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("SIGN_IN_AS_COUNT_WITH_IT_ON_DEVICES_WHERE_PASSKEYS_DO_NOT" /* 在通行密钥无法使用的设备上，用它以“{0}”登录。保存后你将在其他所有地方退出登录，已配对的手机需要重新配对。 */, status.name)}
    </div>
    <form onSubmit={ev => { ev.preventDefault(); save(!status.set) }} noValidate>
      {/* Tells a password manager which account the new password belongs to. */}
      <input type="text" name="username" autoComplete="username" value={status.name} readOnly hidden />
      {status.set && <>
        <input className="input" type="password" name="current-password" autoComplete="current-password" placeholder={t("CURRENT_PASSWORD" /* 当前密码 */)}
          value={current} onChange={e => setCurrent(e.target.value)} />
        <div style={{ height: 10 }} />
      </>}
      <input className="input" type="password" name="new-password" autoComplete="new-password" placeholder={t("NEW_PASSWORD" /* 新密码 */)}
        value={next} onChange={e => setNext(e.target.value)} />
      <div style={{ height: 10 }} />
      <input className="input" type="password" name="new-password-again" autoComplete="new-password" placeholder={t("REPEAT_THE_PASSWORD" /* 再次输入密码 */)}
        value={again} onChange={e => setAgain(e.target.value)} />
      <div className="dim small" style={{ marginTop: 6 }}>{t("AT_LEAST_COUNT_CHARACTERS_A_FEW_UNRELATED_WORDS_MAKE_A_GOOD_ONE" /* 至少 {0} 个字符。几个互不相关的词就是一个好密码。 */, MIN_PASSWORD)}</div>
      {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
      <div style={{ height: 12 }} />
      <Button type="submit" variant="primary" disabled={busy}>{status.set ? t("SAVE" /* 保存 */) : t("CONFIRM_WITH_PASSKEY_SAVE" /* 用通行密钥确认并保存 */)}</Button>
    </form>
    {status.set && status.passkeys > 0 && webauthnOK() && <>
      <div style={{ height: 8 }} />
      <Button type="button" variant="ghost" className="dim" disabled={busy} onClick={() => save(true)}>{t("FORGOT_IT_CONFIRM_WITH_YOUR_PASSKEY_INSTEAD" /* 忘记了？改用你的通行密钥确认 */)}</Button>
    </>}
    {status.set && status.passkeys > 0 && <>
      <div style={{ height: 8 }} />
      <button type="button" className="btn danger" disabled={busy} onClick={remove}>{t("REMOVE_PASSWORD" /* 移除密码 */)}</button>
    </>}
  </>
}

/* Removing the password asks for the proof setting one does (proveOwner in api/server.js): a
   copied session must not take away the owner's way in where passkeys do not work. The proof is
   the confirmation, so it is asked on the sheet that says what removing means — the password
   itself, or a passkey of this profile. Only offered while a passkey remains (the last way in
   stays), and the password counts here: this row exists only while the instance takes them. */
function RemovePasswordSheet({ status, close, done }) {
  const remove = async proof => {
    await api('/api/account/password', { method: 'DELETE', body: JSON.stringify(proof) })
    close(); done()
    toast(t("PASSWORD_REMOVED" /* 密码已移除 */))
  }
  return <>
    <h3>{t("REMOVE_YOUR_PASSWORD" /* 移除你的密码？ */)}</h3>
    <div className="muted small" style={{ marginBottom: 6 }}>{t("ONLY_YOUR_PASSKEYS_SIGN_IN_TO_THIS_PROFILE_AFTERWARDS" /* 之后只能用你的通行密钥登录此档案。 */)}</div>
    <div className="dim small" style={{ marginBottom: 14 }}>{t("FIRST_CONFIRM_THAT_IT_IS_YOU" /* 请先确认是你本人。 */)}</div>
    <ProveOwner passkey={status.passkeys > 0} password danger submitText={t("REMOVE" /* 移除 */)} onProof={remove} />
    <div style={{ height: 8 }} />
    <Button type="button" variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </>
}

/* Settings → Account → Sign-in e-mail, right under the password (and shown on the same terms:
   only while the instance takes passwords, and only where something here can confirm it is the
   owner). An address typed at "Sign in with password" instead of the profile name. Nothing is
   ever sent to it — there is no mail server behind openGym — so it is not verified either, and a
   forgotten password is still reset by the admin's code. Setting, changing and removing it ask
   the proof a password does (ProveOwner): a copied session must not choose how the owner signs
   in. `status` is GET /api/account/password, whose `email` only the owner ever gets. */
export function EmailRow({ status, done }) {
  const subtitle = status.email && !status.set ? t("COUNT_IS_SAVED_BUT_SIGNS_IN_ONLY_ONCE_THIS_PROFILE_HAS_A" /* “{0}”已保存，但只有此个人资料设置了密码后才能用它登录。 */, status.email)
    : status.email ? t("SIGN_IN_WITH_COUNT_INSTEAD_OF_YOUR_NAME" /* 用“{0}”代替名字登录 */, status.email)
    : t("NOT_SET_LETS_YOU_SIGN_IN_WITH_AN_E_MAIL_INSTEAD_OF" /* 未设置。设置后可以用邮箱代替名字登录。 */)
  return <Row icon="envelope" iconTint="var(--blue)" title={t("SIGN_IN_E_MAIL" /* 登录邮箱 */)} subtitle={subtitle} accessory="chevron"
    onClick={() => ui().openSheet(close => <EmailSheet status={status} close={close} done={done} />)} />
}

// Two steps: the address first, checked here before any passkey prompt opens, then the proof,
// which carries the save. An address in use is only refused after the proof (the server's rule,
// so that asking costs something), and is said on the proof step.
export function EmailSheet({ status, close, done }) {
  const [email, setEmail] = useState(status.email || '')
  const [step, setStep] = useState('edit')   // 'edit' | 'confirm'
  const [err, setErr] = useState(null)
  const clean = email.trim()
  const next = ev => {
    ev.preventDefault()
    const bad = !clean || !looksLikeEmail(clean) ? t("THAT_IS_NOT_AN_E_MAIL_ADDRESS" /* 这不是邮箱地址。 */)
      : foldEmail(clean) === status.email ? t("THAT_IS_ALREADY_YOUR_SIGN_IN_E_MAIL" /* 这已经是你的登录邮箱。 */)
      : null
    if (bad) { setErr(bad); return }
    setErr(null); setStep('confirm')
  }
  const save = async proof => {
    await api('/api/account/email', { method: 'POST', body: JSON.stringify({ email: clean, ...proof }) })
    close(); done()
    toast(t("E_MAIL_SAVED" /* 邮箱已保存 */))
  }
  const remove = () => ui().openSheet(c => <RemoveEmailSheet status={status} close={c} done={() => { close(); done() }} />)
  return <>
    <h3>{status.email ? t("CHANGE_SIGN_IN_E_MAIL" /* 更改登录邮箱 */) : t("ADD_A_SIGN_IN_E_MAIL" /* 添加登录邮箱 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("TYPE_IT_AT_SIGN_IN_WITH_PASSWORD_INSTEAD_OF_YOUR_PROFILE_NAME" /* 在“用密码登录”中用它代替档案名字。我们不会向它发送任何邮件；忘记密码仍由管理员重置。 */)}
    </div>
    {step === 'edit' ? <>
      <form onSubmit={next} noValidate>
        <input className="input" type="email" name="email" autoComplete="email" inputMode="email" placeholder={t("E_MAIL_ADDRESS" /* 邮箱地址 */)} maxLength={254}
          value={email} onChange={e => setEmail(e.target.value)} {...field} />
        {err && <div className="small" role="alert" style={errStyle}>{err}</div>}
        <div style={{ height: 12 }} />
        <Button type="submit" variant="primary">{t("CONTINUE" /* 继续 */)}</Button>
      </form>
      {status.email && <>
        <div style={{ height: 8 }} />
        <button type="button" className="btn danger" onClick={remove}>{t("REMOVE_E_MAIL" /* 移除邮箱 */)}</button>
      </>}
    </> : <>
      <div className="small" style={{ marginBottom: 6, fontWeight: 600, overflowWrap: 'anywhere' }}>{clean}</div>
      <div className="dim small" style={{ marginBottom: 14 }}>{t("FIRST_CONFIRM_THAT_IT_IS_YOU" /* 请先确认是你本人。 */)}</div>
      <ProveOwner passkey={status.passkeys > 0} password={!!status.set} submitText={t("SAVE" /* 保存 */)} onProof={save} />
      <div style={{ height: 8 }} />
      <Button type="button" variant="ghost" className="dim" onClick={() => setStep('edit')}>{t("BACK_A" /* 返回 */)}</Button>
    </>}
  </>
}

function RemoveEmailSheet({ status, close, done }) {
  const remove = async proof => {
    await api('/api/account/email', { method: 'DELETE', body: JSON.stringify(proof) })
    close(); done()
    toast(t("E_MAIL_REMOVED" /* 邮箱已移除 */))
  }
  return <>
    <h3>{t("REMOVE_YOUR_SIGN_IN_E_MAIL" /* 移除你的登录邮箱？ */)}</h3>
    <div className="muted small" style={{ marginBottom: 6 }}>{t("AFTERWARDS_YOU_SIGN_IN_WITH_YOUR_PROFILE_NAME_ONLY" /* 之后你只能用档案名字登录。 */)}</div>
    <div className="dim small" style={{ marginBottom: 14 }}>{t("FIRST_CONFIRM_THAT_IT_IS_YOU" /* 请先确认是你本人。 */)}</div>
    <ProveOwner passkey={status.passkeys > 0} password={!!status.set} danger submitText={t("REMOVE" /* 移除 */)} onProof={remove} />
    <div style={{ height: 8 }} />
    <Button type="button" variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </>
}
