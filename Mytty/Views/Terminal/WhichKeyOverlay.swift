import SwiftUI

struct WhichKeyOverlay: View {
  var bindings: [WhichKeyBinding]
  var breadcrumb: [String]
  var isActive: Bool
  var cellHeight: CGFloat

  @State private var availableWidth: CGFloat = 0

  var body: some View {
    if isActive {
      VStack(alignment: .leading, spacing: 6) {
        if breadcrumb.isEmpty {
          Text("SHORTCUTS")
            .fontWeight(.bold)
        } else {
          Text(breadcrumb.joined(separator: " > ") + " >")
            .fontWeight(.bold)
          Text("\u{232B} back")
            .font(.system(size: max(cellHeight * 0.6, 10), design: .monospaced))
            .foregroundStyle(MyttyTheme.overlayTextMuted)
        }
        // availableWidth measures the full overlay frame (includes padding).
        // 174 = 160pt min column width + 14pt inter-column gap
        let columns = max(1, min(6, Int((availableWidth + 14) / 174)))
        let rowsPerColumn =
          bindings.isEmpty ? 0 : Int((Double(bindings.count) / Double(columns)).rounded(.up))
        HStack(alignment: .top, spacing: 14) {
          ForEach(0..<columns, id: \.self) { col in
            VStack(alignment: .leading, spacing: 6) {
              ForEach(0..<rowsPerColumn, id: \.self) { row in
                let index = col * rowsPerColumn + row
                if index < bindings.count {
                  hintBadge(binding: bindings[index])
                }
              }
            }
          }
        }
      }
      .font(MyttyTheme.overlayFont(cellHeight))
      .foregroundStyle(MyttyTheme.overlayText)
      .padding(12)
      .background(MyttyTheme.overlayBackground, in: RoundedRectangle(cornerRadius: 8))
      // Expand frame for width measurement but center the visible panel.
      // Column count depends on available width; without .infinity the
      // GeometryReader would only see the content's intrinsic size.
      // If centering looks too wide on ultrawides, cap with .frame(maxWidth: N).
      .frame(maxWidth: .infinity)
      .background(
        GeometryReader { geo in Color.clear.preference(key: WidthKey.self, value: geo.size.width) }
      )
      .onPreferenceChange(WidthKey.self) { availableWidth = $0 }
      .transition(.opacity)
      .animation(.easeInOut(duration: 0.15), value: isActive)
    }
  }

  private func hintBadge(binding: WhichKeyBinding) -> some View {
    let (label, isGroup) = bindingLabel(binding.action)
    return KeyBadge(
      key: String(binding.key),
      label: label + (isGroup ? " >" : "")
    )
  }

  private func bindingLabel(_ action: WhichKeyAction) -> (String, Bool) {
    switch action {
    case .group(let label, _): (label, true)
    case .command(let label, _): (label, false)
    }
  }
}

private struct WidthKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
