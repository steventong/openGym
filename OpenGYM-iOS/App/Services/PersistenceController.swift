import CoreData

/// Core Data 容器。正式环境把记录镜像到 iCloud 私有库，测试与预览使用不落盘、不联网的内存库。
final class PersistenceController {
    static let cloudContainerIdentifier = "iCloud.me.itwl.opengym"
    /// 本 App 自己写入的事务标记，用来把它们和 iCloud 导入的变更区分开。
    static let transactionAuthor = "OpenGYM"

    /// 模型只加载一次；多个容器共用同一份实体描述。
    private static let model: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "OpenGYM", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("OpenGYM.momd is missing from the app bundle")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer
    let syncsWithCloud: Bool
    /// 打不开本机数据库时保留原因，由 Store 提示用户；不静默改用空库。
    private(set) var loadError: Error?

    init(inMemory: Bool) {
        syncsWithCloud = !inMemory
        container = NSPersistentCloudKitContainer(name: "OpenGYM", managedObjectModel: Self.model)
        let description = container.persistentStoreDescriptions[0]
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
        } else {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerIdentifier)
        }
        // 历史记录与远端变更通知是 CloudKit 镜像和“其他设备改了资料”提示的前提。
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        loadError = failure
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = Self.transactionAuthor
    }
}
