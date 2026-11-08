import Foundation
import Observation

/// 共同的展示状态与保护期刷新，不读取平台 Store，也不执行按钮命令。
@MainActor @Observable final class TrainingViewModel {
    private let source: any TrainingContentSource
    private var refreshedAt = Date()

    init(source: any TrainingContentSource) {
        self.source = source
    }

    convenience init(content: TrainingContentData) {
        self.init(source: TrainingSnapshotSource(trainingContent: content))
    }

    var content: TrainingContentData {
        source.trainingContent.evaluated(at: max(refreshedAt, Date()))
    }

    var protectionDeadline: Date? { source.trainingContent.action?.readyAt }

    func refresh() {
        refreshedAt = Date()
    }

    func refreshAfterProtectionEnds() async {
        refresh()
        guard let deadline = protectionDeadline, deadline > refreshedAt else { return }
        do {
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        refresh()
    }
}
