import SwiftUI

struct AdvancedSetInputField: View {
    let title: String
    @Binding var text: String
    let compact: Bool
    let setLabel: String
    let identifier: String
    let height: CGFloat
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !compact { Text(title).font(.caption2).foregroundStyle(.secondary) }
            HStack(spacing: 3) {
                BufferedTextField(title, text: $text)
                    .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                    .onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad)
                    .multilineTextAlignment(.center).accessibilityLabel("\(setLabel) \(title)")
                    .accessibilityIdentifier(identifier)
                if compact { Text(title).font(.caption2).foregroundStyle(.secondary).fixedSize() }
            }.padding(.horizontal, 7).frame(height: height)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }.disabled(disabled)
    }
}
