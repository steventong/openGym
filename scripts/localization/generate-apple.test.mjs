import { test } from 'node:test'
import assert from 'node:assert/strict'
import { appleFormat, appleCatalogs } from './generate-apple.mjs'

test('converts reordered and repeated arguments to standard Apple positional formats', () => {
  assert.equal(appleFormat('{1}: {0} / {0}'), '%2$@: %1$@ / %1$@')
  assert.equal(appleFormat('{0}% of 100%'), '%1$@%% of 100%%')
  assert.equal(appleFormat('100% complete'), '100% complete')
})
test('emits standard catalogs with both languages and Chinese translator comments', () => {
  const catalogs = appleCatalogs()
  const local = catalogs['native-ios/Localization/Localizable.xcstrings']
  assert.equal(local.sourceLanguage, 'en')
  assert.equal(local.strings.CANCEL.localizations['zh-Hans'].stringUnit.value, '取消')
  assert.equal(local.strings.SET_COUNT_OF_COUNT.localizations.en.stringUnit.value, 'Set %1$@ of %2$@')
  for (const catalog of Object.values(catalogs)) for (const entry of Object.values(catalog.strings)) {
    assert.match(entry.comment, /[\u3400-\u9fff]/)
    assert.ok(entry.localizations.en)
    assert.ok(entry.localizations['zh-Hans'])
  }
})
