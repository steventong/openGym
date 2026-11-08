import SwiftUI

struct LocalSaveStatus: View {
    @Environment(GymStore.self) private var store
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: store.localSaveError, initial: true) { _, issue in
                if let issue, store.error == nil { store.error = issue }
            }
    }
}
