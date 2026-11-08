import { _setLangState } from '../../../frontend/src/lib/i18n-core.js';
import chinese from '../../../localization/zh.json' with { type: 'json' };
// Swift 在每次调用前传入界面语言；规则返回的提示与原生页面一致。
export function setLanguage(language) {
  _setLangState(language, language === 'zh' ? chinese : {}, null, null);
}
