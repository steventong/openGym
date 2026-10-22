import SwiftUI

enum GymTheme {
    static let green = Color(red:0.39, green:0.80, blue:0.35)
    static let background = Color(red:0.025, green:0.025, blue:0.025)
    static let card = Color(red:0.115, green:0.115, blue:0.12)
    static let muted = Color(white:0.54)
}
extension View {
    func gymCard() -> some View { padding(18).background(GymTheme.card,in:RoundedRectangle(cornerRadius:20)) }
}
struct GreenButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:8) { if let icon { Image(systemName:icon) }; Text(title).fontWeight(.semibold) }
                .frame(maxWidth:.infinity).padding(.vertical,16).foregroundStyle(.black)
                .background(GymTheme.green,in:RoundedRectangle(cornerRadius:15))
        }.buttonStyle(.plain)
    }
}
struct Pill: View {
    let title: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action:action) { Text(title).font(.system(size:13,weight:.medium)).padding(.horizontal,15).padding(.vertical,9)
            .foregroundStyle(selected ? .black : .white.opacity(0.85))
            .background(selected ? GymTheme.green : GymTheme.card,in:Capsule()) }.buttonStyle(.plain)
    }
}
struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size:20,weight:.bold)).frame(maxWidth:.infinity,alignment:.leading) }
}
struct EmptyCard: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing:12) {
            Image(systemName:icon).font(.system(size:30,weight:.light)).foregroundStyle(GymTheme.green).padding(.bottom,6)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(GymTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity).padding(.vertical,30).gymCard()
    }
}
struct ExerciseThumbnail: View {
    @Environment(GymStore.self) private var store
    let id: String
    var size: CGFloat = 60
    var body: some View {
        AsyncImage(url:store.mediaURL(id)) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit().padding(3)
            case .failure: Image(systemName:"dumbbell").foregroundStyle(.gray)
            default: ProgressView().tint(.gray)
            }
        }.frame(width:size,height:size).background(.white,in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12))
    }
}
