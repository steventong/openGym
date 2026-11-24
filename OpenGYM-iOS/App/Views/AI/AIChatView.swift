import SwiftUI

/// AI 教练对话页。
struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var chat: AIChatStore
    @State private var confirmNewChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if chat.messages.isEmpty {
                        AIChatWelcome(settings: chat.settings) { chat.input = $0 }
                    }
                    // 工具结果显示在发起调用的回复里，不单独占一行。
                    ForEach(chat.messages.filter { if case .toolResults = $0.content { false } else { true } }) { message in
                        AIMessageView(message: message, results: results(after: message))
                    }
                    AIPhaseView(phase: chat.phase, decide: chat.decide, retry: chat.retry)
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .background(GymTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AIComposer(text: $chat.input, busy: chat.isBusy, canSend: chat.canSend, send: chat.send, stop: chat.stop)
            }
            .navigationTitle("AI_COACH")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("DONE") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmNewChat = true } label: { Image(systemName: "square.and.pencil") }
                        .disabled(chat.isBusy || chat.messages.isEmpty)
                        .accessibilityLabel("AI_NEW_CHAT")
                        .accessibilityIdentifier("ai-new-chat")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { AISettingsView(settings: chat.settings) } label: { Image(systemName: "slider.horizontal.3") }
                        .disabled(chat.isBusy)
                        .accessibilityLabel("AI_SETTINGS")
                }
            }
            .confirmationDialog("AI_NEW_CHAT_CONFIRM", isPresented: $confirmNewChat, titleVisibility: .visible) {
                Button("AI_NEW_CHAT", role: .destructive, action: chat.newChat)
                Button("CANCEL", role: .cancel) {}
            }
            .onAppear(perform: chat.load)
        }
        .tint(GymTheme.green)
    }

    /// 工具结果跟在发起调用的回复之后，显示在各自的调用下面。
    private func results(after message: AIMessage) -> [AIToolResult] {
        guard case .assistant = message.content, let index = chat.messages.firstIndex(where: { $0.id == message.id }),
              chat.messages.indices.contains(index + 1), case let .toolResults(results) = chat.messages[index + 1].content else { return [] }
        return results
    }
}

private struct AIChatWelcome: View {
    let settings: AISettings
    let choose: (String) -> Void
    private let suggestions: [String.LocalizationValue] = ["AI_SUGGESTION_PLAN", "AI_SUGGESTION_REVIEW", "AI_SUGGESTION_FIX", "AI_SUGGESTION_TODAY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(GymTheme.green).accessibilityHidden(true)
            Text(settings.isConfigured ? "AI_WELCOME" : "AI_NOT_CONFIGURED").font(.title3.weight(.semibold))
            Text("AI_WELCOME_INFO").font(.subheadline).foregroundStyle(GymTheme.muted)
            if settings.isConfigured {
                ForEach(suggestions.indices, id: \.self) { index in
                    Button { choose(aiText(suggestions[index])) } label: {
                        Text(aiText(suggestions[index])).font(.subheadline).foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                NavigationLink { AISettingsView(settings: settings) } label: {
                    Text("AI_SETTINGS").fontWeight(.semibold).foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ai-setup")
            }
        }
        .padding(.vertical, 12)
    }
}

private struct AIPhaseView: View {
    let phase: AIChatPhase
    let decide: (AIApprovalDecision) -> Void
    let retry: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case let .responding(text):
            if text.isEmpty {
                HStack(spacing: 8) { ProgressView(); Text("AI_THINKING").font(.subheadline).foregroundStyle(GymTheme.muted) }
            } else {
                AIMarkdownText(text: text)
            }
        case let .runningTool(name):
            HStack(spacing: 8) {
                ProgressView()
                Text(AIToolLabel.title(name)).font(.subheadline).foregroundStyle(GymTheme.muted)
            }
        case let .awaitingApproval(approval):
            AIApprovalCard(summary: approval.summary, decide: decide)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(.subheadline).foregroundStyle(.orange)
                Button("AI_RETRY", action: retry).buttonStyle(.bordered).accessibilityIdentifier("ai-retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AIComposer: View {
    @Binding var text: String
    let busy: Bool
    let canSend: Bool
    let send: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("AI_INPUT_PLACEHOLDER", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(GymTheme.card, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("ai-input")
            if busy {
                Button(action: stop) { Image(systemName: "stop.circle.fill").font(.system(size: 34)) }
                    .accessibilityLabel("AI_STOP").accessibilityIdentifier("ai-stop")
            } else {
                Button { GymKeyboard.dismiss(); send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                    .disabled(!canSend)
                    .accessibilityLabel("AI_SEND").accessibilityIdentifier("ai-send")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

/// 预览用的固定回复，不访问网络。
private struct AIPreviewResponder: AIResponder {
    func respond(to request: AIRequest, onText: @MainActor (String) -> Void) async throws -> AIAssistantTurn {
        onText("好的")
        return AIAssistantTurn(text: "好的")
    }
}

#Preview("确认修改") {
    @Previewable @State var store = GymStore(userID: "preview")
    let chat = AIChatStore(store: store, settings: store.aiSettings, responder: AIPreviewResponder())
    chat.loaded = true
    chat.messages = [
        AIMessage(content: .user(text: "把推日的卧推加到 4 组", context: "")),
        AIMessage(content: .assistant(AIAssistantTurn(text: "先看一下现在的安排。", calls: [AIToolCall(id: "1", name: "get_routine", arguments: "{}")]))),
        AIMessage(content: .toolResults([AIToolResult(callID: "1", outcome: .completed, content: "{}")])),
    ]
    chat.phase = .awaitingApproval(AIPendingApproval(callID: "2", summary: AIProposalSummary(title: "修改计划“推日”", changes: [
        AIChange(label: "杠铃卧推", before: "3×10 · 60 kg", after: "4×8 · 62.5 kg")])) { _ in })
    return AIChatView(chat: chat).environment(store)
        .environment(\.locale, Locale(identifier: "zh-Hans")).preferredColorScheme(.dark)
}

#Preview("English · Empty") {
    @Previewable @State var store = GymStore(userID: "preview")
    AIChatView(chat: AIChatStore(store: store, settings: store.aiSettings, responder: AIPreviewResponder())).environment(store)
        .environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark)
}
