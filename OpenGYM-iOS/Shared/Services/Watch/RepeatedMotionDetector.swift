import Foundation

/// 只判断连续往返运动，不识别具体健身动作；所有阈值和候选状态都留在这里。
/// 直线动作（推、蹲）看线加速度；绕关节的弧线动作（弯举、侧平举）加速度方向随弧线转动，
/// 单轴投影不成立，改看设备系角速度，两个通道任一确认即可。
struct RepeatedMotionDetector {
    struct Vector: Equatable {
        var x: Double
        var y: Double
        var z: Double
        var length: Double { sqrt(dot(self)) }
        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
        func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }
        func scaled(_ scale: Double) -> Self { .init(x: x * scale, y: y * scale, z: z * scale) }
        func adding(_ other: Self) -> Self { .init(x: x + other.x, y: y + other.y, z: z + other.z) }
        static let zero = Self(x: 0, y: 0, z: 0)
    }

    struct Sample {
        /// Core Motion 的开机单调时间，周期计算不受墙上时钟调整影响。
        var timestamp: TimeInterval
        var recordedAt: Date
        /// 去重力加速度，单位 g；采样源负责统一坐标系。
        var acceleration: Vector
        /// 设备系角速度，单位 rad/s；铰链动作的转轴固定在前臂上，不随手腕姿态变化。
        var rotationRate = Vector.zero
    }

    enum Channel: String { case linear, rotation }

    /// 供上层写日志的判定过程；只记录，不参与判定。
    struct Note: Equatable {
        enum Kind: String { case cycle, dropped }
        enum Reason: String {
            case invalidSample, samplingGap, quiet, timeout, fastFlip
            case periodOutOfRange, armSwing, smallTurn, unbalanced, weakPeak, offAxis, cadenceChanged, amplitudeChanged
        }
        var channel: Channel
        var kind: Kind
        /// 已确认的完整周期数；中断时为中断前的数量。
        var cycles: Int
        var reason: Reason?
        var period: TimeInterval?
        /// 线性通道单位 g，转动通道单位 rad/s。
        var positivePeak: Double?
        var negativePeak: Double?
        /// 转动通道两个半程转过的角度（rad）。
        var positiveTurn: Double?
        var negativeTurn: Double?
    }

    private var lastTimestamp: TimeInterval?
    private var detected = false
    private var linear = Tracker(gate: .linear)
    private var rotation = Tracker(gate: .rotation)

    /// 任一通道确认三个完整周期后只返回一次整段运动的起点，而非确认时刻。
    mutating func consume(_ sample: Sample) -> TimeInterval? {
        guard sample.timestamp.isFinite, sample.acceleration.isFinite, sample.rotationRate.isFinite,
              sample.recordedAt.timeIntervalSince1970.isFinite else { noteDrop(.invalidSample); reset(); return nil }
        if detected { return nil }
        let interval = lastTimestamp.map { sample.timestamp - $0 } ?? 0.04
        guard interval > 0 else { noteDrop(.invalidSample); reset(); return nil }
        if interval > 0.35 { noteDrop(.samplingGap); reset() }
        lastTimestamp = sample.timestamp
        // 两个通道都要喂到，不能因一方确认而跳过另一方的滤波。
        let onsets = [linear.consume(sample.acceleration, rotationRate: sample.rotationRate, at: sample.timestamp, interval: interval),
                      rotation.consume(sample.rotationRate, rotationRate: sample.rotationRate, at: sample.timestamp, interval: interval)]
        guard let onset = onsets.compactMap({ $0 }).min() else { return nil }
        detected = true
        return onset
    }

    /// 取出最近的判定记录；每条只返回一次。
    mutating func takeNotes() -> [Note] {
        [linear.takeNote(), rotation.takeNote()].compactMap { $0 }
    }

    mutating func reset() {
        lastTimestamp = nil
        detected = false
        linear.reset()
        rotation.reset()
    }

    private mutating func noteDrop(_ reason: Note.Reason) {
        linear.noteDrop(reason)
        rotation.noteDrop(reason)
    }
}

private extension RepeatedMotionDetector {
    /// 单一信号的往返判定；两个通道共用周期规则，门槛和对称判断不同。
    struct Tracker {
        struct Gate {
            var channel: Channel
            var onset: Double
            var crossing: Double
            var periods: ClosedRange<TimeInterval>
            /// 每个半程至少转过的角度（rad）；设置后按两半转角而非峰值判断往返对称，
            /// 慢速离心的峰值远低于向心，但转过的角度相同。
            var minTurn: Double?
            /// 短于该周期、且平均半程转角达到 armSwingTurn 的往返视为走路摆臂；近似平移的快速推举不受影响。
            static let armSwingPeriod: TimeInterval = 1.6
            static let armSwingTurn = 0.35

            /// 慢速大重量推举（约 2 秒推起、40 cm 行程）峰值仅约 0.06 g，门槛需低于该值。
            static let linear = Gate(channel: .linear, onset: 0.05, crossing: 0.035, periods: 0.7...6, minTurn: nil)
            /// 3 秒下放 130° 的弯举峰值约 1.1 rad/s；走路摆臂靠周期下限和转角门槛排除，
            /// 力量动作一次往返通常更慢。
            static let rotation = Gate(channel: .rotation, onset: 0.5, crossing: 0.25, periods: armSwingPeriod...6, minTurn: 1)
        }

        private struct Candidate {
            var axis: Vector
            var startedAt: TimeInterval
            var cycleStart: TimeInterval
            var transitionAt: TimeInterval
            var negative = false
            var positivePeak: Double
            var negativePeak = 0.0
            var positiveTurn = 0.0
            var negativeTurn = 0.0
            /// 本周期角速度大小的积分，不分方向。
            var turnPath = 0.0
            var projectedEnergy = 0.0
            var totalEnergy = 0.0
            var cycles = 0
            var previousPeriod: TimeInterval?
            var previousAmplitude: Double?
            var quietSince: TimeInterval?
        }

        private enum Phase {
            case searching
            case tracking(Candidate)
        }

        let gate: Gate
        private var phase = Phase.searching
        private var filtered = Vector.zero
        private var pendingNote: Note?
        /// 推举顶端锁定常停 1 秒以上，加上低于 crossing 的减速段约 1.5 秒；超过该时长才视为动作中断。
        private let quietLimit: TimeInterval = 2

        init(gate: Gate) { self.gate = gate }

        mutating func consume(_ value: Vector, rotationRate: Vector, at timestamp: TimeInterval, interval: TimeInterval) -> TimeInterval? {
            let alpha = min(interval, 0.04) / (0.08 + min(interval, 0.04))
            filtered = filtered.scaled(1 - alpha).adding(value.scaled(alpha))
            guard case .tracking(var candidate) = phase else {
                begin(at: timestamp)
                return nil
            }

            if filtered.length < gate.crossing {
                if candidate.quietSince == nil { candidate.quietSince = timestamp }
                if timestamp - (candidate.quietSince ?? timestamp) >= quietLimit {
                    noteDrop(.quiet)
                    phase = .searching
                    return nil
                }
            } else { candidate.quietSince = nil }
            let projected = filtered.dot(candidate.axis)
            candidate.projectedEnergy += projected * projected
            candidate.turnPath += rotationRate.length * interval
            candidate.totalEnergy += filtered.dot(filtered)
            guard timestamp - candidate.transitionAt <= 4,
                  timestamp - candidate.cycleStart <= 6 else {
                noteDrop(.timeout)
                begin(at: timestamp)
                return nil
            }

            if !candidate.negative {
                candidate.positivePeak = max(candidate.positivePeak, projected)
                candidate.positiveTurn += projected * interval
                if projected <= -gate.crossing {
                    guard timestamp - candidate.transitionAt >= 0.18 else {
                        noteDrop(.fastFlip); begin(at: timestamp); return nil
                    }
                    candidate.negative = true
                    candidate.transitionAt = timestamp
                    candidate.negativePeak = -projected
                }
            } else {
                candidate.negativePeak = max(candidate.negativePeak, -projected)
                candidate.negativeTurn -= projected * interval
                if projected >= gate.crossing {
                    let period = timestamp - candidate.cycleStart
                    let amplitude = candidate.positivePeak + candidate.negativePeak
                    let periodMatches = candidate.previousPeriod.map { (0.65...1.55).contains(period / $0) } ?? true
                    let amplitudeMatches = candidate.previousAmplitude.map { (0.5...2).contains(amplitude / $0) } ?? true
                    let rejection: Note.Reason? =
                        timestamp - candidate.transitionAt < 0.18 ? .fastFlip
                        : !gate.periods.contains(period) ? .periodOutOfRange
                        : gate.minTurn.map { min(candidate.positiveTurn, candidate.negativeTurn) < $0 } == true ? .smallTurn
                        : !isBalanced(candidate) ? .unbalanced
                        : candidate.positivePeak < gate.onset || candidate.negativePeak < gate.onset ? .weakPeak
                        : candidate.projectedEnergy < candidate.totalEnergy * 0.65 ? .offAxis
                        : !periodMatches ? .cadenceChanged
                        : !amplitudeMatches ? .amplitudeChanged
                        : gate.channel == .linear && period < Gate.armSwingPeriod
                            && candidate.turnPath / 2 >= Gate.armSwingTurn ? .armSwing : nil
                    let turns = gate.minTurn == nil ? nil : (candidate.positiveTurn, candidate.negativeTurn)
                    let note = Note(channel: gate.channel, kind: rejection == nil ? .cycle : .dropped,
                        cycles: candidate.cycles + (rejection == nil ? 1 : 0), reason: rejection, period: period,
                        positivePeak: candidate.positivePeak, negativePeak: candidate.negativePeak,
                        positiveTurn: turns?.0, negativeTurn: turns?.1)
                    // 首个周期就不成形多为随手动作，只在周期像一次重复时才记录，避免日志被噪声刷满。
                    if rejection == nil || candidate.cycles > 0 || gate.periods.contains(period) { pendingNote = note }
                    guard rejection == nil else { begin(at: timestamp); return nil }
                    candidate.cycles += 1
                    if candidate.cycles == 3 {
                        phase = .searching
                        return candidate.startedAt
                    }
                    candidate.previousPeriod = period
                    candidate.previousAmplitude = amplitude
                    candidate.cycleStart = timestamp
                    candidate.transitionAt = timestamp
                    candidate.negative = false
                    candidate.positivePeak = projected
                    candidate.negativePeak = 0
                    candidate.positiveTurn = 0
                    candidate.negativeTurn = 0
                    candidate.turnPath = 0
                    candidate.projectedEnergy = 0
                    candidate.totalEnergy = 0
                }
            }
            phase = .tracking(candidate)
            return nil
        }

        mutating func takeNote() -> Note? {
            defer { pendingNote = nil }
            return pendingNote
        }

        mutating func reset() {
            phase = .searching
            filtered = .zero
        }

        /// 已确认至少一个周期的候选被丢弃时才记录，单次抖动不进日志。
        mutating func noteDrop(_ reason: Note.Reason) {
            guard case .tracking(let candidate) = phase, candidate.cycles > 0 else { return }
            pendingNote = Note(channel: gate.channel, kind: .dropped, cycles: candidate.cycles, reason: reason)
        }

        private func isBalanced(_ candidate: Candidate) -> Bool {
            if let minTurn = gate.minTurn {
                return (0.6...1.67).contains(candidate.negativeTurn / max(candidate.positiveTurn, minTurn))
            }
            return (0.4...2.5).contains(candidate.negativePeak / max(candidate.positivePeak, gate.onset))
        }

        private mutating func begin(at timestamp: TimeInterval) {
            guard filtered.length >= gate.onset else { phase = .searching; return }
            phase = .tracking(Candidate(axis: filtered.scaled(1 / filtered.length),
                startedAt: timestamp, cycleStart: timestamp, transitionAt: timestamp, positivePeak: filtered.length))
        }
    }
}
