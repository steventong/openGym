import SwiftUI

struct ConfigNumberFieldRow: View {
    let title: String
    @Binding var value: Double
    var fieldWidth: CGFloat = 85
    var labelFont: Font = .subheadline
    let identifier: String

    var body: some View {
        HStack {
            Text(title).font(labelFont)
            Spacer()
            BufferedNumberField(title, value: $value)
                .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                .onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: fieldWidth)
                .accessibilityIdentifier(identifier)
        }
    }
}

#Preview {
    ConfigNumberFieldRow(title: String(localized: "SETS", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        value: .constant(3), identifier: "preview-config-sets")
}
