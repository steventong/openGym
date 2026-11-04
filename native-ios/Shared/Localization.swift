import Foundation
import Observation

/// Apple 标准 String Catalog 的轻量入口；翻译键只使用大写字母与下划线。
/// 不翻译用户输入、数据字段、动作 ID 或同步协议值。
enum L10n {
    @Observable final class Preferences {
        var language: String = resolve(UserDefaults.standard.string(forKey: "opengym.language"))
    }
    static let preferences = Preferences()
    static var language: String { preferences.language }
    static var locale: Locale { Locale(identifier: language == "zh" ? "zh-Hans" : "en") }

    static func resolve(_ value: String?) -> String {
        let preferred = value.flatMap { $0.isEmpty ? nil : $0 } ?? Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? "zh" : "en"
    }

    static func setLanguage(_ value: String?) {
        let resolved = resolve(value)
        guard preferences.language != resolved else { return }
        preferences.language = resolved
        UserDefaults.standard.set(resolved, forKey: "opengym.language")
    }

    // 账号语言可与系统语言不同，使用标准 Bundle 定位对应的编译后本地化资源。
    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for (language, region) in [("en", "en"), ("zh", "zh-Hans")] {
            if let path = Bundle.main.path(forResource: region, ofType: "lproj"),
               let bundle = Bundle(path: path) { result[language] = bundle }
        }
        return result
    }()

    static func text(_ key: String, _ arguments: Any...) -> String {
        format(key, language: language, arguments: arguments)
    }

    /// 查询和位置参数格式化均交给 Foundation，不再读取 JSON 或自行替换占位符。
    static func format(_ key: String, language: String, arguments: [Any] = []) -> String {
        let selected = resolve(language)
        let locale = Locale(identifier: selected == "zh" ? "zh-Hans" : "en")
        let bundle = bundles[selected] ?? bundles["en"] ?? .main
        let template = String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale)
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: locale,
                      arguments: arguments.map { String(describing: $0) as CVarArg })
    }
}
