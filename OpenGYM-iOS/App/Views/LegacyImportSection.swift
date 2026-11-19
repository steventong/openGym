import SwiftUI

/// 设置页的服务器版资料迁移。只在本机留有服务器版账号时显示，点按后才读取服务器。
struct LegacyImportSection: View {
    let server: String
    let busy: Bool
    let run: () async -> GymStore.LegacyImportResult
    @State private var result: GymStore.LegacyImportResult?

    var body: some View {
        Section {
            LabeledContent("SERVER", value: server)
            Button(LocalizedStringKey(busy ? "IMPORTING" : "IMPORT_SERVER_DATA_AGAIN")) {
                Task { result = await run() }
            }
            .disabled(busy)
            .accessibilityIdentifier("import-server-data")
            switch result {
            case .importedFromServer:
                Text("IMPORTED_FROM_SERVER").font(.footnote).foregroundStyle(GymTheme.muted)
            case .importedFromCache:
                Text("IMPORTED_FROM_LOCAL_CACHE").font(.footnote).foregroundStyle(Color.orange)
            case .unavailable:
                Text("SERVER_DATA_UNAVAILABLE").font(.footnote).foregroundStyle(.red)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        } header: {
            Text("SERVER_DATA")
        } footer: {
            Text("IMPORT_SERVER_DATA_INFO")
        }
    }
}

#Preview("中文") {
    Form {
        LegacyImportSection(server: "https://gym.example.com", busy: false) { .importedFromServer }
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("English · Dark") {
    Form {
        LegacyImportSection(server: "https://gym.example.com", busy: false) { .importedFromCache }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.dark)
    .tint(GymTheme.green)
}
