import SwiftUI

struct HintBarView: View {
  let items: [(trigger: String, label: String)]

  var body: some View {
    HStack(spacing: 16) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        HStack(spacing: 2) {
          Text(item.trigger)
            .foregroundStyle(MyttyTheme.overlayText)
          Text(item.label)
            .foregroundStyle(MyttyTheme.overlayTextMuted)
        }
      }
    }
    .font(.system(size: 11))
    .frame(height: 20)
    .frame(maxWidth: .infinity)
    .background(MyttyTheme.hintBarBackground)
  }
}
