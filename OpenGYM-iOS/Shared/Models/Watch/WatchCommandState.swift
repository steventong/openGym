import Foundation

/// A command stays attached to its confirmation state, including after a retry.
enum WatchCommandState: Equatable {
    case idle
    case sending(WatchTrainingCommand)
    case awaitingConfirmation(WatchTrainingCommand)

    var command: WatchTrainingCommand? {
        switch self {
        case .idle: nil
        case .sending(let command), .awaitingConfirmation(let command): command
        }
    }

    var isSending: Bool {
        if case .sending = self { return true }
        return false
    }

    @discardableResult
    mutating func markUnconfirmed(commandID: String) -> Bool {
        guard case .sending(let command) = self, command.id == commandID else { return false }
        self = .awaitingConfirmation(command)
        return true
    }
}
