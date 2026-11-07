import SwiftUI

struct ExerciseDetailActionIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold)).foregroundStyle(.gray)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.07), in: Circle())
    }
}

#Preview {
    ExerciseDetailActionIcon(symbol: "doc.on.doc")
}
