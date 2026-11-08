import SwiftUI

struct CoachStrengthRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
        }.font(.caption)
    }
}
