import SwiftUI

/// The corner badge adds failure information without changing the set row's layout.
private struct SetCompletionMark: View {
    let completed: Bool
    let failure: Bool
    let height: CGFloat
    private let completedColor = Color(red: 0.60, green: 0.88, blue: 0.52)

    var body: some View {
        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
            .foregroundStyle(completed ? Color.black : .gray)
            .frame(width: 44, height: height)
            .background(completed ? completedColor : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if failure {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(completed ? Color.black : .orange)
                        .padding(2).background(completed ? completedColor : GymTheme.card, in: Circle())
                        .padding(4)
                }
            }
    }
}

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
    @FocusState private var focusedField: String?
    @ScaledMetric(relativeTo: .body) private var inputHeight = 44
    private var weightUnit: String { TrainingInput.weightUnit(row, fallback: unit) }
    private var sides:[String:[String:Any]]? { row["sides"] as? [String:[String:Any]] }
    private var mode:String { ((try? WebRules.shared.call("rowInfo",payload:["row":row,"target":target])) as? [String:Any])?["mode"] as? String ?? "reps" }
    private var warmup:Bool { ["warmup","warm-up","warm_up"].contains(row["phase"] as? String ?? "") || (row["phase"] == nil && row["warmup"] as? Bool == true) }
    private var compact: Bool { mode == "reps" && sides == nil }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if !compact { HStack(spacing:8) {
                Text(setLabel).font(.caption).foregroundStyle(GymTheme.muted)
                if warmup { Text("热身").font(.caption).foregroundStyle(.orange) }
                if row["max"] as? Bool == true { Text("MAX").font(.caption).foregroundStyle(GymTheme.green) }
                if let side = row["side"] as? String { Text(side == "L" ? "左侧" : "右侧").font(.caption).foregroundStyle(GymTheme.green) }
                if row["type"] as? String == "dropset" { Text("递减组").font(.caption).foregroundStyle(GymTheme.green) }
                if row["type"] as? String == "restpause" { Text("Rest-pause").font(.caption).foregroundStyle(GymTheme.green) }
                Spacer()
                if !readOnly { setMenu }
            } }
            if sides != nil { pane("L");Divider();pane("R") } else { pane(nil) }
            if !readOnly, mode == "time",let startTimer { Button {focusedField = nil;startTimer()} label:{ Label(timerRunning ? "计时中" : "开始计时",systemImage:"timer").font(.subheadline).frame(maxWidth:.infinity).padding(9).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:10)) }.disabled(timerRunning || row["done"] as? Bool == true).accessibilityIdentifier("timer-\(identifier)") }
        }.disabled(readOnly)
    }
    private var setMenu: some View {
Menu {
                    if let copySet { Button("复制本组", systemImage: "doc.on.doc", action: copySet) }
                    if let removeSet { Button("删除本组", systemImage: "trash", role: .destructive, action: removeSet) }
                    Divider()
                    if mode == "reps" && !warmup {
                        if row["type"] as? String != "restpause" {Button("添加递减") { action(["action":"dropAdd"]) }}
                        if row["type"] as? String != "dropset" {Button("添加 Rest-pause 小组") { action(["action":"clusterAdd"]) }}
                        Button(row["failure"] as? Bool == true ? "取消力竭标记" : "标记力竭") { action(["action":"failure"]) }
                    }
                    if warmup || (((try? WebRules.shared.call("rowInfo",payload:["row":row,"target":target])) as? [String:Any])?["canWarmup"] as? Bool == true) { Button(warmup ? "改为工作组" : "改为热身组") { action(["action":"warmup","value":!warmup]) } }
                    Button(effortVisible ? "收起 RIR / RPE" : "记录 RIR / RPE") { effortVisible.toggle() }
                } label:{Image(systemName:"ellipsis.circle").foregroundStyle(GymTheme.muted).frame(width:44,height:44)}.accessibilityLabel("\(setLabel)选项").accessibilityIdentifier("set-options-\(identifier)").disabled(timerRunning)
    }
    private func pane(_ side:String?)->some View {
        let data = side.flatMap { sides?[$0] } ?? row
        return VStack(alignment:.leading,spacing:9) {
            if let side { Text(side == "L" ? "左侧" : "右侧").font(.caption.bold()).foregroundStyle(GymTheme.green) }
            HStack(alignment: compact ? .top : .bottom, spacing:8) {
                if compact {
                    Text(warmup ? "热" : row["max"] as? Bool == true ? "MAX" : setLabel.replacingOccurrences(of: "第 ", with: "").replacingOccurrences(of: " 组", with: ""))
                        .font(.caption.monospacedDigit()).foregroundStyle(warmup ? .orange : GymTheme.muted).frame(width: 24, height: inputHeight).accessibilityLabel("\(setLabel)\(warmup ? "热身" : "")")
                }
                if mode == "cardio" { field("分钟","min",data,side);field(TrainingInput.speedUnit(inputState) == "mph" ? "mph" : "km/h","speed",data,side) }
                else { field(weightUnit,"w",data,side);field(mode == "time" ? "秒" : "次数",mode == "time" ? "sec" : "r",data,side) }
                completionControl(data, side: side)
                if compact && !readOnly { setMenu }
            }
            if mode == "reps", let plates = plateText(data) {
                ScrollView(.horizontal, showsIndicators: false) { Text(plates).font(.caption2).foregroundStyle(GymTheme.muted).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
            }
            if mode == "cardio", ((try? WebRules.shared.call("rowInfo", payload: ["row": row, "target": target])) as? [String: Any])?["incline"] as? Bool == true {
                field("坡度 %（可选）", "incline", data, side)
            }
            let drops = data["drops"] as? [[String:Any]] ?? []
            ForEach(drops.indices,id:\.self) { i in
                HStack(spacing:8) {
                    Text("降 \(i+1)").font(.caption).foregroundStyle(GymTheme.muted)
                    subField(weightUnit,path:"drop.\(side ?? "both").\(i).w",value:number(drops[i]["w"]),operation:["action":"dropEdit","index":i,"side":side as Any? ?? NSNull()],patchKey:"w") { subAction("dropEdit",side:side,index:i,patch:["w":$0]) }
                    subField("次数",path:"drop.\(side ?? "both").\(i).r",value:number(drops[i]["r"]),operation:["action":"dropEdit","index":i,"side":side as Any? ?? NSNull()],patchKey:"r") { subAction("dropEdit",side:side,index:i,patch:["r":$0]) }
                    if !readOnly {
                        Button { subAction("dropRemove",side:side,index:i) } label:{Image(systemName:"minus.circle").foregroundStyle(.orange)}.buttonStyle(.borderless)
                    }
                }
            }
            let clusters = data["clusters"] as? [[String:Any]] ?? []
            ForEach(clusters.indices,id:\.self) { i in
                HStack {
                    Text("小组 \(i+1)").font(.caption).foregroundStyle(GymTheme.muted)
                    subField("次数",path:"cluster.\(side ?? "both").\(i).r",value:number(clusters[i]["r"]),operation:["action":"clusterEdit","index":i,"side":side as Any? ?? NSNull()]) { var p:[String:Any] = ["action":"clusterEdit","index":i,"value":$0];p["side"] = side;action(p) }
                    if !readOnly, let startRest { Button("休息 \(Int(number(clusters[i]["restSec"])))s") {focusedField = nil;startRest(number(clusters[i]["restSec"]))}.font(.caption2).buttonStyle(.borderless).disabled(timerRunning) }
                    else {Text("休息 \(Int(number(clusters[i]["restSec"])))s").font(.caption2).foregroundStyle(GymTheme.muted)}
                    if !readOnly {
                        Button { subAction("clusterRemove",side:side,index:i) } label:{Image(systemName:"minus.circle").foregroundStyle(.orange)}.buttonStyle(.borderless)
                    }
                }
            }
            if (!readOnly && (effortVisible || ["rir","rpe"].contains(inputState["effort"] as? String ?? ""))) || data["rir"] != nil || data["rpe"] != nil {
                HStack {
                    if readOnly { Text(effortKey(data).uppercased()).font(.caption) }
                    else { Menu(effortKey(data).uppercased()) { Button("RIR") { emitField("rir",value:2,side:side) };Button("RPE") { emitField("rpe",value:8,side:side) };Button("清除") { emitField("rir",value:NSNull(),side:side);emitField("rpe",value:NSNull(),side:side);effortVisible = false } }.font(.caption) }
                    subField("强度",path:"\(side ?? "both").\(effortKey(data))",value:number(data["rpe"] ?? data["rir"] ?? (effortKey(data) == "rpe" ? 8:2)),operation:["action":"field","key":effortKey(data),"side":side as Any? ?? NSNull()]) { emitField(effortKey(data),value:min(10,max(0,$0)),side:side) }
                }
            }
        }
    }
    @ViewBuilder private func completionControl(_ data: [String: Any], side: String?) -> some View {
        let completed = data["done"] as? Bool == true
        let failure = row["failure"] as? Bool == true || data["failure"] as? Bool == true
        Group {
            if readOnly {
                // A read-only marker is not a disabled Button, so its fill never dims.
                SetCompletionMark(completed: completed, failure: failure, height: inputHeight)
                    .accessibilityElement(children: .ignore)
            } else {
                Button {
                    focusedField = nil
                    var operation: [String: Any] = ["action": "toggle"]
                    operation["side"] = side
                    action(operation)
                } label: { SetCompletionMark(completed: completed, failure: failure, height: inputHeight) }
                    .buttonStyle(.plain).disabled(timerRunning)
            }
        }
        .accessibilityLabel("\(side == "L" ? "左侧" : side == "R" ? "右侧" : "本组")完成")
        .accessibilityIdentifier("complete-\(identifier)-\(side ?? "both")")
        .accessibilityValue((completed ? "已完成" : "未完成") + (failure ? "，力竭" : ""))
    }
    private func effortKey(_ data:[String:Any])->String { data["rpe"] != nil ? "rpe":data["rir"] != nil ? "rir":inputState["effort"] as? String == "rpe" ? "rpe":"rir" }
    private func plateText(_ data: [String: Any]) -> String? {
        guard let result = try? WebRules.shared.call("nativePlateInfo", payload: ["state": inputState, "target": target, "weight": number(data["w"])] ) as? [String: Any],
              let load = result["load"] as? [String: Any] else { return nil }
        let suffix = load["kind"] as? String == "pairs" ? "每侧" : "总配片"
        if load["barOnly"] as? Bool == true { return "器械起始重量 \(decimal(number(result["base"]))) \(unit)" }
        let plates = (load["plates"] as? [Double] ?? []).map(decimal).joined(separator: " + ")
        let missing = number(load["missing"])
        return "\(suffix) \(plates.isEmpty ? "—" : plates) \(unit)" + (missing > 0 ? " · 尚差 \(decimal(missing)) \(unit)" : "") + (result["custom"] as? Bool == true ? "" : " · 标准配片")
    }
    private func field(_ title: String, _ key: String, _ data: [String: Any], _ side: String?) -> some View {
        let binding = inputBinding(path: "\(side ?? "both").\(key)", value: number(data[key]), operation: ["action": "field", "key": key, "side": side as Any? ?? NSNull()])
        return VStack(alignment: .leading, spacing: 4) {
            if !compact { Text(title).font(.caption2).foregroundStyle(.secondary) }
            HStack(spacing: 3) {
                TextField(title, text: binding).keyboardType(.decimalPad).focused($focusedField, equals: "\(side ?? "both").\(key)")
                    .multilineTextAlignment(.center).accessibilityLabel("\(setLabel) \(title)")
                    .accessibilityIdentifier("\(key)-\(identifier)-\(side ?? "both")")
                if compact { Text(title).font(.caption2).foregroundStyle(.secondary).fixedSize() }
            }.padding(.horizontal, 7).frame(height: inputHeight)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }.disabled(timerRunning || (key == "r" && data["type"] as? String == "restpause"))
    }
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
    private func subField(_ title:String,path:String,value:Double,operation:[String:Any],patchKey:String? = nil,change:@escaping(Double)->Void)->some View {
        let binding = inputBinding(path:path,value:value,operation:operation,patchKey:patchKey)
        return VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title,text:binding).keyboardType(.decimalPad).focused($focusedField, equals: path).multilineTextAlignment(.center).padding(7).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8)).accessibilityIdentifier("\(path)-\(identifier)")
        }.disabled(timerRunning)
    }
}
