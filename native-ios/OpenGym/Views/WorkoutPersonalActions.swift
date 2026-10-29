import SwiftUI

struct WorkoutPersonalActions:View {
    @Environment(GymStore.self) private var store
    let record:WorkoutRecord
    @State private var deleting = false
    @State private var repeating = false
    private var summary:String {
        let names = Dictionary((record.raw["entries"] as? [[String:Any]] ?? []).compactMap { entry -> (String,String)? in guard let id = entry["id"] as? String else{return nil};return (id,store.exercise(id)?.name ?? entry["n"] as? String ?? id) },uniquingKeysWith:{_,new in new})
        return (try? store.personalInfo("workoutText",["workout":record.raw,"names":names]))?["text"] as? String ?? ""
    }
    var body:some View {
        HStack {
            Button {repeating = true} label: {Label("重复训练",systemImage:"repeat")}.disabled(store.draft != nil || store.syncing)
            Spacer()
            ShareLink(item:summary) {Label("分享",systemImage:"square.and.arrow.up")}
            Spacer()
            Button(role:.destructive) {deleting = true} label:{Image(systemName:"trash").frame(width:44,height:44)}.accessibilityLabel("删除训练记录").disabled(store.syncing)
        }.font(.caption)
            .confirmationDialog("按这次记录开始新训练？",isPresented:$repeating,titleVisibility:.visible) { Button("开始") {_ = store.repeatPersonalWorkout(record)} } message: {Text("保留动作和已记录的目标，清除完成状态，创建今天的自由训练。")}
            .confirmationDialog("删除训练记录？",isPresented:$deleting,titleVisibility:.visible) { Button("删除",role:.destructive) {Task {if !(await store.deletePersonalWorkout(record)) {store.error = store.editError}}} } message:{Text("删除后无法撤销；其他训练保留，并重新核对相关个人纪录。")}
    }
}
struct DayNoteEditor:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let date:Date
    @State private var original:[String:Any] = [:]
    @State private var tag = ""
    @State private var note = ""
    @State private var issue:String?
    @State private var loaded = false
    var body:some View {
        NavigationStack {
            Form {
                Text(dayString(date))
                Picker("标签",selection:$tag) {Text("无").tag("");Text("生病").tag("sick");Text("旅行").tag("travel");Text("休息").tag("rest");Text("受伤").tag("injured")}
                TextField("当天备注",text:$note,axis:.vertical).lineLimit(3...8)
                Button("清除备注") {note = "";tag = ""}
                if let issue {Text(issue).foregroundStyle(.orange)}
            }.navigationTitle("每日备注").toolbar {
                ToolbarItem(placement:.topBarLeading) {Button("取消"){dismiss()}}
                ToolbarItem(placement:.topBarTrailing) {Button("保存"){save()}.disabled(store.syncing)}
            }.onAppear {
                guard !loaded else{return};loaded = true
                original = store.state.filter {$0.key == "dayNotes"}
                let row = (original["dayNotes"] as? [String:Any])?[dayString(date)] as? [String:Any] ?? [:]
                note = row["text"] as? String ?? "";tag = row["tag"] as? String ?? ""
            }
        }
    }
    private func save() {
        let day = dayString(date)
        guard day <= dayString() else{issue = "只能记录今天或以前的日期。";return}
        var row:[String:Any] = ["_ts":Date().timeIntervalSince1970*1000]
        if !tag.isEmpty {row["tag"] = tag};if !note.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {row["text"] = String(note.trimmingCharacters(in:.whitespacesAndNewlines).prefix(500))}
        var proposed = original, notes = original["dayNotes"] as? [String:Any] ?? [:]
        notes[day] = row;proposed["dayNotes"] = notes
        Task {if await store.savePersonalFields(original:original,proposed:proposed) {dismiss()} else {issue = store.editError}}
    }
}
