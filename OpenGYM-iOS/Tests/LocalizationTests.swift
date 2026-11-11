import XCTest
import SwiftUI
import UIKit
@testable import OpenGYM

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

    func testAutomaticRestSettingsResolveInBothLanguages() {
        for (language, expected) in [("en", "Automatically end rest"), ("zh", "自动结束休息")] {
            let bundle = AppLanguage.bundle(for: language)
            let locale = AppLanguage.locale(for: language)
            XCTAssertEqual(String(localized: "AUTO_END_REST", bundle: bundle, locale: locale), expected)
            for key in ["APPLE_WATCH", "AUTO_END_REST_INFO", "AUTO_END_REST_IS_OFF"] {
                XCTAssertNotEqual(String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale), key)
            }
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

    func testSharedUIControlsResolveKeysInBothLanguages() throws {
        let key: LocalizedStringKey = "CANCEL"
        for (language, expected) in [("en", "Cancel"), ("zh-Hans", "取消")] {
            let locale = Locale(identifier: language)
            try assertLocalized(key, expected: expected, locale: locale) { GreenButton(title: $0) {} }
            try assertLocalized(key, expected: expected, locale: locale) { Pill(title: $0) {} }
            try assertLocalized(key, expected: expected, locale: locale) { SectionTitle(text: $0) }
            try assertLocalized(key, expected: expected, locale: locale) { EmptyCard(icon: "dumbbell", title: $0) }
            try assertLocalized(key, expected: expected, locale: locale) { StatsMetricCard(value: "24", label: $0, icon: "dumbbell") }
            try assertLocalized(key, expected: expected, locale: locale) { CoachTextList(title: $0, items: ["CANCEL 50% {0}"], symbol: "dumbbell") }
        }
    }

    func testDynamicTitlesThatLookLikeKeysAreNotTranslatedAgain() throws {
        for language in ["en", "zh-Hans"] {
            let locale = Locale(identifier: language)
            for name in ["CANCEL", "HEART_RATE"] {
                let literal = GreenButton(title: "\(name)") {}
                let translated = GreenButton(title: LocalizedStringKey(name)) {}
                XCTAssertNotEqual(try renderLocalized(literal, locale: locale),
                                  try renderLocalized(translated, locale: locale), name)
                let row = ScheduleSelectionRow(title: "\(name)", selected: false, icon: "dumbbell")
                let translatedRow = ScheduleSelectionRow(title: LocalizedStringKey(name), selected: false, icon: "dumbbell")
                XCTAssertNotEqual(try renderLocalized(row, locale: locale),
                                  try renderLocalized(translatedRow, locale: locale), name)
            }
            for title in ["CANCEL", "HEART_RATE", "50% {0} %@", "我的动作 \\(name)"] {
                let field = AdvancedSetInputField(title: "\(title)", text: .constant("12"), compact: false,
                    setLabel: "Set 1", identifier: "literal-title", height: 44, disabled: false)
                XCTAssertEqual(String(localized: field.title, bundle: AppLanguage.bundle(for: language),
                                      locale: AppLanguage.locale(for: language)), title)
            }
        }
    }

    func testInputKeysFollowLanguageChangesWithoutChangingLiteralContents() async throws {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        let raw = "HEART_RATE 50% {0}"
        let fields = VStack {
            BufferedTextField("EXERCISE_NAME", text: .constant(raw))
            BufferedNumberField("WEIGHT", value: .constant(12.5))
            ExerciseSearchField("SEARCH_EXERCISES", text: .constant(raw))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: fields.environment(\.locale, AppLanguage.locale))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for language in ["en", "zh"] {
            AppLanguage.preferences.language = language
            controller.rootView = fields.environment(\.locale, AppLanguage.locale)
            try await Task.sleep(for: .milliseconds(150))
            controller.view.layoutIfNeeded()
            let inputs = nativeTextFields(in: controller.view)
            XCTAssertEqual(inputs.count, 3)
            guard inputs.count == 3 else { continue }
            for (input, key) in zip(inputs, ["EXERCISE_NAME", "WEIGHT", "SEARCH_EXERCISES"]) {
                XCTAssertEqual(input.placeholder, String(localized: String.LocalizationValue(key),
                    bundle: AppLanguage.bundle, locale: AppLanguage.locale), key)
            }
            XCTAssertEqual(inputs[0].text, raw)
            XCTAssertEqual(inputs[2].text, raw)
        }
    }

    func testSharedContentUsesSnapshotLocaleInsteadOfAmbientLocale() throws {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        for language in ["en", "zh"] {
            AppLanguage.preferences.language = language == "en" ? "zh" : "en"
            let content = TrainingContentData(exercise: "Exercise", position: "1/3", summary: nil,
                action: .init(title: "CANCEL", symbol: "checkmark", status: .workout(startedAt: nil)),
                locale: AppLanguage.locale(for: language))
            let view = TrainingContentView(content: content, layout: .compact, metrics: EmptyView(),
                primaryAction: TrainingActionLabel(title: "CANCEL", symbol: "checkmark", status: .workout(startedAt: nil),
                    disabled: false, tint: .green))
            XCTAssertEqual(try renderLocalized(view, locale: AppLanguage.locale(for: language)),
                           try renderLocalized(view, locale: AppLanguage.locale), language)
        }
    }

    private func assertLocalized<Content: View>(_ key: LocalizedStringKey, expected: String, locale: Locale,
                                                file: StaticString = #filePath, line: UInt = #line,
                                                content: (LocalizedStringKey) -> Content) throws {
        XCTAssertEqual(try renderLocalized(content(key), locale: locale),
                       try renderLocalized(content("\(expected)"), locale: locale),
                       locale.identifier, file: file, line: line)
    }

    private func renderLocalized<Content: View>(_ content: Content, locale: Locale) throws -> Data {
        let renderer = ImageRenderer(content: content
            .frame(width: 320, height: 200).foregroundStyle(.white).background(.black)
            .environment(\.locale, locale).environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .large))
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }

    private func nativeTextFields(in view: UIView) -> [UITextField] {
        if let input = view as? UITextField { return [input] }
        return view.subviews.flatMap { nativeTextFields(in: $0) }
    }

    func testBothBundledCatalogsResolveAndPreserveArguments() {
        XCTAssertEqual(String(localized: "CANCEL", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), "Cancel") // 取消
        XCTAssertEqual(String(localized: "CANCEL", bundle: AppLanguage.bundle(for: "zh-Hans"), locale: AppLanguage.locale(for: "zh-Hans")), "取消") // 取消
        XCTAssertEqual(String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: 2), String(describing: 4)), "Set 2 of 4") // 训练组位置
        XCTAssertEqual(String(format: String(localized: "SET_COUNT_OF_COUNT", bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), locale: AppLanguage.locale(for: "zh"), String(describing: 2), String(describing: 4)), "第 2/4 组") // 训练组位置
        XCTAssertEqual(String(format: String(localized: "INCLINE_COUNT", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: "5%")), " · Incline 5%%") // 百分号与参数不被重复解析
        XCTAssertEqual(String(format: String(localized: "ADMIN_LOGIN_NAME_OR_EMAIL", bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), locale: AppLanguage.locale(for: "en"), String(describing: "{1}"), String(describing: "a@example.com")), "{1} (or sign-in email a@example.com)") // 参数不再次展开
    }

    func testSettingsSyncFeedbackResolvesInBothLanguages() {
        for (key, english, chinese) in [
            ("SYNC_SUCCEEDED", "Sync succeeded", "同步成功"),
            ("SYNC_FAILED", "Sync failed", "同步失败")
        ] {
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), english)
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), chinese)
        }
    }

    func testHistoryHealthActionsResolveInBothLanguages() {
        for (key, english, chinese) in [
            ("SYNC_TO_APPLE_HEALTH", "Sync to Apple Health", "同步到 Apple 健康"),
            ("HEALTH_HISTORY_SYNC_COMPLETE", "Workout synced to Apple Health.", "训练已同步到 Apple 健康。"),
            ("SAVE", "Save", "保存"),
            ("SUBMITTING", "Submitting", "提交中")
        ] {
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), english)
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), chinese)
        }
        for language in ["en", "zh"] {
            for key in ["AUTOMATIC_WORKOUT_SYNC_INFO", "HEALTH_HISTORY_SYNC_CONFIRMATION", "HEALTH_HISTORY_CHECK_BEFORE_RETRY", "HEALTH_HISTORY_INVALID_RECORD", "HEALTH_HISTORY_INVALID_TIME", "HEALTH_HISTORY_SYNC_IN_PROGRESS"] {
                XCTAssertNotEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language)), key)
            }
        }
    }

    func testHistoryTabLabelsResolveInBothLanguages() {
        for (key, english, chinese) in [
            ("HISTORY", "History", "历史"),
            ("STATS", "Stats", "统计"),
            ("LIST", "List", "列表")
        ] {
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "en"), locale: AppLanguage.locale(for: "en")), english)
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: "zh"), locale: AppLanguage.locale(for: "zh")), chinese)
        }
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

    func testSemanticDisplayTemplatesPreserveArgumentsInBothLanguages() {
        let templates: [(String, [String], String, String)] = [
            ("CHARACTER_COUNT_PROGRESS", ["12", "600"], "12 / 600", "12 / 600"),
            ("COACH_INTAKE_PROGRESS", ["2", "7"], "2 / 7", "2 / 7"),
            ("COACH_WORKOUT_SCORE", ["8.5", "10"], "8.5 / 10", "8.5 / 10"),
            ("COACH_SCHEDULE_ENTRY", ["Monday", "Upper body"], "Monday · Upper body", "Monday · Upper body"),
            ("NUMBERED_EXERCISE", ["2", "Squat"], "2. Squat", "2. Squat"),
            ("EXERCISE_TARGET_AND_EQUIPMENT", ["Chest", "Barbell"], "Chest · Barbell", "Chest · Barbell"),
            ("WORKOUT_DATE_AND_NAME", ["2026-11-07", "Workout"], "2026-11-07 · Workout", "2026-11-07 · Workout"),
            ("HEALTH_METRIC_TITLE_AND_UNIT", ["Heart rate", "bpm"], "Heart rate·bpm", "Heart rate·bpm"),
            ("HEALTH_METRIC_ACCESSIBILITY_VALUE", ["Heart rate", "120"], "Heart rate, 120", "Heart rate，120"),
            ("SET_INPUT_ACCESSIBILITY_LABEL", ["Set 1", "Reps"], "Set 1 Reps", "Set 1 Reps"),
            ("WARM_UP_SET_ACCESSIBILITY_LABEL", ["Set 1", "Warm-up"], "Set 1 Warm-up", "Set 1 Warm-up"),
            ("COUNT_PERSONAL_RECORDS_BADGE", ["2"], "2 PR", "2 PR"),
            ("DEFAULT_ROUTINE_SETS_REPS", ["3", "10"], "3 × 10", "3 × 10"),
            ("BULLETED_LIST_ITEM", ["Keep training"], "• Keep training", "• Keep training")
        ]
        for (key, arguments, english, chinese) in templates {
            for (language, expected) in [("en", english), ("zh", chinese)] {
                let format = String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language))
                XCTAssertEqual(String(format: format, locale: AppLanguage.locale(for: language), arguments: arguments.map { $0 as CVarArg }), expected, key)
            }
        }
        for language in ["en", "zh"] {
            XCTAssertEqual(String(localized: "LOCAL_SAVE_ERROR_BADGE", bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language)), "!")
        }
    }

    func testPhoneCopyResolvesInBothLanguages() {
        for (key, english, chinese) in [
            ("START_A_WORKOUT_ON_PHONE", "Start a workout on phone", "在手机开始训练"),
            ("ADD_EXERCISES_ON_IPHONE", "Add exercises on phone", "在手机添加动作"),
            ("SAVE_ON_IPHONE", "Save on phone", "请在手机保存"),
            ("OPEN_OPENGYM_ON_IPHONE", "Open openGym on phone", "请打开手机上的 openGym")
        ] {
            for (language, expected) in [("en", english), ("zh", chinese)] {
                XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: AppLanguage.bundle(for: language), locale: AppLanguage.locale(for: language)), expected, key)
            }
        }
    }

    func testLanguageSwitchPreservesConfiguredExerciseContentAndLocalizesUIVocabulary() {
        let original = AppLanguage.preferences.language
        defer { AppLanguage.preferences.language = original }
        let builtIn = Exercise(id: "0001", name: "杠铃卧推", english: "barbell bench press", bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: ["平躺在训练凳上。"], description: "", englishInstructions: ["Lie on the bench."])
        let custom = Exercise(id: "custom", name: "我的动作 A", english: "", bodyPart: "chest", equipment: "barbell", target: "pectorals", category: "strength", instructions: [], description: "")
        AppLanguage.preferences.language = "zh"
        XCTAssertEqual(builtIn.name, "杠铃卧推")
        XCTAssertEqual(builtIn.instructions, ["平躺在训练凳上。"])
        XCTAssertEqual(builtIn.equipmentLabel, "杠铃")
        AppLanguage.preferences.language = "en"
        XCTAssertEqual(builtIn.name, "杠铃卧推")
        XCTAssertEqual(builtIn.instructions, ["平躺在训练凳上。"])
        XCTAssertEqual(builtIn.equipmentLabel.lowercased(), "barbell")
        XCTAssertEqual(custom.name, "我的动作 A")
        XCTAssertTrue(builtIn.searchText.contains("杠铃卧推"))
        XCTAssertTrue(builtIn.searchText.contains("barbell bench press"))
        let searchText = builtIn.searchText
        AppLanguage.preferences.language = "zh"
        XCTAssertEqual(builtIn.searchText, searchText)
    }

    func testCatalogueIdentifiersResolveUsingNativeStringTables() {
        for (language, equipment, muscle) in [("en", "Barbell", "Traps"), ("zh", "杠铃", "斜方肌")] {
            let bundle = AppLanguage.bundle(for: language)
            let locale = AppLanguage.locale(for: language)
            XCTAssertEqual(String(localized: "barbell", table: "Vocabulary", bundle: bundle, locale: locale).lowercased(), equipment.lowercased())
            XCTAssertEqual(String(localized: "trapezius", table: "Muscles", bundle: bundle, locale: locale).lowercased(), muscle.lowercased())
            XCTAssertEqual(String(localized: "custom-equipment", table: "Vocabulary", bundle: bundle, locale: locale), "custom-equipment")
        }
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
