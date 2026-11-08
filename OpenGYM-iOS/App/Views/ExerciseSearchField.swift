import SwiftUI

/// Exercise queries update immediately, independently of an enclosing form's edit buffer.
struct ExerciseSearchField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
    }
}
