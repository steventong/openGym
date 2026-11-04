import SwiftUI
struct RotationEditor:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var baseline:[String:Any] = [:]
    @State private var ids:[String] = []
    @State private var label = ""
    @State private var mode = "rotation"
    @State private var initialMode = "rotation"
    @State private var initialIDs:[String] = []
    @State private var initialLabel = ""
    @State private var loaded = false
    @State private var restart = false
    @State private var confirmClear = false
    @State private var discard = false
    @State private var error:String?
    private var dirty:Bool { inputBuffer.hasPending || ids != initialIDs || label != initialLabel || mode != initialMode }
    var body:some View {
        NavigationStack {
            List {
                Section(L10n.text("HOW_YOU_TRAIN" /* 训练方式 */)) {
                    Picker(L10n.text("MODE" /* 方式 */),selection:$mode){Text(L10n.text("ROTATION_SCHEDULE" /* 循环排期 */)).tag("rotation");Text(L10n.text("FIXED_WEEKLY_SCHEDULE" /* 固定每周 */)).tag("week")}.pickerStyle(.segmented).accessibilityIdentifier("rotation-mode")
                }
                if mode == "rotation" {
                    Section(L10n.text("ROTATION_NAME" /* 循环名称 */)) {BufferedTextField(L10n.text("FOR_EXAMPLE_PUSH_PULL_LEGS" /* 例如：推 / 拉 / 腿 */),text:$label).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("rotation-label")}
                    Section {
                        ForEach(Array(ids.enumerated()),id:\.element){i,id in
                            HStack {
                                Text("\(i+1)").font(.caption.monospacedDigit()).foregroundStyle(GymTheme.green)
                                Text(store.routines.first{$0.id == id}?.name ?? L10n.text("DELETED_ROUTINE" /* 已删除的计划 */)).font(.subheadline)
                                Spacer()
                                Button {ids.swapAt(i,i-1)} label:{Image(systemName:"arrow.up")}.disabled(i==0).buttonStyle(.borderless).accessibilityLabel(L10n.text("MOVE_ITEM_COUNT_UP" /* 上移第{0}项 */, i+1))
                                Button {ids.swapAt(i,i+1)} label:{Image(systemName:"arrow.down")}.disabled(i==ids.count-1).buttonStyle(.borderless).accessibilityLabel(L10n.text("MOVE_ITEM_COUNT_DOWN" /* 下移第{0}项 */, i+1))
                                Button(role:.destructive){ids.removeAll{$0 == id}} label:{Image(systemName:"minus.circle")}.buttonStyle(.borderless).accessibilityLabel(L10n.text("REMOVE_FROM_ROTATION" /* 移出循环 */))
                            }
                        }
                        ForEach(store.routines.filter{!ids.contains($0.id)}){r in Button {ids.append(r.id)} label:{Label(r.name,systemImage:"plus.circle")}.accessibilityIdentifier("rotation-add-\(r.id)")}
                    } header: { HStack { Text(L10n.text("WORKOUT_ORDER" /* 训练顺序 */)); Spacer(); ExplanationButton(title: L10n.text("ROTATION_RULES" /* 循环规则 */), message: L10n.text("CONTINUE_UNFINISHED_WORKOUTS_IN_ORDER_THE_NEXT_ROUND_STARTS_THE_DAY_AFTER" /* 按顺序继续未完成的训练，下一轮从本轮结束的次日开始。清空顺序会停止循环；切换到固定每周会保留循环顺序。 */)) } }
                    Section(L10n.text("CURRENT_ROUND" /* 当前一轮 */)) {RotationProgressCard(card:false)}
                    Section {
                        Button(L10n.text("RESTART_ROUND" /* 重新开始一轮 */)){restart = true}.disabled(dirty || ids.isEmpty || store.syncing || (store.state["rotation"] as? [String:Any]) == nil).accessibilityIdentifier("rotation-restart")
                    }
                }
            }.navigationTitle(L10n.text("ROTATION_SCHEDULE" /* 循环排期 */)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading){Button(L10n.text("CANCEL" /* 取消 */)){inputBuffer.commitAll();if dirty {discard = true}else{dismiss()}}.disabled(store.syncing)}
                    ToolbarItem(placement:.topBarTrailing){Button(store.syncing ? L10n.text("SAVING" /* 正在保存 */) : L10n.text("SAVE" /* 保存 */)) {
                        if mode == "rotation", ids.isEmpty, !initialIDs.isEmpty { confirmClear = true }
                        else { Task { await save(action: mode == "week" ? "week" : "save") } }
                    }.lineLimit(1).disabled(store.syncing || !loaded).accessibilityIdentifier("save-rotation")}
                }
                .onAppear {if !loaded {baseline = store.state;let rotation = store.state["rotation"] as? [String:Any] ?? [:];let queue = store.state["queue"] as? [String:Any] ?? [:];ids = (rotation["sequence"] as? [String] ?? queue["ids"] as? [String] ?? []).filter { id in store.routines.contains { $0.id == id } };label = rotation["label"] as? String ?? queue["label"] as? String ?? L10n.text("MY_ROTATION" /* 我的循环 */);mode = store.rotationSummary()["mode"] as? String ?? "week";initialMode = mode;initialIDs = ids;initialLabel = label;loaded = true}}
                .confirmationDialog(L10n.text("RESTART_THE_CURRENT_ROUND" /* 重新开始当前循环？ */),isPresented:$restart,titleVisibility:.visible){Button(L10n.text("START_NEW_PASS" /* 开始新一轮 */)){Task{await save(action:"restart")}};Button(L10n.text("CANCEL" /* 取消 */),role:.cancel){}} message: { Text(L10n.text("RESET_THIS_ROUND_S_PROGRESS_AND_KEEP_WORKOUT_HISTORY" /* 重置本轮进度，保留训练记录。 */)) }
                .confirmationDialog(L10n.text("STOP_THE_CURRENT_ROTATION" /* 停止当前循环？ */), isPresented: $confirmClear, titleVisibility: .visible) {
                    Button(L10n.text("CLEAR_AND_SAVE" /* 清空并保存 */), role: .destructive) { Task { await save(action: "save") } }
                    Button(L10n.text("CANCEL" /* 取消 */), role: .cancel) {}
                } message: { Text(L10n.text("CLEAR_THE_WORKOUT_ORDER_AND_STOP_THE_ROTATION_WORKOUT_HISTORY_IS_KEPT" /* 清空训练顺序并停止循环，保留训练记录。 */)) }
                .confirmationDialog(L10n.text("DISCARD_ROTATION_CHANGES" /* 放弃循环修改？ */),isPresented:$discard,titleVisibility:.visible){Button(L10n.text("DISCARD_CHANGES" /* 放弃修改 */),role:.destructive){dismiss()};Button(L10n.text("KEEP_EDITING" /* 继续编辑 */),role:.cancel){}}
                .alert(L10n.text("COULD_NOT_SAVE" /* 无法保存 */),isPresented:Binding(get:{error != nil},set:{if !$0 {error = nil}})){Button(L10n.text("GOT_IT" /* 知道了 */),role:.cancel){}}message:{Text(error ?? "")}
                .interactiveDismissDisabled(dirty || store.syncing)
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
    private func save(action:String) async {inputBuffer.commitAll();if await store.updateRotation(action:action,ids:ids,label:label,baseline:baseline){dismiss()}else{error = store.editError}}
}
struct RotationProgressCard:View {
    @Environment(GymStore.self) private var store
    var card = true
    var body:some View {
        let summary = store.rotationSummary(),view = summary["view"] as? [String:Any]
        Group {
            if let view {
                VStack(alignment:.leading,spacing:12) {
                    HStack{Label(view["label"] as? String ?? L10n.text("CURRENT_ROTATION" /* 当前循环 */),systemImage:"arrow.trianglehead.2.clockwise.rotate.90").font(.headline);Spacer();Text(L10n.text("COUNT_REMAINING" /* {0} 项待完成 */, (view["remaining"] as? [String] ?? []).count)).font(.caption).foregroundStyle(.secondary)}
                    if view["waiting"] as? Bool == true {Text(L10n.text("NEXT_ROUND_STARTS_COUNT" /* 下一轮从 {0} 开始。 */, view["startsOn"] as? String ?? "")).font(.caption).foregroundStyle(.orange)}
                    ForEach(Array((view["items"] as? [[String:Any]] ?? []).enumerated()),id:\.offset){_,item in
                        let status = item["state"] as? String ?? "later"
                        HStack {Image(systemName:status == "done" ? "checkmark.circle.fill" : status == "next" ? "play.circle.fill":"circle").foregroundStyle(status == "later" ? GymTheme.muted:GymTheme.green);Text(item["name"] as? String ?? L10n.text("PLAN" /* 计划 */)).font(.subheadline);Spacer();Text(status == "done" ? L10n.text("COMPLETED" /* 已完成 */):status == "next" ? L10n.text("UP_NEXT" /* 下一个 */):status == "pinned" ? item["on"] as? String ?? L10n.text("SCHEDULED" /* 已排期 */):L10n.text("NOT_STARTED" /* 待训练 */)).font(.caption).foregroundStyle(.secondary)}
                    }
                }.padding(card ? 16:0).background(card ? GymTheme.card:.clear,in:RoundedRectangle(cornerRadius:18))
            } else {Text(L10n.text("NO_ROTATION_YET" /* 暂无循环 */)).font(.subheadline).foregroundStyle(.secondary)}
        }
    }
}
