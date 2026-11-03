import SwiftUI

enum GymTheme {
    static let green = Color(red:0.39, green:0.80, blue:0.35)
    static let background = Color(red:0.025, green:0.025, blue:0.025)
    static let card = Color(red:0.115, green:0.115, blue:0.12)
    static let muted = Color(white:0.54)
}
extension View {
    func gymCard() -> some View { padding(18).background(GymTheme.card,in:RoundedRectangle(cornerRadius:20)) }
    func operationAlert(_ issue: Binding<String?>, title: String = "操作未完成") -> some View {
        alert(title, isPresented: Binding(get: { issue.wrappedValue != nil }, set: { if !$0 { issue.wrappedValue = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(issue.wrappedValue ?? "") }
    }
    func invalidInput(_ invalid: Bool) -> some View {
        overlay(RoundedRectangle(cornerRadius: 4).stroke(invalid ? Color.orange : .clear))
            .accessibilityHint(invalid ? "输入无效，请检查" : "")
    }
}

/// Details are available on demand without inserting explanatory rows into the screen.
struct ExplanationButton: View {
    let title: String
    let message: String
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "info.circle").frame(width: 28, height: 28) }
            .buttonStyle(.borderless).accessibilityLabel("\(title)说明")
            .alert(title, isPresented: $showing) { Button("好", role: .cancel) {} } message: { Text(message) }
    }
}

struct StatusDetailButton: View {
    let title: String
    let message: String
    var warning = false
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Label(title, systemImage: warning ? "exclamationmark.circle" : "info.circle")
                .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(warning ? Color.orange : GymTheme.muted)
        }.buttonStyle(.borderless).accessibilityHint("查看详情")
            .alert(title, isPresented: $showing) { Button("好", role: .cancel) {} } message: { Text(message) }
    }
}
struct GreenButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:8) { if let icon { Image(systemName:icon) }; Text(title).fontWeight(.semibold) }
                .lineLimit(1).minimumScaleFactor(0.8)
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
    var detail: String? = nil
    var body: some View {
        VStack(spacing:12) {
            Image(systemName:icon).font(.system(size:30,weight:.light)).foregroundStyle(GymTheme.green).padding(.bottom,6)
            Text(title).font(.headline)
            if let detail, !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(GymTheme.muted).multilineTextAlignment(.center) }
        }.frame(maxWidth:.infinity).padding(.vertical,30).gymCard()
    }
}
struct ExerciseThumbnail: View {
    @Environment(GymStore.self) private var store
    let id: String
    var size: CGFloat = 60
    var body: some View {
        Group {
            if let url = store.mediaURL(id), let image = UIImage(contentsOfFile:url.path) {
                Image(uiImage:image).resizable().scaledToFit().padding(3)
            } else {
                Image(systemName:"dumbbell").foregroundStyle(.gray)
            }
        }.frame(width:size,height:size).background(.white,in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12))
    }
}
