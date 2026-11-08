import SwiftUI

struct CoachMessageBubble: View {
    let text: String
    let user: Bool
    var failed = false

    var body: some View {
        HStack {
            if user { Spacer(minLength: 32) }
            Text(text).textSelection(.enabled).font(.body)
                .foregroundStyle(failed ? Color.orange : Color.primary).padding(15)
                .background(user ? GymTheme.green.opacity(0.18) : GymTheme.card, in: RoundedRectangle(cornerRadius: 18))
            if !user { Spacer(minLength: 20) }
        }
    }
}

#Preview {
    CoachMessageBubble(text: "Ready for the next workout.", user: false)
}
