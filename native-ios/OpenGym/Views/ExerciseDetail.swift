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
    let exercise: Exercise
    @State private var playback = LoopPlayback()
    @State private var videoAttempt = 0
    @State private var weight = 20.0
    @State private var reps = 10
    @State private var choosePlan = false
    @State private var saved = false
    @State private var editingCustom = false
    @State private var progress = false
    @State private var copiedName = false
    @State private var copyFeedbackID = UUID()
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
                            detailActionIcon(copiedName ? "checkmark" : "doc.on.doc")
                        }.accessibilityLabel(copiedName ? L10n.text("EXERCISE_NAME_COPIED" /* 已复制动作名称 */) : L10n.text("COPY_EXERCISE_NAME" /* 复制动作名称 */))
                            .accessibilityIdentifier("copy-exercise-name")
                        Button { dismiss() } label: { detailActionIcon("xmark") }
                            .accessibilityLabel(L10n.text("CLOSE_EXERCISE_DETAILS" /* 关闭动作详情 */))
                    }.buttonStyle(.plain).fixedSize()
                }
                if store.thumbnailAssetName(exercise.id) != nil {
                  ZStack(alignment:.bottomTrailing) {
                    PlayerSurface(player:playback.player).frame(height:260).background(.white)
                    if !playback.ready && !playback.failed {
                        ProgressView().tint(.gray).accessibilityLabel(L10n.text("LOADING_VIDEO" /* 正在加载视频 */))
                            .foregroundStyle(.black).frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    if playback.failed {
                        VStack(spacing:12) { Image(systemName:"exclamationmark.triangle").accessibilityLabel(L10n.text("COULD_NOT_PLAY_VIDEO" /* 视频播放失败 */)); Button(L10n.text("TRY_AGAIN" /* 重试 */)) { videoAttempt += 1 } }.padding().foregroundStyle(.black).frame(maxWidth:.infinity,maxHeight:.infinity).background(.white)
                    } else {
                        Button { playback.toggle() } label: {
                            Label(playback.playing ? L10n.text("TAP_TO_PAUSE" /* 点按暂停 */) : L10n.text("RESUME_PLAYBACK" /* 继续播放 */),systemImage:playback.playing ? "pause.fill" : "play.fill").font(.system(size:11,weight:.medium)).padding(9).foregroundStyle(.white).background(.black.opacity(0.4),in:Capsule())
                        }.padding(12).accessibilityIdentifier("animation-toggle").disabled(!playback.ready)
                    }
                  }.clipShape(RoundedRectangle(cornerRadius:18)).accessibilityElement(children:.contain).accessibilityLabel(L10n.text("EXERCISE_DEMONSTRATION" /* 动作示范动画 */))
                }
                HStack(spacing:7) {
                    ForEach([exercise.bodyLabel,exercise.targetLabel,exercise.equipmentLabel],id:\.self) { label in
                        Text(label).font(.system(size:11,weight:.medium)).padding(.horizontal,10).padding(.vertical,6).foregroundStyle(GymTheme.green).background(GymTheme.green.opacity(0.12),in:Capsule())
                    }
                }
                HStack {
                    Button { Task { _ = await store.setFavourite(exercise.id,enabled:!store.favouriteIDs.contains(exercise.id)) } } label: { Label(store.favouriteIDs.contains(exercise.id) ? L10n.text("FAVOURITED" /* 已收藏 */):L10n.text("FAVOURITES" /* 收藏 */),systemImage:store.favouriteIDs.contains(exercise.id) ? "star.fill":"star") }.disabled(store.syncing)
                    Spacer()
                    Button(L10n.text("WORKOUT_HISTORY_AND_PROGRESS" /* 训练历史与进步 */)) { progress = true }
                }
                if store.customExercises.contains(where:{$0["id"] as? String == exercise.id}) {
                    Button(L10n.text("EDIT_CUSTOM_EXERCISE" /* 编辑自定义动作 */)) { editingCustom = true }
                }
                if let link = store.customExercises.first(where:{$0["id"] as? String == exercise.id})?["url"] as? String, let url = URL(string:link), ["http","https"].contains(url.scheme?.lowercased() ?? "") {
                    Link(L10n.text("OPEN_EXERCISE_TUTORIAL" /* 打开动作教学链接 */),destination:url)
                }
                GreenButton(title:saved ? L10n.text("ADDED_TO_ROUTINE" /* 已加入计划 */) : L10n.text("ADD_TO_MY_PLAN" /* 加入我的计划 */),icon:saved ? "checkmark" : "plus") { choosePlan = true }
                    .disabled(saved || store.syncing)
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text(L10n.text("EST_ONE_REP_MAX" /* 估算 1RM */)).font(.headline); Spacer(); Text(store.state["oneRmFormula"] as? String ?? "epley").font(.caption).foregroundStyle(GymTheme.muted) }
                    HStack(spacing:14) {
                        VStack(alignment:.leading,spacing:9) { Text(L10n.text("WEIGHT_COUNT" /* 重量（{0}） */, store.unit)).font(.caption).foregroundStyle(GymTheme.muted); Stepper(decimal(weight),value:$weight,in:0...1000,step:2.5) }
                        VStack(alignment:.leading,spacing:9) { Text(L10n.text("REPS" /* 次数 */)).font(.caption).foregroundStyle(GymTheme.muted); Stepper("\(reps)",value:$reps,in:1...30) }
                    }
                    Text(estimateText).font(.system(size:30,weight:.bold,design:.rounded)).foregroundStyle(GymTheme.green).frame(maxWidth:.infinity,alignment:.trailing)
                }.gymCard()
                if !exercise.description.isEmpty { Text(exercise.description).font(.system(size:15)).foregroundStyle(GymTheme.muted) }
                if !exercise.instructions.isEmpty { SectionTitle(text:L10n.text("HOW_TO" /* 动作要领 */)) }
                ForEach(Array(exercise.instructions.enumerated()),id:\.offset) { index, text in
                    HStack(alignment:.top,spacing:12) {
                        Text(String(format:"%02d",index + 1)).font(.system(size:13,weight:.semibold,design:.monospaced)).foregroundStyle(GymTheme.green).padding(.top,2)
                        Text(text).font(.system(size:15)).foregroundStyle(.white.opacity(0.8)).lineSpacing(6)
                    }
                }
                Text(L10n.text("EXERCISE_MEDIA_ALIAKSANDR_MAKATSERCHYK_GYM_VISUAL_USED_IN_OPENGYM_UNDER_THE_ORIGINAL" /* 动作素材 © Aliaksandr Makatserchyk · Gym visual 用于 openGym，保留原版授权。 */)).font(.system(size:10)).foregroundStyle(GymTheme.muted).padding(.top,12)
            }.padding(22)
        }.background(GymTheme.background).presentationDragIndicator(.visible)
            .sheet(isPresented:$editingCustom) { CustomExerciseEditor(original:store.customExercises.first {$0["id"] as? String == exercise.id}) }
            .sheet(isPresented:$progress) { NavigationStack { ExerciseProgressView(initialID:exercise.id) } }
            .task(id:"\(exercise.id)|\(store.serverURL)|\(videoAttempt)") { await loadVideo() }.onDisappear { playback.stop() }
            .task(id:copyFeedbackID) {
                guard copiedName else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                copiedName = false
            }
            .onChange(of:scenePhase) { _, phase in if phase != .active { playback.stop() } else { playback.resume() } }
            .confirmationDialog(L10n.text("ADD_TO_WHICH_ROUTINE" /* 加入哪个计划？ */),isPresented:$choosePlan,titleVisibility:.visible) {
                ForEach(store.routines) { routine in Button(routine.name) { Task { saved = await store.appendExercise(exercise,to:routine.id) } } }
                Button(L10n.text("CREATE_A_SINGLE_EXERCISE_ROUTINE" /* 新建单动作计划 */)) { Task { saved = await store.addRoutine(name:exercise.name,exerciseIDs:[exercise.id]) } }
                Button(L10n.text("CANCEL" /* 取消 */),role:.cancel) {}
            }
    }
    private func detailActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size:13,weight:.bold)).foregroundStyle(.gray)
            .frame(width:44,height:44)
            .background(.white.opacity(0.07),in:Circle())
    }
    private var estimateText:String {
        guard let result = try? store.personalInfo("oneRM",["weight":weight,"reps":reps]), let value = result["value"] as? Double else { return L10n.text("TOO_MANY_REPS_FOR_A_RELIABLE_ESTIMATE" /* 次数过高，无法可靠估算 */) }
        return "\(decimal(value)) \(store.unit)"
    }
    private func loadVideo() async {
        playback.reset()
        guard store.thumbnailAssetName(exercise.id) != nil else { return }
        do {
            let local = try await ExerciseVideoCache.shared.video(for: exercise.id, remoteURL: store.remoteVideoURL(exercise.id))
            try Task.checkCancellation()
            playback.load(local)
            if scenePhase != .active { playback.stop() }
        } catch {
            guard !Task.isCancelled else { return }
            playback.failed = true
        }
    }
}
