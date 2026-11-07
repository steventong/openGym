import SwiftUI

struct OptionalProgressionFieldRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            BufferedTextField(String(localized: "DEFAULT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $text)
                .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                .onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}

#Preview {
    OptionalProgressionFieldRow(title: String(localized: "SETS_UP_TO", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        text: .constant(""))
}
