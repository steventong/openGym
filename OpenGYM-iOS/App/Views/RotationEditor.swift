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
                Section("HOW_YOU_TRAIN") {
                    Picker("MODE",selection:$mode){Text("ROTATION_SCHEDULE").tag("rotation");Text("FIXED_WEEKLY_SCHEDULE").tag("week")}.pickerStyle(.segmented).accessibilityIdentifier("rotation-mode")
                }
                if mode == "rotation" {
                    Section("ROTATION_NAME") {BufferedTextField("FOR_EXAMPLE_PUSH_PULL_LEGS",text:$label).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.accessibilityIdentifier("rotation-label")}
                    Section {
                        ForEach(Array(ids.enumerated()),id:\.element){i,id in
                            HStack {
                                Text(verbatim: String(i + 1)).font(.caption.monospacedDigit()).foregroundStyle(GymTheme.green)
                                Text(store.routines.first{$0.id == id}?.name ?? String(localized: "DELETED_ROUTINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline)
                                Spacer()
                                Button {ids.swapAt(i,i-1)} label:{Image(systemName:"arrow.up")}.disabled(i==0).buttonStyle(.borderless).accessibilityLabel(String(format: String(localized: "MOVE_ITEM_COUNT_UP", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: i+1)))
                                Button {ids.swapAt(i,i+1)} label:{Image(systemName:"arrow.down")}.disabled(i==ids.count-1).buttonStyle(.borderless).accessibilityLabel(String(format: String(localized: "MOVE_ITEM_COUNT_DOWN", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: i+1)))
                                Button(role:.destructive){ids.removeAll{$0 == id}} label:{Image(systemName:"minus.circle")}.buttonStyle(.borderless).accessibilityLabel("REMOVE_FROM_ROTATION")
                            }
                        }
                        ForEach(store.routines.filter{!ids.contains($0.id)}){r in Button {ids.append(r.id)} label:{Label(r.name,systemImage:"plus.circle")}.accessibilityIdentifier("rotation-add-\(r.id)")}
                    } header: { HStack { Text("WORKOUT_ORDER"); Spacer(); ExplanationButton(title: "ROTATION_RULES", message: "CONTINUE_UNFINISHED_WORKOUTS_IN_ORDER_THE_NEXT_ROUND_STARTS_THE_DAY_AFTER") } }
                    Section("CURRENT_ROUND") {RotationProgressCard(card:false)}
                    Section {
                        Button("RESTART_ROUND"){restart = true}.disabled(dirty || ids.isEmpty || store.syncing || (store.state["rotation"] as? [String:Any]) == nil).accessibilityIdentifier("rotation-restart")
                    }
                }
            }.navigationTitle("ROTATION_SCHEDULE").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading){Button("CANCEL"){inputBuffer.commitAll();if dirty {discard = true}else{dismiss()}}.disabled(store.syncing)}
                    ToolbarItem(placement:.topBarTrailing){Button(LocalizedStringKey(store.syncing ? "SAVING" : "SAVE")) {
                        if mode == "rotation", ids.isEmpty, !initialIDs.isEmpty { confirmClear = true }
                        else { Task { await save(action: mode == "week" ? "week" : "save") } }
                    }.lineLimit(1).disabled(store.syncing || !loaded).accessibilityIdentifier("save-rotation")}
                }
                .onAppear {if !loaded {baseline = store.state;let rotation = store.state["rotation"] as? [String:Any] ?? [:];let queue = store.state["queue"] as? [String:Any] ?? [:];ids = (rotation["sequence"] as? [String] ?? queue["ids"] as? [String] ?? []).filter { id in store.routines.contains { $0.id == id } };label = rotation["label"] as? String ?? queue["label"] as? String ?? String(localized: "MY_ROTATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale);mode = store.rotationSummary()["mode"] as? String ?? "week";initialMode = mode;initialIDs = ids;initialLabel = label;loaded = true}}
                .confirmationDialog("RESTART_THE_CURRENT_ROUND",isPresented:$restart,titleVisibility:.visible){Button("START_NEW_PASS"){Task{await save(action:"restart")}};Button("CANCEL",role:.cancel){}} message: { Text("RESET_THIS_ROUND_S_PROGRESS_AND_KEEP_WORKOUT_HISTORY") }
                .confirmationDialog("STOP_THE_CURRENT_ROTATION", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("CLEAR_AND_SAVE", role: .destructive) { Task { await save(action: "save") } }
                    Button("CANCEL", role: .cancel) {}
                } message: { Text("CLEAR_THE_WORKOUT_ORDER_AND_STOP_THE_ROTATION_WORKOUT_HISTORY_IS_KEPT") }
                .confirmationDialog("DISCARD_ROTATION_CHANGES",isPresented:$discard,titleVisibility:.visible){Button("DISCARD_CHANGES",role:.destructive){dismiss()};Button("KEEP_EDITING",role:.cancel){}}
                .alert("COULD_NOT_SAVE",isPresented:Binding(get:{error != nil},set:{if !$0 {error = nil}})){Button("GOT_IT",role:.cancel){}}message:{Text(error ?? "")}
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
                    HStack{Label(view["label"] as? String ?? String(localized: "CURRENT_ROTATION", bundle: AppLanguage.bundle, locale: AppLanguage.locale),systemImage:"arrow.trianglehead.2.clockwise.rotate.90").font(.headline);Spacer();Text(String(format: String(localized: "COUNT_REMAINING", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: (view["remaining"] as? [String] ?? []).count))).font(.caption).foregroundStyle(.secondary)}
                    if view["waiting"] as? Bool == true {Text(String(format: String(localized: "NEXT_ROUND_STARTS_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: view["startsOn"] as? String ?? ""))).font(.caption).foregroundStyle(.orange)}
                    ForEach(Array((view["items"] as? [[String:Any]] ?? []).enumerated()),id:\.offset){_,item in
                        let status = item["state"] as? String ?? "later"
                        HStack {Image(systemName:status == "done" ? "checkmark.circle.fill" : status == "next" ? "play.circle.fill":"circle").foregroundStyle(status == "later" ? GymTheme.muted:GymTheme.green);Text(item["name"] as? String ?? String(localized: "PLAN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline);Spacer();Text(status == "done" ? String(localized: "COMPLETED", bundle: AppLanguage.bundle, locale: AppLanguage.locale):status == "next" ? String(localized: "UP_NEXT", bundle: AppLanguage.bundle, locale: AppLanguage.locale):status == "pinned" ? item["on"] as? String ?? String(localized: "SCHEDULED", bundle: AppLanguage.bundle, locale: AppLanguage.locale):String(localized: "NOT_STARTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)}
                    }
                }.padding(card ? 16:0).background(card ? GymTheme.card:.clear,in:RoundedRectangle(cornerRadius:18))
            } else {Text("NO_ROTATION_YET").font(.subheadline).foregroundStyle(.secondary)}
        }
    }
}
