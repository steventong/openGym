import SwiftUI

struct CoachView: View {
    @Environment(GymStore.self) private var store
    var body: some View { CoachContent(store:store).id(store.coachIdentity) }
}
struct CoachRecord: Identifiable {
    let raw: [String: Any]
    var id: String { raw.coachText("id") }
}
private enum CoachSheet: Identifiable {
    case profile, history, cadence, community, record(CoachRecord)
    var id: String {
        switch self { case .profile:return "profile";case .history:return "history";case .cadence:return "cadence";case .community:return "community";case .record(let r):return "record-"+r.id }
    }
}
private struct CoachContent: View {
    @State private var session: CoachSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: CoachSheet?
    @State private var confirmUndo = false
    @State private var composerIssue: String?
    init(store: GymStore) { _session = State(initialValue:CoachSession(store:store)) }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                if !session.loaded { ProgressView().accessibilityLabel("正在连接教练").frame(maxWidth:.infinity,maxHeight:.infinity) }
                else if !session.enabled {
                    EmptyCard(icon:"sparkles",title:"教练暂不可用").padding()
                    ExplanationButton(title: "启用教练", message: "配对账号后，请管理员在网页后台启用 AI 教练。")
                    Button("重新检查") { Task { await session.refresh() } }.disabled(session.locked)
                    Spacer()
                } else if !session.hasConsent {
                    CoachConsentView(session:session)
                } else if session.profile.isEmpty {
                    CoachIntakeView(session:session,editing:false)
                } else { conversation }
            }
            .background(GymTheme.background).navigationTitle("AI 教练").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement:.topBarTrailing) {
                    HStack {
                        if let error = session.error {
                            StatusDetailButton(title: "需重试", message: error, warning: true).accessibilityIdentifier("coach-error")
                            Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(session.locked).accessibilityLabel("重试连接")
                        } else if session.ready { actions }
                    }
                }
            }
            .sheet(item:$sheet) { page in
                NavigationStack {
                    Group {
                        switch page {
                        case .profile: CoachIntakeView(session:session,editing:true)
                        case .history: CoachHistoryView(session:session)
                        case .cadence: CoachCadenceView(session:session)
                        case .community: CoachCommunityView(session:session)
                        case .record(let record): ScrollView { CoachProposalView(session:session,proposal:record.raw,historical:true).padding() }
                        }
                    }.background(GymTheme.background).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("关闭") { sheet = nil } } }
                }.tint(GymTheme.green).preferredColorScheme(.dark)
            }
            .confirmationDialog("撤销上次教练修改？",isPresented:$confirmUndo,titleVisibility:.visible) {
                Button("撤销修改",role:.destructive) { Task { await session.revert() } }
            } message: { Text("训练计划将恢复到应用前的状态，之后记录的训练不会被删除。") }
            .task(id:"\(scenePhase)-\(session.running)") { if scenePhase == .active { await session.poll() } }
        }.tint(GymTheme.green).preferredColorScheme(.dark)
    }
    private var actions: some View {
        Menu {
            if !session.running && session.pending == nil {
                Button("评估我的训练",systemImage:"sparkles") { Task { await session.ask("review") } }
                Button("复盘上次训练",systemImage:"checkmark.circle") { Task { await session.ask("debrief") } }.disabled(session.store.workouts.isEmpty)
                Menu("优化指定计划") {
                    ForEach(session.store.routines) { routine in Button(routine.name) { Task { await session.ask("review",routine:routine) } } }
                }
                Button("设计新计划",systemImage:"plus.rectangle") { Task { await session.ask("create") } }
            }
            Button("历史建议",systemImage:"clock.arrow.circlepath") { sheet = .history }
            Button("编辑训练问答",systemImage:"pencil") { sheet = .profile }
            Button("自动评估",systemImage:"calendar.badge.clock") { sheet = .cadence }
            let cap = session.status.coachObject("cap")
            if number(cap["limit"]) > 0 { Text("今日用量 \(Int(number(cap["used"]))) / \(Int(number(cap["limit"])))") }
            if session.configuration.coachObject("coach")["community"] as? Bool == true { Button("匿名训练对比",systemImage:"person.2") { sheet = .community } }
            if session.info["canRevert"] as? Bool == true { Button("撤销上次教练修改",systemImage:"arrow.uturn.backward") { confirmUndo = true }.disabled(session.running) }
        } label: { Image(systemName:"ellipsis.circle").accessibilityLabel("教练菜单") }.disabled(session.locked).accessibilityIdentifier("coach-menu")
    }
    private var conversation: some View {
        VStack(spacing:0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:18) {
                        ForEach(Array(session.coach.coachObjects("chat").enumerated()),id:\.offset) { _,message in
                            VStack(alignment:.leading,spacing:8) {
                                let text = message.coachText("kind") == "intake" ? (session.info["profileLines"] as? [String] ?? []).joined(separator:"\n") : message.coachText("text")
                                if !text.isEmpty { bubble(text,user:message.coachText("role") == "user",failed:message.coachText("kind") == "error") }
                                if let record = session.history.first(where: { $0.coachText("id") == message.coachText("ref") }) {
                                    Button { sheet = .record(CoachRecord(raw:record)) } label: {
                                        Label("查看完整建议与处理结果",systemImage:"doc.text.magnifyingglass").font(.subheadline).padding()
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                        if let pending = session.pending, !session.running {
                            if session.savedPending != nil {
                                Button("完成同步", systemImage: "arrow.clockwise") { Task { await session.retryResolution() } }
                                    .disabled(session.locked).accessibilityIdentifier("coach-finish-sync")
                            } else { CoachProposalView(session:session,proposal:pending).id(pending.coachText("id")) }
                        }
                        Color.clear.frame(height:1).id("coach-bottom")
                    }.padding()
                }.refreshable { await session.refresh() }
                .onChange(of:session.coach.coachObjects("chat").count) { _,_ in withAnimation { proxy.scrollTo("coach-bottom",anchor:.bottom) } }
                .onChange(of:session.pending?.coachText("id")) { _,_ in withAnimation { proxy.scrollTo("coach-bottom",anchor:.bottom) } }
            }
            composer
        }
    }
    private func bubble(_ text: String, user: Bool, failed: Bool = false) -> some View {
        HStack {
            if user { Spacer(minLength:32) }
            Text(text).textSelection(.enabled).font(.body).foregroundStyle(failed ? Color.orange : Color.primary).padding(15)
                .background(user ? GymTheme.green.opacity(0.18) : GymTheme.card,in:RoundedRectangle(cornerRadius:18))
            if !user { Spacer(minLength:20) }
        }
    }
    private var composer: some View {
        VStack(spacing:10) {
            if !session.running && session.pending == nil {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack {
                        Button("评估训练") { Task { await session.ask("review") } }.buttonStyle(.bordered)
                        Button("上次训练") { Task { await session.ask("debrief") } }.buttonStyle(.bordered).disabled(session.store.workouts.isEmpty)
                        Button("设计新计划") { Task { await session.ask("create") } }.buttonStyle(.bordered)
                    }.disabled(session.locked)
                }
            }
            HStack(alignment:.bottom,spacing:12) {
                TextField(session.running ? "正在思考" : session.pending?.coachText("kind") == "create" ? "修改要求" : "发消息",text:$session.draft,axis:.vertical)
                    .lineLimit(1...5).padding(12).background(GymTheme.card,in:RoundedRectangle(cornerRadius:14)).disabled(session.running)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(session.draft.count > session.maxLength ? Color.orange : .clear))
                    .accessibilityIdentifier("coach-composer")
                Button {
                    if session.draft.count > session.maxLength { composerIssue = "最多 \(session.maxLength) 字，当前 \(session.draft.count) 字。" }
                    else { Task { await session.send() } }
                } label: { Image(systemName: session.running ? "hourglass" : session.draft.count > session.maxLength ? "exclamationmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size:36)).frame(width: 44, height: 44) }
                    .disabled(session.locked || session.running || session.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(session.running ? "教练正在思考" : session.draft.count > session.maxLength ? "字数超限，查看详情" : "发送给教练").accessibilityIdentifier("coach-send")
            }
        }.padding().background(.ultraThinMaterial).operationAlert($composerIssue, title: "字数超限")
    }
}

struct CoachConsentView: View {
    let session: CoachSession
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Image(systemName:"sparkles").font(.system(size:42)).foregroundStyle(GymTheme.green)
                Text("启用 AI 教练").font(.largeTitle.bold())
                Text("会读取哪些数据").font(.headline)
                ForEach(session.info.coachObjects("categories").map { CoachRecord(raw:$0) }) { record in
                    let item = record.raw
                    VStack(alignment:.leading,spacing:6) { Label(item.coachText("title"),systemImage:"checkmark.circle");Text(item.coachText("detail")).font(.subheadline).foregroundStyle(.secondary) }
                }
                Text("数据发送给服务器配置的 \(session.disclosure.coachText("providerLabel"))，使用管理员的服务账号。你的姓名、登录凭据和其他用户的数据不会包含在请求中。").font(.footnote).foregroundStyle(.secondary)
                Text("教练不是医生或物理治疗师；如果疼痛，请咨询专业人士。").font(.footnote).foregroundStyle(.orange)
                CoachPrimaryButton(title:session.busy ? "正在保存" : "我已了解，继续",icon:"checkmark") { Task { _ = await session.agree() } }
                    .disabled(session.locked || session.disclosure.isEmpty).accessibilityIdentifier("coach-consent")
            }.padding(24)
        }
    }
}


struct CoachPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action:action) {
            HStack(spacing:8) { if let icon { Image(systemName:icon) }; Text(title).fontWeight(.semibold).multilineTextAlignment(.center) }
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth:.infinity,minHeight:24).padding(.horizontal,16).padding(.vertical,14)
                .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.55))
                .background(enabled ? GymTheme.green : Color.white.opacity(0.1),in:RoundedRectangle(cornerRadius:15))
        }.buttonStyle(.plain)
    }
}
struct CoachTextAction: View {
    let title: String
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action:action) {
            Text(title).font(.body.weight(.medium)).multilineTextAlignment(.center)
                .frame(maxWidth:.infinity,minHeight:48)
                .foregroundStyle(Color(red:1,green:0.48,blue:0.48).opacity(enabled ? 1 : 0.4))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
