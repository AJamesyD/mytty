import SwiftUI

struct KeyBadge: View {
  let key: String
  let label: String
  var labelStyle: Color = MyttyTheme.overlayText
  var badgeBackground: Color = MyttyTheme.overlayKeyBadge

  var body: some View {
    HStack(spacing: 4) {
      Text(key)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(badgeBackground, in: RoundedRectangle(cornerRadius: 3))
      Text(label)
        .foregroundStyle(labelStyle)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }
}
