import { readFileSync } from 'node:fs'
import { buildNudgeCopy } from '../../api/scripts/build-nudge-copy.mjs'
const root = new URL('../../', import.meta.url)
const { appleCatalogs } = await import('./generate-apple.mjs')
for (const [file, catalog] of Object.entries(appleCatalogs())) {
  if (readFileSync(new URL(file, root), 'utf8') !== JSON.stringify(catalog, null, 2) + '\n') throw Error(`Stale String Catalog: ${file}; run npm run generate:localization`)
}
if (readFileSync(new URL('api/nudge-copy.js', root), 'utf8') !== await buildNudgeCopy()) throw Error('Stale notification copy; run npm run generate:localization')
const push = JSON.parse(readFileSync(new URL('api/push-copy.json', root)))
const english = JSON.parse(readFileSync(new URL('localization/en.json', root)))
for (const [language, values] of Object.entries(push)) {
  const pack = JSON.parse(readFileSync(new URL(`localization/${language}.json`, root)))
  for (const [key, value] of Object.entries(values)) if (value !== (pack[key] || english[key])) throw Error(`Stale push copy: ${language}/${key}`)
}
console.log('Apple resources and generated notification copy match JSON.')

const { buildRules } = await import('../../OpenGYM-iOS/scripts/build-rules.mjs')
const built = await buildRules(false)
if (readFileSync(new URL('OpenGYM-iOS/Resources/web-rules.js', root), 'utf8') !== built.outputFiles[0].text) throw Error('Stale native rule bundle; run npm run generate:localization')
console.log('Native rule bundle matches shared JSON and source.')
