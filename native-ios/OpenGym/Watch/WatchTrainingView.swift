import SwiftUI

struct WatchTrainingView: View {
    
    let store: WatchRemoteStore
    private let green = TrainingDisplayStyle.green

    var body: some View {
        VStack(spacing: 0) {
            // 信息区按内容自然排布，剩余高度留在健康数据和底部按钮之间。
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TrainingExerciseTitle(title: store.snapshot.exercise)
                    TrainingExercisePosition(position: store.snapshot.exercisePosition, fontSize: 13)
                }
                
                TrainingSetSummary(weight: store.snapshot.displayedSet?.weight ?? String(localized: "SAVE_ON_IPHONE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                    detail: store.snapshot.displayedSet?.detail ?? "",
                    label: store.snapshot.displayedSet?.label ?? String(localized: "ALL_SETS_COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                    weightFontSize: 20, labelFontSize: 13, detailFontSize: 10)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                
                HStack(spacing: 2) {
                    WatchHealthMetricView(title: String(localized: "HEART_RATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: store.currentHealthReport?.state == .running ? store.currentHealthReport?.heartRate : nil, unit: String(localized: "BPM", bundle: AppLanguage.bundle, locale: AppLanguage.locale), color: .red)
                    WatchHealthMetricView(title: String(localized: "ACTIVE_CALORIES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: store.currentHealthReport?.activeCalories, unit: "kcal", color: .orange)
                    WatchHealthMetricView(title: String(localized: "TOTAL_CALORIES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: store.currentHealthReport?.totalCalories, unit: "kcal", color: .orange)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: TrainingDisplayStyle.actionGap)
            
            WatchPrimaryActionButton(store: store, tint: green)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

#Preview("训练中") {
    WatchTrainingView(store: WatchRemoteStore(previewSnapshot: .canvas(resting: false)))
}

#Preview("休息中") {
    WatchTrainingView(store: WatchRemoteStore(previewSnapshot: .canvas(resting: true)))
}

private extension WatchTrainingSnapshot {
    static func canvas(resting: Bool) -> Self {
        let set = WatchTrainingSet(entry: 0, index: 0, label: "第 1/3 组", weight: "5 kg", detail: "12 次")
        return Self(language: "zh-Hans", sessionID: "canvas", exercise: "哑铃飞鸟", exercisePosition: "第 1/1 个动作",
            nextSet: set, restSet: resting ? set : nil,
            restEnd: resting ? Date().addingTimeInterval(75) : nil,
            restEntry: resting ? 0 : nil, restExercise: "哑铃飞鸟",
            setStartedAt: resting ? nil : Date().addingTimeInterval(-45))
    }
}
