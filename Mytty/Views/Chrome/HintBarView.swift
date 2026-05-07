import SwiftUI

struct HintBarView: View {
  let items: [(trigger: String, label: String)]
  var cellHeight: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        KeyBadge(key: item.trigger, label: item.label, labelStyle: MyttyTheme.overlayTextMuted)
      }
    }
    .font(MyttyTheme.overlayFont(cellHeight))
    .foregroundStyle(MyttyTheme.overlayText)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(MyttyTheme.hintBarBackground, in: RoundedRectangle(cornerRadius: 8))
  }
}
