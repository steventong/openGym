import SwiftUI
import UniformTypeIdentifiers

struct GymJSONDocument:FileDocument {
    static var readableContentTypes:[UTType] { [.json] }
    var data:Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws { guard let data = configuration.file.regularFileContents else { throw APIError.invalidResponse };self.data = data }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct PlanToolsView:View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDoc = GymJSONDocument(data:Data())
    @State private var bundle:[String:Any]?
    @State private var preparedOriginal:[String:Any]?
    @State private var preparedProposed:[String:Any]?
    @State private var applySchedule = false
    @State private var expectedUnit = "kg"
    @State private var issue:String?
    @State private var notice:String?
    @State private var loaded = false
    private let templates = [("ppl","推 / 拉 / 腿 · 每周 3 天"),("upper-lower","上肢 / 下肢 · 每周 4 天"),("full-body","全身训练 · 每周 3 天"),("5x5","5 × 5 力量训练 · 每周 3 天")]
    var body:some View {
        NavigationStack {
            List {
                Section("计划文件") {
                    Button("导出全部计划") { exportPlan() }.disabled(store.routines.isEmpty)
                    Button("导入 openGym 计划") { importing = true }
                }
                Section("入门模板") {
                    ForEach(templates,id:\.0) { id,name in Button(name) { loadTemplate(id) } }
                }
                if let bundle {
                    Section("导入预览") {
                        ForEach(Array((bundle["routines"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) { _,r in
                            VStack(alignment:.leading) { Text(r["name"] as? String ?? "训练");Text("\((r["ex"] as? [Any] ?? []).count) 个动作").font(.caption).foregroundStyle(.secondary) }
                        }
                        if number(bundle["dropped"])>0 { Text("\(Int(number(bundle["dropped"]))) 个无法识别的动作已排除。").foregroundStyle(.orange) }
                        Toggle("采用导入的每周排期",isOn:$applySchedule).disabled(preparedProposed != nil)
                        Text("计划作为新副本添加。勾选排期将替换当前每周安排；单日安排保留。重量自动换算为 \(expectedUnit)。").font(.caption).foregroundStyle(.secondary)
                        Button(store.syncing ? "保存中…":"确认导入") { apply() }.disabled(store.syncing || (bundle["routines"] as? [Any] ?? []).isEmpty).accessibilityIdentifier("confirm-plan-import")
                        Button("取消导入",role:.cancel) { self.bundle = nil;preparedOriginal = nil;preparedProposed = nil }
                    }
                }
                if let issue { Text(issue).foregroundStyle(.orange) }
                if let notice { Text(notice).foregroundStyle(GymTheme.green) }
            }.navigationTitle("计划工具").toolbar { ToolbarItem(placement:.topBarTrailing) {Button("完成"){dismiss()}} }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
                        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size <= 10_000_000 else { throw APIError.response(0,"计划文件过大（上限 10 MB）。") }
                        let data = try Data(contentsOf:url);guard let text = String(data:data,encoding:.utf8) else{throw APIError.invalidResponse}
                        bundle = try store.personalInfo("parsePlan",["raw":text]);expectedUnit = store.unit;preparedOriginal = nil;preparedProposed = nil;issue = nil;notice = nil
                    } catch { issue = error.localizedDescription }
                }
                .fileExporter(isPresented:$exporting,document:exportDoc,contentType:.json,defaultFilename:"openGym-plan-\(dayString())") { result in if case .failure(let e) = result { issue = e.localizedDescription } }
        }
    }
    private func loadTemplate(_ id:String) {
        do {
            let built = try store.personalInfo("starter",["id":id]), routines = built["routines"] as? [[String:Any]] ?? []
            var week:[String:Any] = [:]
            for item in built["schedule"] as? [[String:Any]] ?? [] { week[String(Int(number(item["day"])))] = [item["routineId"] as? String ?? ""] }
            bundle = ["routines":routines,"week":week,"customEx":[],"unit":store.unit,"name":"入门训练"]
            expectedUnit = store.unit;preparedOriginal = nil;preparedProposed = nil;issue = nil;notice = nil
        } catch { issue = error.localizedDescription }
    }
    private func exportPlan() { do {
        let bundle = try store.personalInfo("exportPlan",["name":store.userName ?? "openGym"])
        exportDoc = GymJSONDocument(data:try JSONSerialization.data(withJSONObject:bundle,options:[.prettyPrinted,.sortedKeys]));exporting = true
    } catch {issue = error.localizedDescription} }
    private func apply() {
        guard let bundle else{return}
        do {
            if preparedProposed == nil {
                let baseline = store.state
                let next = try WebRules.shared.call("personalChange",payload:["action":"importPlan","state":baseline,"bundle":bundle,"schedule":applySchedule]) as! [String:Any]
                let keys = ["routines","customEx"]+(applySchedule ? ["week"]:[])
                preparedOriginal = baseline.filter {keys.contains($0.key)};preparedProposed = next.filter {keys.contains($0.key)}
            }
            guard let original = preparedOriginal, let proposed = preparedProposed else{return}
            Task { if await store.savePersonalFields(original:original,proposed:proposed,unit:expectedUnit) { notice = "已导入计划。";self.bundle = nil;preparedOriginal = nil;preparedProposed = nil;issue = nil } else { issue = store.editError } }
        } catch { issue = error.localizedDescription }
    }
}
