// 兼容旧词库工具；界面文案统一维护在 localization JSON。
import pack from '../../../localization/es.json' with { type: 'json' }
import legacySources from '../../../localization/metadata/legacy-source-keys.json' with { type: 'json' }
import aliases from '../../../localization/metadata/legacy-values.json' with { type: 'json' }
export default Object.fromEntries(Object.entries(aliases).filter(([source, key]) => legacySources.includes(source) && pack[key] !== undefined).map(([source, key]) => [source, pack[key]]))
