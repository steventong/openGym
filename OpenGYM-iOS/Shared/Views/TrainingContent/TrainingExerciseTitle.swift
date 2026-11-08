import SwiftUI

struct TrainingExerciseTitle: View {
    let title: String
    var scale: CGFloat = 1

    var body: some View {
        Text(title)
            .font(.system(size: 15 * scale, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1, reservesSpace: true)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
