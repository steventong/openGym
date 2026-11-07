import SwiftUI

struct SetCompletionControl: View {
    let completed: Bool
    let failure: Bool
    let readOnly: Bool
    let timerRunning: Bool
    let height: CGFloat
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Group {
            if readOnly {
                // A read-only marker is not a disabled Button, so its fill never dims.
                SetCompletionMark(completed: completed, failure: failure, height: height)
                    .accessibilityElement(children: .ignore)
            } else {
                Button(action: action) {
                    SetCompletionMark(completed: completed, failure: failure, height: height)
                }.buttonStyle(.plain).disabled(timerRunning)
            }
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityValue((completed ? String(localized: "COMPLETED", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "INCOMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) + (failure ? String(localized: "TO_FAILURE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : ""))
    }
}
