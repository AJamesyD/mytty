import SwiftUI

struct InlineEditableTextField: View {
  let text: String
  let placeholder: String
  let font: Font
  let onCommit: (String) -> Void
  let onCancel: () -> Void

  @State private var editText: String = ""
  @State private var didCommit = false
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField(placeholder, text: $editText)
      .onSubmit {
        didCommit = true
        onCommit(editText)
      }
      .textFieldStyle(.plain)
      .font(font)
      .focused($isFocused)
      .onExitCommand { onCancel() }
      .onAppear {
        editText = text
        isFocused = true
      }
      .onChange(of: isFocused) {
        if !isFocused && !didCommit { onCancel() }
      }
  }
}
