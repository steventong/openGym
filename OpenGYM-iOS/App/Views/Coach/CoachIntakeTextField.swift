import SwiftUI

struct CoachIntakeTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            BufferedTextField(title, text: $text, axis: .vertical)
                .textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                .lineLimit(3...6).padding().background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
            Text(String(format: String(localized: "CHARACTER_COUNT_PROGRESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(text.count), String(limit))).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CoachIntakeTextField(title: "OTHER_GOALS_OR_PREFERENCES",
        text: .constant(""), limit: 600)
}
