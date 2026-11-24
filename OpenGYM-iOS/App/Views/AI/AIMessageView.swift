import SwiftUI

/// 一条对话消息。工具结果由发起调用的回复一起显示。
struct AIMessageView: View {
    let message: AIMessage
    let results: [AIToolResult]

    var body: some View {
        switch message.content {
        case let .user(text, _):
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(.black)
                .background(GymTheme.green, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case let .assistant(turn):
            VStack(alignment: .leading, spacing: 10) {
                if !turn.text.isEmpty { AIMarkdownText(text: turn.text) }
                ForEach(turn.calls) { call in
                    if let result = results.first(where: { $0.callID == call.id }) { AIToolResultView(call: call, result: result) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .toolResults:
            EmptyView()
        }
    }
}

enum AIToolLabel {
    static func title(_ name: String) -> String {
        guard AITool.all.contains(where: { $0.name == name }) else { return name }
        return aiText(String.LocalizationValue("AI_TOOL_" + name.uppercased()))
    }
}

private struct AIToolResultView: View {
    let call: AIToolCall
    let result: AIToolResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                HStack {
                    Text(result.summary?.title ?? AIToolLabel.title(call.name))
                    Spacer()
                    Text(status)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            .font(.footnote).foregroundStyle(GymTheme.muted)
            if let summary = result.summary, !summary.changes.isEmpty { AIChangeList(changes: summary.changes) }
        }
        .padding(result.summary == nil ? 0 : 14)
        .background(result.summary == nil ? Color.clear : GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var status: LocalizedStringKey {
        switch result.outcome {
        case .completed: result.summary == nil ? "AI_STATUS_READ" : "AI_STATUS_SAVED"
        case .declined: "AI_STATUS_DECLINED"
        case .failed: "AI_STATUS_FAILED"
        case .cancelled: "AI_STATUS_STOPPED"
        }
    }
    private var icon: String {
        switch result.outcome {
        case .completed: result.summary == nil ? "magnifyingglass" : "checkmark.circle.fill"
        case .declined: "xmark.circle"
        case .failed: "exclamationmark.circle"
        case .cancelled: "stop.circle"
        }
    }
    private var color: Color {
        switch result.outcome {
        case .completed: result.summary == nil ? GymTheme.muted : GymTheme.green
        case .failed: .orange
        case .declined, .cancelled: GymTheme.muted
        }
    }
}

/// 修改前的二次确认：列出全部改动，用户确认后才写入。
struct AIApprovalCard: View {
    let summary: AIProposalSummary
    let decide: (AIApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label { Text(summary.title) } icon: { Image(systemName: summary.destructive ? "trash" : "pencil") }
                .font(.headline)
                .foregroundStyle(summary.destructive ? Color.red : .white)
            if !summary.changes.isEmpty { AIChangeList(changes: summary.changes) }
            Text(summary.destructive ? "AI_CONFIRM_DELETE_INFO" : "AI_CONFIRM_INFO").font(.caption).foregroundStyle(GymTheme.muted)
            HStack(spacing: 12) {
                Button { decide(.declined) } label: { Text("AI_DECLINE").frame(maxWidth: .infinity, minHeight: 32) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("ai-decline")
                Button(role: summary.destructive ? .destructive : nil) { decide(.confirmed) } label: {
                    Text(summary.destructive ? "DELETE" : "AI_CONFIRM").fontWeight(.semibold)
                        .foregroundStyle(summary.destructive ? .white : .black)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(summary.destructive ? .red : GymTheme.green)
                .accessibilityIdentifier("ai-confirm")
            }
        }
        .gymCard()
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(summary.destructive ? Color.red : GymTheme.green, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-approval")
    }
}

private struct AIChangeList: View {
    let changes: [AIChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(changes.indices, id: \.self) { index in
                let change = changes[index]
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.label).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    if let before = change.before {
                        Text(before).font(.footnote).foregroundStyle(GymTheme.muted).strikethrough()
                            .accessibilityLabel(aiText("AI_BEFORE_COUNT", before))
                    }
                    if let after = change.after {
                        Text(after).font(.footnote).foregroundStyle(GymTheme.green)
                            .accessibilityLabel(aiText("AI_AFTER_COUNT", after))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 回复正文：逐行显示标题、列表和行内强调，流式输出时未写完的标记也能正常显示。
struct AIMarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            ForEach(lines.indices, id: \.self) { index in
                AIMarkdownLine(line: lines[index])
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIMarkdownLine: View {
    let line: String

    var body: some View {
        if line.hasPrefix("#") {
            Text(inline(line.drop { $0 == "#" || $0 == " " })).font(.headline)
        } else if let item = ["- ", "* ", "• "].first(where: line.hasPrefix).map({ line.dropFirst($0.count) }) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•").foregroundStyle(GymTheme.green)
                Text(inline(item))
            }
        } else {
            Text(inline(line[...]))
        }
    }

    private func inline(_ text: Substring) -> AttributedString {
        (try? AttributedString(markdown: String(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(String(text))
    }
}

#Preview("Approval") {
    VStack(spacing: 20) {
        AIApprovalCard(summary: AIProposalSummary(title: "修改计划“推日”", changes: [
            AIChange(label: "杠铃卧推", before: "3×10 · 60 kg", after: "4×8 · 62.5 kg"),
            AIChange(label: "绳索飞鸟", after: "3×12 · 15 kg")])) { _ in }
        AIApprovalCard(summary: AIProposalSummary(title: "删除训练“推日 · 2026-11-20”", changes: [AIChange(label: "杠铃卧推", before: "60×8, 60×8")], destructive: true)) { _ in }
    }
    .padding().background(GymTheme.background).preferredColorScheme(.dark)
    .environment(\.locale, Locale(identifier: "zh-Hans"))
}
