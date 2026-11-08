import SwiftUI

struct CoachIntakeChoices: View {
    let items: [(String, LocalizedStringKey, LocalizedStringKey)]
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(items, id: \.0) { item in
                Button { selection = item.0 } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.1).font(.headline)
                            Text(item.2).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selection == item.0 ? "checkmark.circle.fill" : "circle").foregroundStyle(GymTheme.green)
                    }.frame(maxWidth: .infinity, alignment: .leading).gymCard()
                }.buttonStyle(.plain).accessibilityIdentifier("coach-answer-" + item.0)
            }
        }
    }
}
