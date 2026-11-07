import SwiftUI

struct AdvancedSetSubfield: View {
    let title: String
    @Binding var text: String
    let identifier: String
    let timerRunning: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            BufferedTextField(title, text: $text)
                .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                .onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad)
                .multilineTextAlignment(.center).padding(7)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier(identifier)
        }.disabled(timerRunning)
    }
}
