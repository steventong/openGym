import SwiftUI

/// AI 服务设置。API key 只写入 iCloud 钥匙串，保存后不再显示。
struct AISettingsView: View {
    let settings: AISettings
    @State private var slot: AIServiceSlot
    @State private var address: String
    @State private var model: String
    @State private var newKey = ""
    @State private var models: AIModelList = .none
    @State private var issue: String?
    @State private var confirmRemove = false
    /// 上次保存时的内容，与当前内容一致即显示“已保存”。
    @State private var savedValues: [String] = []

    init(settings: AISettings) {
        self.settings = settings
        _slot = State(initialValue: settings.slot)
        _address = State(initialValue: settings.customAddress(settings.slot.kind))
        _model = State(initialValue: settings.model(settings.slot))
    }

    var body: some View {
        Form {
            Section {
                Picker("AI_PROTOCOL", selection: $slot.kind) {
                    Text(verbatim: "Anthropic").tag(AIProtocolKind.anthropic)
                    Text(verbatim: "OpenAI").tag(AIProtocolKind.openai)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai-protocol")
            } header: { Text("AI_PROTOCOL") } footer: { Text("AI_PROTOCOL_INFO") }

            Section {
                Picker("AI_ADDRESS", selection: $slot.address) {
                    Text("AI_OFFICIAL_ADDRESS").tag(AIAddressKind.official)
                    Text("AI_CUSTOM_ADDRESS").tag(AIAddressKind.custom)
                }
                .accessibilityIdentifier("ai-address-kind")
                if slot.address == .custom {
                    TextField("AI_ADDRESS_EXAMPLE", text: $address)
                        .stableInputLine().submitLabel(.done).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("ai-custom-address")
                }
            } footer: {
                if let service {
                    Text(aiText("AI_REQUESTS_GO_TO_COUNT", service.baseURL.absoluteString))
                } else {
                    Text("AI_INVALID_ADDRESS")
                }
            }

            Section {
                TextField("AI_MODEL_NAME", text: $model)
                    .stableInputLine().submitLabel(.done)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("ai-model")
                switch models {
                case .none:
                    Button("AI_LOAD_MODELS") { Task { await loadModels() } }
                case .loading:
                    HStack { Text("AI_LOADING_MODELS"); Spacer(); ProgressView() }
                case let .loaded(names):
                    Picker("AI_CHOOSE_MODEL", selection: $model) {
                        if !names.contains(model) { Text(model).tag(model) }
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
            } header: { Text("AI_MODEL") } footer: { Text("AI_MODEL_INFO") }

            Section {
                SecureField(LocalizedStringKey(hasKey ? "AI_API_KEY_SAVED_PLACEHOLDER" : "AI_ENTER_API_KEY"), text: $newKey)
                    .stableInputLine().submitLabel(.done)
                    .textContentType(.none).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("ai-api-key")
                if hasKey {
                    Button("AI_REMOVE_API_KEY", role: .destructive) { confirmRemove = true }
                }
            } header: { Text("AI_API_KEY") } footer: { Text("AI_API_KEY_INFO") }

            Section {} footer: { Text("AI_PRIVACY_INFO") }
        }
        .operationAlert($issue)
        .navigationTitle("AI_SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(LocalizedStringKey(savedValues == values ? "AI_STATUS_SAVED" : "SAVE"), action: save).accessibilityIdentifier("ai-save")
            }
        }
        .onChange(of: slot) { _, next in
            // 每种协议与地址各有自己的配置，切换时显示对应内容。
            address = settings.customAddress(next.kind)
            model = settings.model(next)
            newKey = ""
        }
        .onChange(of: [slot.storageKey, address, newKey]) { models = .none }
        .confirmationDialog("AI_REMOVE_API_KEY_CONFIRM", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("AI_REMOVE_API_KEY", role: .destructive) {
                do { try settings.removeKey(settings.service(slot, address: address, model: model)) } catch { issue = error.localizedDescription }
            }
            Button("CANCEL", role: .cancel) {}
        }
    }

    private var values: [String] { [slot.storageKey, address, model, newKey] }
    /// 当前填写的服务；自定义地址不合法时为空。
    private var service: AIService? { try? settings.service(slot, address: address, model: model) }
    private var hasKey: Bool { service.map(settings.hasKey) ?? false }

    private func save() {
        GymKeyboard.dismiss()
        do {
            try settings.save(slot, address: address, model: model, newKey: newKey)
            newKey = ""
            savedValues = values
        } catch { issue = error.localizedDescription }
    }

    private func loadModels() async {
        GymKeyboard.dismiss()
        let requested = [slot.storageKey, address, newKey]
        do {
            let service = try settings.service(slot, address: address, model: model)
            let typed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty || settings.hasKey(service) else { throw AIClientError.missingKey }
            let key = typed.isEmpty ? try settings.key(service) : typed
            models = .loading
            let names = try await AIHTTPClient().models(service, key: key)
            guard requested == [slot.storageKey, address, newKey] else { return }
            models = .loaded(names)
        } catch {
            guard requested == [slot.storageKey, address, newKey] else { return }
            models = .none
            issue = error.localizedDescription
        }
    }
}

private enum AIModelList {
    case none, loading, loaded([String])
}

#Preview("中文") {
    NavigationStack { AISettingsView(settings: AISettings(defaults: UserDefaults(suiteName: "ai-preview")!, keys: AIMemoryKeyStore())) }
        .environment(\.locale, Locale(identifier: "zh-Hans")).preferredColorScheme(.dark)
}

#Preview("English") {
    NavigationStack { AISettingsView(settings: AISettings(defaults: UserDefaults(suiteName: "ai-preview")!, keys: AIMemoryKeyStore())) }
        .environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark)
}
