import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    private let translatedName: String
    var name: String { L10n.language == "en" && !english.isEmpty ? english : translatedName }
    let english: String
    let thumbnailAsset: String?
    let bodyPart: String
    let equipment: String
    let target: String
    let category: String
    private let translatedInstructions: [String]
    let englishInstructions: [String]?
    var instructions: [String] { L10n.language == "en" ? (englishInstructions ?? translatedInstructions) : translatedInstructions }
    let description: String
    enum CodingKeys: String, CodingKey {
        case id, translatedName = "name", english, thumbnailAsset, bodyPart, equipment, target, category
        case translatedInstructions = "instructions", englishInstructions, description
    }
    init(id: String, name: String, english: String, bodyPart: String, equipment: String,
         target: String, category: String, instructions: [String], description: String,
         englishInstructions: [String]? = nil, thumbnailAsset: String? = nil) {
        self.id = id; self.translatedName = name; self.english = english; self.thumbnailAsset = thumbnailAsset
        self.bodyPart = bodyPart; self.equipment = equipment; self.target = target
        self.category = category; self.translatedInstructions = instructions
        self.description = description; self.englishInstructions = englishInstructions
    }
    var bodyLabel: String { Vocabulary.label(bodyPart) }
    var equipmentLabel: String { Vocabulary.label(equipment) }
    var targetLabel: String { Vocabulary.label(target) }
    var searchText: String { "\(translatedName) \(english) \(bodyLabel) \(targetLabel)" }

    /// Keep imported gym suffixes out of the training title and copied name.
    var titleParts: (primary: String, secondary: String) {
        let importedName = name.components(separatedBy: " · ").first ?? name
        if id.hasPrefix("cimp"), let opening = importedName.firstIndex(of: "（"),
           let closing = importedName.lastIndex(of: "）"), opening < closing {
            return (String(importedName[importedName.index(after: opening)..<closing]),
                    String(importedName[..<opening]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if id.hasPrefix("cimp"), let opening = importedName.firstIndex(of: "("), importedName.hasSuffix(")") {
            return (String(importedName[..<opening]), String(importedName[importedName.index(after: opening)..<importedName.index(before: importedName.endIndex)]))
        }
        let translation = english.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, translation.isEmpty || translation == name ? "" : translation)
    }
    var recordName: String {
        let parts = titleParts
        return parts.secondary.isEmpty ? parts.primary : "\(parts.primary)(\(parts.secondary))"
    }
    var clipboardName: String {
        let parts = titleParts
        return parts.secondary.isEmpty ? parts.primary : "\(parts.primary)（\(parts.secondary)）"
    }

    func recordLabel(at index: Int) -> String { "\(index + 1).\(recordName)" }

    /// Server custom exercises use the web catalogue's compact keys, not the bundled JSON schema.
    static func custom(_ raw: [String: Any]) -> Exercise? {
        guard let id = raw["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let name = raw["n"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Exercise(id: id, name: name, english: "", bodyPart: raw["bp"] as? String ?? "",
                        equipment: raw["eq"] as? String ?? "", target: raw["tg"] as? String ?? "",
                        category: raw["cat"] as? String ?? "", instructions: [], description: raw["desc"] as? String ?? "")
    }
}

enum Vocabulary {
    static var words: [String: String] { ["back":L10n.text("BACK" /* 背部 */), "cardio":L10n.text("CARDIO_A" /* 有氧 */), "chest":L10n.text("CHEST" /* 胸部 */), "full body":L10n.text("FULL_BODY_A" /* 全身 */), "lower arms":L10n.text("LOWER_ARMS" /* 前臂 */), "lower legs":L10n.text("LOWER_LEGS" /* 小腿 */), "neck":L10n.text("NECK" /* 颈部 */), "shoulders":L10n.text("SHOULDERS" /* 肩部 */), "upper arms":L10n.text("UPPER_ARMS" /* 上臂 */), "upper legs":L10n.text("UPPER_LEGS" /* 大腿 */), "waist":L10n.text("WAIST" /* 腰腹 */), "body weight":L10n.text("BODY_WEIGHT_A" /* 自重 */), "dumbbell":L10n.text("DUMBBELL" /* 哑铃 */), "cable":L10n.text("CABLE" /* 绳索 */), "barbell":L10n.text("BARBELL" /* 杠铃 */), "leverage machine":L10n.text("LEVERAGE_MACHINE" /* 杠杆器械 */), "band":L10n.text("BAND" /* 弹力带 */), "kettlebell":L10n.text("KETTLEBELL" /* 壶铃 */), "smith machine":L10n.text("SMITH_MACHINE" /* 史密斯机 */), "weighted":L10n.text("WEIGHTED" /* 负重 */), "assisted":L10n.text("ASSISTED" /* 辅助 */), "resistance band":L10n.text("RESISTANCE_BAND" /* 阻力带 */), "lats":L10n.text("LATS" /* 背阔肌 */), "pectorals":L10n.text("PECTORALS" /* 胸肌 */), "abs":L10n.text("ABS" /* 腹肌 */), "quads":L10n.text("QUADS" /* 股四头肌 */), "glutes":L10n.text("GLUTES" /* 臀肌 */), "hamstrings":L10n.text("HAMSTRINGS" /* 腘绳肌 */), "biceps":L10n.text("BICEPS" /* 肱二头肌 */), "triceps":L10n.text("TRICEPS" /* 肱三头肌 */), "delts":L10n.text("DELTS" /* 三角肌 */), "calves":L10n.text("CALVES" /* 小腿肌 */), "forearms":L10n.text("FOREARMS" /* 前臂 */), "spine":L10n.text("SPINE" /* 脊柱 */), "traps":L10n.text("TRAPS" /* 斜方肌 */), "cardiovascular system":L10n.text("CARDIOVASCULAR_SYSTEM" /* 心血管系统 */), "strength":L10n.text("STRENGTH_A" /* 力量 */), "calisthenics":L10n.text("CALISTHENICS" /* 自重训练 */), "stretching":L10n.text("STRETCHING" /* 拉伸 */), "mobility":L10n.text("MOBILITY" /* 灵活性 */), "plyometrics":L10n.text("PLYOMETRICS" /* 增强式训练 */), "yoga":L10n.text("YOGA" /* 瑜伽 */), "pilates":L10n.text("PILATES" /* 普拉提 */), "olympic weightlifting":L10n.text("OLYMPIC" /* 奥林匹克举重 */), "isometric":L10n.text("ISOMETRIC" /* 等长训练 */), "bosu ball":L10n.text("BOSU_BALL" /* 波速球 */), "elliptical machine":L10n.text("ELLIPTICAL_MACHINE" /* 椭圆机 */), "ez barbell":L10n.text("EZ_BARBELL" /* 曲杆杠铃 */), "hammer":L10n.text("HAMMER" /* 锤 */), "landmine":L10n.text("LANDMINE" /* 地雷管 */), "macebell":L10n.text("MACEBELL" /* 锤铃 */), "medicine ball":L10n.text("MEDICINE_BALL" /* 药球 */), "olympic barbell":L10n.text("OLYMPIC_BARBELL" /* 奥杆 */), "roller":L10n.text("ROLLER" /* 滚轴 */), "rope":L10n.text("ROPE" /* 绳 */), "sandbag":L10n.text("SANDBAG" /* 沙袋 */), "skierg machine":L10n.text("SKIERG_MACHINE" /* 滑雪机 */), "sled machine":L10n.text("SLED_MACHINE" /* 雪橇 */), "stability ball":L10n.text("STABILITY_BALL" /* 健身球 */), "stationary bike":L10n.text("STATIONARY_BIKE" /* 动感单车 */), "stepmill machine":L10n.text("STEPMILL_MACHINE" /* 爬楼机 */), "suspension trainer":L10n.text("SUSPENSION_TRAINER" /* 悬挂训练带 */), "tire":L10n.text("TIRE" /* 轮胎 */), "trap bar":L10n.text("TRAP_BAR" /* 六角杠 */), "upper body ergometer":L10n.text("UPPER_BODY_ERGOMETER" /* 上肢功率车 */), "weight plate":L10n.text("WEIGHT_PLATE" /* 杠铃片 */), "wheel roller":L10n.text("WHEEL_ROLLER" /* 健腹轮 */)] }
    static func label(_ key: String) -> String { words[key] ?? key.capitalized }
}

struct Routine: Identifiable {
    var raw: [String: Any]
    var id: String { raw["id"] as? String ?? "" }
    var name: String { raw["name"] as? String ?? L10n.text("ROUTINES" /* 训练计划 */) }
    var exercises: [[String: Any]] { raw["ex"] as? [[String: Any]] ?? [] }
}

struct TrainingSet: Codable, Identifiable {
    var id = UUID().uuidString
    var weight: Double = 20
    var reps: Int = 10
    var done = false
    var completedAt: Double?
    var json: [String: Any] {
        var result: [String: Any] = ["w": weight, "r": reps, "done": done, "type": "work"]
        if let completedAt { result["at"] = completedAt }
        return result
    }
}
struct TrainingEntry: Codable, Identifiable {
    var id: String
    var name: String
    var sets: [TrainingSet]
    var routineID: String? = nil
    var restSec: Double? = nil
}
struct TrainingDraft: Codable, Identifiable {
    var id = UUID().uuidString
    var routineID: String?
    var name: String
    var start = Date()
    var entries: [TrainingEntry]
    var unit: String
    var routineIDs: [String]? = nil
    var webData: Data? = nil
    var completedSets: Int { webData == nil ? entries.flatMap(\.sets).filter(\.done).count : rawEntries.flatMap { $0["sets"] as? [[String:Any]] ?? [] }.filter(rawCompleted).count }
    // Matches the ordinary-set branch of frontend/src/lib/finish-workout.js:
    // a gap longer than 20 minutes ends the continuous session, but keeps all logged sets.
    func sessionEnd(now: Date) -> Double {
        let nowMS = now.timeIntervalSince1970 * 1000
        let ticks = entries.flatMap(\.sets).filter(\.done).compactMap(\.completedAt).filter(\.isFinite).sorted()
        guard var reach = ticks.first else { return nowMS }
        let gap = 20.0 * 60 * 1000
        for tick in ticks.dropFirst() {
            if tick - reach > gap { break }
            reach = max(reach, tick)
        }
        return nowMS - reach > gap ? reach : nowMS
    }
    func workoutJSON(now: Date = Date()) -> [String: Any] {
        ["id": id, "d": dayString(start), "start": start.timeIntervalSince1970 * 1000, "end": sessionEnd(now: now),
         "name": name, "routineId": routineID as Any? ?? NSNull(), "routineIds": routineIDs ?? routineID.map { [$0] } ?? [], "prs": [],
         "entries": entries.filter { $0.sets.contains(where: \.done) }.map { entry -> [String: Any] in
             var raw: [String:Any] = ["id": entry.id, "sets": entry.sets.map(\.json)]
             if let rid = entry.routineID { raw["rid"] = rid }
             return raw
         }]
    }
}
func dayString(_ date: Date = Date()) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
}
func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }
func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
