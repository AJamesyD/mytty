import SwiftUI

struct HintsOverlayView: View {
  let labels: [HintLabel]
  let typed: String
  let cellWidth: CGFloat
  let cellHeight: CGFloat
  var actionBarItems: [(symbol: String, label: String)] = [
    ("⏎", "copy"), ("⇧", "open"), ("⌃", "paste"),
  ]

  var body: some View {
    ZStack {
      MyttyTheme.hintsBackdrop
        .ignoresSafeArea()

      Canvas { context, _ in
        let fontSize = MyttyTheme.overlayFontSize(cellHeight)
        for label in labels {
          let origin = label.target.labelOrigin
          let labelWidth = cellWidth * CGFloat(label.label.count)
          let rect = CGRect(
            x: origin.x, y: origin.y,
            width: labelWidth, height: cellHeight
          )
          context.fill(Path(rect), with: .color(MyttyTheme.hintLabelBackground))

          let remaining = String(label.label.dropFirst(typed.count))
          guard !remaining.isEmpty else { continue }
          let text = Text(remaining)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(MyttyTheme.hintLabelForeground)
          let resolved = context.resolve(text)
          let textX = origin.x + cellWidth * CGFloat(typed.count)
          context.draw(resolved, at: CGPoint(x: textX, y: origin.y), anchor: .topLeading)
        }
      }

      VStack {
        Spacer()
        HStack(spacing: 16) {
          ForEach(Array(actionBarItems.enumerated()), id: \.offset) { index, item in
            Text("\(item.symbol) \(item.label)")
              .foregroundStyle(index == 0 ? MyttyTheme.overlayText : MyttyTheme.overlayTextMuted)
          }
        }
        .font(MyttyTheme.overlayFont(cellHeight, weight: .medium))
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(MyttyTheme.overlayBackground, in: RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 8)
      }
    }
    .allowsHitTesting(false)
  }
}
