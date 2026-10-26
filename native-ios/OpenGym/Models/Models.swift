import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let english: String
    let bodyPart: String
    let equipment: String
    let target: String
    let category: String
    let instructions: [String]
    let description: String
    var bodyLabel: String { Vocabulary.label(bodyPart) }
    var equipmentLabel: String { Vocabulary.label(equipment) }
    var targetLabel: String { Vocabulary.label(target) }
    var searchText: String { "\(name) \(english) \(bodyLabel) \(targetLabel)" }

    /// A session label does not include the gym suffix used to distinguish imported IDs.
    var recordName: String {
        // Remove the suffix before parsing: 档位（非kg） is not part of the translation.
        let importedName = name.components(separatedBy: " · ").first ?? name
        if id.hasPrefix("cimp"), let opening = importedName.firstIndex(of: "（"),
           let closing = importedName.lastIndex(of: "）"), opening < closing {
            let chinese = String(importedName[importedName.index(after: opening)..<closing])
            let english = String(importedName[..<opening]).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(chinese)(\(english))"
        }
        let english = english.trimmingCharacters(in: .whitespacesAndNewlines)
        return english.isEmpty || english == name ? name : "\(name)(\(english))"
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
    static let words = ["back":"背部", "cardio":"有氧", "chest":"胸部", "full body":"全身", "lower arms":"前臂", "lower legs":"小腿", "neck":"颈部", "shoulders":"肩部", "upper arms":"上臂", "upper legs":"大腿", "waist":"腰腹", "body weight":"自重", "dumbbell":"哑铃", "cable":"绳索", "barbell":"杠铃", "leverage machine":"杠杆器械", "band":"弹力带", "kettlebell":"壶铃", "smith machine":"史密斯机", "weighted":"负重", "assisted":"辅助", "resistance band":"阻力带", "lats":"背阔肌", "pectorals":"胸肌", "abs":"腹肌", "quads":"股四头肌", "glutes":"臀肌", "hamstrings":"腘绳肌", "biceps":"肱二头肌", "triceps":"肱三头肌", "delts":"三角肌", "calves":"小腿", "forearms":"前臂", "spine":"竖脊肌", "traps":"斜方肌", "cardiovascular system":"心肺", "strength":"力量", "calisthenics":"自重训练", "stretching":"拉伸", "mobility":"灵活性", "plyometrics":"增强式训练", "yoga":"瑜伽", "pilates":"普拉提", "olympic weightlifting":"奥林匹克举重", "isometric":"等长训练", "bosu ball":"波速球", "elliptical machine":"椭圆机", "ez barbell":"曲杆杠铃", "hammer":"锤", "landmine":"地雷管", "macebell":"锤铃", "medicine ball":"药球", "olympic barbell":"奥杆", "roller":"滚轴", "rope":"绳", "sandbag":"沙袋", "skierg machine":"滑雪机", "sled machine":"雪橇", "stability ball":"健身球", "stationary bike":"动感单车", "stepmill machine":"爬楼机", "suspension trainer":"悬挂训练带", "tire":"轮胎", "trap bar":"六角杠", "upper body ergometer":"上肢功率车", "weight plate":"杠铃片", "wheel roller":"健腹轮"]
    static func label(_ key: String) -> String { words[key] ?? key.capitalized }
}

struct Routine: Identifiable {
    var raw: [String: Any]
    var id: String { raw["id"] as? String ?? "" }
    var name: String { raw["name"] as? String ?? "训练计划" }
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
