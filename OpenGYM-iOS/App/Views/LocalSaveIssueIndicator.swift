import SwiftUI

struct LocalSaveIssueIndicator: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        if let issue = store.localSaveError {
            Button { store.error = issue } label: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    .frame(width: 28, height: 28).background(.black, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("COULD_NOT_SAVE_ON_THIS_DEVICE_VIEW_DETAILS")
                .accessibilityIdentifier("local-save-error")
        }
    }
}
