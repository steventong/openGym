import SwiftUI

/// 设置页的资料备份：导出当前资料，或选择一份备份替换全部资料。
struct DataBackupSection: View {
    /// 自动备份最近一次失败的原因。
    let issue: String?
    let export: () throws -> Data
    let restore: ([String: Any]) async throws -> Void

    private enum Phase {
        case idle
        case confirming([String: Any])
        case restoring
        case restored
        case failed(String)
    }
    @State private var phase = Phase.idle
    @State private var exporting = false
    @State private var importing = false
    @State private var exported = GymJSONDocument(data: Data())

    var body: some View {
        Section {
            Button("EXPORT_BACKUP", action: prepareExport)
                .accessibilityIdentifier("export-backup")
                .fileExporter(isPresented: $exporting, document: exported, contentType: .json, defaultFilename: "openGym-backup-\(dayString())") { result in
                    if case .failure(let error) = result { phase = .failed(error.localizedDescription) }
                }
            Button("IMPORT_BACKUP") { phase = .idle; importing = true }
                .disabled(isRestoring)
                .accessibilityIdentifier("import-backup")
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: read)
                .confirmationDialog("REPLACE_ALL_DATA_WITH_BACKUP", isPresented: isConfirming, titleVisibility: .visible, presenting: candidate) { document in
                    Button("IMPORT_AND_REPLACE", role: .destructive) { apply(document) }
                    Button("CANCEL", role: .cancel) {}
                } message: { document in
                    Text(summary(of: document))
                }
            switch phase {
            case .restored: Text("BACKUP_IMPORTED").font(.footnote).foregroundStyle(GymTheme.muted)
            case .failed(let message): Text(message).font(.footnote).foregroundStyle(.red)
            case .idle, .confirming, .restoring: EmptyView()
            }
            if let issue { Text(issue).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("DATA_BACKUP")
        } footer: {
            Text("DATA_BACKUP_INFO")
        }
    }

    private var isRestoring: Bool {
        if case .restoring = phase { true } else { false }
    }
    private var candidate: [String: Any]? {
        if case .confirming(let document) = phase { document } else { nil }
    }
    private var isConfirming: Binding<Bool> {
        Binding(get: { candidate != nil }, set: { if !$0, candidate != nil { phase = .idle } })
    }

    private func summary(of document: [String: Any]) -> String {
        func count(_ key: String) -> String { String((document[key] as? [Any] ?? []).count) }
        return String(format: String(localized: "BACKUP_REPLACEMENT_SUMMARY", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                      locale: AppLanguage.locale, count("workouts"), count("routines"), count("bodyweight"))
    }

    private func prepareExport() {
        do { exported = GymJSONDocument(data: try export()); exporting = true }
        catch { phase = .failed(error.localizedDescription) }
    }

    private func read(_ result: Result<URL, Error>) {
        do {
            let url = try result.get(), access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            phase = .confirming(try DataBackup.decode(Data(contentsOf: url)))
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func apply(_ document: [String: Any]) {
        phase = .restoring
        Task {
            do { try await restore(document); phase = .restored }
            catch { phase = .failed(error.localizedDescription) }
        }
    }
}

#Preview("中文") {
    Form { DataBackupSection(issue: nil, export: { Data() }, restore: { _ in }) }
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .tint(GymTheme.green)
}

#Preview("English · Dark") {
    Form { DataBackupSection(issue: "Could not save the data backup: disk full", export: { Data() }, restore: { _ in }) }
        .environment(\.locale, Locale(identifier: "en"))
        .preferredColorScheme(.dark)
        .tint(GymTheme.green)
}
