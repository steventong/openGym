import { t , translateValue } from './i18n-core.js'
// Rendering for the admin activity log (GET /api/admin/audit).
//
// The server stores reason codes, not sentences — `{ ev: 'auth.login.fail', msg: 'unknown-credential' }`
// rather than "someone tried a passkey we don't know". Turning those into English
// belongs here and not in Admin.jsx: it is the only part of the feature that can be wrong in a way
// a person sees, and as a plain module it is testable without mounting the dashboard.
//
// 日志事件和原因使用共享 JSON 翻译，事件代码保持原样。
import { dateLocale } from './i18n-core.js'

// The first segment of an event name is also the filter chip it belongs to.
export const auditCat = ev => String(ev || '').split('.')[0]

const LABELS = {
  'auth.login.ok': "SIGNED_IN" /* 登录成功 */,
  'auth.login.fail': "SIGN_IN_FAILED" /* 登录失败 */,
  'auth.register.ok': "CREATED_A_PROFILE" /* 已创建账号 */,
  'auth.register.fail': "PROFILE_CREATION_FAILED" /* 账号创建失败 */,
  'auth.register.denied': "SIGNUP_REFUSED" /* 注册被拒绝 */,
  'auth.logout': "SIGNED_OUT" /* 已退出登录 */,
  'auth.logout.all': "SIGNED_OUT_EVERYWHERE" /* 已退出所有设备 */,
  // Device pairing (Settings → "Pair the mobile app"): the code is minted in a signed-in browser
  // tab and redeemed by the app, so "ok" is the phone coming online, not a sign-in.
  'auth.pair.create': "CREATED_A_PAIRING_CODE" /* 已生成配对码 */,
  'auth.pair.ok': "PAIRED_A_PHONE" /* 已配对手机 */,
  'auth.pair.fail': "PAIRING_FAILED" /* 配对失败 */,
  // Password sign-in (#118), where the instance offers it.
  'auth.password.ok': "SIGNED_IN_WITH_A_PASSWORD" /* 密码登录成功 */,
  'auth.password.fail': "PASSWORD_SIGN_IN_FAILED" /* 密码登录失败 */,
  'auth.password.locked': "PASSWORD_SIGN_IN_PAUSED_AFTER_REPEATED_FAILURES" /* 多次登录失败，密码登录已暂停 */,
  'auth.password.set': "SET_A_PASSWORD" /* 设置密码 */,
  'auth.password.change': "CHANGED_THEIR_PASSWORD" /* 已修改密码 */,
  'auth.password.remove': "REMOVED_THEIR_PASSWORD" /* 已移除密码 */,
  'auth.password.reset': "USED_A_RESET_CODE" /* 已使用重置码 */,
  // The e-mail a profile may sign in with instead of its name. `msg` is the proof it was set with
  // and the address masked to two characters ("password · a…@e…") — never the address itself.
  'auth.email.set': "ADDED_A_SIGN_IN_E_MAIL" /* 已添加登录邮箱 */,
  'auth.email.change': "CHANGED_THEIR_SIGN_IN_E_MAIL" /* 已修改登录邮箱 */,
  'auth.email.remove': "REMOVED_THEIR_SIGN_IN_E_MAIL" /* 已移除登录邮箱 */,
  'auth.email.fail': "CHANGING_THE_SIGN_IN_E_MAIL_FAILED" /* 登录邮箱修改失败 */,
  // More than one passkey, and one-time codes for another device (#95). `msg` on an addition or a
  // code is the proof it was made with (passkey, password); on a removal or a redemption, the
  // passkey's name.
  'auth.passkey.add': "ADDED_A_PASSKEY" /* 已添加通行密钥 */,
  'auth.passkey.fail': "ADDING_A_PASSKEY_FAILED" /* 通行密钥添加失败 */,
  'auth.passkey.remove': "REMOVED_A_PASSKEY" /* 已移除通行密钥 */,
  'auth.link.create': "MADE_A_ONE_TIME_CODE_FOR_ANOTHER_DEVICE" /* 已生成设备连接码 */,
  'auth.link.ok': "ADDED_A_DEVICE_WITH_A_ONE_TIME_CODE" /* 已使用一次性码添加设备 */,
  'auth.link.fail': "ADDING_A_DEVICE_WITH_A_CODE_FAILED" /* 使用连接码添加设备失败 */,
  // The owner's proof (current password or a passkey) for one of the changes below was refused.
  'auth.proof.fail': "CONFIRMING_A_CHANGE_FAILED" /* 修改确认失败 */,
  // The password throttle paused an address; `msg` says for what (password, signup).
  'auth.throttled': "TOO_MANY_FAILED_ATTEMPTS_FROM_ONE_ADDRESS" /* 同一地址失败次数过多 */,
  'admin.user.disable': "DISABLED_AN_ACCOUNT" /* 已停用账号 */,
  'admin.user.enable': "RE_ENABLED_AN_ACCOUNT" /* 已重新启用账号 */,
  'admin.user.delete': "DELETED_AN_ACCOUNT" /* 已删除账号 */,
  'admin.password.reset': "ISSUED_A_PASSWORD_RESET_CODE" /* 已生成密码重置码 */,
  'admin.invite.create': "CREATED_AN_INVITE_CODE" /* 已生成邀请码 */,
  'admin.invite.revoke': "REVOKED_AN_INVITE_CODE" /* 已撤销邀请码 */,
  'admin.audit.clear': "CLEARED_THE_ACTIVITY_LOG" /* 已清空操作日志 */,
  // FIRST_USER_ADMIN=1: the first profile on a fresh instance is made admin as it signs up.
  'admin.first-user': "BECAME_ADMIN_AS_THE_FIRST_PROFILE" /* 首位注册用户已成为管理员 */,
  'admin.denied': "BLOCKED_FROM_THE_ADMIN_DASHBOARD" /* 管理后台访问被拒绝 */,
  // Photos and videos of custom exercises: "Reset everything" clearing a profile's files, and the
  // upload or clean-up throttle pausing a profile (`msg` says which).
  'media.sweep': "CLEARED_UNUSED_PHOTOS_AND_VIDEOS" /* 已清理未使用的照片和视频 */,
  'media.throttled': "TOO_MANY_PHOTO_OR_VIDEO_REQUESTS" /* 照片或视频请求过于频繁 */
}
// An unknown event is shown raw rather than dropped or rendered as "undefined": a dashboard
// that is one version behind the server should still say *something* truthful.
export const auditLabel = ev => translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(LABELS[ev]) || String(ev || (t("UNKNOWN_EVENT" /* 未知事件 */)))

const REASONS = {
  'challenge-expired': "THE_SIGN_IN_TOOK_TOO_LONG_AND_EXPIRED" /* 登录耗时过长，已过期 */,
  'unknown-credential': "UNKNOWN_PASSKEY" /* 无法识别的通行密钥 */,
  'verify-error': "THE_PASSKEY_COULD_NOT_BE_VERIFIED" /* 无法验证通行密钥 */,
  'not-verified': "THE_PASSKEY_WAS_REJECTED" /* 通行密钥被拒绝 */,
  'user-missing': "THE_PASSKEY_POINTS_AT_A_PROFILE_THAT_NO_LONGER_EXISTS" /* 此通行密钥对应的账号已不存在 */,
  'account-disabled': "THE_ACCOUNT_IS_DISABLED" /* 账号已停用 */,
  'credential-exists': "THAT_PASSKEY_ALREADY_BELONGS_TO_A_PROFILE" /* 此通行密钥已绑定其他账号 */,
  'invite-invalid': "THE_INVITE_CODE_WAS_USED_OR_REVOKED_IN_THE_MEANTIME" /* 邀请码已被使用或撤销 */,
  'invite-rejected': "WRONG_OR_ALREADY_USED_INVITE_CODE" /* 邀请码错误或已使用 */,
  'code-invalid': "WRONG_OR_EXPIRED_PAIRING_CODE" /* 配对码错误或已过期 */,
  'user-unavailable': "THE_PROFILE_BEHIND_THE_CODE_IS_DISABLED_OR_GONE" /* 连接码对应的账号已停用或删除 */,
  'bad-password': "WRONG_PASSWORD" /* 密码错误 */,
  'bad-current': "WRONG_CURRENT_PASSWORD" /* 当前密码错误 */,
  'unknown-name': "NO_PROFILE_WITH_A_PASSWORD_HAS_THAT_NAME" /* 未找到使用此名称且已设置密码的账号 */,
  'unknown-email': "NO_PROFILE_WITH_A_PASSWORD_HAS_THAT_E_MAIL" /* 未找到使用此邮箱且已设置密码的账号 */,
  'email-taken': "ANOTHER_PROFILE_ALREADY_USES_THAT_E_MAIL" /* 此邮箱已被其他账号使用 */,
  'step-up-failed': "THE_PASSKEY_CONFIRMING_THE_CHANGE_WAS_REJECTED" /* 用于确认修改的通行密钥被拒绝 */,
  'reset-invalid': "WRONG_OR_EXPIRED_RESET_CODE" /* 重置码错误或已过期 */,
  'link-invalid': "WRONG_USED_OR_EXPIRED_DEVICE_CODE" /* 设备连接码错误、已使用或已过期 */,
  'passkey-limit': "THE_PROFILE_ALREADY_HAS_AS_MANY_PASSKEYS_AS_IT_CAN_HOLD" /* 账号的通行密钥数量已达上限 */,
  // What an `auth.throttled` pause was for.
  'password': "WRONG_PASSWORDS_OR_RESET_CODES" /* 密码或重置码错误 */,
  'signup': "WRONG_INVITE_CODES_ON_PASSWORD_SIGNUP" /* 密码注册时邀请码错误 */,
  'link': "WRONG_ONE_TIME_DEVICE_CODES" /* 一次性设备连接码错误 */,
  'email': "E_MAIL_ADDRESSES_ALREADY_IN_USE" /* 邮箱已被使用 */,
  // What a `media.throttled` pause was for.
  'upload': "PHOTO_AND_VIDEO_UPLOADS" /* 照片和视频上传 */,
  'sweep': "CLEARING_UNUSED_PHOTOS_AND_VIDEOS" /* 清理未使用的照片和视频 */
}
export const auditReason = msg => translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(REASONS[msg]) || (msg ? String(msg) : '')

// What an `auth.proof.fail` was confirming (the server's `act`).
const ACTS = {
  'email': "CHANGING_THE_SIGN_IN_E_MAIL" /* 修改登录邮箱 */,
  'email-remove': "REMOVING_THE_SIGN_IN_E_MAIL" /* 移除登录邮箱 */,
  'password': "SETTING_OR_CHANGING_THE_PASSWORD" /* 设置或修改密码 */,
  'password-remove': "REMOVING_THE_PASSWORD" /* 移除密码 */,
  'passkey-add': "ADDING_A_PASSKEY" /* 添加通行密钥 */,
  'passkey-remove': "REMOVING_A_PASSKEY" /* 移除通行密钥 */,
  'device-link': "MAKING_A_ONE_TIME_CODE_FOR_ANOTHER_DEVICE" /* 生成设备连接码 */
}
export const auditAct = act => translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(ACTS[act]) || (act ? String(act) : '')

// → { title, sub }. `sub` is the house "a · b · c" metadata line used by every list row.
export function auditLine(e) {
  if (!e) return { title: '', sub: '' }
  const parts = []
  if (e.name) parts.push(e.name)
  else if (e.uid) parts.push(e.uid)
  else if (!e.ok) parts.push((t("UNKNOWN_CALLER" /* 未知操作者 */)))
  if (e.tname) parts.push('→ ' + e.tname)
  if (e.act) parts.push(auditAct(e.act))
  // The reason codes and the invite codes share the msg field; only failures read as a reason.
  if (e.msg) parts.push(e.ok ? e.msg : auditReason(e.msg))
  if (e.ip) parts.push(e.ip)
  return { title: auditLabel(e.ev), sub: parts.join(' · ') }
}

// The activity log is the one place in the app that needs a clock, and fmtDate() renders none —
// it is used by every other view and is not worth changing for this.
export function fmtWhen(ts, now = Date.now()) {
  if (!ts) return ''
  const d = new Date(ts)
  const time = d.toLocaleTimeString(dateLocale(), { hour: '2-digit', minute: '2-digit' })
  const n = new Date(now)
  const sameDay = d.toDateString() === n.toDateString()
  if (sameDay) return t("ADMIN_AUDIT_TODAY" /* 今天 {0} */, time)
  if (now - ts < 6 * 86400000 && ts <= now) return d.toLocaleDateString(dateLocale(), { weekday: 'short' }) + ' ' + time
  return d.toLocaleDateString(dateLocale(), { day: 'numeric', month: 'short' }) + ' ' + time
}
