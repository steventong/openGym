import XCTest
@testable import OpenGYM

final class RepeatedMotionDetectorTests: XCTestCase {
    private func sample(_ time: Double, _ value: Double, axis: RepeatedMotionDetector.Vector = .init(x: 1, y: 0, z: 0)) -> RepeatedMotionDetector.Sample {
        .init(timestamp: time, recordedAt: Date(timeIntervalSince1970: time), acceleration: axis.scaled(value))
    }

    private func wave(start: Double = 100, duration: Double = 8, period: Double = 2,
                      axis: RepeatedMotionDetector.Vector = .init(x: 1, y: 0, z: 0)) -> [RepeatedMotionDetector.Sample] {
        (0...Int(duration * 25)).map { index in
            let t = Double(index) / 25
            return sample(start + t, 0.4 * sin(2 * .pi * t / period), axis: axis)
        }
    }

    func testThreeFullCyclesReturnFirstMotionRatherThanConfirmationAndOnlyOnce() throws {
        var detector = RepeatedMotionDetector()
        let samples = wave()
        var results: [(TimeInterval, TimeInterval)] = []
        for sample in samples {
            if let onset = detector.consume(sample) { results.append((onset, sample.timestamp)) }
        }
        XCTAssertEqual(results.count, 1)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.0, 100.12, accuracy: 0.001)
        XCTAssertGreaterThan(result.1 - result.0, 5.5)
        XCTAssertLessThan(result.1 - result.0, 6.5)
    }

    func testDifferentAxesAndCadences() {
        for axis in [RepeatedMotionDetector.Vector(x: 0, y: -1, z: 0), .init(x: 0.6, y: 0, z: 0.8)] {
            for period in [1.0, 2.0, 4.0] {
                var detector = RepeatedMotionDetector()
                let results = wave(duration: period * 4, period: period, axis: axis).compactMap { detector.consume($0) }
                XCTAssertEqual(results.count, 1, "axis=\(axis), period=\(period)")
                XCTAssertLessThan((results.first ?? .infinity) - 100, 0.5)
            }
        }
    }

    /// 慢速推举：2 秒推起、顶端停 1.2 秒、2 秒下放、底部停 0.3 秒，行程 40 cm，峰值约 0.064 g。
    private func slowPress(start: Double = 100, reps: Int = 4, up: Double = 2, down: Double = 2,
                           topPause: Double = 1.2) -> [RepeatedMotionDetector.Sample] {
        let bottomPause = 0.3
        let peak = 0.4 * 2 * .pi / (up * up) / 9.81
        let rep = up + topPause + down + bottomPause
        return (0...Int(Double(reps) * rep * 25)).map { index in
            let t = Double(index) / 25
            let phase = t.truncatingRemainder(dividingBy: rep)
            var value = 0.0
            if phase < up { value = peak * sin(2 * .pi * phase / up) }
            else if phase >= up + topPause, phase < up + topPause + down {
                value = -peak * sin(2 * .pi * (phase - up - topPause) / down)
            }
            return sample(start + t, value, axis: .init(x: 0.3, y: 0, z: 0.95))
        }
    }

    func testSlowPressWithLockoutPauseConfirmsFromFirstRep() throws {
        var detector = RepeatedMotionDetector()
        let results = slowPress().compactMap { detector.consume($0) }
        XCTAssertEqual(results.count, 1)
        XCTAssertLessThan(try XCTUnwrap(results.first) - 100, 1)
    }

    /// 周期仍在允许范围内，只有停顿超过静止上限，用来单独验证静止判定。
    func testPauseLongerThanQuietLimitRestartsSequence() {
        var detector = RepeatedMotionDetector()
        XCTAssertTrue(slowPress(up: 1.2, down: 1.2, topPause: 2.2).compactMap { detector.consume($0) }.isEmpty)
    }

    func testNotesReportCycleProgressAndQuietDrop() {
        var detector = RepeatedMotionDetector()
        var notes: [RepeatedMotionDetector.Note] = []
        let samples = wave(duration: 4.5) + (1...75).map { sample(104.5 + Double($0) / 25, 0) }
        for item in samples {
            XCTAssertNil(detector.consume(item))
            notes += detector.takeNotes()
        }
        XCTAssertEqual(notes.map(\.kind), [.cycle, .cycle, .dropped])
        XCTAssertEqual(notes.map(\.cycles), [1, 2, 2])
        XCTAssertEqual(notes.last?.reason, .quiet)
        XCTAssertEqual(notes.first?.period ?? 0, 2, accuracy: 0.1)
        XCTAssertEqual(notes.map(\.channel), [.linear, .linear, .linear])
        XCTAssertTrue(detector.takeNotes().isEmpty)
    }

    func testNoiseProducesNoNotes() {
        var detector = RepeatedMotionDetector()
        for i in 0..<500 {
            _ = detector.consume(sample(Double(i) / 25, i % 2 == 0 ? 0.03 : -0.03))
            XCTAssertTrue(detector.takeNotes().isEmpty)
        }
    }

    func testNoiseSingleWristRaiseAndTwoCyclesNeverConfirm() {
        var detector = RepeatedMotionDetector()
        for i in 0..<2500 {
            XCTAssertNil(detector.consume(sample(Double(i) / 25, i % 2 == 0 ? 0.03 : -0.03)))
        }
        detector.reset()
        for item in wave(duration: 2.5) { XCTAssertNil(detector.consume(item)) }
        for i in 0..<100 { XCTAssertNil(detector.consume(sample(103 + Double(i) / 25, 0))) }
        detector.reset()
        for item in wave(duration: 5.8) { XCTAssertNil(detector.consume(item)) }
    }

    func testStillnessDiscardsEarlierIsolatedMovement() throws {
        var detector = RepeatedMotionDetector()
        for item in wave(duration: 0.8) { XCTAssertNil(detector.consume(item)) }
        for i in 0..<50 { XCTAssertNil(detector.consume(sample(100.84 + Double(i) / 25, 0))) }
        let results = wave(start: 103).compactMap { detector.consume($0) }
        XCTAssertEqual(try XCTUnwrap(results.first), 103.12, accuracy: 0.001)
    }

    func testSamplingGapAndInvalidSamplesCannotBridgeCandidates() throws {
        for invalid in [sample(102, .nan), sample(102, .infinity), sample(.nan, 0.4), sample(101, 0.4)] {
            var detector = RepeatedMotionDetector()
            for item in wave(duration: 3) { XCTAssertNil(detector.consume(item)) }
            XCTAssertNil(detector.consume(invalid))
            let results = wave(start: 110).compactMap { detector.consume($0) }
            XCTAssertEqual(try XCTUnwrap(results.first), 110.12, accuracy: 0.001)
        }
        var detector = RepeatedMotionDetector()
        for item in wave(duration: 3) { XCTAssertNil(detector.consume(item)) }
        for item in wave(start: 105, duration: 5.8) { XCTAssertNil(detector.consume(item)) }
    }

    func testAbruptCadenceChangeDropsOriginalStart() throws {
        var detector = RepeatedMotionDetector()
        for item in wave(duration: 4) { XCTAssertNil(detector.consume(item)) }
        let results = wave(start: 104.04, duration: 5, period: 1).compactMap { detector.consume($0) }
        XCTAssertEqual(results.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(results.first), 104)
    }

    func testAmplitudeMismatchDropsOriginalStartAndResetAllowsNewSequence() throws {
        var detector = RepeatedMotionDetector()
        for item in wave(duration: 4) { XCTAssertNil(detector.consume(item)) }
        let results = wave(start: 104.04, duration: 10).compactMap { item -> TimeInterval? in
            var amplified = item
            amplified.acceleration = item.acceleration.scaled(4)
            return detector.consume(amplified)
        }
        XCTAssertGreaterThan(try XCTUnwrap(results.first), 104)
        detector.reset()
        XCTAssertEqual(wave(start: 200).compactMap { detector.consume($0) }.count, 1)
    }

    /// 前臂绕肘转动：手腕沿半径 33 cm 的圆弧运动，加速度方向随弧线转动，角速度沿固定的肘关节轴。
    private func arc(start: Double = 100, duration: Double = 14, radius: Double = 0.33,
                     angle: @escaping (Double) -> Double) -> [RepeatedMotionDetector.Sample] {
        let h = 0.04
        func position(_ t: Double) -> (Double, Double) { (radius * sin(angle(t)), -radius * cos(angle(t))) }
        return (0...Int(duration * 25)).map { index in
            let t = Double(index) / 25
            let (x0, z0) = position(t - h), (x1, z1) = position(t), (x2, z2) = position(t + h)
            let rate = (angle(t + h) - angle(t - h)) / (2 * h)
            return .init(timestamp: start + t, recordedAt: Date(timeIntervalSince1970: start + t),
                acceleration: .init(x: (x2 - 2 * x1 + x0) / (h * h) / 9.81, y: 0, z: (z2 - 2 * z1 + z0) / (h * h) / 9.81),
                rotationRate: .init(x: 0.1 * rate, y: rate, z: 0))
        }
    }

    /// 平滑的单次往返：上举、顶端停、下放、底部停。
    private func reps(up: Double, top: Double, down: Double, bottom: Double, range: Double) -> (Double) -> Double {
        { t in
            func ease(_ u: Double) -> Double { let c = min(max(u, 0), 1); return c * c * (3 - 2 * c) }
            let x = max(t, 0).truncatingRemainder(dividingBy: up + top + down + bottom)
            if x < up { return range * ease(x / up) }
            if x < up + top { return range }
            return range * (1 - ease((x - up - top) / down))
        }
    }

    func testCurlArcConfirmsThroughRotationWhileLinearRejectsIt() throws {
        for (up, down) in [(1.0, 1.5), (0.8, 1.0), (1.0, 3.0)] {
            var detector = RepeatedMotionDetector()
            var notes: [RepeatedMotionDetector.Note] = []
            var results: [TimeInterval] = []
            for item in arc(angle: reps(up: up, top: 0.3, down: down, bottom: 0.3, range: 2.3)) {
                if let onset = detector.consume(item) { results.append(onset) }
                notes += detector.takeNotes()
            }
            XCTAssertEqual(results.count, 1, "up=\(up) down=\(down)")
            XCTAssertLessThan(try XCTUnwrap(results.first) - 100, 0.5)
            XCTAssertEqual(notes.filter { $0.kind == .cycle }.map(\.channel), [.rotation, .rotation, .rotation])
            XCTAssertTrue(notes.contains { $0.channel == .linear && $0.reason == .offAxis })
            let turn = try XCTUnwrap(notes.first { $0.kind == .cycle }?.positiveTurn)
            XCTAssertEqual(turn, 2.3, accuracy: 0.15)
        }
    }

    func testRotationRejectsArmSwingCadenceSmallTurnsAndSingleWristRaise() {
        let swing: (Double) -> Double = { 0.45 * sin(2 * .pi * $0 / 1.1) }
        let smallTurns = reps(up: 1, top: 0.3, down: 1.2, bottom: 0.3, range: 0.7)
        let raise: (Double) -> Double = { t in t < 1 ? 1.5 * t : t < 4 ? 1.5 : max(0, 1.5 * (5 - t)) }
        for angle in [swing, smallTurns, raise] {
            var detector = RepeatedMotionDetector()
            for item in arc(radius: 0, angle: angle) {
                XCTAssertNil(detector.consume(item))
                XCTAssertFalse(detector.takeNotes().contains { $0.channel == .rotation && $0.kind == .cycle })
            }
        }
    }

    func testWalkingArmSwingNeverConfirmsOnEitherChannel() {
        for period in [1.0, 1.1, 1.2, 1.3, 1.5] {
            for amplitude in [0.35, 0.5, 0.7] {
                var detector = RepeatedMotionDetector()
                let items = arc(duration: 30, radius: 0.6) { amplitude * sin(2 * .pi * $0 / period) }
                XCTAssertTrue(items.compactMap { detector.consume($0) }.isEmpty, "period=\(period) amplitude=\(amplitude)")
            }
        }
    }

    /// 快速推举前臂只有轻微晃动，不能被当成摆臂。
    func testFastPressWithSlightForearmTurnStillConfirms() {
        for period in [1.0, 1.2, 1.5] {
            var detector = RepeatedMotionDetector()
            let results = wave(duration: 8, period: period).compactMap { item -> TimeInterval? in
                var item = item
                item.rotationRate = .init(x: 0, y: 0.1 * 2 * .pi / period * cos(2 * .pi * (item.timestamp - 100) / period), z: 0)
                return detector.consume(item)
            }
            XCTAssertEqual(results.count, 1, "period=\(period)")
        }
    }
}
