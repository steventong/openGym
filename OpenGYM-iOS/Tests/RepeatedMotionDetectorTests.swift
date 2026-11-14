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
            if let note = detector.takeNote() { notes.append(note) }
        }
        XCTAssertEqual(notes.map(\.kind), [.cycle, .cycle, .dropped])
        XCTAssertEqual(notes.map(\.cycles), [1, 2, 2])
        XCTAssertEqual(notes.last?.reason, .quiet)
        XCTAssertEqual(notes.first?.period ?? 0, 2, accuracy: 0.1)
        XCTAssertNil(detector.takeNote())
    }

    func testNoiseProducesNoNotes() {
        var detector = RepeatedMotionDetector()
        for i in 0..<500 {
            _ = detector.consume(sample(Double(i) / 25, i % 2 == 0 ? 0.03 : -0.03))
            XCTAssertNil(detector.takeNote())
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
}
