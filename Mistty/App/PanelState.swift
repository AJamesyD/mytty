import SwiftUI

enum PanelMode: String, Codable, CaseIterable {
  case pinned, autoHide, hidden
}

extension PanelMode {
  var configValue: String {
    switch self {
    case .pinned: "pinned"
    case .autoHide: "auto-hide"
    case .hidden: "hidden"
    }
  }

  static func fromConfig(_ string: String) -> PanelMode? {
    switch string {
    case "pinned": .pinned
    case "auto-hide": .autoHide
    case "hidden": .hidden
    default: nil
    }
  }
}

@MainActor @Observable
final class PanelState {
  var sidebarMode: PanelMode = .pinned
  var sidebarPosition: SidebarPosition = .left
  var sidebarShowTree: Bool = true
  var tabBarMode: PanelMode = .pinned
  var hideTabBarWhenSingleTab: Bool = true
  var dwellDuration: TimeInterval = 0.15
  var dismissDelay: TimeInterval = 0.3
  var showHints: Bool = true

  var isSidebarRevealed: Bool = false
  var isTabBarRevealed: Bool = false
  var isSidebarTempPinned: Bool = false
  var isTabBarTempPinned: Bool = false

  var shouldShowSidebar: Bool {
    switch sidebarMode {
    case .pinned: true
    case .autoHide, .hidden: isSidebarRevealed
    }
  }

  func shouldShowTabBar(tabCount: Int) -> Bool {
    if hideTabBarWhenSingleTab && tabCount < 2 { return false }
    switch tabBarMode {
    case .pinned: return true
    case .autoHide, .hidden: return isTabBarRevealed
    }
  }

  var sidebarIsPinned: Bool { sidebarMode == .pinned }

  func tabBarIsPinned(tabCount: Int) -> Bool {
    if hideTabBarWhenSingleTab && tabCount < 2 { return false }
    return tabBarMode == .pinned
  }
}
