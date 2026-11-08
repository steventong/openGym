import SwiftUI

struct CoachIntakeView: View {
    let session: CoachSession
    let editing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer = InputCommitBuffer()
    @State private var step = 0
    @State private var value: [String: Any]
    private let original: [String: Any]
    private let goals: [(String, LocalizedStringKey, LocalizedStringKey)] = [("strength","BUILD_STRENGTH","HEAVIER_WEIGHTS_FEWER_REPS"),("muscle","BUILD_MUSCLE","TRAINING_VOLUME_AND_GRADUAL_PROGRESSION"),("general","GENERAL_FITNESS","BALANCED_SUSTAINABLE_TRAINING"),("fatloss","LOSE_BODY_FAT","MAINTAIN_STRENGTH_WHILE_LOSING_FAT"),("endurance","BUILD_ENDURANCE","MORE_REPS_SHORTER_RESTS_AND_CARDIO")]
    private let experience: [(String, LocalizedStringKey, LocalizedStringKey)] = [("new","NEW_TO_TRAINING","JUST_STARTING_STRENGTH_TRAINING"),("returning","RETURNING_TO_TRAINING","EXPERIENCED_REBUILDING_CONSISTENCY"),("regular","TRAINING_REGULARLY","ALREADY_TRAINING_CONSISTENTLY")]
    private let equipment: [(String, LocalizedStringKey)] = [("body weight","BODY_WEIGHT_A"),("dumbbell","DUMBBELL"),("barbell","BARBELL"),("cable","CABLE"),("leverage machine","WEIGHT_MACHINES"),("smith machine","SMITH_MACHINE"),("kettlebell","KETTLEBELL"),("band","BAND"),("assisted","ASSISTANCE_EQUIPMENT"),("stability ball","STABILITY_BALL"),("medicine ball","MEDICINE_BALL"),("ez barbell","EZ_BARBELL")]
    init(session: CoachSession, editing: Bool) {
        self.session = session; self.editing = editing; original = session.profile
        var value: [String: Any] = ["daysPerWeek":3,"preferredDays":[1,3,5],"sessionMin":60,"equipment":[String](),"limitations":"","likes":"","dislikes":"","notes":""]
        value.merge(session.profile) { _,new in new }; _value = State(initialValue:value)
    }
    private var titles: [LocalizedStringKey] { ["WHAT_ARE_YOU_TRAINING_FOR","WHAT_S_YOUR_TRAINING_EXPERIENCE","HOW_MANY_DAYS_A_WEEK_CAN_YOU_TRAIN","HOW_MUCH_TIME_DO_YOU_HAVE_PER_SESSION","WHAT_EQUIPMENT_CAN_YOU_USE","WHAT_LIMITATIONS_SHOULD_WE_CONSIDER","ANYTHING_ELSE_YOUR_COACH_SHOULD_KNOW"] }
    private var canContinue: Bool { step == 0 ? !value.coachText("goal").isEmpty : step == 1 ? !value.coachText("experience").isEmpty : true }
    var body: some View {
        let days = CoachCadenceView.days.map { String(localized: $0, bundle: AppLanguage.bundle, locale: AppLanguage.locale) }

        VStack(spacing:0) {
            HStack { ForEach(0..<7,id:\.self) { index in Capsule().fill(index <= step ? GymTheme.green : GymTheme.card).frame(height:4) } }.padding()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text(String(format: String(localized: "COACH_INTAKE_PROGRESS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(step + 1), String(titles.count))).font(.caption).foregroundStyle(.secondary)
                    HStack { Text(titles[step]).font(.largeTitle.bold()); if step == 4 { ExplanationButton(title: "EQUIPMENT_SELECTION", message: "CHOOSE_SEVERAL_TYPES_OR_LEAVE_EMPTY_TO_INCLUDE_ALL_EXERCISES") } }
                    Group {
                        switch step {
                        case 0: CoachIntakeChoices(items: goals, selection: answerBinding("goal"))
                        case 1: CoachIntakeChoices(items: experience, selection: answerBinding("experience"))
                        case 2:
                            Stepper(String(format: String(localized: "COUNT_DAYS_PER_WEEK", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(value["daysPerWeek"])))),value:integer("daysPerWeek"),in:1...7)
                            Text("PREFERRED_TRAINING_DAYS_OPTIONAL").font(.headline)
                            ForEach(0..<7,id:\.self) { index in
                                let day = (index+1)%7
                                Toggle(days[day],isOn:Binding(get:{ (value["preferredDays"] as? [Int] ?? []).contains(day) },set:{ on in var days = value["preferredDays"] as? [Int] ?? [];days.removeAll{$0==day};if on {days.append(day)};value["preferredDays"] = days.sorted() }))
                            }
                        case 3:
                            Stepper(String(format: String(localized: "COUNT_MINUTES_PER_SESSION_INCLUDING_REST", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(value["sessionMin"])))),value:integer("sessionMin"),in:10...235,step:5)
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:110))],spacing:10) { ForEach([30,45,60,90],id:\.self) { min in Pill(title:"\(String(format: String(localized: "COUNT_MIN", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: min)))",selected:Int(number(value["sessionMin"])) == min) { value["sessionMin"] = min } } }
                        case 4:
                            ForEach(equipment,id:\.0) { item in Toggle(item.1,isOn:Binding(get:{ (value["equipment"] as? [String] ?? []).contains(item.0) },set:{ on in var items = value["equipment"] as? [String] ?? [];items.removeAll{$0==item.0};if on {items.append(item.0)};value["equipment"] = items })) }
                        case 5:
                            CoachIntakeTextField(title: "INJURIES_JOINT_DISCOMFORT_EXERCISES_TO_AVOID_OR_SPACE_LIMITATIONS", text: answerBinding("limitations", limit: 600), limit: 600)
                        default:
                            CoachIntakeTextField(title: "EXERCISES_YOU_ENJOY", text: answerBinding("likes", limit: 300), limit: 300)
                            CoachIntakeTextField(title: "EXERCISES_YOU_DISLIKE", text: answerBinding("dislikes", limit: 300), limit: 300)
                            CoachIntakeTextField(title: "OTHER_GOALS_OR_PREFERENCES", text: answerBinding("notes", limit: 600), limit: 600)
                        }
                    }
                }.padding(24)
            }
            HStack(spacing:14) {
                if step > 0 { Button("BACK_A") { inputBuffer.commitAll(); step -= 1 }.padding(.horizontal).disabled(session.busy) }
                CoachPrimaryButton(title:step == 6 ? (editing ? "SAVE_ANSWERS" : "ASK_COACH_TO_BUILD_A_PLAN") : "RESUME") {
                    inputBuffer.commitAll()
                    if step < 6 { step += 1 }
                    else { Task { if await session.saveProfile(value,original:original,create:!editing), editing { dismiss() } } }
                }.disabled(!canContinue || session.locked).accessibilityIdentifier("coach-intake-next")
            }.padding()
        }.environment(\.inputCommitBuffer, inputBuffer).operationAlert(Binding(get: { session.error }, set: { session.error = $0 })).navigationTitle(LocalizedStringKey(editing ? "TRAINING_QUESTIONNAIRE" : "GETTING_TO_KNOW_YOU")).tint(GymTheme.green)
    }
    private func integer(_ key: String) -> Binding<Int> { Binding(get:{Int(number(value[key]))},set:{value[key] = $0}) }
    private func answerBinding(_ key: String, limit: Int? = nil) -> Binding<String> {
        Binding(get: { value.coachText(key) }, set: { text in
            value[key] = limit.map { String(text.prefix($0)) } ?? text
        })
    }
}
