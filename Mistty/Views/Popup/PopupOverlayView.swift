import SwiftUI

struct PopupOverlayView: View {
  let popup: PopupState
  let onDismiss: () -> Void
  let onClose: () -> Void

  var body: some View {
    ZStack {
      // Semi-transparent backdrop
      MisttyTheme.popupBackdrop
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }

      // Popup container
      VStack(spacing: 0) {
        // Header bar
        HStack {
          Text(popup.definition.name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            onClose()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .font(.system(size: 14))
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)

        // Terminal surface
        TerminalSurfaceRepresentable(pane: popup.pane)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(MisttyTheme.popupBorder, lineWidth: 1)
      )
      .shadow(color: MisttyTheme.popupShadow, radius: 20, y: 5)
    }
  }
}
