// 将共享 JSON 中的通知文案打包进 API 镜像，无需依赖前端目录。
import { readFileSync, writeFileSync } from 'node:fs'
const root = new URL('../../', import.meta.url)
const keys = ['REST_COMPLETE', 'NOTIFICATION_NEXT_SET', 'NOTIFICATION_TEST_BODY', 'NOTIFICATION_WORKOUT_TODAY', 'NOTIFICATION_ROUTINE_TODAY', 'NOTIFICATION_WORKOUT_BODY']
const result = {}
for (const lang of ['en', 'zh', 'pt-BR']) {
  const en = JSON.parse(readFileSync(new URL('localization/en.json', root)))
  const pack = JSON.parse(readFileSync(new URL(`localization/${lang}.json`, root)))
  result[lang] = Object.fromEntries(keys.map(key => [key, pack[key] || en[key]]))
}
const output = JSON.stringify(result, null, 2) + '\n'
const target = new URL('api/push-copy.json', root)
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== output) throw Error('Run node scripts/localization/generate-push.mjs')
} else writeFileSync(target, output)
