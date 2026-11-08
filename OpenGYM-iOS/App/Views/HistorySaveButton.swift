import SwiftUI

struct HistorySaveButton: View {
    let submitting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text("SAVE").opacity(submitting ? 0 : 1)
                if submitting { ProgressView().controlSize(.small) }
            }.frame(minWidth: 44, minHeight: 44)
        }
        .disabled(submitting)
        .accessibilityLabel(submitting ? Text("SUBMITTING") : Text("SAVE"))
        .accessibilityIdentifier("save-history")
    }
}

#Preview {
    HStack {
        HistorySaveButton(submitting: false) {}
        HistorySaveButton(submitting: true) {}
    }.padding().tint(GymTheme.green)
}
