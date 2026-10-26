import SwiftUI
/// The same controls edit a live set and a saved set; writes go through the web's row functions.
struct AdvancedSetEditor:View {
    let row:[String:Any]
    let target:[String:Any]
    let unit:String
    var identifier = "set"
    var timerRunning = false
    var startTimer:(()->Void)? = nil
    var startRest:((Double)->Void)? = nil
    let action:([String:Any])->Void
    @State private var effortVisible = false
    @FocusState private var editing:Bool
    private var sides:[String:[String:Any]]? { row["sides"] as? [String:[String:Any]] }
    private var mode:String { ((try? WebRules.shared.call("rowInfo",payload:["row":row,"target":target])) as? [String:Any])?["mode"] as? String ?? "reps" }
    private var warmup:Bool { ["warmup","warm-up","warm_up"].contains(row["phase"] as? String ?? "") || (row["phase"] == nil && row["warmup"] as? Bool == true) }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:8) {
                if warmup { Text("热身").font(.caption).foregroundStyle(.orange) }
                if row["max"] as? Bool == true { Text("MAX").font(.caption).foregroundStyle(GymTheme.green) }
                if let side = row["side"] as? String { Text(side == "L" ? "左侧" : "右侧").font(.caption).foregroundStyle(GymTheme.green) }
                if row["type"] as? String == "dropset" { Text("递减组").font(.caption).foregroundStyle(GymTheme.green) }
                if row["type"] as? String == "restpause" { Text("Rest-pause").font(.caption).foregroundStyle(GymTheme.green) }
                Spacer()
                Menu {
                    if mode == "reps" && !warmup {
                        if row["type"] as? String != "restpause" {Button("添加递减") { action(["action":"dropAdd"]) }}
                        if row["type"] as? String != "dropset" {Button("添加 Rest-pause 小组") { action(["action":"clusterAdd"]) }}
                        Button(row["failure"] as? Bool == true ? "取消力竭标记" : "标记力竭") { action(["action":"failure"]) }
                    }
                    if warmup || (((try? WebRules.shared.call("rowInfo",payload:["row":row,"target":target])) as? [String:Any])?["canWarmup"] as? Bool == true) { Button(warmup ? "改为工作组" : "改为热身组") { action(["action":"warmup","value":!warmup]) } }
                    Button(effortVisible ? "收起 RIR / RPE" : "记录 RIR / RPE") { effortVisible.toggle() }
                } label:{Image(systemName:"ellipsis.circle").foregroundStyle(GymTheme.muted)}.accessibilityLabel("组型与强度选项").disabled(timerRunning)
            }
            if sides != nil { pane("L");Divider();pane("R") } else { pane(nil) }
            if row["failure"] as? Bool == true { Label("力竭",systemImage:"bolt.fill").font(.caption).foregroundStyle(.orange) }
            if mode == "time",let startTimer { Button {editing = false;startTimer()} label:{ Label(timerRunning ? "计时中" : "开始计时",systemImage:"timer").font(.subheadline).frame(maxWidth:.infinity).padding(9).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:10)) }.disabled(timerRunning || row["done"] as? Bool == true).accessibilityIdentifier("timer-\(identifier)") }
        }
    }
    private func pane(_ side:String?)->some View {
        let data = side.flatMap { sides?[$0] } ?? row
        return VStack(alignment:.leading,spacing:9) {
            if let side { Text(side == "L" ? "左侧" : "右侧").font(.caption.bold()).foregroundStyle(GymTheme.green) }
            HStack(spacing:8) {
                if mode == "cardio" { field("分钟","min",data,side);field(unit == "lb" ? "mph" : "km/h","speed",data,side) }
                else { field(unit,"w",data,side);field(mode == "time" ? "秒" : "次数",mode == "time" ? "sec" : "r",data,side) }
                Button { editing = false;var p:[String:Any] = ["action":"toggle"];p["side"] = side;action(p) } label:{Image(systemName:"checkmark").font(.system(size:15,weight:.bold)).frame(width:39,height:40).foregroundStyle(data["done"] as? Bool == true ? .black : .gray).background(data["done"] as? Bool == true ? GymTheme.green : Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.borderless).accessibilityLabel("\(side == "L" ? "左侧" : side == "R" ? "右侧" : "本组")完成").accessibilityIdentifier("complete-\(identifier)-\(side ?? "both")").accessibilityValue(data["done"] as? Bool == true ? "已完成":"未完成").disabled(timerRunning)
            }
            let drops = data["drops"] as? [[String:Any]] ?? []
            ForEach(drops.indices,id:\.self) { i in
                HStack(spacing:8) {
                    Text("降 \(i+1)").font(.caption).foregroundStyle(GymTheme.muted)
                    subField("重量",path:"drop.\(side ?? "both").\(i).w",value:number(drops[i]["w"]),operation:["action":"dropEdit","index":i,"side":side as Any? ?? NSNull()],patchKey:"w") { subAction("dropEdit",side:side,index:i,patch:["w":$0]) }
                    subField("次数",path:"drop.\(side ?? "both").\(i).r",value:number(drops[i]["r"]),operation:["action":"dropEdit","index":i,"side":side as Any? ?? NSNull()],patchKey:"r") { subAction("dropEdit",side:side,index:i,patch:["r":$0]) }
                    Button { subAction("dropRemove",side:side,index:i) } label:{Image(systemName:"minus.circle").foregroundStyle(.orange)}.buttonStyle(.borderless)
                }
            }
            let clusters = data["clusters"] as? [[String:Any]] ?? []
            ForEach(clusters.indices,id:\.self) { i in
                HStack {
                    Text("小组 \(i+1)").font(.caption).foregroundStyle(GymTheme.muted)
                    subField("次数",path:"cluster.\(side ?? "both").\(i).r",value:number(clusters[i]["r"]),operation:["action":"clusterEdit","index":i,"side":side as Any? ?? NSNull()]) { var p:[String:Any] = ["action":"clusterEdit","index":i,"value":$0];p["side"] = side;action(p) }
                    if let startRest { Button("休息 \(Int(number(clusters[i]["restSec"])))s") {editing = false;startRest(number(clusters[i]["restSec"]))}.font(.caption2).buttonStyle(.borderless).disabled(timerRunning) }
                    else {Text("休息 \(Int(number(clusters[i]["restSec"])))s").font(.caption2).foregroundStyle(GymTheme.muted)}
                    Button { subAction("clusterRemove",side:side,index:i) } label:{Image(systemName:"minus.circle").foregroundStyle(.orange)}.buttonStyle(.borderless)
                }
            }
            if effortVisible || data["rir"] != nil || data["rpe"] != nil {
                HStack {
                    Menu(data["rpe"] != nil ? "RPE" : "RIR") { Button("RIR") { emitField("rir",value:2,side:side) };Button("RPE") { emitField("rpe",value:8,side:side) };Button("清除") { emitField("rir",value:NSNull(),side:side);emitField("rpe",value:NSNull(),side:side);effortVisible = false } }.font(.caption)
                    subField("强度",path:"\(side ?? "both").\(data["rpe"] != nil ? "rpe" : "rir")",value:number(data["rpe"] ?? data["rir"] ?? 2),operation:["action":"field","key":data["rpe"] != nil ? "rpe" : "rir","side":side as Any? ?? NSNull()]) { emitField(data["rpe"] != nil ? "rpe" : "rir",value:min(10,max(0,$0)),side:side) }
                }
            }
        }
    }
    private func field(_ title:String,_ key:String,_ data:[String:Any],_ side:String?)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title,text:inputBinding(path:"\(side ?? "both").\(key)",value:number(data[key]),operation:["action":"field","key":key,"side":side as Any? ?? NSNull()])).keyboardType(.decimalPad).focused($editing).multilineTextAlignment(.center).padding(9).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:9)).accessibilityIdentifier("\(key)-\(identifier)-\(side ?? "both")").disabled(timerRunning || (key == "r" && data["type"] as? String == "restpause"))
        }
    }
    private func emitField(_ key:String,value:Any,side:String?) { var p:[String:Any] = ["action":"field","key":key,"value":value];p["side"] = side;action(p) }
    private func subAction(_ type:String,side:String?,index:Int,patch:[String:Any] = [:]) { var p:[String:Any] = ["action":type,"index":index,"patch":patch];p["side"] = side;action(p) }
    private func inputBinding(path:String,value:Double,operation:[String:Any],patchKey:String? = nil) -> Binding<String> {
        Binding(get:{TrainingInput.display(row,path:path,number:value)},set:{ text in
            var message:[String:Any] = ["action":"input","path":path,"text":text,"operation":operation]
            message["patchKey"] = patchKey;action(message)
        })
    }
    private func subField(_ title:String,path:String,value:Double,operation:[String:Any],patchKey:String? = nil,change:@escaping(Double)->Void)->some View {
        TextField(title,text:inputBinding(path:path,value:value,operation:operation,patchKey:patchKey)).keyboardType(.decimalPad).focused($editing).multilineTextAlignment(.center).padding(7).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8)).accessibilityIdentifier("\(path)-\(identifier)")
    }
}
