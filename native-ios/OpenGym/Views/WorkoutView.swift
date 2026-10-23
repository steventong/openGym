import SwiftUI
struct WorkoutView:View {
    @Environment(GymStore.self) private var store
    @State private var confirmFinish = false
    var body:some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if let d = store.draft {
                        HStack(alignment:.top) { Text(d.name).font(.system(size:28,weight:.bold));Spacer();Text(d.start,style:.timer).font(.system(size:20,design:.rounded)).monospacedDigit().foregroundStyle(GymTheme.green) }
                        let info = (try? WebRules.shared.call("sessionInfo",payload:["active":d.activeJSON])) as? [String:Any] ?? [:]
                        Text("\(Int(number(info["done"]))) / \(Int(number(info["total"]))) 组／侧已完成").font(.subheadline).foregroundStyle(GymTheme.muted)
                        ProgressView(value:number(info["done"]),total:max(1,number(info["total"]))).tint(GymTheme.green)
                        if let timer = store.workTimer { timerCard(timer) }
                        if let until = store.restUntil {
                            TimelineView(.periodic(from:.now,by:1)) { c in
                                let s = max(0,Int(until.timeIntervalSince(c.date)))
                                HStack { Label(s>0 ? "组间休息" : "休息结束",systemImage:"timer");Spacer();Text(String(format:"%02d:%02d",s/60,s%60)).monospacedDigit();Button("跳过") { store.restUntil = nil } }.font(.subheadline).foregroundStyle(GymTheme.green).gymCard()
                            }
                        }
                        ForEach(Array(d.rawEntries.enumerated()),id:\.offset) { e,entry in
                            VStack(alignment:.leading,spacing:16) {
                                Button { store.selectedExercise = store.exercise(entry["id"] as? String ?? "") } label:{HStack {ExerciseThumbnail(id:entry["id"] as? String ?? "",size:52);VStack(alignment:.leading,spacing:5){Text(store.exercise(entry["id"] as? String ?? "")?.name ?? "自定义动作").font(.headline);if entry["sg"] != nil {Label("超级组",systemImage:"link").font(.caption).foregroundStyle(GymTheme.green)}};Spacer();Image(systemName:"play.circle").foregroundStyle(GymTheme.green)}}.buttonStyle(.plain)
                                let rows = entry["sets"] as? [[String:Any]] ?? []
                                ForEach(rows.indices,id:\.self) { s in
                                    VStack(alignment:.leading,spacing:8) {
                                        Text("第 \(s+1) 组").font(.caption).foregroundStyle(GymTheme.muted)
                                        AdvancedSetEditor(row:rows[s],target:entry["target"] as? [String:Any] ?? [:],unit:d.unit,identifier:"\(e)-\(s)",timerRunning:store.workTimer != nil,startTimer:{store.startWorkTimer(entry:e,set:s)},startRest:{store.restUntil = $0>0 ? Date().addingTimeInterval($0):nil}) { action in store.liveRowAction(entry:e,set:s,action:action) }
                                    }
                                    if s < rows.count-1 {Divider()}
                                }
                                Button {store.addLiveSet(entry:e)} label:{Label("添加一组",systemImage:"plus").font(.subheadline).frame(maxWidth:.infinity)}.disabled(store.workTimer != nil)
                                if let note = (entry["target"] as? [String:Any])?["note"] as? String,!note.isEmpty {Text(note).font(.caption).foregroundStyle(GymTheme.muted)}
                            }.gymCard().id(e)
                        }
                        GreenButton(title:store.syncing ? "保存中…" : "完成训练",icon:"checkmark") {confirmFinish = true}.disabled(store.syncing || number(info["done"]) == 0 || store.workTimer != nil).accessibilityIdentifier("finish-workout")
                        Text("训练组和计时自动保存在本机，完成后同步。").font(.caption).foregroundStyle(GymTheme.muted)
                    } else {
                        Text("开始训练").font(.system(size:34,weight:.bold))
                        EmptyCard(icon:"figure.strengthtraining.traditional",title:"准备好开始了吗？",detail:"选择计划，按目标逐组训练。")
                        let scheduled = store.scheduledRoutines(on:Date())
                        if !scheduled.isEmpty {GreenButton(title:"开始今日安排",icon:"play.fill"){store.start(scheduled)}}
                        ForEach(store.routines){r in GreenButton(title:r.name,icon:"play.fill"){store.start(r)}}
                        if store.routines.isEmpty {GreenButton(title:"前往训练计划"){store.selectedTab = 1}}
                    }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of:store.draft?.activeJSON["cur"] as? Int) { _,value in if let value {withAnimation{proxy.scrollTo(value,anchor:.top)}} }
        }.confirmationDialog("完成并保存训练？",isPresented:$confirmFinish,titleVisibility:.visible){Button("保存到服务端"){Task{await store.finish()}};Button("继续训练",role:.cancel){}}
            .task { while !Task.isCancelled {store.settleTimer();try? await Task.sleep(for:.seconds(1))} }
    }
    private func timerCard(_ timer:[String:Any])->some View {
        TimelineView(.periodic(from:.now,by:1)) { c in
            let paused = timer["paused"] as? Bool == true
            let sec = max(0,Int(ceil(paused ? number(timer["remaining"]) : number(timer["end"])-c.date.timeIntervalSince1970)))
            VStack(spacing:12) {
                HStack{Label(paused ? "计时已暂停" : "动作计时",systemImage:"stopwatch");Spacer();Text(String(format:"%02d:%02d",sec/60,sec%60)).font(.title2.monospacedDigit())}
                HStack{Button(paused ? "继续" : "暂停"){store.pauseWorkTimer()};Spacer();Button("提前完成"){store.finishWorkTimer()};Button("取消",role:.cancel){store.finishWorkTimer(cancel:true)}}.font(.subheadline)
            }.foregroundStyle(GymTheme.green).gymCard().accessibilityIdentifier("work-timer")
        }
    }
}
