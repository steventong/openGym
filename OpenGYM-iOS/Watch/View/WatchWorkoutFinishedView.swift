import SwiftUI

/// 全部动作完成后的手表页面，与等待开始页同布局；手表无法挑选动作，只提示回到手机添加。
struct WatchWorkoutFinishedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            Text("ALL_EXERCISES_COMPLETE")
                .font(.headline)
                .multilineTextAlignment(.center)

            Label("ADD_NEW_EXERCISES_ON_PHONE", systemImage: "plus")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("全部动作完成") {
    WatchWorkoutFinishedView()
        .environment(\.locale, AppLanguage.locale(for: "zh"))
}
