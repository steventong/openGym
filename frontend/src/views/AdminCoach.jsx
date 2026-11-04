import { fmtAgo } from '../lib/format.js'
import { t, translateValue } from '../lib/i18n.js'
import { useEffect, useState } from 'react'
import { useUI } from '../store/useUI.js'
import { useStore } from '../store/useStore.js'
import { api } from '../lib/api.js'
import Icon from '../components/Icon.jsx'
import { Button, Switch, TextArea, TextField } from '../components/ui.jsx'
import { confirmSheet } from '../sheets.jsx'

/* The operator's side of the Coach, laid out as a guided setup: one master switch, numbered
   steps that each say what they are for, and everything an owner rarely needs folded away
   under "Advanced" and "Activity". 管理后台同样使用共享的 JSON 文案，支持中英文。

   What it never shows: anybody's intake answers, payloads or proposals. An admin can enable
   the feature and see that jobs ran; they cannot read what their users asked it.

   This is the ONLY place the Coach can be switched off for everyone. Users can decline the
   consent screen for themselves, but they cannot disable the feature — that is an operator
   decision, so it lives with the operator. */

const rel = ts => ts ? fmtAgo(new Date(ts).getTime()) : t("NEVER" /* 从未 */)

// Extra static headers for the endpoint, one `Name: value` per line — e.g. a gateway's
// routing/session header (opencode Go's `x-opencode-session`). Parsed client-side so a
// typo reads as a message on the card, not a 400 the admin has to decode. Empty clears.
export const headersToText = h => h && typeof h === 'object'
  ? Object.entries(h).map(([k, v]) => `${k}: ${v}`).join('\n')
  : ''
export function parseHeadersText(text) {
  const lines = String(text || '').split('\n').map(l => l.trim()).filter(Boolean)
  if (!lines.length) return { headers: null }
  const out = {}
  for (const line of lines) {
    const i = line.indexOf(':')
    if (i < 1) return { error: t("ADMIN_HEADER_INVALID" /* 请求头格式应为“名称: 值”：{0} */, line.slice(0, 40)) }
    const name = line.slice(0, i).trim()
    const value = line.slice(i + 1).trim()
    if (!name || !value) return { error: t("ADMIN_HEADER_INVALID" /* 请求头格式应为“名称: 值”：{0} */, line.slice(0, 40)) }
    out[name] = value
  }
  return { headers: out }
}

// Which chips go under which heading. Runtime-backed providers are the ones that need the
// bigger `coach` image; the fixture exists so the whole loop can be walked without any account.
const RUNTIME_IDS = ['claude', 'codex']
const TESTING_IDS = ['fixture']

export default function AdminCoach() {
  const toast = useUI(s => s.toast)
  const openSheet = useUI(s => s.openSheet)
  const [d, setD] = useState(null)
  const [busy, setBusy] = useState(false)
  // The models the endpoint serves, fetched on demand. Seeded from the status call when the
  // stored key already let it list them.
  const [models, setModels] = useState(null)
  // The last "Test the Coach" outcome, shown inline where the button is rather than only as a
  // toast that is gone before anyone has read the provider's reason.
  const [testResult, setTestResult] = useState(null)

  // Every change on this card ends in load(), so load() also re-reads /api/config. The app reads
  // that once per boot, and the Plan tab's Coach card hangs off it: without the re-read, an admin
  // who has just switched the Coach on and connected it finds no Coach anywhere until a reload,
  // which reads as a setup that failed (Discord #install-help, 2026-09-19).
  const load = () => api('/api/admin/coach').then(r => { setD(r); setModels(r.knownModels || null); useStore.getState().refreshConfig() }).catch(e => toast(e.message || (t("FAILED_TO_LOAD" /* 加载失败 */))))
  useEffect(() => { load() }, [])

  const patch = async body => {
    setBusy(true)
    try { await api('/api/admin/coach/config', { method: 'POST', body: JSON.stringify(body) }); await load() }
    catch (e) { toast(e.message) }
    setBusy(false)
  }
  const loadModels = async () => {
    setBusy(true)
    try {
      const r = await api('/api/admin/coach/models', { method: 'POST', body: '{}' })
      if (r.ok) { setModels(r.models); toast(t("ADMIN_MODELS_COUNT" /* {0} 个模型 */, r.models.length)) } else toast(r.error || (t("COULD_NOT_LIST_MODELS" /* 无法获取模型列表 */)))
    } catch (e) { toast(e.message) }
    setBusy(false)
  }
  const test = async () => {
    setBusy(true); setTestResult({ pending: true })
    try {
      // The server gives the provider up to 90 s for this round-trip (api/coach/jobs.js testRun),
      // longer than api()'s default for a request; a slow local model must still get its answer.
      const r = await api('/api/admin/coach/test', { method: 'POST', body: '{}', timeout: 150000 })
      setTestResult(r)
      toast(r.ok ? (t("COACH_TEST_PASSED" /* 教练连接测试通过 ✅ */)) : (t("TEST_FAILED" /* 测试失败 */)))
      await load()
    } catch (e) { setTestResult({ ok: false, error: e.message }); toast(e.message) }
    setBusy(false)
  }
  // A number input hands back "" for anything it cannot parse, and +"" is 0, which the hint on
  // this card calls "no limit". So an admin who cleared the box to retype and clicked elsewhere
  // had just uncapped daily spend on their API key, silently. An empty box is no change now: the
  // stored value goes back into it and nothing is written. Removing the cap takes typing a 0.
  const capBlur = key => e => {
    if (e.target.value.trim() === '') { e.target.value = d.caps[key]; return }
    if (+e.target.value !== d.caps[key]) patch({ caps: { ...d.caps, [key]: +e.target.value } })
  }
  const disconnect = async () => {
    setBusy(true)
    try { await api('/api/admin/coach/disconnect', { method: 'POST', body: JSON.stringify({ provider: d.provider }) }); toast((t("CREDENTIAL_REMOVED" /* 凭据已移除 */))); await load() }
    catch (e) { toast(e.message) }
    setBusy(false)
  }

  if (!d) return <div className="card"><div className="muted small">{t("LOADING_COACH_STATUS" /* 正在加载教练状态… */)}</div></div>

  if (d.disabledByEnv) return <div className="card">
    <h2 style={{ margin: '0 0 6px' }}>{t("AI_COACH" /* AI 教练 */)}</h2>
    <div className="adm-lead">{t("FORCE_DISABLED_BY" /* 服务器已通过环境变量停用： */)} <code>{t("COACH_DISABLED" /* 术语：COACH_DISABLED */)}</code> {t("IN_THE_SERVER_S_ENVIRONMENT_REMOVE_THAT_VARIABLE_AND_RESTART_TO_CONFIGURE" /* 。移除此变量并重启服务器后，即可在此配置教练。 */)}</div>
  </div>

  const meta = d.providers.find(p => p.id === d.provider) || {}
  const authState = d.auth?.state
  const authed = authState === 'connected' || authState === 'not-required' || authState === 'optional'
  const needsEndpoint = !!meta.baseUrl
  const hasEndpoint = !needsEndpoint || !!d.baseUrl
  const live = d.enabled && d.runtime.ok && authed && hasEndpoint

  const status = !d.enabled ? (t("OFF_USERS_WON_T_SEE_THE_COACH_ANYWHERE_IN_THE_APP" /* 已关闭。用户在 App 中不会看到教练入口。 */))
    : live ? <>{t("ON_B" /* 已开启 · */)} {meta.label}{d.model ? ' · ' + d.model : ''}</>
      : !hasEndpoint ? (t("ON_BUT_NO_ENDPOINT_YET_FINISH_STEP" /* 已开启，但尚未设置服务地址。请完成第 2 步。 */))
        : !authed ? (t("ON_BUT_NO_CREDENTIAL_YET_FINISH_THE_CREDENTIAL_STEP" /* 已开启，但尚未配置凭据。请完成凭据设置。 */))
          : !d.runtime.ok ? (t("ON_BUT_THE_PROVIDER_CAN_T_BE_REACHED_SEE_THE_TEST_STEP" /* 已开启，但无法连接服务。请查看测试结果。 */))
            : 'On'

  // Chips, grouped.
  const groups = [
    { title: (t("PASTE_AN_API_KEY" /* 粘贴 API 密钥 */)), hint: (t("PLAIN_HTTPS_TO_THE_PROVIDER_WORKS_ON_THE_DEFAULT_API_IMAGE_NOTHING" /* 通过 HTTPS 直接请求服务商，无需安装额外组件，默认 api 镜像即可运行。 */)), items: d.providers.filter(p => p.http) },
    { title: (t("RUNS_A_LOCAL_AI_RUNTIME" /* 运行本地 AI 程序 */)), hint: (t("NEEDS_THE_BIGGER_API_IMAGE_BUILT_WITH_TARGET_COACH" /* 需要使用 --target coach 构建包含运行环境的 api 镜像。 */)), items: d.providers.filter(p => RUNTIME_IDS.includes(p.id)) },
    { title: t("ADMIN_TESTING" /* 测试服务 */), hint: (t("A_BUILT_IN_FAKE_THAT_ANSWERS_INSTANTLY_SO_THE_WHOLE_LOOP_CAN" /* 内置测试服务会立即返回模拟结果，无需账号即可验证完整流程。 */)), items: d.providers.filter(p => TESTING_IDS.includes(p.id)) }
  ]

  const hasCredentialStep = !!(meta.setupToken || meta.apiKey)
  // The model this provider was explicitly GIVEN — as opposed to `d.model`, which falls back to
  // the provider's own default. Both halves of the Model step (the dropdown and the free-text
  // box) read this one value, so they cannot disagree about what is configured.
  const chosenModel = d.models?.[d.provider] || ''
  const step1Done = !!d.provider
  const step2Done = hasEndpoint
  const step3Done = authed
  const step4Done = !!d.model
  const step5Done = !!testResult?.ok || !!d.lastSuccess
  // Step numbers only count the steps this provider actually shows — and like any wizard,
  // only the first unfinished step stands open; everything done folds to its summary line.
  const flags = [step1Done, ...(needsEndpoint ? [step2Done] : []), ...(hasCredentialStep ? [step3Done] : []), step4Done, step5Done]
  const doneCount = flags.filter(Boolean).length
  const firstTodo = flags.indexOf(false)
  let n = 1
  let idx = 0
  const num = () => n++
  const stepAt = () => { const i = idx++; return { open: i === (firstTodo === -1 ? -1 : firstTodo), key: i + ':' + (i === firstTodo) } }

  // Off = a quiet, optional feature: one clean pitch and one button, no half-dimmed controls.
  if (!d.enabled) return <div className="card">
    <div className="adm-hero">
      <div className="adm-hero-av"><Icon name="sparkles" /></div>
      <h2>{t("AI_COACH" /* AI 教练 */)}</h2>
      <p>{t("AN_OPTIONAL_COACH_THAT_DESIGNS_TRAINING_PLANS_AND_REVIEWS_WHAT_PEOPLE_ACTUALLY" /* 可选的训练教练，能够设计计划并分析已记录的训练。当前已关闭，所有用户均看不到教练入口。 */)}</p>
      <div className="adm-hero-feats">
        <div><Icon name="key" /><span><b>{t("BRING_ANY_AI" /* 自由选择 AI 服务。 */)}</b> {t("AN_API_KEY_FROM_ANTHROPIC_OPENAI_OR_GEMINI_OR_A_FREE_LOCAL" /* 支持 Anthropic、OpenAI、Gemini API 密钥，也支持通过 Ollama 运行的免费本地模型。 */)}</span></div>
        <div><Icon name="shield" /><span><b>{t("PRIVATE_BY_DESIGN" /* 严格控制数据访问。 */)}</b> {t("A_STRICT_ALLOWLIST_DECIDES_WHAT_LEAVES_EVERY_CHANGE_NEEDS_THE_USER_S" /* 仅发送白名单允许的数据；每项修改都需用户确认，且支持撤销。 */)}</span></div>
        <div><Icon name="person" /><span><b>{t("EACH_USER_DECIDES" /* 由用户自行决定。 */)}</b> {t("TURNING_IT_ON_ONLY_MAKES_THE_COACH_AVAILABLE_EVERY_PERSON_CONSENTS_FOR" /* 开启后仅提供教练入口，每位用户仍需自行同意数据使用说明。 */)}</span></div>
      </div>
      <Button variant="primary" icon="sparkles" disabled={busy} onClick={() => patch({ enabled: true })}>{t("SET_UP_THE_COACH" /* 设置教练 */)}</Button>
    </div>
  </div>

  return <div className="card" style={{ borderColor: live ? 'var(--acc)' : undefined }}>
    <div className="row between" style={{ marginBottom: 2 }}>
      <h2 style={{ margin: 0 }}>{t("AI_COACH" /* AI 教练 */)}</h2>
      <Switch checked={!!d.enabled} disabled={busy} onChange={v => patch({ enabled: v })} />
    </div>
    <div className="adm-status">
      <span className={'adm-pill ' + (live ? 'ok' : 'warn')}>{live ? (t("READY_A" /* 已就绪 */)) : (t("NOT_READY" /* 尚未就绪 */))}</span>
      <span>{status}</span>
    </div>
    {!live && <div className="adm-progress" aria-hidden="true"><i style={{ width: Math.round(doneCount / flags.length * 100) + '%' }} /></div>}
    <div className="adm-lead">
      {live ? (t("USERS_FIND_THE_COACH_UNDER_PLAN_COACH_THIS_SWITCH_IS_THE_ONLY" /* 用户可在“计划 → 教练”进入。只有此处的开关能为所有用户关闭教练。 */))
        : `${doneCount} of ${flags.length} steps done. Finish the open step and the next one unfolds.`}
    </div>

    {d.enabled && <>
      {/* ---------- provider ---------- */}
      <Step n={num()} title={t("PROVIDER" /* 提供商 */)} hint={meta.label || (t("WHICH_AI_ANSWERS_THE_COACH" /* 选择提供回答的 AI 服务 */))} done={step1Done} {...stepAt()}>
        <div className="adm-hint">{t("PICK_WHO_ANSWERS_A_KEY_OR_TOKEN_YOU_SAVE_STAYS_WITH_ITS" /* 选择服务商。已保存的密钥或令牌与服务商分别关联，切换时无需重复填写。 */)}</div>
        {groups.map(g => !!g.items.length && <div key={g.title} className="adm-group">
          <div className="adm-group-t">{g.title}</div>
          <div className="adm-chips">
            {g.items.map(p => <button key={p.id} className={'chip' + (p.id === d.provider ? ' on' : '')} disabled={busy}
              onClick={() => { setTestResult(null); patch({ provider: p.id }) }}>
              {p.label}{p.connected && <span className="adm-chip-key">{t("KEY_SAVED" /* 密钥已保存 */)}</span>}
            </button>)}
          </div>
          <div className="adm-hint" style={{ margin: '6px 0 0' }}>{g.hint}</div>
        </div>)}
      </Step>

      {/* ---------- endpoint (compatible only) ---------- */}
      {needsEndpoint && <Step n={num()} title={t("ENDPOINT" /* 端点 */)} hint={d.baseUrl || (t("WHERE_THE_MODEL_RUNS" /* 模型运行地址 */))} done={step2Done} {...stepAt()}>
        <div className="adm-hint">{t("THE_ADDRESS_OF_ANY_SERVER_THAT_SPEAKS_OPENAI_S_CHAT_API" /* 支持 OpenAI 聊天 API 格式的服务地址： */)} <b>{t("OLLAMA" /* 术语：Ollama */)}</b>, <b>{t("LM_STUDIO" /* 术语：LM Studio */)}</b>, <b>{t("VLLM" /* 术语：vLLM */)}</b>, <b>{t("OPENROUTER" /* 术语：OpenRouter */)}</b>{t("OR_A_GATEWAY_OF_YOUR_OWN_THE_BASE_AS_YOUR_PROVIDER_DOCUMENTS" /* 或自建网关。按服务商文档填写基础地址，可包含版本路径（ */)}<code>{t("LABEL_V" /* 术语：/v1 */)}</code>, <code>{t("LABEL_V_A" /* 术语：/v4 */)}</code>{t("AND_NO_KEY_IN_THE_URL" /* ），请勿在地址中填写密钥。 */)}</div>
        <div className="adm-field">
          <label>{t("BASE_URL" /* 基础地址 */)}</label>
          <TextField key={d.baseUrl || ''} defaultValue={d.baseUrl || ''} placeholder="http://ollama:11434  or  https://openrouter.ai/api" inputMode="url" autoCapitalize="none" autoCorrect="off"
            onBlur={e => e.target.value !== (d.baseUrl || '') && patch({ baseUrl: e.target.value })} />
        </div>
        <div className="adm-hint" style={{ margin: 0 }}>{t("THE_HOST_IS_WRITTEN_TO_THE_JOB_LOG_SO_YOU_CAN_ALWAYS" /* 请求主机会写入任务日志，便于确认数据发送到哪里。 */)}</div>
        <div className="adm-field">
          <label>{t("EXTRA_HEADERS_OPTIONAL" /* 附加请求头（可选） */)}</label>
          <TextArea key={headersToText(d.headers)} defaultValue={headersToText(d.headers)} placeholder={'x-opencode-session: 550e8400-…'} autoCapitalize="none" autoCorrect="off" rows={2}
            onBlur={e => {
              const cur = headersToText(d.headers)
              if (e.target.value === cur) return
              const p = parseHeadersText(e.target.value)
              if (p.error) { toast(p.error); e.target.value = cur; return }
              patch({ headers: p.headers })
            }} />
        </div>
        <div className="adm-hint" style={{ margin: 0 }}>{t("ONE" /* 每行填写一组 */)} <code>{t("NAME_VALUE" /* 名称: 值 */)}</code> {t("PER_LINE_SENT_WITH_EVERY_REQUEST_TO_THIS_ENDPOINT_FOR_GATEWAYS_THAT" /* ，每次请求此地址时都会附带，适用于需要路由请求头的网关。不能设置 */)} <code>{t("AUTHORIZATION" /* 术语：Authorization */)}</code> {t("OR" /* 或 */)} <code>{t("CONTENT_TYPE" /* 术语：Content-Type */)}</code> {t("THOSE_ARE_REFUSED" /* ，这两种请求头会被拒绝。 */)}</div>
      </Step>}

      {/* ---------- credential ---------- */}
      {hasCredentialStep && <Step n={num()} title={t("CREDENTIAL" /* 访问凭据 */)} hint={credentialHint(d.auth, meta)} done={step3Done} {...stepAt()}>
        <div className="row" style={{ gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
          <CredentialPill auth={d.auth} />
        </div>
        {authState === 'connected' ? <>
          <div className="adm-hint">{t("ADMIN_CONNECTED_VIA" /* 已连接{0}，使用 {1}{2}。密钥加密保存在服务器上，之后无法再次查看。 */,
            d.auth.account ? t("ADMIN_ACCOUNT_AS" /* 账号：{0} */, d.auth.account) : '',
            credentialLabel(d.auth.type),
            d.auth.connectedAt ? ' · ' + t("ADMIN_KEY_ADDED" /* 添加于 {0} */, rel(d.auth.connectedAt)) : '')}</div>
          <div className="adm-actions">
            {meta.apiKey && <Button size="sm" variant="tinted" icon="lock" disabled={busy}
              onClick={() => openSheet(close => <ApiKeySheet close={close} onDone={load} label={meta.label} placeholder={meta.keyPlaceholder} optional={meta.keyOptional} />)}>{t("REPLACE_KEY" /* 替换密钥 */)}</Button>}
            {/* The key is encrypted at rest and never shown again, so this is the one action on the
                card that cannot be walked back. Every other irreversible action in the app asks first;
                until 2026-09-22 this one did not. */}
            <Button size="sm" danger disabled={busy} onClick={() => confirmSheet({
              title: (t("REMOVE_THIS_CREDENTIAL" /* 移除此凭据？ */)),
              message: (t("THE_COACH_STOPS_WORKING_FOR_EVERYONE_ON_THIS_INSTANCE_UNTIL_A_NEW" /* 移除后，所有用户均无法使用教练，直到添加新密钥。已保存的密钥无法恢复。 */)),
              confirmText: (t("REMOVE" /* 移除 */)), danger: true, onConfirm: disconnect,
            })}>{t("REMOVE" /* 移除 */)}</Button>
          </div>
        </> : <>
          {authState === 'unreadable' && <div className="adm-hint" style={{ color: 'var(--red)' }}> {t("THE_STORED_CREDENTIAL_CAN_T_BE_DECRYPTED_THIS_USUALLY_MEANS" /* 无法解密已保存的凭据。通常是因为恢复了 */)} <code>{t("DATA_A" /* 术语：./data */)}</code> {t("WAS_RESTORED_WITHOUT_ITS" /* 目录，却没有恢复其中的 */)} <code>{t("SECRET" /* 术语：secret */)}</code> {t("FILE_ADD_THE_KEY_AGAIN_TO_FIX_IT" /* 文件。请重新添加密钥。 */)} </div>}
          {authState === 'optional' && <div className="adm-hint">{t("THIS_ENDPOINT_WORKS_WITHOUT_A_KEY_ADD_ONE_ONLY_IF_YOUR_SERVER" /* 此地址不要求密钥。仅在服务器要求时填写，例如 OpenRouter；局域网内的本地模型通常无需密钥。 */)}</div>}
          {authState === 'none' && <div className="adm-hint">{meta.setupToken
            ? (t("PASTE_EITHER_A_CLAUDE_CODE_SETUP_TOKEN_YOUR_SUBSCRIPTION_OR_AN_ANTHROPIC" /* 可粘贴 Claude Code setup token（使用订阅），或 Anthropic API 密钥（按量计费）。 */))
            : (t("PASTE_AN_API_KEY_FROM_THE_PROVIDER_S_CONSOLE_IT_IS_STORED" /* 粘贴从服务商控制台获取的 API 密钥。密钥加密保存在服务器上，仅在执行请求时发送给服务商。 */))}</div>}
          <div className="adm-actions">
            {meta.setupToken && <Button size="sm" variant="primary" icon="key" disabled={busy}
              onClick={() => openSheet(close => <SetupTokenSheet close={close} onDone={load} label={meta.label} />)}>{t("ADD_CLAUDE_CODE_TOKEN" /* 添加 Claude Code 令牌 */)}</Button>}
            {meta.apiKey && <Button size="sm" variant={meta.setupToken ? undefined : 'primary'} icon="lock" disabled={busy}
              onClick={() => openSheet(close => <ApiKeySheet close={close} onDone={load} label={meta.label} placeholder={meta.keyPlaceholder} optional={meta.keyOptional} />)}>
              {meta.keyOptional ? (t("ADD_API_KEY_OPTIONAL" /* 添加 API 密钥（可选） */)) : (t("ADD_API_KEY" /* 添加 API 密钥 */))}</Button>}
          </div>
        </>}
      </Step>}

      {/* ---------- model ---------- */}
      <Step n={num()} title={t("MODEL" /* 模型 */)} hint={d.model || (meta.defaultModel ? t("ADMIN_DEFAULT" /* 默认：{0} */, meta.defaultModel) : (t("NOT_CHOSEN_YET" /* 尚未选择 */)))} done={step4Done} {...stepAt()}>
        <div className="adm-hint">{meta.http
          ? (t("WHICH_MODEL_THE_PROVIDER_SHOULD_USE_LIST_MODELS_ASKS_THE_PROVIDER_FOR" /* 选择服务商使用的模型。“获取模型列表”会向服务商查询当前可用模型。 */))
          : (t("OPTIONAL_LEAVE_IT_EMPTY_TO_USE_THE_RUNTIME_S_OWN_DEFAULT" /* 可选。留空使用运行环境的默认模型。 */))}</div>
        <div className="adm-field">
          <label>{t("MODEL" /* 模型 */)}</label>
          {models && models.length
            ? <select className="adm-select" value={chosenModel} disabled={busy} onChange={e => patch({ model: e.target.value })}>
              <option value="">{meta.defaultModel ? t("ADMIN_DEFAULT_MODEL" /* 默认（{0}） */, meta.defaultModel) : (t("PICK_A_MODEL_A" /* 选择模型… */))}</option>
              {chosenModel && !models.includes(chosenModel) && <option value={chosenModel}>{chosenModel} {t("NOT_IN_THE_LIST" /* （不在列表中） */)}</option>}
              {models.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
            : <TextField key={d.provider} defaultValue={chosenModel} placeholder={meta.defaultModel ? t("ADMIN_DEFAULT_MODEL_PLACEHOLDER" /* 默认：{0} */, meta.defaultModel) : needsEndpoint ? (t("E_G_QWEN_B_OR_PRESS_LIST_MODELS" /* 例如 qwen2.5:3b，或点击“获取模型列表” */)) : (t("RUNTIME_DEFAULT" /* （运行环境默认模型） */))}
              onBlur={e => e.target.value !== chosenModel && patch({ model: e.target.value })} />}
        </div>
        {meta.http && <div className="adm-actions">
          <Button size="sm" variant="tinted" icon="reset" disabled={busy} onClick={loadModels}>{models ? (t("REFRESH_LIST" /* 刷新列表 */)) : (t("LIST_MODELS" /* 列出模型 */))}</Button>
          {models && models.length ? <span className="dim small" style={{ alignSelf: 'center' }}>{t("ADMIN_MODEL_COUNT_AVAILABLE" /* 服务商提供 {0} 个模型 */, models.length)}</span> : null}
        </div>}
      </Step>

      {/* ---------- test ---------- */}
      <Step n={num()} title={t("TEST" /* 测试 */)} hint={step5Done ? t("PASSED" /* 通过 */) : (t("ONE_REAL_ROUND_TRIP_NO_USER_DATA" /* 发送一次真实请求，不包含用户数据 */))} done={step5Done} {...stepAt()} forceOpen={!!testResult}>
        <div className="adm-hint">{t("SENDS_ONE_TINY_QUESTION_TO_THE_PROVIDER_AND_CHECKS_THE_ANSWER_NO" /* 向服务商发送一个简短问题并检查回答，不涉及训练数据。修改上述配置后请重新测试。 */)}</div>
        <div className="adm-actions">
          <Button size="sm" variant="primary" icon="check" disabled={busy || !authed || !hasEndpoint} onClick={test}>{t("TEST_THE_COACH" /* 测试教练连接 */)}</Button>
        </div>
        {(!authed || !hasEndpoint) && <div className="adm-hint" style={{ margin: '6px 0 0' }}>
          {!hasEndpoint ? (t("FINISH_THE_ENDPOINT_STEP_FIRST" /* 请先完成服务地址设置。 */)) : (t("FINISH_THE_CREDENTIAL_STEP_FIRST" /* 请先完成凭据设置。 */))}
        </div>}
        {testResult && <div className={'adm-result ' + (testResult.pending ? '' : testResult.ok ? 'ok' : 'bad')}>
          {testResult.pending ? (t("ASKING_THE_PROVIDER" /* 正在请求服务商… */))
            : testResult.ok ? <><b>{t("PASSED" /* 通过 */)}</b>{testResult.version ? t("ADMIN_PROVIDER_STATUS" /* 服务商：{0} */, testResult.version) : (t("THE_PROVIDER_ANSWERED_AS_EXPECTED" /* 服务商已正常响应。 */))}</>
              : <><b>{t("FAILED" /* 失败 */)}</b>{testResult.error || (t("NO_ANSWER_FROM_THE_PROVIDER" /* 服务商未响应。 */))}</>}
        </div>}
        <div className="adm-kv" style={{ marginTop: 10 }}>
          <span className="k">{t("RUNTIME" /* 运行环境 */)}</span>
          <span className="v">{d.runtime.ok ? <span className="adm-pill ok">{t("READY_A" /* 已就绪 */)}</span> : <span className="adm-pill bad">{t("MISSING" /* 缺失 */)}</span>}{d.runtime.version ? <div className="dim small">{d.runtime.version}</div> : null}{!d.runtime.ok && d.runtime.error ? <div className="small" style={{ color: 'var(--red)' }}>{d.runtime.error}</div> : null}</span>
        </div>
      </Step>

      {/* ---------- advanced ---------- */}
      <details className="adm-fold">
        <summary>{t("ADVANCED" /* 高级设置 */)} <Icon name="chevronRight" className="chev" /></summary>
        <div className="adm-fold-b">
          <div className="adm-group-t">{t("LIMITS" /* 限制 */)}</div>
          <div className="adm-hint">{t("HOW_MANY_COACH_RUNS_ARE_ALLOWED_PER_DAY_EVERY_RUN_IS_ONE" /* 限制每天可调用教练的次数。每次调用会向上述服务账号发送一次请求，0 表示不限次数。 */)}</div>
          <div className="adm-kv"><span className="k">{t("PER_USER_PER_DAY" /* 每位用户每天 */)}</span>
            <span className="v"><input className="num" type="number" min="0" max="200" defaultValue={d.caps.perProfileDaily} disabled={busy}
              onBlur={capBlur('perProfileDaily')} /></span></div>
          <div className="adm-kv"><span className="k">{t("WHOLE_INSTANCE_PER_DAY" /* 整个服务器每天 */)}</span>
            <span className="v"><input className="num" type="number" min="0" max="5000" defaultValue={d.caps.instanceDaily} disabled={busy}
              onBlur={capBlur('instanceDaily')} /></span></div>
          <div className="adm-hint" style={{ marginTop: 10 }}>{t("HOW_LONG_A_CHAT_MESSAGE_REFINEMENT_OR_REVIEW_NOTE_CAN_BE_THE" /* 限制聊天消息、修改要求和复盘备注的长度，输入框和服务器均会检查。 */)}</div>
          <div className="adm-kv"><span className="k">{t("MAX_MESSAGE_LENGTH" /* 消息字数上限 */)}</span>
            <span className="v"><input className="num" type="number" min="200" max="4000" defaultValue={d.maxMessageLen} disabled={busy}
              onBlur={e => +e.target.value !== d.maxMessageLen && patch({ maxMessageLen: +e.target.value })} /></span></div>
          <div className="adm-hint" style={{ marginTop: 10 }}>{t("THE_CEILING_ON_A_SINGLE_PROVIDER_ANSWER_REASONING_MODELS_DEEPSEEK_STYLE_ENDPOINTS" /* 单次回答的输出 token 上限。推理模型会将内部推理计入此额度，因此即使计划较短，也可能因达到输出上限而中断。出现此情况可适当提高，但不能超过模型支持的上限。 */)}</div>
          <div className="adm-kv"><span className="k">{t("MAX_OUTPUT_TOKENS" /* 输出 token 上限 */)}</span>
            <span className="v"><input className="num" type="number" min="1024" max="65536" defaultValue={d.maxOutputTokens} disabled={busy}
              onBlur={e => +e.target.value !== d.maxOutputTokens && patch({ maxOutputTokens: +e.target.value })} /></span></div>

          <div className="adm-group-t" style={{ marginTop: 14 }}>{t("COMPARE_WITH_OTHERS" /* 匿名训练对比 */)}</div>
          <div className="row between" style={{ gap: 12, alignItems: 'flex-start' }}>
            <div className="adm-hint" style={{ margin: 0 }}>
              <b>{t("LET_PEOPLE_COMPARE_WITH_EACH_OTHER" /* 允许用户比较训练表现。 */)}</b> {t("ANONYMOUS_MEDIANS_ESTIMATED_RM_SESSIONS_PER_WEEK_ACROSS_PROFILES_THAT_OPT_IN" /* 仅比较自愿参与用户的估算 1RM、每周训练次数等汇总中位数。至少 3 人参与后才会显示结果；用户需在教练聊天中主动开启，未参与者无法查看。 */)} </div>
            <Switch checked={!!d.community} disabled={busy} onChange={v => patch({ community: v })} />
          </div>

          <div className="adm-group-t" style={{ marginTop: 14 }}>{t("WHOSE_ACCOUNT_PAYS" /* 费用归属 */)}</div>
          <div className="adm-hint">{d.authMode === 'profile'
            ? (t("EACH_PROFILE_SIGNS_IN_WITH_THEIR_OWN_ACCOUNT" /* 每位用户使用自己的服务账号登录。 */))
            : d.auth?.type === 'apikey' || meta.http
              ? (t("ONE_API_KEY_FOR_THE_WHOLE_INSTANCE_EVERY_PROFILE_MAY_USE_THE" /* 整个服务器共用一个 API 密钥，所有用户均可使用教练；可通过上述每日次数限制控制费用。 */))
              : d.boundUid
                ? (t("ONE_PERSONAL_ACCOUNT_ALREADY_IN_USE_BY_ONE_PROFILE_EVERY_OTHER_PROFILE" /* 个人账号已绑定一位用户，其他用户无法使用，以免占用他人的订阅额度。 */))
                : (t("ONE_PERSONAL_ACCOUNT_THE_FIRST_PROFILE_TO_USE_IT_BECOMES_THE_ONLY" /* 个人账号将绑定首次使用的用户，之后仅该用户可用。如需供所有用户使用，请改用 API 密钥。 */))}</div>

          <div className="adm-group-t" style={{ marginTop: 14 }}>{t("ISOLATION" /* 运行隔离 */)}</div>
          <div className="adm-hint">{d.unprivileged && !d.unprivileged.ok
            ? <span style={{ color: 'var(--red)' }}>{t("JOBS_ARE_BLOCKED" /* 任务已阻止： */)} {d.unprivileged.why}{t("NOTHING_RUNS_UNTIL_THIS_IS_FIXED" /* 。解决此问题前不会执行任务。 */)}</span>
            : d.unprivileged?.dropped
              ? (t("JOBS_RUN_AS_A_SEPARATE_UNPRIVILEGED_USER_THAT_CANNOT_READ_YOUR_DATA" /* 任务以独立的低权限用户运行，无法读取数据目录或密钥。 */))
              : d.unprivileged?.why?.includes('no child process')
                ? (t("NOT_NEEDED_FOR_THIS_PROVIDER_IT_MAKES_AN_HTTPS_REQUEST_AND_STARTS" /* 此服务商无需进程隔离，仅发送 HTTPS 请求，不在服务器上启动程序。 */))
                : (t("JOBS_RUN_WITH_THE_SERVER_S_OWN_USER_ON_THIS_HOST_NO" /* 任务使用服务器当前用户运行，未切换至独立的低权限用户。 */))}</div>
        </div>
      </details>

      {/* ---------- activity ---------- */}
      <details className="adm-fold">
        <summary>{t("ACTIVITY" /* 运行记录 */)} <Icon name="chevronRight" className="chev" /></summary>
        <div className="adm-fold-b">
          <div className="tiles" style={{ textAlign: 'start', marginBottom: 10 }}>
            <div className="tile"><div className="l">{t("JOBS_TODAY" /* 今日任务 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{d.jobsToday}</div></div>
            <div className="tile"><div className="l">{t("LAST_SUCCESS" /* 最近成功 */)}</div><div className="v" style={{ fontSize: '.85rem' }}>{rel(d.lastSuccess?.at)}</div></div>
          </div>
          {d.lastError && <>
            <div className="adm-group-t">{t("LAST_FAILURE" /* 最近失败 */)}</div>
            <div className="adm-result bad" style={{ marginTop: 0, marginBottom: 10 }}>
              <b>{failureTitle(d.lastError.errorClass)}</b>
              {d.lastError.detail ? <span className="small">{d.lastError.detail}</span> : null}
              <div className="dim" style={{ fontSize: '.72rem', marginTop: 4 }}>{rel(d.lastError.at)}</div>
            </div>
          </>}
          <div className="adm-group-t">{t("RECENT_JOBS" /* 最近任务 */)}</div>
          {d.recent?.length ? <div className="adm-log">
            {d.recent.slice(0, 10).map((e, i) => <div key={i} className="adm-log-row">
              <span>{e.kind === 'create' ? (t("PLAN" /* 计划 */)) : (t("COACH_REVIEW" /* 训练评估 */))}{e.trigger === 'scheduled' ? ' · ' + t("ADMIN_SCHEDULED" /* 定时任务 */) : ''} · <span style={{ color: e.outcome === 'failed' ? 'var(--red)' : e.outcome === 'ready' ? 'var(--acc)' : 'var(--label-2)' }}>{translateValue(e.outcome)}</span>{e.ms ? ' · ' + t("DURATION_SECONDS_SHORT" /* {0} 秒 */, Math.round(e.ms / 1000)) : ''}</span>
              <span className="when">{rel(e.at)}</span>
            </div>)}
          </div> : <div className="adm-empty">{t("NO_JOBS_YET" /* 暂无任务。 */)}</div>}
          <div className="adm-hint" style={{ margin: '8px 0 0' }}>{t("COUNTS_AND_OUTCOMES_ONLY_WHAT_PEOPLE_ASKED_THE_COACH_AND_WHAT_IT" /* 仅显示次数和结果，不展示用户向教练提出的问题或教练的回答。 */)}</div>
        </div>
      </details>
    </>}
  </div>
}

/* ---------------------------------- pieces ---------------------------------- */

function Step({ n, title, hint, done, open, forceOpen, children }) {
  // `key` remounts the <details> when the wizard advances, so the next step unfolds itself.
  return <details className={'adm-step ' + (done ? 'done' : 'todo')} open={open || forceOpen}>
    <summary>
      <span className="adm-num">{done ? <Icon name="check" /> : n}</span>
      <span className="adm-step-t"><b>{title}</b><span>{hint}</span></span>
      <Icon name="chevronRight" className="chev" />
    </summary>
    <div className="adm-step-b">{children}</div>
  </details>
}

function CredentialPill({ auth }) {
  const s = auth?.state
  if (s === 'connected') return <span className="adm-pill ok">{t("CONNECTED_A" /* 已连接 */)}{auth.account ? ' · ' + auth.account : ''}</span>
  if (s === 'not-required') return <span className="adm-pill">{t("NOT_NEEDED" /* 无需配置 */)}</span>
  if (s === 'optional') return <span className="adm-pill">{t("OPTIONAL_NONE_SAVED" /* 可选，尚未保存 */)}</span>
  if (s === 'unreadable') return <span className="adm-pill bad">{t("CAN_T_BE_READ" /* 无法读取 */)}</span>
  return <span className="adm-pill warn">{t("NEEDED" /* 需要配置 */)}</span>
}

const credentialHint = (auth, meta) => {
  const s = auth?.state
  if (s === 'connected') return auth.account ? t("ADMIN_CONNECTED_AS" /* 已连接账号 {0} */, auth.account) : t("CONNECTED" /* 已连接 */)
  if (s === 'not-required') return (t("NOT_NEEDED_A" /* 无需配置 */))
  if (s === 'optional') return (t("OPTIONAL_FOR_THIS_ENDPOINT" /* 此地址可不填 */))
  if (s === 'unreadable') return (t("STORED_KEY_CAN_T_BE_READ_ADD_IT_AGAIN" /* 无法读取已保存的密钥，请重新添加 */))
  return meta.setupToken ? (t("TOKEN_OR_API_KEY_NEEDED" /* 需要令牌或 API 密钥 */)) : (t("API_KEY_NEEDED" /* 需要 API 密钥 */))
}

const credentialLabel = type => ({
  'cli-token': (t("CLAUDE_CODE_SETUP_TOKEN" /* 术语：Claude Code setup token */)), 'chatgpt-cli': (t("CHATGPT_CLI_LOGIN" /* ChatGPT CLI 登录 */)), oauth: (t("LEGACY_TOKEN" /* 旧版令牌 */)), apikey: (t("API_KEY" /* API 密钥 */))
}[type] || (t("CREDENTIAL_A" /* 凭据 */)))

// The failure classes jobs.js emits, in words an operator can act on.
const failureTitle = cls => ({
  timeout: (t("THE_PROVIDER_TOOK_LONGER_THAN_THE_JOB_BUDGET_COACH_JOB_TIMEOUT_MS" /* 服务商响应超时，已超过任务时限（COACH_JOB_TIMEOUT_MS，默认 5 分钟） */)),
  missing: (t("THE_PROVIDER_RUNTIME_OR_KEY_IS_MISSING" /* 缺少服务商运行环境或密钥 */)),
  auth: (t("THE_PROVIDER_REJECTED_THE_CREDENTIAL" /* 服务商拒绝了访问凭据 */)),
  provider: (t("THE_PROVIDER_RETURNED_AN_ERROR" /* 服务商返回错误 */)),
  unusable: (t("THE_MODEL_ANSWERED_BUT_NOT_IN_A_SHAPE_THE_APP_COULD_USE" /* 模型已回答，但格式无法使用 */)),
  restart: (t("THE_SERVER_RESTARTED_WHILE_A_JOB_WAS_RUNNING" /* 执行任务期间服务器重启 */)),
  nostate: (t("THE_USER_S_TRAINING_DATA_COULD_NOT_BE_READ" /* 无法读取用户训练数据 */)),
  off: (t("THE_COACH_WAS_OFF_WHEN_THE_JOB_RAN" /* 任务执行时教练已关闭 */)),
  toolarge: (t("THE_USER_S_TRAINING_DATA_MADE_A_REQUEST_TOO_LARGE_TO_SEND" /* 用户训练数据超过请求大小限制，未向服务商发送请求 */)),
  internal: (t("SOMETHING_WENT_WRONG_ON_THE_SERVER_A" /* 服务器内部错误 */))
}[cls] || cls || (t("FAILED" /* 失败 */)))

/* ------------------------------- setup token -------------------------------- */

function SetupTokenSheet({ close, onDone, label }) {
  const toast = useUI(s => s.toast)
  const [token, setToken] = useState('')
  // Which account this token belongs to. Optional, and stored as a plain label — it is what the
  // admin card and the user's Coach screen both show when they name whose account is spent.
  const [account, setAccount] = useState('')
  const [busy, setBusy] = useState(false)

  const save = async () => {
    setBusy(true)
    try {
      const r = await api('/api/admin/coach/connect', { method: 'POST', body: JSON.stringify({ type: 'cli-token', token: token.trim(), account: account.trim() }) })
      setToken('')
      toast(r.test?.ok ? 'Connected ✅' : (t("TOKEN_SAVED" /* 令牌已保存 */)))
      close(); onDone()
    } catch (e) { toast(e.message); setBusy(false) }
  }

  return <>
    <h3>{t("CONNECT" /* 连接 */)} {label}</h3>
    <div className="muted small" style={{ lineHeight: 1.5, marginBottom: 12 }}> {t("ON_A_TRUSTED_COMPUTER_WHERE_YOU_USE_CLAUDE_CODE_RUN" /* 在使用 Claude Code 的可信电脑上运行 */)} <code>{t("CLAUDE_SETUP_TOKEN" /* 术语：claude setup-token */)}</code>{t("COMPLETE_ITS_NORMAL_BROWSER_SIGN_IN_THEN_PASTE_THE_TOKEN_IT_PRINTS" /* ，按提示在浏览器完成登录，然后将输出的令牌粘贴到此处。本 App 不发起或处理 Claude 的授权流程。 */)} </div>
    <TextField value={token} autoFocus type="password" placeholder={t("PASTE_SETUP_TOKEN" /* 粘贴 setup token */)} onChange={e => setToken(e.target.value)} />
    <div style={{ height: 8 }} />
    <TextField value={account} placeholder={t("WHOSE_ACCOUNT_IS_THIS_E_G_YOU_EXAMPLE_COM" /* 账号归属（例如 you@example.com） */)} onChange={e => setAccount(e.target.value)} />
    <div style={{ height: 12 }} />
    <Button variant="primary" disabled={busy || !token.trim()} onClick={save}>{t("SAVE_TOKEN" /* 保存令牌 */)}</Button>
    <div style={{ height: 8 }} />
  </>
}

function ApiKeySheet({ close, onDone, label, placeholder, optional }) {
  const toast = useUI(s => s.toast)
  const [key, setKey] = useState('')
  const [busy, setBusy] = useState(false)
  const save = async () => {
    setBusy(true)
    try {
      const r = await api('/api/admin/coach/connect', { method: 'POST', body: JSON.stringify({ type: 'apikey', token: key.trim() }) })
      toast(r.test?.ok ? (t("KEY_SAVED_A" /* 密钥已保存 ✅ */)) : (t("KEY_SAVED_B" /* 密钥已保存 */)))
      close(); onDone()
    } catch (e) { toast(e.message); setBusy(false) }
  }
  return <>
    <h3>{label} {t("API_KEY" /* API 密钥 */)}</h3>
    <div className="muted small" style={{ lineHeight: 1.5, marginBottom: 12 }}> {t("STORED_ENCRYPTED_ON_THIS_SERVER_AND_SENT_TO_THE_PROVIDER_ONLY_WHILE" /* 密钥加密保存在此服务器上，仅在执行请求时发送给服务商，之后无法再次查看 */)}{optional ? (t("FOR_AN_ENDPOINT_THAT_TAKES_NO_KEY_YOU_CAN_LEAVE_THIS_EMPTY" /* 。如果此地址无需密钥，可留空并关闭此窗口。 */)) : '.'}
    </div>
    <TextField value={key} autoFocus type="password" placeholder={placeholder || 'sk-…'} autoCapitalize="none" autoCorrect="off" onChange={e => setKey(e.target.value)} />
    <div style={{ height: 12 }} />
    <Button variant="primary" disabled={busy || !key.trim()} onClick={save}>{t("SAVE_KEY" /* 保存密钥 */)}</Button>
    <div style={{ height: 8 }} />
  </>
}
