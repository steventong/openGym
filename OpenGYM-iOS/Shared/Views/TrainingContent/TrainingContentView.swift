import SwiftUI

/// Apple Watch 与实时活动共用的训练内容视图，负责组织动作标题、组摘要、指标和主操作区域。
///
/// 只读取展示数据，不访问 Store、不计算训练进度，也不执行平台命令。
/// 指标和主操作控件由调用方注入，以复用布局，同时保留各平台的数据与交互实现。
struct TrainingContentView<Metrics: View, PrimaryAction: View>: View {
    /// 已由数据源和 ViewModel 准备好的展示值，包含文案、操作状态及显示语言。
    let content: TrainingContentData
    /// 控制展开、紧凑或隐藏标题的紧凑布局，不代表训练或休息等业务状态。
    let layout: TrainingContentLayout
    /// 平台提供的指标视图；不展示指标时传入 EmptyView。
    let metrics: Metrics
    /// 平台提供的主操作控件；仅在 content.action 存在时展示，具体命令由调用方处理。
    let primaryAction: PrimaryAction
    /// 遵循系统的“减弱动态效果”设置，避免强制播放操作状态的过渡动画。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.18)

        // 各区域自行控制间距，展开布局可利用弹性留白，紧凑布局则保持内容高度可控。
        VStack(spacing: 0) {
            // 灵动岛使用无标题布局，只保留组摘要、指标和主操作区域。
            if layout != .compactWithoutHeader {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TrainingExerciseTitle(title: content.exercise)
                    TrainingExercisePosition(position: content.position,
                        fontWeight: layout == .expanded ? .regular : .medium,
                        textColor: layout == .expanded ? .secondary : .white.opacity(0.9))
                }
                // 紧凑布局固定标题行高度；展开布局由文字自身决定高度。
                .frame(height: layout == .expanded ? nil : 22)
                .padding(.bottom, layout == .expanded ? 0 : 4)
            }

            // 展开布局吸收父容器的剩余高度，拉开标题与训练详情。
            if layout == .expanded {
                Spacer(minLength: TrainingDisplayStyle.actionGap)
            }

            // 没有组摘要时不保留占位；展开布局额外使用内边距和圆角底色突出当前组。
            if let summary = content.summary {
                TrainingSetSummary(weight: summary.weight, detail: summary.detail, label: summary.label,
                    detailFontWeight: layout == .expanded ? .regular : .medium,
                    detailColor: layout == .expanded ? .secondary : .white.opacity(0.9))
                    .padding(.horizontal, layout == .expanded ? 2 : 0)
                    .padding(.vertical, layout == .expanded ? 5 : 0)
                    .background(.white.opacity(layout == .expanded ? 0.1 : 0),
                        in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, layout == .expanded ? 5 : 0)
            }

            // 指标内容独立于组摘要和主操作，即使它们缺失，也仍由调用方决定是否展示指标。
            metrics

            // 操作数据决定整个操作区域是否存在，避免无操作时仍占用按钮及其上方间距。
            if let action = content.action {
                if layout == .expanded {
                    // 展开布局用弹性留白将主操作与上方详情分开。
                    Spacer(minLength: TrainingDisplayStyle.actionGap)
                } else {
                    // 紧凑布局使用固定间隔；无标题版本进一步缩小间隔，透明占位不参与无障碍朗读。
                    Color.clear.frame(height: TrainingDisplayStyle.actionGap - (layout == .compactWithoutHeader ? 6 : 0))
                        .accessibilityHidden(true)
                }
                primaryAction
                    // 保留调用方控件的自定义外观，统一应用展示数据中的禁用状态。
                    .buttonStyle(.plain)
                    .disabled(action.disabled)
                    // 保留控件所需的垂直高度，水平方向仍接受父容器的宽度约束。
                    .fixedSize(horizontal: false, vertical: true)
                    // 对禁用状态和标题变化应用过渡；减弱动态效果开启时不指定动画。
                    .animation(animation, value: action.disabled)
                    .animation(animation, value: action.title)
                    .accessibilityHint(action.hint)
            }
        }
        .foregroundStyle(.white)
        // 将展示数据的语言环境传递给子视图，使日期、计时等格式与当前内容语言一致。
        .environment(\.locale, content.locale)
    }
}

#Preview("训练内容", traits: .sizeThatFitsLayout) {
    let action = TrainingContentData.Action(title: "完成", symbol: "checkmark", status: .workout(startedAt: nil))
    let content = TrainingContentData(exercise: "哑铃飞鸟", position: "第 1/3 个动作",
        summary: .init(weight: "5 kg", detail: "12 次", label: "第 1/3 组"),
        action: action, locale: AppLanguage.locale(for: "zh"))
    TrainingContentView(content: content, layout: .compact, metrics: EmptyView(),
        primaryAction: TrainingActionLabel(title: action.title, symbol: action.symbol,
            status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green))
        .frame(width: 320)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("休息内容", traits: .sizeThatFitsLayout) {
    let action = TrainingContentData.Action(title: "结束", symbol: "forward.end.fill",
        status: .rest(endsAt: .now.addingTimeInterval(75)))
    let content = TrainingContentData(exercise: "哑铃飞鸟", position: "第 1/3 个动作",
        summary: .init(weight: "5 kg", detail: "12 次", label: "第 1/3 组"),
        action: action, locale: AppLanguage.locale(for: "zh"))
    TrainingContentView(content: content, layout: .compact, metrics: EmptyView(),
        primaryAction: TrainingActionLabel(title: action.title, symbol: action.symbol,
            status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green))
        .frame(width: 320)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("English", traits: .sizeThatFitsLayout) {
    let action = TrainingContentData.Action(title: "Complete", symbol: "checkmark",
        status: .workout(startedAt: .now.addingTimeInterval(-45)))
    let content = TrainingContentData(exercise: "Dumbbell fly", position: "Exercise 1/3",
        summary: .init(weight: "5 kg", detail: "12 reps", label: "Set 1 of 3"),
        action: action, locale: AppLanguage.locale(for: "en"))
    TrainingContentView(content: content, layout: .compact, metrics: EmptyView(),
        primaryAction: TrainingActionLabel(title: action.title, symbol: action.symbol,
            status: action.status, disabled: action.disabled, tint: TrainingDisplayStyle.green))
        .frame(width: 320)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}
