import SwiftUI
struct LibraryView: View {
    @Environment(GymStore.self) private var store
    @State private var query = ""
    @State private var bodyPart = ""
    @State private var equipment = ""
    @State private var grid = false
    @State private var limit = 60
    @State private var available:Set<String>?
    @State private var favouritesOnly = false
    @State private var trainedOnly = false
    @State private var customOnly = false
    @State private var createCustom = false
    private let bodyParts = ["", "back", "cardio", "chest", "full body", "lower arms", "lower legs", "neck", "shoulders", "upper arms", "upper legs", "waist"]
    private var results: [Exercise] {
        let favourites = store.favouriteIDs, customs = customIDs
        let trained = trainedOnly ? store.trainedExerciseIDs : []
        let matching = store.exercises.filter { (available == nil || available!.contains($0.id)) && (!favouritesOnly || favourites.contains($0.id)) && (!trainedOnly || trained.contains($0.id)) && (!customOnly || customs.contains($0.id)) && (bodyPart.isEmpty || $0.bodyPart == bodyPart) && (equipment.isEmpty || $0.equipment == equipment) && (query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query)) }
        return matching.filter {favourites.contains($0.id)} + matching.filter {!favourites.contains($0.id)}
    }
    private var customIDs:Set<String> { Set(store.customExercises.compactMap {$0["id"] as? String}) }
    private var equipments: [String] { [""] + Set(store.exercises.filter { bodyPart.isEmpty || $0.bodyPart == bodyPart }.map(\.equipment)).sorted() }
    var body: some View {
        let results = results
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("EXERCISES").font(.system(size:34,weight:.bold))
                        Text(String(format: String(localized: "COUNT_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: store.exercises.count))).font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                    Spacer()
                    if let error = store.catalogueError { StatusDetailButton(title: "COULD_NOT_LOAD", message: "\(error)", warning: true) }
                }
                HStack(spacing:10) {
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(GymTheme.muted)
                        ExerciseSearchField("SEARCH_EXERCISES_MUSCLES",text:$query).onSubmit { GymKeyboard.dismiss() }.textFieldStyle(.plain).font(.system(size:15)).autocorrectionDisabled().accessibilityIdentifier("exercise-search")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.gray) }.accessibilityLabel("CLEAR_SEARCH") }
                    }.padding(.horizontal,14).frame(height:48).background(Color(white:0.16),in:RoundedRectangle(cornerRadius:14))
                    Button { grid.toggle() } label: { Image(systemName:grid ? "list.bullet" : "square.grid.2x2").frame(width:48,height:48).background(GymTheme.card,in:RoundedRectangle(cornerRadius:14)) }.accessibilityLabel(LocalizedStringKey(grid ? "LIST_VIEW" : "CARD_VIEW"))
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) { ForEach(bodyParts,id:\.self) { item in Pill(title:item.isEmpty ? "ALL" : "\(String(localized: String.LocalizationValue(item), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale))",selected:bodyPart == item) { bodyPart = item; equipment = "" } } }
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) { ForEach(equipments,id:\.self) { item in Pill(title:item.isEmpty ? "ANY_EQUIPMENT" : "\(String(localized: String.LocalizationValue(item), table: "Vocabulary", bundle: AppLanguage.bundle, locale: AppLanguage.locale))",selected:equipment == item) { equipment = item } } }
                }
                HStack {
                    Pill(title:"FAVOURITES",selected:favouritesOnly) { favouritesOnly.toggle();limit = 60 }
                    Pill(title:"PREVIOUSLY_TRAINED",selected:trainedOnly) { trainedOnly.toggle();limit = 60 }
                    Pill(title:"CUSTOM",selected:customOnly) { customOnly.toggle();limit = 60 }
                    Spacer()
                    Button { createCustom = true } label: { Label("CREATE",systemImage:"plus") }.accessibilityIdentifier("create-custom-exercise")
                }
                HStack { Text(query.isEmpty && bodyPart.isEmpty && equipment.isEmpty && !favouritesOnly && !trainedOnly && !customOnly ? String(localized: "EXPLORE_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(format: String(localized: "COUNT_EXERCISES_FOUND", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: results.count))).font(.caption).foregroundStyle(GymTheme.muted); Spacer(); Label("EXERCISES",systemImage:"checkmark.seal").font(.caption2).foregroundStyle(GymTheme.muted) }
                if results.isEmpty {
                    EmptyCard(icon:"magnifyingglass",title:"NO_EXERCISES_FOUND")
                    Button("CLEAR_SEARCH_AND_FILTERS") { query = ""; bodyPart = ""; equipment = ""; favouritesOnly = false; trainedOnly = false; customOnly = false }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                LazyVGrid(columns:grid ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.flexible())],spacing:10) {
                    ForEach(Array(results.prefix(limit))) { exercise in
                        Button { store.selectedExercise = exercise } label: {
                            if grid {
                                VStack(alignment:.leading,spacing:12) {
                                    ExerciseThumbnail(id:exercise.id,size:130).frame(maxWidth:.infinity)
                                    Text(exercise.name).font(.system(size:14,weight:.medium)).lineLimit(2)
                                    Text(exercise.targetLabel).font(.caption).foregroundStyle(GymTheme.muted)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(GymTheme.card,in:RoundedRectangle(cornerRadius:16))
                            } else { ExerciseRow(exercise:exercise) }
                        }.buttonStyle(.plain).accessibilityIdentifier("exercise-\(exercise.id)")
                            .contextMenu { Button(LocalizedStringKey(store.favouriteIDs.contains(exercise.id) ? "REMOVE_FROM_FAVOURITES":"FAVOURITES")) { Task { _ = await store.setFavourite(exercise.id,enabled:!store.favouriteIDs.contains(exercise.id)) } } }
                    }
                    if results.count > limit { ExercisePageTrigger(limit: $limit, total: results.count).id(limit) }
                }
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively)
            .onAppear { refreshEquipment() }.onChange(of:store.lastSync) {_,_ in refreshEquipment()}
            .sheet(isPresented:$createCustom) { CustomExerciseEditor() }
            .onChange(of:query) { _, _ in limit = 60 }.onChange(of:bodyPart) { _, _ in limit = 60 }.onChange(of:equipment) { _, _ in limit = 60 }
    }
    private func refreshEquipment() {
        if store.state["equipFilterOn"] as? Bool == true {
            available = ((try? store.personalInfo("equipment"))?["available"] as? [String]).map { Set($0) }
        } else { available = nil }
    }
}
/// Keep the trigger inside a lazy container so it loads only when the end is reached.
struct ExercisePageTrigger: View {
    @Binding var limit: Int
    let total: Int
    var body: some View {
        Color.clear.frame(height: 1)
            .accessibilityHidden(true)
            .onAppear { limit = min(limit + 60, total) }
    }
}
struct ExerciseRow: View {
    let exercise: Exercise
    var accessoryIcon = "chevron.right"
    var body: some View {
        HStack(spacing:12) {
            ExerciseThumbnail(id:exercise.id)
            VStack(alignment:.leading,spacing:5) {
                Text(exercise.name).font(.system(size:15,weight:.medium)).foregroundStyle(.white).lineLimit(2)
                Text(String(format: String(localized: "EXERCISE_TARGET_AND_EQUIPMENT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, exercise.targetLabel, exercise.equipmentLabel)).font(.system(size:12)).foregroundStyle(GymTheme.muted)
            }
            Spacer(minLength:0)
            Image(systemName:accessoryIcon).font(.system(size:11,weight:.semibold)).foregroundStyle(GymTheme.muted).accessibilityHidden(true)
        }.padding(12).background(GymTheme.card,in:RoundedRectangle(cornerRadius:16))
    }
}
