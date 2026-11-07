import SwiftUI

struct CoachIntakeTextField: View {
    let title: String
    @Binding var text: String
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            BufferedTextField(title, text: $text, axis: .vertical)
                .textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                .lineLimit(3...6).padding().background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
            Text("\(text.count) / \(limit)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CoachIntakeTextField(title: String(localized: "OTHER_GOALS_OR_PREFERENCES", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        text: .constant(""), limit: 600)
}
