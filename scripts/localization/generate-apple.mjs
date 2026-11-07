// Apple 使用标准 String Catalog；共享 JSON 仅在构建前转换，不由 Swift 运行时解析。
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { resolve, dirname } from 'node:path'
const root = fileURLToPath(new URL('../../', import.meta.url))

// Apple 的位置参数允许译文调整语序；全部参数使用对象格式，保留调用处的数字格式化。
export function appleFormat(value) {
  return /\{\d+\}/.test(value)
    ? value.replaceAll('%', '%%').replace(/\{(\d+)\}/g, (_, index) => `%${Number(index) + 1}$@`)
    : value
}
// Validate direct lookups even when a call has no translator comment.
export function nativeLocalizationKeys(source, en, zh, file = 'Swift source') {
  for (const match of source.matchAll(/(?:String\(localized:\s*|(?:Text|Button|Section|Label|Toggle|Picker|TextField|SecureField|DatePicker|NavigationLink|LabeledContent|navigationTitle|accessibilityLabel|accessibilityHint|confirmationDialog|alert)\(\s*)"([A-Z][A-Z_0-9]*)"/g)) {
    for (const [language, pack] of [['en', en], ['zh', zh]]) {
      if (typeof pack[match[1]] !== 'string' || !pack[match[1]].trim()) {
        throw Error(`${file}: missing ${language} translation for ${match[1]}`)
      }
    }
  }
  return [...source.matchAll(/"([A-Z]+(?:_[A-Z]+)*)"/g)]
    .map(match => match[1]).filter(key => Object.hasOwn(en, key))
}

export function appleCatalogs() {
  const en = JSON.parse(readFileSync(resolve(root, 'localization/en.json')))
  const zh = JSON.parse(readFileSync(resolve(root, 'localization/zh.json')))
  const make = entries => ({
    sourceLanguage: 'en',
    strings: Object.fromEntries(entries.map(([key, source]) => [key, {
      comment: /[\u3400-\u9fff]/.test(zh[source]) ? zh[source] : `术语：${zh[source]}`,
      extractionState: 'manual',
      localizations: Object.fromEntries([['en', en], ['zh-Hans', zh]].map(([language, pack]) => [language, {
        stringUnit: { state: 'translated', value: appleFormat(pack[source]) },
      }])),
    }])),
    version: '1.0',
  })
  // Apple 只打包原生引用的 key；网页独有的复数分支可能省略参数位置，不属于 Apple 格式。
  const used = new Set()
  const scan = directory => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = resolve(directory, entry.name)
      if (entry.isDirectory()) { if (entry.name !== 'Resources') scan(path) }
      else if (entry.name.endsWith('.swift')) {
        for (const key of nativeLocalizationKeys(readFileSync(path, 'utf8'), en, zh, path)) used.add(key)
      }
    }
  }
  for (const directory of ['OpenGym', 'Shared', 'OpenGymTests']) scan(resolve(root, 'native-ios', directory))
  const result = {
    'native-ios/Resources/Localization/Localizable.xcstrings': make([...used].sort().map(key => [key, key])),
  }
  for (const target of ['OpenGym', 'OpenGymWatch']) {
    result[`native-ios/Resources/Localization/${target}/InfoPlist.xcstrings`] = make([
      ['NSHealthShareUsageDescription', target === 'OpenGymWatch' ? 'SYSTEM_HEALTH_READ_WATCH' : 'SYSTEM_HEALTH_READ_PHONE'], // 健康读取权限
      ['NSHealthUpdateUsageDescription', 'SYSTEM_HEALTH_WRITE'], // 健康写入权限
    ])
  }
  return result
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  for (const [file, catalog] of Object.entries(appleCatalogs())) {
    mkdirSync(dirname(resolve(root, file)), { recursive: true })
    writeFileSync(resolve(root, file), JSON.stringify(catalog, null, 2) + '\n')
  }
}
