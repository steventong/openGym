import XCTest
import SwiftUI
import UIKit
import AVFoundation
@testable import OpenGym
@MainActor final class AdvancedTests:XCTestCase {
    func testVerticalPagingOnShortCardsAndListBoundaries() {
        func destination(_ y: CGFloat, selected: Int = 1, count: Int = 3) -> Int? {
            TrainingVerticalPaging.destination(geometry: pagingGeometry(y: y, height: 400),
                from: .interacting, to: .decelerating, selected: selected, count: count)
        }
        XCTAssertEqual(destination(-60), 0, "Pull down goes to the previous card")
        XCTAssertEqual(destination(60), 2, "Pull up goes to the next card even when content fits")
        XCTAssertNil(destination(-40), "A small bounce must not change cards")
        XCTAssertNil(destination(40))
        XCTAssertNil(destination(-80, selected: 0))
        XCTAssertNil(destination(80, selected: 2))
        XCTAssertNil(destination(80, selected: 0, count: 1))
        XCTAssertNil(destination(80, selected: 0, count: 0))
    }

    func testVerticalPagingKeepsLongCardsScrollableAndAccountsForInsets() {
        func destination(_ y: CGFloat) -> Int? {
            TrainingVerticalPaging.destination(geometry: pagingGeometry(y: y, height: 1200, top: 20, bottom: 30),
                from: .interacting, to: .idle, selected: 1, count: 3)
        }
        XCTAssertNil(destination(250), "Scrolling through training rows must not change cards")
        XCTAssertNil(destination(650), "A small bounce beyond the bottom is still scrolling")
        XCTAssertEqual(destination(690), 2)
        XCTAssertNil(destination(-60))
        XCTAssertEqual(destination(-80), 0)
    }

    func testVerticalPagingIgnoresMomentumSpringBackAndProgrammaticScrolls() {
        for phases: (ScrollPhase, ScrollPhase) in [(.decelerating, .idle), (.animating, .idle),
                                                   (.tracking, .interacting), (.idle, .tracking)] {
            for y: CGFloat in [-100, 100] {
                XCTAssertNil(TrainingVerticalPaging.destination(geometry: pagingGeometry(y: y, height: 400),
                    from: phases.0, to: phases.1, selected: 1, count: 3))
            }
        }
    }

    private func pagingGeometry(y: CGFloat, height: CGFloat, top: CGFloat = 0, bottom: CGFloat = 0) -> ScrollGeometry {
        ScrollGeometry(contentOffset: CGPoint(x: 0, y: y), contentSize: CGSize(width: 390, height: height),
            contentInsets: EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0),
            containerSize: CGSize(width: 390, height: 600))
    }

    func testLiveRowIdentitySurvivesEditingCopyRemovalUndoAndRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "row-identity", storage: storage)
        store.draft = try TrainingDraft.fromWeb(begin(state([["id": "0289", "sets": 3, "weight": 20]])), unit: "kg")
        func rowIDs(_ draft: TrainingDraft?) -> [String] {
            (draft?.rawEntries.first?["sets"] as? [[String: Any]] ?? []).compactMap { $0["nativeViewID"] as? String }
        }
        let original = rowIDs(store.draft)
        XCTAssertEqual(original.count, 3)
        XCTAssertEqual(Set(original).count, 3)
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "field", "key": "w", "value": 25]))
        XCTAssertEqual(rowIDs(store.draft), original)
        store.copyLiveSet(entry: 0, set: 0)
        let copied = rowIDs(store.draft)
        XCTAssertEqual(copied.count, 4)
        XCTAssertEqual(Set(copied).count, 4)
        XCTAssertEqual([copied[0], copied[2], copied[3]], original)
        store.removeLiveSet(entry: 0, set: 1)
        XCTAssertEqual(rowIDs(store.draft), original)
        store.undoSetRemoval()
        XCTAssertEqual(rowIDs(store.draft), copied)
        store.addLiveSet(entry: 0)
        XCTAssertEqual(Array(rowIDs(store.draft).prefix(4)), copied)
        XCTAssertEqual(Set(rowIDs(store.draft)).count, 5)
        let restored = GymStore(userID: "row-identity", storage: storage)
        restored.restoreDraft()
        XCTAssertEqual(rowIDs(restored.draft), rowIDs(store.draft))
        let cleaned = try JSONSerialization.data(withJSONObject: TrainingInput.clean(try XCTUnwrap(store.draft).activeJSON))
        XCTAssertFalse(String(decoding: cleaned, as: UTF8.self).contains("nativeViewID"))
    }

    func testLegacyDraftIdentityIsStableBeforeAndAfterFirstEdit() throws {
        let raw = begin(state([["id": "0289", "sets": 2]]))
        var draft = try TrainingDraft.fromWeb(raw, unit: "kg")
        // Simulate a persisted draft from before native identities existed.
        draft.webData = try JSONSerialization.data(withJSONObject: raw)
        let first = draft.activeJSON
        XCTAssertTrue(RecordPatch.equal(first, draft.activeJSON))
        var edited = first; edited["note"] = "keep rows"
        try draft.setActive(edited)
        XCTAssertTrue(RecordPatch.equal(first["entries"], draft.activeJSON["entries"]))
        var removed = raw
        var entries = raw["entries"] as! [[String: Any]]
        entries[0]["sets"] = Array((entries[0]["sets"] as! [[String: Any]]).dropFirst())
        removed["entries"] = entries
        removed["nativeSetUndo"] = ["entries": raw["entries"]!, "expected": entries]
        draft.webData = try JSONSerialization.data(withJSONObject: removed)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(userID: "legacy-undo", storage: LocalTrainingStorage(root: root))
        store.draft = draft
        store.undoSetRemoval()
        XCTAssertEqual((store.draft?.rawEntries.first?["sets"] as? [[String: Any]])?.count, 2)
        XCTAssertFalse(store.canUndoSetRemoval)
    }

    func testExerciseFieldsKeepTheirViewsWhenSiblingRowsChange() async throws {
        let store = GymStore()
        func view(_ ids: [String]) -> some View {
            let rows = ids.map { TrainingEditorRow(id: $0, raw: ["w": 20, "r": 8]) }
            let entry: [String: Any] = ["id": "0289", "sets": rows.map(\.raw)]
            return TrainingExerciseEditor(
                showingOptions: .constant(false), entries: [entry], names: ["卧推"], selected: .constant(0),
                rows: rows, unit: "kg", previous: "", note: .constant(""), identifier: "identity",
                showDetails: {}, addSet: {}, copySet: { _ in }, removeSet: { _ in }, editSet: { _, _ in }, exerciseActions: { EmptyView() }
            ) { EmptyView() }.environment(store)
        }
        let controller = UIHostingController(rootView: view(["a", "b", "c"]))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func fields(in view: UIView) -> [UITextField] {
            if let field = view as? UITextField { return [field] }
            return view.subviews.flatMap { fields(in: $0) }
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let original = fields(in: controller.view)
        XCTAssertEqual(original.count, 6)
        let first = try XCTUnwrap(original.first)
        let last = try XCTUnwrap(original.last)
        for ids in [["a", "c"], ["a", "new", "c"]] {
            controller.rootView = view(ids)
            _ = controller.sizeThatFits(in: window.bounds.size)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for _ in 0..<20 where fields(in: controller.view).count != ids.count * 2 {
                try await Task.sleep(for: .milliseconds(50))
                controller.view.layoutIfNeeded()
            }
            let current = fields(in: controller.view)
            XCTAssertEqual(current.count, ids.count * 2)
            XCTAssertTrue(current.first === first)
            XCTAssertTrue(current.last === last)
        }
    }

    func testHealthSamplesDoNotResizeReservedMetricsRow() {
        let reports: [HealthWorkoutReport?] = [nil,
            HealthWorkoutReport(id: "health", state: .running, activeCalories: 0),
            HealthWorkoutReport(id: "health", state: .running, activeCalories: 1200, heartRate: 180),
            HealthWorkoutReport(id: "health", state: .saved, activeCalories: 1200)]
        for width: CGFloat in [240, 350] {
            for textSize: DynamicTypeSize in [.large, .accessibility3] {
                let sizes = reports.map { report in
                    UIHostingController(rootView: WorkoutHealthMetricsContent(report: report)
                        .environment(\.dynamicTypeSize, textSize))
                        .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                }
                for size in sizes.dropFirst() {
                    XCTAssertEqual(size.height, sizes[0].height, accuracy: 0.5)
                    XCTAssertEqual(size.width, sizes[0].width, accuracy: 0.5)
                }
            }
        }
    }

    func testVideoLoopHandoffDoesNotRestoreLoadingIndicator() {
        let playback = LoopPlayback()
        playback.updateReadiness(.unknown)
        XCTAssertFalse(playback.ready)
        playback.updateReadiness(.readyToPlay)
        for _ in 0..<3 {
            playback.updateReadiness(.unknown)
            XCTAssertTrue(playback.ready)
            XCTAssertFalse(playback.failed)
            playback.updateReadiness(.readyToPlay)
        }
        playback.updateReadiness(.failed)
        XCTAssertTrue(playback.failed)
        XCTAssertFalse(playback.ready)
        playback.updateReadiness(.unknown)
        XCTAssertTrue(playback.failed)
        playback.updateReadiness(.readyToPlay)
        XCTAssertTrue(playback.ready)
        XCTAssertFalse(playback.failed)
    }
    let day = "2026-10-23"
    let now = 1_792_699_200_000.0
    func testRestCountdownDoesNotResizeExerciseCard() async throws {
        let store = GymStore()
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalogue", withExtension: "json"))
        store.registerCatalogue(try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: catalogue)))
        let row: [String: Any] = ["w": 20, "r": 8]
        let entry: [String: Any] = ["id": "0289", "sets": [row], "target": ["mode": "reps"]]
        let restStates: [Date?] = [nil, Date().addingTimeInterval(90), Date().addingTimeInterval(-10)]
        for width: CGFloat in [280, 350] {
            for textSize: DynamicTypeSize in [.large, .accessibility3] {
                var baseline: CGSize?
                for (index, restUntil) in restStates.enumerated() {
                    let view = TrainingExerciseEditor(
                        showingOptions: .constant(false), entries: [entry], names: ["哑铃卧推"], selected: .constant(0),
                        rows: [TrainingEditorRow(id: "0", raw: row)], unit: "kg", previous: "上次 20 kg × 8",
                        note: .constant(""), identifier: "layout-test", restUntil: restUntil,
                        startRest: { _, _ in }, showDetails: {}, addSet: {}, copySet: { _ in },
                        removeSet: { _ in }, editSet: { _, _ in }, exerciseActions: { EmptyView() }
                    ) { EmptyView() }
                        .environment(store).environment(\.dynamicTypeSize, textSize)
                        .preferredColorScheme(.dark).tint(GymTheme.green)
                        .frame(width: width).ignoresSafeArea()
                    let controller = UIHostingController(rootView: view)
                    let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                    if let baseline {
                        XCTAssertEqual(size.width, baseline.width, accuracy: 0.5)
                        XCTAssertEqual(size.height, baseline.height, accuracy: 0.5,
                                       "Rest state \(index) resized the card at width \(width), text size \(textSize)")
                    } else {
                        baseline = size
                    }
                    if width == 350 && textSize == .large {
                        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                        window.rootViewController = controller
                        window.makeKeyAndVisible()
                        controller.view.frame = window.bounds
                        controller.view.layoutIfNeeded()
                        try await Task.sleep(for: .milliseconds(250))
                        let image = UIGraphicsImageRenderer(size: size).image { _ in
                            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "rest-layout-\(index)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                        window.isHidden = true
                    }
                }
            }
        }
    }
    func state(_ configs:[[String:Any]])->[String:Any] { ["unit":"kg","restSec":90,"bodyweight":[],"workouts":[],"routines":[["id":"a","name":"A","excludeFromProgression":true,"ex":configs]],"week":[:],"dayPlan":[:]] }
    func begin(_ state:[String:Any],id:String = "test")->[String:Any] { try! WebRules.shared.call("beginAdvanced",payload:["state":state,"ids":["a"],"id":id,"now":now,"day":day]) as! [String:Any] }
    func testEmptyOrMissingPlanDoesNotSilentlyStartFreestyle() throws {
        for ids in [["a"], ["missing"]] {
            XCTAssertThrowsError(try WebRules.shared.call("beginAdvanced", payload: ["state": state([]), "ids": ids, "id": "test", "now": now, "day": day]))
        }
    }
    func testSideDropsMatchWebAndPartialSideCountsOnce() throws {
        let s = state([["id":"0150","sets":1,"reps":12,"weight":40,"side":true,"intensifier":["type":"dropset","count":2,"pct":20]]])
        var a = begin(s);var entries = a["entries"] as! [[String:Any]];var rows = entries[0]["sets"] as! [[String:Any]]
        let sides = rows[0]["sides"] as! [String:[String:Any]]
        XCTAssertEqual(number(sides["L"]?["r"]),6)
        XCTAssertEqual((sides["L"]?["drops"] as! [[String:Any]]).map{number($0["w"])},[30,25])
        rows[0] = try WebRules.shared.call("editAdvancedRow",payload:["row":rows[0],"action":"toggle","side":"L","now":now+10_000]) as! [String:Any]
        XCTAssertEqual(rows[0]["done"] as? Bool,false)
        entries[0]["sets"] = rows;a["entries"] = entries
        let next = try WebRules.shared.call("finishAdvanced",payload:["state":s,"active":a,"now":now+60_000,"today":day]) as! [String:Any]
        let work = (next["workouts"] as! [[String:Any]])[0]
        XCTAssertEqual(number(work["vol"]),570)
        XCTAssertEqual((work["entries"] as! [[String:Any]]).count,1)
    }
    func testRestPauseUsesWarmupAndTotalWithoutDoubleCounting() throws {
        let s = state([["id":"0150","sets":5,"reps":8,"weight":40,"intensifier":["type":"restpause","totalReps":12,"restSec":15]]])
        let a = begin(s);let e = (a["entries"] as! [[String:Any]])[0];let rows = e["sets"] as! [[String:Any]]
        XCTAssertEqual(rows.count,2);XCTAssertEqual(rows[0]["phase"] as? String,"warmup")
        XCTAssertEqual((rows[1]["clusters"] as! [[String:Any]]).reduce(0){$0+number($1["r"])},12)
        var active = a;var entry = e;entry["sets"] = rows.map { row -> [String:Any] in var r = row;r["done"] = true;return r };active["entries"] = [entry]
        let result = try WebRules.shared.call("finishAdvanced",payload:["state":s,"active":active,"now":now+60_000,"today":day]) as! [String:Any]
        XCTAssertEqual(number((result["workouts"] as! [[String:Any]])[0]["vol"]),480)
    }
    func testPyramidPerSideNormalizationAndTimedCardioShapes() throws {
        let normalized = try WebRules.shared.call("advancedConfig",payload:["config":["id":"0150","side":true,"pyramid":[11,"max",7],"pyramidWeight":[20,25,30],"intensifier":["type":"dropset"]]]) as! [String:Any]
        XCTAssertEqual((normalized["pyramid"] as! [Any]).map{String(describing:$0)},["12","max","8"]);XCTAssertNil(normalized["intensifier"])
        let a = begin(state([["id":"0150","mode":"time","sets":2,"sec":30,"side":true,"weight":0],["id":"3893","sets":1,"min":10,"speed":6]]))
        let entries = a["entries"] as! [[String:Any]],timed = entries[0]["sets"] as! [[String:Any]]
        XCTAssertEqual(timed.count,4);XCTAssertEqual(timed.map{$0["side"] as! String},["L","R","L","R"])
        XCTAssertEqual(number((entries[1]["sets"] as! [[String:Any]])[0]["min"]),10)
    }
    func testSupersetPairAndRestOnlyAtRoundBoundary() throws {
        let configs:[[String:Any]] = [["id":"0150","sets":2,"reps":8,"weight":20],["id":"0025","sets":2,"reps":8,"weight":30]]
        let grouped = try WebRules.shared.call("planGroup",payload:["rows":configs,"operation":"pair","index":0]) as! [[String:Any]]
        XCTAssertNotNil(grouped[0]["sg"]);XCTAssertEqual(grouped[0]["sg"] as? String,grouped[1]["sg"] as? String)
        let single = try WebRules.shared.call("planGroup",payload:["rows":[grouped[0]],"operation":"cleanup","index":0]) as! [[String:Any]]
        XCTAssertNil(single[0]["sg"])
        let s = state(grouped);var a = begin(s);var entries = a["entries"] as! [[String:Any]]
        var rows = entries[0]["sets"] as! [[String:Any]];rows[0]["done"] = true;entries[0]["sets"] = rows;a["entries"] = entries
        let first = try WebRules.shared.call("restForCompleted",payload:["active":a,"entry":0,"index":0,"state":s]) as! [String:Any]
        XCTAssertEqual(number(first["seconds"]),0);XCTAssertEqual(number(first["next"]),1)
        rows = entries[1]["sets"] as! [[String:Any]];rows[0]["done"] = true;entries[1]["sets"] = rows;a["entries"] = entries
        let second = try WebRules.shared.call("restForCompleted",payload:["active":a,"entry":1,"index":0,"state":s]) as! [String:Any]
        XCTAssertEqual(number(second["seconds"]),90)
    }
    func testRotationFinishingPassRefillsTomorrowAndSaveIsIdempotent() throws {
        var s = state([["id":"0150","sets":1,"reps":10,"weight":20]])
        s = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"save","ids":["a"],"label":"Loop","today":day,"now":now]) as! [String:Any]
        var a = begin(s);var entries = a["entries"] as! [[String:Any]];var rows = entries[0]["sets"] as! [[String:Any]];rows[0]["done"] = true;entries[0]["sets"] = rows;a["entries"] = entries
        let next = try WebRules.shared.call("finishAdvanced",payload:["state":s,"active":a,"now":now+60_000,"today":day]) as! [String:Any]
        XCTAssertEqual((next["queue"] as! [String:Any])["startsOn"] as? String,"2026-10-24")
        let repeated = try WebRules.shared.call("finishAdvanced",payload:["state":next,"active":a,"now":now+120_000,"today":day]) as! [String:Any]
        XCTAssertEqual((repeated["workouts"] as! [[String:Any]]).count,1)
        XCTAssertTrue(RecordPatch.equal(next["queue"],repeated["queue"]))
    }
    func testFixedWeekPreservesExternalQueueAndReorderPreservesProgress() throws {
        var s = state([]);s["routines"] = [["id":"a","name":"A","ex":[]],["id":"b","name":"B","ex":[]]]
        s["queue"] = ["ids":["a","b"],"since":now,"startsOn":day,"label":"Coach"]
        let fixed = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"week","today":day,"now":now]) as! [String:Any]
        XCTAssertTrue(RecordPatch.equal(fixed["queue"],s["queue"]))
        s = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"save","ids":["a","b"],"label":"Loop","today":day,"now":now]) as! [String:Any]
        s["workouts"] = [["id":"w","d":day,"start":now,"routineIds":["a"],"entries":[]]]
        let moved = try WebRules.shared.call("rotationChange",payload:["state":s,"action":"save","ids":["b","a"],"label":"Loop","today":day,"now":now+1000]) as! [String:Any]
        let info = try WebRules.shared.call("rotationInfo",payload:["state":moved,"today":day]) as! [String:Any]
        let items = (info["view"] as! [String:Any])["items"] as! [[String:Any]]
        XCTAssertEqual(items.first{$0["id"] as? String == "a"}?["state"] as? String,"done")
    }
    func testAdvancedDraftAndTimerSurviveEncoding() throws {
        var a = begin(state([["id":"0150","mode":"time","sec":3,"sets":1]]));a["nativeTimer"] = ["entry":0,"set":0,"end":1000,"paused":true,"remaining":2]
        let draft = try TrainingDraft.fromWeb(a,unit:"kg")
        let restored = try JSONDecoder().decode(TrainingDraft.self,from:JSONEncoder().encode(draft))
        XCTAssertTrue(RecordPatch.equal(restored.activeJSON,draft.activeJSON));XCTAssertEqual((restored.activeJSON["nativeTimer"] as? [String:Any])?["paused"] as? Bool,true)
    }
    func testHistoryClusterEditKeepsAggregateAndOriginalCompletionTime() throws {
        let row:[String:Any] = ["w":20,"r":12,"done":true,"at":1234,"type":"restpause","clusters":[["r":6,"restSec":15],["r":3,"restSec":15],["r":2,"restSec":15],["r":1,"restSec":15]]]
        let next = try WebRules.shared.call("editAdvancedRow",payload:["row":row,"action":"clusterEdit","index":0,"value":8,"editing":true]) as! [String:Any]
        XCTAssertEqual(number(next["r"]),14)
        let toggled = try WebRules.shared.call("editAdvancedRow",payload:["row":next,"action":"toggle","editing":true,"now":9999]) as! [String:Any]
        XCTAssertEqual(number(toggled["at"]),1234)
    }
    func testRestoredExpiredTimerLogsPlannedSecondsOnlyOnce() throws {
        var a = begin(state([["id":"0150","mode":"time","sec":30,"sets":1]]))
        let time = Date().timeIntervalSince1970
        a["nativeTimer"] = ["entry":0,"set":0,"start":time-150,"end":time-120,"planned":30,"remaining":30,"elapsed":0,"paused":false]
        let store = GymStore();store.draft = try TrainingDraft.fromWeb(a,unit:"kg")
        store.settleTimer();store.settleTimer()
        let row = (store.draft!.rawEntries[0]["sets"] as! [[String:Any]])[0]
        XCTAssertEqual(row["done"] as? Bool,true);XCTAssertEqual(number(row["sec"]),30);XCTAssertNil(store.workTimer)
    }
    func testCompletedExerciseWaitsForExplicitNavigationEvenBeforeWarmup() throws {
        let s = state([["id":"0150","sets":1,"reps":8,"weight":20], ["id":"0025","sets":1,"reps":8,"weight":30]])
        var active = begin(s)
        var entries = active["entries"] as! [[String:Any]]
        entries[0]["sets"] = [["w":20,"r":8,"done":false]]
        entries[1]["sets"] = [["w":10,"r":8,"done":false,"phase":"warmup"], ["w":30,"r":8,"done":false]]
        active["entries"] = entries; active["cur"] = 0
        let store = GymStore(); store.state = s; store.draft = try TrainingDraft.fromWeb(active,unit:"kg")
        store.liveRowAction(entry:0,set:0,action:["action":"toggle"])
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int,0)
        XCTAssertNil(store.restUntil)
        XCTAssertEqual((store.draft?.rawEntries[0]["sets"] as? [[String:Any]])?[0]["done"] as? Bool,true)
        store.selectLiveEntry(1)
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int,1)
    }
    func testIncompleteSupersetStillAdvancesToPartner() throws {
        let configs:[[String:Any]] = [["id":"0150","sets":2,"reps":8,"weight":20], ["id":"0025","sets":2,"reps":8,"weight":30]]
        let grouped = try WebRules.shared.call("planGroup",payload:["rows":configs,"operation":"pair","index":0]) as! [[String:Any]]
        let s = state(grouped)
        let store = GymStore(); store.state = s; store.draft = try TrainingDraft.fromWeb(begin(s),unit:"kg")
        store.liveRowAction(entry:0,set:0,action:["action":"toggle"])
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int,1)
        XCTAssertNil(store.restUntil)
    }
    func testFinalSetClearsRestEvenWithAnotherExerciseRemaining() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let s = state([["id": "0150", "sets": 2, "reps": 8, "weight": 20],
                       ["id": "0025", "sets": 2, "reps": 8, "weight": 30]])
        let store = GymStore(userID: "rest-completion", storage: LocalTrainingStorage(root: root))
        store.state = s
        store.draft = try TrainingDraft.fromWeb(begin(s), unit: "kg")
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"]))
        XCTAssertNotNil(store.restUntil)
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "toggle"]))
        XCTAssertNil(store.restUntil)
        XCTAssertNil(store.watchSnapshot().restEnd)
        XCTAssertEqual(store.draft?.activeJSON["cur"] as? Int, 0)

        // Rechecking the final set must also clear an existing timer instead of preserving it.
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "toggle"]))
        store.startRest(entry: 0, seconds: 90)
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "toggle"]))
        XCTAssertNil(store.restUntil)
        let restored = GymStore(userID: "rest-completion", storage: LocalTrainingStorage(root: root))
        restored.restoreDraft()
        XCTAssertNil(restored.restUntil)
    }
    func testSupersetRestsBetweenRoundsButNotAfterFinalRound() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configs: [[String: Any]] = [["id": "0150", "sets": 2, "reps": 8, "weight": 20],
                                       ["id": "0025", "sets": 2, "reps": 8, "weight": 30],
                                       ["id": "0289", "sets": 2, "reps": 8, "weight": 10]]
        let grouped = try WebRules.shared.call("planGroup", payload: ["rows": configs, "operation": "pair", "index": 0]) as! [[String: Any]]
        let s = state(grouped)
        let store = GymStore(userID: "superset-rest-completion", storage: LocalTrainingStorage(root: root))
        store.state = s
        store.draft = try TrainingDraft.fromWeb(begin(s), unit: "kg")
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"]))
        XCTAssertNil(store.restUntil)
        XCTAssertTrue(store.liveRowAction(entry: 1, set: 0, action: ["action": "toggle"]))
        XCTAssertNotNil(store.restUntil)
        XCTAssertTrue(store.liveRowAction(entry: 0, set: 1, action: ["action": "toggle"]))
        XCTAssertNil(store.restUntil)
        XCTAssertTrue(store.liveRowAction(entry: 1, set: 1, action: ["action": "toggle"]))
        XCTAssertNil(store.restUntil)
    }
}

extension AdvancedTests {
    func testInclineControlsFollowExerciseAndKeepExistingGradesEditable() throws {
        for (id, expected) in [("2259", true), ("3893", false)] {
            let info = try WebRules.shared.call("rowInfo", payload: ["row": ["mode": "cardio"], "target": ["id": id]]) as! [String: Any]
            XCTAssertEqual(info["incline"] as? Bool, expected)
        }
        let existing = try WebRules.shared.call("rowInfo", payload: ["row": ["mode": "cardio", "incline": 3], "target": ["id": "3893"]]) as! [String: Any]
        XCTAssertEqual(existing["incline"] as? Bool, true)
    }
    func testInputSteppersRespectEquipmentSidesAndDisplayUnits() throws {
        let state: [String: Any] = ["unit": "kg", "dumbbells": ["kg": ["weights": [9, 11, 13]]]]
        XCTAssertEqual(TrainingInput.steppedText("9", path: "both.w", direction: 1, target: ["id": "0289"], state: state, unit: "kg"), "11")
        XCTAssertEqual(TrainingInput.steppedText("8", path: "L.r", direction: 1, target: ["side": true], state: state, unit: "kg"), "9")
        XCTAssertEqual(TrainingInput.steppedText("8", path: "both.r", direction: 1, target: ["side": true], state: state, unit: "kg"), "10")
        XCTAssertEqual(TrainingInput.steppedText("10", path: "both.w", direction: 1, target: ["inc": 0.45359237], state: state, unit: "lb"), "11")
        XCTAssertEqual(TrainingInput.steppedText("0", path: "both.w", direction: -1, target: [:], state: state, unit: "kg"), "0")
        XCTAssertNil(TrainingInput.steppedText("", path: "both.w", direction: 1, target: [:], state: state, unit: "kg"))
    }
    func testSpeedInputConvertsMphAndHonorsIndependentPreference() throws {
        let imperial: [String: Any] = ["unit": "lb"]
        let action: [String: Any] = ["action": "input", "path": "both.speed", "text": "6", "operation": ["action": "field", "key": "speed"]]
        let row = try TrainingInput.edit(row: ["mode": "cardio", "min": 20], action: action, target: [:], state: imperial, editing: false)
        XCTAssertEqual(number(row["speed"]), 9.66, accuracy: 0.001)
        XCTAssertEqual(TrainingInput.speedDisplay(number(row["speed"]), state: imperial), 6)
        let metric = try TrainingInput.edit(row: row, action: action, target: [:], state: ["unit": "lb", "speedUnit": "kmh"], editing: false)
        XCTAssertEqual(number(metric["speed"]), 6)
        XCTAssertEqual(TrainingInput.speedUnit(["unit": "kg", "speedUnit": "mph"]), "mph")
    }
    func testInclineCanBeEditedClearedAndInvalidInputIsPreserved() throws {
        func edit(_ row: [String: Any], _ text: String) throws -> [String: Any] {
            try TrainingInput.edit(row: row, action: ["action": "input", "path": "both.incline", "text": text, "operation": ["action": "field", "key": "incline"]], target: [:], state: [:], editing: false)
        }
        let row = try edit(["mode": "cardio", "min": 20, "speed": 6], "4.5")
        XCTAssertEqual(number(row["incline"]), 4.5)
        let invalid = try edit(row, "100")
        XCTAssertEqual(number(invalid["incline"]), 4.5)
        XCTAssertThrowsError(try TrainingInput.validate(invalid))
        let cleared = try edit(invalid, "")
        XCTAssertNil(cleared["incline"])
        XCTAssertNoThrow(try TrainingInput.validate(cleared))
    }
    func testCopySelectedPairPreservesNeighborsAndClearsCopiedInput() throws {
        let sets: [[String: Any]] = [
            ["side": "L", "sec": 30, "done": true, "at": 1000, TrainingInput.key: ["both.sec": "30."]],
            ["side": "R", "sec": 40, "done": true],
            ["w": 20, "r": 8, "done": true, TrainingInput.key: ["both.w": "20."]]
        ]
        let result = try WebRules.shared.call("copySelectedSet", payload: ["sets": sets, "index": 1]) as! [String: Any]
        let copied = result["sets"] as! [[String: Any]]
        XCTAssertEqual(copied.count, 5); XCTAssertEqual(result["at"] as? Int, 2)
        XCTAssertTrue(RecordPatch.equal(copied[0], sets[0])); XCTAssertTrue(RecordPatch.equal(copied[4], sets[2]))
        XCTAssertEqual(copied[2]["side"] as? String, "L"); XCTAssertEqual(copied[3]["side"] as? String, "R")
        XCTAssertEqual(copied[2]["done"] as? Bool, false); XCTAssertNil(copied[2]["at"]); XCTAssertNil(copied[2][TrainingInput.key])
        var form = HistoryEntryDraft(["id": "0289", "sets": sets])
        let oldID = form.sets[2].id
        try form.copySet(at: 1)
        XCTAssertEqual(form.sets[4].id, oldID); XCTAssertEqual(form.sets[2].raw["done"] as? Bool, true)
    }
    func testCopyAndRestChangesPersistAndPreserveTimerOwnership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "input-parity", storage: storage)
        store.draft = try TrainingDraft.fromWeb(begin(state([["id": "0289", "sets": 3, "reps": 8, "weight": 20]])), unit: "kg")
        store.startRest(entry: 0, seconds: 90, set: 2)
        let end = try XCTUnwrap(store.restUntil)
        store.copyLiveSet(entry: 0, set: 0)
        XCTAssertEqual((store.draft?.activeJSON["nativeRest"] as? [String: Any])?["set"] as? Int, 3)
        store.adjustRest(by: 15)
        XCTAssertEqual(try XCTUnwrap(store.restUntil).timeIntervalSince(end), 15, accuracy: 0.1)
        store.changeActive { $0["name"] = "New name"; $0["note"] = "keep this note" }
        let restored = GymStore(userID: "input-parity", storage: storage); restored.restoreDraft()
        XCTAssertEqual(restored.draft?.name, "New name")
        XCTAssertEqual(restored.draft?.activeJSON["note"] as? String, "keep this note")
        XCTAssertEqual((restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.count, 4)
        restored.startExerciseRest(entry: 0, seconds: 120)
        XCTAssertEqual((restored.draft?.rawEntries[0]["target"] as? [String: Any])?["restSec"] as? Int, 120)
        restored.adjustRest(by: -200)
        XCTAssertNil(restored.restUntil)
    }
    func testCopyRejectsIncompleteOtherSideOfTimedPair() throws {
        var form = HistoryEntryDraft(["id": "0289", "sets": [["side": "L", "sec": 30], ["side": "R", "sec": 30, TrainingInput.key: ["both.sec": ""]]]])
        XCTAssertThrowsError(try form.copySet(at: 0))
        XCTAssertEqual(form.sets.count, 2)
    }
    func testLiveSupersetControlsPreserveSets() throws {
        let original = begin(state([["id": "0289", "sets": 2, "weight": 20], ["id": "1047", "sets": 2, "weight": 10]]))
        let paired = try WebRules.shared.call("manageTrainingExercises", payload: ["active": original, "action": "pair", "index": 1, "direction": -1]) as! [String: Any]
        let entries = paired["entries"] as! [[String: Any]]
        XCTAssertNotNil(entries[0]["sg"]); XCTAssertEqual(entries[0]["sg"] as? String, entries[1]["sg"] as? String)
        XCTAssertTrue(RecordPatch.equal(entries[0]["sets"], (original["entries"] as! [[String: Any]])[0]["sets"]))
        let unpaired = try WebRules.shared.call("manageTrainingExercises", payload: ["active": paired, "action": "unpair", "index": 0]) as! [String: Any]
        XCTAssertTrue((unpaired["entries"] as! [[String: Any]]).allSatisfy { $0["sg"] == nil })
    }
}


extension AdvancedTests {
    func testLivePendingWeightFlushesBeforeCopyAndSurvivesRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "buffered-live", storage: storage)
        store.draft = try TrainingDraft.fromWeb(begin(state([["id": "0289", "sets": 2, "weight": 20]])), unit: "kg")
        let field = UUID()
        for text in ["4", "42", "42.", "42.5"] {
            store.liveInputBuffer.stage(field) {
                XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.w", "text": text, "operation": ["action": "field", "key": "w"]]))
            }
        }
        let before = GymStore(userID: "buffered-live", storage: storage)
        before.restoreDraft()
        XCTAssertEqual(number((before.draft?.rawEntries[0]["sets"] as? [[String: Any]])?[0]["w"]), 20)
        store.copyLiveSet(entry: 0, set: 0)
        let restored = GymStore(userID: "buffered-live", storage: storage)
        restored.restoreDraft()
        let rows = try XCTUnwrap(restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { number($0["w"]) }, [42.5, 42.5, 42.5])
        XCTAssertFalse(store.liveInputBuffer.hasPending)
    }

    func testLivePendingInvalidInputBlocksCompletionAndBackgroundSaveKeepsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalTrainingStorage(root: root)
        let store = GymStore(userID: "buffered-invalid", storage: storage)
        store.draft = try TrainingDraft.fromWeb(begin(state([["id": "0289", "sets": 1, "weight": 20]])), unit: "kg")
        store.liveInputBuffer.stage(UUID()) {
            XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.w", "text": "", "operation": ["action": "field", "key": "w"]]))
        }
        XCTAssertFalse(store.liveRowAction(entry: 0, set: 0, action: ["action": "toggle"]))
        XCTAssertEqual(store.draft?.completedSets, 0)
        store.liveInputBuffer.stage(UUID()) { store.setLiveNote(entry: 0, text: "最后输入") }
        XCTAssertTrue(store.persistDraft())
        let restored = GymStore(userID: "buffered-invalid", storage: storage)
        restored.restoreDraft()
        XCTAssertEqual(restored.draft?.rawEntries[0]["note"] as? String, "最后输入")
        let row = try XCTUnwrap((restored.draft?.rawEntries[0]["sets"] as? [[String: Any]])?.first)
        XCTAssertEqual((row[TrainingInput.key] as? [String: String])?["both.w"], "")
        XCTAssertThrowsError(try TrainingInput.validate(row))
    }

    func testLiveTimerUsesPendingDurationBeforeStarting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(userID: "buffered-timer", storage: LocalTrainingStorage(root: root))
        store.draft = try TrainingDraft.fromWeb(begin(state([["id": "0289", "mode": "time", "sets": 1, "sec": 30]])), unit: "kg")
        store.liveInputBuffer.stage(UUID()) {
            XCTAssertTrue(store.liveRowAction(entry: 0, set: 0, action: ["action": "input", "path": "both.sec", "text": "75", "operation": ["action": "field", "key": "sec"]]))
        }
        store.startWorkTimer(entry: 0, set: 0)
        XCTAssertEqual(number(store.workTimer?["planned"]), 75)
    }
}


extension AdvancedTests {
    func testReplacingLiveSessionCannotApplyOldPendingInputToNewSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GymStore(userID: "buffered-replacement", storage: LocalTrainingStorage(root: root))
        let source = state([["id": "0289", "sets": 1]])
        store.draft = try TrainingDraft.fromWeb(begin(source, id: "first"), unit: "kg")
        var cancelled = false
        store.liveInputBuffer.stage(UUID(), cancel: { cancelled = true }) {
            store.changeActive { $0["name"] = "old pending title" }
        }
        store.draft = try TrainingDraft.fromWeb(begin(source, id: "second"), unit: "kg")
        store.liveInputBuffer.commitAll()
        XCTAssertTrue(cancelled)
        XCTAssertEqual(store.draft?.id, "second")
        XCTAssertEqual(store.draft?.name, "A")
    }
}
