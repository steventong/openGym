import SwiftUI
import AVFoundation
import Observation
import OSLog

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
    func load(_ url: URL) {
        observation = nil; currentItemObservation = nil
        stop(); player.removeAllItems(); looper = nil; ready = false; failed = false; playing = true
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
                    try AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default)
                } catch {
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
        do {
            try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        } catch {
            Self.logger.error("Cannot release exercise audio session: \(error.localizedDescription)")
        }
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
                        }.accessibilityLabel(copiedName ? "已复制动作名称" : "复制动作名称")
                            .accessibilityIdentifier("copy-exercise-name")
                        Button { dismiss() } label: { detailActionIcon("xmark") }
                            .accessibilityLabel("关闭动作详情")
                    }.buttonStyle(.plain).fixedSize()
                }
                if store.mediaURL(exercise.id, video: true) != nil {
                  ZStack(alignment:.bottomTrailing) {
                    PlayerSurface(player:playback.player).frame(height:260).background(.white)
                    if !playback.ready && !playback.failed {
                        ProgressView().tint(.gray).accessibilityLabel("正在加载视频")
                            .foregroundStyle(.black).frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    if playback.failed {
                        VStack(spacing:12) { Image(systemName:"exclamationmark.triangle").accessibilityLabel("视频播放失败"); Button("重试") { loadVideo() } }.padding().foregroundStyle(.black).frame(maxWidth:.infinity,maxHeight:.infinity).background(.white)
                    } else {
                        Button { playback.toggle() } label: {
                            Label(playback.playing ? "点按暂停" : "继续播放",systemImage:playback.playing ? "pause.fill" : "play.fill").font(.system(size:11,weight:.medium)).padding(9).foregroundStyle(.white).background(.black.opacity(0.4),in:Capsule())
                        }.padding(12).accessibilityIdentifier("animation-toggle").disabled(!playback.ready)
                    }
                  }.clipShape(RoundedRectangle(cornerRadius:18)).accessibilityElement(children:.contain).accessibilityLabel("动作示范动画")
                }
                HStack(spacing:7) {
                    ForEach([exercise.bodyLabel,exercise.targetLabel,exercise.equipmentLabel],id:\.self) { label in
                        Text(label).font(.system(size:11,weight:.medium)).padding(.horizontal,10).padding(.vertical,6).foregroundStyle(GymTheme.green).background(GymTheme.green.opacity(0.12),in:Capsule())
                    }
                }
                HStack {
                    Button { Task { _ = await store.setFavourite(exercise.id,enabled:!store.favouriteIDs.contains(exercise.id)) } } label: { Label(store.favouriteIDs.contains(exercise.id) ? "已收藏":"收藏",systemImage:store.favouriteIDs.contains(exercise.id) ? "star.fill":"star") }.disabled(store.syncing)
                    Spacer()
                    Button("训练历史与进步") { progress = true }
                }
                if store.customExercises.contains(where:{$0["id"] as? String == exercise.id}) {
                    Button("编辑自定义动作") { editingCustom = true }
                }
                if let link = store.customExercises.first(where:{$0["id"] as? String == exercise.id})?["url"] as? String, let url = URL(string:link), ["http","https"].contains(url.scheme?.lowercased() ?? "") {
                    Link("打开动作教学链接",destination:url)
                }
                GreenButton(title:saved ? "已加入计划" : "加入我的计划",icon:saved ? "checkmark" : "plus") { choosePlan = true }
                    .disabled(saved || store.syncing)
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("预估 1RM").font(.headline); Spacer(); Text(store.state["oneRmFormula"] as? String ?? "epley").font(.caption).foregroundStyle(GymTheme.muted) }
                    HStack(spacing:14) {
                        VStack(alignment:.leading,spacing:9) { Text("重量（\(store.unit)）").font(.caption).foregroundStyle(GymTheme.muted); Stepper(decimal(weight),value:$weight,in:0...1000,step:2.5) }
                        VStack(alignment:.leading,spacing:9) { Text("次数").font(.caption).foregroundStyle(GymTheme.muted); Stepper("\(reps)",value:$reps,in:1...30) }
                    }
                    Text(estimateText).font(.system(size:30,weight:.bold,design:.rounded)).foregroundStyle(GymTheme.green).frame(maxWidth:.infinity,alignment:.trailing)
                }.gymCard()
                if !exercise.description.isEmpty { Text(exercise.description).font(.system(size:15)).foregroundStyle(GymTheme.muted) }
                if !exercise.instructions.isEmpty { SectionTitle(text:"动作要领") }
                ForEach(Array(exercise.instructions.enumerated()),id:\.offset) { index, text in
                    HStack(alignment:.top,spacing:12) {
                        Text(String(format:"%02d",index + 1)).font(.system(size:13,weight:.semibold,design:.monospaced)).foregroundStyle(GymTheme.green).padding(.top,2)
                        Text(text).font(.system(size:15)).foregroundStyle(.white.opacity(0.8)).lineSpacing(6)
                    }
                }
                Text("动作素材 © Aliaksandr Makatserchyk · Gym visual\n用于 openGym，保留原版授权。").font(.system(size:10)).foregroundStyle(GymTheme.muted).padding(.top,12)
            }.padding(22)
        }.background(GymTheme.background).presentationDragIndicator(.visible)
            .sheet(isPresented:$editingCustom) { CustomExerciseEditor(original:store.customExercises.first {$0["id"] as? String == exercise.id}) }
            .sheet(isPresented:$progress) { NavigationStack { ExerciseProgressView(initialID:exercise.id) } }
            .task(id:exercise.id) { loadVideo() }.onDisappear { playback.stop() }
            .task(id:copyFeedbackID) {
                guard copiedName else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                copiedName = false
            }
            .onChange(of:scenePhase) { _, phase in if phase != .active { playback.stop() } else { playback.resume() } }
            .confirmationDialog("加入哪个计划？",isPresented:$choosePlan,titleVisibility:.visible) {
                ForEach(store.routines) { routine in Button(routine.name) { Task { saved = await store.appendExercise(exercise,to:routine.id) } } }
                Button("新建单动作计划") { Task { saved = await store.addRoutine(name:exercise.name,exerciseIDs:[exercise.id]) } }
                Button("取消",role:.cancel) {}
            }
    }
    private func detailActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size:13,weight:.bold)).foregroundStyle(.gray)
            .frame(width:44,height:44)
            .background(.white.opacity(0.07),in:Circle())
    }
    private var estimateText:String {
        guard let result = try? store.personalInfo("oneRM",["weight":weight,"reps":reps]), let value = result["value"] as? Double else { return "次数过高，无法可靠估算" }
        return "\(decimal(value)) \(store.unit)"
    }
    private func loadVideo() {
        if let local = store.mediaURL(exercise.id,video:true) {
            playback.load(local)
            if scenePhase != .active { playback.stop() }
        }
    }
}
