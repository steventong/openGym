import SwiftUI

/// 设置页的动作媒体地址。动作文字随 App 内置，图片和视频按需从这个地址下载并缓存。
struct MediaServerSection: View {
    let current: String
    let save: (String) throws -> Void
    @State private var address: String
    @State private var issue: String?

    init(current: String, save: @escaping (String) throws -> Void) {
        self.current = current
        self.save = save
        _address = State(initialValue: current)
    }

    private var changed: Bool { address.trimmingCharacters(in: .whitespacesAndNewlines) != current }

    var body: some View {
        Section {
            TextField("LOCAL_SERVER_EXAMPLE", text: $address)
                .textFieldStyle(.plain).stableInputLine().submitLabel(.done)
                .onSubmit { GymKeyboard.dismiss(); apply() }.keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: address) { issue = nil }
                .onChange(of: current) { _, saved in address = saved }
                .accessibilityIdentifier("media-server-url")
            if let issue { Text(issue).font(.footnote).foregroundStyle(.red) }
            if changed {
                Button("SAVE", action: apply).accessibilityIdentifier("save-media-server")
            }
        } header: {
            Text("EXERCISE_MEDIA_SERVER")
        } footer: {
            Text("EXERCISE_MEDIA_SERVER_INFO")
        }
    }

    private func apply() {
        guard changed else { return }
        do { try save(address); issue = nil }
        catch { issue = error.localizedDescription }
    }
}

#Preview("中文") {
    @Previewable @State var saved = "https://gym.example.com"
    Form {
        MediaServerSection(current: saved) { saved = try ServerAddress($0).url.absoluteString }
    }
    .environment(\.locale, Locale(identifier: "zh-Hans"))
    .tint(GymTheme.green)
}

#Preview("English · Dark") {
    @Previewable @State var saved = "http://localhost:8080"
    Form {
        MediaServerSection(current: saved) { saved = try ServerAddress($0).url.absoluteString }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.dark)
    .tint(GymTheme.green)
}
