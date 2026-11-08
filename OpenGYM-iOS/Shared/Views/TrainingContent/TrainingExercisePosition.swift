import SwiftUI

struct TrainingExercisePosition: View {
    let position: String
    var scale: CGFloat = 1
    var fontSize: CGFloat = 13
    var fontWeight: Font.Weight = .regular
    var textColor: Color = .secondary

    var body: some View {
        Text(position).font(.system(size: fontSize * scale, weight: fontWeight)).foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .fixedSize(horizontal: true, vertical: false)
    }
}
