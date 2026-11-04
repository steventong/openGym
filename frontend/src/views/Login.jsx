import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { webauthnOK, passkeyLogin, passkeyRegister, passkeyError, bio } from '../lib/api.js'
import { hasData } from '../store/useStore.js'
import { t } from '../lib/i18n.js'
import { DEMO, REPO } from '../lib/demo.js'
import { guestAllowed } from '../lib/guest.js'
import { useState, useRef, useEffect } from 'react'
import Icon from '../components/Icon.jsx'
import { Button, Segmented } from '../components/ui.jsx'
import { askAddDeviceData } from '../sheets.jsx'
import { passwordOn, PasswordRegisterForm, openPasswordSignIn } from '../components/PasswordAuth.jsx'
import { openDeviceLinkRedeem } from '../components/Passkeys.jsx'

function RegisterSheet({ close }) {
  const { setUser, pushState, pullState, loadConfig } = useStore()
  const config = useStore(s => s.config)
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const inviteOnly = !!config?.invite_only
  // A password is offered only where the instance allows it (#118), and is the only choice in a
  // browser that cannot make a passkey. Where both work, the passkey stays the first one.
  const pwOn = passwordOn(config)
  const [how, setHow] = useState(webauthnOK() ? 'passkey' : 'password')
  const ref = useRef(null)
  useEffect(() => { setTimeout(() => ref.current?.focus(), 250) }, [])
  // Boot already fetched this; retry here only if that attempt failed, so the invite field still
  // appears on an instance whose config arrived late rather than never.
  useEffect(() => { loadConfig() }, [loadConfig])
  const go = async () => {
    const n = name.trim()
    if (!n) { useUI.getState().toast(t("ENTER_A_NAME" /* 请输入名字 */)); return }
    if (inviteOnly && !code.trim()) { useUI.getState().toast(t("AN_INVITE_CODE_IS_REQUIRED" /* 需要邀请码 */)); return }
    try {
      const u = await passkeyRegister(n, code.trim())
      setUser(u); close()
      if (hasData(useStore.getState().S)) { await pushState(); useUI.getState().toast(t("PROFILE_CREATED_AND_THIS_DEVICE_S_DATA_MOVED_INTO_IT" /* 档案已创建，本设备的数据已转入 */)) }
      else { await pullState(); useUI.getState().toast(t("WELCOME_COUNT" /* 欢迎，{0} */, u.name)) }
    } catch (e) { if (e.name !== 'NotAllowedError' && e.name !== 'AbortError') useUI.getState().toast(passkeyError(e, t("REGISTRATION_FAILED" /* 注册失败 */))) }
  }
  const choose = pwOn && webauthnOK() && <>
    <Segmented options={[{ value: 'passkey', label: t("PASSKEY" /* 通行密钥 */), icon: 'fingerprint' }, { value: 'password', label: t("PASSWORD" /* 密码 */), icon: 'key' }]}
      value={how} onChange={setHow} />
    <div style={{ height: 12 }} />
  </>
  if (pwOn && how === 'password') return <>
    <h3>{t("CREATE_YOUR_PROFILE" /* 创建你的档案 */)}</h3>
    {choose}
    <div className="muted small" style={{ marginBottom: 14 }}>{t("PICK_A_NAME_AND_A_PASSWORD_YOU_SIGN_IN_WITH_BOTH" /* 选择一个名字和一个密码。你用两者一起登录。 */)}</div>
    <PasswordRegisterForm close={close} inviteOnly={inviteOnly} name={name} setName={setName} code={code} setCode={setCode} />
  </>
  return <>
    <h3>{t("CREATE_YOUR_PROFILE" /* 创建你的档案 */)}</h3>
    {choose}
    <div className="muted small" style={{ marginBottom: 14 }}>{t("PICK_A_NAME_THEN_CONFIRM_WITH_COUNT_THE_PASSKEY_LIVES_ON_YOUR" /* 取个名字，然后用{0}确认。通行密钥保存在你的设备上，所以不需要密码。 */, bio())}</div>
    <input ref={ref} className="input" placeholder={t("YOUR_NAME" /* 你的名字 */)} maxLength={40} value={name} onChange={e => setName(e.target.value)} />
    {inviteOnly && <>
      <div style={{ height: 10 }} />
      <input className="input" placeholder={t("INVITE_CODE" /* 邀请码 */)} maxLength={40} value={code}
        onChange={e => setCode(e.target.value.toUpperCase())} style={{ letterSpacing: '.14em', fontWeight: 600, textAlign: 'center' }} />
      <div className="dim small" style={{ marginTop: 6 }}>{t("THIS_APP_IS_INVITE_ONLY_ENTER_THE_CODE_YOU_WERE_GIVEN" /* 此应用仅限邀请。请输入你收到的邀请码。 */)}</div>
    </>}
    <div style={{ height: 12 }} />
    <Button variant="primary" onClick={go}>{t("CREATE_PASSKEY" /* 创建通行密钥 */)}</Button>
  </>
}

export default function Login() {
  const { setUser, adoptProfile, setGuest } = useStore()
  const config = useStore(s => s.config)
  const canGuest = guestAllowed(config)
  const pwOn = passwordOn(config)
  const register = () => useUI.getState().openSheet(close => <RegisterSheet close={close} />)
  const signIn = async () => {
    try { const u = await passkeyLogin(); setUser(u, { adopt: true }); await adoptProfile(askAddDeviceData); useUI.getState().toast(t("WELCOME_BACK_COUNT" /* 欢迎回来，{0} */, u.name)) }
    catch (e) { if (e.name !== 'NotAllowedError' && e.name !== 'AbortError') useUI.getState().toast(passkeyError(e, t("SIGN_IN_FAILED" /* 登录失败 */))) }
  }
  const head = <>
    <div style={{ fontSize: 54, display: 'flex', justifyContent: 'center', color: 'var(--acc)' }}><Icon name="dumbbell" /></div>
    <h1 style={{ fontSize: 34, fontWeight: 700, letterSpacing: '-.028em', margin: '10px 0 4px' }}>openGym</h1>
  </>
  const wrap = { display: 'flex', flexDirection: 'column', justifyContent: 'center', minHeight: '78vh', textAlign: 'center' }

  // Demo build: no backend to sign in against — the only way in is the local guest profile.
  if (DEMO) return (
    <div className="narrow" style={wrap}>
      {head}
      <div className="muted" style={{ marginBottom: 30 }}>{t("LIVE_DEMO_EVERYTHING_STAYS_IN_THIS_BROWSER" /* 在线演示。所有内容都留在此浏览器中。 */)}</div>
      <Button variant="primary" icon="play" onClick={() => setGuest(true)}>{t("START_THE_DEMO" /* 开始演示 */)}</Button>
      <div className="card small muted" style={{ textAlign: 'start', marginTop: 16 }}>
        {t("THIS_DEMO_RUNS_ENTIRELY_IN_YOUR_BROWSER_ON_EXAMPLE_DATA_NOTHING_IS" /* 此演示完全在你的浏览器中用示例数据运行，不会发送任何内容。通行密钥登录和多设备同步随 openGym 服务器提供，自托管即可获得。 */)}
      </div>
      <div className="dim small" style={{ marginTop: 22, lineHeight: 1.6 }}>
        <a href={REPO} target="_blank" rel="noopener">{t("SELF_HOST_IT_IN_A_MINUTE" /* 一分钟内自托管 → */)}</a>
      </div>
    </div>
  )

  return (
    <div className="narrow" style={wrap}>
      {head}
      <div className="muted" style={{ marginBottom: 34 }}>{t("YOUR_WORKOUTS_YOUR_WEIGHTS_YOUR_PROFILE" /* 你的训练。你的重量。你的档案。 */)}</div>
      {webauthnOK() ? <>
        <Button variant="primary" icon="fingerprint" onClick={signIn}>{t("SIGN_IN_WITH_PASSKEY" /* 用通行密钥登录 */)}</Button>
        <div style={{ height: 10 }} />
        {pwOn && <><Button icon="key" onClick={() => openPasswordSignIn()}>{t("SIGN_IN_WITH_PASSWORD" /* 用密码登录 */)}</Button><div style={{ height: 10 }} /></>}
        <Button icon="plusCircle" onClick={register}>{t("CREATE_NEW_PROFILE" /* 创建新档案 */)}</Button>
        {/* Already signed in on another device: a code from there gives this one a passkey of
            its own (#95), instead of a new, empty profile. */}
        <div style={{ height: 10 }} />
        <Button variant="ghost" className="dim" icon="qr" onClick={openDeviceLinkRedeem}>{t("USE_A_CODE_FROM_YOUR_OTHER_DEVICE" /* 使用另一台设备上的代码 */)}</Button>
        {canGuest && <div style={{ height: 4 }} />}
      </> : pwOn ? <>
        {/* Plain http on a LAN address, or a browser without passkey support: the password is
            the way in, and the only way to create a profile from here. */}
        <div className="card small muted" style={{ textAlign: 'start', marginBottom: 14 }}>{t("THIS_BROWSER_DOESN_T_SUPPORT_PASSKEYS_SIGN_IN_WITH_YOUR_NAME_AND" /* 此浏览器不支持通行密钥。请改用名字和密码登录。 */)}</div>
        <Button variant="primary" icon="key" onClick={() => openPasswordSignIn()}>{t("SIGN_IN_WITH_PASSWORD" /* 用密码登录 */)}</Button>
        <div style={{ height: 10 }} />
        <Button icon="plusCircle" onClick={register}>{t("CREATE_NEW_PROFILE" /* 创建新档案 */)}</Button>
        {canGuest && <div style={{ height: 10 }} />}
      </> : <div className="card small muted" style={{ textAlign: 'start' }}>{canGuest
        ? t("THIS_BROWSER_DOESN_T_DO_PASSKEYS_BUT_YOU_CAN_STILL_USE_OPENGYM" /* 这个浏览器不支持通行密钥，不过你仍然可以在本设备上本地使用 openGym。 */)
        // Without passkeys and without the guest entrance there is no way in from this browser,
        // so say that plainly instead of offering a local profile that cannot be created.
        : t("THIS_BROWSER_DOESN_T_SUPPORT_PASSKEYS_AND_THIS_INSTANCE_REQUIRES_AN_ACCOUNT" /* 此浏览器不支持通行密钥，且此服务器需要账户。请换用支持通行密钥的浏览器或设备。 */)}</div>}
      {canGuest && <Button variant="ghost" className="dim" onClick={() => setGuest(true)}>{t("CONTINUE_WITHOUT_ACCOUNT" /* 不用账号继续 */)}</Button>}
      <div className="dim small" style={{ marginTop: 26, lineHeight: 1.5 }}>{pwOn ? t("PASSKEYS_USE_COUNT_A_PASSWORD_WORKS_TOO_WHERE_PASSKEYS_DO_NOT" /* 通行密钥使用{0}。在通行密钥无法使用的地方，也可以用密码。 */, bio()) : t("PASSKEYS_USE_COUNT_NO_PASSWORDS_TO_REMEMBER" /* 通行密钥使用{0}。不用再记密码。 */, bio())}<br />{t("EACH_PROFILE_KEEPS_ITS_OWN_PLAN_WORKOUTS_BODY_WEIGHT" /* 每个档案有自己的计划、训练和体重。 */)}</div>
    </div>
  )
}
