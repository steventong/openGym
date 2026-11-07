import SwiftUI

struct CoachTextList: View {
    let title: String
    let items: [String]
    let symbol: String

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(GymTheme.green)
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    Text("• " + text).font(.subheadline)
                }
            }
        }
    }
}
