import Foundation
import HealthKit
import Observation

enum HealthWeightMerge {
    static func untouched(_ row: [String: Any]) -> Bool {
        guard let mark = row["healthKit"] as? [String: Any] else { return false }
        return RecordPatch.equal(row["w"], mark["value"]) && RecordPatch.equal(row["t"], mark["time"])
    }
    static func merge(_ state: [String: Any], samples: [String: [String: Any]], deleted: Set<String>) -> [String: Any] {
        var latest: [String: [String: Any]] = [:]
        for (id, sample) in samples {
            let kg = number(sample["kg"]), time = number(sample["time"])
            guard kg.isFinite, kg > 0, time.isFinite, time > 0 else { continue }
            let day = sample["day"] as? String ?? dayString(Date(timeIntervalSince1970: time / 1000))
            if let old = latest[day], number(old["time"]) > time || (number(old["time"]) == time && (old["id"] as? String ?? "") > id) { continue }
            latest[day] = ["id": id, "kg": kg, "time": time]
        }
        var result = state, rows = state["bodyweight"] as? [[String: Any]] ?? []
        let removed = (state["deleted"] as? [String: Any])?["bodyweight"] as? [String: Any] ?? [:]
        for (day, sample) in latest {
            let time = number(sample["time"])
            if number(removed[day]) >= time { continue }
            let existing = rows.firstIndex { $0["d"] as? String == day }
            if let existing, !untouched(rows[existing]) { continue } // Manual entry/override always wins.
            let value = (number(sample["kg"]) * (state["unit"] as? String == "lb" ? 2.20462262185 : 1) * 1000).rounded() / 1000
            var row = existing.map { rows[$0] } ?? [:]
            row["d"] = day; row["w"] = value; row["t"] = time
            row["healthKit"] = ["id": sample["id"]!, "value": value, "time": time, "kg": sample["kg"]!]
            if let existing { rows[existing] = row } else { rows.append(row) }
        }
        rows.removeAll { row in
            guard let mark = row["healthKit"] as? [String: Any], let id = mark["id"] as? String, let day = row["d"] as? String else { return false }
            return deleted.contains(id) && latest[day] == nil && untouched(row)
        }
        result["bodyweight"] = rows.sorted { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") }
        return result
    }
}

@MainActor @Observable final class HealthWeightSync {
    private(set) var enabled = false
    private(set) var busy = false
    private(set) var status = "未开启"
    private(set) var lastRead: Date?
    private(set) var pending = false
    private(set) var backgroundIssue: String?
    private(set) var samples: [String: [String: Any]] = [:]
    private var deleted: Set<String> = []
    private var anchorData: String?
    private var observer: HKObserverQuery?
    private var query: HKAnchoredObjectQuery?
    private var account: String?
    private var epoch = UUID()
    private var readAgain = false
    private weak var store: GymStore?
    private let health = HKHealthStore()
    private let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    init(store: GymStore) { self.store = store }
    private var file: URL? { store?.accountFolder?.appendingPathComponent("health-weight.json") }
    private var identity: String? { store?.accountFolder?.path }
    private func save() throws {
        guard let file, let store else { throw APIError.signIn }
        var record: [String: Any] = ["enabled": enabled, "samples": samples, "deleted": Array(deleted), "pending": pending]
        record["anchor"] = anchorData; record["lastRead"] = lastRead?.timeIntervalSince1970
        try store.localStorage.write(record, to: file)
    }
    func prepare() {
        guard identity != nil else { return }
        if account != identity {
            stop(); account = identity; enabled = false; samples = [:]; deleted = []; anchorData = nil; pending = false; lastRead = nil
            do {
                if let file, let saved = try store?.localStorage.read(file) {
                    enabled = saved["enabled"] as? Bool == true; samples = saved["samples"] as? [String: [String: Any]] ?? [:]
                    deleted = Set(saved["deleted"] as? [String] ?? []); anchorData = saved["anchor"] as? String; pending = saved["pending"] as? Bool == true
                    if let t = saved["lastRead"] as? Double { lastRead = Date(timeIntervalSince1970: t) }
                }
            } catch { status = "本机健康数据读取失败：\(error.localizedDescription)"; return }
        }
        guard enabled, available else { status = available ? "未开启" : "此设备不支持健康数据"; return }
        observe()
    }
    func resume() async { prepare(); if enabled { await sync() } }
    func setEnabled(_ on: Bool) async {
        if !on {
            enabled = false; stop()
            do { try save(); try await health.disableBackgroundDelivery(for: type); status = "已停止同步，已有体重记录保留" }
            catch { status = "同步已停止：\(error.localizedDescription)" }
            return
        }
        guard available, !busy, let identity else { status = available ? "请先连接 openGym 账号" : "此设备不支持健康数据"; return }
        if account != identity { prepare() }
        busy = true; let token = epoch, target = identity
        do {
            // Read only. Completion means the permission sheet was handled, not that read access was granted.
            try await health.requestAuthorization(toShare: [], read: [type])
            guard token == epoch, target == self.identity else { busy = false; return }
            enabled = true
            do { try save() } catch { enabled = false; throw error }
            observe()
            do { try await health.enableBackgroundDelivery(for: type, frequency: .immediate); backgroundIssue = nil }
            catch { backgroundIssue = "后台更新暂不可用，打开 App 时仍会同步：\(error.localizedDescription)" }
            status = "已开启；读取权限由 Apple 健康管理"
        } catch { status = error.localizedDescription }
        busy = false
        if enabled { await sync() }
    }
    private func observe() {
        guard observer == nil, enabled else { return }
        let token = epoch
        let next = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            Task { @MainActor in
                defer { completion() }
                guard let self, self.epoch == token, self.enabled else { return }
                if let error { self.status = error.localizedDescription; return }
                await self.sync()
            }
        }
        observer = next; health.execute(next)
    }
    private func stop() {
        epoch = UUID()
        readAgain = false
        if let observer { health.stop(observer) }; observer = nil
        // Let an in-flight one-shot query finish and discard its result via the epoch check.
    }
    private func readChanges() async throws -> ([HKQuantitySample], [HKDeletedObject], HKQueryAnchor?) {
        var anchor: HKQueryAnchor?
        if let anchorData, let data = Data(base64Encoded: anchorData) { anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) }
        return try await withCheckedThrowingContinuation { continuation in
            let next = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, deleted, anchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKQuantitySample] ?? [], deleted ?? [], anchor)) }
            }
            query = next; health.execute(next)
        }
    }
    func sync() async {
        guard enabled, account == identity else { return }
        if busy { readAgain = true; return }
        busy = true
        defer {
            busy = false; query = nil
            if readAgain && enabled { readAgain = false; Task { await self.sync() } }
        }
        let token = epoch, target = identity
        do {
            let (added, removed, anchor) = try await readChanges()
            guard token == epoch, enabled, target == identity else { return }
            var next = samples, tombstones = deleted
            for r in removed { next.removeValue(forKey: r.uuid.uuidString); tombstones.insert(r.uuid.uuidString) }
            for s in added {
                next[s.uuid.uuidString] = ["kg": s.quantity.doubleValue(for: .gramUnit(with: .kilo)), "time": s.startDate.timeIntervalSince1970 * 1000, "day": dayString(s.startDate)]
                tombstones.remove(s.uuid.uuidString)
            }
            let newAnchor = try anchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true).base64EncodedString() }
            // Checkpoint samples and anchor together before attempting any network write.
            guard let store, let file else { return }
            var checkpoint: [String: Any] = ["enabled": true, "samples": next, "deleted": Array(tombstones), "pending": true, "lastRead": Date().timeIntervalSince1970]
            checkpoint["anchor"] = newAnchor
            try store.localStorage.write(checkpoint, to: file)
            samples = next; deleted = tombstones; anchorData = newAnchor; pending = true; lastRead = Date()
            guard token == epoch, enabled, target == identity else { return }
            if samples.isEmpty && deleted.isEmpty { pending = false; try save(); status = "暂无可读取体重；可能没有记录或未允许读取"; return }
            var expected: Any?
            let saved = await store.mutate(reportError: false, verify: { RecordPatch.equal($0["bodyweight"], expected) }) { source in
                guard self.enabled, self.epoch == token, self.identity == target else { throw APIError.response(0, "同步已停止") }
                let result = HealthWeightMerge.merge(source, samples: next, deleted: tombstones); expected = result["bodyweight"]; return result
            }
            guard token == epoch, enabled, target == identity else { return }
            if saved { pending = false; deleted = []; try save(); status = "体重已同步" }
            else { status = "体重已存本机，等待同步：\(store.editError ?? "稍后重试")" }
        } catch { if token == epoch { status = "同步未完成：\(error.localizedDescription)" } }
    }
    func localBodyweights(_ state: [String: Any]) -> [[String: Any]] {
        guard account == identity else { return state["bodyweight"] as? [[String: Any]] ?? [] }
        return HealthWeightMerge.merge(state, samples: samples, deleted: deleted)["bodyweight"] as? [[String: Any]] ?? []
    }
}
