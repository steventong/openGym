import Foundation
import Observation

/// Account language preferences and resource selection. Text lookup and formatting use Apple APIs directly.
enum AppLanguage {
    @Observable final class Preferences {
        var language: String = resolve(UserDefaults.standard.string(forKey: "opengym.language"))
    }
    static let preferences = Preferences()
    static var language: String { preferences.language }
    static var locale: Locale { locale(for: language) }
    static var bundle: Bundle { bundle(for: language) }

    static func locale(for language: String) -> Locale {
        Locale(identifier: resolve(language) == "zh" ? "zh-Hans" : "en")
    }

    static func bundle(for language: String) -> Bundle {
        bundles[resolve(language)] ?? bundles["en"] ?? .main
    }

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

}
