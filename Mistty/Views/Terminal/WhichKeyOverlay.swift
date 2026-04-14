import SwiftUI

struct WhichKeyOverlay: View {
  var bindings: [WhichKeyBinding]
  var breadcrumb: [String]
  var isActive: Bool

  var body: some View {
    if isActive {
      VStack(alignment: .leading, spacing: 6) {
        if !breadcrumb.isEmpty {
          Text(breadcrumb.joined(separator: " > ") + " >")
            .fontWeight(.bold)
        }
        ForEach(Array(chunked(bindings, size: 4).enumerated()), id: \.offset) { _, row in
          HStack(spacing: 14) {
            ForEach(row, id: \.key) { binding in
              hintBadge(binding: binding)
            }
          }
        }
      }
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.white)
      .padding(12)
      .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
      .transition(.opacity)
      .animation(.easeInOut(duration: 0.15), value: isActive)
    }
  }

  private func hintBadge(binding: WhichKeyBinding) -> some View {
    let (label, isGroup) = bindingLabel(binding.action)
    return HStack(spacing: 4) {
      Text(String(binding.key))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
      Text(label + (isGroup ? " >" : ""))
    }
  }

  private func bindingLabel(_ action: WhichKeyAction) -> (String, Bool) {
    switch action {
    case .group(let label, _): (label, true)
    case .command(let label, _): (label, false)
    }
  }

  private func chunked(_ array: [WhichKeyBinding], size: Int) -> [[WhichKeyBinding]] {
    stride(from: 0, to: array.count, by: size).map {
      Array(array[$0..<min($0 + size, array.count)])
    }
  }
}
