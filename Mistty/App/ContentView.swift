import AppKit
import GhosttyKit
import MisttyShared
import SwiftUI

struct ContentView: View {
  var store: SessionStore
  @AppStorage("sidebarVisible") var sidebarVisible = true
  @SceneStorage("sidebarWidth") var sidebarWidth: Double = 220
  @State var showingSessionManager = false
  @State private var sessionManagerVM: SessionManagerViewModel?
  @State private var eventMonitor: Any?
  @State private var windowModeManager = WindowModeManager()
  @State private var copyModeManager = CopyModeManager()
  @State private var whichKeyManager = WhichKeyManager()

  var body: some View {
    contentWithNotifications
      .onReceive(NotificationCenter.default.publisher(for: .misttyFocusTabByIndex)) {
        notification in
        guard let session = store.activeSession,
          let index = notification.userInfo?["index"] as? Int,
          index < session.tabs.count
        else { return }
        session.activeTab = session.tabs[index]
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyNextTab)) { _ in
        store.activeSession?.nextTab()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyPrevTab)) { _ in
        store.activeSession?.prevTab()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyNextSession)) { _ in
        store.nextSession()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyPrevSession)) { _ in
        store.prevSession()
      }
  }

  private var contentWithNotifications: some View {
    contentWithOverlays
      .onReceive(NotificationCenter.default.publisher(for: .misttyPopupToggle)) { notification in
        handlePopupToggle(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyClosePane)) { _ in
        handleClosePane()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyWindowMode)) { _ in
        handleWindowMode()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyCopyMode)) { _ in
        handleCopyMode()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyWhichKey)) { _ in
        if whichKeyManager.isActive {
          whichKeyManager.deactivate()
        } else {
          // NOTE: only one keyboard mode can be active at a time. Each mode
          // installs its own NSEvent monitor; competing monitors cause
          // unpredictable event routing.
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
            bindings: WhichKeyManager.defaultBindings(store: store))
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttyCloseTab)) { _ in
        handleCloseTab()
      }
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

  private var contentWithOverlays: some View {
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
      .onReceive(NotificationCenter.default.publisher(for: .misttyNewTab)) { _ in
        store.activeSession?.addTab()
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttySplitHorizontal)) { _ in
        splitPane(direction: .horizontal)
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttySplitVertical)) { _ in
        splitPane(direction: .vertical)
      }
      .onReceive(NotificationCenter.default.publisher(for: .misttySessionManager)) { _ in
        showingSessionManager = true
      }
      .paneNavigation(store: store, showingSessionManager: $showingSessionManager)
  }

  @ViewBuilder
  private var mainContent: some View {
    HStack(spacing: 0) {
      if sidebarVisible {
        SidebarView(
          store: store,
          width: Binding(
            get: { CGFloat(sidebarWidth) },
            set: { sidebarWidth = Double($0) }
          ))
        Divider()
      }

      Group {
        if let session = store.activeSession,
          let tab = session.activeTab
        {
          VStack(spacing: 0) {
            TabBarView(session: session)
            Divider()
            let joinPickTabNames = session.tabs
              .filter { $0.id != tab.id }
              .map { $0.displayTitle }
            ZStack(alignment: .bottom) {
              if let zoomedPane = tab.zoomedPane {
                PaneView(
                  pane: zoomedPane,
                  isActive: true,
                  isWindowModeActive: tab.isWindowModeActive,
                  isZoomed: true,
                  copyModeState: (zoomedPane.id == tab.activePane?.id) ? tab.copyModeState : nil,
                  windowModeState: tab.windowModeState,
                  joinPickTabNames: joinPickTabNames,
                  paneCount: tab.panes.count,
                  onClose: { closePane(zoomedPane) },
                  onSelect: {}
                )
              } else {
                PaneLayoutView(
                  node: tab.layout.root,
                  activePane: tab.activePane,
                  isWindowModeActive: tab.isWindowModeActive,
                  copyModeState: tab.copyModeState,
                  copyModePaneID: tab.activePane?.id,
                  windowModeState: tab.windowModeState,
                  joinPickTabNames: joinPickTabNames,
                  paneCount: tab.panes.count,
                  onClosePane: { pane in closePane(pane) },
                  onSelectPane: { pane in tab.activePane = pane }
                )
              }
              if tab.windowModeState != .inactive {
                WindowModeHints(
                  isJoinPick: tab.windowModeState == .joinPick,
                  tabNames: joinPickTabNames,
                  paneCount: tab.panes.count
                )
                .padding(6)
                .allowsHitTesting(false)
              }
            }
          }
        } else {
          VStack(spacing: 12) {
            Text("No active session")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text("Press ⌘J to open or create a session")
              .foregroundStyle(.tertiary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .onAppear {
      windowModeManager.onNeedExitCopyMode = { copyModeManager.exit() }
      copyModeManager.onNeedExitWindowMode = {
        store.activeSession?.activeTab?.windowModeState = .inactive
        windowModeManager.deactivate()
      }
      DispatchQueue.main.async {
        if let window = NSApplication.shared.keyWindow {
          _ = store.registerWindow(window)
        }
      }
    }
    .onDisappear {
      DispatchQueue.main.async { [store] in
        for tracked in store.trackedWindows where !tracked.window.isVisible {
          store.unregisterWindow(tracked.window)
        }
      }
      removeKeyMonitor()
      windowModeManager.deactivate()
      copyModeManager.deactivate()
      store.activeSession?.activeTab?.windowModeState = .inactive
      showingSessionManager = false
    }
  }

  @ViewBuilder
  private var sessionManagerOverlay: some View {
    if showingSessionManager, let vm = sessionManagerVM {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
        .onTapGesture { showingSessionManager = false }

      SessionManagerView(
        vm: vm,
        isPresented: $showingSessionManager
      )
    }
  }

  @ViewBuilder
  private var popupOverlay: some View {
    if let session = store.activeSession,
      let popup = session.activePopup,
      popup.isVisible
    {
      GeometryReader { geometry in
        PopupOverlayView(
          popup: popup,
          onDismiss: {
            session.hideActivePopup()
            returnFocusToActivePane()
          },
          onClose: {
            session.closePopup(popup)
            returnFocusToActivePane()
          }
        )
        .frame(
          width: geometry.size.width * popup.definition.width,
          height: geometry.size.height * popup.definition.height
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private func splitPane(direction: SplitDirection) {
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

  private func closePane(_ pane: MisttyPane) {
    guard let session = store.activeSession,
      let tab = session.activeTab
    else { return }
    closePaneInTab(pane, tab: tab, session: session)
  }

  private func returnFocusToActivePane() {
    if let pane = store.activeSession?.activeTab?.activePane {
      DispatchQueue.main.async {
        pane.surfaceView.window?.makeFirstResponder(pane.surfaceView)
      }
    }
  }

  private func closePaneInTab(_ pane: MisttyPane, tab: MisttyTab, session: MisttySession) {
    tab.closePane(pane)
    if tab.panes.isEmpty {
      session.closeTab(tab)
      if session.tabs.isEmpty {
        store.closeSession(session)
      }
    }
  }

  // MARK: - Notification Handlers

  private func handlePopupToggle(_ notification: Notification) {
    guard let session = store.activeSession,
      let name = notification.userInfo?["name"] as? String
    else { return }
    let config = MisttyConfig.load()
    guard let definition = config.popups.first(where: { $0.name == name }) else { return }
    session.togglePopup(definition: definition)
    if let popup = session.activePopup, popup.isVisible {
      DispatchQueue.main.async {
        popup.pane.surfaceView.window?.makeFirstResponder(popup.pane.surfaceView)
      }
    }
  }

  private func handleClosePane() {
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

  private func handleWindowMode() {
    guard let tab = store.activeSession?.activeTab else { return }
    if tab.isWindowModeActive {
      tab.windowModeState = .inactive
      windowModeManager.deactivate()
    } else {
      tab.windowModeState = .normal
      windowModeManager.activate(store: store)
    }
  }

  private func handleCopyMode() {
    guard let tab = store.activeSession?.activeTab else { return }
    if tab.isCopyModeActive {
      copyModeManager.exit()
    } else {
      copyModeManager.enter(store: store)
    }
  }

  private func handleCloseTab() {
    guard let session = store.activeSession,
      let tab = session.activeTab
    else { return }
    session.closeTab(tab)
    if session.tabs.isEmpty {
      store.closeSession(session)
    }
  }

  private func handleSetTitle(_ notification: Notification) {
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

  private func handleRingBell(_ notification: Notification) {
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

  private func handleCloseSurface(_ notification: Notification) {
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

  private func installKeyMonitor(vm: SessionManagerViewModel) {
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

  private func removeKeyMonitor() {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
  }
}
