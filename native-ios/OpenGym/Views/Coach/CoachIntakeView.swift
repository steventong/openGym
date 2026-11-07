import SwiftUI

struct CoachIntakeView: View {
    let session: CoachSession
    let editing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var step = 0
    @State private var value: [String: Any]
    private let original: [String: Any]
    private let goals = [("strength",String(localized: "BUILD_STRENGTH", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "HEAVIER_WEIGHTS_FEWER_REPS", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("muscle",String(localized: "BUILD_MUSCLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "TRAINING_VOLUME_AND_GRADUAL_PROGRESSION", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("general",String(localized: "GENERAL_FITNESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "BALANCED_SUSTAINABLE_TRAINING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("fatloss",String(localized: "LOSE_BODY_FAT", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "MAINTAIN_STRENGTH_WHILE_LOSING_FAT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("endurance",String(localized: "BUILD_ENDURANCE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "MORE_REPS_SHORTER_RESTS_AND_CARDIO", bundle: AppLanguage.bundle, locale: AppLanguage.locale))]
    private let experience = [("new",String(localized: "NEW_TO_TRAINING", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "JUST_STARTING_STRENGTH_TRAINING", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("returning",String(localized: "RETURNING_TO_TRAINING", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "EXPERIENCED_REBUILDING_CONSISTENCY", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("regular",String(localized: "TRAINING_REGULARLY", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "ALREADY_TRAINING_CONSISTENTLY", bundle: AppLanguage.bundle, locale: AppLanguage.locale))]
    private let equipment = [("body weight",String(localized: "BODY_WEIGHT_A", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("dumbbell",String(localized: "DUMBBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("barbell",String(localized: "BARBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("cable",String(localized: "CABLE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("leverage machine",String(localized: "WEIGHT_MACHINES", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("smith machine",String(localized: "SMITH_MACHINE", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("kettlebell",String(localized: "KETTLEBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("band",String(localized: "BAND", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("assisted",String(localized: "ASSISTANCE_EQUIPMENT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("stability ball",String(localized: "STABILITY_BALL", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("medicine ball",String(localized: "MEDICINE_BALL", bundle: AppLanguage.bundle, locale: AppLanguage.locale)),("ez barbell",String(localized: "EZ_BARBELL", bundle: AppLanguage.bundle, locale: AppLanguage.locale))]
    init(session: CoachSession, editing: Bool) {
        self.session = session; self.editing = editing; original = session.profile
        var value: [String: Any] = ["daysPerWeek":3,"preferredDays":[1,3,5],"sessionMin":60,"equipment":[String](),"limitations":"","likes":"","dislikes":"","notes":""]
        value.merge(session.profile) { _,new in new }; _value = State(initialValue:value)
    }
    private var titles: [String] { [String(localized: "WHAT_ARE_YOU_TRAINING_FOR", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "WHAT_S_YOUR_TRAINING_EXPERIENCE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "HOW_MANY_DAYS_A_WEEK_CAN_YOU_TRAIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "HOW_MUCH_TIME_DO_YOU_HAVE_PER_SESSION", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "WHAT_EQUIPMENT_CAN_YOU_USE", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "WHAT_LIMITATIONS_SHOULD_WE_CONSIDER", bundle: AppLanguage.bundle, locale: AppLanguage.locale),String(localized: "ANYTHING_ELSE_YOUR_COACH_SHOULD_KNOW", bundle: AppLanguage.bundle, locale: AppLanguage.locale)] }
    private var canContinue: Bool { step == 0 ? !value.coachText("goal").isEmpty : step == 1 ? !value.coachText("experience").isEmpty : true }
    var body: some View {
        VStack(spacing:0) {
            HStack { ForEach(0..<7,id:\.self) { index in Capsule().fill(index <= step ? GymTheme.green : GymTheme.card).frame(height:4) } }.padding()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("\(step+1) / 7").font(.caption).foregroundStyle(.secondary)
                    HStack { Text(titles[step]).font(.largeTitle.bold()); if step == 4 { ExplanationButton(title: String(localized: "EQUIPMENT_SELECTION", bundle: AppLanguage.bundle, locale: AppLanguage.locale), message: String(localized: "CHOOSE_SEVERAL_TYPES_OR_LEAVE_EMPTY_TO_INCLUDE_ALL_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } }
                    Group {
                        switch step {
                        case 0: CoachIntakeChoices(items: goals, selection: answerBinding("goal"))
                        case 1: CoachIntakeChoices(items: experience, selection: answerBinding("experience"))
                        case 2:
                            Stepper(String(format: String(localized: "COUNT_DAYS_PER_WEEK", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(value["daysPerWeek"])))),value:integer("daysPerWeek"),in:1...7)
                            Text("PREFERRED_TRAINING_DAYS_OPTIONAL").font(.headline)
                            ForEach(0..<7,id:\.self) { index in
                                let day = (index+1)%7
                                Toggle(CoachCadenceView.days[day],isOn:Binding(get:{ (value["preferredDays"] as? [Int] ?? []).contains(day) },set:{ on in var days = value["preferredDays"] as? [Int] ?? [];days.removeAll{$0==day};if on {days.append(day)};value["preferredDays"] = days.sorted() }))
                            }
                        case 3:
                            Stepper(String(format: String(localized: "COUNT_MINUTES_PER_SESSION_INCLUDING_REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(value["sessionMin"])))),value:integer("sessionMin"),in:10...235,step:5)
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:110))],spacing:10) { ForEach([30,45,60,90],id:\.self) { min in Pill(title:String(format: String(localized: "COUNT_MIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: min)),selected:Int(number(value["sessionMin"])) == min) { value["sessionMin"] = min } } }
                        case 4:
                            ForEach(equipment,id:\.0) { item in Toggle(item.1,isOn:Binding(get:{ (value["equipment"] as? [String] ?? []).contains(item.0) },set:{ on in var items = value["equipment"] as? [String] ?? [];items.removeAll{$0==item.0};if on {items.append(item.0)};value["equipment"] = items })) }
                        case 5:
                            CoachIntakeTextField(title: String(localized: "INJURIES_JOINT_DISCOMFORT_EXERCISES_TO_AVOID_OR_SPACE_LIMITATIONS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: answerBinding("limitations", limit: 600), limit: 600)
                        default:
                            CoachIntakeTextField(title: String(localized: "EXERCISES_YOU_ENJOY", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: answerBinding("likes", limit: 300), limit: 300)
                            CoachIntakeTextField(title: String(localized: "EXERCISES_YOU_DISLIKE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: answerBinding("dislikes", limit: 300), limit: 300)
                            CoachIntakeTextField(title: String(localized: "OTHER_GOALS_OR_PREFERENCES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: answerBinding("notes", limit: 600), limit: 600)
                        }
                    }
                }.padding(24)
            }
            HStack(spacing:14) {
                if step > 0 { Button("BACK_A") { inputBuffer.commitAll(); step -= 1 }.padding(.horizontal).disabled(session.busy) }
                CoachPrimaryButton(title:step == 6 ? (editing ? String(localized: "SAVE_ANSWERS", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "ASK_COACH_TO_BUILD_A_PLAN", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) : String(localized: "RESUME", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    inputBuffer.commitAll()
                    if step < 6 { step += 1 }
                    else { Task { if await session.saveProfile(value,original:original,create:!editing), editing { dismiss() } } }
                }.disabled(!canContinue || session.locked).accessibilityIdentifier("coach-intake-next")
            }.padding()
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert(Binding(get: { session.error }, set: { session.error = $0 })).navigationTitle(editing ? String(localized: "TRAINING_QUESTIONNAIRE", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "GETTING_TO_KNOW_YOU", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tint(GymTheme.green)
    }
    private func integer(_ key: String) -> Binding<Int> { Binding(get:{Int(number(value[key]))},set:{value[key] = $0}) }
    private func answerBinding(_ key: String, limit: Int? = nil) -> Binding<String> {
        Binding(get: { value.coachText(key) }, set: { text in
            value[key] = limit.map { String(text.prefix($0)) } ?? text
        })
    }
}
