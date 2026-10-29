import SwiftUI
struct AdvancedConfigEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var config:[String:Any]
    @State private var error:String?
    let unit:String
    let save:([String:Any])->Void
    init(config:[String:Any],unit:String,save:@escaping([String:Any])->Void) { _config = State(initialValue:config);self.unit = unit;self.save = save }
    private var cardio:Bool { store.exercise(config["id"] as? String ?? "")?.bodyPart == "cardio" }
    private var mode:String { cardio ? "cardio" : config["mode"] as? String ?? "reps" }
    private var pyramid:[Any] { config["pyramid"] as? [Any] ?? [] }
    private var intensifier:[String:Any] { config["intensifier"] as? [String:Any] ?? [:] }
    var body:some View {
        NavigationStack {
            Form {
                Section("记录方式") {
                    if cardio { Label("有氧 · 时长与速度",systemImage:"figure.run") }
                    else { Picker("方式",selection:Binding(get:{mode},set:{config["mode"] = $0;config.removeValue(forKey:"prog")})) { Text("次数").tag("reps");Text("计时").tag("time") }.pickerStyle(.segmented).accessibilityIdentifier("advanced-mode") }
                    field("组数",key:"sets",fallback:3)
                    if mode == "cardio" { field("每组分钟",key:"min",fallback:20);field(unit == "lb" ? "速度（mph）" : "速度（km/h）",key:"speed",fallback:8) }
                    else if mode == "time" { field("每组秒数",key:"sec",fallback:45);field("附加重量（\(unit)）",key:"weight",fallback:0) }
                    else { field("总次数（双侧合计）",key:"reps",fallback:10);field("重量（\(unit)）",key:"weight",fallback:0) }
                    if mode != "cardio" { Toggle("左右分侧记录",isOn:flag("side")).accessibilityIdentifier("advanced-side") }
                }
                if mode != "cardio" {
                    Section("热身与休息") {
                        if intensifier["type"] as? String != "restpause" { Stepper("热身 \(Int(number(config["warmupSets"]))) 组",value:Binding(get:{Int(number(config["warmupSets"]))},set:{config["warmupSets"] = $0}),in:0...5).accessibilityIdentifier("advanced-warmups") }
                        field("组间休息（秒，0 为默认）",key:"restSec",fallback:0)
                        field("热身间休息（秒，0 为默认）",key:"warmupRestSec",fallback:0)
                    }
                }
                if mode == "reps" {
                    Section {
                        Toggle("金字塔组",isOn:Binding(get:{!pyramid.isEmpty},set:{ enabled in
                            if enabled { config["pyramid"] = [12,10,8,6];config.removeValue(forKey:"intensifier");config.removeValue(forKey:"lastToFailure") }
                            else { config.removeValue(forKey:"pyramid");config.removeValue(forKey:"pyramidWeight");config.removeValue(forKey:"pyramidRest") }
                        })).accessibilityIdentifier("advanced-pyramid")
                        if !pyramid.isEmpty {
                            ForEach(pyramid.indices,id:\.self) { i in
                                VStack(alignment:.leading,spacing:8) {
                                    HStack { Text("第 \(i+1) 组").font(.headline);Spacer();Toggle("Max",isOn:Binding(get:{pyramid[i] as? String == "max"},set:{setPyramid("pyramid",i,$0 ? "max" : 10)})).fixedSize() }
                                    if pyramid[i] as? String != "max" { pyramidField("次数",key:"pyramid",i:i) }
                                    pyramidField("重量（0 沿用上次）",key:"pyramidWeight",i:i)
                                    pyramidField("休息秒数（0 为默认）",key:"pyramidRest",i:i)
                                    if pyramid.count > 1 { Button("移除此组",role:.destructive) { for key in ["pyramid","pyramidWeight","pyramidRest"] { if var list = config[key] as? [Any],list.indices.contains(i) { list.remove(at:i);config[key] = list } } }.font(.caption) }
                                }.padding(.vertical,5)
                            }
                            Button("添加金字塔组") { var list = pyramid;list.append(10);config["pyramid"] = list }.disabled(pyramid.count>=10)
                        }
                    } header:{Text("逐组目标")} footer:{Text("金字塔每组可以有不同次数、重量与休息。Max 组记录实际做到的次数；不会自动进阶。")}
                    if pyramid.isEmpty {
                        Section("递减 / Rest-pause") {
                            Picker("组型",selection:Binding(get:{intensifier["type"] as? String ?? "straight"},set:{ kind in
                                if kind == "straight" { config.removeValue(forKey:"intensifier") }
                                else if kind == "dropset" { config["intensifier"] = ["type":kind,"count":1,"pct":20] }
                                else { config["intensifier"] = ["type":kind,"totalReps":12,"restSec":15] }
                            })) { Text("普通组").tag("straight");Text("递减组").tag("dropset");Text("Rest-pause").tag("restpause") }.accessibilityIdentifier("advanced-intensifier")
                            if intensifier["type"] as? String == "dropset" { intensityField("递减次数",key:"count",fallback:1);intensityField("每次减重 %",key:"pct",fallback:20) }
                            if intensifier["type"] as? String == "restpause" {
                                intensityField("Rest-pause 总次数",key:"totalReps",fallback:12);intensityField("小组间休息秒数",key:"restSec",fallback:15)
                                Text("按网页规则生成一组热身与一组 Rest-pause；小组次数合计为工作组总次数，不重复计算训练量。").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ProgressionOptions(config:$config,mode:mode,unit:unit)
                if mode != "cardio" && pyramid.isEmpty { Section { Toggle("最后一组力竭 / AMRAP",isOn:flag("lastToFailure")) } }
            }.navigationTitle("高级组型").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("取消") { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button("完成") {
                    do { var c = config;c["mode"] = mode;for key in ["inc","repsMin","setsMax","deloadFactor"] { if let text = c[key] as? String { guard let n = TrainingInput.value(text) else { throw APIError.response(0,"请填完进阶参数。") };c[key] = n } }; _ = try WebRules.shared.call("validatePersonalConfig",payload:["config":c]);let next = try WebRules.shared.call("advancedConfig",payload:["config":c]) as! [String:Any];save(next);dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("advanced-config-done") } }
                .alert("无法应用",isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button("知道了",role:.cancel) {} } message:{Text(error ?? "")}
        }.tint(GymTheme.green)
    }
    private func flag(_ key:String)->Binding<Bool>{Binding(get:{config[key] as? Bool ?? false},set:{if $0 { config[key] = true } else { config.removeValue(forKey:key) }})}
    private func field(_ title:String,key:String,fallback:Double)->some View { HStack { Text(title).font(.subheadline);Spacer();TextField(title,value:Binding(get:{number(config[key] ?? fallback)},set:{config[key] = max(0,$0)}),format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:85).accessibilityIdentifier("config-\(key)") } }
    private func intensityField(_ title:String,key:String,fallback:Double)->some View { HStack { Text(title).font(.subheadline);Spacer();TextField(title,value:Binding(get:{number(intensifier[key] ?? fallback)},set:{var x = intensifier;x[key] = max(0,$0);config["intensifier"] = x}),format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:80).accessibilityIdentifier("config-intensity-\(key)") } }
    private func setPyramid(_ key:String,_ index:Int,_ value:Any) { var list = config[key] as? [Any] ?? Array(repeating:0,count:pyramid.count);while list.count < pyramid.count { list.append(0) };guard list.indices.contains(index) else {return};list[index] = value;config[key] = list }
    private func pyramidField(_ title:String,key:String,i:Int)->some View { HStack { Text(title).font(.caption);Spacer();TextField(title,value:Binding(get:{let list = config[key] as? [Any] ?? [];return list.indices.contains(i) ? number(list[i]) : 0},set:{setPyramid(key,i,max(0,$0))}),format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:80).accessibilityIdentifier("\(key)-\(i)") } }
}
