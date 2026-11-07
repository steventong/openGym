import SwiftUI

struct WorkoutNoteView: View {
    let note: String?

    var body: some View {
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(note).font(.subheadline).foregroundStyle(GymTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("live-workout-note-display")
        }
    }
}

#Preview {
    WorkoutNoteView(note: "Keep a steady pace.")
}
