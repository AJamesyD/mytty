import AppKit

enum HintAction: Hashable, Sendable {
  case copy, open, paste, focus, close
}

@MainActor
protocol HintTarget {
  var id: String { get }
  var labelOrigin: CGPoint { get }
  var displayText: String { get }
  var availableActions: [HintAction] { get }
  var defaultAction: HintAction { get }
}

enum HintsGeometry {
  case terminal(
    rows: Int, cols: Int, cellWidth: CGFloat, cellHeight: CGFloat, offsetX: CGFloat,
    offsetY: CGFloat)
  case chrome(elementFrames: [String: CGRect])
}

@MainActor
protocol HintTargetProvider {
  var providerID: String { get }
  func targets(in geometry: HintsGeometry) -> [any HintTarget]
}

enum TerminalMatchType: CaseIterable {
  case url, path, hash, ip, linenum
}

@MainActor
struct TerminalHintTarget: HintTarget {
  let id: String
  let labelOrigin: CGPoint
  let displayText: String
  let matchType: TerminalMatchType
  let row: Int
  let colRange: Range<Int>

  var availableActions: [HintAction] {
    switch matchType {
    case .url, .path: [.copy, .open, .paste]
    case .hash, .ip, .linenum: [.copy, .paste]
    }
  }

  var defaultAction: HintAction { .copy }
}

enum ChromeElement {
  case session(sessionID: Int)
  case tab(sessionID: Int, tabID: Int)
  case pane(paneID: Int)
}

@MainActor
struct ChromeHintTarget: HintTarget {
  let id: String
  let labelOrigin: CGPoint
  let displayText: String
  let chromeElement: ChromeElement

  var availableActions: [HintAction] { [.focus, .close] }
  var defaultAction: HintAction { .focus }
}

struct HintLabel {
  let target: any HintTarget
  let label: String
}

enum HintsModeState {
  case inactive
  case active(labels: [HintLabel], typed: String)
  case filtering(labels: [HintLabel], typed: String, remaining: [HintLabel])
  case selected(label: HintLabel, action: HintAction)
}
