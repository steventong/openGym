import SwiftUI

struct WatchHealthMetricView: View {
    let title: String.LocalizationValue
    let value: Double?
    let unit: String.LocalizationValue
    let color: Color
    @Environment(\.locale) private var locale

    var body: some View {
        let bundle = AppLanguage.bundle(for: locale.identifier)
        let localizedTitle = String(localized: title, bundle: bundle, locale: locale)
        let localizedUnit = String(localized: unit, bundle: bundle, locale: locale)

        VStack(spacing: 0) {
            Text(String(format: String(localized: "HEALTH_METRIC_TITLE_AND_UNIT", bundle: bundle, locale: locale), locale: locale, localizedTitle, localizedUnit)).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(color)
                .monospacedDigit()
        }.lineLimit(1, reservesSpace: true).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: String(localized: "HEALTH_METRIC_ACCESSIBILITY_VALUE", bundle: bundle, locale: locale), locale: locale, localizedTitle, value.map { String(format: "%.0f", $0) + localizedUnit } ?? String(localized: "NO_DATA_YET", bundle: bundle, locale: locale)))
    }
}

#Preview("心率") {
    WatchHealthMetricView(title: "HEART_RATE", value: 124, unit: "BPM", color: .red)
}

#Preview("暂无数据") {
    WatchHealthMetricView(title: "ACTIVE_CALORIES", value: nil, unit: "kcal", color: .orange)
}
