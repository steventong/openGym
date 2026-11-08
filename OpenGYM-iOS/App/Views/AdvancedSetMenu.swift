import SwiftUI

struct AdvancedSetMenu: View {
    let row: [String: Any]
    let target: [String: Any]
    let mode: String
    let warmup: Bool
    let identifier: String
    let setLabel: String
    let copySet: (() -> Void)?
    let removeSet: (() -> Void)?
    let timerRunning: Bool
    @Binding var effortVisible: Bool
    let action: ([String: Any]) -> Void

    var body: some View {
        Menu {
            if let copySet { Button("COPY_SET", systemImage: "doc.on.doc", action: copySet) }
            if let removeSet { Button("DELETE_SET", systemImage: "trash", role: .destructive, action: removeSet) }
            Divider()
            if mode == "reps" && !warmup {
                if row["type"] as? String != "restpause" { Button("ADD_DROP_SET") { action(["action": "dropAdd"]) } }
                if row["type"] as? String != "dropset" { Button("ADD_REST_PAUSE_MINI_SET") { action(["action": "clusterAdd"]) } }
                Button(LocalizedStringKey(row["failure"] as? Bool == true ? "CLEAR_FAILURE_MARK" : "MARK_AS_FAILURE")) { action(["action": "failure"]) }
            }
            if warmup || (((try? WebRules.shared.call("rowInfo", payload: ["row": row, "target": target])) as? [String: Any])?["canWarmup"] as? Bool == true) {
                Button(LocalizedStringKey(warmup ? "MARK_AS_WORK_SET" : "MARK_AS_WARM_UP")) { action(["action": "warmup", "value": !warmup]) }
            }
            Button(LocalizedStringKey(effortVisible ? "HIDE_RIR_RPE" : "LOG_RIR_RPE")) { effortVisible.toggle() }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(GymTheme.muted).frame(width: 44, height: 44)
        }.accessibilityLabel(String(format: String(localized: "COUNT_OPTIONS", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: setLabel)))
            .accessibilityIdentifier("set-options-\(identifier)").disabled(timerRunning)
    }
}
