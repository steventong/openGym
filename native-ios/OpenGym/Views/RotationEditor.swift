import SwiftUI
struct RotationEditor:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var baseline:[String:Any] = [:]
    @State private var ids:[String] = []
    @State private var label = ""
    @State private var mode = "rotation"
    @State private var initialMode = "rotation"
    @State private var initialIDs:[String] = []
    @State private var initialLabel = ""
    @State private var loaded = false
    @State private var restart = false
    @State private var discard = false
    @State private var error:String?
    private var dirty:Bool { ids != initialIDs || label != initialLabel || mode != initialMode }
    var body:some View {
        NavigationStack {
            List {
                Section("训练方式") {
                    Picker("方式",selection:$mode){Text("循环排期").tag("rotation");Text("固定每周").tag("week")}.pickerStyle(.segmented).accessibilityIdentifier("rotation-mode")
                    if store.rotationSummary()["external"] as? Bool == true {Text("当前是外部教练队列。保存循环会采用此顺序并启用自动循环；切回固定每周不会删除外部队列。").font(.caption).foregroundStyle(.orange)}
                }
                if mode == "rotation" {
                    Section("循环名称") {TextField("例如：推 / 拉 / 腿",text:$label).accessibilityIdentifier("rotation-label")}
                    Section {
                        ForEach(Array(ids.enumerated()),id:\.element){i,id in
                            HStack {
                                Text("\(i+1)").font(.caption.monospacedDigit()).foregroundStyle(GymTheme.green)
                                Text(store.routines.first{$0.id == id}?.name ?? "已删除的计划").font(.subheadline)
                                Spacer()
                                Button {ids.swapAt(i,i-1)} label:{Image(systemName:"arrow.up")}.disabled(i==0).buttonStyle(.borderless).accessibilityLabel("上移第\(i+1)项")
                                Button {ids.swapAt(i,i+1)} label:{Image(systemName:"arrow.down")}.disabled(i==ids.count-1).buttonStyle(.borderless).accessibilityLabel("下移第\(i+1)项")
                                Button(role:.destructive){ids.removeAll{$0 == id}} label:{Image(systemName:"minus.circle")}.buttonStyle(.borderless).accessibilityLabel("移出循环")
                            }
                        }
                        ForEach(store.routines.filter{!ids.contains($0.id)}){r in Button {ids.append(r.id)} label:{Label(r.name,systemImage:"plus.circle")}.accessibilityIdentifier("rotation-add-\(r.id)")}
                    } header:{Text("训练顺序")} footer:{Text("按未完成的顺序继续。完成一轮后，下一轮从结束当天的次日开始，避免当天的训练被重复计入。清空顺序会停止当前循环。")}
                    Section("当前一轮") {RotationProgressCard(card:false)}
                    Section {
                        Button("重新开始一轮"){restart = true}.disabled(dirty || ids.isEmpty || store.syncing || (store.state["rotation"] as? [String:Any]) == nil).accessibilityIdentifier("rotation-restart")
                    } footer:{Text("重新开始保留已有训练记录，但本轮进度会重置。请先保存顺序修改。")}
                } else {Section {Text("使用已有每周安排。你的循环顺序会保留，以后可以再次启用。").font(.subheadline)}}
            }.navigationTitle("循环排期").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading){Button("取消"){if dirty {discard = true}else{dismiss()}}.disabled(store.syncing)}
                    ToolbarItem(placement:.topBarTrailing){Button(store.syncing ? "保存中…" : "保存"){Task{await save(action:mode == "week" ? "week":"save")}}.disabled(store.syncing || !loaded).accessibilityIdentifier("save-rotation")}
                }
                .onAppear {if !loaded {baseline = store.state;let rotation = store.state["rotation"] as? [String:Any] ?? [:];let queue = store.state["queue"] as? [String:Any] ?? [:];ids = (rotation["sequence"] as? [String] ?? queue["ids"] as? [String] ?? []).filter { id in store.routines.contains { $0.id == id } };label = rotation["label"] as? String ?? queue["label"] as? String ?? "我的循环";mode = store.rotationSummary()["mode"] as? String ?? "week";initialMode = mode;initialIDs = ids;initialLabel = label;loaded = true}}
                .confirmationDialog("重新开始当前循环？",isPresented:$restart,titleVisibility:.visible){Button("开始新一轮"){Task{await save(action:"restart")}};Button("取消",role:.cancel){}}
                .confirmationDialog("放弃循环修改？",isPresented:$discard,titleVisibility:.visible){Button("放弃修改",role:.destructive){dismiss()};Button("继续编辑",role:.cancel){}}
                .alert("无法保存",isPresented:Binding(get:{error != nil},set:{if !$0 {error = nil}})){Button("知道了",role:.cancel){}}message:{Text(error ?? "")}
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green)
    }
    private func save(action:String) async {if await store.updateRotation(action:action,ids:ids,label:label,baseline:baseline){dismiss()}else{error = store.editError}}
}
struct RotationProgressCard:View {
    @Environment(GymStore.self) private var store
    var card = true
    var body:some View {
        let summary = store.rotationSummary(),view = summary["view"] as? [String:Any]
        Group {
            if let view {
                VStack(alignment:.leading,spacing:12) {
                    HStack{Label(view["label"] as? String ?? "当前循环",systemImage:"arrow.trianglehead.2.clockwise.rotate.90").font(.headline);Spacer();Text("\((view["remaining"] as? [String] ?? []).count) 项待完成").font(.caption).foregroundStyle(.secondary)}
                    if view["waiting"] as? Bool == true {Text("下一轮从 \(view["startsOn"] as? String ?? "") 开始").font(.caption).foregroundStyle(.orange)}
                    ForEach(Array((view["items"] as? [[String:Any]] ?? []).enumerated()),id:\.offset){_,item in
                        let status = item["state"] as? String ?? "later"
                        HStack {Image(systemName:status == "done" ? "checkmark.circle.fill" : status == "next" ? "play.circle.fill":"circle").foregroundStyle(status == "later" ? GymTheme.muted:GymTheme.green);Text(item["name"] as? String ?? "计划").font(.subheadline);Spacer();Text(status == "done" ? "已完成":status == "next" ? "下一项":status == "pinned" ? item["on"] as? String ?? "已排期":"待训练").font(.caption).foregroundStyle(.secondary)}
                    }
                }.padding(card ? 16:0).background(card ? GymTheme.card:.clear,in:RoundedRectangle(cornerRadius:18))
            } else {Text("还没有正在进行的一轮，选择计划并保存即可开始。").font(.subheadline).foregroundStyle(.secondary)}
        }
    }
}
