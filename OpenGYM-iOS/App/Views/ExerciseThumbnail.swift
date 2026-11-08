import SwiftUI
import UIKit

struct ExerciseThumbnail: View {
    @Environment(GymStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let id: String
    var size: CGFloat = 60
    @State private var image: UIImage?
    @State private var loadedKey: LoadKey?
    @State private var failed = false
    @State private var attempt = 0

    private struct LoadKey: Hashable {
        let id: String
        let server: String
        let mediaID: String?
        let attempt: Int
    }

    private var loadKey: LoadKey {
        LoadKey(id: id, server: store.serverURL, mediaID: store.imageMediaID(id), attempt: attempt)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if loadedKey == loadKey, let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(3)
                } else {
                    Image(systemName: "dumbbell").foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if failed && loadedKey == loadKey {
                Button { attempt += 1 } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                        .foregroundStyle(.gray).padding(6).background(.white, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("TRY_AGAIN")
                .accessibilityIdentifier("retry-exercise-image-\(id)")
            }
        }
        .frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: loadKey) { await load(loadKey) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && failed { attempt += 1 }
        }
    }

    @MainActor private func load(_ key: LoadKey) async {
        image = nil
        loadedKey = key
        failed = false
        guard let mediaID = key.mediaID else { return }
        do {
            let downloaded = try await ExerciseImageCache.shared.image(for: mediaID, remoteURL: store.remoteImageURL(key.id))
            try Task.checkCancellation()
            image = downloaded
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}
