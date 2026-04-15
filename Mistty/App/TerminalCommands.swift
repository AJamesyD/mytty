import SwiftUI

struct TerminalCommands {
  var newTab: () -> Void
  var closeTab: () -> Void
  var nextTab: () -> Void
  var prevTab: () -> Void
  var focusTab: (Int) -> Void
  var nextSession: () -> Void
  var prevSession: () -> Void
  var splitHorizontal: () -> Void
  var splitVertical: () -> Void
  var closePane: () -> Void
  var windowMode: () -> Void
  var copyMode: () -> Void
  var whichKey: () -> Void
  var sessionManager: () -> Void
  var togglePopup: (String) -> Void
  var toggleSidebar: () -> Void
  var toggleTabBar: () -> Void
  var jumpToPreviousPrompt: () -> Void
  var jumpToNextPrompt: () -> Void
}

struct TerminalCommandsKey: FocusedValueKey {
  typealias Value = TerminalCommands
}

extension FocusedValues {
  var terminalCommands: TerminalCommands? {
    get { self[TerminalCommandsKey.self] }
    set { self[TerminalCommandsKey.self] = newValue }
  }
}
