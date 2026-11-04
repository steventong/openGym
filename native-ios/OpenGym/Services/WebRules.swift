import Foundation
import JavaScriptCore

/// Only the repository's pure calculation rules run here; every screen is SwiftUI.
@MainActor final class WebRules {
    static let shared = WebRules()
    private var context: JSContext?
    private var failure: String?
    private init() {
        guard let context = JSContext(), let url = Bundle.main.url(forResource:"web-rules",withExtension:"js"), let source = try? String(contentsOf:url,encoding:.utf8) else { failure = L10n.text("COULD_NOT_LOAD_WORKOUT_RULES" /* 无法加载训练规则。 */); return }
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in self?.failure = exception?.toString() ?? L10n.text("COULD_NOT_CALCULATE_WORKOUT_RULES" /* 训练规则计算失败。 */) }
        context.evaluateScript("if(typeof structuredClone==='undefined')globalThis.structuredClone=x=>JSON.parse(JSON.stringify(x));")
        context.evaluateScript(source)
    }
    func call(_ name:String, payload:[String:Any]) throws -> Any {
        guard let context else { throw APIError.response(0,failure ?? L10n.text("WORKOUT_RULES_ARE_UNAVAILABLE" /* 训练规则不可用。 */)) }
        failure = nil
        context.objectForKeyedSubscript("OpenGymRules")?.objectForKeyedSubscript("setLanguage")?.call(withArguments: [L10n.language])
        let data = try JSONSerialization.data(withJSONObject:payload)
        let result = context.objectForKeyedSubscript("OpenGymRules")?.objectForKeyedSubscript(name)?.call(withArguments:[String(decoding:data,as:UTF8.self)])
        guard failure == nil, let string = result?.toString(), let bytes = string.data(using:.utf8) else { throw APIError.response(0,failure ?? L10n.text("WORKOUT_RULES_RETURNED_INVALID_DATA" /* 训练规则返回无效数据。 */)) }
        return try JSONSerialization.jsonObject(with:bytes)
    }
}
