import SwiftUI

struct HintsOverlayView: View {
  let labels: [HintLabel]
  let typed: String
  let cellWidth: CGFloat
  let cellHeight: CGFloat

  var body: some View {
    ZStack {
      MyttyTheme.hintsBackdrop
        .ignoresSafeArea()

      Canvas { context, _ in
        let fontSize = cellHeight * 0.8
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
          Text("⏎ copy")
            .foregroundStyle(MyttyTheme.overlayText)
          Text("⇧ open")
            .foregroundStyle(MyttyTheme.overlayTextMuted)
          Text("⌃ paste")
            .foregroundStyle(MyttyTheme.overlayTextMuted)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(MyttyTheme.overlayBackground, in: RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 8)
      }
    }
    .allowsHitTesting(false)
  }
}
