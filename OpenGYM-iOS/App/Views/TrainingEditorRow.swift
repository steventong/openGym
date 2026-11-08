import Foundation

struct TrainingEditorRow: Identifiable {
    let id: String
    let raw: [String: Any]
    var accessibilityIdentifier: String? = nil
}
