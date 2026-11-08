import { test } from 'node:test'
import assert from 'node:assert/strict'
import { appleFormat, appleCatalogs, nativeLocalizationKeys } from './generate-apple.mjs'

test('converts reordered and repeated arguments to standard Apple positional formats', () => {
  assert.equal(appleFormat('{1}: {0} / {0}'), '%2$@: %1$@ / %1$@')
  assert.equal(appleFormat('{0}% of 100%'), '%1$@%% of 100%%')
  assert.equal(appleFormat('100% complete'), '100% complete')
})
test('emits standard catalogs with both languages and Chinese translator comments', () => {
  const catalogs = appleCatalogs()
  const local = catalogs['OpenGYM-iOS/Resources/Localization/Localizable.xcstrings']
  assert.equal(local.sourceLanguage, 'en')
  for (const [key, entry] of Object.entries(local.strings)) {
    assert.match(key, /^[A-Z]+(?:_[A-Z]+)*$/)
    for (const language of ['en', 'zh-Hans']) assert.ok(!entry.localizations[language].stringUnit.value.includes('iPhone'), key)
  }
  assert.equal(local.strings.CANCEL.localizations['zh-Hans'].stringUnit.value, '取消')
  assert.equal(local.strings.SET_COUNT_OF_COUNT.localizations.en.stringUnit.value, 'Set %1$@ of %2$@')
  for (const catalog of Object.values(catalogs)) for (const entry of Object.values(catalog.strings)) {
    assert.match(entry.comment, /[\u3400-\u9fff]/)
    assert.ok(entry.localizations.en)
    assert.ok(entry.localizations['zh-Hans'])
  }
})

test('rejects raw text, symbols and interpolation as native localization keys', () => {
  for (const source of [
    'Text(" ")', 'Text("!")', 'Text("—:—")', 'Text("3 × 10")', 'Text("%@")', 'Text("openGym")',
    'Text("\\(count) / \\(limit)")', 'Stepper("\\(reps)", value: $reps)',
    '.accessibilityLabel("\\(title), \\(value)")',
    'String(localized: "Raw text")', 'Text("INVALID_1_KEY")',
  ]) assert.throws(() => nativeLocalizationKeys(source, {}, {}), /invalid native localization key/, source)
})

test('ignores explicit dynamic text, comments and native vocabulary tables', () => {
  const source = `
    Text(verbatim: " ")
    Text(verbatim: "\\(number)")
    Text(value)
    Text(verbatim: "openGym")
    Text(number, format: .number)
    Stepper(String(reps), value: $reps)
    // Text("Example prose")
    /* Text("Another example") */
    String(localized: "barbell", table: "Vocabulary", bundle: bundle)
    String(localized: "trapezius", table: "Muscles", bundle: bundle)
    String(localized: String.LocalizationValue(id), table: "Muscles")
  `
  assert.deepEqual(nativeLocalizationKeys(source, {}, {}), [])
})

test('rejects missing native translations even without a translator comment', () => {
  const source = 'String(localized: "PREVIOUS_EXERCISE_NAMED")'
  assert.throws(() => nativeLocalizationKeys(source, {}, {}), /missing en translation for PREVIOUS_EXERCISE_NAMED/)
  assert.throws(() => nativeLocalizationKeys(source, { PREVIOUS_EXERCISE_NAMED: 'Previous: {0}' }, {}), /missing zh translation/)
  assert.throws(() => nativeLocalizationKeys('Text(\n "NEXT_EXERCISE_NAMED")', {}, {}), /missing en translation for NEXT_EXERCISE_NAMED/)
  assert.deepEqual(nativeLocalizationKeys(source, { PREVIOUS_EXERCISE_NAMED: 'Previous: {0}' }, { PREVIOUS_EXERCISE_NAMED: '上一个：{0}' }), ['PREVIOUS_EXERCISE_NAMED'])
})
