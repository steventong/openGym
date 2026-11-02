import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trainingName: String
        var exercise: String
        var position: String
        var setLabel: String
        var compactSet: String
        var detail: String
        var message: String
        var restEnd: Date?
        var restExercise: String
        var command: String?
        var commandTitle: String
        var restCommand: String?
        // Optional so activities created before the inline summary still decode.
        var setWeight: String? = nil
        var setDetail: String? = nil
    }

    var account: String
    var sessionID: String
}
