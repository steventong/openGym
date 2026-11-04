import SwiftUI

struct CoachIntakeView: View {
    let session: CoachSession
    let editing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var step = 0
    @State private var value: [String: Any]
    private let original: [String: Any]
    private let goals = [("strength",L10n.text("BUILD_STRENGTH" /* 增强力量 */),L10n.text("HEAVIER_WEIGHTS_FEWER_REPS" /* 更大的重量，较低的次数 */)),("muscle",L10n.text("BUILD_MUSCLE" /* 增肌 */),L10n.text("TRAINING_VOLUME_AND_GRADUAL_PROGRESSION" /* 训练量和渐进提升 */)),("general",L10n.text("GENERAL_FITNESS" /* 综合体能 */),L10n.text("BALANCED_SUSTAINABLE_TRAINING" /* 均衡、可持续的训练。 */)),("fatloss",L10n.text("LOSE_BODY_FAT" /* 减少脂肪 */),L10n.text("MAINTAIN_STRENGTH_WHILE_LOSING_FAT" /* 减脂同时保持力量 */)),("endurance",L10n.text("BUILD_ENDURANCE" /* 提升耐力 */),L10n.text("MORE_REPS_SHORTER_RESTS_AND_CARDIO" /* 更多次数、较短休息和有氧 */))]
    private let experience = [("new",L10n.text("NEW_TO_TRAINING" /* 刚开始训练 */),L10n.text("JUST_STARTING_STRENGTH_TRAINING" /* 刚接触力量训练 */)),("returning",L10n.text("RETURNING_TO_TRAINING" /* 恢复训练 */),L10n.text("EXPERIENCED_REBUILDING_CONSISTENCY" /* 有过经验，正在重新建立状态 */)),("regular",L10n.text("TRAINING_REGULARLY" /* 规律训练中 */),L10n.text("ALREADY_TRAINING_CONSISTENTLY" /* 已经持续训练一段时间 */))]
    private let equipment = [("body weight",L10n.text("BODY_WEIGHT_A" /* 自重 */)),("dumbbell",L10n.text("DUMBBELL" /* 哑铃 */)),("barbell",L10n.text("BARBELL" /* 杠铃 */)),("cable",L10n.text("CABLE" /* 绳索 */)),("leverage machine",L10n.text("WEIGHT_MACHINES" /* 固定器械 */)),("smith machine",L10n.text("SMITH_MACHINE" /* 史密斯机 */)),("kettlebell",L10n.text("KETTLEBELL" /* 壶铃 */)),("band",L10n.text("BAND" /* 弹力带 */)),("assisted",L10n.text("ASSISTANCE_EQUIPMENT" /* 辅助器械 */)),("stability ball",L10n.text("STABILITY_BALL" /* 健身球 */)),("medicine ball",L10n.text("MEDICINE_BALL" /* 药球 */)),("ez barbell",L10n.text("EZ_BARBELL" /* 曲杆杠铃 */))]
    init(session: CoachSession, editing: Bool) {
        self.session = session; self.editing = editing; original = session.profile
        var value: [String: Any] = ["daysPerWeek":3,"preferredDays":[1,3,5],"sessionMin":60,"equipment":[String](),"limitations":"","likes":"","dislikes":"","notes":""]
        value.merge(session.profile) { _,new in new }; _value = State(initialValue:value)
    }
    private var titles: [String] { [L10n.text("WHAT_ARE_YOU_TRAINING_FOR" /* 你的训练目标是什么？ */),L10n.text("WHAT_S_YOUR_TRAINING_EXPERIENCE" /* 你的训练经验？ */),L10n.text("HOW_MANY_DAYS_A_WEEK_CAN_YOU_TRAIN" /* 每周训练几天？ */),L10n.text("HOW_MUCH_TIME_DO_YOU_HAVE_PER_SESSION" /* 每次有多少时间？ */),L10n.text("WHAT_EQUIPMENT_CAN_YOU_USE" /* 可以使用什么器械？ */),L10n.text("WHAT_LIMITATIONS_SHOULD_WE_CONSIDER" /* 有哪些需要注意的限制？ */),L10n.text("ANYTHING_ELSE_YOUR_COACH_SHOULD_KNOW" /* 还有什么想告诉教练？ */)] }
    private var canContinue: Bool { step == 0 ? !value.coachText("goal").isEmpty : step == 1 ? !value.coachText("experience").isEmpty : true }
    var body: some View {
        VStack(spacing:0) {
            HStack { ForEach(0..<7,id:\.self) { index in Capsule().fill(index <= step ? GymTheme.green : GymTheme.card).frame(height:4) } }.padding()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("\(step+1) / 7").font(.caption).foregroundStyle(.secondary)
                    HStack { Text(titles[step]).font(.largeTitle.bold()); if step == 4 { ExplanationButton(title: L10n.text("EQUIPMENT_SELECTION" /* 器械范围 */), message: L10n.text("CHOOSE_SEVERAL_TYPES_OR_LEAVE_EMPTY_TO_INCLUDE_ALL_EXERCISES" /* 不选时使用全部动作；可选择多种器械。 */)) } }
                    Group {
                        switch step {
                        case 0: choices(goals,key:"goal")
                        case 1: choices(experience,key:"experience")
                        case 2:
                            Stepper(L10n.text("COUNT_DAYS_PER_WEEK" /* 每周 {0} 天 */, Int(number(value["daysPerWeek"]))),value:integer("daysPerWeek"),in:1...7)
                            Text(L10n.text("PREFERRED_TRAINING_DAYS_OPTIONAL" /* 偏好的训练日（可选） */)).font(.headline)
                            ForEach(0..<7,id:\.self) { index in
                                let day = (index+1)%7
                                Toggle(CoachCadenceView.days[day],isOn:Binding(get:{ (value["preferredDays"] as? [Int] ?? []).contains(day) },set:{ on in var days = value["preferredDays"] as? [Int] ?? [];days.removeAll{$0==day};if on {days.append(day)};value["preferredDays"] = days.sorted() }))
                            }
                        case 3:
                            Stepper(L10n.text("COUNT_MINUTES_PER_SESSION_INCLUDING_REST" /* 每次 {0} 分钟（含休息） */, Int(number(value["sessionMin"]))),value:integer("sessionMin"),in:10...235,step:5)
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:110))],spacing:10) { ForEach([30,45,60,90],id:\.self) { min in Pill(title:L10n.text("COUNT_MIN" /* {0} 分钟 */, min),selected:Int(number(value["sessionMin"])) == min) { value["sessionMin"] = min } } }
                        case 4:
                            ForEach(equipment,id:\.0) { item in Toggle(item.1,isOn:Binding(get:{ (value["equipment"] as? [String] ?? []).contains(item.0) },set:{ on in var items = value["equipment"] as? [String] ?? [];items.removeAll{$0==item.0};if on {items.append(item.0)};value["equipment"] = items })) }
                        case 5:
                            field(L10n.text("INJURIES_JOINT_DISCOMFORT_EXERCISES_TO_AVOID_OR_SPACE_LIMITATIONS" /* 伤病、关节不适、不能做的动作或场地限制 */),key:"limitations",limit:600)
                        default:
                            field(L10n.text("EXERCISES_YOU_ENJOY" /* 喜欢的动作 */),key:"likes",limit:300)
                            field(L10n.text("EXERCISES_YOU_DISLIKE" /* 不喜欢的动作 */),key:"dislikes",limit:300)
                            field(L10n.text("OTHER_GOALS_OR_PREFERENCES" /* 其他目标或偏好 */),key:"notes",limit:600)
                        }
                    }
                }.padding(24)
            }
            HStack(spacing:14) {
                if step > 0 { Button(L10n.text("BACK_A" /* 返回 */)) { inputBuffer.commitAll(); step -= 1 }.padding(.horizontal).disabled(session.busy) }
                CoachPrimaryButton(title:step == 6 ? (editing ? L10n.text("SAVE_ANSWERS" /* 保存回答 */) : L10n.text("ASK_COACH_TO_BUILD_A_PLAN" /* 让教练设计计划 */)) : L10n.text("RESUME" /* 继续 */)) {
                    inputBuffer.commitAll()
                    if step < 6 { step += 1 }
                    else { Task { if await session.saveProfile(value,original:original,create:!editing), editing { dismiss() } } }
                }.disabled(!canContinue || session.locked).accessibilityIdentifier("coach-intake-next")
            }.padding()
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert(Binding(get: { session.error }, set: { session.error = $0 })).navigationTitle(editing ? L10n.text("TRAINING_QUESTIONNAIRE" /* 训练问答 */) : L10n.text("GETTING_TO_KNOW_YOU" /* 认识你 */)).tint(GymTheme.green)
    }
    private func integer(_ key: String) -> Binding<Int> { Binding(get:{Int(number(value[key]))},set:{value[key] = $0}) }
    private func choices(_ items: [(String,String,String)], key: String) -> some View {
        VStack(spacing:12) {
            ForEach(items,id:\.0) { item in
                Button { value[key] = item.0 } label: {
                    HStack {
                        VStack(alignment:.leading,spacing:6) { Text(item.1).font(.headline);Text(item.2).font(.subheadline).foregroundStyle(.secondary) }
                        Spacer();Image(systemName:value.coachText(key) == item.0 ? "checkmark.circle.fill" : "circle").foregroundStyle(GymTheme.green)
                    }.frame(maxWidth:.infinity,alignment:.leading).gymCard()
                }.buttonStyle(.plain).accessibilityIdentifier("coach-answer-"+item.0)
            }
        }
    }
    private func field(_ title: String,key: String,limit: Int) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.headline)
            BufferedTextField(title,text:Binding(get:{value.coachText(key)},set:{value[key] = String($0.prefix(limit))}),axis:.vertical).textFieldStyle(.plain).submitLabel(.done).onSubmit { GymKeyboard.dismiss() }.lineLimit(3...6).padding().background(GymTheme.card,in:RoundedRectangle(cornerRadius:14))
            Text("\(value.coachText(key).count) / \(limit)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
