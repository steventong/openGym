import SwiftUI

/// System-driven text updates do not invalidate the enclosing button or page.
struct TrainingCountdownText: View {
    let end: Date
    var pausedRemaining: TimeInterval? = nil
    var minimumIntegerDigits = 1
    var suffix = "S"

    var body: some View {
        Group {
            if let pausedRemaining {
                Text(TrainingCountdownSecondsStyle(end: end, minimumIntegerDigits: minimumIntegerDigits, suffix: suffix)
                    .formattedSeconds(pausedRemaining))
            } else if #available(iOS 18, watchOS 11, *) {
                // Live Activities are decoded in a system renderer that cannot
                // resolve app-defined DiscreteFormatStyle types. Keep the live
                // format entirely in Foundation; append our shared unit as Text.
                ZStack(alignment: .trailing) {
                    Text(String(repeating: "0", count: minimumIntegerDigits) + suffix).hidden()
                    Text("\(Text(.dateRange(endingAt: Self.displayDeadline(end)), format: Self.secondsFormat))\(suffix)")
                        .fixedSize()
                }
            } else {
                // watchOS 10 fallback: only this text has a periodic timeline.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TrainingCountdownSecondsStyle(end: end,
                        minimumIntegerDigits: minimumIntegerDigits, suffix: suffix).format(context.date))
                }
            }
        }.monospacedDigit().contentTransition(.numericText(countsDown: true))
    }

    @available(iOS 18, watchOS 11, *)
    static var secondsFormat: Date.ComponentsFormatStyle {
        var format = Date.ComponentsFormatStyle.timeDuration
        format.fields = [.second]
        format.locale = Locale(identifier: "en_US_POSIX")
        return format
    }

    // Foundation truncates fractional seconds; shift by just under one second
    // to retain the existing ceil-to-seconds display. dateRange clamps at zero.
    static func displayDeadline(_ end: Date) -> Date { end.addingTimeInterval(0.999999) }
}

// Static formatting only (paused timers and the watchOS 10 local timeline).
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
            restEnd: timing.restEnd, readyHint: readyHint, language: language))
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
                        TrainingCountdownText(end: restEnd, minimumIntegerDigits: 3, suffix: "")
                            .font(.system(size: 32 * scale, weight: .semibold, design: .monospaced))
                        Text("S")
                            .font(.system(size: 20 * scale, weight: .semibold))
                    }.layoutPriority(1)
                }
            } else if let readyHint {
                Text(readyHint).font(.system(size: 10 * scale))
            }
            HStack(spacing: 4 * scale) {
                Image(systemName: symbol)
                Text(title).contentTransition(.opacity)
                if let protectionEnd {
                    TrainingCountdownText(end: protectionEnd)
                        .font(.system(size: 10 * scale, weight: .medium))
                        .frame(width: 24 * scale, alignment: .trailing)
                }
            }.font(.system(size: (restEnd == nil ? 15 : 12) * scale, weight: .semibold))
        }.padding(.horizontal, 12 * scale)
    }
}
