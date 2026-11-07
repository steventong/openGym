import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    private let translatedName: String
    var name: String { translatedName }
    let english: String
    let thumbnailAsset: String?
    let bodyPart: String
    let equipment: String
    let target: String
    let category: String
    private let translatedInstructions: [String]
    let englishInstructions: [String]?
    var instructions: [String] { translatedInstructions }
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
    var bodyLabel: String { String(localized: String.LocalizationValue(bodyPart), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    var equipmentLabel: String { String(localized: String.LocalizationValue(equipment), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    var targetLabel: String { String(localized: String.LocalizationValue(target), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    var searchText: String { "\(name) \(english) \(bodyPart) \(target) \(equipment)" }

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
