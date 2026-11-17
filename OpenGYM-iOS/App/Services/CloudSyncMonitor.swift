import CoreData
import Observation

/// 设置页展示的 iCloud 同步情况。
struct CloudSyncStatus: Equatable {
    var accountAvailable = false
    var lastSync: Date?
    var issue: String?
}

/// 监听 Core Data 的 CloudKit 镜像事件。同步由系统自动进行，这里只记录结果供设置页显示。
@MainActor @Observable final class CloudSyncMonitor {
    private(set) var status: CloudSyncStatus
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private static let lastSyncKey = "cloudSync.lastSuccess"

    init(container: NSPersistentCloudKitContainer, defaults: UserDefaults) {
        self.defaults = defaults
        status = CloudSyncStatus(accountAvailable: FileManager.default.ubiquityIdentityToken != nil,
                                 lastSync: defaults.object(forKey: Self.lastSyncKey) as? Date)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let finished = event.endDate else { return }
            let succeeded = event.succeeded, failure = event.error?.localizedDescription, isSetup = event.type == .setup
            MainActor.assumeIsolated { self?.record(finished: finished, succeeded: succeeded, failure: failure, isSetup: isSetup) }
        })
        observers.append(center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.status.accountAvailable = FileManager.default.ubiquityIdentityToken != nil }
        })
    }

    private func record(finished: Date, succeeded: Bool, failure: String?, isSetup: Bool) {
        guard succeeded else { status.issue = failure; return }
        status.issue = nil
        // 初始化事件不代表资料已经传输。
        guard !isSetup else { return }
        status.lastSync = finished
        defaults.set(finished, forKey: Self.lastSyncKey)
    }
}
