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
    @State private var confirmImport = false
    private let templates = [("ppl",L10n.text("PUSH_PULL_LEGS_THREE_DAYS_A_WEEK" /* 推 / 拉 / 腿 · 每周 3 天 */)),("upper-lower",L10n.text("UPPER_LOWER_FOUR_DAYS_A_WEEK" /* 上肢 / 下肢 · 每周 4 天 */)),("full-body",L10n.text("FULL_BODY_THREE_DAYS_A_WEEK" /* 全身训练 · 每周 3 天 */)),("5x5",L10n.text("FIVE_FIVE_STRENGTH_THREE_DAYS_A_WEEK" /* 5 × 5 力量训练 · 每周 3 天 */))]
    var body:some View {
        NavigationStack {
            List {
                Section(L10n.text("ROUTINE_FILES" /* 计划文件 */)) {
                    Button(L10n.text("EXPORT_ALL_ROUTINES" /* 导出全部计划 */)) { exportPlan() }.disabled(store.routines.isEmpty)
                    Button { importing = true } label: { Label(notice == nil ? L10n.text("IMPORT_ROUTINES" /* 导入训练计划 */) : L10n.text("IMPORTED" /* 已导入 */), systemImage: notice == nil ? "square.and.arrow.down" : "checkmark") }
                }
                Section(L10n.text("STARTER_TEMPLATES" /* 入门模板 */)) {
                    ForEach(templates,id:\.0) { id,name in Button(name) { loadTemplate(id) } }
                }
                if let bundle {
                    Section {
                        ForEach(Array((bundle["routines"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) { _,r in
                            VStack(alignment:.leading) { Text(r["name"] as? String ?? L10n.text("WORKOUT" /* 训练 */));Text(L10n.text("COUNT_EXERCISES" /* {0} 个动作 */, (r["ex"] as? [Any] ?? []).count)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Toggle(L10n.text("USE_IMPORTED_WEEKLY_SCHEDULE" /* 采用导入的每周排期 */),isOn:$applySchedule).disabled(preparedProposed != nil)
                        Button(store.syncing ? L10n.text("SAVING" /* 正在保存 */):L10n.text("CONFIRM_IMPORT" /* 确认导入 */)) {
                            if applySchedule { confirmImport = true } else { apply() }
                        }.lineLimit(1).disabled(store.syncing || (bundle["routines"] as? [Any] ?? []).isEmpty).accessibilityIdentifier("confirm-plan-import")
                        Button(L10n.text("CANCEL_IMPORT" /* 取消导入 */),role:.cancel) { self.bundle = nil;preparedOriginal = nil;preparedProposed = nil }
                    } header: {
                        HStack {
                            Text(L10n.text("IMPORT_PREVIEW" /* 导入预览 */))
                            Spacer()
                            if number(bundle["dropped"]) > 0 {
                                StatusDetailButton(title: L10n.text("COUNT_ITEMS_EXCLUDED" /* 已排除 {0} 项 */, Int(number(bundle["dropped"]))), message: L10n.text("UNRECOGNIZED_EXERCISES_WILL_NOT_BE_IMPORTED" /* 无法识别的动作不会导入。 */), warning: true)
                            }
                        }
                    }
                }
            }.operationAlert($issue).navigationTitle(L10n.text("ROUTINE_TOOLS" /* 计划工具 */)).toolbar { ToolbarItem(placement:.topBarTrailing) {Button(L10n.text("DONE" /* 完成 */)){dismiss()}} }
                .confirmationDialog(L10n.text("REPLACE_WEEKLY_SCHEDULE" /* 替换每周排期？ */), isPresented: $confirmImport, titleVisibility: .visible) {
                    Button(L10n.text("IMPORT_AND_REPLACE" /* 导入并替换 */)) { apply() }
                    Button(L10n.text("CANCEL" /* 取消 */), role: .cancel) {}
                } message: { Text(L10n.text("ROUTINES_ARE_ADDED_AS_COPIES_YOUR_WEEKLY_SCHEDULE_WILL_BE_REPLACED_DATE" /* 计划作为副本添加；现有每周排期将被替换，单日调整保留。 */)) }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
                        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size <= 10_000_000 else { throw APIError.response(0,L10n.text("ROUTINE_FILE_IS_TOO_LARGE_ONEZERO_MB_MAXIMUM" /* 计划文件过大（上限 10 MB）。 */)) }
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
            bundle = ["routines":routines,"week":week,"customEx":[],"unit":store.unit,"name":L10n.text("STARTER_WORKOUT" /* 入门训练 */)]
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
            Task { if await store.savePersonalFields(original:original,proposed:proposed,unit:expectedUnit) { notice = L10n.text("ROUTINES_IMPORTED" /* 已导入计划。 */);self.bundle = nil;preparedOriginal = nil;preparedProposed = nil;issue = nil } else { issue = store.editError } }
        } catch { issue = error.localizedDescription }
    }
}
