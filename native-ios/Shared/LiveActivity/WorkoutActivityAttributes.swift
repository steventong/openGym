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
        var setCompletionLabel: String? = nil
        // Optional for activities created by older builds. Busy state stays inside the button.
        var busyTitle: String? = nil
        var actionReadyAt: Date? = nil
        var setStartedAt: Date? = nil
        var language: String? = nil
        var actionTiming: TrainingActionTiming { .init(restEnd: restEnd, readyAt: actionReadyAt) }
    }

    var account: String
    var sessionID: String
}
