import { afterEach, describe, expect, it } from 'vitest'
import en from '../../../localization/en.json'
import zh from '../../../localization/zh.json'
import { _setLangState, t, tn, translateValue } from './i18n-core.js'

afterEach(() => _setLangState('en', {}, null, null))
describe('shared localization JSON', () => {
  it('switches existing keys and dynamic catalogue labels together', () => {
    _setLangState('zh', zh, null, null)
    expect(t('CANCEL')).toBe('取消')
    expect(t('REST_COMPLETE')).toBe('休息结束')
    expect(translateValue('body weight')).toBe('自重')
    expect(t('BODY_WEIGHT')).toBe('体重')
    _setLangState('en', {}, null, null)
    expect(t('CANCEL')).toBe('Cancel')
    expect(t('REST_COMPLETE')).toBe('Rest complete')
  })
  it('uses complete messages without interpreting placeholders inside user input', () => {
    expect(t('ADMIN_LOGIN_NAME_OR_EMAIL', '{1}', 'a@example.com')).toBe('{1} (or sign-in email a@example.com)')
    _setLangState('zh', zh, null, null)
    expect(t('ADMIN_USER_COUNTS', 3, 2)).toBe('3 位用户 · 本周 2 位活跃')
    expect(t('SET_COUNT_OF_COUNT', 2, 4)).toBe('第 2/4 组')
    expect(t('RULE_MAX_SETS', 8)).toContain('8')
  })
  it('distinguishes anatomical labels, body measurements and different set techniques', () => {
    expect(zh.MEASUREMENT_CHEST).toBe('胸围')
    expect(zh.CHEST_A).toBe('胸部')
    expect(zh.BACK_OFF_SETS).toBe('减重组（Back-off）')
    expect(zh.DROP_SET).toBe('递减组')
    expect(zh.BACK_OFF_SETS).not.toBe(zh.DROP_SET)
  })
  it('keeps singular and plural selection with token keys', () => {
    expect(tn('COUNT_SET', 'COUNT_SETS', 1)).toBe('1 set')
    expect(tn('COUNT_SET', 'COUNT_SETS', 3)).toBe('3 sets')
    _setLangState('zh', zh, null, null)
    expect(tn('COUNT_SET', 'COUNT_SETS', 3)).toBe('3 组')
  })
  it('requires complete Chinese and English catalogs with no malformed placeholders', () => {
    expect(Object.keys(zh).sort()).toEqual(Object.keys(en).sort())
    const marks = value => [...value.matchAll(/\{\d+\}/g)].map(m => m[0]).sort()
    for (const key of Object.keys(en)) {
      expect(key).toMatch(/^[A-Z]+(?:_[A-Z]+)*$/)
      expect(zh[key].trim(), key).not.toBe('')
      expect(marks(zh[key]), key).toEqual(marks(en[key]))
    }
  })
})
