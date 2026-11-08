/// 平台适配层提供展示数据；共享 ViewModel 不需要认识具体 Store。
@MainActor protocol TrainingContentSource {
    var trainingContent: TrainingContentData { get }
}
