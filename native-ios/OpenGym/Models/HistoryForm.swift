import Foundation

struct HistoryEntryDraft: Identifiable {
    var id = UUID()
    var raw: [String: Any]
    var sets: [RawRow]
    init(_ raw: [String: Any]) { self.raw = raw; sets = (raw["sets"] as? [[String: Any]] ?? []).map { RawRow(raw: $0) } }
    @MainActor mutating func addSet() throws {
        let copied = try WebRules.shared.call("copyAdvancedSet", payload: ["sets": sets.map(\.raw), "target": raw["target"] as? [String: Any] ?? [:], "editing": true]) as! [[String: Any]]
        sets.append(contentsOf: copied.dropFirst(sets.count).map { RawRow(raw: $0) })
    }
    @MainActor mutating func removeSet(id: UUID) throws {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        let result = try WebRules.shared.call("removeAdvancedSet", payload: ["sets": sets.map(\.raw), "index": index]) as! [String: Any]
        let start = Int(number(result["start"])), count = Int(number(result["count"]))
        sets.removeSubrange(start..<(start + count))
    }
    @MainActor mutating func copySet(at index: Int) throws {
        guard sets.indices.contains(index) else { return }
        try TrainingInput.validate(sets[index].raw)
        let result = try WebRules.shared.call("copySelectedSet", payload: ["sets": sets.map(\.raw), "index": index, "editing": true]) as! [String: Any]
        let at = Int(number(result["at"])), count = Int(number(result["count"]))
        try TrainingInput.validate(sets[(at - count)..<at].map(\.raw))
        let rows = result["sets"] as! [[String: Any]]
        sets.insert(contentsOf: rows[at..<(at + count)].map { RawRow(raw: $0) }, at: at)
    }
    var value: [String: Any] { var next = raw; next["sets"] = sets.map(\.raw); return next }
}
struct HistoryForm {
    var original: [String: Any]
    var unit: String
    var name: String
    var note: String
    var date: Date
    var minutes: String
    var entries: [HistoryEntryDraft]
    var selected: Int = 0
    init(original: [String: Any], unit: String, saved: [String: Any]? = nil) {
        self.original = saved?["original"] as? [String: Any] ?? original
        self.unit = saved?["unit"] as? String ?? unit
        let proposed = saved?["proposed"] as? [String: Any] ?? original
        let fields = saved?["form"] as? [String: Any] ?? [:]
        name = fields["name"] as? String ?? proposed["name"] as? String ?? "训练"
        note = fields["note"] as? String ?? proposed["note"] as? String ?? ""
        date = Date(timeIntervalSince1970: number(fields["start"] ?? proposed["start"]) / 1000)
        minutes = fields["minutes"] as? String ?? String(format: "%.8g", max(0, number(proposed["end"]) - number(proposed["start"])) / 60000)
        entries = (proposed["entries"] as? [[String: Any]] ?? []).map(HistoryEntryDraft.init)
        selected = min(max(0, fields["selected"] as? Int ?? 0), max(0, entries.count - 1))
    }
    var fields: [String: Any] { ["name": name, "note": note, "start": date.timeIntervalSince1970 * 1000, "minutes": minutes, "selected": selected] }
    var proposed: [String: Any] {
        var result = original
        result["name"] = name
        if note != (original["note"] as? String ?? "") { result["note"] = note }
        result["entries"] = entries.map(\.value)
        let start = date.timeIntervalSince1970 * 1000
        if abs(start - number(original["start"])) > 1 { result["start"] = start; result["d"] = dayString(date) }
        if let duration = TrainingInput.value(minutes), abs(start - number(original["start"])) > 1 || abs(duration * 60000 - (number(original["end"]) - number(original["start"]))) > 1 { result["end"] = start + duration * 60000 }
        return result
    }
}
