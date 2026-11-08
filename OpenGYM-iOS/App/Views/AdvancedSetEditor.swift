import SwiftUI

/// The same controls edit a live set and a saved set; writes go through the web's row functions.
struct AdvancedSetEditor:View {
    let row:[String:Any]
    let target:[String:Any]
    let unit:String
    var inputState: [String: Any] = [:]
    var identifier = "set"
    var setLabel = ""
    var copySet: (() -> Void)?
    var removeSet: (() -> Void)?
    var readOnly = false
    var timerRunning = false
    var startTimer:(()->Void)? = nil
    var startRest:((Double)->Void)? = nil
    let action:([String:Any])->Void
    @State private var effortVisible = false
    @ScaledMetric(relativeTo: .body) private var inputHeight = 44
    private var sides:[String:[String:Any]]? { row["sides"] as? [String:[String:Any]] }
    private var mode:String { ((try? WebRules.shared.call("rowInfo",payload:["row":row,"target":target])) as? [String:Any])?["mode"] as? String ?? "reps" }
    private var warmup:Bool { ["warmup","warm-up","warm_up"].contains(row["phase"] as? String ?? "") || (row["phase"] == nil && row["warmup"] as? Bool == true) }
    private var compact: Bool { mode == "reps" && sides == nil }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if !compact { HStack(spacing:8) {
                Text(setLabel).font(.caption).foregroundStyle(GymTheme.muted)
                if warmup { Text("WARM_UP").font(.caption).foregroundStyle(.orange) }
                if row["max"] as? Bool == true { Text("MAX").font(.caption).foregroundStyle(GymTheme.green) }
                if let side = row["side"] as? String { Text(LocalizedStringKey(side == "L" ? "LEFT" : "RIGHT")).font(.caption).foregroundStyle(GymTheme.green) }
                if row["type"] as? String == "dropset" { Text("DROP_SET").font(.caption).foregroundStyle(GymTheme.green) }
                if row["type"] as? String == "restpause" { Text("REST_PAUSE").font(.caption).foregroundStyle(GymTheme.green) }
                Spacer()
                if !readOnly { AdvancedSetMenu(row: row, target: target, mode: mode, warmup: warmup, identifier: identifier, setLabel: setLabel, copySet: copySet, removeSet: removeSet, timerRunning: timerRunning, effortVisible: $effortVisible, action: action) }
            } }
            if sides != nil { AdvancedSetPane(row: row, target: target, unit: unit, inputState: inputState, identifier: identifier, setLabel: setLabel, copySet: copySet, removeSet: removeSet, readOnly: readOnly, timerRunning: timerRunning, inputHeight: inputHeight, side: "L", effortVisible: $effortVisible, startRest: startRest, action: action);Divider();AdvancedSetPane(row: row, target: target, unit: unit, inputState: inputState, identifier: identifier, setLabel: setLabel, copySet: copySet, removeSet: removeSet, readOnly: readOnly, timerRunning: timerRunning, inputHeight: inputHeight, side: "R", effortVisible: $effortVisible, startRest: startRest, action: action) } else { AdvancedSetPane(row: row, target: target, unit: unit, inputState: inputState, identifier: identifier, setLabel: setLabel, copySet: copySet, removeSet: removeSet, readOnly: readOnly, timerRunning: timerRunning, inputHeight: inputHeight, side: nil, effortVisible: $effortVisible, startRest: startRest, action: action) }
            if !readOnly, mode == "time",let startTimer { Button {GymKeyboard.dismiss();startTimer()} label:{ Label(LocalizedStringKey(timerRunning ? "TIMER_RUNNING" : "START_TIMER"),systemImage:"timer").font(.subheadline).frame(maxWidth:.infinity).padding(9).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:10)) }.disabled(timerRunning || row["done"] as? Bool == true).accessibilityIdentifier("timer-\(identifier)") }
        }.disabled(readOnly)
    }
}
