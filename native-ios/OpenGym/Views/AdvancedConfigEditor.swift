import SwiftUI
struct AdvancedConfigEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
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
                Section(L10n.text("LOGGING_MODE" /* 记录方式 */)) {
                    if cardio { Label(L10n.text("CARDIO_DURATION_AND_SPEED" /* 有氧 · 时长与速度 */),systemImage:"figure.run") }
                    else { Picker(L10n.text("MODE" /* 方式 */),selection:Binding(get:{mode},set:{inputBuffer.commitAll();config["mode"] = $0;config.removeValue(forKey:"prog")})) { Text(L10n.text("REPS" /* 次数 */)).tag("reps");Text(L10n.text("TIMED" /* 计时 */)).tag("time") }.pickerStyle(.segmented).accessibilityIdentifier("advanced-mode") }
                    field(L10n.text("SETS" /* 组数 */),key:"sets",fallback:3)
                    if mode == "cardio" { field(L10n.text("MINUTES_PER_SET" /* 每组分钟 */),key:"min",fallback:20);field(unit == "lb" ? L10n.text("SPEED_MPH" /* 速度（mph） */) : L10n.text("SPEED_KM_H" /* 速度（km/h） */),key:"speed",fallback:8) }
                    else if mode == "time" { field(L10n.text("SECONDS_PER_SET" /* 每组秒数 */),key:"sec",fallback:45);field(L10n.text("ADDED_WEIGHT_COUNT" /* 附加重量（{0}） */, unit),key:"weight",fallback:0) }
                    else { field(L10n.text("TOTAL_REPS_BOTH_SIDES" /* 总次数（双侧合计） */),key:"reps",fallback:10);field(L10n.text("WEIGHT_COUNT" /* 重量（{0}） */, unit),key:"weight",fallback:0) }
                    if mode != "cardio" { Toggle(L10n.text("LOG_LEFT_AND_RIGHT_SEPARATELY" /* 左右分侧记录 */),isOn:flag("side")).accessibilityIdentifier("advanced-side") }
                }
                if mode != "cardio" {
                    Section(L10n.text("WARM_UP_AND_REST" /* 热身与休息 */)) {
                        if intensifier["type"] as? String != "restpause" { Stepper(L10n.text("COUNT_WARM_UP_SETS" /* 热身 {0} 组 */, Int(number(config["warmupSets"]))),value:Binding(get:{Int(number(config["warmupSets"]))},set:{config["warmupSets"] = $0}),in:0...5).accessibilityIdentifier("advanced-warmups") }
                        field(L10n.text("REST_BETWEEN_SETS_SECONDS_ZERO_FOR_DEFAULT" /* 组间休息（秒，0 为默认） */),key:"restSec",fallback:0)
                        field(L10n.text("REST_BETWEEN_WARM_UPS_SECONDS_ZERO_FOR_DEFAULT" /* 热身间休息（秒，0 为默认） */),key:"warmupRestSec",fallback:0)
                    }
                }
                if mode == "reps" {
                    Section {
                        Toggle(L10n.text("PYRAMID_SETS" /* 金字塔组 */),isOn:Binding(get:{!pyramid.isEmpty},set:{ enabled in
                            inputBuffer.commitAll()
                            if enabled { config["pyramid"] = [12,10,8,6];config.removeValue(forKey:"intensifier");config.removeValue(forKey:"lastToFailure") }
                            else { config.removeValue(forKey:"pyramid");config.removeValue(forKey:"pyramidWeight");config.removeValue(forKey:"pyramidRest") }
                        })).accessibilityIdentifier("advanced-pyramid")
                        if !pyramid.isEmpty {
                            ForEach(pyramid.indices,id:\.self) { i in
                                VStack(alignment:.leading,spacing:8) {
                                    HStack { Text(L10n.text("SET_COUNT" /* 第 {0} 组 */, i+1)).font(.headline);Spacer();Toggle(L10n.text("MAX" /* 力竭次数 */),isOn:Binding(get:{pyramid[i] as? String == "max"},set:{setPyramid("pyramid",i,$0 ? "max" : 10)})).fixedSize() }
                                    if pyramid[i] as? String != "max" { pyramidField(L10n.text("REPS" /* 次数 */),key:"pyramid",i:i) }
                                    pyramidField(L10n.text("WEIGHT_ZERO_TO_USE_LAST_WORKOUT" /* 重量（0 沿用上次） */),key:"pyramidWeight",i:i)
                                    pyramidField(L10n.text("REST_IN_SECONDS_ZERO_FOR_DEFAULT" /* 休息秒数（0 为默认） */),key:"pyramidRest",i:i)
                                    if pyramid.count > 1 { Button(L10n.text("DELETE_SET" /* 删除本组 */),role:.destructive) { inputBuffer.commitAll(); for key in ["pyramid","pyramidWeight","pyramidRest"] { if var list = config[key] as? [Any],list.indices.contains(i) { list.remove(at:i);config[key] = list } } }.font(.caption) }
                                }.padding(.vertical,5)
                            }
                            Button(L10n.text("ADD_PYRAMID_SET" /* 添加金字塔组 */)) { inputBuffer.commitAll(); var list = pyramid;list.append(10);config["pyramid"] = list }.disabled(pyramid.count>=10)
                        }
                    } header: { HStack { Text(L10n.text("TARGETS_BY_SET" /* 逐组目标 */)); Spacer(); ExplanationButton(title: L10n.text("PYRAMID_AND_MAX_SETS" /* 金字塔与 Max */), message: L10n.text("SET_DIFFERENT_REPS_WEIGHT_AND_REST_FOR_EACH_SET_MAX_SETS_RECORD" /* 每组可设置不同次数、重量和休息。Max 组记录实际次数，不自动进阶。 */)) } }
                    if pyramid.isEmpty {
                        Section {
                            Picker(L10n.text("SET_TYPE" /* 组型 */),selection:Binding(get:{intensifier["type"] as? String ?? "straight"},set:{ kind in
                                inputBuffer.commitAll()
                                if kind == "straight" { config.removeValue(forKey:"intensifier") }
                                else if kind == "dropset" { config["intensifier"] = ["type":kind,"count":1,"pct":20] }
                                else { config["intensifier"] = ["type":kind,"totalReps":12,"restSec":15] }
                            })) { Text(L10n.text("STRAIGHT_SETS" /* 普通组 */)).tag("straight");Text(L10n.text("DROP_SET" /* 递减组 */)).tag("dropset");Text(L10n.text("REST_PAUSE" /* 休息暂停组 */)).tag("restpause") }.accessibilityIdentifier("advanced-intensifier")
                            if intensifier["type"] as? String == "dropset" { intensityField(L10n.text("DROPS" /* 递减次数 */),key:"count",fallback:1);intensityField(L10n.text("WEIGHT_REDUCTION_PER_DROP" /* 每次减重 % */),key:"pct",fallback:20) }
                            if intensifier["type"] as? String == "restpause" {
                                intensityField(L10n.text("REST_PAUSE_TOTAL_REPS" /* 休息暂停组总次数 */),key:"totalReps",fallback:12);intensityField(L10n.text("REST_BETWEEN_MINI_SETS_SECONDS" /* 小组间休息秒数 */),key:"restSec",fallback:15)
                            }
                        } header: { HStack { Text(L10n.text("DROP_SETS_REST_PAUSE" /* 递减组 / 休息暂停组 */)); Spacer(); ExplanationButton(title: L10n.text("REST_PAUSE" /* 休息暂停组 */), message: L10n.text("GENERATES_WARM_UP_AND_REST_PAUSE_SETS_MINI_SET_REPS_COUNT_TOWARDS" /* 生成热身组和 休息暂停组；小组次数合计为工作组总次数，训练量不重复计算。 */)) } }
                    }
                }
                ProgressionOptions(config:$config,mode:mode,unit:unit)
                if mode != "cardio" && pyramid.isEmpty { Section { Toggle(L10n.text("LAST_SET_TO_FAILURE_AMRAP" /* 最后一组力竭 / AMRAP */),isOn:flag("lastToFailure")) } }
            }.navigationTitle(L10n.text("ADVANCED_SET_TYPES" /* 高级组型 */)).navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button(L10n.text("CANCEL" /* 取消 */)) { dismiss() } };ToolbarItem(placement:.topBarTrailing) { Button(L10n.text("DONE" /* 完成 */)) {
                    inputBuffer.commitAll()
                    do { var c = config;c["mode"] = mode;for key in ["inc","repsMin","setsMax","deloadFactor"] { if let text = c[key] as? String { guard let n = TrainingInput.value(text) else { throw APIError.response(0,L10n.text("COMPLETE_THE_PROGRESSION_PARAMETERS" /* 请填完进阶参数。 */)) };c[key] = n } }; _ = try WebRules.shared.call("validatePersonalConfig",payload:["config":c]);let next = try WebRules.shared.call("advancedConfig",payload:["config":c]) as! [String:Any];save(next);dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("advanced-config-done") } }
                .alert(L10n.text("COULD_NOT_APPLY" /* 无法应用 */),isPresented:Binding(get:{error != nil},set:{if !$0 { error = nil }})) { Button(L10n.text("GOT_IT" /* 知道了 */),role:.cancel) {} } message:{Text(error ?? "")}
        }.tint(GymTheme.green).environment(\.inputCommitBuffer, inputBuffer)
    }
    private func flag(_ key:String)->Binding<Bool>{Binding(get:{config[key] as? Bool ?? false},set:{inputBuffer.commitAll();if $0 { config[key] = true } else { config.removeValue(forKey:key) }})}
    private func field(_ title:String,key:String,fallback:Double)->some View { HStack { Text(title).font(.subheadline);Spacer();BufferedNumberField(title,value:Binding(get:{number(config[key] ?? fallback)},set:{config[key] = max(0,$0)})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:85).accessibilityIdentifier("config-\(key)") } }
    private func intensityField(_ title:String,key:String,fallback:Double)->some View { HStack { Text(title).font(.subheadline);Spacer();BufferedNumberField(title,value:Binding(get:{number(intensifier[key] ?? fallback)},set:{var x = intensifier;x[key] = max(0,$0);config["intensifier"] = x})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:80).accessibilityIdentifier("config-intensity-\(key)") } }
    private func setPyramid(_ key:String,_ index:Int,_ value:Any) { inputBuffer.commitAll(); var list = config[key] as? [Any] ?? Array(repeating:0,count:pyramid.count);while list.count < pyramid.count { list.append(0) };guard list.indices.contains(index) else {return};list[index] = value;config[key] = list }
    private func pyramidField(_ title:String,key:String,i:Int)->some View { HStack { Text(title).font(.caption);Spacer();BufferedNumberField(title,value:Binding(get:{let list = config[key] as? [Any] ?? [];return list.indices.contains(i) ? number(list[i]) : 0},set:{setPyramid(key,i,max(0,$0))})).textFieldStyle(.plain).stableInputLine().submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:80).accessibilityIdentifier("\(key)-\(i)") } }
}
