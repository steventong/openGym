import Foundation

/// 只判断连续往返运动，不识别具体健身动作；所有阈值和候选状态都留在这里。
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
    }

    private struct Candidate {
        var axis: Vector
        var startedAt: TimeInterval
        var cycleStart: TimeInterval
        var transitionAt: TimeInterval
        var negative = false
        var positivePeak: Double
        var negativePeak = 0.0
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
        case detected
    }

    private var phase = Phase.searching
    private var lastTimestamp: TimeInterval?
    private var filtered = Vector.zero
    private let onset = 0.10
    private let crossing = 0.06

    /// 确认三个完整周期后只返回一次整段运动的起点，而非确认时刻。
    mutating func consume(_ sample: Sample) -> TimeInterval? {
        guard sample.timestamp.isFinite, sample.acceleration.isFinite,
              sample.recordedAt.timeIntervalSince1970.isFinite else { reset(); return nil }
        if case .detected = phase { return nil }
        let interval = lastTimestamp.map { sample.timestamp - $0 } ?? 0.04
        guard interval > 0 else { reset(); return nil }
        if interval > 0.35 { reset() }
        lastTimestamp = sample.timestamp
        let alpha = min(interval, 0.04) / (0.08 + min(interval, 0.04))
        filtered = filtered.scaled(1 - alpha).adding(sample.acceleration.scaled(alpha))
        guard case .tracking(var candidate) = phase else {
            begin(at: sample.timestamp)
            return nil
        }

        if filtered.length < crossing {
            if candidate.quietSince == nil { candidate.quietSince = sample.timestamp }
            if sample.timestamp - (candidate.quietSince ?? sample.timestamp) >= 0.5 {
                phase = .searching
                return nil
            }
        } else { candidate.quietSince = nil }
        let projected = filtered.dot(candidate.axis)
        candidate.projectedEnergy += projected * projected
        candidate.totalEnergy += filtered.dot(filtered)
        guard sample.timestamp - candidate.transitionAt <= 4,
              sample.timestamp - candidate.cycleStart <= 6 else {
            begin(at: sample.timestamp)
            return nil
        }

        if !candidate.negative {
            candidate.positivePeak = max(candidate.positivePeak, projected)
            if projected <= -crossing {
                guard sample.timestamp - candidate.transitionAt >= 0.18 else {
                    begin(at: sample.timestamp); return nil
                }
                candidate.negative = true
                candidate.transitionAt = sample.timestamp
                candidate.negativePeak = -projected
            }
        } else {
            candidate.negativePeak = max(candidate.negativePeak, -projected)
            if projected >= crossing {
                let period = sample.timestamp - candidate.cycleStart
                let amplitude = candidate.positivePeak + candidate.negativePeak
                let balanced = candidate.negativePeak / max(candidate.positivePeak, onset)
                let periodMatches = candidate.previousPeriod.map { (0.65...1.55).contains(period / $0) } ?? true
                let amplitudeMatches = candidate.previousAmplitude.map { (0.5...2).contains(amplitude / $0) } ?? true
                guard sample.timestamp - candidate.transitionAt >= 0.18,
                      (0.7...6).contains(period), (0.4...2.5).contains(balanced),
                      candidate.positivePeak >= onset, candidate.negativePeak >= onset,
                      candidate.projectedEnergy >= candidate.totalEnergy * 0.65,
                      periodMatches, amplitudeMatches else {
                    begin(at: sample.timestamp); return nil
                }
                candidate.cycles += 1
                if candidate.cycles == 3 {
                    phase = .detected
                    return candidate.startedAt
                }
                candidate.previousPeriod = period
                candidate.previousAmplitude = amplitude
                candidate.cycleStart = sample.timestamp
                candidate.transitionAt = sample.timestamp
                candidate.negative = false
                candidate.positivePeak = projected
                candidate.negativePeak = 0
                candidate.projectedEnergy = 0
                candidate.totalEnergy = 0
            }
        }
        phase = .tracking(candidate)
        return nil
    }

    mutating func reset() {
        phase = .searching
        lastTimestamp = nil
        filtered = .zero
    }

    private mutating func begin(at timestamp: TimeInterval) {
        guard filtered.length >= onset else { phase = .searching; return }
        phase = .tracking(Candidate(axis: filtered.scaled(1 / filtered.length),
            startedAt: timestamp, cycleStart: timestamp, transitionAt: timestamp, positivePeak: filtered.length))
    }
}
