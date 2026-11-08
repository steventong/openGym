import SwiftUI

struct ExercisePositionLabel: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "dumbbell").accessibilityHidden(true)
            Text(String(format: String(localized: "EXERCISE_COUNT_OF_COUNT", bundle: AppLanguage.bundle, locale: AppLanguage.locale), locale: AppLanguage.locale, String(describing: index + 1), String(describing: count)))
        }.fixedSize().accessibilityElement(children: .combine)
    }
}
