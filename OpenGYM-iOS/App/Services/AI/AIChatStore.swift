import Foundation
import Observation

/// 一次等待用户确认的修改。
struct AIPendingApproval {
    let callID: String
    let summary: AIProposalSummary
    /// 恢复等待中的任务；只调用一次。
    let decide: (AIApprovalDecision) -> Void
}

enum AIApprovalDecision { case confirmed, declined, cancelled }

/// 对话当前所处的阶段，各阶段互斥。
enum AIChatPhase {
    case idle
    /// 正在接收回复，附带已收到的文字。
    case responding(String)
    case runningTool(String)
    case awaitingApproval(AIPendingApproval)
    case failed(String)
}

/// AI 对话的状态与依赖。数据流：用户消息 → 模型回复 → 工具调用（查询直接执行，修改先等确认）
/// → 结果回给模型，循环到模型不再调用工具。处理方法见 AIChatStore+Actions.swift。
@MainActor @Observable final class AIChatStore {
    /// 对话记录，只追加；保存在本机文件，不随 iCloud 同步。
    var messages: [AIMessage] = []
    var phase = AIChatPhase.idle
    /// 尚未发送的输入，关闭页面后保留。
    var input = ""
    let settings: AISettings
    @ObservationIgnored weak var store: GymStore?
    @ObservationIgnored let responder: AIResponder
    /// 正在进行的一轮对话，供停止时取消。
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var loaded = false

    /// 一条用户消息最多连续调用模型的次数，防止无限循环消耗额度。
    static let stepLimit = 25

    init(store: GymStore, settings: AISettings, responder: AIResponder) {
        self.store = store
        self.settings = settings
        self.responder = responder
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .failed: false
        case .responding, .runningTool, .awaitingApproval: true
        }
    }
    var canSend: Bool { !isBusy && settings.isConfigured && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
