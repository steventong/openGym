import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
const root = new URL('../../', import.meta.url)
// Android 资源名必须使用小写；所有实际翻译仍由大写 JSON key 提供。
const mapping = {
  rest_countdown_channel_name: 'ANDROID_REST_COUNTDOWN_CHANNEL', // 倒计时通知类别
  rest_channel_name: 'ANDROID_REST_CHANNEL', // 休息通知类别
  rest_quiet_channel_name: 'ANDROID_REST_QUIET_CHANNEL', // 静默通知类别
  rest_channel_desc: 'ANDROID_REST_CHANNEL_DESCRIPTION', // 通知类别说明
  localized_rest_complete: 'REST_COMPLETE', // 休息结束
  localized_rest: 'REST_BETWEEN_SETS', // 组间休息
  localized_pause: 'PAUSE', // 暂停
  localized_resume: 'RESUME', // 继续
  localized_skip: 'END_REST', // 结束休息
  localized_rest_minus: 'REST_MINUS_FIFTEEN', // 减少十五秒
  localized_rest_plus: 'REST_PLUS_FIFTEEN', // 增加十五秒
}
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll("'", "\\'").replaceAll('"', '\\"')
export function androidResources(pack) {
  return '<?xml version="1.0" encoding="utf-8"?>\n<!-- Generated from shared localization JSON. -->\n<resources>\n' + Object.entries(mapping).map(([name, key]) => `    <string name="${name}" formatted="false">${escape(pack[key])}</string>`).join('\n') + '\n</resources>\n'
}
for (const [lang, folder] of [['en', 'values'], ['zh', 'values-zh']]) {
  const directory = new URL(`frontend/android/app/src/main/res/${folder}/`, root)
  const file = new URL('localization.xml', directory)
  const content = androidResources(JSON.parse(readFileSync(new URL(`localization/${lang}.json`, root))))
  if (process.argv.includes('--check')) {
    if (readFileSync(file, 'utf8') !== content) throw Error(`Stale Android strings: ${folder}`)
  } else { mkdirSync(directory, { recursive: true }); writeFileSync(file, content) }
}
