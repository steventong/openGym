import SwiftUI

struct HomeTrainingButton: View {
    let title: String
    let icon: String
    let primary: Bool
    let identifier: String
    var startedAt: Date? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 22, height: 22).accessibilityHidden(true)
                Text(title)
                    .padding(.horizontal, startedAt == nil ? 0 : 32)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 22, height: 22).accessibilityHidden(true)
            }
            .font(.system(size: primary ? 17 : 15, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if let startedAt {
                    HomeWorkoutDurationLabel(start: startedAt)
                        .allowsHitTesting(false)
                }
            }
            .foregroundStyle(enabled ? (primary ? Color.black : GymTheme.green) : GymTheme.muted)
        }
        .disabled(!enabled)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier(identifier)

        Group {
            if primary {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.glass)
            }
        }
    }
}

#Preview {
    HomeTrainingButton(title: String(localized: "START_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        icon: "play.fill", primary: true, identifier: "preview-home-start") {}
}
