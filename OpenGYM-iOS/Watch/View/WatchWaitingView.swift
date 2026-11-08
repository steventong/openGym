import SwiftUI

struct WatchWaitingView: View {
    
    var body: some View {
        VStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            
            Text("START_A_WORKOUT_ON_PHONE")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("等待手机") {
    WatchWaitingView()
}
