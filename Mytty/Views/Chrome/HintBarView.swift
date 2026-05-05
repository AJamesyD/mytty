import SwiftUI

struct HintBarView: View {
  let items: [(trigger: String, label: String)]

  var body: some View {
    HStack(spacing: 12) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        HStack(spacing: 3) {
          Text(item.trigger)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(MyttyTheme.overlayKeyBadge, in: RoundedRectangle(cornerRadius: 3))
          Text(item.label)
            .foregroundStyle(MyttyTheme.overlayTextMuted)
        }
      }
    }
    .font(.system(size: 12, design: .monospaced))
    .foregroundStyle(MyttyTheme.overlayText)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(MyttyTheme.overlayBackground, in: RoundedRectangle(cornerRadius: 6))
  }
}
