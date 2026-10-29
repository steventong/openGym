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
    @State private var customOnly = false
    @State private var createCustom = false
    private let bodyParts = ["", "back", "cardio", "chest", "full body", "lower arms", "lower legs", "neck", "shoulders", "upper arms", "upper legs", "waist"]
    private var results: [Exercise] {
        let favourites = store.favouriteIDs, customs = customIDs
        let matching = store.exercises.filter { (available == nil || available!.contains($0.id)) && (!favouritesOnly || favourites.contains($0.id)) && (!customOnly || customs.contains($0.id)) && (bodyPart.isEmpty || $0.bodyPart == bodyPart) && (equipment.isEmpty || $0.equipment == equipment) && (query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query)) }
        return matching.filter {favourites.contains($0.id)} + matching.filter {!favourites.contains($0.id)}
    }
    private var customIDs:Set<String> { Set(store.customExercises.compactMap {$0["id"] as? String}) }
    private var equipments: [String] { [""] + Set(store.exercises.filter { bodyPart.isEmpty || $0.bodyPart == bodyPart }.map(\.equipment)).sorted() }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("动作库").font(.system(size:34,weight:.bold))
                        Text("\(store.exercises.count) 个动作").font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                    Spacer()
                    Button { store.showSettings = true } label: { Image(systemName:"slider.horizontal.3").font(.system(size:20)).foregroundStyle(GymTheme.green).padding(12).background(GymTheme.green.opacity(0.12),in:RoundedRectangle(cornerRadius:12)) }.accessibilityLabel("服务设置")
                }
                HStack(spacing:10) {
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(GymTheme.muted)
                        TextField("搜索动作、肌群…",text:$query).font(.system(size:15)).autocorrectionDisabled().accessibilityIdentifier("exercise-search")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.gray) }.accessibilityLabel("清除搜索") }
                    }.padding(14).background(Color(white:0.16),in:RoundedRectangle(cornerRadius:14))
                    Button { grid.toggle() } label: { Image(systemName:grid ? "list.bullet" : "square.grid.2x2").frame(width:48,height:48).background(GymTheme.card,in:RoundedRectangle(cornerRadius:14)) }.accessibilityLabel(grid ? "列表视图" : "卡片视图")
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) { ForEach(bodyParts,id:\.self) { item in Pill(title:item.isEmpty ? "全部" : Vocabulary.label(item),selected:bodyPart == item) { bodyPart = item; equipment = "" } } }
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) { ForEach(equipments,id:\.self) { item in Pill(title:item.isEmpty ? "所有器械" : Vocabulary.label(item),selected:equipment == item) { equipment = item } } }
                }
                HStack {
                    Pill(title:"收藏",selected:favouritesOnly) { favouritesOnly.toggle();limit = 60 }
                    Pill(title:"自定义",selected:customOnly) { customOnly.toggle();limit = 60 }
                    Spacer()
                    Button { createCustom = true } label: { Label("创建",systemImage:"plus") }.accessibilityIdentifier("create-custom-exercise")
                }
                if let error = store.catalogueError { Text(error).foregroundStyle(.orange) }
                HStack { Text(query.isEmpty && bodyPart.isEmpty && equipment.isEmpty ? "探索动作" : "找到 \(results.count) 个动作").font(.caption).foregroundStyle(GymTheme.muted); Spacer(); Label("动作库",systemImage:"checkmark.seal").font(.caption2).foregroundStyle(GymTheme.muted) }
                if results.isEmpty { EmptyCard(icon:"magnifyingglass",title:"没有找到动作",detail:"试试其他关键词，或清除肌群、器械筛选。") }
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
                            .contextMenu { Button(store.favouriteIDs.contains(exercise.id) ? "取消收藏":"收藏") { Task { _ = await store.setFavourite(exercise.id,enabled:!store.favouriteIDs.contains(exercise.id)) } } }
                    }
                }
                if results.count > limit { Button("显示更多") { limit += 60 }.frame(maxWidth:.infinity).padding() }
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
struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        HStack(spacing:12) {
            ExerciseThumbnail(id:exercise.id)
            VStack(alignment:.leading,spacing:5) {
                Text(exercise.name).font(.system(size:15,weight:.medium)).foregroundStyle(.white).lineLimit(2)
                Text("\(exercise.targetLabel) · \(exercise.equipmentLabel)").font(.system(size:12)).foregroundStyle(GymTheme.muted)
            }
            Spacer(minLength:0)
            Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(GymTheme.muted)
        }.padding(12).background(GymTheme.card,in:RoundedRectangle(cornerRadius:16))
    }
}
