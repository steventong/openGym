// Mobile build only, first launch: the choice useStore.boot() couldn't make on its own — keep
// everything on this device, or connect to a self-hosted openGym server instead. See
// lib/remote.js for the pairing flow this hands off to.
import { useState, useRef, useEffect } from 'react'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t } from '../lib/i18n.js'
import Icon from '../components/Icon.jsx'
import { Button } from '../components/ui.jsx'
import { askAddDeviceData } from '../sheets.jsx'
import { normalizeServerUrl } from '../lib/remote.js'
import { loadCfAccess, saveCfAccess } from '../lib/cf-access.js'

// A plain http:// server works (#428), but whatever the app sends, the pairing code and then its
// token, crosses the network readable. Said once under the field, not in the way: on a home
// network that is often a fine trade. localhost is the phone itself and needs no warning.
export function plainHttp(raw) {
  const base = /^\s*http:\/\//i.test(String(raw || '')) ? normalizeServerUrl(raw) : null
  if (!base) return false
  const host = new URL(base).hostname
  return !/^(localhost|127\.\d+\.\d+\.\d+|\[::1\])$/i.test(host)
}


// `server`: the address the token is most likely for (the one being typed into ConnectSheet).
const openCfAccess = server => useUI.getState().openSheet(close => <CfAccessSheet close={close} server={server} />)

// A server behind Cloudflare Access (lib/cf-access.js): the service token that lets this phone
// through, entered before pairing because the pairing request has to get through as well. It is
// saved with the address of its server and only ever sent there, so the sheet asks for that
// address too and says it: a stored token shows the server it belongs to, not `server`.
export function CfAccessSheet({ close, server = '' }) {
  const [addr, setAddr] = useState(typeof server === 'string' ? server : '')
  const [clientId, setClientId] = useState('')
  const [clientSecret, setClientSecret] = useState('')
  const [had, setHad] = useState(false)
  const [busy, setBusy] = useState(false)
  const origin = normalizeServerUrl(addr)
  useEffect(() => {
    loadCfAccess().then(c => { if (c) { setClientId(c.clientId); setClientSecret(c.clientSecret); setHad(true); if (c.origin) setAddr(c.origin) } })
  }, [])
  const save = async (id, secret) => {
    if (!!id.trim() !== !!secret.trim()) { useUI.getState().toast(t("ENTER_BOTH_THE_CLIENT_ID_AND_THE_CLIENT_SECRET" /* 请同时填写 Client ID 和 Client Secret */)); return }
    if (id.trim() && !origin) { useUI.getState().toast(t("ENTER_THE_ADDRESS_OF_THE_SERVER_THIS_TOKEN_IS_FOR" /* 输入这个令牌所属服务器的地址 */)); return }
    setBusy(true)
    try {
      const saved = await saveCfAccess({ clientId: id, clientSecret: secret, server: origin })
      close()
      useUI.getState().toast(saved ? t("SAVED" /* 已保存 */) : t("REMOVED" /* 已移除 */))
    } catch (e) { useUI.getState().toast(e.message || t("COULD_NOT_SAVE" /* 无法保存 */)) }
    finally { setBusy(false) }
  }
  return <>
    <h3>{t("CLOUDFLARE_ACCESS" /* 术语：Cloudflare Access */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {t("ONLY_IF_YOUR_SERVER_IS_BEHIND_CLOUDFLARE_ACCESS_THE_SERVICE_TOKEN_THIS" /* 仅当你的服务器位于 Cloudflare Access 之后才需要：这部手机会在每个请求中附带的服务令牌。保存在这部手机的安全存储中。 */)}
    </div>
    <input className="input" placeholder={t("SERVER_ADDRESS_E_G_GYM_EXAMPLE_COM" /* 服务器地址（例如 gym.example.com） */)} value={addr} aria-label={t("SERVER_ADDRESS_E_G_GYM_EXAMPLE_COM" /* 服务器地址（例如 gym.example.com） */)}
      onChange={e => setAddr(e.target.value)} autoCapitalize="none" autoCorrect="off" inputMode="url" />
    {origin && <div className="dim small" role="note" style={{ marginTop: 8, lineHeight: 1.45, overflowWrap: 'anywhere' }}>
      {t("SENT_ONLY_TO_COUNT_NEVER_TO_ANOTHER_SERVER" /* 只发送到 {0}，绝不会发给其他服务器。 */, new URL(origin).host)}
    </div>}
    <div style={{ height: 10 }} />
    <input className="input" placeholder="CF-Access-Client-Id" value={clientId}
      onChange={e => setClientId(e.target.value)} autoCapitalize="none" autoCorrect="off" spellCheck={false} />
    <div style={{ height: 10 }} />
    <input className="input" type="password" placeholder="CF-Access-Client-Secret" value={clientSecret}
      onChange={e => setClientSecret(e.target.value)} autoCapitalize="none" autoCorrect="off" spellCheck={false} autoComplete="off" />
    <div style={{ height: 12 }} />
    <Button variant="primary" onClick={() => save(clientId, clientSecret)} disabled={busy}>{t("SAVE" /* 保存 */)}</Button>
    {had && <>
      <div style={{ height: 10 }} />
      <Button icon="trash" onClick={() => save('', '')} disabled={busy}>{t("REMOVE" /* 移除 */)}</Button>
    </>}
  </>
}

// `again`: a phone whose server stopped accepting it (components/ServerSync.jsx pairAgain) — the
// address it had is filled in when it still has one, so only the new code is left to type, and
// the sheet says that what the phone kept is merged, not replaced.
export function ConnectSheet({ close, initialUrl = '', again = false }) {
  const { connectToServer } = useStore()
  const [url, setUrl] = useState(initialUrl)
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  // Why the last try failed, under the fields: a toast is gone in two seconds, too soon to read
  // "the server was reached but refused the app's request" and act on it (#329).
  const [error, setError] = useState('')
  const ref = useRef(null)
  const codeRef = useRef(null)
  useEffect(() => { setTimeout(() => (initialUrl ? codeRef : ref).current?.focus(), 250) }, [])
  const go = async () => {
    if (!url.trim() || !code.trim()) { useUI.getState().toast(t("ENTER_YOUR_SERVER_ADDRESS_AND_THE_CODE" /* 输入你的服务器地址和配对码 */)); return }
    setBusy(true)
    setError('')
    try { await connectToServer(url.trim(), code.trim(), askAddDeviceData); close(); useUI.getState().toast(t("CONNECTED" /* 已连接 */)) }
    catch (e) { setError(e.message || t("COULD_NOT_CONNECT" /* 无法连接 */)) }
    finally { setBusy(false) }
  }
  return <>
    <h3>{again ? t("PAIR_AGAIN" /* 重新配对 */) : t("CONNECT_TO_MY_SERVER" /* 连接到我的服务器 */)}</h3>
    <div className="muted small" style={{ marginBottom: 14 }}>
      {again
        ? t("OPEN_SETTINGS_ACCOUNT_PAIR_THE_MOBILE_APP_ON_YOUR_OPENGYM_SITE_IN" /* 在浏览器中打开你的 openGym 网站的 设置 → 账号 →“配对手机应用”，然后输入那里显示的新配对码。这部手机保留的内容会合并到你的账号。 */)
        : t("OPEN_SETTINGS_ACCOUNT_PAIR_THE_MOBILE_APP_ON_THE_OPENGYM_SITE_YOU" /* 在你已登录的 openGym 网站上，打开 设置 → 账号 →“配对手机应用”，然后输入其地址和那里显示的配对码。 */)}
    </div>
    <input ref={ref} className="input" placeholder={t("SERVER_ADDRESS_E_G_GYM_EXAMPLE_COM" /* 服务器地址（例如 gym.example.com） */)} value={url}
      onChange={e => setUrl(e.target.value)} autoCapitalize="none" autoCorrect="off" inputMode="url" />
    {plainHttp(url) && <div className="dim small" role="note" style={{ marginTop: 8, lineHeight: 1.45 }}>
      {t("PLAIN_HTTP_ISN_T_ENCRYPTED_FINE_ON_YOUR_HOME_NETWORK_BUT_USE" /* 普通 http:// 不加密。在家庭网络里没问题，但如果你的服务器能从互联网访问，请用 https://。 */)}
    </div>}
    <div style={{ height: 10 }} />
    <input ref={codeRef} className="input" placeholder={t("PAIRING_CODE" /* 配对码 */)} maxLength={8} value={code}
      onChange={e => setCode(e.target.value.toUpperCase())} style={{ letterSpacing: '.14em', fontWeight: 600, textAlign: 'center' }} />
    {error && <div className="small" role="alert" style={{ color: 'var(--red)', marginTop: 10, lineHeight: 1.45, overflowWrap: 'anywhere' }}>{error}</div>}
    <div style={{ height: 12 }} />
    <Button variant="primary" onClick={go} disabled={busy}>{busy ? t("CONNECTING" /* 连接中… */) : t("CONNECT" /* 连接 */)}</Button>
    <div style={{ height: 10 }} />
    <Button icon="key" onClick={() => openCfAccess(normalizeServerUrl(url) || '')} disabled={busy}>{t("CLOUDFLARE_ACCESS" /* 术语：Cloudflare Access */)}</Button>
  </>
}

export default function MobileOnboarding() {
  const { chooseLocalMode } = useStore()
  const head = <>
    <div style={{ fontSize: 54, display: 'flex', justifyContent: 'center', color: 'var(--acc)' }}><Icon name="dumbbell" /></div>
    <h1 style={{ fontSize: 34, fontWeight: 700, letterSpacing: '-.028em', margin: '10px 0 4px' }}>openGym</h1>
  </>
  const wrap = { display: 'flex', flexDirection: 'column', justifyContent: 'center', minHeight: '78vh', textAlign: 'center' }
  return (
    <div className="narrow" style={wrap}>
      {head}
      <div className="muted" style={{ marginBottom: 34 }}>{t("HOW_DO_YOU_WANT_TO_USE_OPENGYM" /* 你想如何使用 openGym？ */)}</div>
      <Button variant="primary" icon="lock" onClick={() => chooseLocalMode()}>{t("USE_ON_THIS_DEVICE" /* 在此设备上使用 */)}</Button>
      <div style={{ height: 10 }} />
      <Button icon="cloud" onClick={() => useUI.getState().openSheet(close => <ConnectSheet close={close} />)}>{t("CONNECT_TO_MY_SERVER" /* 连接到我的服务器 */)}</Button>
      <div className="dim small" style={{ marginTop: 26, lineHeight: 1.5 }}>
        {t("LOCAL_KEEPS_EVERYTHING_ON_THIS_PHONE_CONNECTING_SYNCS_TO_YOUR_OWN_OPENGYM" /* 本地模式会把所有内容保留在这部手机上。连接则会改为与你自己的 openGym 服务器同步。之后可以在设置中更改。 */)}
      </div>
      <div style={{ height: 18 }} />
      <Button icon="gear" onClick={() => openCfAccess()}>{t("CONNECTION_SETTINGS" /* 连接设置 */)}</Button>
    </div>
  )
}
