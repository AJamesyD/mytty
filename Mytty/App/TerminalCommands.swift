import SwiftUI

@MainActor
class TerminalCommands {
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
  var hintsMode: () -> Void
  var chromeHintsMode: () -> Void

  init(
    newTab: @escaping () -> Void,
    closeTab: @escaping () -> Void,
    nextTab: @escaping () -> Void,
    prevTab: @escaping () -> Void,
    focusTab: @escaping (Int) -> Void,
    nextSession: @escaping () -> Void,
    prevSession: @escaping () -> Void,
    splitHorizontal: @escaping () -> Void,
    splitVertical: @escaping () -> Void,
    closePane: @escaping () -> Void,
    windowMode: @escaping () -> Void,
    copyMode: @escaping () -> Void,
    whichKey: @escaping () -> Void,
    sessionManager: @escaping () -> Void,
    togglePopup: @escaping (String) -> Void,
    toggleSidebar: @escaping () -> Void,
    toggleTabBar: @escaping () -> Void,
    jumpToPreviousPrompt: @escaping () -> Void,
    jumpToNextPrompt: @escaping () -> Void,
    hintsMode: @escaping () -> Void,
    chromeHintsMode: @escaping () -> Void
  ) {
    self.newTab = newTab
    self.closeTab = closeTab
    self.nextTab = nextTab
    self.prevTab = prevTab
    self.focusTab = focusTab
    self.nextSession = nextSession
    self.prevSession = prevSession
    self.splitHorizontal = splitHorizontal
    self.splitVertical = splitVertical
    self.closePane = closePane
    self.windowMode = windowMode
    self.copyMode = copyMode
    self.whichKey = whichKey
    self.sessionManager = sessionManager
    self.togglePopup = togglePopup
    self.toggleSidebar = toggleSidebar
    self.toggleTabBar = toggleTabBar
    self.jumpToPreviousPrompt = jumpToPreviousPrompt
    self.jumpToNextPrompt = jumpToNextPrompt
    self.hintsMode = hintsMode
    self.chromeHintsMode = chromeHintsMode
  }
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
