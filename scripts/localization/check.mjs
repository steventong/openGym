import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { resolve, relative } from 'node:path'
import { createRequire } from 'node:module'
const root = fileURLToPath(new URL('../../', import.meta.url))
const require = createRequire(resolve(root, 'frontend/package.json'))
const { parse } = require('@babel/parser')
const read = file => readFileSync(resolve(root, file), 'utf8')
const catalog = language => JSON.parse(read(`localization/${language}.json`))
const en = catalog('en'), zh = catalog('zh'), aliases = JSON.parse(read('localization/metadata/legacy-values.json'))
const canonicalKeys = JSON.parse(read('localization/metadata/canonical-keys.json'))
const errors = []
const keyPattern = /^[A-Z]+(?:_[A-Z]+)*$/
const marks = s => [...s.matchAll(/\{\d+\}/g)].map(m => m[0]).sort().join(' ')
const report = message => errors.push(message)
if (JSON.stringify(Object.keys(en).sort()) !== JSON.stringify(Object.keys(zh).sort())) report('en / zh key sets differ')
for (const file of readdirSync(resolve(root, 'localization')).filter(f => f.endsWith('.json') && f !== 'legacy-values.json')) {
  for (const [key, value] of Object.entries(catalog(file.slice(0, -5)))) {
    if (!keyPattern.test(key)) report(`${file}: invalid key ${key}`)
    if (!Object.hasOwn(en, key)) report(`${file}: unknown key ${key}`)
    for (const form of typeof value === 'object' ? Object.values(value) : [value]) {
      if (typeof form !== 'string' || !form.trim()) report(`${file}: blank/non-string ${key}`)
      else if (en[key] && marks(form) !== marks(en[key])) report(`${file}: placeholders differ for ${key}`)
    }
  }
}
for (const [source, key] of Object.entries(aliases)) if (!Object.hasOwn(en, key)) report(`Legacy value has no target: ${source}`)
for (const [oldKey, key] of Object.entries(canonicalKeys)) {
  if (!en[oldKey] || !en[key] || canonicalKeys[key] || marks(en[oldKey]) !== marks(en[key])) report(`Invalid canonical copy mapping: ${oldKey} → ${key}`)
}
for (const [source, key] of Object.entries(aliases)) if (canonicalKeys[key]) report(`Legacy value must use canonical copy: ${source} → ${canonicalKeys[key]}`)
export function walk(n, visit, parent) {
  if (!n || typeof n !== 'object') return
  if (n.type) visit(n, parent)
  for (const [key, value] of Object.entries(n)) {
    if (key === 'loc' || key === 'comments' || key.endsWith('Comments')) continue
    if (Array.isArray(value)) value.forEach(child => walk(child, visit, n))
    else if (value && typeof value === 'object') walk(value, visit, n)
  }
}
const files = dir => !existsSync(resolve(root, dir)) ? [] : readdirSync(resolve(root, dir), { withFileTypes: true }).flatMap(e => e.isDirectory() ? files(`${dir}/${e.name}`) : [`${dir}/${e.name}`])
let references = 0
const verify = (key, comment, file) => {
  references++
  if (!keyPattern.test(key) || !Object.hasOwn(en, key)) report(`${file}: missing/invalid key ${key}`)
  if (canonicalKeys[key]) report(`${file}: use shared copy ${canonicalKeys[key]} instead of ${key}`)
  if (!/[\u3400-\u9fff]/.test(comment)) report(`${file}: Chinese comment missing for ${key}`)
}
const leaves = (node, visit) => {
  if (!node) return
  if (node.type === 'StringLiteral') visit(node)
  else if (node.type === 'ConditionalExpression') { leaves(node.consequent, visit); leaves(node.alternate, visit) }
}
// Stable brands, technical sample values and visible unit symbols are not prose.
const nonCopy = /^(?:openGym(?: v)?|PR|s|15s|CF-Access-Client-(?:Id|Secret)|Gym visual|NOTICE\.md|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)$/
for (const file of [...files('frontend/src'), ...files('native-ios/scripts/rules')].filter(f => /\.[jt]sx?$/.test(f) && !f.includes('.test.') && !/\/(locales|instr|exercise-names|exercise-desc)\//.test(f))) {
  const source = read(file)
  walk(parse(source, { sourceType: 'module', plugins: ['jsx'] }), (n, parent) => {
    // Catch untranslated workout fragments even when assembled before reaching JSX.
    if (n.type === 'TemplateLiteral' && n.quasis.some(q => /\b(?:Rest|Reps|Set|Increase|Decrease)\b/.test(q.value.cooked))) report(`${file}: use shared workout copy instead of a prose template`)
    if (n.type === 'CallExpression' && ['t', 'tn'].includes(n.callee.name)) {
      for (const argument of n.arguments.slice(0, n.callee.name === 'tn' ? 2 : 1)) leaves(argument, literal => {
        const tail = source.slice(literal.end).match(/^\s*\/\*([\s\S]*?)\*\//)?.[1] || ''
        verify(literal.value, tail, file)
      })
    }
    if (n.type === 'JSXText') {
      const text = n.value.trim()
      if (/[A-Za-z\u3400-\u9fff]/.test(text) && !nonCopy.test(text)) report(`${file}: unlocalized JSX ${text.slice(0, 100)}`)
    }
    if (n.type === 'StringLiteral' && parent?.type === 'JSXAttribute' && ['title', 'aria-label', 'placeholder', 'alt'].includes(parent.name.name)
      && /[A-Za-z\u3400-\u9fff]/.test(n.value) && !nonCopy.test(n.value) && !/^https?:\/\//.test(n.value)) report(`${file}: unlocalized ${parent.name.name}: ${n.value}`)
  })
}
for (const directory of ['OpenGym', 'Shared']) {
  for (const file of files(`native-ios/${directory}`).filter(f => f.endsWith('.swift'))) {
    const source = read(file)
    for (const match of source.matchAll(/(?:String\(localized:\s*|(?:Text|Button|Section|Label|Toggle|Picker|TextField|SecureField|DatePicker|NavigationLink|LabeledContent|navigationTitle|accessibilityLabel|accessibilityHint|confirmationDialog|alert)\(\s*)"([A-Z][A-Z_0-9]*)"/g)) {
      if (!keyPattern.test(match[1]) || !Object.hasOwn(en, match[1]) || !Object.hasOwn(zh, match[1])) report(`${file}: missing/invalid key ${match[1]}`)
      if (canonicalKeys[match[1]]) report(`${file}: use shared copy ${canonicalKeys[match[1]]} instead of ${match[1]}`)
    }
    for (const match of source.matchAll(/(?:String\(localized:\s*|(?:Text|Button|Section|Label|Toggle|Picker|TextField|SecureField|DatePicker|NavigationLink|LabeledContent|navigationTitle|accessibilityLabel|accessibilityHint|confirmationDialog|alert)\(\s*)"([A-Z][A-Z_0-9]*)"\s*\/\*([\s\S]*?)\*\//g)) verify(match[1], match[2], file)
  }
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1 }
else console.log(`${Object.keys(en).length} bilingual JSON keys; ${references} source references — in sync.`)
