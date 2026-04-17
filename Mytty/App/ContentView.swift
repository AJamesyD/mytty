import AppKit
import GhosttyKit
import MyttyShared
import SwiftUI

struct ContentView: View {
  var store: SessionStore
  @SceneStorage("sidebarWidth") var sidebarWidth: Double = 220
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @State var showingSessionManager = false
  @State var sessionManagerVM: SessionManagerViewModel?
  @State var eventMonitor: Any?
  @State var windowModeManager = WindowModeManager()
  @State var copyModeManager = CopyModeManager()
  @State var whichKeyManager = WhichKeyManager()
  @State var keySequenceManager = KeySequenceManager()
  @State var panelState = PanelState()
  @State var configWatcher = ConfigWatcher()
  @State var terminalCommands: TerminalCommands?

  var body: some View {
    contentWithNotifications
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
          Text("Press ⌘J to open or create a session")
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
      applyConfig(MyttyConfig.load())
      configWatcher.start()
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
      configWatcher.stop()
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
