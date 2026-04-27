import SwiftUI

struct WindowModeHints: View {
  var keybindingStore: KeybindingStore
  var isJoinPick: Bool = false
  var tabNames: [String] = []
  var paneCount: Int = 1
  var cellHeight: CGFloat

  private func label(for action: String) -> String? {
    keybindingStore.trigger(for: action, in: .windowMode)?.displayLabel
  }

  private func directionalLabel(prefix: String) -> String? {
    let directions = ["left", "up", "down", "right"]
    let triggers = directions.compactMap {
      keybindingStore.trigger(for: "\(prefix)-\($0)", in: .windowMode)
    }
    guard triggers.count == 4 else { return nil }
    let modifiers = triggers[0].modifiers
    guard triggers.allSatisfy({ $0.modifiers == modifiers }) else {
      return triggers[0].displayLabel
    }
    var parts: [String] = []
    if modifiers.contains(.ctrl) { parts.append("⌃") }
    if modifiers.contains(.alt) { parts.append("⌥") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.cmd) { parts.append("⌘") }
    parts.append("←↑↓→")
    return parts.joined()
  }

  private var normalHints: [(key: String, label: String)] {
    var hints: [(key: String, label: String)] = []
    if let key = directionalLabel(prefix: "swap") { hints.append((key, "swap")) }
    if let key = directionalLabel(prefix: "resize") { hints.append((key, "resize")) }
    if let key = label(for: "zoom") { hints.append((key, "zoom")) }
    if let key = label(for: "break-to-tab") { hints.append((key, "break to tab")) }
    if let key = label(for: "join-pick") { hints.append((key, "join to tab")) }
    if let key = label(for: "rotate") { hints.append((key, "rotate")) }
    if let key = label(for: "exit") { hints.append((key, "exit")) }
    return hints
  }

  private var layoutHints: [(key: String, label: String)] {
    var hints: [(key: String, label: String)] = []
    if let key = label(for: "layout-even-horizontal") { hints.append((key, "even-h")) }
    if let key = label(for: "layout-even-vertical") { hints.append((key, "even-v")) }
    if let key = label(for: "layout-main-horizontal") { hints.append((key, "main-h")) }
    if let key = label(for: "layout-main-vertical") { hints.append((key, "main-v")) }
    if let key = label(for: "layout-tiled") { hints.append((key, "tiled")) }
    return hints
  }

  var body: some View {
    VStack(spacing: 4) {
      hintsRow {
        if isJoinPick {
          Text("JOIN TO TAB")
            .fontWeight(.bold)
          if tabNames.isEmpty {
            Text("no other tabs")
          } else {
            ForEach(Array(tabNames.enumerated()), id: \.offset) { index, name in
              hintBadge(key: "\(index + 1)", label: name)
            }
          }
          hintBadge(key: "esc", label: "back")
        } else {
          Text("WINDOW")
            .fontWeight(.bold)
          ForEach(normalHints, id: \.key) { hint in
            hintBadge(key: hint.key, label: hint.label)
          }
        }
      }
      if !isJoinPick && paneCount >= 2 {
        hintsRow {
          Text("LAYOUT")
            .fontWeight(.bold)
          ForEach(layoutHints, id: \.key) { hint in
            hintBadge(key: hint.key, label: hint.label)
          }
        }
      }
    }
  }

  private func hintsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: 12) {
      content()
    }
    .font(.system(size: max(cellHeight * 0.8, 12), design: .monospaced))
    .foregroundStyle(MyttyTheme.overlayText)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(MyttyTheme.overlayBackground, in: RoundedRectangle(cornerRadius: 8))
  }

  private func hintBadge(key: String, label: String) -> some View {
    HStack(spacing: 3) {
      Text(key)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(MyttyTheme.overlayKeyBadge, in: RoundedRectangle(cornerRadius: 3))
      Text(label)
    }
  }
}
