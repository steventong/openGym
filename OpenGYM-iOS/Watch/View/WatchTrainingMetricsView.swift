import SwiftUI

/// 仅手表提供的健康指标，不参与公共训练内容的状态判断。
struct WatchTrainingMetricsView: View {
    let report: HealthWorkoutReport?

    var body: some View {
        HStack(spacing: 2) {
            WatchHealthMetricView(title: "HEART_RATE",
                value: report?.state == .running ? report?.heartRate : nil, unit: "BPM", color: .red)
            WatchHealthMetricView(title: "ACTIVE_CALORIES", value: report?.activeCalories, unit: "kcal", color: .orange)
            WatchHealthMetricView(title: "TOTAL_CALORIES", value: report?.totalCalories, unit: "kcal", color: .orange)
        }
    }
}
