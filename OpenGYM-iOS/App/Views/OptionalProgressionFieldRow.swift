import SwiftUI

struct OptionalProgressionFieldRow: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            BufferedTextField("DEFAULT", text: $text)
                .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                .onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}

#Preview {
    OptionalProgressionFieldRow(title: "SETS_UP_TO",
        text: .constant(""))
}
