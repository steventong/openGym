import CloudKit
import Foundation

/// iCloud 同步失败的具体原因。
/// CloudKit 常把一批记录的失败合并成“部分记录修改失败”，这里拆开逐条归类，设置页才能说明原因和是否需要处理。
struct CloudSyncIssue: Equatable {
    enum Phase: Equatable {
        case setup, download, upload
    }

    enum Reason: Equatable {
        /// 正式环境缺少记录类型或字段：Schema 没有部署到 Production。
        case schemaNotDeployed
        /// 其他设备同时修改了同一条记录。
        case conflict
        case quotaExceeded
        case notSignedIn
        case network
        /// iCloud 繁忙、限流或单批过大，系统稍后重试。
        case busy
        /// iCloud 中的资料区被删除，例如用户在系统设置里清除了 iCloud 数据。
        case dataDeleted
        /// 容器、权限或授权配置错误。
        case configuration
        case other

        /// 系统会自行恢复的原因不需要用户处理。
        var needsAction: Bool {
            switch self {
            case .conflict, .network, .busy, .dataDeleted: false
            case .schemaNotDeployed, .quotaExceeded, .notSignedIn, .configuration, .other: true
            }
        }
    }

    struct Cause: Equatable {
        let reason: Reason
        /// 涉及的记录数；不是逐条记录的错误时为 nil。
        let records: Int?
    }

    let phase: Phase
    /// 按涉及记录数从多到少排列。
    let causes: [Cause]
    /// CloudKit 的原始错误文字，去重后保留，供排查。
    let details: [String]

    var needsAction: Bool { causes.contains { $0.reason.needsAction } }

    init(phase: Phase, causes: [Cause], details: [String]) {
        self.phase = phase
        self.causes = causes
        self.details = details
    }

    init(error: Error, phase: Phase) {
        self.phase = phase
        let root = Self.cloudKitError(in: error as NSError)
        let partial = root.domain == CKErrorDomain && root.code == CKError.Code.partialFailure.rawValue
        let items = (root.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error])?.values.map { $0 as NSError } ?? []
        guard partial, !items.isEmpty else {
            causes = [Cause(reason: Self.reason(for: root), records: nil)]
            details = [Self.detail(of: root)]
            return
        }
        // batchRequestFailed 只表示被同一批里的其他失败牵连，本身不是原因。
        let own = items.filter { !($0.domain == CKErrorDomain && $0.code == CKError.Code.batchRequestFailed.rawValue) }
        let failures = own.isEmpty ? items : own
        var counts: [(Reason, Int)] = []
        for failure in failures {
            let reason = Self.reason(for: failure)
            if let index = counts.firstIndex(where: { $0.0 == reason }) { counts[index].1 += 1 } else { counts.append((reason, 1)) }
        }
        causes = counts.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map { Cause(reason: $0.element.0, records: $0.element.1) }
        var seen = Set<String>()
        details = failures.map(Self.detail).filter { seen.insert($0).inserted }
    }

    /// Core Data 有时把 CloudKit 错误包在自己的错误里。
    private static func cloudKitError(in error: NSError) -> NSError {
        var current: NSError? = error
        while let candidate = current {
            if candidate.domain == CKErrorDomain { return candidate }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return error
    }

    private static func reason(for error: NSError) -> Reason {
        guard error.domain == CKErrorDomain, let code = CKError.Code(rawValue: error.code) else {
            return error.domain == NSURLErrorDomain ? .network : .other
        }
        switch code {
        case .invalidArguments, .unknownItem:
            // 正式环境拒绝新建类型或字段时，服务器说明里会提到 schema 或 record type。
            let text = detail(of: error).lowercased()
            return text.contains("schema") || text.contains("record type") ? .schemaNotDeployed : .other
        case .serverRecordChanged: return .conflict
        case .quotaExceeded: return .quotaExceeded
        case .notAuthenticated, .accountTemporarilyUnavailable: return .notSignedIn
        case .networkUnavailable, .networkFailure: return .network
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .limitExceeded, .serverResponseLost: return .busy
        case .zoneNotFound, .userDeletedZone: return .dataDeleted
        case .permissionFailure, .badContainer, .missingEntitlement, .badDatabase, .managedAccountRestricted: return .configuration
        default: return .other
        }
    }

    /// 服务器说明比 localizedDescription 更具体，有就一起保留。
    private static func detail(of error: NSError) -> String {
        let name = error.domain == CKErrorDomain ? "CKError \(error.code)" : "\(error.domain) \(error.code)"
        let server = error.userInfo["ServerErrorDescription"] as? String
        let description = error.localizedDescription
        let text = server.map { $0 == description ? $0 : "\(description) \($0)" } ?? description
        return "\(name): \(text)"
    }
}
