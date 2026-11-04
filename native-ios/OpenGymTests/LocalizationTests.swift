import XCTest
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
            XCTAssertEqual(L10n.format("CANCEL", language: language), expected)
            XCTAssertNotEqual(bundle.localizedString(forKey: "NSHealthShareUsageDescription", value: nil, table: "InfoPlist"), "NSHealthShareUsageDescription")
            XCTAssertNotEqual(bundle.localizedString(forKey: "UPDATE_CURRENT_WORKOUT", value: nil, table: "Localizable"), "UPDATE_CURRENT_WORKOUT")
        }
    }

    func testBothBundledCatalogsResolveAndPreserveArguments() {
        XCTAssertEqual(L10n.format("CANCEL", language: "en"), "Cancel") // 取消
        XCTAssertEqual(L10n.format("CANCEL", language: "zh-Hans"), "取消") // 取消
        XCTAssertEqual(L10n.format("SET_COUNT_OF_COUNT", language: "en", arguments: [2, 4]), "Set 2 of 4") // 训练组位置
        XCTAssertEqual(L10n.format("SET_COUNT_OF_COUNT", language: "zh", arguments: [2, 4]), "第 2/4 组") // 训练组位置
        XCTAssertEqual(L10n.format("INCLINE_COUNT", language: "en", arguments: ["5%"]), " · Incline 5%%") // 百分号与参数不被重复解析
        XCTAssertEqual(L10n.format("ADMIN_LOGIN_NAME_OR_EMAIL", language: "en", arguments: ["{1}", "a@example.com"]), "{1} (or sign-in email a@example.com)") // 参数不再次展开
    }

    func testExercisePagingCopyResolvesInBothLanguages() {
        for (key, english, chinese) in [
            ("PREVIOUS_EXERCISE_NAMED", "Previous exercise: Squat", "上一个动作：深蹲"),
            ("NEXT_EXERCISE_NAMED", "Next exercise: Squat", "下一个动作：深蹲")
        ] {
            XCTAssertEqual(L10n.format(key, language: "en", arguments: ["Squat"]), english)
            XCTAssertEqual(L10n.format(key, language: "zh", arguments: ["深蹲"]), chinese)
        }
        for (key, english, chinese) in [
            ("KEEP_PULLING_DOWN_TO_VIEW", "Keep pulling down to view", "继续下拉查看"),
            ("KEEP_PULLING_UP_TO_VIEW", "Keep pulling up to view", "继续上拉查看"),
            ("RELEASE_TO_SWITCH_EXERCISE", "Release to switch", "松开切换")
        ] {
            XCTAssertEqual(L10n.format(key, language: "en"), english)
            XCTAssertEqual(L10n.format(key, language: "zh"), chinese)
        }
    }

    func testLanguageSwitchUpdatesExerciseAndVocabularyWithoutChangingUserContent() {
        let original = L10n.preferences.language
        defer { L10n.preferences.language = original }
        let builtIn = Exercise(id: "0001", name: "杠铃卧推", english: "barbell bench press", bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: ["平躺在训练凳上。"], description: "", englishInstructions: ["Lie on the bench."])
        let custom = Exercise(id: "custom", name: "我的动作 A", english: "", bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: [], description: "")
        L10n.preferences.language = "zh"
        XCTAssertEqual(builtIn.name, "杠铃卧推")
        XCTAssertEqual(builtIn.instructions, ["平躺在训练凳上。"])
        XCTAssertEqual(builtIn.equipmentLabel, "杠铃")
        L10n.preferences.language = "en"
        XCTAssertEqual(builtIn.name, "barbell bench press")
        XCTAssertEqual(builtIn.instructions, ["Lie on the bench."])
        XCTAssertEqual(builtIn.equipmentLabel.lowercased(), "barbell")
        XCTAssertEqual(custom.name, "我的动作 A")
        XCTAssertTrue(builtIn.searchText.contains("杠铃卧推"))
    }

    func testRulesKeepSelectedLanguageAfterOpeningCoach() throws {
        let original = L10n.preferences.language
        defer { L10n.preferences.language = original }
        for language in ["en", "zh"] {
            L10n.preferences.language = language
            _ = try WebRules.shared.call("coachInfo", payload: ["state": [:]])
            XCTAssertThrowsError(try WebRules.shared.call("validatePersonalConfig", payload: ["config": ["id": "0025", "prog": "linear", "inc": 0]])) { error in
                XCTAssertTrue(error.localizedDescription.contains(L10n.text("RULE_INCREMENT_POSITIVE" /* 进阶步进必须大于零 */)))
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
