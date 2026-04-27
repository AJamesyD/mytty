import GhosttyKit
import SwiftUI

struct PaneView: View {
  let pane: MyttyPane
  let isActive: Bool
  var isWindowModeActive: Bool = false
  var isZoomed: Bool = false
  var copyModeState: CopyModeState?
  var windowModeState: MyttyTab.WindowModeState = .inactive
  var joinPickTabNames: [String] = []
  var paneCount: Int = 1
  var hintsModeManager: HintsModeManager?
  var onClose: (() -> Void)?
  var onSelect: (() -> Void)?
  @State private var isHovering = false

  var body: some View {
    TerminalSurfaceRepresentable(pane: pane, onSelect: onSelect)
      .id(pane.id)
      .overlay(alignment: .topTrailing) {
        if isHovering, let onClose {
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.secondary)
              .frame(width: 20, height: 20)
              .background(.regularMaterial, in: Circle())
          }
          .buttonStyle(.plain)
          .padding(6)
        }
      }
      .overlay {
        if !isActive {
          MyttyTheme.paneDimOverlay
            .allowsHitTesting(false)
        }
      }
      .overlay {
        if isActive && windowModeState != .inactive {
          RoundedRectangle(cornerRadius: 2)
            .stroke(MyttyTheme.windowModePaneBorder, lineWidth: 2)
            .allowsHitTesting(false)
        } else if isActive {
          RoundedRectangle(cornerRadius: 2)
            .stroke(MyttyTheme.activePaneBorder, lineWidth: 1)
            .allowsHitTesting(false)
        }
      }
      .overlay(alignment: .topLeading) {
        if isZoomed {
          let cellH = pane.surfaceView.gridMetrics()?.cellHeight ?? 16
          Text("⊕ ZOOMED")
            .font(.system(size: max(cellH * 0.8, 12), weight: .bold, design: .monospaced))
            .foregroundStyle(MyttyTheme.overlayText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(MyttyTheme.modeIndicatorBackground, in: RoundedRectangle(cornerRadius: 4))
            .padding(6)
            .allowsHitTesting(false)
        }
      }
      .overlay {
        if let state = copyModeState {
          GeometryReader { geo in
            let metrics = pane.surfaceView.gridMetrics()
            let cellW = metrics?.cellWidth ?? geo.size.width / CGFloat(state.cols)
            let cellH = metrics?.cellHeight ?? geo.size.height / CGFloat(state.rows)
            let offX = metrics?.offsetX ?? 0
            let offY = metrics?.offsetY ?? 0
            let reader: ((Int) -> String?)? = { row in
              guard let surface = pane.surfaceView.surface else { return nil }
              let size = ghostty_surface_size(surface)
              var sel = ghostty_selection_s()
              sel.top_left.tag = GHOSTTY_POINT_VIEWPORT
              sel.top_left.coord = GHOSTTY_POINT_COORD_EXACT
              sel.top_left.x = 0
              sel.top_left.y = UInt32(row)
              sel.bottom_right.tag = GHOSTTY_POINT_VIEWPORT
              sel.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT
              sel.bottom_right.x = UInt32(size.columns - 1)
              sel.bottom_right.y = UInt32(row)
              sel.rectangle = false
              var text = ghostty_text_s()
              guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
              defer { ghostty_surface_free_text(surface, &text) }
              guard let ptr = text.text else { return nil }
              return String(cString: ptr)
            }
            CopyModeOverlay(
              state: state,
              cellWidth: cellW,
              cellHeight: cellH,
              gridOffsetX: offX,
              gridOffsetY: offY,
              lineReader: reader
            )
          }
        }
      }
      .overlay {
        if let manager = hintsModeManager, manager.isActive {
          let metrics = pane.surfaceView.gridMetrics()
          switch manager.state {
          case .active(let labels, let typed):
            HintsOverlayView(
              labels: labels, typed: typed,
              cellWidth: metrics?.cellWidth ?? 8,
              cellHeight: metrics?.cellHeight ?? 16)
          case .filtering(_, let typed, let remaining):
            HintsOverlayView(
              labels: remaining, typed: typed,
              cellWidth: metrics?.cellWidth ?? 8,
              cellHeight: metrics?.cellHeight ?? 16)
          default:
            EmptyView()
          }
        }
      }
      .onHover { hovering in
        isHovering = hovering
      }
      // TODO: Ghostty renders the URL in both corners and swaps on hover
      // (SurfaceView.swift lines 139-178). Add dual-position swap.
      .overlay(alignment: .bottomTrailing) {
        if let url = pane.hoverUrl {
          Text(verbatim: url)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
              UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6))
                .fill(.regularMaterial)
            )
            .allowsHitTesting(false)
        }
      }
  }
}
