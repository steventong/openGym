import Foundation

/// 资料版本备份：每个版本一份完整的 JSON，放在“文件”App 可见的 OpenGYM/data-backup。
/// 文件只新增，不覆盖也不清理，随系统 iCloud 备份保存。文件内容就是资料文档本身，导出和导入使用同一格式。
@MainActor final class DataBackup {
    static let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("data-backup", isDirectory: true)

    let directory: URL
    /// 最近一份备份的内容，内容没有变化时不重复保存。首次保存时从磁盘读取。
    private var latest: [String: Any]?
    private var loadedLatest = false
    private let nameFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return format
    }()

    init(directory: URL = DataBackup.documentsFolder) { self.directory = directory }

    func save(_ document: [String: Any], at date: Date = Date()) throws {
        if !loadedLatest {
            latest = newestDocument()
            loadedLatest = true
        }
        if let latest, StateDocument.same(latest, document) { return }
        let data = try Self.encode(document)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = freeURL(at: date)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        latest = document
    }

    static func encode(_ document: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    /// 读取用户选择的备份文件。其他 JSON（例如只含计划的导出文件）不能当作整份资料导入。
    static func decode(_ data: Data) throws -> [String: Any] {
        guard let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              document["workouts"] != nil, document["routines"] != nil,
              StateDocument.recordSets.allSatisfy({ document[$0.documentKey] == nil || document[$0.documentKey] is [[String: Any]] }),
              document["unit"] == nil || ["kg", "lb"].contains(document["unit"] as? String) else {
            throw APIError.response(0, String(localized: "NOT_AN_OPENGYM_BACKUP", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        return document
    }

    /// 同一毫秒内的多个版本顺延，不覆盖已有文件。
    private func freeURL(at date: Date) -> URL {
        var date = date
        while true {
            let url = directory.appendingPathComponent(nameFormat.string(from: date)).appendingPathExtension("json")
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            date += 0.001
        }
    }

    private func newestDocument() -> [String: Any]? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        // 用户可能把其他文件放进这个文件夹，只认自动备份的文件名。
        guard let newest = names.filter({ $0.hasSuffix(".json") && nameFormat.date(from: String($0.dropLast(5))) != nil }).max(),
              let data = try? Data(contentsOf: directory.appendingPathComponent(newest)) else { return nil }
        return try? Self.decode(data)
    }
}
