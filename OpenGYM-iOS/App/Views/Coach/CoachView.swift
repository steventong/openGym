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
    init(store: GymStore) { _session = State(initialValue:CoachSession(store:store)) }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                if !session.loaded { ProgressView().accessibilityLabel("CONNECTING_TO_COACH").frame(maxWidth:.infinity,maxHeight:.infinity) }
                else if !session.enabled {
                    EmptyCard(icon:"sparkles",title:"COACH_UNAVAILABLE").padding()
                    ExplanationButton(title: "ENABLE_COACH", message: "PAIR_YOUR_ACCOUNT_THEN_ASK_YOUR_ADMINISTRATOR_TO_ENABLE_THE_AI_COACH")
                    Button("CHECK_AGAIN") { Task { await session.refresh() } }.disabled(session.locked)
                    Spacer()
                } else if !session.hasConsent {
                    CoachConsentView(session:session)
                } else if session.profile.isEmpty {
                    CoachIntakeView(session:session,editing:false)
                } else { conversation }
            }
            .background(GymTheme.background).navigationTitle("AI_COACH").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button("DONE") { dismiss() } }
                ToolbarItem(placement:.topBarTrailing) {
                    HStack {
                        if let error = session.error {
                            StatusDetailButton(title: "RETRY_NEEDED", message: "\(error)", warning: true).accessibilityIdentifier("coach-error")
                            Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(session.locked).accessibilityLabel("RETRY_CONNECTION")
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
                    }.background(GymTheme.background).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("TURN_OFF") { sheet = nil } } }
                }.tint(GymTheme.green).preferredColorScheme(.dark)
            }
            .confirmationDialog("UNDO_THE_LAST_COACH_CHANGES",isPresented:$confirmUndo,titleVisibility:.visible) {
                Button("UNDO_CHANGES",role:.destructive) { Task { await session.revert() } }
            } message: { Text("YOUR_ROUTINES_WILL_RETURN_TO_THEIR_PREVIOUS_STATE_WORKOUTS_LOGGED_SINCE_THEN") }
            .task(id:"\(scenePhase)-\(session.running)") { if scenePhase == .active { await session.poll() } }
        }.tint(GymTheme.green).preferredColorScheme(.dark)
    }
    private var actions: some View {
        Menu {
            if !session.running && session.pending == nil {
                Button("REVIEW_MY_TRAINING",systemImage:"sparkles") { Task { await session.ask("review") } }
                Button("REVIEW_MY_LAST_WORKOUT",systemImage:"checkmark.circle") { Task { await session.ask("debrief") } }.disabled(session.store.workouts.isEmpty)
                Menu("IMPROVE_A_SPECIFIC_ROUTINE") {
                    ForEach(session.store.routines) { routine in Button(routine.name) { Task { await session.ask("review",routine:routine) } } }
                }
                Button("BUILD_A_NEW_PLAN",systemImage:"plus.rectangle") { Task { await session.ask("create") } }
            }
            Button("PAST_SUGGESTIONS",systemImage:"clock.arrow.circlepath") { sheet = .history }
            Button("EDIT_TRAINING_QUESTIONNAIRE",systemImage:"pencil") { sheet = .profile }
            Button("AUTOMATIC_REVIEW",systemImage:"calendar.badge.clock") { sheet = .cadence }
            let cap = session.status.coachObject("cap")
            if number(cap["limit"]) > 0 { Text(String(format: String(localized: "TODAY_S_USAGE_COUNT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(cap["used"]))), String(describing: Int(number(cap["limit"]))))) }
            if session.configuration.coachObject("coach")["community"] as? Bool == true { Button("ANONYMOUS_TRAINING_COMPARISONS",systemImage:"person.2") { sheet = .community } }
            if session.info["canRevert"] as? Bool == true { Button("UNDO_LAST_COACH_CHANGES",systemImage:"arrow.uturn.backward") { confirmUndo = true }.disabled(session.running) }
        } label: { Image(systemName:"ellipsis.circle").accessibilityLabel("COACH_MENU") }.disabled(session.locked).accessibilityIdentifier("coach-menu")
    }
    private var conversation: some View {
        VStack(spacing:0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:18) {
                        ForEach(Array(session.coach.coachObjects("chat").enumerated()),id:\.offset) { _,message in
                            VStack(alignment:.leading,spacing:8) {
                                let text = message.coachText("kind") == "intake" ? (session.info["profileLines"] as? [String] ?? []).joined(separator:"\n") : message.coachText("text")
                                if !text.isEmpty { CoachMessageBubble(text: text, user:message.coachText("role") == "user", failed:message.coachText("kind") == "error") }
                                if let record = session.history.first(where: { $0.coachText("id") == message.coachText("ref") }) {
                                    Button { sheet = .record(CoachRecord(raw:record)) } label: {
                                        Label("VIEW_FULL_SUGGESTION_AND_OUTCOME",systemImage:"doc.text.magnifyingglass").font(.subheadline).padding()
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                        if let pending = session.pending, !session.running {
                            if session.savedPending != nil {
                                Button("FINISH_SYNCING", systemImage: "arrow.clockwise") { Task { await session.retryResolution() } }
                                    .disabled(session.locked).accessibilityIdentifier("coach-finish-sync")
                            } else { CoachProposalView(session:session,proposal:pending).id(pending.coachText("id")) }
                        }
                        Color.clear.frame(height:1).id("coach-bottom")
                    }.padding()
                }.refreshable { await session.refresh() }
                .onChange(of:session.coach.coachObjects("chat").count) { _,_ in withAnimation { proxy.scrollTo("coach-bottom",anchor:.bottom) } }
                .onChange(of:session.pending?.coachText("id")) { _,_ in withAnimation { proxy.scrollTo("coach-bottom",anchor:.bottom) } }
            }
            CoachComposer(session: session)
        }
    }
}

private struct CoachComposer: View {
    @Bindable var session: CoachSession
    @State private var composerIssue: String?
    var body: some View {
        VStack(spacing:10) {
            if !session.running && session.pending == nil {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack {
                        Button("REVIEW_TRAINING") { Task { await session.ask("review") } }.buttonStyle(.bordered)
                        Button("LAST_WORKOUT") { Task { await session.ask("debrief") } }.buttonStyle(.bordered).disabled(session.store.workouts.isEmpty)
                        Button("BUILD_A_NEW_PLAN") { Task { await session.ask("create") } }.buttonStyle(.bordered)
                    }.disabled(session.locked)
                }
            }
            HStack(alignment:.bottom,spacing:12) {
                TextField(LocalizedStringKey(session.running ? "THINKING" : session.pending?.coachText("kind") == "create" ? "REVISE_REQUEST" : "SEND_A_MESSAGE"),text:$session.draft,axis:.vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }
                    .lineLimit(1...5).padding(12).background(GymTheme.card,in:RoundedRectangle(cornerRadius:14)).disabled(session.running)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(session.draft.count > session.maxLength ? Color.orange : .clear))
                    .accessibilityIdentifier("coach-composer")
                Button {
                    if session.draft.count > session.maxLength { composerIssue = String(format: String(localized: "MAXIMUM_COUNT_CHARACTERS_CURRENTLY_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: session.maxLength), String(describing: session.draft.count)) }
                    else { Task { await session.send() } }
                } label: { Image(systemName: session.running ? "hourglass" : session.draft.count > session.maxLength ? "exclamationmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size:36)).frame(width: 44, height: 44) }
                    .disabled(session.locked || session.running || session.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(LocalizedStringKey(session.running ? "COACH_IS_THINKING" : session.draft.count > session.maxLength ? "MESSAGE_TOO_LONG_VIEW_DETAILS" : "SEND_TO_COACH")).accessibilityIdentifier("coach-send")
            }
        }.padding().background(.ultraThinMaterial).operationAlert($composerIssue, title: "MESSAGE_TOO_LONG")
    }
}

struct CoachConsentView: View {
    let session: CoachSession
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Image(systemName:"sparkles").font(.system(size:42)).foregroundStyle(GymTheme.green)
                Text("ENABLE_AI_COACH").font(.largeTitle.bold())
                Text("WHAT_DATA_IS_SHARED").font(.headline)
                ForEach(session.info.coachObjects("categories").map { CoachRecord(raw:$0) }) { record in
                    let item = record.raw
                    VStack(alignment:.leading,spacing:6) { Label(item.coachText("title"),systemImage:"checkmark.circle");Text(item.coachText("detail")).font(.subheadline).foregroundStyle(.secondary) }
                }
                Text(String(format: String(localized: "DATA_IS_SENT_TO_COUNT_CONFIGURED_BY_YOUR_SERVER_USING_THE_ADMINISTRATOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: session.disclosure.coachText("providerLabel")))).font(.footnote).foregroundStyle(.secondary)
                Text("YOUR_COACH_IS_NOT_A_DOCTOR_OR_PHYSIOTHERAPIST_IF_YOU_HAVE_PAIN").font(.footnote).foregroundStyle(.orange)
                CoachPrimaryButton(title:session.busy ? "SAVING" : "I_UNDERSTAND_CONTINUE",icon:"checkmark") { Task { _ = await session.agree() } }
                    .disabled(session.locked || session.disclosure.isEmpty).accessibilityIdentifier("coach-consent")
            }.padding(24)
        }
    }
}


struct CoachPrimaryButton: View {
    let title: LocalizedStringKey
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
    let title: LocalizedStringKey
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
