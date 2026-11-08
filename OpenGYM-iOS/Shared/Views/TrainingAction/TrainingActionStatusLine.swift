import SwiftUI

/// 按钮上排：训练／组间休息标题和对应的系统计时文字，语言继承环境。
struct TrainingActionStatusLine: View {
    let status: TrainingActionStatus
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
            Text(LocalizedStringKey(status.titleKey))
                .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
                // 系统计时文字会占满可用宽度，优先为状态标题保留空间。
                .layoutPriority(1)

            // 系统计时文字在已归档的 Live Activity 视图中也能继续更新。
            Group {
                switch status {
                case .rest(let end):
                    TrainingCountdownText(end: end, presentation: .systemTimer)
                case .workout(let start?):
                    Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
                case .workout(nil):
                    Text(verbatim: "00:00")
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 24 * scale, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }
}

#Preview("训练", traits: .sizeThatFitsLayout) {
    TrainingActionStatusLine(status: .workout(startedAt: .now.addingTimeInterval(-45)))
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .frame(width: 164)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("组间休息", traits: .sizeThatFitsLayout) {
    TrainingActionStatusLine(status: .rest(endsAt: .now.addingTimeInterval(75)))
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .frame(width: 164)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}
