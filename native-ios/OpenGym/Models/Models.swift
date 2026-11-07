import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    private let translatedName: String
    var name: String { AppLanguage.language == "en" && !english.isEmpty ? english : translatedName }
    let english: String
    let thumbnailAsset: String?
    let bodyPart: String
    let equipment: String
    let target: String
    let category: String
    private let translatedInstructions: [String]
    let englishInstructions: [String]?
    var instructions: [String] { AppLanguage.language == "en" ? (englishInstructions ?? translatedInstructions) : translatedInstructions }
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
    static var words: [String: String] { ["back":String(localized: "BACK", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "cardio":String(localized: "CARDIO_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "chest":String(localized: "CHEST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "full body":String(localized: "FULL_BODY_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "lower arms":String(localized: "LOWER_ARMS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "lower legs":String(localized: "LOWER_LEGS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "neck":String(localized: "NECK", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "shoulders":String(localized: "SHOULDERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "upper arms":String(localized: "UPPER_ARMS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "upper legs":String(localized: "UPPER_LEGS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "waist":String(localized: "WAIST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "body weight":String(localized: "BODY_WEIGHT_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "dumbbell":String(localized: "DUMBBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "cable":String(localized: "CABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "barbell":String(localized: "BARBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "leverage machine":String(localized: "LEVERAGE_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "band":String(localized: "BAND", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "kettlebell":String(localized: "KETTLEBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "smith machine":String(localized: "SMITH_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "weighted":String(localized: "WEIGHTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "assisted":String(localized: "ASSISTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "resistance band":String(localized: "RESISTANCE_BAND", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "lats":String(localized: "LATS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "pectorals":String(localized: "PECTORALS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "abs":String(localized: "ABS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "quads":String(localized: "QUADS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "glutes":String(localized: "GLUTES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "hamstrings":String(localized: "HAMSTRINGS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "biceps":String(localized: "BICEPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "triceps":String(localized: "TRICEPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "delts":String(localized: "DELTS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "calves":String(localized: "CALVES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "forearms":String(localized: "FOREARMS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "spine":String(localized: "SPINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "traps":String(localized: "TRAPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "cardiovascular system":String(localized: "CARDIOVASCULAR_SYSTEM", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "strength":String(localized: "STRENGTH_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "calisthenics":String(localized: "CALISTHENICS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "stretching":String(localized: "STRETCHING", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "mobility":String(localized: "MOBILITY", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "plyometrics":String(localized: "PLYOMETRICS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "yoga":String(localized: "YOGA", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "pilates":String(localized: "PILATES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "olympic weightlifting":String(localized: "OLYMPIC", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "isometric":String(localized: "ISOMETRIC", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "bosu ball":String(localized: "BOSU_BALL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "elliptical machine":String(localized: "ELLIPTICAL_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "ez barbell":String(localized: "EZ_BARBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "hammer":String(localized: "HAMMER", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "landmine":String(localized: "LANDMINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "macebell":String(localized: "MACEBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "medicine ball":String(localized: "MEDICINE_BALL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "olympic barbell":String(localized: "OLYMPIC_BARBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "roller":String(localized: "ROLLER", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "rope":String(localized: "ROPE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "sandbag":String(localized: "SANDBAG", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "skierg machine":String(localized: "SKIERG_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "sled machine":String(localized: "SLED_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "stability ball":String(localized: "STABILITY_BALL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "stationary bike":String(localized: "STATIONARY_BIKE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "stepmill machine":String(localized: "STEPMILL_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "suspension trainer":String(localized: "SUSPENSION_TRAINER", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "tire":String(localized: "TIRE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "trap bar":String(localized: "TRAP_BAR", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "upper body ergometer":String(localized: "UPPER_BODY_ERGOMETER", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "weight plate":String(localized: "WEIGHT_PLATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), "wheel roller":String(localized: "WHEEL_ROLLER", bundle: AppLanguage.bundle, locale: AppLanguage.locale)] }
    static func label(_ key: String) -> String { words[key] ?? key.capitalized }
}

struct Routine: Identifiable {
    var raw: [String: Any]
    var id: String { raw["id"] as? String ?? "" }
    var name: String { raw["name"] as? String ?? String(localized: "ROUTINES", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
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
