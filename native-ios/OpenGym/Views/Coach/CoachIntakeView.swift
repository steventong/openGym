import SwiftUI

struct CoachIntakeView: View {
    let session: CoachSession
    let editing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var value: [String: Any]
    private let original: [String: Any]
    private let goals = [("strength","增强力量","更大的重量，较低的次数"),("muscle","增加肌肉","训练量和渐进提升"),("general","全面健身","均衡、可持续的训练"),("fatloss","减少脂肪","减脂同时保持力量"),("endurance","提升耐力","更多次数、较短休息和有氧")]
    private let experience = [("new","刚开始训练","刚接触力量训练"),("returning","恢复训练","有过经验，正在重新建立状态"),("regular","规律训练","已经持续训练一段时间")]
    private let equipment = [("body weight","自重"),("dumbbell","哑铃"),("barbell","杠铃"),("cable","绳索"),("leverage machine","固定器械"),("smith machine","史密斯机"),("kettlebell","壶铃"),("band","弹力带"),("assisted","辅助器械"),("stability ball","健身球"),("medicine ball","药球"),("ez barbell","曲杆杠铃")]
    init(session: CoachSession, editing: Bool) {
        self.session = session; self.editing = editing; original = session.profile
        var value: [String: Any] = ["daysPerWeek":3,"preferredDays":[1,3,5],"sessionMin":60,"equipment":[String](),"limitations":"","likes":"","dislikes":"","notes":""]
        value.merge(session.profile) { _,new in new }; _value = State(initialValue:value)
    }
    private var titles: [String] { ["你为什么训练？","你的训练经验？","每周训练几天？","每次有多少时间？","可以使用什么器械？","有哪些需要注意的限制？","还有什么想告诉教练？"] }
    private var canContinue: Bool { step == 0 ? !value.coachText("goal").isEmpty : step == 1 ? !value.coachText("experience").isEmpty : true }
    var body: some View {
        VStack(spacing:0) {
            HStack { ForEach(0..<7,id:\.self) { index in Capsule().fill(index <= step ? GymTheme.green : GymTheme.card).frame(height:4) } }.padding()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("\(step+1) / 7").font(.caption).foregroundStyle(.secondary)
                    Text(titles[step]).font(.largeTitle.bold())
                    Group {
                        switch step {
                        case 0: choices(goals,key:"goal")
                        case 1: choices(experience,key:"experience")
                        case 2:
                            Stepper("每周 \(Int(number(value["daysPerWeek"]))) 天",value:integer("daysPerWeek"),in:1...7)
                            Text("偏好的训练日（可选）").font(.headline)
                            ForEach(0..<7,id:\.self) { index in
                                let day = (index+1)%7
                                Toggle(CoachCadenceView.days[day],isOn:Binding(get:{ (value["preferredDays"] as? [Int] ?? []).contains(day) },set:{ on in var days = value["preferredDays"] as? [Int] ?? [];days.removeAll{$0==day};if on {days.append(day)};value["preferredDays"] = days.sorted() }))
                            }
                        case 3:
                            Text("包括组间休息，选择你实际能坚持的时间。").foregroundStyle(.secondary)
                            Stepper("每次 \(Int(number(value["sessionMin"]))) 分钟",value:integer("sessionMin"),in:10...235,step:5)
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:110))],spacing:10) { ForEach([30,45,60,90],id:\.self) { min in Pill(title:"\(min) 分钟",selected:Int(number(value["sessionMin"])) == min) { value["sessionMin"] = min } } }
                        case 4:
                            Text("不选表示使用整个动作库。可以选择多种器械。").foregroundStyle(.secondary)
                            ForEach(equipment,id:\.0) { item in Toggle(item.1,isOn:Binding(get:{ (value["equipment"] as? [String] ?? []).contains(item.0) },set:{ on in var items = value["equipment"] as? [String] ?? [];items.removeAll{$0==item.0};if on {items.append(item.0)};value["equipment"] = items })) }
                        case 5:
                            field("伤病、关节不适、不能做的动作或场地限制",key:"limitations",limit:600)
                            Text("若确实存在疼痛，请咨询专业人士。教练可以保守安排训练，但不能诊断。").font(.footnote).foregroundStyle(.orange)
                        default:
                            Text("以下都可以留空。").foregroundStyle(.secondary)
                            field("喜欢的动作",key:"likes",limit:300)
                            field("不喜欢的动作",key:"dislikes",limit:300)
                            field("其他目标或偏好",key:"notes",limit:600)
                        }
                    }
                    if let error = session.error { Text(error).foregroundStyle(.orange).font(.subheadline) }
                }.padding(24)
            }
            HStack(spacing:14) {
                if step > 0 { Button("上一步") { step -= 1 }.padding(.horizontal).disabled(session.busy) }
                CoachPrimaryButton(title:step == 6 ? (editing ? "保存回答" : "让教练设计计划") : "继续") {
                    if step < 6 { step += 1 }
                    else { Task { if await session.saveProfile(value,original:original,create:!editing), editing { dismiss() } } }
                }.disabled(!canContinue || session.locked).accessibilityIdentifier("coach-intake-next")
            }.padding()
        }.navigationTitle(editing ? "训练问答" : "认识你").tint(GymTheme.green)
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
            TextField(title,text:Binding(get:{value.coachText(key)},set:{value[key] = String($0.prefix(limit))}),axis:.vertical).lineLimit(3...6).padding().background(GymTheme.card,in:RoundedRectangle(cornerRadius:14))
            Text("\(value.coachText(key).count) / \(limit)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
