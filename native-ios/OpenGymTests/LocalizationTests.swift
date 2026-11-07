import XCTest
import SwiftUI
@testable import OpenGym

@MainActor final class LocalizationTests: XCTestCase {
    func testUsesCompiledAppleResourcesWithoutRuntimeJSON() throws {
        XCTAssertNil(Bundle.main.url(forResource: "en", withExtension: "json"))
        XCTAssertNil(Bundle.main.url(forResource: "zh", withExtension: "json"))
        for (language, region, expected) in [("en", "en", "Cancel"), ("zh", "zh-Hans", "取消")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: region, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "strings"))
            XCTAssertEqual(String(localized: "CANCEL", bundle: bundle, locale: Locale(identifier: region)), expected)
            XCTAssertEqual(String(localized: "CANCEL", bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language)), expected)
            XCTAssertNotEqual(bundle.localizedString(forKey: "NSHealthShareUsageDescription", value: nil, table: "InfoPlist"), "NSHealthShareUsageDescription")
            XCTAssertNotEqual(bundle.localizedString(forKey: "UPDATE_CURRENT_WORKOUT", value: nil, table: "Localizable"), "UPDATE_CURRENT_WORKOUT")
        }
    }

    func testSwiftUIKeysFollowLocaleWithoutTranslationWrapper() throws {
        for (region, expected) in [("en", "Cancel"), ("zh-Hans", "取消")] {
            func render(_ text: Text) throws -> Data {
                let renderer = ImageRenderer(content: text
                    .font(.system(size: 24)).foregroundStyle(.black)
                    .frame(width: 180, height: 50).background(.white)
                    .environment(\.locale, Locale(identifier: region)))
                return try XCTUnwrap(renderer.uiImage?.pngData())
            }
            XCTAssertEqual(try render(Text("CANCEL")), try render(Text(verbatim: expected)), region)
        }
    }

    func testBothBundledCatalogsResolveAndPreserveArguments() {
        XCTAssertEqual(String(localized: "CANCEL", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), "Cancel") // 取消
        XCTAssertEqual(String(localized: "CANCEL", bundle: AppLanguage.bundle(for: "zh-Hans"), locale: AppLanguage.locale(for: "zh-Hans")), "取消") // 取消
        XCTAssertEqual(String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: 2), String(describing: 4)), "Set 2 of 4") // 训练组位置
        XCTAssertEqual(String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), locale: AppLanguage.locale(for: "zh"), String(describing: 2), String(describing: 4)), "第 2/4 组") // 训练组位置
        XCTAssertEqual(String(format: String(localized: "INCLINE_COUNT", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: "5%")), " · Incline 5%%") // 百分号与参数不被重复解析
        XCTAssertEqual(String(format: String(localized: "ADMIN_LOGIN_NAME_OR_EMAIL", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: "{1}"), String(describing: "a@example.com")), "{1} (or sign-in email a@example.com)") // 参数不再次展开
    }

    func testExercisePagingCopyResolvesInBothLanguages() {
        for (key, english, chinese) in [
            ("PREVIOUS_EXERCISE_NAMED", "Previous exercise: Squat", "上一个动作：深蹲"),
            ("NEXT_EXERCISE_NAMED", "Next exercise: Squat", "下一个动作：深蹲")
        ] {
            XCTAssertEqual(String(format: String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: "Squat")), english)
            XCTAssertEqual(String(format: String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), locale: AppLanguage.locale(for: "zh"), String(describing: "深蹲")), chinese)
        }
        for (key, english, chinese) in [
            ("KEEP_PULLING_DOWN_TO_VIEW", "Keep pulling down to view", "继续下拉查看"),
            ("KEEP_PULLING_UP_TO_VIEW", "Keep pulling up to view", "继续上拉查看"),
            ("RELEASE_TO_SWITCH_EXERCISE", "Release to switch", "松开切换")
        ] {
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), english)
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), chinese)
        }
    }

    func testLanguageSwitchUpdatesExerciseAndVocabularyWithoutChangingUserContent() {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        let builtIn = Exercise(id: "0001", name: "杠铃卧推", english: "barbell bench press", bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: ["平躺在训练凳上。"], description: "", englishInstructions: ["Lie on the bench."])
        let custom = Exercise(id: "custom", name: "我的动作 A", english: "", bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: [], description: "")
        AppLanguage.preferences.language = "zh"
        XCTAssertEqual(builtIn.name, "杠铃卧推")
        XCTAssertEqual(builtIn.instructions, ["平躺在训练凳上。"])
        XCTAssertEqual(builtIn.equipmentLabel, "杠铃")
        AppLanguage.preferences.language = "en"
        XCTAssertEqual(builtIn.name, "barbell bench press")
        XCTAssertEqual(builtIn.instructions, ["Lie on the bench."])
        XCTAssertEqual(builtIn.equipmentLabel.lowercased(), "barbell")
        XCTAssertEqual(custom.name, "我的动作 A")
        XCTAssertTrue(builtIn.searchText.contains("杠铃卧推"))
    }

    func testRulesKeepSelectedLanguageAfterOpeningCoach() throws {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        for language in ["en", "zh"] {
            AppLanguage.preferences.language = language
            _ = try WebRules.shared.call("coachInfo", payload: ["state": [:]])
            XCTAssertThrowsError(try WebRules.shared.call("validatePersonalConfig", payload: ["config": ["id": "0025", "prog": "linear", "inc": 0]])) { error in
                XCTAssertTrue(error.localizedDescription.contains(String(localized: "RULE_INCREMENT_POSITIVE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
            }
        }
    }

    func testWatchLanguageFieldIsBackwardCompatible() throws {
        let data = try JSONEncoder().encode(WatchTrainingSnapshot(language: "zh"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "language")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(WatchTrainingSnapshot.self, from: oldData).language)
        XCTAssertEqual(try JSONDecoder().decode(WatchTrainingSnapshot.self, from: data).language, "zh")
    }
}
