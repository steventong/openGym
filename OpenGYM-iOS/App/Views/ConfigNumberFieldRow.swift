import SwiftUI

struct ConfigNumberFieldRow: View {
    let title: LocalizedStringKey
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
    ConfigNumberFieldRow(title: "SETS",
        value: .constant(3), identifier: "preview-config-sets")
}
