import SwiftUI

struct WatchHealthMetricView: View {
    let title: String
    let value: Double?
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text("\(title)·\(unit)").font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(color)
                .monospacedDigit()
        }.lineLimit(1, reservesSpace: true).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(value.map { String(format: "%.0f", $0) + unit } ?? String(localized: "NO_DATA_YET", bundle: AppLanguage.bundle, locale: AppLanguage.locale))")
    }
}

#Preview("心率") {
    WatchHealthMetricView(title: String(localized: "HEART_RATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        value: 124, unit: String(localized: "BPM", bundle: AppLanguage.bundle, locale: AppLanguage.locale), color: .red)
}

#Preview("暂无数据") {
    WatchHealthMetricView(title: String(localized: "ACTIVE_CALORIES", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        value: nil, unit: "kcal", color: .orange)
}
