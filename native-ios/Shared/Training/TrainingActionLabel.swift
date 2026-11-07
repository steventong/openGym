import SwiftUI

struct TrainingActionLabel: View {
    let title: String
    let symbol: String
    let protectionEnd: Date?
    let disabled: Bool
    let tint: Color
    var scale: CGFloat = 1
    var restEnd: Date? = nil
    var quietReady = false
    var setStartedAt: Date? = nil
    var language: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    private var unavailable: Bool { disabled || !isEnabled }
    private var hidesRestAction: Bool { restEnd != nil && protectionEnd != nil }
    private var foreground: Color {
        unavailable ? .secondary : .black
    }
    private var background: Color {
        unavailable ? .gray.opacity(0.25) : tint
    }

    var body: some View {
        stackedLabel
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity).frame(height: TrainingDisplayStyle.actionHeight * scale)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 17 * scale))
        .contentShape(RoundedRectangle(cornerRadius: 17 * scale))
        .accessibilityElement(children: .combine)
    }

    private var stackedLabel: some View {
        VStack(spacing: TrainingDisplayStyle.actionLineSpacing * scale) {
            if restEnd != nil || quietReady || setStartedAt != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    Text(String(localized: String.LocalizationValue(restEnd == nil ? "WORKOUT" : "REST"), bundle: AppLanguage.bundle(for: language ?? AppLanguage.language), locale: AppLanguage.locale(for: language ?? AppLanguage.language)))
                        .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
                        // System timer text expands to its proposed width. Reserve
                        // the status label first so WidgetKit cannot squeeze it out.
                        .layoutPriority(1)
                    clock
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 24 * scale, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.4)
            }
            Label(title, systemImage: symbol)
                .font(.system(size: 16 * scale, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .opacity(hidesRestAction ? 0 : 1)
                .accessibilityHidden(hidesRestAction)
        }
        .padding(.horizontal, 10 * scale)
    }

    @ViewBuilder private var clock: some View {
        // System-rendered timers keep ticking in archived Live Activity views.
        if let restEnd {
            // Use the same bounded interval as the compact Dynamic Island.
            // A distantPast lower bound spans millennia unnecessarily.
            TrainingCountdownText(end: restEnd, presentation: .systemTimer)
        } else if let setStartedAt {
            Text(timerInterval: setStartedAt...Date.distantFuture, countsDown: false, showsHours: false)
        } else {
            Text("—:—")
        }
    }
}
