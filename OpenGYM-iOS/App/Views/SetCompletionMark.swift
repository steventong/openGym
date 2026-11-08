import SwiftUI

/// The corner badge adds failure information without changing the set row's layout.
struct SetCompletionMark: View {
    let completed: Bool
    let failure: Bool
    let height: CGFloat
    private let completedColor = Color(red: 0.60, green: 0.88, blue: 0.52)

    var body: some View {
        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
            .foregroundStyle(completed ? Color.black : .gray)
            .frame(width: 44, height: height)
            .background(completed ? completedColor : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if failure {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(completed ? Color.black : .orange)
                        .padding(2).background(completed ? completedColor : GymTheme.card, in: Circle())
                        .padding(4)
                }
            }
    }
}
