// Mobile build only: how the Coach should run on this phone.
//
// Two answers. "Use my self-hosted openGym" hands the whole thing to the paired server — the
// same Coach the web app has, with whatever provider its admin configured; the phone only has
// to be paired. "Bring my own API key" runs the pipeline on the phone against Anthropic,
// OpenAI, Gemini or an OpenAI-compatible endpoint, with a key that stays in secure storage.
//
// The promise this screen keeps: nothing AI-shaped is loaded until a mode is chosen. Its only
// imports from the Coach core are the provider table and the five category names — the
// catalogue, the prompts and the validator arrive through one dynamic import, behind a
// progress line that reports real steps rather than a pretend byte counter.
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t } from '../lib/i18n.js'
import { MOBILE } from '../lib/mobile.js'
import { CATEGORY_TEXT } from '../lib/coach.js'
import { getApiKey, setApiKey, clearApiKey } from '../lib/coach-secrets.js'
import { HTTP_PROVIDERS, HTTP_PROVIDER_IDS, baseUrlFor, validateBaseUrl } from '../../../api/coach/core/providers.js'
import { DATA_CATEGORIES } from '../../../api/coach/core/categories.js'
import { ConnectSheet } from './MobileOnboarding.jsx'
import Icon from '../components/Icon.jsx'
import { Section, Row, Button, TextField } from '../components/ui.jsx'

// Literal t() calls, so check-source-strings sees the three lines; t(s) over a list of keys hid them.
const STEPS = () => [t("LOADING_THE_EXERCISE_CATALOGUE" /* 正在加载动作库… */), t("CHECKING_THE_ENDPOINT" /* 正在检查端点… */), t("READY" /* 准备好 */)]

// The phone calls the provider through CapacitorHttp, native networking that obeys the
// platform's cleartext rule, and Android refuses unencrypted http:// from apps
// (network_security_config.xml leaves it at the default, off). An http:// endpoint on the LAN
// therefore failed as a bare "could not reach the provider", with nothing to say why. It is
// refused up front with the two ways that work: HTTPS in front of the model, or the server's
// Coach, which has no such rule and reaches http:// on its own network.
const isCleartext = url => /^http:\/\//i.test(String(url || '').trim())
const cleartextRefused = () => t("ANDROID_BLOCKS_UNENCRYPTED_HTTP_CONNECTIONS_FROM_APPS_SO_THIS_PHONE_CAN_ONLY" /* Android 会阻止应用发起未加密的 http:// 连接，所以这部手机只能连接 https:// 端点。请在它前面加一层 HTTPS（Tailscale 或反向代理），或选择“使用我自托管的 op */)

export default function CoachSetup() {
  const nav = useNavigate()
  const user = useStore(s => s.user)
  const config = useStore(s => s.config)
  const coachLocal = useStore(s => s.coachLocal)
  const setCoachLocal = useStore(s => s.setCoachLocal)
  const refreshConfig = useStore(s => s.refreshConfig)
  const toast = useUI(s => s.toast)
  const openSheet = useUI(s => s.openSheet)

  const [choice, setChoice] = useState(null)              // 'server' | 'byok' | null
  const [provider, setProvider] = useState(coachLocal?.provider || 'anthropic')
  const [baseUrl, setBaseUrl] = useState(coachLocal?.baseUrl || '')
  const [model, setModel] = useState(coachLocal?.model || '')
  const [key, setKey] = useState('')
  const [hasKey, setHasKey] = useState(false)
  const [models, setModels] = useState(null)
  const [step, setStep] = useState(-1)                     // -1 idle, 0..2 running, 3 done
  const [busy, setBusy] = useState(false)

  useEffect(() => { if (!MOBILE) nav('/settings', { replace: true }) }, [])
  useEffect(() => { getApiKey().then(k => setHasKey(!!k)) }, [])
  // Ask the paired server afresh: the admin may have switched the Coach on since this phone booted.
  useEffect(() => { if (user) refreshConfig() }, [user])
  useEffect(() => { setModels(null); setModel(coachLocal?.provider === provider ? (coachLocal?.model || '') : '') }, [provider])

  const meta = HTTP_PROVIDERS[provider] || {}
  const host = hostOf(baseUrlFor(provider, { providerOptions: { [provider]: { baseUrl } } }))
  const serverHasCoach = !!(user && config?.coach?.enabled)

  const useServer = async () => {
    if (!user) return openSheet(close => <ConnectSheet close={close} />)
    await setCoachLocal({ mode: 'server' })
    toast(t("THE_COACH_IS_ON" /* 教练已开启 */))
    nav('/coach')
  }

  // The lazy load, and the reachability check, as three real steps.
  const prepare = async () => {
    const v = validateBaseUrl(meta.baseUrl ? baseUrl : '')
    if (!v.ok) return toast(v.error)
    // An empty field passes the validator on purpose: for a provider with a fixed endpoint,
    // empty means the default. This one has no default, so empty is nowhere to call.
    if (meta.baseUrl && !meta.defaultBase && !v.value) return toast(t("ENTER_THE_ENDPOINT_URL" /* 请输入端点 URL */))
    if (isCleartext(v.value)) return toast(cleartextRefused())
    if (!meta.keyOptional && !key.trim() && !hasKey) return toast(t("ENTER_YOUR_API_KEY" /* 请输入你的 API 密钥 */))
    setBusy(true); setStep(0)
    try {
      const local = await import('../lib/coach-local.js')
      setStep(1)
      const k = key.trim() || await getApiKey()
      const r = await local.localModels({ provider, baseUrl: v.value }, k)
      if (!r.ok) { setStep(-1); toast(t("COULD_NOT_REACH_THE_PROVIDER_COUNT" /* 无法连接到提供商：{0} */, r.error)); return }
      setModels(r.models)
      setStep(2)
      if (!model && meta.defaultModel && r.models.includes(meta.defaultModel)) setModel(meta.defaultModel)
    } catch (e) {
      setStep(-1); toast(e.message || t("COULD_NOT_CONNECT" /* 无法连接 */))
    } finally { setBusy(false) }
  }

  const save = async () => {
    // The same check "List models" makes. The endpoint field stays editable after a successful
    // listing, and taking `.value` off an unchecked result turned a typo into `baseUrl: null` —
    // saved, "The Coach is on", and the phone pointed at nothing.
    const v = validateBaseUrl(meta.baseUrl ? baseUrl : '')
    if (!v.ok) return toast(v.error)
    if (meta.baseUrl && !meta.defaultBase && !v.value) return toast(t("ENTER_THE_ENDPOINT_URL" /* 请输入端点 URL */))
    const chosen = model || meta.defaultModel
    if (!chosen) return toast(t("PICK_A_MODEL" /* 选择一个模型 */))
    // The endpoint can still be edited after the models were listed.
    if (isCleartext(v.value)) return toast(cleartextRefused())
    setBusy(true)
    try {
      // The mode first, the key second: the settings file is the cheap, reliable write, the
      // key goes through the platform's secure store, which is the step that can misbehave.
      // Either way the user hears what happened instead of watching a greyed-out button (#42).
      await setCoachLocal({ mode: 'byok', provider, model: chosen, baseUrl: meta.baseUrl ? v.value : null })
      if (key.trim()) { await setApiKey(key.trim()); setHasKey(true); setKey('') }
      toast(t("THE_COACH_IS_ON" /* 教练已开启 */))
      nav('/coach')
    } catch (e) {
      toast(e?.message || t("COULD_NOT_CONNECT" /* 无法连接 */))
    } finally { setBusy(false) }
  }

  const turnOff = async () => {
    await clearApiKey(); setHasKey(false)
    await setCoachLocal({ mode: 'off' })
    const local = await import('../lib/coach-local.js').catch(() => null)
    if (local) await local.localForget()
    setChoice(null)
    toast(t("THE_COACH_IS_OFF" /* 教练已关闭 */))
  }

  const current = coachLocal?.mode === 'server' ? t("RUNS_ON_YOUR_OPENGYM_SERVER" /* 在你的 openGym 服务器上运行 */)
    : coachLocal?.mode === 'byok' ? t("RUNS_ON_THIS_PHONE_WITH_YOUR_OWN_API_KEY" /* 在此手机上使用你自己的 API 密钥运行 */)
    : t("OFF_CHOOSE_HOW_THE_COACH_SHOULD_RUN" /* 已关闭。选择教练的运行方式。 */)

  return <div className="narrow">
    <div className="hdr">
      <button className="iconbtn" onClick={() => nav('/settings')} aria-label={t("BACK_A" /* 返回 */)}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginInlineStart: 10 }}><h1>{t("AI_COACH" /* AI 教练 */)}</h1></div>
    </div>

    <Section title={t("HOW_SHOULD_THE_COACH_RUN" /* 教练应如何运行？ */)} footer={current}>
      <Row icon="rocket" iconTint="var(--indigo)" title={t("USE_MY_SELF_HOSTED_OPENGYM" /* 使用我自托管的 openGym */)}
        subtitle={user ? (serverHasCoach ? t("YOUR_SERVER_RUNS_THE_COACH_WITH_WHATEVER_PROVIDER_ITS_ADMIN_SET_UP" /* 你的服务器使用管理员设置的提供商运行教练。除了已同步的内容外，此手机不会发送任何新数据。 */) : config == null ? t("LOADING" /* 加载中… */) : t("YOUR_SERVER_HAS_NO_COACH_ENABLED_ASK_ITS_ADMIN_OR_BRING_YOUR" /* 你的服务器没有启用教练。请联系管理员，或在下方使用你自己的密钥。 */)) : t("CONNECT_TO_MY_SERVER" /* 连接到我的服务器 */)}
        accessory="chevron" onClick={() => { if (!user || serverHasCoach) useServer(); else setChoice('server') }} />
      <Row icon="key" iconTint="var(--acc)" title={t("BRING_MY_OWN_API_KEY" /* 使用我自己的 API 密钥 */)}
        subtitle={t("THIS_PHONE_CALLS_THE_PROVIDER_DIRECTLY_WITH_YOUR_KEY_EVERY_REQUEST_IS" /* 此手机使用你的密钥直接调用提供商。每个请求都会计入你的账户。 */)}
        accessory="chevron" onClick={() => setChoice('byok')} />
    </Section>

    {choice === 'server' && !serverHasCoach && <div className="card">
      <div className="muted small">{t("YOUR_SERVER_HAS_NO_COACH_ENABLED_ASK_ITS_ADMIN_OR_BRING_YOUR" /* 你的服务器没有启用教练。请联系管理员，或在下方使用你自己的密钥。 */)}</div>
    </div>}

    {choice === 'byok' && <>
      <Section title={t("PROVIDER" /* 提供商 */)}>
        <div className="row" style={{ flexWrap: 'wrap', gap: 7, padding: '8px 12px' }}>
          {HTTP_PROVIDER_IDS.map(id => <button key={id} className={'chip' + (id === provider ? ' on' : '')} disabled={busy}
            onClick={() => setProvider(id)}>{HTTP_PROVIDERS[id].label}</button>)}
        </div>
      </Section>

      {meta.baseUrl && <Section title={t("ENDPOINT" /* 端点 */)}
        footer={isCleartext(baseUrl) ? <span style={{ color: 'var(--red)' }}>{cleartextRefused()}</span> : null}>
        <div style={{ padding: '8px 12px' }}>
          <TextField value={baseUrl} placeholder="https://ollama.example.com" inputMode="url" autoCapitalize="none" autoCorrect="off"
            onChange={e => setBaseUrl(e.target.value)} />
        </div>
      </Section>}

      <Section title={t("API_KEY" /* API 密钥 */)} footer={t("THE_KEY_IS_STORED_IN_THIS_PHONE_S_SECURE_STORAGE_AND_NEVER" /* 密钥保存在此手机的安全存储中，除调用提供商外不会离开手机。 */)}>
        <div style={{ padding: '8px 12px' }}>
          <TextField value={key} type="password" placeholder={hasKey ? '••••••••  ' + t("SAVED_A" /* （已保存） */) : (meta.keyPlaceholder || 'sk-…')} autoCapitalize="none" autoCorrect="off"
            onChange={e => setKey(e.target.value)} />
        </div>
      </Section>

      <Section title={t("WHAT_LEAVES_THIS_PHONE" /* 哪些数据会离开此手机 */)}>
        {DATA_CATEGORIES.map(k => {
          const [title, sub] = CATEGORY_TEXT[k]?.() || [k, '']
          return <Row key={k} icon="check" iconTint="var(--acc)" title={title} subtitle={sub} />
        })}
      </Section>
      <p className="sect-f" style={{ marginTop: -18, marginBottom: 22, lineHeight: 1.5 }}>
        {t("EACH_REQUEST_GOES_STRAIGHT_TO_COUNT_WITH_YOUR_KEY_NOBODY_ELSE_SEES" /* 每个请求都会用你的密钥直接发送到 {0}。其他人看不到，费用由你承担。 */, host || meta.label)}
      </p>

      {step >= 0 && <div className="card">
        {STEPS().map((s, i) => <div key={s} className="row" style={{ gap: 8, padding: '3px 0', opacity: i > step ? .4 : 1 }}>
          <span style={{ color: i < step || step === 2 ? 'var(--green)' : i === step ? 'var(--acc)' : 'var(--dim)' }}><Icon name={i < step || step === 2 ? 'check' : 'hourglass'} /></span>
          <span className="small">{s}</span>
        </div>)}
      </div>}

      {models && <Section title={t("MODEL" /* 模型 */)}>
        <div style={{ padding: '8px 12px' }}>
          <select className="input" value={model} disabled={busy} onChange={e => setModel(e.target.value)} style={{ width: '100%' }}>
            <option value="">{meta.defaultModel ? `(${meta.defaultModel})` : t("PICK_A_MODEL" /* 选择一个模型 */)}</option>
            {models.map(m => <option key={m} value={m}>{m}</option>)}
          </select>
        </div>
      </Section>}

      <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
        {!models
          ? <Button variant="primary" icon="sparkles" disabled={busy} onClick={prepare}>{t("LIST_MODELS" /* 列出模型 */)}</Button>
          : <Button variant="primary" icon="check" disabled={busy} onClick={save}>{t("SAVE_AND_USE_THE_COACH" /* 保存并使用教练 */)}</Button>}
        {models && <Button disabled={busy} onClick={prepare}>{t("LIST_MODELS" /* 列出模型 */)}</Button>}
      </div>
    </>}

    {coachLocal?.mode && coachLocal.mode !== 'off' && <Section title={t("CONTROLS" /* 控制 */)}>
      <Row icon="signOut" iconTint="var(--red)" title={t("TURN_THE_COACH_OFF_ON_THIS_PHONE" /* 在此手机上关闭教练 */)} danger onClick={turnOff} />
    </Section>}
  </div>
}

const hostOf = url => { try { return new URL(url).host } catch { return '' } }
