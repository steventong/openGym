import SwiftUI
import UIKit

enum GymKeyboard {
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

enum GymTheme {
    static let green = Color(red:0.39, green:0.80, blue:0.35)
    static let background = Color(red:0.025, green:0.025, blue:0.025)
    static let card = Color(red:0.115, green:0.115, blue:0.12)
    static let muted = Color(white:0.54)
}
extension View {
    func stableInputLine(height: CGFloat = 24) -> some View {
        modifier(StableInputLine(height: height))
    }
    /// Number and decimal pads have no return key, so provide a native keyboard toolbar.
    /// Install once on the containing screen, not on each repeated input row.
    func keyboardDismissToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("FOLD_AWAY", action: GymKeyboard.dismiss)
                    .accessibilityIdentifier("dismiss-keyboard")
            }
        }
    }
    func gymCard() -> some View { padding(18).background(GymTheme.card,in:RoundedRectangle(cornerRadius:20)) }
    func operationAlert(_ issue: Binding<String?>, title: LocalizedStringKey = "COULD_NOT_COMPLETE_ACTION") -> some View {
        alert(title, isPresented: Binding(get: { issue.wrappedValue != nil }, set: { if !$0 { issue.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(issue.wrappedValue ?? "") }
    }
    func invalidInput(_ invalid: Bool) -> some View {
        let hint: LocalizedStringKey = invalid ? "INVALID_INPUT_PLEASE_CHECK" : ""
        return overlay(RoundedRectangle(cornerRadius: 4).stroke(invalid ? Color.orange : .clear))
            .accessibilityHint(hint)
    }
}

/// Keep single-line input geometry independent of focus, while following Dynamic Type.
private struct StableInputLine: ViewModifier {
    @ScaledMetric private var height: CGFloat

    init(height: CGFloat) {
        _height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.lineLimit(1).frame(height: height)
    }
}

/// Details are available on demand without inserting explanatory rows into the screen.
struct ExplanationButton: View {
    let title: String.LocalizationValue
    let message: LocalizedStringKey
    @State private var showing = false
    var body: some View {
        let title = String(localized: self.title, bundle: AppLanguage.bundle, locale: AppLanguage.locale)

        Button { showing = true } label: { Image(systemName: "info.circle").frame(width: 28, height: 28) }
            .buttonStyle(.borderless).accessibilityLabel(String(format: String(localized: "ABOUT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: title)))
            .alert(title, isPresented: $showing) { Button("OK", role: .cancel) {} } message: { Text(message) }
    }
}

struct StatusDetailButton: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var warning = false
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Label(title, systemImage: warning ? "exclamationmark.circle" : "info.circle")
                .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(warning ? Color.orange : GymTheme.muted)
        }.buttonStyle(.borderless).accessibilityHint("VIEW_DETAILS")
            .alert(title, isPresented: $showing) { Button("OK", role: .cancel) {} } message: { Text(message) }
    }
}
struct GreenButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:8) { if let icon { Image(systemName:icon) }; Text(title).fontWeight(.semibold) }
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth:.infinity).padding(.vertical,16)
                .foregroundStyle(isEnabled ? Color.black : GymTheme.muted)
                .background(isEnabled ? GymTheme.green : Color.gray.opacity(0.25),in:RoundedRectangle(cornerRadius:15))
        }.buttonStyle(.plain)
    }
}
struct Pill: View {
    let title: LocalizedStringKey
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action:action) { Text(title).font(.system(size:13,weight:.medium)).padding(.horizontal,15).padding(.vertical,9)
            .foregroundStyle(selected ? .black : .white.opacity(0.85))
            .background(selected ? GymTheme.green : GymTheme.card,in:Capsule()) }.buttonStyle(.plain)
    }
}
struct SectionTitle: View {
    let text: LocalizedStringKey
    var body: some View { Text(text).font(.system(size:20,weight:.bold)).frame(maxWidth:.infinity,alignment:.leading) }
}
struct EmptyCard: View {
    let icon: String
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var body: some View {
        VStack(spacing:12) {
            Image(systemName:icon).font(.system(size:30,weight:.light)).foregroundStyle(GymTheme.green).padding(.bottom,6)
            Text(title).font(.headline)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(GymTheme.muted).multilineTextAlignment(.center) }
        }.frame(maxWidth:.infinity).padding(.vertical,30).gymCard()
    }
}
/// Only the clean/dirty transition is observable; keystrokes stay inside the input view.
/// Flush before actions that read or replace the form, without waiting for a focus update.
@MainActor @Observable final class InputCommitBuffer {
    @ObservationIgnored private var pending: [UUID: (write: () -> Void, cancel: () -> Void)] = [:]
    private(set) var hasPending = false

    func stage(_ id: UUID, cancel: @escaping () -> Void = {}, commit: @escaping () -> Void) {
        pending[id] = (commit, cancel)
        if !hasPending { hasPending = true }
    }
    func commit(_ id: UUID) {
        let entry = pending.removeValue(forKey: id)
        updatePending()
        entry?.write()
    }
    func commitAll() {
        let entries = Array(pending.values)
        pending.removeAll()
        updatePending()
        for entry in entries { entry.write() }
    }
    func discardAll() {
        let entries = Array(pending.values)
        pending.removeAll()
        updatePending()
        for entry in entries { entry.cancel() }
    }
    private func updatePending() {
        let next = !pending.isEmpty
        if hasPending != next { hasPending = next }
    }
}

private struct InputCommitBufferKey: EnvironmentKey {
    static let defaultValue: InputCommitBuffer? = nil
}
extension EnvironmentValues {
    var inputCommitBuffer: InputCommitBuffer? {
        get { self[InputCommitBufferKey.self] }
        set { self[InputCommitBufferKey.self] = newValue }
    }
}

private struct BufferedInput<Value: Equatable, Content: View>: View {
    @Binding var value: Value
    @ViewBuilder let content: (Binding<Value>) -> Content
    @Environment(\.inputCommitBuffer) private var buffer
    @State private var draft: Value?
    @State private var id = UUID()
    @FocusState private var focused: Bool

    var body: some View {
        content(Binding(get: { draft ?? value }, set: { next in
            guard let buffer else { value = next; return }
            draft = next
            buffer.stage(id, cancel: { draft = nil }) {
                draft = nil
                if next != value { value = next }
            }
        }))
        .focused($focused)
        .onChange(of: focused) { _, isFocused in
            if !isFocused { buffer?.commit(id) }
        }
        .onSubmit { buffer?.commit(id) }
        .onDisappear { buffer?.commit(id) }
    }
}

struct BufferedTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var axis: Axis
    init(_ title: LocalizedStringKey, text: Binding<String>, axis: Axis = .horizontal) {
        self.title = title; _text = text; self.axis = axis
    }
    var body: some View {
        BufferedInput(value: $text) { TextField(title, text: $0, axis: axis) }
    }
}

/// Keep native locale-aware numeric formatting, but write the parsed value on blur.
struct BufferedNumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    init(_ title: LocalizedStringKey, value: Binding<Double>) { self.title = title; _value = value }
    var body: some View {
        BufferedInput(value: $value) { TextField(title, value: $0, format: .number) }
    }
}
