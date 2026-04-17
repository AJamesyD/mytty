import SwiftUI

struct SequenceIndicatorView: View {
  var text: String

  var body: some View {
    if !text.isEmpty {
      Text(text)
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(MyttyTheme.overlayText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MyttyTheme.overlayBackground, in: RoundedRectangle(cornerRadius: 6))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text)
    }
  }
}
