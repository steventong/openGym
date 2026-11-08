import Foundation
import JavaScriptCore

/// Only the repository's pure calculation rules run here; every screen is SwiftUI.
@MainActor final class WebRules {
    static let shared = WebRules()
    private var context: JSContext?
    private var failure: String?
    private init() {
        guard let context = JSContext(), let url = Bundle.main.url(forResource:"web-rules",withExtension:"js"), let source = try? String(contentsOf:url,encoding:.utf8) else { failure = String(localized: "COULD_NOT_LOAD_WORKOUT_RULES", bundle: AppLanguage.bundle, locale: AppLanguage.locale); return }
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in self?.failure = exception?.toString() ?? String(localized: "COULD_NOT_CALCULATE_WORKOUT_RULES", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        context.evaluateScript("if(typeof structuredClone==='undefined')globalThis.structuredClone=x=>JSON.parse(JSON.stringify(x));")
        context.evaluateScript(source)
    }
    func call(_ name:String, payload:[String:Any]) throws -> Any {
        guard let context else { throw APIError.response(0,failure ?? String(localized: "WORKOUT_RULES_ARE_UNAVAILABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        failure = nil
        context.objectForKeyedSubscript("OpenGymRules")?.objectForKeyedSubscript("setLanguage")?.call(withArguments: [AppLanguage.language])
        let data = try JSONSerialization.data(withJSONObject:payload)
        let result = context.objectForKeyedSubscript("OpenGymRules")?.objectForKeyedSubscript(name)?.call(withArguments:[String(decoding:data,as:UTF8.self)])
        guard failure == nil, let string = result?.toString(), let bytes = string.data(using:.utf8) else { throw APIError.response(0,failure ?? String(localized: "WORKOUT_RULES_RETURNED_INVALID_DATA", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        return try JSONSerialization.jsonObject(with:bytes)
    }
}
