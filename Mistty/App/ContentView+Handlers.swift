import AppKit
import GhosttyKit
import MisttyShared
import SwiftUI

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
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyCloseSurface)) { notification in
        handleCloseSurface(notification)
      }
  }

  var contentWithOverlays: some View {
    mainContent
      .overlay { sessionManagerOverlay }
      .overlay { popupOverlay }
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
          installKeyMonitor(vm: vm)
        } else {
          removeKeyMonitor()
          sessionManagerVM = nil
        }
      }
      .paneNavigation(store: store, showingSessionManager: $showingSessionManager)
  }

  func splitPane(direction: SplitDirection) {
    guard let session = store.activeSession,
      let tab = session.activeTab
    else { return }
    if let sshCommand = session.sshCommand,
      !NSEvent.modifierFlags.contains(.option)
    {
      let pane = MisttyPane(id: tab.paneIDGenerator())
      pane.directory = session.directory
      pane.command = sshCommand
      pane.useCommandField = false
      tab.addExistingPane(pane, direction: direction)
    } else {
      tab.splitActivePane(direction: direction)
    }
  }

  func closePane(_ pane: MisttyPane) {
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

  func closePaneInTab(_ pane: MisttyPane, tab: MisttyTab, session: MisttySession) {
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
    let config = MisttyConfig.load()
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
      whichKeyManager.activate(
        bindings: WhichKeyManager.defaultBindings(store: store, commands: terminalCommands))
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
          tab.title = title
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

  // MARK: - Key Monitors

  func installKeyMonitor(vm: SessionManagerViewModel) {
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      switch event.keyCode {
      case 53:  // Escape
        showingSessionManager = false
        return nil
      case 36:  // Return
        vm.confirmSelection(modifierFlags: event.modifierFlags)
        showingSessionManager = false
        return nil
      case 126:  // Up arrow
        vm.moveUp()
        return nil
      case 125:  // Down arrow
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
  }

  func removeKeyMonitor() {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
  }
}
