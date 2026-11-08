import SwiftUI

struct AdvancedSetPane: View {
    let row: [String: Any]
    let target: [String: Any]
    let unit: String
    let inputState: [String: Any]
    let identifier: String
    let setLabel: String
    let copySet: (() -> Void)?
    let removeSet: (() -> Void)?
    let readOnly: Bool
    let timerRunning: Bool
    let inputHeight: CGFloat
    let side: String?
    @Binding var effortVisible: Bool
    let startRest: ((Double) -> Void)?
    let action: ([String: Any]) -> Void
    private var weightUnit: String { TrainingInput.weightUnit(row, fallback: unit) }
    private var sides:[String:[String:Any]]? { row["sides"] as? [String:[String:Any]] }
    private var mode:String { ((try? WebRules.shared.call("rowInfo",payload:["row":row,"target":target])) as? [String:Any])?["mode"] as? String ?? "reps" }
    private var warmup:Bool { ["warmup","warm-up","warm_up"].contains(row["phase"] as? String ?? "") || (row["phase"] == nil && row["warmup"] as? Bool == true) }
    private var compact: Bool { mode == "reps" && sides == nil }
    private var data: [String: Any] { side.flatMap { sides?[$0] } ?? row }

    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            if let side { Text(LocalizedStringKey(side == "L" ? "LEFT" : "RIGHT")).font(.caption.bold()).foregroundStyle(GymTheme.green) }
            HStack(alignment: compact ? .top : .bottom, spacing:8) {
                if compact {
                    Text(warmup ? String(localized: "LABEL_W", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : row["max"] as? Bool == true ? "MAX" : setLabel.filter(\.isNumber))
                        .font(.caption.monospacedDigit()).foregroundStyle(warmup ? .orange : GymTheme.muted).frame(width: 24, height: inputHeight).accessibilityLabel(warmup ? String(format: String(localized: "WARM_UP_SET_ACCESSIBILITY_LABEL", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, setLabel, String(localized: "WARM_UP", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) : setLabel)
                }
                if mode == "cardio" { AdvancedSetInputField(title: "MINUTES", text: fieldBinding("min"), compact: compact, setLabel: setLabel, identifier: fieldIdentifier("min"), height: inputHeight, disabled: timerRunning || (("min") == "r" && data["type"] as? String == "restpause"));AdvancedSetInputField(title: TrainingInput.speedUnit(inputState) == "mph" ? "mph" : "km/h", text: fieldBinding("speed"), compact: compact, setLabel: setLabel, identifier: fieldIdentifier("speed"), height: inputHeight, disabled: timerRunning || (("speed") == "r" && data["type"] as? String == "restpause")) }
                else { AdvancedSetInputField(title: "\(weightUnit)", text: fieldBinding("w"), compact: compact, setLabel: setLabel, identifier: fieldIdentifier("w"), height: inputHeight, disabled: timerRunning || (("w") == "r" && data["type"] as? String == "restpause"));AdvancedSetInputField(title: mode == "time" ? "SEC" : "REPS", text: fieldBinding(mode == "time" ? "sec" : "r"), compact: compact, setLabel: setLabel, identifier: fieldIdentifier(mode == "time" ? "sec" : "r"), height: inputHeight, disabled: timerRunning || ((mode == "time" ? "sec" : "r") == "r" && data["type"] as? String == "restpause")) }
                SetCompletionControl(completed: data["done"] as? Bool == true,
                    failure: row["failure"] as? Bool == true || data["failure"] as? Bool == true,
                    readOnly: readOnly, timerRunning: timerRunning, height: inputHeight,
                    label: completionLabel, identifier: "complete-\(identifier)-\(side ?? "both")") {
                    GymKeyboard.dismiss()
                    var operation: [String: Any] = ["action": "toggle"]
                    operation["side"] = side
                    action(operation)
                }
                if compact && !readOnly { AdvancedSetMenu(row: row, target: target, mode: mode, warmup: warmup, identifier: identifier, setLabel: setLabel, copySet: copySet, removeSet: removeSet, timerRunning: timerRunning, effortVisible: $effortVisible, action: action) }
            }
            if mode == "cardio", ((try? WebRules.shared.call("rowInfo", payload: ["row": row, "target": target])) as? [String: Any])?["incline"] as? Bool == true {
                AdvancedSetInputField(title: "INCLINE_OPTIONAL", text: fieldBinding("incline"), compact: compact, setLabel: setLabel, identifier: fieldIdentifier("incline"), height: inputHeight, disabled: timerRunning || (("incline") == "r" && data["type"] as? String == "restpause"))
            }
            let drops = data["drops"] as? [[String:Any]] ?? []
            ForEach(drops.indices,id:\.self) { i in
                HStack(spacing:8) {
                    Text(String(format: String(localized: "DROP_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: i+1))).font(.caption).foregroundStyle(GymTheme.muted)
                    AdvancedSetSubfield(title: "\(weightUnit)", text: inputBinding(path: "drop.\(side ?? "both").\(i).w", value: number(drops[i]["w"]), operation: ["action":"dropEdit","index":i,"side":side as Any? ?? NSNull()], patchKey: "w"), identifier: "drop.\(side ?? "both").\(i).w" + "-" + identifier, timerRunning: timerRunning)
                    AdvancedSetSubfield(title: "REPS", text: inputBinding(path: "drop.\(side ?? "both").\(i).r", value: number(drops[i]["r"]), operation: ["action":"dropEdit","index":i,"side":side as Any? ?? NSNull()], patchKey: "r"), identifier: "drop.\(side ?? "both").\(i).r" + "-" + identifier, timerRunning: timerRunning)
                    if !readOnly {
                        Button { subAction("dropRemove",side:side,index:i) } label:{Image(systemName:"minus.circle").foregroundStyle(.orange)}.buttonStyle(.borderless)
                    }
                }
            }
            let clusters = data["clusters"] as? [[String:Any]] ?? []
            ForEach(clusters.indices,id:\.self) { i in
                HStack {
                    Text(String(format: String(localized: "MINI_SET_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: i+1))).font(.caption).foregroundStyle(GymTheme.muted)
                    AdvancedSetSubfield(title: "REPS", text: inputBinding(path: "cluster.\(side ?? "both").\(i).r", value: number(clusters[i]["r"]), operation: ["action":"clusterEdit","index":i,"side":side as Any? ?? NSNull()]), identifier: "cluster.\(side ?? "both").\(i).r" + "-" + identifier, timerRunning: timerRunning)
                    if !readOnly, let startRest { Button(String(format: String(localized: "COUNT_REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: String(format: String(localized: "DURATION_SECONDS_SHORT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(clusters[i]["restSec"]))))))) {GymKeyboard.dismiss();startRest(number(clusters[i]["restSec"]))}.font(.caption2).buttonStyle(.borderless).disabled(timerRunning) }
                    else {Text(String(format: String(localized: "COUNT_REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: String(format: String(localized: "DURATION_SECONDS_SHORT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(clusters[i]["restSec"]))))))).font(.caption2).foregroundStyle(GymTheme.muted)}
                    if !readOnly {
                        Button { subAction("clusterRemove",side:side,index:i) } label:{Image(systemName:"minus.circle").foregroundStyle(.orange)}.buttonStyle(.borderless)
                    }
                }
            }
            if (!readOnly && (effortVisible || ["rir","rpe"].contains(inputState["effort"] as? String ?? ""))) || data["rir"] != nil || data["rpe"] != nil {
                HStack {
                    if readOnly { Text(effortKey(data).uppercased()).font(.caption) }
                    else { Menu(effortKey(data).uppercased()) { Button("RIR") { emitField("rir",value:2,side:side) };Button("RPE") { emitField("rpe",value:8,side:side) };Button("CLEAR") { emitField("rir",value:NSNull(),side:side);emitField("rpe",value:NSNull(),side:side);effortVisible = false } }.font(.caption) }
                    AdvancedSetSubfield(title: "EFFORT", text: inputBinding(path: "\(side ?? "both").\(effortKey(data))", value: number(data["rpe"] ?? data["rir"] ?? (effortKey(data) == "rpe" ? 8:2)), operation: ["action":"field","key":effortKey(data),"side":side as Any? ?? NSNull()]), identifier: "\(side ?? "both").\(effortKey(data))" + "-" + identifier, timerRunning: timerRunning)
                }
            }
        }
    }

    private func fieldBinding(_ key: String) -> Binding<String> {
        inputBinding(path: "\(side ?? "both").\(key)", value: number(data[key]),
            operation: ["action": "field", "key": key, "side": side as Any? ?? NSNull()])
    }

    private func fieldIdentifier(_ key: String) -> String {
        "\(key)-\(identifier)-\(side ?? "both")"
    }

    private var completionLabel: String {
        String(format: String(localized: "COUNT_COMPLETE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale,
            String(describing: side == "L" ? String(localized: "LEFT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : side == "R" ? String(localized: "RIGHT", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "THIS_SET", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
    }

    private func effortKey(_ data:[String:Any])->String { data["rpe"] != nil ? "rpe":data["rir"] != nil ? "rir":inputState["effort"] as? String == "rpe" ? "rpe":"rir" }

    private func emitField(_ key:String,value:Any,side:String?) { var p:[String:Any] = ["action":"field","key":key,"value":value];p["side"] = side;action(p) }

    private func subAction(_ type:String,side:String?,index:Int,patch:[String:Any] = [:]) { var p:[String:Any] = ["action":type,"index":index,"patch":patch];p["side"] = side;action(p) }

    private func inputBinding(path:String,value:Double,operation:[String:Any],patchKey:String? = nil) -> Binding<String> {
        Binding(get:{
            if path.hasSuffix(".w") { return TrainingInput.weightDisplay(row,path:path,value:value,storedUnit:unit) }
            if path.hasSuffix(".incline"), row["incline"] == nil, (row[TrainingInput.key] as? [String: String])?[path] == nil { return "" }
            return TrainingInput.display(row,path:path,number:path.hasSuffix(".speed") ? TrainingInput.speedDisplay(value,state:inputState) : value)
        },set:{ text in
            var message:[String:Any] = ["action":"input","path":path,"text":text,"operation":operation]
            message["patchKey"] = patchKey;action(message)
        })
    }

}
