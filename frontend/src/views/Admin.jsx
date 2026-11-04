import { t, dateLocale } from '../lib/i18n.js'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { api } from '../lib/api.js'
import { fmtDate, fmtNum, fmtVol, fmtDur, fmtAgo } from '../lib/format.js'
import { auditCat, auditLine, fmtWhen } from '../lib/audit.js'
import { workoutVolume, setsDone } from '../lib/history.js'
import { confirmSheet } from '../sheets.jsx'
import Icon from '../components/Icon.jsx'
import { Button } from '../components/ui.jsx'
import AdminCoach from './AdminCoach.jsx'
import '../admin.css'

// Admin-only operator dashboard (owner passkey + admin flag; guarded again server-side).
// 管理后台与用户页面使用同一套 JSON 翻译。
// One page of cards, each opening with a sentence that says what it is for. An operator who
// looks at this twice a year should not have to remember what "synced 3d ago" or an invite
// code means.

const rel = ts => ts ? fmtAgo(ts) : t("NEVER" /* 从未 */)
const dur = fmtDur

// The one time the reset code is visible. Locked, so a tap beside the sheet cannot lose it
// before it has been copied or written down.
function ResetCodeSheet({ name, email, code, expires, close }) {
  const toast = useUI(s => s.toast)
  const copy = () => { navigator.clipboard?.writeText(code).catch(() => {}); toast((t("COPIED" /* 已复制 */))) }
  return <>
    <h3>{t("ADMIN_RESET_CODE_FOR" /* {0} 的密码重置码 */, name)}</h3>
    <div className="adm-lead">{t("ADMIN_RESET_INSTRUCTIONS" /* 将此码交给用户。请选择“使用密码登录”→“已有管理员提供的重置码？”，填写 {0}、重置码和新密码。此码仅可使用一次，有效期至 {1}，关闭后无法再次查看。 */,
      email ? t("ADMIN_LOGIN_NAME_OR_EMAIL" /* 用户名 {0}（或登录邮箱 {1}） */, name, email) : name,
      new Date(expires).toLocaleString(dateLocale()))}</div>
    <button className="adm-code" style={{ fontSize: 22, width: '100%', padding: '14px 0' }} onClick={copy} aria-label={t("COPY_CODE" /* 复制重置码 */)}>{code}</button>
    <div style={{ height: 12 }} />
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}

function UserDetail({ id, onChanged, close }) {
  const [d, setD] = useState(null)
  const toast = useUI(s => s.toast)
  const openSheet = useUI(s => s.openSheet)
  useEffect(() => { api('/api/admin/user?id=' + encodeURIComponent(id)).then(setD).catch(e => toast(e.message)) }, [id])
  if (!d) return <div className="muted small">{t("LOADING" /* 加载中… */)}</div>
  const u = d.user
  // The document comes straight off the user's state file. PUT /api/data drops null and
  // shapeless entries now, but a file written before it did still answers with them, and this
  // sheet renders outside the route's ErrorBoundary: one throw here blanked the whole app and
  // left exactly this account un-disableable. setsDone/workoutVolume walk entries and sets, so
  // an entry that lacks either has nothing to show and is skipped rather than drawn.
  const workouts = (d.workouts || []).filter(w => w && Array.isArray(w.entries) && w.entries.every(e => e && Array.isArray(e.sets)))
  // Their whole record as the admin API already returns it — the export the delete sheet offers.
  const exportUser = () => {
    const blob = new Blob([JSON.stringify(d, null, 2)], { type: 'application/json' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `opengym-${u.name.replace(/[^a-zA-Z0-9_-]+/g, '-').toLowerCase()}-${u.id}.json`
    document.body.appendChild(a); a.click(); a.remove()
    setTimeout(() => URL.revokeObjectURL(a.href), 1000)
  }
  const doDelete = () => {
    api('/api/admin/user/delete', { method: 'POST', body: JSON.stringify({ id: u.id }) })
      .then(() => { toast((t("ACCOUNT_DELETED" /* 账号已删除 */))); onChanged(); close() })
      .catch(e => toast(e.message))
  }
  const setDisabled = disabled => {
    api('/api/admin/user/disable', { method: 'POST', body: JSON.stringify({ id: u.id, disabled }) })
      .then(() => { toast(disabled ? (t("USER_DISABLED" /* 账号已停用 */)) : (t("USER_ENABLED" /* 账号已启用 */))); onChanged(); close() })
      .catch(e => toast(e.message))
  }
  // Password sign-in (#118): the server only sends `password` when the instance offers it. The
  // code comes back once, is shown once, and is never stored anywhere but as a hash.
  const pwInstance = typeof u.password === 'boolean'
  const resetPassword = () => confirmSheet({
    title: t("ADMIN_RESET_PASSWORD_TITLE" /* 重置 {0} 的密码？ */, u.name),
    message: (t("YOU_GET_A_ONE_TIME_CODE_TO_HAND_THEM_THEIR_CURRENT_PASSWORD" /* 将生成一个有效期为 24 小时的一次性重置码，请转交给用户。原密码立即失效，所有设备将退出登录，通行密钥仍可使用。用户可在“使用密码登录”页面凭重置码设置新密码。重置码只显示一次。 */)),
    confirmText: (t("CREATE_RESET_CODE" /* 生成重置码 */)),
    danger: true,
    onConfirm: () => api('/api/admin/user/password-reset', { method: 'POST', body: JSON.stringify({ id: u.id }) })
      .then(r => { onChanged(); close(); openSheet(done => <ResetCodeSheet name={r.name} email={u.email} code={r.code} expires={r.expires} close={done} />, { locked: true }) })
      .catch(e => toast(e.message)),
  })
  return <>
    <h3 className="capitalize">{u.name}</h3>
    <div className="row" style={{ gap: 6, flexWrap: 'wrap', margin: '8px 0 12px' }}>
      {u.admin && <span className="adm-pill acc">{t("ADMIN" /* 管理员 */)}</span>}
      {u.disabled && <span className="adm-pill bad">{t("DISABLED" /* 已停用 */)}</span>}
      {u.invitedBy && <span className="adm-pill">{t("INVITE" /* 邀请码 */)} {u.invitedBy}</span>}
      {u.password && <span className="adm-pill">{t("PASSWORD_A" /* 密码 */)}</span>}
      {/* The sign-in e-mail (password instances only): shown to admins and nobody else. */}
      {u.email && <span className="adm-pill" title={t("SIGN_IN_E_MAIL_A" /* 登录邮箱 */)}>{u.email}</span>}
      {u.resetUntil && <span className="adm-pill acc">{t("RESET_CODE_UNTIL" /* 重置码有效期至 */)} {new Date(u.resetUntil).toLocaleString(dateLocale())}</span>}
      <span className="adm-pill">{t("JOINED" /* 加入时间 */)} {u.created ? fmtDate(u.created.slice(0, 10)) : '–'}</span>
    </div>
    <div className="tiles" style={{ textAlign: 'start' }}>
      <div className="tile"><div className="l">{t("WORKOUTS" /* 训练次数 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{workouts.length}</div></div>
      <div className="tile"><div className="l">{t("WEIGH_INS" /* 称重记录 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{d.bodyweight.length}</div></div>
      <div className="tile"><div className="l">{t("MEASUREMENTS" /* 身体围度 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{(d.measurements || []).length}</div></div>
      <div className="tile"><div className="l">{t("ROUTINES" /* 训练计划 */)}</div><div className="v" style={{ fontSize: '1.1rem' }}>{d.routines.length}</div></div>
      <div className="tile"><div className="l">{t("LAST_SYNC" /* 上次同步 */)}</div><div className="v" style={{ fontSize: '.95rem' }}>{rel(d.lastSync)}</div></div>
    </div>
    {!u.admin && <>
      <button className={'btn ' + (u.disabled ? 'primary' : 'danger')} style={{ margin: '12px 0 4px' }}
        onClick={() => u.disabled ? setDisabled(false)
          : confirmSheet({ title: t("ADMIN_DISABLE_TITLE" /* 停用 {0}？ */, u.name), message: (t("THEY_ARE_SIGNED_OUT_EVERYWHERE_AND_CAN_NO_LONGER_SYNC_OR_LOG" /* 该用户将在所有设备退出登录，重新启用前无法登录或同步。已有数据会保留。 */)), confirmText: t("ADMIN_DISABLE_ACTION" /* 停用 */), danger: true, onConfirm: () => setDisabled(true) })}>
        {u.disabled ? (t("ENABLE_ACCOUNT" /* 启用账号 */)) : (t("DISABLE_ACCOUNT" /* 停用账号 */))}</button>
      <div className="adm-hint">{u.disabled ? (t("ENABLING_LETS_THEM_SIGN_IN_AND_SYNC_AGAIN" /* 启用后，用户可以重新登录和同步。 */)) : (t("DISABLING_SIGNS_THEM_OUT_EVERYWHERE_AND_BLOCKS_SIGN_IN_NOTHING_IS_DELETED" /* 停用后，用户将在所有设备退出登录，且无法再次登录。已有数据会保留。 */))}</div>
      {/* The one destructive action in the app (issue #107), so it asks twice and offers the
          export first — that history is theirs. The second step names the account again, because
          the first sheet can be dismissed by anyone who was not reading. */}
      <button className="btn danger" style={{ margin: '14px 0 4px' }}
        onClick={() => confirmSheet({
          title: t("ADMIN_DELETE_TITLE" /* 删除 {0}？ */, u.name),
          message: (t("EVERYTHING_GOES_THEIR_WORKOUTS_WEIGH_INS_ROUTINES_PASSKEYS_AND_NOTIFICATIONS_THIS_CANNOT" /* 将删除该用户的训练、体重、计划、通行密钥和通知，且无法恢复。注册时使用的邀请码不会恢复可用。如需保留数据，请先下载。 */)),
          confirmText: t("CONTINUE" /* 继续 */),
          danger: true,
          onConfirm: () => confirmSheet({
            title: t("ADMIN_DELETE_PERMANENT_TITLE" /* 永久删除 {0} 及其数据？ */, u.name),
            message: (t("LAST_CHANCE_THERE_S_NO_UNDO_AND_NO_BACKUP_OF_THIS_ON" /* 请再次确认。删除后无法撤销，服务器也不保留备份。 */)),
            confirmText: (t("DELETE_ACCOUNT" /* 删除账号 */)),
            danger: true,
            onConfirm: doDelete,
          }),
        })}>{t("DELETE_ACCOUNT" /* 删除账号 */)}</button>
      <button className="btn" style={{ marginBottom: 4 }} onClick={exportUser}>{t("DOWNLOAD_THEIR_DATA" /* 下载用户数据 */)}</button>
      <div className="adm-hint">{t("DELETING_REMOVES_THE_ACCOUNT_AND_EVERY_TRACE_OF_ITS_TRAINING_HISTORY_FROM" /* 将从此服务器删除账号及其全部训练记录。 */)}</div>
      {pwInstance && <>
        <button className="btn" style={{ margin: '14px 0 4px' }} onClick={resetPassword}>{t("RESET_PASSWORD" /* 重置密码 */)}</button>
        <div className="adm-hint">{u.password
          ? (t("FOR_A_FORGOTTEN_PASSWORD_A_ONE_TIME_CODE_LETS_THEM_CHOOSE_A" /* 用户忘记密码时，可凭一次性重置码设置新密码。原密码立即失效。 */))
          : (t("NO_PASSWORD_YET_A_ONE_TIME_CODE_LETS_THEM_SET_ONE_THAT" /* 尚未设置密码。用户可凭一次性重置码设置密码，也可在丢失唯一通行密钥后用此方式恢复登录。 */))}</div>
      </>}
    </>}
    <h4 className="sec">{t("WORKOUT_HISTORY" /* 训练记录 */)}</h4>
    {workouts.length ? <div className="list" style={{ gap: 0 }}>
      {workouts.slice(0, 60).map(w => <div key={w.id} className="row between" style={{ padding: '9px 2px', borderBottom: '1px solid var(--sep)' }}>
        <div><div className="small" style={{ fontWeight: 600 }}>{w.name}</div>
          <div className="dim" style={{ fontSize: '.72rem' }}>{fmtDate(w.d, true)} · {fmtDur((w.end || w.start) - w.start)} · {setsDone(w)} {t("SETS_A" /* 组 */)}{w.prs?.length ? ' · ' + w.prs.length + ' PR' : ''}</div></div>
        <span className="small muted">{fmtVol(w.vol ?? workoutVolume(w), d.unit)}</span>
      </div>)}
    </div> : <div className="adm-empty">{t("NO_WORKOUTS_YET" /* 暂无训练记录 */)}</div>}
  </>
}

function InvitesCard({ invites, reload, inviteOnly }) {
  const toast = useUI(s => s.toast)
  const gen = () => api('/api/admin/invites/new', { method: 'POST', body: '{}' })
    .then(({ invite }) => { navigator.clipboard?.writeText(invite.code).catch(() => {}); toast(t("ADMIN_CODE_CREATED" /* 邀请码 {0} 已生成并复制 */, invite.code)); reload() })
    .catch(e => toast(e.message))
  const revoke = code => confirmSheet({
    title: t("ADMIN_REVOKE_CODE_TITLE" /* 撤销邀请码 {0}？ */, code), message: (t("ANYONE_WHO_HAS_IT_CAN_NO_LONGER_USE_IT_PEOPLE_WHO_ALREADY" /* 该邀请码将立即失效，已使用它注册的用户不受影响。 */)),
    confirmText: t("ADMIN_REVOKE_ACTION" /* 撤销 */), danger: true,
    onConfirm: () => api('/api/admin/invites/revoke', { method: 'POST', body: JSON.stringify({ code }) })
      .then(() => { toast((t("CODE_REVOKED" /* 邀请码已撤销 */))); reload() }).catch(e => toast(e.message))
  })
  const copy = code => { navigator.clipboard?.writeText(code).catch(() => {}); toast((t("COPIED" /* 已复制 */) + " ") + code) }
  const open = (invites || []).filter(i => !i.usedBy)
  const used = (invites || []).filter(i => i.usedBy)
  return <div className="card">
    <div className="row between"><h2 style={{ margin: 0 }}>{t("INVITE_CODES" /* 邀请码 */)}</h2>
      <Button variant="primary" size="sm" onClick={gen} icon="plus">{t("NEW_CODE" /* 生成邀请码 */)}</Button></div>
    <div className="adm-lead">
      {inviteOnly
        ? (t("SIGN_UP_IS_INVITE_ONLY_SOMEONE_NEEDS_ONE_OF_THESE_CODES_TO" /* 当前仅限受邀注册。新用户需要邀请码，每个码仅可使用一次。 */))
        : (t("SIGN_UP_IS_OPEN_SO_CODES_ARE_OPTIONAL_HERE_THEY_ONLY_RECORD" /* 当前开放注册，无需邀请码。邀请码仅用于记录邀请关系。 */))}
    </div>
    {open.length ? <>
      <div className="adm-group-t">{t("UNUSED_TAP_TO_COPY" /* 未使用 · 点击复制 */)}</div>
      {open.map(i => <div key={i.code} className="row between" style={{ padding: '6px 0', borderBottom: 'var(--hair) solid var(--sep)' }}>
        <button className="adm-code" onClick={() => copy(i.code)} aria-label={(t("COPY_B" /* 复制 */) + " ") + i.code}>{i.code}</button>
        <div className="row" style={{ gap: 4 }}>
          <button className="iconbtn adm-iconbtn" onClick={() => copy(i.code)} aria-label={t("COPY_B" /* 复制 */)}><Icon name="copy" /></button>
          <button className="iconbtn adm-iconbtn" style={{ color: 'var(--red)' }} onClick={() => revoke(i.code)} aria-label={t("REVOKE" /* 撤销 */)}><Icon name="trash" /></button>
        </div>
      </div>)}
    </> : null}
    {used.length ? <>
      <div className="adm-group-t" style={{ marginTop: open.length ? 12 : 0 }}>{t("ALREADY_USED" /* 已使用 */)}</div>
      {used.map(i => <div key={i.code} className="row between dim" style={{ padding: '6px 0', fontSize: '.82rem' }}>
        <span style={{ fontFamily: 'ui-monospace,SFMono-Regular,Menlo,monospace', letterSpacing: '.06em' }}>{i.code}</span><span>→ {i.usedByName || (t("USED" /* 已使用 */))}</span>
      </div>)}
    </> : null}
    {!open.length && !used.length && <div className="adm-empty">{t("NO_CODES_YET_NEW_CODE_MAKES_ONE_AND_COPIES_IT_TO_YOUR" /* 暂无邀请码。点击“生成邀请码”即可创建并复制。 */)}</div>}
  </div>
}

// Who signed in, who tried and failed, what an admin changed. A card rather than its own route:
// the dashboard is deliberately one page of cards, and the 95 % use of this is a glance at the
// last twenty events. Paging follows Library.jsx's house style — "Show more", not page numbers.
function AuditCard({ tick }) {
  const toast = useUI(s => s.toast)
  const [meta, setMeta] = useState(null)      // last response minus the rows: total, retention, …
  const [rows, setRows] = useState([])
  const [cat, setCat] = useState('')

  const load = (c, before) => api('/api/admin/audit?limit=50&cat=' + c + (before ? '&before=' + before : ''))
    .then(r => { setMeta(r); setRows(x => (before ? x.concat(r.events) : r.events)) })
    .catch(e => toast(e.message))
  const pick = c => { setCat(c); setRows([]); setMeta(null); load(c) }
  // Reloads on mount and whenever the header's ↻ bumps the tick. Deliberately not on the 15s
  // poll that drives "training now": this is history, not presence.
  useEffect(() => { load(cat) }, [tick])

  const clear = () => confirmSheet({
    title: (t("CLEAR_THE_ACTIVITY_LOG" /* 清空操作日志？ */)),
    message: (t("EVERY_RECORDED_EVENT_IS_DELETED_THE_CLEAR_ITSELF_IS_LOGGED_SO_THE" /* 将删除全部已有日志。本次清空操作仍会被记录，便于追溯。 */)),
    confirmText: t("CLEAR" /* 清除 */), danger: true,
    onConfirm: () => api('/api/admin/audit/clear', { method: 'POST', body: '{}' })
      .then(() => { toast((t("ACTIVITY_LOG_CLEARED" /* 操作日志已清空 */))); pick(cat) }).catch(e => toast(e.message))
  })

  if (meta && !meta.enabled) return null      // AUDIT_LOG=0 — the card isn't there at all

  return <div className="card">
    <div className="row between"><h2 style={{ margin: 0 }}>{t("ACTIVITY_LOG" /* 操作日志 */)}</h2>
      <button className="iconbtn adm-iconbtn" style={{ color: 'var(--red)' }} onClick={clear} aria-label={t("CLEAR_LOG" /* 清空日志 */)}><Icon name="trash" /></button></div>
    <div className="adm-lead"> {t("WHO_SIGNED_IN_WHAT_FAILED_AND_WHAT_AN_ADMIN_CHANGED" /* 查看登录、失败请求及管理员操作。 */)} {meta ? ' ' + t("ADMIN_EVENT_COUNT" /* {0} 条事件 */, fmtNum(meta.total))
        + (meta.retention.days ? ', ' + t("ADMIN_RETENTION" /* 保留 {0} 天 */, meta.retention.days) : '')
        + (meta.ip_mode === 'off' ? t("WITHOUT_IP_ADDRESSES" /* ，不记录 IP 地址 */) : '') + '.' : ''}
    </div>
    <div className="chips" style={{ marginBottom: 10 }}>
      {[['', (t("ALL" /* 全部 */))], ['auth', (t("SIGN_INS" /* 登录 */))], [(t("ADMIN" /* 管理员 */)), (t("ADMIN_A" /* 管理后台 */))], ['fail', (t("FAILED" /* 失败 */))]].map(([v, l]) =>
        <button key={v} className={'chip' + (cat === v ? ' on' : '')} onClick={() => pick(v)}>{l}</button>)}
    </div>
    {rows.map(e => {
      const line = auditLine(e)
      return <div key={e.id} className="row between" style={{ padding: '8px 2px', borderBottom: 'var(--hair) solid var(--sep)' }}>
        <div className="grow">
          <div className="small" style={{ fontWeight: 600 }}>{line.title}
            {/* a red pill, not a red row: twenty fumbled Face IDs in a row shouldn't read as an incident */}
            {!e.ok && <span className="adm-pill bad" style={{ marginInlineStart: 6 }}>{t("FAILED_A" /* 失败 */)}</span>}
            {auditCat(e.ev) === 'admin' && <span className="adm-pill acc" style={{ marginInlineStart: 6 }}>{t("ADMIN" /* 管理员 */)}</span>}</div>
          {line.sub && <div className="dim" style={{ fontSize: '.72rem' }}>{line.sub}</div>}
        </div>
        <span className="small muted" style={{ flex: 'none', marginInlineStart: 8 }}>{fmtWhen(e.ts, meta?.now)}</span>
      </div>
    })}
    {meta && !rows.length && <div className="adm-empty">{t("NOTHING_LOGGED_YET_A" /* 暂无日志。 */)}</div>}
    {meta?.nextBefore && <div style={{ marginTop: 10 }}>
      <Button size="sm" onClick={() => load(cat, meta.nextBefore)}>{t("SHOW_MORE" /* 显示更多 */)}</Button></div>}
  </div>
}

export default function Admin() {
  const nav = useNavigate()
  const user = useStore(s => s.user)
  const openSheet = useUI(s => s.openSheet)
  const [users, setUsers] = useState(null)
  const [usersErr, setUsersErr] = useState(null)   // why the last load failed, until one succeeds
  const [invites, setInvites] = useState(null)
  const [inviteOnly, setInviteOnly] = useState(false)
  const [tick, setTick] = useState(0)          // the ↻ button; the activity log listens to it

  // A failed load, or an answer without a list, used to leave the page on "Loading…" for good —
  // with a toast every 15 seconds from the poll, or with nothing at all when the answer was
  // someone else's page. It says so where the list would be instead, and the poll (or ↻) keeps
  // trying; a list that did load stays up, marked as the last one that came through.
  const loadUsers = () => api('/api/admin/users')
    .then(d => {
      if (!Array.isArray(d?.users)) throw new Error((t("THE_SERVER_ANSWERED_WITHOUT_A_LIST_OF_USERS" /* 服务器未返回用户列表。 */)))
      setUsers(d.users); setInviteOnly(!!d.invite_only); setUsersErr(null)
    })
    .catch(e => setUsersErr(e.message || (t("FAILED_TO_LOAD" /* 加载失败 */))))
  const loadInvites = () => api('/api/admin/invites').then(d => setInvites(d.invites)).catch(() => {})
  // poll every 15s so the "training now" section stays live without a manual refresh
  useEffect(() => { if (!user?.admin) return; loadUsers(); loadInvites(); const iv = setInterval(loadUsers, 15000); return () => clearInterval(iv) }, [])
  if (!user?.admin) return null

  const openUser = id => openSheet(close => <UserDetail id={id} onChanged={loadUsers} close={close} />)
  const liveUsers = (users || []).filter(u => u.live)
  const activeCount = (users || []).filter(u => u.lastSync && Date.now() - u.lastSync < 7 * 86400000).length
  const disabledCount = (users || []).filter(u => u.disabled).length

  return <div className="narrow">
    <div className="hdr">
      <button className="iconbtn" onClick={() => nav('/settings/account')} aria-label={t("BACK_A" /* 返回 */)}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginInlineStart: 8 }}><h1 style={{ margin: 0 }}>{t("ADMIN_A" /* 管理后台 */)}</h1>
        <div className="sub">{users ? t("ADMIN_USER_COUNTS" /* {0} 位用户 · 本周 {1} 位活跃 */, users.length, activeCount) : usersErr ? (t("COULD_NOT_LOAD" /* 无法加载 */)) : (t("LOADING" /* 加载中… */))}</div></div>
      <button className="iconbtn" onClick={() => { loadUsers(); loadInvites(); setTick(n => n + 1) }} aria-label={t("REFRESH_A" /* 刷新 */)}>↻</button>
    </div>
    <div className="adm-intro"> {t("EVERYTHING_ABOUT_RUNNING_THIS_INSTANCE_WHO_USES_IT_HOW_THEY_GET_IN" /* 管理用户、登录方式和 AI 教练，查看服务器操作记录。此处仅显示训练统计数量，不展示用户的具体训练内容。 */)} </div>

    {usersErr && <div className="card" role="alert" style={{ borderColor: 'var(--red)' }}>
      <div className="row between"><h2 style={{ margin: 0 }}>{users ? (t("THE_LAST_UPDATE_FAILED" /* 上次更新失败 */)) : (t("COULD_NOT_LOAD_THE_USERS" /* 无法加载用户列表 */))}</h2>
        <Button size="sm" icon="reset" onClick={loadUsers}>{t("TRY_AGAIN" /* 重试 */)}</Button></div>
      <div className="adm-lead" style={{ marginBottom: 0 }}>
        {usersErr} {users ? (t("THE_LIST_BELOW_IS_THE_LAST_ONE_THAT_LOADED" /* 下方显示上次成功加载的列表。 */)) : (t("IT_TRIES_AGAIN_EVERY_SECONDS" /* 每 15 秒自动重试。 */))}
      </div>
    </div>}

    <div className="tiles" style={{ marginBottom: 12 }}>
      <div className="tile"><div className="l">{t("USERS" /* 用户 */)}</div><div className="v">{users ? users.length : '–'}</div></div>
      <div className="tile"><div className="l">{t("TRAINING_NOW" /* 正在训练 */)}</div><div className="v" style={{ color: liveUsers.length ? 'var(--acc)' : undefined }}>{users ? liveUsers.length : '–'}</div></div>
      <div className="tile"><div className="l">{t("ACTIVE_DAYS" /* 近 7 天活跃 */)}</div><div className="v">{users ? activeCount : '–'}</div></div>
      <div className="tile"><div className="l">{t("DISABLED_A" /* 已停用 */)}</div><div className="v">{users ? disabledCount : '–'}</div></div>
    </div>

    {liveUsers.length > 0 && <div className="card" style={{ borderColor: 'var(--acc)' }}>
      <h2 className="row" style={{ margin: '0 0 2px', gap: 6 }}><Icon name="dot" style={{ fontSize: 10, color: 'var(--green)' }} />{t("TRAINING_NOW" /* 正在训练 */)}</h2>
      <div className="adm-lead">{t("SESSIONS_RUNNING_AT_THIS_MOMENT_TAP_A_NAME_FOR_DETAILS" /* 查看正在进行的训练。点击用户名称查看详情。 */)}</div>
      {liveUsers.map(u => <div key={u.id} className="row between" style={{ padding: '8px 2px', borderBottom: 'var(--hair) solid var(--sep)' }} onClick={() => openUser(u.id)}>
        <div><div className="small" style={{ fontWeight: 600 }}>{u.name}</div>
          <div className="dim" style={{ fontSize: '.72rem' }}>{u.live.name} {t("EXERCISE_A" /* · 动作 */)} {u.live.exIdx} {t("OF" /* 术语：/ */)} {u.live.exTotal} · {u.live.setsDone}/{u.live.setsTotal} {t("SETS_A" /* 组 */)}</div></div>
        <span className="adm-pill acc">{dur(Date.now() - u.live.startedAt)}</span>
      </div>)}
    </div>}

    {/* The Coach setup. Renders nothing at all unless the instance offers the Coach, so an admin
        page on a box that never enabled it is byte-for-byte the page it was before. */}
    <AdminCoach />

    <InvitesCard invites={invites} reload={loadInvites} inviteOnly={inviteOnly} />

    <div className="card">
      <h2 style={{ margin: 0 }}>{t("USERS" /* 用户 */)}</h2>
      <div className="adm-lead">{t("EVERYONE_WITH_A_PROFILE_ON_THIS_INSTANCE_TAP_ONE_TO_SEE_THEIR" /* 查看此服务器的全部用户。点击可查看活动、停用账号并保留数据，或永久删除账号及其数据。 */)}</div>
      <div className="list">
        {(users || []).map(u => <div key={u.id} className="item" onClick={() => openUser(u.id)} style={u.disabled ? { opacity: .55 } : null}>
          <div className="grow"><div className="tt">{u.live && <Icon name="dot" style={{ fontSize: 9, color: 'var(--green)', display: 'inline-block', marginInlineEnd: 5 }} />}{u.name} {u.admin && <span className="adm-pill acc" style={{ marginInlineStart: 4 }}>{t("ADMIN" /* 管理员 */)}</span>}{u.disabled && <span className="adm-pill bad" style={{ marginInlineStart: 4 }}>{t("DISABLED" /* 已停用 */)}</span>}</div>
            <div className="ss">{u.live ? (t("TRAINING_NOW_A" /* 训练中 · */) + " ") + u.live.name : t("ADMIN_PROFILE_ACTIVITY" /* {0} 次训练{1} · 上次同步：{2} */, u.workouts, u.lastWorkout ? t("ADMIN_LAST_WORKOUT" /* · 最近训练：{0} */, fmtDate(u.lastWorkout)) : "", rel(u.lastSync))}</div>
            {u.email && <div className="ss" title={t("SIGN_IN_E_MAIL_A" /* 登录邮箱 */)}>{u.email}</div>}</div>
          {u.hasPush && <Icon name="bell" title={t("PUSH_NOTIFICATIONS_ON" /* 推送通知已开启 */)} style={{ fontSize: 15, color: 'var(--label-3)' }} />}<Icon name="chevronRight" className="chev" />
        </div>)}
        {users && !users.length && <div className="adm-empty">{t("NO_USERS_YET" /* 暂无用户。 */)}</div>}
      </div>
    </div>

    <div style={{ marginTop: 14 }}><AuditCard tick={tick} /></div>
  </div>
}
