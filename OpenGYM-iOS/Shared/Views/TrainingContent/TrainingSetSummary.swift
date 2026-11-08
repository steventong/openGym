import SwiftUI

struct TrainingSetSummary: View {
    let weight: String
    let detail: String
    let label: String
    var scale: CGFloat = 1
    var weightFontSize: CGFloat = 20
    var labelFontSize: CGFloat = 13
    var detailFontSize: CGFloat = 10
    var detailFontWeight: Font.Weight = .regular
    var detailColor: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 5 * scale) {
                Text(weight).font(.system(size: weightFontSize * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail).font(.system(size: detailFontSize * scale, weight: detailFontWeight)).foregroundStyle(detailColor)
            }.lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 0)
            Text(label).font(.system(size: labelFontSize * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(TrainingDisplayStyle.green)
                .multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 9 * scale)
        .frame(maxWidth: .infinity)
        .frame(height: TrainingDisplayStyle.summaryHeight * scale)
    }
}
