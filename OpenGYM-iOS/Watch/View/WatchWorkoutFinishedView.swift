import SwiftUI

/// 全部动作完成后的手表页面，提示回手机保存训练；与等待开始页同布局。
struct WatchWorkoutFinishedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            Text("SAVE_WORKOUT_ON_PHONE")
                .font(.headline)
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
