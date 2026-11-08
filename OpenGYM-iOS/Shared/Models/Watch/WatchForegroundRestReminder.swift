import Foundation

/// Direct feedback has its own deadline; an active workout also permits background haptics.
struct WatchForegroundRestReminder {
    private enum Phase {
        case inactive, armed, delivered
    }

    private(set) var key: String?
    private(set) var deadline: Date?
    private var phase = Phase.inactive
    var didAlert: Bool { phase == .delivered }

    mutating func update(_ snapshot: WatchTrainingSnapshot, active: Bool, workoutRunning: Bool = false, now: Date) -> Date? {
        if key != snapshot.restReminderKey {
            key = snapshot.restReminderKey
            deadline = key == nil ? nil : snapshot.restEnd
            phase = .inactive
        }
        if !active && !workoutRunning {
            if phase == .armed { phase = .inactive }
        } else if phase != .delivered, let deadline, deadline > now {
            phase = .armed
        }
        // Keep an already armed deadline across a same-rest refresh at expiry, but never
        // replay an expired rest when opening the app or returning from the background.
        return phase == .armed ? deadline : nil
    }

    mutating func consume(key: String, now: Date) -> Bool {
        guard self.key == key, phase == .armed, let deadline, now >= deadline else { return false }
        phase = .delivered
        return true
    }
}
