import SwiftUI

/// 手表、锁屏和灵动岛共用的训练操作外观，不负责处理点击或修改训练数据。
/// 上排显示训练／组间休息计时，下排仅可点击时显示操作文字，隐藏时保留占位。
struct TrainingActionLabel: View {
    let title: String
    let symbol: String
    let status: TrainingActionStatus
    let disabled: Bool
    let tint: Color
    var scale: CGFloat = 1
    @Environment(\.isEnabled) private var isEnabled

    private var unavailable: Bool { disabled || !isEnabled }

    var body: some View {
        VStack(spacing: TrainingDisplayStyle.actionLineSpacing * scale) {
            TrainingActionStatusLine(status: status, scale: scale)

            Label(title, systemImage: symbol)
                .font(.system(size: 16 * scale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(unavailable ? 0 : 1)
                .accessibilityHidden(unavailable)
        }
        .padding(.horizontal, 10 * scale)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity).frame(height: TrainingDisplayStyle.actionHeight * scale)
        .foregroundStyle(unavailable ? Color.secondary : .black)
        .background(unavailable ? Color.gray.opacity(0.25) : tint, in: RoundedRectangle(cornerRadius: 17 * scale))
        .contentShape(RoundedRectangle(cornerRadius: 17 * scale))
        .accessibilityElement(children: .combine)
    }
}

#Preview("训练", traits: .sizeThatFitsLayout) {
    TrainingActionLabel(title: "完成", symbol: "checkmark", status: .workout(startedAt: nil),
        disabled: false, tint: TrainingDisplayStyle.green)
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .frame(width: 184)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("组间休息", traits: .sizeThatFitsLayout) {
    TrainingActionLabel(title: "结束", symbol: "forward.end.fill",
        status: .rest(endsAt: .now.addingTimeInterval(75)), disabled: false, tint: TrainingDisplayStyle.green)
        .environment(\.locale, AppLanguage.locale(for: "zh"))
        .frame(width: 184)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("English", traits: .sizeThatFitsLayout) {
    TrainingActionLabel(title: "Complete", symbol: "checkmark",
        status: .workout(startedAt: .now.addingTimeInterval(-45)), disabled: false, tint: TrainingDisplayStyle.green)
        .environment(\.locale, AppLanguage.locale(for: "en"))
        .frame(width: 184)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}
