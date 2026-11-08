/// 固定快照数据源，也用于显式注入 Preview 样例。
struct TrainingSnapshotSource: TrainingContentSource {
    let trainingContent: TrainingContentData
}
