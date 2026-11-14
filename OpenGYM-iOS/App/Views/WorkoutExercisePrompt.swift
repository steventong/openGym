import SwiftUI

/// 训练页的居中提示：图标、说明文字和添加动作按钮。
/// 空白训练和全部动作完成共用同一布局，只替换图标与文字。
struct WorkoutExercisePrompt: View {
    let icon: String
    let message: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let buttonAccessibilityLabel: LocalizedStringKey
    let buttonIdentifier: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(GymTheme.muted)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Label(buttonTitle, systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .background(GymTheme.card, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
                .accessibilityLabel(buttonAccessibilityLabel)
                .accessibilityIdentifier(buttonIdentifier)
        }.frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

#Preview("空白训练") {
    WorkoutExercisePrompt(icon: "dumbbell", message: "NO_EXERCISES_YET", buttonTitle: "ADD",
        buttonAccessibilityLabel: "ADD_WORKOUT_EXERCISE", buttonIdentifier: "empty-workout-add-exercise") {}
        .environment(\.locale, AppLanguage.locale(for: "zh"))
}

#Preview("全部动作完成") {
    WorkoutExercisePrompt(icon: "checkmark.circle", message: "ALL_EXERCISES_COMPLETE", buttonTitle: "ADD_NEW_EXERCISE",
        buttonAccessibilityLabel: "ADD_NEW_EXERCISE", buttonIdentifier: "completed-workout-add-exercise") {}
        .environment(\.locale, AppLanguage.locale(for: "zh"))
}
