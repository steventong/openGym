/// Watch 的组合适配：共享模型只看到展示数据，不直接依赖远程 Store。
struct WatchTrainingContentSource: TrainingContentSource {
    let store: WatchRemoteStore

    var trainingContent: TrainingContentData {
        let action = store.primaryAction()
        return store.snapshot.trainingContent(action: action,
            disabled: store.isDisabled(action, includeProtection: false))
    }
}
