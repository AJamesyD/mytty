import AppKit
import GhosttyKit
import MyttyShared
import SwiftUI
import UserNotifications

@MainActor
private var hasRequestedNotificationPermission = false

extension ContentView {
  var isAnyModalActive: Bool {
    showingSessionManager
      || windowModeManager.isActive
      || copyModeManager.isActive
      || whichKeyManager.isActive
  }

  var contentWithNotifications: some View {
    contentWithOverlays
      .onReceive(NotificationCenter.default.publisher(for: .ghosttySetTitle)) { notification in
        handleSetTitle(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyRingBell)) { notification in
        handleRingBell(notification)
      }
      .onChange(of: store.activeSession?.activeTab?.id) { _, _ in
        store.activeSession?.activeTab?.hasBell = false
        store.activeSession?.activeTab?.hasFailedCommand = false
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyCloseSurface)) { notification in
        handleCloseSurface(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyPwd)) { notification in
        handlePwd(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttySetTabTitle)) { notification in
        handleSetTabTitle(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyDesktopNotification)) {
        notification in
        handleDesktopNotification(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyCommandFinished)) {
        notification in
        handleCommandFinished(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyProgressReport)) {
        notification in
        handleProgressReport(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyColorChange)) { notification in
        handleColorChange(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .configDidChange)) { _ in
        let newConfig = MyttyConfig.load()
        applyConfig(newConfig)
        if let error = newConfig.parseError {
          print("[Mytty] Config parse error: \(error)")
        }
        for warning in newConfig.keybindingStore.warnings {
          print("[Mytty] Keybinding warning: \(warning)")
        }
        if windowModeManager.isActive {
          windowModeManager.reloadConfig()
        }
      }
      .onAppear {
        activateKeySequenceManager()
      }
  }

  var contentWithOverlays: some View {
    mainContent
      .overlay { sessionManagerOverlay }
      .overlay { popupOverlay }
      .overlay(alignment: .bottom) {
        SequenceIndicatorView(text: keySequenceManager.pendingDisplay)
          .padding(.bottom, 40)
      }
      .overlay {
        WhichKeyOverlay(
          bindings: whichKeyManager.currentBindings,
          breadcrumb: whichKeyManager.breadcrumb,
          isActive: whichKeyManager.isActive
        )
      }
      .onChange(of: showingSessionManager) { _, isShowing in
        if isShowing {
          let vm = SessionManagerViewModel(store: store)
          sessionManagerVM = vm
        } else {
          sessionManagerVM = nil
        }
      }
      .paneNavigation(
        store: store,
        sequenceManager: keySequenceManager)
  }

  func splitPane(direction: SplitDirection) {
    guard let session = store.activeSession,
      let tab = session.activeTab
    else { return }
    if let sshCommand = session.sshCommand,
      !NSEvent.modifierFlags.contains(.option)
    {
      let pane = MyttyPane(id: tab.paneIDGenerator())
      pane.directory = session.directory
      pane.command = sshCommand
      pane.useCommandField = false
      tab.addExistingPane(pane, direction: direction)
    } else {
      tab.splitActivePane(direction: direction)
    }
  }

  func closePane(_ pane: MyttyPane) {
    guard let session = store.activeSession,
      let tab = session.activeTab
    else { return }
    closePaneInTab(pane, tab: tab, session: session)
  }

  func returnFocusToActivePane() {
    if let pane = store.activeSession?.activeTab?.activePane {
      DispatchQueue.main.async {
        pane.surfaceView.window?.makeFirstResponder(pane.surfaceView)
      }
    }
  }

  func closePaneInTab(_ pane: MyttyPane, tab: MyttyTab, session: MyttySession) {
    tab.closePane(pane)
    if tab.panes.isEmpty {
      session.closeTab(tab)
      if session.tabs.isEmpty {
        store.closeSession(session)
      }
    }
  }

  // MARK: - Notification Handlers

  func handlePopupToggle(name: String) {
    guard let session = store.activeSession else { return }
    let config = MyttyConfig.load()
    guard let definition = config.popups.first(where: { $0.name == name }) else { return }
    session.togglePopup(definition: definition)
    if let popup = session.activePopup, popup.isVisible {
      DispatchQueue.main.async {
        popup.pane.surfaceView.window?.makeFirstResponder(popup.pane.surfaceView)
      }
    }
  }

  func handleClosePane() {
    if let session = store.activeSession,
      let popup = session.activePopup,
      popup.isVisible
    {
      session.closePopup(popup)
      returnFocusToActivePane()
      return
    }
    guard let tab = store.activeSession?.activeTab,
      let pane = tab.activePane
    else { return }
    closePane(pane)
  }

  func handleWindowMode() {
    guard let tab = store.activeSession?.activeTab else { return }
    if tab.isWindowModeActive {
      tab.windowModeState = .inactive
      windowModeManager.deactivate()
    } else {
      tab.windowModeState = .normal
      windowModeManager.activate(store: store)
    }
  }

  func handleCopyMode() {
    guard let tab = store.activeSession?.activeTab else { return }
    if tab.isCopyModeActive {
      copyModeManager.exit()
    } else {
      copyModeManager.enter(store: store)
    }
  }

  func handleWhichKey() {
    if whichKeyManager.isActive {
      whichKeyManager.deactivate()
    } else {
      if let tab = store.activeSession?.activeTab {
        if tab.isWindowModeActive {
          tab.windowModeState = .inactive
          windowModeManager.deactivate()
        }
        if tab.isCopyModeActive {
          copyModeManager.exit()
        }
      }
      let keybindingStore = MyttyConfig.load().keybindingStore
      guard let terminalCommands else { return }
      whichKeyManager.activate(
        bindings: WhichKeyManager.buildBindings(
          store: store, commands: terminalCommands,
          groups: keybindingStore.whichKeyGroups))
    }
  }

  func handleCloseTab() {
    guard let session = store.activeSession,
      let tab = session.activeTab
    else { return }
    session.closeTab(tab)
    if session.tabs.isEmpty {
      store.closeSession(session)
    }
  }

  func handleToggleSidebar() {
    switch panelState.sidebarMode {
    case .pinned:
      panelState.sidebarMode = .hidden
    case .autoHide:
      panelState.isSidebarTempPinned.toggle()
      panelState.isSidebarRevealed = panelState.isSidebarTempPinned
    case .hidden:
      panelState.isSidebarTempPinned.toggle()
      panelState.isSidebarRevealed = panelState.isSidebarTempPinned
    }
  }

  func handleToggleTabBar() {
    guard let session = store.activeSession else { return }
    if panelState.hideTabBarWhenSingleTab && session.tabs.count < 2 { return }
    switch panelState.tabBarMode {
    case .pinned:
      panelState.tabBarMode = .hidden
    case .autoHide:
      panelState.isTabBarTempPinned.toggle()
      panelState.isTabBarRevealed = panelState.isTabBarTempPinned
    case .hidden:
      panelState.isTabBarTempPinned.toggle()
      panelState.isTabBarRevealed = panelState.isTabBarTempPinned
    }
  }

  func handleSetTitle(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int,
      let title = notification.userInfo?["title"] as? String
    else { return }
    for session in store.sessions {
      for tab in session.tabs {
        if let pane = tab.panes.first(where: { $0.id == paneID }) {
          pane.processTitle = title
          tab.titleDebounceTask?.cancel()
          let task = DispatchWorkItem { [weak tab] in
            tab?.title = title
          }
          tab.titleDebounceTask = task
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: task)
          return
        }
      }
    }
  }

  func handleRingBell(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int else { return }
    for session in store.sessions {
      for tab in session.tabs {
        if tab.panes.contains(where: { $0.id == paneID }),
          !(store.activeSession?.id == session.id && session.activeTab?.id == tab.id)
        {
          tab.hasBell = true
        }
      }
    }
  }

  func handleCloseSurface(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int else { return }
    // Check if this is a popup pane
    for session in store.sessions {
      if let popup = session.popups.first(where: { $0.pane.id == paneID }) {
        if popup.definition.closeOnExit {
          session.closePopup(popup)
        } else {
          popup.isVisible = false
          if session.activePopup?.id == popup.id {
            session.activePopup = nil
          }
        }
        returnFocusToActivePane()
        return
      }
    }
    // Find and close the pane whose shell exited
    for session in store.sessions {
      for tab in session.tabs {
        if let pane = tab.panes.first(where: { $0.id == paneID }) {
          closePaneInTab(pane, tab: tab, session: session)
          return
        }
      }
    }
  }

  func handlePwd(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int,
      let pwd = notification.userInfo?["pwd"] as? String
    else { return }
    for session in store.sessions {
      for tab in session.tabs {
        if let pane = tab.panes.first(where: { $0.id == paneID }) {
          pane.workingDirectory = URL(fileURLWithPath: pwd)
          return
        }
      }
    }
  }

  func handleSetTabTitle(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int,
      let title = notification.userInfo?["title"] as? String
    else { return }
    for session in store.sessions {
      for tab in session.tabs where tab.panes.contains(where: { $0.id == paneID }) {
        tab.tabTitle = title
        return
      }
    }
  }

  func handleDesktopNotification(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int,
      let title = notification.userInfo?["title"] as? String,
      let body = notification.userInfo?["body"] as? String
    else { return }
    if store.activeSession?.activeTab?.activePane?.id == paneID { return }
    if !hasRequestedNotificationPermission {
      hasRequestedNotificationPermission = true
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.userInfo = ["paneID": paneID]
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  func handleCommandFinished(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int,
      let exitCode = notification.userInfo?["exitCode"] as? Int16,
      let duration = notification.userInfo?["duration"] as? UInt64
    else { return }
    for session in store.sessions {
      for tab in session.tabs {
        if let pane = tab.panes.first(where: { $0.id == paneID }) {
          pane.lastCommandResult = MyttyPane.CommandResult(
            exitCode: exitCode, duration: duration)
          if exitCode != 0,
            !(store.activeSession?.id == session.id && session.activeTab?.id == tab.id)
          {
            tab.hasFailedCommand = true
          }
          return
        }
      }
    }
  }

  func handleProgressReport(_ notification: Notification) {
    guard let paneID = notification.userInfo?["paneID"] as? Int,
      let stateRaw = notification.userInfo?["state"] as? UInt32,
      let progress = notification.userInfo?["progress"] as? Int8
    else { return }
    for session in store.sessions {
      for tab in session.tabs {
        if let pane = tab.panes.first(where: { $0.id == paneID }) {
          pane.progressExpiryTask?.cancel()
          if stateRaw == GHOSTTY_PROGRESS_STATE_REMOVE.rawValue {
            pane.progressState = nil
            return
          }
          switch stateRaw {
          case GHOSTTY_PROGRESS_STATE_SET.rawValue:
            pane.progressState = .set(progress: progress)
          case GHOSTTY_PROGRESS_STATE_ERROR.rawValue:
            pane.progressState = .error
          case GHOSTTY_PROGRESS_STATE_INDETERMINATE.rawValue:
            pane.progressState = .indeterminate
          case GHOSTTY_PROGRESS_STATE_PAUSE.rawValue:
            pane.progressState = .pause
          default:
            return
          }
          let task = DispatchWorkItem { [weak pane] in
            pane?.progressState = nil
          }
          pane.progressExpiryTask = task
          DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: task)
          return
        }
      }
    }
  }

  func handleColorChange(_ notification: Notification) {
    guard let kind = notification.userInfo?["kind"] as? String,
      kind == "background",
      let r = notification.userInfo?["r"] as? CGFloat,
      let g = notification.userInfo?["g"] as? CGFloat,
      let b = notification.userInfo?["b"] as? CGFloat,
      let paneID = notification.userInfo?["paneID"] as? Int,
      let match = store.pane(byId: paneID)
    else { return }
    match.pane.surfaceView.layer?.backgroundColor = NSColor(
      red: r, green: g, blue: b, alpha: 1.0
    ).cgColor
  }

  // MARK: - Key Sequence

  func activateKeySequenceManager() {
    let config = MyttyConfig.load().keybindingStore
    keySequenceManager.activate(
      trie: config.sequenceTrie,
      timeout: config.sequenceTimeout,
      dispatch: { [self] action in
        dispatchSequenceAction(action)
      },
      surfaceForUnconsumed: { [self] in
        store.activeSession?.activeTab?.activePane?.surfaceView.surface
      },
      showWhichKey: { [self] bindings in
        whichKeyManager.showContinuations(bindings)
      },
      hideWhichKey: { [self] in
        whichKeyManager.hideContinuations()
      }
    )
  }

  func dispatchSequenceAction(_ action: String) {
    guard let commands = terminalCommands else { return }
    switch action {
    case "new-tab": commands.newTab()
    case "close-tab": commands.closeTab()
    case "next-tab": commands.nextTab()
    case "previous-tab": commands.prevTab()
    case "next-session": commands.nextSession()
    case "previous-session": commands.prevSession()
    case "split-horizontal": commands.splitHorizontal()
    case "split-vertical": commands.splitVertical()
    case "close-pane": commands.closePane()
    case "window-mode": commands.windowMode()
    case "copy-mode": commands.copyMode()
    case "which-key": commands.whichKey()
    case "session-manager": commands.sessionManager()
    case "toggle-sidebar": commands.toggleSidebar()
    case "toggle-tab-bar": commands.toggleTabBar()
    case "previous-prompt": commands.jumpToPreviousPrompt()
    case "next-prompt": commands.jumpToNextPrompt()
    case "navigate-left": handleNavigate(.left)
    case "navigate-down": handleNavigate(.down)
    case "navigate-up": handleNavigate(.up)
    case "navigate-right": handleNavigate(.right)
    default:
      if action.hasPrefix("focus-tab-"),
        let n = Int(action.dropFirst("focus-tab-".count))
      {
        commands.focusTab(n - 1)
      }
    }
  }

  func handleNavigate(_ direction: NavigationDirection) {
    guard let tab = store.activeSession?.activeTab,
      let pane = tab.activePane,
      let target = tab.layout.adjacentPane(from: pane, direction: direction)
    else { return }
    tab.activePane = target
    DispatchQueue.main.async {
      target.surfaceView.window?.makeFirstResponder(target.surfaceView)
    }
  }

  // MARK: - Key Monitors

  func handleSessionManagerKeyDown(_ event: NSEvent, vm: SessionManagerViewModel) -> NSEvent? {
    switch event.keyName {
    case "escape":
      showingSessionManager = false
      return nil
    case "return":
      vm.confirmSelection(modifierFlags: event.modifierFlags)
      showingSessionManager = false
      return nil
    case "up":
      vm.moveUp()
      return nil
    case "down":
      vm.moveDown()
      return nil
    default:
      break
    }

    if event.modifierFlags.contains(.control) {
      if event.charactersIgnoringModifiers == "j" {
        vm.moveDown()
        return nil
      } else if event.charactersIgnoringModifiers == "k" {
        vm.moveUp()
        return nil
      }
    }

    return event
  }

  func jumpToPrompt(direction: Int) {
    guard let surface = store.activeSession?.activeTab?.activePane?.surfaceView.surface else {
      return
    }
    let action = "jump_to_prompt:\(direction)"
    _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
  }
}
