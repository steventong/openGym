import SwiftUI

enum TrainingCountdownPresentation {
    case seconds
    case systemTimer
}

/// Live Activities use WidgetKit's native timer text. App and Watch seconds
/// tick only this leaf view, without rebuilding their enclosing control.
struct TrainingCountdownText: View {
    let end: Date
    var pausedRemaining: TimeInterval? = nil
    var minimumIntegerDigits = 1
    var suffix = "S"
    var presentation: TrainingCountdownPresentation = .seconds

    var body: some View {
        Group {
            if let pausedRemaining {
                Text(TrainingCountdownSecondsStyle(end: end, minimumIntegerDigits: minimumIntegerDigits, suffix: suffix)
                    .formattedSeconds(pausedRemaining))
            } else if presentation == .systemTimer {
                Text(timerInterval: Self.timerInterval(endingAt: end), countsDown: true, showsHours: false)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TrainingCountdownSecondsStyle(end: end,
                        minimumIntegerDigits: minimumIntegerDigits, suffix: suffix).format(context.date))
                }
            }
        }.monospacedDigit().contentTransition(.numericText(countsDown: true))
    }

    static func timerInterval(endingAt end: Date, now: Date = Date()) -> ClosedRange<Date> {
        now...max(now, end)
    }
}

// Static formatting only (paused timers and the App/Watch local timeline).
// Never pass this app-defined type to Text's TimeDataSource initializer.
struct TrainingCountdownSecondsStyle {
    var end: Date
    var minimumIntegerDigits = 1
    var suffix = "S"
    func formattedSeconds(_ remaining: TimeInterval) -> String {
        let digits = String(max(0, Int(ceil(remaining))))
        return String(repeating: "0", count: max(0, minimumIntegerDigits - digits.count)) + digits + suffix
    }
    func format(_ value: Date) -> String { formattedSeconds(end.timeIntervalSince(value)) }
    func discreteInput(after input: Date) -> Date? {
        let seconds = Int(ceil(end.timeIntervalSince(input)))
        return seconds > 0 ? end.addingTimeInterval(-Double(seconds - 1)) : nil
    }
    func discreteInput(before input: Date) -> Date? {
        if input > end { return end }
        return end.addingTimeInterval(-floor(end.timeIntervalSince(input)) - 0.000001)
    }
}

/// Hosts one Button/Intent/Link; ownership of the action stays with its platform.
/// Only the protection deadline refreshes this container. Seconds update in Text.
struct TrainingActionControl<Content: View>: View {
    var title: String
    var symbol: String
    var timing: TrainingActionTiming
    var disabled = false
    var tint: Color = .green
    var scale: CGFloat = 1
    var readyHint: String? = nil
    var language: String? = nil
    // An invalidation input for ActivityKit's stale-date redraw, not permission to
    // unlock early: the absolute deadline remains authoritative on every surface.
    var systemDeadlinePassed = false
    var countdownPresentation: TrainingCountdownPresentation = .seconds
    @ViewBuilder var control: (TrainingActionLabel) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var evaluatedAt = Date()

    var body: some View {
        let protected = timing.isProtected(at: max(evaluatedAt, Date()))
        let unavailable = disabled || protected
        control(TrainingActionLabel(title: title, symbol: symbol,
            protectionEnd: protected ? timing.readyAt : nil,
            disabled: unavailable, tint: tint, scale: scale,
            restEnd: timing.restEnd, readyHint: readyHint, language: language, countdownPresentation: countdownPresentation))
            .buttonStyle(.plain).disabled(unavailable)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: unavailable)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: title)
            #if !WORKOUT_WIDGET
            .task(id: timing.readyAt) {
                evaluatedAt = Date()
                guard let end = timing.readyAt, end > evaluatedAt else { return }
                do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
                catch { return }
                guard !Task.isCancelled else { return }
                evaluatedAt = Date()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { evaluatedAt = Date() } }
            #endif
    }
}

struct TrainingActionLabel: View {
    let title: String
    let symbol: String
    let protectionEnd: Date?
    let disabled: Bool
    let tint: Color
    var scale: CGFloat = 1
    var restEnd: Date? = nil
    var readyHint: String? = nil
    var language: String? = nil
    var countdownPresentation: TrainingCountdownPresentation = .seconds
    @Environment(\.isEnabled) private var isEnabled

    private var unavailable: Bool { disabled || !isEnabled }
    private var isQuietReady: Bool { restEnd == nil && readyHint != nil }
    private var foreground: Color {
        unavailable ? .secondary : (isQuietReady ? tint : .black)
    }
    private var background: Color {
        unavailable ? .gray.opacity(0.25) : (isQuietReady ? tint.opacity(0.18) : tint)
    }

    var body: some View {
        stackedLabel
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity).frame(height: 62 * scale)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 17 * scale))
        .contentShape(RoundedRectangle(cornerRadius: 17 * scale))
        .accessibilityElement(children: .combine)
    }

    private var stackedLabel: some View {
        VStack(spacing: 4 * scale) {
            if let restEnd {
                HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                    Text(L10n.format("REST_BETWEEN_SETS", language: language ?? L10n.language))
                        .font(.system(size: 10 * scale, weight: .medium))
                    Spacer(minLength: 2)
                    HStack(alignment: .firstTextBaseline, spacing: 2 * scale) {
                        TrainingCountdownText(end: restEnd, minimumIntegerDigits: 3, suffix: "", presentation: countdownPresentation)
                            .font(.system(size: 32 * scale, weight: .semibold, design: .monospaced))
                            .frame(width: countdownPresentation == .systemTimer ? 120 * scale : nil, alignment: .trailing)
                        if countdownPresentation == .seconds {
                            Text("S").font(.system(size: 20 * scale, weight: .semibold))
                        }
                    }.layoutPriority(1)
                }
            } else if let readyHint {
                Text(readyHint).font(.system(size: 10 * scale))
            }
            HStack(spacing: 4 * scale) {
                Image(systemName: symbol)
                Text(title).contentTransition(.opacity)
                if let protectionEnd {
                    TrainingCountdownText(end: protectionEnd, presentation: countdownPresentation)
                        .font(.system(size: 10 * scale, weight: .medium))
                        .frame(width: 24 * scale, alignment: .trailing)
                }
            }.font(.system(size: (restEnd == nil ? 15 : 12) * scale, weight: .semibold))
        }.padding(.horizontal, 12 * scale)
    }
}
