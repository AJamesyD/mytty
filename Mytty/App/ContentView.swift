import AppKit
import GhosttyKit
import MyttyShared
import SwiftUI
import UserNotifications

// TODO: extract @State properties into an @Observable ContentViewState model.
// Handlers were consolidated from ContentView+Handlers.swift (see 4ffbf4b) to
// enable private_swiftui_state. Extracting state into a model would allow
// re-splitting handlers into a separate file with proper private access,
// but it touches every handler method signature. Do as a standalone refactor.
struct ContentView: View {
  private static let sessionManagerShortcutLabel: String = {
    let trigger = MyttyConfig.load().keybindingStore.trigger(for: "session-manager", in: .global)
    return trigger?.displayLabel ?? "⌘N"
  }()

  var store: SessionStore
  @SceneStorage("sidebarWidth") private var sidebarWidth: Double = 220
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingSessionManager = false
  @State private var sessionManagerVM: SessionManagerViewModel?
  @State private var windowModeManager = WindowModeManager()
  @State private var copyModeManager = CopyModeManager()
  @State private var whichKeyManager = WhichKeyManager()
  @State private var keySequenceManager = KeySequenceManager()
  @State private var panelState = PanelState()
  @State private var configWatcher = ConfigWatcher()
  @State private var ghosttyConfigWatcher = GhosttyConfigWatcher()
  @State private var terminalCommands: TerminalCommands?

  var body: some View {
    contentWithNotifications
      .ignoresSafeArea(
        .container,
        edges: GhosttyAppManager.shared.windowConfig.titlebarStyle == "hidden" ? .top : []
      )
      .focusedSceneValue(\.terminalCommands, terminalCommands)
  }

  private func makeTerminalCommands() -> TerminalCommands {
    TerminalCommands(
      newTab: { store.activeSession?.addTab() },
      closeTab: { handleCloseTab() },
      nextTab: { store.activeSession?.nextTab() },
      prevTab: { store.activeSession?.prevTab() },
      focusTab: { index in
        guard let session = store.activeSession,
          index < session.tabs.count
        else { return }
        session.activeTab = session.tabs[index]
      },
      nextSession: { store.nextSession() },
      prevSession: { store.prevSession() },
      splitHorizontal: { splitPane(direction: .horizontal) },
      splitVertical: { splitPane(direction: .vertical) },
      closePane: { handleClosePane() },
      windowMode: { handleWindowMode() },
      copyMode: { handleCopyMode() },
      whichKey: { handleWhichKey() },
      sessionManager: { showingSessionManager = true },
      togglePopup: { name in handlePopupToggle(name: name) },
      toggleSidebar: { handleToggleSidebar() },
      toggleTabBar: { handleToggleTabBar() },
      jumpToPreviousPrompt: { jumpToPrompt(direction: -1) },
      jumpToNextPrompt: { jumpToPrompt(direction: 1) }
    )
  }

  var sidebarPanel: some View {
    SidebarView(
      store: store,
      width: Binding(
        get: { CGFloat(sidebarWidth) },
        set: { sidebarWidth = Double($0) }
      ),
      showTree: panelState.sidebarShowTree,
      position: panelState.sidebarPosition)
  }

  var terminalArea: some View {
    Group {
      if let session = store.activeSession,
        let tab = session.activeTab
      {
        ZStack(alignment: .top) {
          VStack(spacing: 0) {
            if panelState.tabBarIsPinned(tabCount: session.tabs.count) {
              TabBarView(session: session)
              Divider()
            }
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

          if !panelState.tabBarIsPinned(tabCount: session.tabs.count)
            && panelState.shouldShowTabBar(tabCount: session.tabs.count)
          {
            VStack(spacing: 0) {
              TabBarView(session: session)
                .background(.ultraThinMaterial)
                .shadow(color: MyttyTheme.panelOverlayShadow, radius: 0, x: 0, y: 1)
                .onHover { hovering in
                  panelState.isTabBarHovered = hovering
                  if !hovering && !panelState.isTabBarTempPinned {
                    panelState.isTabBarRevealed = false
                  }
                }
              Spacer()
            }
            .transition(reduceMotion ? .opacity : .move(edge: .top))
          }

          if panelState.tabBarMode == .autoHide
            && (!panelState.hideTabBarWhenSingleTab || session.tabs.count > 1)
          {
            VStack {
              EdgeTriggerView(
                dwellDuration: panelState.dwellDuration,
                dismissDelay: panelState.dismissDelay,
                onReveal: {
                  guard !isAnyModalActive else { return }
                  panelState.isTabBarRevealed = true
                },
                onDismiss: {
                  guard !panelState.isTabBarTempPinned else { return }
                  guard !panelState.isTabBarHovered else { return }
                  panelState.isTabBarRevealed = false
                }
              )
              .frame(height: 20)
              .frame(maxWidth: .infinity)
              Spacer()
            }
          }

          if panelState.showHints && panelState.tabBarMode == .autoHide
            && !panelState.isTabBarRevealed
            && (!panelState.hideTabBarWhenSingleTab || session.tabs.count > 1)
          {
            VStack {
              RoundedRectangle(cornerRadius: 1)
                .fill(MyttyTheme.autoHideHint)
                .frame(width: 28, height: 3)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
              Spacer()
            }
          }
        }
        .animation(
          reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 1.0),
          value: panelState.isTabBarRevealed
        )
      } else {
        VStack(spacing: 12) {
          Text("No active session")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("Press \(Self.sessionManagerShortcutLabel) to open or create a session")
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder
  var mainContent: some View {
    let isRight = panelState.sidebarPosition == .right
    ZStack(alignment: isRight ? .trailing : .leading) {
      HStack(spacing: 0) {
        if panelState.sidebarIsPinned && !isRight {
          sidebarPanel
          Rectangle()
            .fill(MyttyTheme.sidebarDivider)
            .frame(width: 1)
        }
        terminalArea
        if panelState.sidebarIsPinned && isRight {
          Rectangle()
            .fill(MyttyTheme.sidebarDivider)
            .frame(width: 1)
          sidebarPanel
        }
      }

      if !panelState.sidebarIsPinned {
        if panelState.isSidebarRevealed {
          sidebarPanel
            .background(.ultraThinMaterial)
            .shadow(color: MyttyTheme.panelOverlayShadow, radius: 2, x: isRight ? -1 : 1, y: 0)
            .onHover { hovering in
              panelState.isSidebarHovered = hovering
              if !hovering && !panelState.isSidebarTempPinned {
                panelState.isSidebarRevealed = false
              }
            }
            .transition(reduceMotion ? .opacity : .move(edge: isRight ? .trailing : .leading))
        }

        if panelState.sidebarMode == .autoHide {
          HStack(spacing: 0) {
            if isRight { Spacer() }
            EdgeTriggerView(
              dwellDuration: panelState.dwellDuration,
              dismissDelay: panelState.dismissDelay,
              onReveal: {
                guard !isAnyModalActive else { return }
                panelState.isSidebarRevealed = true
              },
              onDismiss: {
                guard !panelState.isSidebarTempPinned else { return }
                guard !panelState.isSidebarHovered else { return }
                panelState.isSidebarRevealed = false
              }
            )
            .frame(width: 20)
            .frame(maxHeight: .infinity)
            if !isRight { Spacer() }
          }
        }

        if panelState.showHints && panelState.sidebarMode == .autoHide
          && !panelState.isSidebarRevealed
        {
          HStack(spacing: 0) {
            if isRight { Spacer() }
            RoundedRectangle(cornerRadius: 1)
              .fill(MyttyTheme.autoHideHint)
              .frame(width: 3, height: 28)
              .allowsHitTesting(false)
            if !isRight { Spacer() }
          }
          .frame(maxHeight: .infinity)
        }
      }
    }
    .animation(
      reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 1.0),
      value: panelState.isSidebarRevealed
    )
    .onAppear {
      terminalCommands = makeTerminalCommands()
      let initialConfig = MyttyConfig.load()
      applyConfig(initialConfig)
      if let error = initialConfig.parseError {
        print("[Mytty] Config parse error: \(error)")
      }
      configWatcher.start()
      ghosttyConfigWatcher.start()
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
      TerminalSurfaceView.modalKeyHandler = { [self] event in
        if showingSessionManager, let vm = sessionManagerVM {
          if handleSessionManagerKeyDown(event, vm: vm) == nil { return nil }
        }
        if whichKeyManager.handleKeyDown(event) == nil { return nil }
        if copyModeManager.handleKeyDown(event) == nil { return nil }
        if windowModeManager.handleKeyDown(event) == nil { return nil }
        return event
      }
    }
    .onDisappear {
      configWatcher.stop()
      ghosttyConfigWatcher.stop()
      DispatchQueue.main.async { [store] in
        for tracked in store.trackedWindows where !tracked.window.isVisible {
          store.unregisterWindow(tracked.window)
        }
      }
      TerminalSurfaceView.modalKeyHandler = nil
      windowModeManager.deactivate()
      copyModeManager.deactivate()
      store.activeSession?.activeTab?.windowModeState = .inactive
      showingSessionManager = false
    }
  }

  @ViewBuilder
  var sessionManagerOverlay: some View {
    if showingSessionManager, let vm = sessionManagerVM {
      MyttyTheme.modalBackdrop
        .ignoresSafeArea()
        .onTapGesture { showingSessionManager = false }

      SessionManagerView(
        vm: vm,
        isPresented: $showingSessionManager
      )
    }
  }

  @ViewBuilder
  var popupOverlay: some View {
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

  func applyConfig(_ config: MyttyConfig) {
    let positionChanged = panelState.sidebarPosition != config.sidebarPosition
    panelState.sidebarMode = config.sidebarMode
    panelState.sidebarPosition = config.sidebarPosition
    panelState.sidebarShowTree = config.sidebarShowTree
    panelState.tabBarMode = config.tabBarMode
    panelState.hideTabBarWhenSingleTab = config.hideTabBarWhenSingleTab
    panelState.dwellDuration = Double(config.autoHideDwellMs) / 1000.0
    panelState.dismissDelay = Double(config.autoHideDismissDelayMs) / 1000.0
    panelState.showHints = config.autoHideShowHints
    if positionChanged {
      panelState.isSidebarRevealed = false
      panelState.isSidebarTempPinned = false
    }
  }
}

@MainActor
private var hasRequestedNotificationPermission = false

// MARK: - Notifications & Handlers

extension ContentView {
  private var isAnyModalActive: Bool {
    showingSessionManager
      || windowModeManager.isActive
      || copyModeManager.isActive
      || whichKeyManager.isActive
  }

  var contentWithNotifications: some View {
    contentWithGhosttyActions
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
  }

  var contentWithGhosttyActions: some View {
    contentWithOverlays
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyNewTab)) { notification in
        handleGhosttyNewTab(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyNewSplit)) { notification in
        handleGhosttyNewSplit(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyCloseTab)) { notification in
        handleGhosttyCloseTab(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyGotoSplit)) { notification in
        handleGhosttyGotoSplit(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyResizeSplit)) { notification in
        handleGhosttyResizeSplit(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyEqualizeSplits)) {
        notification in
        handleGhosttyEqualizeSplits(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyToggleSplitZoom)) {
        notification in
        handleGhosttyToggleSplitZoom(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyGotoTab)) { notification in
        handleGhosttyGotoTab(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyMoveTab)) { notification in
        handleGhosttyMoveTab(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyToggleQuickTerminal)) { _ in
        handleGhosttyToggleQuickTerminal()
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyChildExited)) { notification in
        handleGhosttyChildExited(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .ghosttyKeyTable)) { notification in
        handleKeyTable(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .myttyConfigDidChange)) { _ in
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
    guard let p = notification.payload(SetTitlePayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    let title = p.title
    match.pane.processTitle = title
    match.tab.titleDebounceTask?.cancel()
    let tab = match.tab
    let task = DispatchWorkItem { [weak tab] in
      tab?.title = title
    }
    match.tab.titleDebounceTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: task)
  }

  func handleRingBell(_ notification: Notification) {
    guard let p = notification.payload(PanePayload.self), let paneID = p.paneID else { return }
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
    guard let p = notification.payload(PanePayload.self), let paneID = p.paneID else { return }
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
    if let match = store.pane(byId: paneID) {
      closePaneInTab(match.pane, tab: match.tab, session: match.session)
    }
  }

  func handlePwd(_ notification: Notification) {
    guard let p = notification.payload(PwdPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.pane.workingDirectory = URL(fileURLWithPath: p.pwd)
  }

  func handleSetTabTitle(_ notification: Notification) {
    guard let p = notification.payload(SetTitlePayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.tab.tabTitle = p.title
  }

  func handleDesktopNotification(_ notification: Notification) {
    guard let p = notification.payload(DesktopNotificationPayload.self), let paneID = p.paneID
    else { return }
    let title = p.title
    let body = p.body
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
    guard let p = notification.payload(CommandFinishedPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.pane.lastCommandResult = MyttyPane.CommandResult(
      exitCode: p.exitCode, duration: p.duration)
    if p.exitCode != 0,
      !(store.activeSession?.id == match.session.id && match.session.activeTab?.id == match.tab.id)
    {
      match.tab.hasFailedCommand = true
    }
  }

  func handleProgressReport(_ notification: Notification) {
    guard let p = notification.payload(ProgressReportPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    let pane = match.pane
    pane.progressExpiryTask?.cancel()
    if case .remove = p.state {
      pane.progressState = nil
      return
    }
    switch p.state {
    case .set:
      pane.progressState = .set(progress: p.progress)
    case .error:
      pane.progressState = .error
    case .indeterminate:
      pane.progressState = .indeterminate
    case .pause:
      pane.progressState = .pause
    case .remove:
      break
    }
    let task = DispatchWorkItem { [weak pane] in
      pane?.progressState = nil
    }
    pane.progressExpiryTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: task)
  }

  func handleColorChange(_ notification: Notification) {
    guard let payload = notification.payload(ColorChangePayload.self),
      payload.kind == .background,
      let paneID = payload.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.pane.surfaceView.layer?.backgroundColor =
      NSColor(
        red: payload.r, green: payload.g, blue: payload.b, alpha: 1.0
      ).cgColor
  }

  // MARK: - Ghostty Action Handlers

  func handleGhosttyNewTab(_ notification: Notification) {
    guard let p = notification.payload(PanePayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.session.addTab()
  }

  func handleGhosttyNewSplit(_ notification: Notification) {
    guard let p = notification.payload(NewSplitPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.tab.splitActivePane(direction: p.direction)
  }

  func handleGhosttyCloseTab(_ notification: Notification) {
    guard let p = notification.payload(PanePayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.session.closeTab(match.tab)
    if match.session.tabs.isEmpty {
      store.closeSession(match.session)
    }
  }

  func handleGhosttyGotoSplit(_ notification: Notification) {
    guard let p = notification.payload(GotoSplitPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    let target: MyttyPane
    switch p.direction {
    case .previous, .next:
      let panes = match.tab.layout.leaves
      guard let idx = panes.firstIndex(where: { $0.id == match.pane.id }) else { return }
      let next =
        if case .next = p.direction {
          panes.index(after: idx) % panes.count
        } else {
          (idx - 1 + panes.count) % panes.count
        }
      target = panes[next]
    case .spatial(let navDirection):
      guard let adj = match.tab.layout.adjacentPane(from: match.pane, direction: navDirection)
      else { return }
      target = adj
    }
    match.tab.activePane = target
    DispatchQueue.main.async {
      target.surfaceView.window?.makeFirstResponder(target.surfaceView)
    }
  }

  func handleGhosttyResizeSplit(_ notification: Notification) {
    guard let p = notification.payload(ResizeSplitPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    let splitDir: SplitDirection
    let sign: CGFloat
    switch p.direction {
    case .up:
      splitDir = .vertical
      sign = -1
    case .down:
      splitDir = .vertical
      sign = 1
    case .left:
      splitDir = .horizontal
      sign = -1
    case .right:
      splitDir = .horizontal
      sign = 1
    }
    let delta = sign * CGFloat(p.amount) / 100.0
    match.tab.layout.resizeSplit(containing: match.pane, delta: delta, along: splitDir)
  }

  func handleGhosttyEqualizeSplits(_ notification: Notification) {
    guard let p = notification.payload(PanePayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    match.tab.layout.equalize()
  }

  func handleGhosttyToggleSplitZoom(_ notification: Notification) {
    guard let p = notification.payload(PanePayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    if match.tab.zoomedPane != nil {
      match.tab.zoomedPane = nil
    } else {
      match.tab.zoomedPane = match.pane
    }
  }

  func handleGhosttyGotoTab(_ notification: Notification) {
    guard let p = notification.payload(GotoTabPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    let tabRaw = p.tab
    let session = match.session
    switch tabRaw {
    case -1: session.prevTab()
    case -2: session.nextTab()
    case -3:
      if let last = session.tabs.last { session.activeTab = last }
    default:
      let index = Int(tabRaw)
      if index >= 0, index < session.tabs.count {
        session.activeTab = session.tabs[index]
      }
    }
  }

  func handleGhosttyMoveTab(_ notification: Notification) {
    guard let p = notification.payload(MoveTabPayload.self), let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    guard let currentIndex = match.session.tabs.firstIndex(where: { $0.id == match.tab.id }) else {
      return
    }
    let destination = currentIndex + p.amount
    guard destination >= 0, destination < match.session.tabs.count else { return }
    match.session.moveTab(withID: match.tab.id, toIndex: destination)
  }

  func handleGhosttyToggleQuickTerminal() {
    NotificationCenter.default.post(
      name: .myttyDropdownHotkeyPressed,
      object: nil
    )
  }

  func handleGhosttyChildExited(_ notification: Notification) {
    guard let p = notification.payload(ChildExitedPayload.self), let paneID = p.paneID else {
      return
    }
    // TODO(phase-7): show child exited overlay on the pane
    _ = store.pane(byId: paneID)
  }

  func handleKeyTable(_ notification: Notification) {
    guard let p = notification.payload(KeyTablePayload.self),
      let paneID = p.paneID,
      let match = store.pane(byId: paneID)
    else { return }
    switch p.action {
    case .activate(let name):
      match.pane.activeKeyTables.append(name)
    case .deactivate:
      _ = match.pane.activeKeyTables.popLast()
    case .deactivateAll:
      match.pane.activeKeyTables.removeAll()
    }
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
      if event.keyName == "j" {
        vm.moveDown()
        return nil
      }
      if event.keyName == "k" {
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
