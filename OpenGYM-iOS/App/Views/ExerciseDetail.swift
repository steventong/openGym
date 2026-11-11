import SwiftUI
import AVFoundation
import Observation
import OSLog

// Session calls can block on the audio service. Keep configuration and release
// ordered on one worker queue, including when views are rapidly opened/closed.
final class ExerciseAudioSession: Sendable {
    static let shared = ExerciseAudioSession()
    private let queue = DispatchQueue(label: "me.itwl.opengym.exercise-audio", qos: .userInitiated)
    private let configure: @Sendable () throws -> Void
    private let release: @Sendable () throws -> Void
    private static let logger = Logger(subsystem: "me.itwl.opengym", category: "ExercisePlayback")

    init(
        configure: @escaping @Sendable () throws -> Void = {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        },
        release: @escaping @Sendable () throws -> Void = {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    ) {
        self.configure = configure
        self.release = release
    }

    func configureForPlayback() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deactivate() {
        queue.async {
            do {
                try self.release()
            } catch {
                Self.logger.error("Cannot release exercise audio session: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor @Observable final class LoopPlayback {
    var ready = false
    var failed = false
    var playing = true
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var startTask: Task<Void, Never>?
    private static let logger = Logger(subsystem:"me.itwl.opengym",category:"ExercisePlayback")
    func reset() {
        observation = nil; currentItemObservation = nil
        stop(); player.removeAllItems(); looper = nil; ready = false; failed = false; playing = true
    }
    func load(_ url: URL) {
        reset()
        let item = AVPlayerItem(url:url)
        currentItemObservation = player.observe(\.currentItem,options:[.initial,.new]) { [weak self] player, _ in
            let current = player.currentItem
            Task { @MainActor in self?.observeItem(current) }
        }
        player.isMuted = true; looper = AVPlayerLooper(player:player,templateItem:item); resume()
    }
    private func observeItem(_ item: AVPlayerItem?) {
        guard let item, player.currentItem === item else { return }
        observation = item.observe(\.status,options:[.initial,.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.updateReadiness(status)
            }
        }
    }
    // Loading is a one-time state for this URL. Loop item handoffs can briefly
    // report .unknown; keep the video visible, but still surface real failures.
    func updateReadiness(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay: ready = true; failed = false
        case .failed: ready = false; failed = true
        case .unknown: break
        @unknown default: break
        }
    }
    func toggle() { playing.toggle(); playing ? resume() : stop() }
    func resume() {
        guard playing else { return }
        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Catalogue clips have no audio tracks. Muting alone still lets AVPlayer
            // activate the shared audio session, so disconnect it before playback.
            if #available(iOS 27.0, *) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.player.setDisconnectedFromSystemAudio(true) { continuation.resume() }
                }
            } else {
                do {
                    // Older systems cannot disconnect AVPlayer from system audio.
                    // Ambient mixes with music without interrupting or ducking it.
                    try await ExerciseAudioSession.shared.configureForPlayback()
                } catch {
                    guard !Task.isCancelled else { return }
                    Self.logger.error("Cannot configure silent video playback: \(error.localizedDescription)")
                    failed = true
                    return
                }
            }
            // Closing or backgrounding while the disconnect completes must not
            // restart a player that the view has already stopped.
            guard !Task.isCancelled else { return }
            player.play()
        }
    }
    func stop() {
        startTask?.cancel(); startTask = nil
        player.pause()
        ExerciseAudioSession.shared.deactivate()
    }
}
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context:Context) -> PlayerLayerView {
        let view = PlayerLayerView(); view.backgroundColor = .white; view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.player = player; return view
    }
    func updateUIView(_ uiView:PlayerLayerView,context:Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) { uiView.playerLayer.player = nil }
}
struct ExerciseDetail: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let initialExercise: Exercise
    @State private var playback = LoopPlayback()
    @State private var videoAttempt = 0
    @State private var weight = 20.0
    @State private var reps = 10
    @State private var choosePlan = false
    @State private var saved = false
    @State private var editingCustom: RawRow?
    @State private var progress = false
    @State private var copiedName = false
    @State private var copyFeedbackID = UUID()
    @State private var namingCopy = false
    @State private var copyName = ""
    @State private var copyID = "c" + UUID().uuidString
    @State private var copyIssue: String?
    @State private var savedCopyName: String?
    @State private var copyConfirmation: String?
    @FocusState private var copyNameFocused: Bool

    init(exercise: Exercise) {
        initialExercise = exercise
    }

    private var exercise: Exercise { store.exercise(initialExercise.id) ?? initialExercise }

    private var customExercise: [String: Any]? {
        store.customExercises.first { $0["id"] as? String == exercise.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:7) {
                        Text(exercise.titleParts.primary).font(.system(size:24,weight:.bold)).lineLimit(1).minimumScaleFactor(0.7)
                        if !exercise.titleParts.secondary.isEmpty { Text(exercise.titleParts.secondary).font(.system(size:13)).foregroundStyle(GymTheme.muted) }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = exercise.clipboardName
                            copiedName = true
                            copyFeedbackID = UUID()
                        } label: {
                            ExerciseDetailActionIcon(symbol: copiedName ? "checkmark" : "doc.on.doc")
                        }.accessibilityLabel(LocalizedStringKey(copiedName ? "EXERCISE_NAME_COPIED" : "COPY_EXERCISE_NAME"))
                            .accessibilityIdentifier("copy-exercise-name")
                        Menu {
                            Button("COPY_EXERCISE", systemImage: "doc.on.doc") { namingCopy = true }
                                .disabled(store.syncing)
                            if let customExercise {
                                Button("EDIT_EXERCISE", systemImage: "pencil") {
                                    editingCustom = RawRow(raw: customExercise)
                                }
                            }
                        } label: {
                            ExerciseDetailActionIcon(symbol: "ellipsis")
                        }
                        .accessibilityLabel("MORE_EXERCISE_ACTIONS")
                        .accessibilityIdentifier("exercise-detail-menu")
                        Button { dismiss() } label: { ExerciseDetailActionIcon(symbol: "xmark") }
                            .accessibilityLabel("CLOSE_EXERCISE_DETAILS")
                    }.buttonStyle(.plain).fixedSize()
                }
                if store.videoMediaID(exercise.id) != nil {
                  ZStack(alignment:.bottomTrailing) {
                    PlayerSurface(player:playback.player).frame(height:260).background(.white)
                    if !playback.ready && !playback.failed {
                        ProgressView().tint(.gray).accessibilityLabel("LOADING_VIDEO")
                            .foregroundStyle(.black).frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    if playback.failed {
                        VStack(spacing:12) { Image(systemName:"exclamationmark.triangle").accessibilityLabel("COULD_NOT_PLAY_VIDEO"); Button("TRY_AGAIN") { videoAttempt += 1 } }.padding().foregroundStyle(.black).frame(maxWidth:.infinity,maxHeight:.infinity).background(.white)
                    } else {
                        Button { playback.toggle() } label: {
                            Label(LocalizedStringKey(playback.playing ? "TAP_TO_PAUSE" : "RESUME_PLAYBACK"),systemImage:playback.playing ? "pause.fill" : "play.fill").font(.system(size:11,weight:.medium)).padding(9).foregroundStyle(.white).background(.black.opacity(0.4),in:Capsule())
                        }.padding(12).accessibilityIdentifier("animation-toggle").disabled(!playback.ready)
                    }
                  }.clipShape(RoundedRectangle(cornerRadius:18)).accessibilityElement(children:.contain).accessibilityLabel("EXERCISE_DEMONSTRATION")
                }
                HStack(spacing:7) {
                    ForEach([exercise.bodyLabel,exercise.targetLabel,exercise.equipmentLabel],id:\.self) { label in
                        Text(label).font(.system(size:11,weight:.medium)).padding(.horizontal,10).padding(.vertical,6).foregroundStyle(GymTheme.green).background(GymTheme.green.opacity(0.12),in:Capsule())
                    }
                }
                HStack {
                    Button { Task { _ = await store.setFavourite(exercise.id,enabled:!store.favouriteIDs.contains(exercise.id)) } } label: { Label(LocalizedStringKey(store.favouriteIDs.contains(exercise.id) ? "FAVOURITED":"FAVOURITES"),systemImage:store.favouriteIDs.contains(exercise.id) ? "star.fill":"star") }.disabled(store.syncing)
                    Spacer()
                    Button("WORKOUT_HISTORY_AND_PROGRESS") { progress = true }
                }
                if let link = customExercise?["url"] as? String, let url = URL(string:link), ["http","https"].contains(url.scheme?.lowercased() ?? "") {
                    Link("OPEN_EXERCISE_TUTORIAL",destination:url)
                }
                GreenButton(title:saved ? "ADDED_TO_ROUTINE" : "ADD_TO_MY_PLAN",icon:saved ? "checkmark" : "plus") { choosePlan = true }
                    .disabled(saved || store.syncing)
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("EST_ONE_REP_MAX").font(.headline); Spacer(); Text(store.state["oneRmFormula"] as? String ?? "epley").font(.caption).foregroundStyle(GymTheme.muted) }
                    HStack(spacing:14) {
                        VStack(alignment:.leading,spacing:9) { Text(String(format: String(localized: "WEIGHT_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: store.unit))).font(.caption).foregroundStyle(GymTheme.muted); Stepper(decimal(weight),value:$weight,in:0...1000,step:2.5) }
                        VStack(alignment:.leading,spacing:9) { Text("REPS").font(.caption).foregroundStyle(GymTheme.muted); Stepper(value: $reps, in: 1...30) { Text(verbatim: String(reps)) } }
                    }
                    Text(estimateText).font(.system(size:30,weight:.bold,design:.rounded)).foregroundStyle(GymTheme.green).frame(maxWidth:.infinity,alignment:.trailing)
                }.gymCard()
                if !exercise.description.isEmpty { Text(exercise.description).font(.system(size:15)).foregroundStyle(GymTheme.muted) }
                if !exercise.instructions.isEmpty { SectionTitle(text:"HOW_TO") }
                ForEach(Array(exercise.instructions.enumerated()),id:\.offset) { index, text in
                    HStack(alignment:.top,spacing:12) {
                        Text(String(format:"%02d",index + 1)).font(.system(size:13,weight:.semibold,design:.monospaced)).foregroundStyle(GymTheme.green).padding(.top,2)
                        Text(text).font(.system(size:15)).foregroundStyle(.white.opacity(0.8)).lineSpacing(6)
                    }
                }
                Text("EXERCISE_MEDIA_ALIAKSANDR_MAKATSERCHYK_GYM_VISUAL_USED_IN_OPENGYM_UNDER_THE_ORIGINAL").font(.system(size:10)).foregroundStyle(GymTheme.muted).padding(.top,12)
            }.padding(22)
        }.background(GymTheme.background).presentationDragIndicator(.visible)
            .sheet(item: $editingCustom) {
                CustomExerciseEditor(original: $0.raw)
            }
            .sheet(isPresented:$progress) { NavigationStack { ExerciseProgressView(initialID:exercise.id) } }
            .sheet(isPresented: $namingCopy, onDismiss: finishNamingCopy) {
                copyNameSheet
            }
            .operationAlert($copyConfirmation, title: "EXERCISE_COPIED")
            .task(id:"\(exercise.id)|\(store.videoMediaID(exercise.id) ?? "")|\(store.serverURL)|\(videoAttempt)") { await loadVideo() }.onDisappear { playback.stop() }
            .task(id:copyFeedbackID) {
                guard copiedName else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                copiedName = false
            }
            .onChange(of:scenePhase) { _, phase in if phase != .active { playback.stop() } else { playback.resume() } }
            .confirmationDialog("ADD_TO_WHICH_ROUTINE",isPresented:$choosePlan,titleVisibility:.visible) {
                ForEach(store.routines) { routine in Button(routine.name) { Task { saved = await store.appendExercise(exercise,to:routine.id) } } }
                Button("CREATE_A_SINGLE_EXERCISE_ROUTINE") { Task { saved = await store.addRoutine(name:exercise.name,exerciseIDs:[exercise.id]) } }
                Button("CANCEL",role:.cancel) {}
            }
    }

    private var copyNameSheet: some View {
        NavigationStack {
            Form {
                TextField("EXERCISE_NAME", text: $copyName)
                    .focused($copyNameFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await saveExerciseCopy() } }
                    .onChange(of: copyName) { copyIssue = nil }
                    .disabled(store.syncing)
                    .accessibilityIdentifier("exercise-copy-name")
                if let copyIssue { Text(copyIssue).foregroundStyle(.red) }
            }
            .navigationTitle("COPY_EXERCISE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { namingCopy = false }.disabled(store.syncing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("SAVE") { Task { await saveExerciseCopy() } }
                        .disabled(store.syncing)
                        .accessibilityIdentifier("save-exercise-copy")
                }
            }
        }
        .presentationDetents([.height(240), .large])
        .interactiveDismissDisabled(store.syncing)
        .onAppear { copyNameFocused = true }
    }

    private func finishNamingCopy() {
        copyConfirmation = savedCopyName
        savedCopyName = nil
        copyName = ""
        copyIssue = nil
        copyID = "c" + UUID().uuidString
    }

    private func saveExerciseCopy() async {
        guard !store.syncing else { return }
        let name = copyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = store.customExerciseNameIssue(name) {
            copyIssue = issue
            return
        }
        do {
            let proposed = try store.exerciseCopyRecord(exercise, id: copyID, name: name)
            if await store.savePersonalRecord(collection: "customEx", key: "id", original: nil, proposed: proposed) {
                savedCopyName = name
                namingCopy = false
            } else {
                copyIssue = store.editError
            }
        } catch {
            copyIssue = error.localizedDescription
        }
    }

    private var estimateText:String {
        guard let result = try? store.personalInfo("oneRM",["weight":weight,"reps":reps]), let value = result["value"] as? Double else { return String(localized: "TOO_MANY_REPS_FOR_A_RELIABLE_ESTIMATE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        return "\(decimal(value)) \(store.unit)"
    }
    private func loadVideo() async {
        playback.reset()
        guard let mediaID = store.videoMediaID(exercise.id) else { return }
        do {
            let local = try await ExerciseVideoCache.shared.video(for: mediaID, remoteURL: store.remoteVideoURL(exercise.id))
            try Task.checkCancellation()
            playback.load(local)
            if scenePhase != .active { playback.stop() }
        } catch {
            guard !Task.isCancelled else { return }
            playback.failed = true
        }
    }
}
