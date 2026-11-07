import SwiftUI

struct RoutineNumberField: View {
    let title: String
    @Binding var value: Double
    let allowsDecimal: Bool
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            BufferedNumberField(title, value: $value)
                .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                .onSubmit { GymKeyboard.dismiss() }
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .padding(9).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityIdentifier(identifier)
        }
    }
}

#Preview {
    RoutineNumberField(title: String(localized: "REPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
        value: .constant(10), allowsDecimal: false, identifier: "preview-routine-reps")
}
