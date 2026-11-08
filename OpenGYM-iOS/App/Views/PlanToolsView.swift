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
    private let templates: [(String, LocalizedStringKey)] = [("ppl","PUSH_PULL_LEGS_THREE_DAYS_A_WEEK"),("upper-lower","UPPER_LOWER_FOUR_DAYS_A_WEEK"),("full-body","FULL_BODY_THREE_DAYS_A_WEEK"),("5x5","FIVE_FIVE_STRENGTH_THREE_DAYS_A_WEEK")]
    var body:some View {
        NavigationStack {
            List {
                Section("ROUTINE_FILES") {
                    Button("EXPORT_ALL_ROUTINES") { exportPlan() }.disabled(store.routines.isEmpty)
                    Button { importing = true } label: { Label(LocalizedStringKey(notice == nil ? "IMPORT_ROUTINES" : "IMPORTED"), systemImage: notice == nil ? "square.and.arrow.down" : "checkmark") }
                }
                Section("STARTER_TEMPLATES") {
                    ForEach(templates,id:\.0) { id,name in Button(name) { loadTemplate(id) } }
                }
                if let bundle {
                    Section {
                        ForEach(Array((bundle["routines"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) { _,r in
                            VStack(alignment:.leading) { Text(r["name"] as? String ?? String(localized: "WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale));Text(String(format: String(localized: "COUNT_EXERCISES", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: (r["ex"] as? [Any] ?? []).count))).font(.caption).foregroundStyle(.secondary) }
                        }
                        Toggle("USE_IMPORTED_WEEKLY_SCHEDULE",isOn:$applySchedule).disabled(preparedProposed != nil)
                        Button(LocalizedStringKey(store.syncing ? "SAVING":"CONFIRM_IMPORT")) {
                            if applySchedule { confirmImport = true } else { apply() }
                        }.lineLimit(1).disabled(store.syncing || (bundle["routines"] as? [Any] ?? []).isEmpty).accessibilityIdentifier("confirm-plan-import")
                        Button("CANCEL_IMPORT",role:.cancel) { self.bundle = nil;preparedOriginal = nil;preparedProposed = nil }
                    } header: {
                        HStack {
                            Text("IMPORT_PREVIEW")
                            Spacer()
                            if number(bundle["dropped"]) > 0 {
                                StatusDetailButton(title: "\(String(format: String(localized: "COUNT_ITEMS_EXCLUDED", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: Int(number(bundle["dropped"])))))", message: "UNRECOGNIZED_EXERCISES_WILL_NOT_BE_IMPORTED", warning: true)
                            }
                        }
                    }
                }
            }.operationAlert($issue).navigationTitle("ROUTINE_TOOLS").toolbar { ToolbarItem(placement:.topBarTrailing) {Button("DONE"){dismiss()}} }
                .confirmationDialog("REPLACE_WEEKLY_SCHEDULE", isPresented: $confirmImport, titleVisibility: .visible) {
                    Button("IMPORT_AND_REPLACE") { apply() }
                    Button("CANCEL", role: .cancel) {}
                } message: { Text("ROUTINES_ARE_ADDED_AS_COPIES_YOUR_WEEKLY_SCHEDULE_WILL_BE_REPLACED_DATE") }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
                        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size <= 10_000_000 else { throw APIError.response(0,String(localized: "ROUTINE_FILE_IS_TOO_LARGE_ONEZERO_MB_MAXIMUM", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
            bundle = ["routines":routines,"week":week,"customEx":[],"unit":store.unit,"name":String(localized: "STARTER_WORKOUT", bundle: AppLanguage.bundle, locale: AppLanguage.locale)]
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
            Task { if await store.savePersonalFields(original:original,proposed:proposed,unit:expectedUnit) { notice = String(localized: "ROUTINES_IMPORTED", bundle: AppLanguage.bundle, locale: AppLanguage.locale);self.bundle = nil;preparedOriginal = nil;preparedProposed = nil;issue = nil } else { issue = store.editError } }
        } catch { issue = error.localizedDescription }
    }
}
