import SwiftUI

struct CoachTextList: View {
    let title: LocalizedStringKey
    let items: [String]
    let symbol: String

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(GymTheme.green)
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    Text(String(format: String(localized: "BULLETED_LIST_ITEM", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, text)).font(.subheadline)
                }
            }
        }
    }
}
